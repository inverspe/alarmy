import SwiftUI
import UIKit
import AlarmyCore

enum MissionResult {
    case matched
    case miss(distance: Float, threshold: Float, switchedTo: RegisteredObject?)
}

/// Owns the app state and drives the alarm: starts sessions when an alarm is due,
/// keeps audio and backups in sync, and enforces the edit lock.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var state: AppState
    /// Trusted "now", refreshed every tick, so views that depend on time update.
    @Published private(set) var now = Date()

    let audio = AlarmAudio()
    let volume = VolumeEnforcer()
    let notifications = NotificationScheduler()
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
    /// Constant for the life of the process; a different value means the phone rebooted.
    private let bootID = AppModel.bootSessionID()

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        store = StateStore(fileURL: support.appendingPathComponent("state.json"))
        photos = ObjectPhotoStore(directory: support.appendingPathComponent("objects"))
        state = store.load()

        notifications.isRingingInForeground = { [weak self] in
            UIApplication.shared.applicationState == .active && (self?.state.ringSession?.isRinging ?? false)
        }
        notifications.onTap = { [weak self] in self?.tick() }
        UNUserNotificationCenter.current().delegate = notifications

        let notifications = self.notifications
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        DiagnosticLog.shared.add("launch build \(build)")
        Task { await notifications.logPermissions("at launch") }

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
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
                                              isEarlyClear: false, objectIDs: usableObjectIDs(in: s), now: t, using: &rng)
        }

        if var session = s.ringSession {
            session.tick(now: t)
            if session.phase == .finished {
                finish(session, in: &s, at: t)
            } else {
                s.ringSession = session
            }
        }

        if s != state { commit(s) }
        syncAudio()

        let ringing = state.ringSession?.isRinging ?? false
        if planDirty || (ringing && t.timeIntervalSince(lastPlanAt) >= 60) || t.timeIntervalSince(lastPlanAt) >= 900 {
            replan(at: t)
        }
    }

    // MARK: Actions

    /// Applies a change unless the edit lock is held, or the change would leave an
    /// alarm enabled with no objects to photograph.
    @discardableResult
    func update(_ change: (inout AppState) -> Void) -> Bool {
        guard !isLocked else { return false }
        var s = state
        change(&s)
        if s.objects.isEmpty && s.alarms.contains(where: \.isEnabled) { return false }
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
                                          isEarlyClear: true, objectIDs: usableObjectIDs(in: s), now: trustedNow(), using: &rng)
        commit(s)
        tick()
    }

    /// Backing out of an early clear is fine: nothing is ringing yet.
    func cancelEarlyClear() {
        guard let session = state.ringSession, session.isEarlyClear else { return }
        var s = state
        s.ringSession = nil
        commit(s)
    }

    func submitMissionPhoto(_ image: UIImage) async -> MissionResult? {
        guard let session = state.ringSession, session.phase == .mission, let object = currentObject else { return nil }
        let references = object.referencePhotoIDs.compactMap { photos.featurePrint($0) }
        let strictness = state.strictness
        let matcher = self.matcher
        let evaluation = await Task.detached { () -> (matched: Bool, distance: Float, threshold: Float) in
            guard let cg = image.normalized(maxSide: 1280).cgImage,
                  let result = try? matcher.evaluate(cg, references: references, strictness: strictness) else {
                return (false, .infinity, PhotoMatcher.threshold(for: strictness))
            }
            return result
        }.value

        // The session may have moved on while matching (e.g. fire time passed for an early clear).
        guard var current = state.ringSession, current.occurrence == session.occurrence, current.phase == .mission else {
            return nil
        }
        var s = state
        if evaluation.matched {
            current.recordMatch(now: trustedNow())
            s.ringSession = current
            commit(s)
            tick()
            return .matched
        }
        let before = current.currentObjectID
        current.recordMiss(availableObjectIDs: usableObjectIDs(in: s), using: &rng)
        s.ringSession = current
        commit(s)
        let switched = current.currentObjectID != before ? state.objects.first { $0.id == current.currentObjectID } : nil
        return .miss(distance: evaluation.distance, threshold: evaluation.threshold, switchedTo: switched)
    }

    func addObject(name: String, photos images: [UIImage]) throws -> Bool {
        guard !isLocked else { return false }
        let ids = try images.map { try photos.add($0) }
        let added = update { $0.objects.append(RegisteredObject(name: name, referencePhotoIDs: ids)) }
        if !added { ids.forEach(photos.delete) }
        return added
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

    /// Only acts on transitions, so it never fights audio started elsewhere (e.g. sound previews).
    private func syncAudio() {
        let ringing = state.ringSession?.isRinging ?? false
        if ringing != modelRinging {
            modelRinging = ringing
            if ringing {
                audio.startRinging(sessionOccurrence?.alarm.sound ?? .klaxon)
                volume.start()
            } else {
                audio.stopRinging()
                volume.stop()
                notifications.clearDelivered()
            }
            UIApplication.shared.isIdleTimerDisabled = ringing
        }
        let armed = state.alarms.contains(where: \.isEnabled)
        if armed != modelKeepAlive {
            modelKeepAlive = armed
            armed ? audio.startKeepAlive() : audio.stopKeepAlive()
        }
        audio.ensureRunning()
    }

    private func replan(at t: Date) {
        let upcoming = Schedule.upcoming(state.alarms, after: t, calendar: calendar, limit: 3)
        let plan = BackupPlanner.plan(upcoming: upcoming, completed: Set(state.completed.keys),
                                      session: state.ringSession, now: t)
        notifications.apply(plan, calendar: calendar)
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
