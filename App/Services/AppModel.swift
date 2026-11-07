import SwiftUI
import UIKit
import AlarmyCore

enum MissionResult {
    case matched
    case miss(distance: Float, limit: Float, switchedTo: RegisteredObject?)
}

/// Owns the app state and drives the alarm: starts sessions when an alarm is due,
/// keeps audio and backups in sync, and enforces the edit lock.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var state: AppState
    /// Trusted "now", refreshed every tick, so views that depend on time update.
    @Published private(set) var now = Date()
    /// A mission screen is up. The sound stops while it is, unless the alarm says otherwise.
    @Published private(set) var missionOpen = false
    @Published private(set) var missionSecondsLeft = TimeInterval(MissionAttempt.defaultLimit)
    /// The last mission closed because nothing was happening.
    @Published private(set) var missionTimedOut = false
    /// The owner switched the sound on or off with the mission open. Lasts until the ring ends.
    @Published private var missionQuietChoice: Bool?

    let audio = AlarmAudio()
    let volume = VolumeEnforcer()
    let notifications = NotificationScheduler()
    private let voice = VoiceAnnouncer()
    private let weather = WeatherService()
    private let location = LocationFinder()
    let photos: ObjectPhotoStore

    private let store: StateStore
    private let matcher = PhotoMatcher()
    private var rng = SystemRandomNumberGenerator()
    private var calendar: Calendar { .current }
    private var timer: Timer?
    private var lastPlanAt = Date.distantPast
    private var planDirty = true
    private var modelRinging = false
    private var modelKeepAlive = false
    private var missionAttempt: MissionAttempt?
    private var stuck = MissionStuckTracker()
    private var lastMissionTick: TimeInterval = 0
    private var lastVibration: TimeInterval = 0
    private var voiceCycle: VoiceCycle?
    private var lastWeatherCheck = Date.distantPast
    /// Constant for the life of the process; a different value means the phone rebooted.
    private let bootID = AppModel.bootSessionID()

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        #if DEBUG
        UITestHarness.seedIfRequested(support: support)
        #endif
        store = StateStore(fileURL: support.appendingPathComponent("state.json"))
        photos = ObjectPhotoStore(directory: support.appendingPathComponent("objects"))
        state = store.load()

        let photoStore = photos
        let photoIDs = state.objects.flatMap(\.referencePhotoIDs)
        DispatchQueue.global(qos: .utility).async { photoStore.refreshPrints(photoIDs) }

        notifications.isRingingInForeground = { [weak self] in
            UIApplication.shared.applicationState == .active && (self?.state.ringSession?.isRinging ?? false)
        }
        notifications.onTap = { [weak self] in self?.tick() }
        voice.onStarted = { [weak self] in self?.voiceCycle?.speechStarted() }
        voice.onFinished = { [weak self] in
            self?.voiceCycle?.speechFinished(now: Self.monotonic())
            self?.syncAudio()
        }
        location.onPlace = { [weak self] place in self?.setWeatherPlace(place) }
        UNUserNotificationCenter.current().delegate = notifications

        let notifications = self.notifications
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        DiagnosticLog.shared.add("launch build \(build)")
        DiagnosticLog.shared.add(PlatformProbe.launchServicesRecord())
        DiagnosticLog.shared.add(PlatformProbe.runtimeEntitlement(PlatformProbe.criticalAlerts))
        BackupSounds.installIfNeeded()
        Task { [weak self] in
            await notifications.logPermissions("at launch")
            self?.planDirty = true
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            // Must run before the process exits, so it can't wait for a Task.
            MainActor.assumeIsolated { self?.appWillTerminate() }
        }
        // Backups are tied to the clock on screen, so they get redone when it changes.
        let clockChanges: [Notification.Name] = [UIApplication.significantTimeChangeNotification, .NSSystemClockDidChange, .NSSystemTimeZoneDidChange]
        for name in clockChanges {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.planDirty = true
                    self?.tick()
                }
            }
        }
        tick()
    }

    // MARK: Derived state

    var sessionOccurrence: Occurrence? {
        guard let session = state.ringSession, session.phase != .finished else { return nil }
        let alarm = state.alarms.first { $0.id == session.occurrence.alarmID }
            ?? Alarm(id: session.occurrence.alarmID, hour: 0, minute: 0)
        return Occurrence(alarm: alarm, fireDate: session.occurrence.fireDate)
    }

    var lockHolder: Occurrence? {
        EditLock.lockedUntilDone(state.alarms, completed: state.completed, session: sessionOccurrence,
                                 now: now, calendar: calendar)
    }

    var isLocked: Bool { lockHolder != nil }

    var earlyClearable: Occurrence? {
        guard state.ringSession == nil else { return nil }
        return EditLock.earlyClearable(state.alarms, completed: state.completed, now: now, calendar: calendar)
    }

    var currentObject: RegisteredObject? {
        guard let id = state.ringSession?.currentObjectID else { return nil }
        return state.objects.first { $0.id == id }
    }

    func trustedNow() -> Date {
        TrustedClock.now(wall: Date(), monotonic: Self.monotonic(), bootID: bootID, anchor: state.clockAnchor)
    }

    /// Re-attaches the volume enforcer (it needs a key window, which may not exist
    /// yet on a cold launch from a backup tap), then ticks.
    func sceneBecameActive() {
        if modelRinging { volume.start() }
        if state.alarms.contains(where: \.voiceWeather) { location.find(asking: false) }
        tick()
    }

    /// Nobody is looking at the mission any more, so the sound has to come back.
    func sceneWentToBackground() {
        guard missionOpen else { return }
        closeMission()
        tick()
    }

    // MARK: Tick

    func tick() {
        let wall = Date()
        let monotonic = Self.monotonic()
        let t = TrustedClock.now(wall: wall, monotonic: monotonic, bootID: bootID, anchor: state.clockAnchor)
        now = t
        var s = state

        // Re-anchor at most once a minute (so state isn't rewritten every second),
        // but immediately after a reboot.
        let anchor = TrustedClock.refreshedAnchor(s.clockAnchor, wall: wall, monotonic: monotonic, bootID: bootID)
        if let old = s.clockAnchor, old.bootID == bootID, anchor.wall.timeIntervalSince(old.wall) < 60 {
            // keep
        } else {
            s.clockAnchor = anchor
        }

        // An early clear that wasn't finished by fire time turns into the real alarm.
        if let session = s.ringSession, session.isEarlyClear, t >= session.occurrence.fireDate {
            s.ringSession = nil
        }

        if s.ringSession == nil,
           let due = Schedule.activeOccurrence(s.alarms, completed: s.completed, now: t, calendar: calendar) {
            s.ringSession = RingSession.start(occurrence: due.key, ringAfterMinutes: due.alarm.ringAfterMinutes,
                                              isEarlyClear: false, objectIDs: usableObjectIDs(in: s),
                                              missions: due.alarm.missions.runnable(barcodes: s.barcodes),
                                              wakeCheckMinutes: due.alarm.wakeCheckMinutes, gentleSeconds: due.alarm.gentleSeconds,
                                              snoozeMinutes: due.alarm.snoozeOn ? due.alarm.snoozeMinutes : 0, snoozeLimit: due.alarm.snoozeLimit,
                                              now: t, using: &rng)
        }

        if var session = s.ringSession {
            // Finding usable objects reads files, so it only happens when a missed check needs a new one.
            var probe = session
            probe.tick(now: t)
            let startingOver = probe.missedWakeChecks > session.missedWakeChecks
            session.tick(now: t, availableObjectIDs: startingOver ? usableObjectIDs(in: s) : [], using: &rng)
            if session.phase == .finished {
                finish(session, in: &s, at: t)
            } else {
                s.ringSession = session
            }
        }

        if s != state { commit(s) }
        syncMission()
        syncVoice(at: t)
        syncAudio()
        refreshWeather(at: t)

        let ringing = state.ringSession?.isRinging ?? false
        if planDirty || (ringing && t.timeIntervalSince(lastPlanAt) >= 60) || t.timeIntervalSince(lastPlanAt) >= 900 {
            replan(at: t, wall: wall)
        }
    }

    // MARK: Actions

    /// Applies a change unless the edit lock is held, or the change would leave an
    /// alarm with a photo mission enabled and no objects to photograph.
    @discardableResult
    func update(_ change: (inout AppState) -> Void) -> Bool {
        guard !isLocked else { return false }
        var s = state
        change(&s)
        if s.objects.isEmpty && s.alarms.contains(where: { $0.isEnabled && $0.needsObjects }) { return false }
        let barcodes = s.barcodes
        let missingBarcode = s.alarms.contains { alarm in
            alarm.isEnabled && alarm.missions.runnable(barcodes: barcodes).count != alarm.missions.count
        }
        if missingBarcode { return false }
        s.completed = Completion.suppressFired(old: state.alarms, new: s.alarms, completed: s.completed,
                                               now: trustedNow(), calendar: calendar)
        commit(s)
        tick()
        return true
    }

    func completeOnboarding() {
        var s = state
        s.onboardingDone = true
        commit(s)
    }

    /// Re-shows the setup guide. Nothing in it can weaken the alarm, so the lock doesn't apply.
    func restartOnboarding() {
        var s = state
        s.onboardingDone = false
        commit(s)
    }

    func startEarlyClear() {
        guard let occurrence = earlyClearable else { return }
        var s = state
        s.ringSession = RingSession.start(occurrence: occurrence.key, ringAfterMinutes: occurrence.alarm.ringAfterMinutes,
                                          isEarlyClear: true, objectIDs: usableObjectIDs(in: s), missions: occurrence.alarm.missions.runnable(barcodes: s.barcodes),
                                          now: trustedNow(), using: &rng)
        commit(s)
        tick()
    }

    /// Backing out of an early clear is fine: nothing is ringing yet.
    func cancelEarlyClear() {
        guard let session = state.ringSession, session.isEarlyClear else { return }
        closeMission()
        stuck = MissionStuckTracker()
        var s = state
        s.ringSession = nil
        commit(s)
    }

    /// Starts the current mission. The chain then runs on from one mission to the next.
    func openMission() {
        guard state.ringSession?.phase == .mission else { return }
        let time = Self.monotonic()
        missionAttempt = MissionAttempt(now: time, limit: state.missionTimeLimit)
        missionSecondsLeft = missionTimeLimit
        lastMissionTick = time
        missionTimedOut = false
        missionOpen = true
        DiagnosticLog.shared.add("mission opened")
        syncAudio()
    }

    /// Anything the owner does in a mission starts its time again.
    func noteMissionInput() {
        missionAttempt?.input(at: Self.monotonic())
        missionSecondsLeft = missionTimeLimit
    }

    var missionTimeLimit: TimeInterval { TimeInterval(state.missionTimeLimit) }

    /// A moment's pause, then a buzz, then on to whatever is next.
    func finishMissionSoon(_ kind: MissionKind) {
        noteMissionInput()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            Haptics.success()
            self?.completeMission(kind)
        }
    }

    var canSnooze: Bool { state.ringSession?.canSnooze(now: now) ?? false }

    func snooze() {
        guard var session = state.ringSession, session.canSnooze(now: trustedNow()) else { return }
        session.snooze(now: trustedNow())
        DiagnosticLog.shared.add("snoozed, \(session.snoozeCount) so far")
        var s = state
        s.ringSession = session
        commit(s)
        tick()
    }

    /// Rather than wait, the owner gets on with it: it rings again and the mission starts.
    func endSnooze() {
        guard var session = state.ringSession else { return }
        session.endSnooze(now: trustedNow())
        var s = state
        s.ringSession = session
        commit(s)
        tick()
        openMission()
    }

    func barcodeName(_ code: String?) -> String {
        state.barcodes.first { $0.code == code }?.name ?? "your barcode"
    }

    func addBarcode(name: String, code: String) -> Bool {
        update { $0.barcodes.append(RegisteredBarcode(name: name, code: code)) }
    }

    /// Refused while an alarm that's on still needs it.
    func deleteBarcode(_ id: UUID) -> Bool {
        update { $0.barcodes.removeAll { $0.id == id } }
    }

    func addSentence(_ text: String) -> Bool {
        guard let sentence = Sentences.cleaned(text), state.customSentences.count < Sentences.maxCustom else { return false }
        return update { $0.customSentences.append(sentence) }
    }

    func removeSentence(at index: Int) {
        guard state.customSentences.indices.contains(index) else { return }
        update { $0.customSentences.remove(at: index) }
    }

    func setMissionTimeLimit(_ seconds: Int) {
        update { $0.missionTimeLimit = seconds }
    }

    /// Called when an alarm has the weather turned on, which is the moment to ask for location access.
    func askForWeatherLocation() {
        location.find(asking: true)
    }

    /// The sensor counted something, so it's working.
    func noteMissionProgress(_ kind: MissionKind, count: Int) {
        noteMissionInput()
        stuck.counted(count, for: kind)
    }

    func isMissionStuck(_ kind: MissionKind) -> Bool {
        stuck.isStuck(kind)
    }

    var isMissionSoundOn: Bool { !missionQuiet }

    func toggleMissionSound() {
        missionQuietChoice = !missionQuiet
        noteMissionInput()
        syncAudio()
    }

    /// A steps, squats, shake or math mission was finished. Moves on to the next one.
    func completeMission(_ kind: MissionKind) {
        guard var session = state.ringSession, session.currentMission?.kind == kind else { return }
        noteMissionInput()
        session.completeMission(now: trustedNow())
        var s = state
        s.ringSession = session
        commit(s)
        tick()
    }

    /// The owner answered the wake-up check, which ends the alarm for today.
    func confirmAwake() {
        guard var session = state.ringSession else { return }
        session.confirmAwake()
        var s = state
        s.ringSession = session
        commit(s)
        notifications.clearDelivered()
        tick()
    }

    func submitMissionPhoto(_ image: UIImage) async -> MissionResult? {
        guard let session = state.ringSession, session.currentMission?.kind == .photo, let object = currentObject else { return nil }
        noteMissionInput()
        let references = object.referencePhotoIDs.compactMap { photos.featurePrint($0) }
        let misses = state.photoMisses
        let matcher = self.matcher
        let evaluation = await Task.detached { () -> PhotoMatcher.MatchResult in
            guard let cg = image.normalized(maxSide: 1280).cgImage,
                  let result = try? matcher.evaluate(cg, references: references, misses: misses) else {
                return PhotoMatcher.MatchResult(matched: false, distance: .infinity, limit: PhotoMatcher.limit(misses: misses))
            }
            return result
        }.value
        noteMissionInput()
        DiagnosticLog.shared.add(String(format: "mission %@: %@ score %.2f (needs under %.2f, %d misses)",
                                        object.name, evaluation.matched ? "match" : "miss", evaluation.distance,
                                        evaluation.limit, misses))

        // The session may have moved on while matching (e.g. fire time passed for an early clear).
        guard var current = state.ringSession, current.occurrence == session.occurrence, current.currentMission?.kind == .photo else {
            return nil
        }
        var s = state
        if evaluation.matched {
            s.photoMisses = 0
            current.completeMission(now: trustedNow())
            s.ringSession = current
            commit(s)
            tick()
            return .matched
        }
        let before = current.currentObjectID
        s.photoMisses += 1
        current.recordMiss(availableObjectIDs: usableObjectIDs(in: s), using: &rng)
        s.ringSession = current
        commit(s)
        let switched = current.currentObjectID != before ? state.objects.first { $0.id == current.currentObjectID } : nil
        return .miss(distance: evaluation.distance, limit: evaluation.limit, switchedTo: switched)
    }

    func addObject(name: String, photos images: [UIImage]) throws -> Bool {
        guard !isLocked else { return false }
        let ids = try images.map { try photos.add($0) }
        let added = update { $0.objects.append(RegisteredObject(name: name, referencePhotoIDs: ids)) }
        if !added { ids.forEach(photos.delete) }
        return added
    }

    /// The existing object these photos look most like, when close enough to pass for it
    /// on the first try. Look-alike objects make the morning photo unreliable.
    func lookalike(for images: [UIImage]) -> RegisteredObject? {
        let prints = images.compactMap { $0.normalized(maxSide: 1280).cgImage }.compactMap { try? matcher.featurePrint(for: $0) }
        let limit = PhotoMatcher.limit(misses: 0)
        var best: (object: RegisteredObject, distance: Float)?
        for object in state.objects {
            let references = object.referencePhotoIDs.compactMap { photos.featurePrint($0) }
            for print in prints {
                guard let d = try? matcher.distance(fromPrint: print, toReferences: references),
                      d < limit, d < (best?.distance ?? .infinity) else { continue }
                best = (object, d)
            }
        }
        if let best { DiagnosticLog.shared.add(String(format: "new object resembles %@ (%.2f)", best.object.name, best.distance)) }
        return best?.object
    }

    func deleteObject(_ id: UUID) -> Bool {
        guard let object = state.objects.first(where: { $0.id == id }) else { return false }
        let removed = update { $0.objects.removeAll { $0.id == id } }
        if removed { object.referencePhotoIDs.forEach(photos.delete) }
        return removed
    }

    /// Plays `sound` for 3 seconds (alarm editor). Never interferes with a real ring.
    func previewSound(_ sound: AlarmSound) {
        guard !modelRinging else { return }
        audio.startRinging(sound)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, !self.modelRinging else { return }
            self.audio.stopRinging()
        }
    }

    func requestNotificationPermission() async -> Bool {
        await notifications.requestAuthorization()
    }

    // MARK: Private

    private func finish(_ session: RingSession, in s: inout AppState, at t: Date) {
        stuck = MissionStuckTracker()
        s.completed = Completion.markFinished(session.occurrence, at: t, alarms: s.alarms,
                                              completed: s.completed, calendar: calendar)
        if let i = s.alarms.firstIndex(where: { $0.id == session.occurrence.alarmID }), s.alarms[i].repeatDays.isEmpty {
            s.alarms[i].isEnabled = false
        }
        s.ringSession = nil
    }

    private func usableObjectIDs(in s: AppState) -> [UUID] {
        s.objects.filter { object in object.referencePhotoIDs.contains { photos.featurePrint($0) != nil } }.map(\.id)
    }

    /// Closes a mission that has ended or run out of time.
    private func syncMission() {
        guard missionOpen else { return }
        guard let session = state.ringSession, session.phase == .mission, missionAttempt != nil else {
            closeMission()
            return
        }
        let time = Self.monotonic()
        if let kind = session.currentMission?.kind, kind.canGetStuck {
            let wasStuck = stuck.isStuck(kind)
            stuck.add(time - lastMissionTick, to: kind)
            // A full 20 seconds to read the way out that has just appeared.
            if !wasStuck && stuck.isStuck(kind) { missionAttempt?.input(at: time) }
        }
        lastMissionTick = time
        guard let attempt = missionAttempt else { return }
        missionSecondsLeft = attempt.remaining(at: time)
        guard attempt.timedOut(at: time) else { return }

        DiagnosticLog.shared.add("mission ran out of time")
        closeMission()
        missionTimedOut = true
        var restarted = session
        restarted.restartMissions()
        var s = state
        s.ringSession = restarted
        commit(s)
    }

    private func closeMission() {
        missionOpen = false
        missionAttempt = nil
    }

    /// When to speak is decided here. Saying nothing is fine, but the sound always has to come back.
    private func syncVoice(at time: Date) {
        guard state.ringSession?.isRinging == true, let alarm = sessionOccurrence?.alarm, alarm.voiceIsOn else {
            if voiceCycle != nil {
                voice.stop()
                voiceCycle = nil
            }
            return
        }
        let seconds = Self.monotonic()
        var cycle = voiceCycle ?? VoiceCycle(now: seconds)
        if missionOpen {
            if !cycle.isPaused {
                cycle.pause()
                voice.stop()
            }
        } else if cycle.isPaused {
            cycle.resume(now: seconds)
        }
        switch cycle.tick(now: seconds) {
        case .speak:
            let lines = VoiceScript.lines(sayTime: alarm.voiceTime, weather: alarm.voiceWeather ? weather.spokenLine(now: time) : nil,
                                          label: alarm.voiceLabel ? alarm.label : nil, first: cycle.announcements == 1, date: time)
            DiagnosticLog.shared.add("speaking \(lines.count) lines")
            voice.speak(lines)
        case .gaveUp:
            DiagnosticLog.shared.add("speech never finished, sound back")
            voice.stop()
        case .none:
            break
        }
        voiceCycle = cycle
    }

    /// Fetched shortly before an alarm that reads out the weather, and during its ring.
    private func refreshWeather(at t: Date) {
        guard t.timeIntervalSince(lastWeatherCheck) >= 15, let place = state.weatherPlace else { return }
        lastWeatherCheck = t
        let wanting = state.alarms.filter(\.voiceWeather)
        guard !wanting.isEmpty else { return }
        let ringing = state.ringSession?.isRinging == true && sessionOccurrence?.alarm.voiceWeather == true
        let soon = Schedule.upcoming(wanting, after: t, calendar: calendar, limit: 1).first
            .map { $0.fireDate.timeIntervalSince(t) <= WeatherReport.fetchAhead } ?? false
        if ringing || soon { weather.refreshIfNeeded(place: place, now: t) }
    }

    private func setWeatherPlace(_ place: WeatherPlace) {
        guard state.weatherPlace != place else { return }
        var s = state
        s.weatherPlace = place
        commit(s)
    }

    /// True while the sound should be held back for an open mission.
    private var missionQuiet: Bool {
        guard missionOpen, state.ringSession?.isRinging == true else { return false }
        return missionQuietChoice ?? sessionOccurrence?.alarm.quietDuringMissions ?? true
    }

    /// Only acts on transitions, so it never fights audio started elsewhere (e.g. sound previews).
    private func syncAudio() {
        let ringing = state.ringSession?.isRinging ?? false
        if ringing != modelRinging {
            modelRinging = ringing
            if ringing {
                audio.startRinging(sessionOccurrence?.alarm.sound ?? .klaxon, gentle: gentleProgress())
                volume.start()
            } else {
                audio.stopRinging()
                volume.stop()
                notifications.clearDelivered()
                missionQuietChoice = nil
            }
        }
        audio.setQuiet(missionQuiet || (voiceCycle?.holdsSoundBack ?? false))
        if ringing, !missionOpen, sessionOccurrence?.alarm.vibrate ?? true {
            let time = Self.monotonic()
            if time - lastVibration >= 0.9 {
                lastVibration = time
                Haptics.vibrate()
            }
        }
        var answering = false
        switch state.ringSession?.phase {
        case .wakeCheckPrompt, .snoozed: answering = true
        default: break
        }
        UIApplication.shared.isIdleTimerDisabled = ringing || answering
        let armed = state.alarms.contains(where: \.isEnabled)
        if armed != modelKeepAlive {
            modelKeepAlive = armed
            armed ? audio.startKeepAlive() : audio.stopKeepAlive()
        }
        audio.ensureRunning()
    }

    /// Counted from the alarm time, so reopening the app partway through doesn't start the ramp over.
    private func gentleProgress() -> (elapsed: TimeInterval, duration: TimeInterval)? {
        guard let session = state.ringSession, let end = session.gentleEndsAt else { return nil }
        let start = session.ringStart
        return (now.timeIntervalSince(start), end.timeIntervalSince(start))
    }

    private func appWillTerminate() {
        let active = state.ringSession.map { !$0.isEarlyClear && $0.phase != .finished } ?? false
        guard active || state.alarms.contains(where: \.isEnabled) else { return }
        DiagnosticLog.shared.add("app closed, active session=\(active)")
        notifications.postAppClosedNotice(ringing: active)
        Thread.sleep(forTimeInterval: BackupPlanner.appClosedHold)
    }

    private func replan(at t: Date, wall: Date) {
        let upcoming = Schedule.upcoming(state.alarms, after: t, calendar: calendar, limit: 3)
        let plan = BackupPlanner.plan(upcoming: upcoming, completed: Set(state.completed.keys),
                                      session: state.ringSession, now: t)
        let alarms = state.alarms
        notifications.apply(plan, soundFor: { key in alarms.first { $0.id == key.alarmID }?.sound ?? .klaxon }, calendar: calendar, wall: wall, trusted: t)
        lastPlanAt = t
        planDirty = false
    }

    private func commit(_ s: AppState) {
        state = s
        try? store.save(s)
        planDirty = true
    }

    private static func monotonic() -> TimeInterval {
        Double(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000
    }

    /// `kern.bootsessionuuid` — changes on every boot and, unlike `kern.boottime`,
    /// doesn't move when the clock is set by hand.
    private static func bootSessionID() -> String? {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.bootsessionuuid", &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}
