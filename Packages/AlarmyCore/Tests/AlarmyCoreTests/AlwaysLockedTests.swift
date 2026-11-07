import XCTest
@testable import AlarmyCore

// An alarm that can't be turned off: locked between rings too, and its missions open it up.
// One 6:30 daily alarm (America/New_York) unless a test says otherwise.
final class AlwaysLockedTests: XCTestCase {
    private func locked(_ h: Int = 6, _ m: Int = 30, days: Set<Weekday> = Set(Weekday.allCases),
                        on: Bool = true, always: Bool = true, lockHours: Int = 8) -> Alarm {
        Alarm(hour: h, minute: m, repeatDays: days, isEnabled: on, lockHours: lockHours,
              missions: [MissionStep(kind: .math, amount: 1)], alwaysLocked: always)
    }

    private func standing(_ alarms: [Alarm], now: String, unlockedUntil: String? = nil) -> Occurrence? {
        EditLock.standingLock(alarms, unlockedUntil: unlockedUntil.map { date($0) }, now: date(now), calendar: cal())
    }

    private func unlockSession(for occurrence: Occurrence, at now: String) -> RingSession {
        var g = SeededGenerator(seed: 1)
        return RingSession.start(occurrence: occurrence.key, ringAfterMinutes: 10, isEarlyClear: false, isUnlock: true,
                                 objectIDs: [], missions: occurrence.alarm.missions, snoozeMinutes: 5,
                                 now: date(now), using: &g)
    }

    // MARK: The lock

    func testLockedBetweenRings() {
        let alarm = locked()
        XCTAssertNil(EditLock.lockedUntilDone([alarm], completed: [:], session: nil, now: date("2026-10-21 12:00"), calendar: cal()),
                     "The normal window shouldn't hold at midday")
        let holder = standing([alarm], now: "2026-10-21 12:00")
        XCTAssertEqual(holder?.fireDate, date("2026-10-22 06:30"))
        XCTAssertEqual(holder?.alarm.id, alarm.id)
    }

    func testOnlyWhenTheOptionIsOn() {
        XCTAssertNil(standing([locked(always: false)], now: "2026-10-21 12:00"))
    }

    func testAnAlarmThatIsOffHoldsNothing() {
        XCTAssertNil(standing([locked(on: false)], now: "2026-10-21 12:00"))
    }

    func testOneTimeAlarmHoldsUntilItHasRung() {
        let once = locked(days: [])
        XCTAssertEqual(standing([once], now: "2026-10-21 12:00")?.fireDate, date("2026-10-22 06:30"))
    }

    func testTheSoonestLockedAlarmHolds() {
        let late = locked(9, 0)
        let early = locked(7, 0)
        let free = locked(5, 0, always: false)
        XCTAssertEqual(standing([late, free, early], now: "2026-10-21 12:00")?.alarm.id, early.id)
    }

    func testUnlockOpensForTenMinutesThenLocksAgain() {
        let alarm = locked()
        XCTAssertNil(standing([alarm], now: "2026-10-21 12:05", unlockedUntil: "2026-10-21 12:10"))
        XCTAssertNil(standing([alarm], now: "2026-10-21 12:09", unlockedUntil: "2026-10-21 12:10"))
        XCTAssertNotNil(standing([alarm], now: "2026-10-21 12:10", unlockedUntil: "2026-10-21 12:10"))
        XCTAssertNotNil(standing([alarm], now: "2026-10-21 12:30", unlockedUntil: "2026-10-21 12:10"))
        XCTAssertEqual(EditLock.unlockMinutes, 10)
    }

    func testClockTurnedBackCannotBringBackAnUnlock() {
        let alarm = locked()
        // Earned at 12:00, good until 12:10. Turning the clock back before 12:00 doesn't reopen it.
        XCTAssertNotNil(standing([alarm], now: "2026-10-21 11:59", unlockedUntil: "2026-10-21 12:10"))
        XCTAssertNotNil(standing([alarm], now: "2026-10-01 12:05", unlockedUntil: "2026-10-21 12:10"))
        XCTAssertNil(standing([alarm], now: "2026-10-21 12:00", unlockedUntil: "2026-10-21 12:10"))
    }

    func testRunOutOrRebootedUnlockIsForgotten() {
        var state = AppState()
        state.unlockedUntil = date("2026-10-21 12:10")
        state.dropStaleUnlock(now: date("2026-10-21 12:05"), sameBoot: true)
        XCTAssertEqual(state.unlockedUntil, date("2026-10-21 12:10"), "Still good")

        state.dropStaleUnlock(now: date("2026-10-21 12:05"), sameBoot: false)
        XCTAssertNil(state.unlockedUntil, "After a reboot the clock can't be checked")

        state.unlockedUntil = date("2026-10-21 12:10")
        state.dropStaleUnlock(now: date("2026-10-21 12:10"), sameBoot: true)
        XCTAssertNil(state.unlockedUntil, "Run out")
    }

    func testSameBootNeedsAnEarlierReading() {
        let anchor = ClockAnchor(wall: date("2026-10-21 12:00"), monotonic: 1000, bootID: "a")
        XCTAssertTrue(TrustedClock.sameBoot(anchor, monotonic: 1600, bootID: "a"))
        XCTAssertFalse(TrustedClock.sameBoot(anchor, monotonic: 1600, bootID: "b"))
        XCTAssertFalse(TrustedClock.sameBoot(nil, monotonic: 1600, bootID: "a"))
    }

    func testUnlockIsNeverFree() {
        let sums = MissionStep(kind: .math)
        XCTAssertEqual(EditLock.unlockMissions([MissionStep.photo], hasObjects: true), [MissionStep.photo])
        XCTAssertEqual(EditLock.unlockMissions([MissionStep.photo], hasObjects: false), [sums])
        XCTAssertEqual(EditLock.unlockMissions([MissionStep.photo, MissionStep(kind: .steps)], hasObjects: false), [MissionStep(kind: .steps)])
        XCTAssertEqual(EditLock.unlockMissions([], hasObjects: true), [sums])
    }

    func testPhotosDuringAnUnlockDontMakeTheRingEasier() {
        let occurrence = Occurrence(alarm: locked(), fireDate: date("2026-10-22 06:30"))
        var state = AppState()
        state.photoMisses = 2
        var unlock = unlockSession(for: occurrence, at: "2026-10-21 12:00")
        XCTAssertEqual(state.photoMissCount(for: unlock), 0)
        for _ in 0..<3 { state.recordPhoto(matched: false, in: &unlock) }
        XCTAssertEqual(state.photoMisses, 2, "The alarm's own count is untouched")
        XCTAssertEqual(unlock.unlockPhotoMisses, 3)
        XCTAssertEqual(state.photoMissCount(for: unlock), 3, "The unlock still gets easier as it goes")
        state.recordPhoto(matched: true, in: &unlock)
        XCTAssertEqual(state.photoMisses, 2)

        var g = SeededGenerator(seed: 1)
        var ring = RingSession.start(occurrence: occurrence.key, ringAfterMinutes: 10, isEarlyClear: false,
                                     objectIDs: [], missions: [.photo], now: date("2026-10-22 06:30"), using: &g)
        XCTAssertEqual(state.photoMissCount(for: ring), 2)
        state.recordPhoto(matched: false, in: &ring)
        XCTAssertEqual(state.photoMisses, 3)
        state.recordPhoto(matched: true, in: &ring)
        XCTAssertEqual(state.photoMisses, 0)
    }

    // MARK: The unlock session

    func testUnlockRingsNothingAndCanBeBackedOutOf() {
        let occurrence = Occurrence(alarm: locked(), fireDate: date("2026-10-22 06:30"))
        let session = unlockSession(for: occurrence, at: "2026-10-21 12:00")
        XCTAssertTrue(session.isUnlock)
        XCTAssertTrue(session.isEarlyClear, "An unlock is a session before the alarm")
        XCTAssertFalse(session.isRinging)
        XCTAssertFalse(session.canSnooze(now: date("2026-10-21 12:00")))
        XCTAssertEqual(session.currentMission?.kind, .math)
    }

    func testUnlockFinishesAfterTheLastMission() {
        let occurrence = Occurrence(alarm: locked(), fireDate: date("2026-10-22 06:30"))
        var session = unlockSession(for: occurrence, at: "2026-10-21 12:00")
        session.completeMission(now: date("2026-10-21 12:01"))
        XCTAssertEqual(session.phase, .finished)
    }

    func testFinishingAnUnlockLeavesTheAlarmToRing() {
        let once = locked(days: [])
        let occurrence = Occurrence(alarm: once, fireDate: date("2026-10-22 06:30"))
        var state = AppState()
        state.alarms = [once]
        var session = unlockSession(for: occurrence, at: "2026-10-21 12:00")
        session.completeMission(now: date("2026-10-21 12:01"))
        state.ringSession = session

        state.finish(session, at: date("2026-10-21 12:01"), calendar: cal())

        XCTAssertNil(state.ringSession)
        XCTAssertTrue(state.completed.isEmpty, "Unlocking must not count as the morning's alarm")
        XCTAssertTrue(state.alarms[0].isEnabled, "Unlocking must not turn a one-time alarm off")
        XCTAssertEqual(state.unlockedUntil, date("2026-10-21 12:11"))
        XCTAssertEqual(Schedule.activeOccurrence(state.alarms, completed: state.completed,
                                                 now: date("2026-10-22 06:30"), calendar: cal())?.key, occurrence.key)
        XCTAssertNil(EditLock.standingLock(state.alarms, unlockedUntil: state.unlockedUntil, now: date("2026-10-21 12:05"), calendar: cal()))
    }

    func testFinishingARingStillCountsAsDone() {
        let once = locked(days: [])
        let occurrence = Occurrence(alarm: once, fireDate: date("2026-10-22 06:30"))
        var g = SeededGenerator(seed: 1)
        var state = AppState()
        state.alarms = [once]
        let session = RingSession.start(occurrence: occurrence.key, ringAfterMinutes: 10, isEarlyClear: false,
                                        objectIDs: [], missions: once.missions, now: date("2026-10-22 06:30"), using: &g)
        XCTAssertFalse(session.isUnlock)

        state.finish(session, at: date("2026-10-22 06:45"), calendar: cal())

        XCTAssertEqual(state.completed[occurrence.key], date("2026-10-22 06:45"))
        XCTAssertFalse(state.alarms[0].isEnabled)
        XCTAssertNil(state.unlockedUntil)
        XCTAssertNil(EditLock.standingLock(state.alarms, unlockedUntil: nil, now: date("2026-10-22 06:46"), calendar: cal()),
                     "A one-time alarm that's done stops holding the lock")
    }

    // MARK: Nothing gets in the way of a ring

    func testUnlockGivesWayToAnotherAlarm() {
        let lockedAlarm = locked(22, 0)
        let other = locked(12, 30, always: false)
        var state = AppState()
        state.alarms = [lockedAlarm, other]
        state.ringSession = unlockSession(for: Occurrence(alarm: lockedAlarm, fireDate: date("2026-10-21 22:00")), at: "2026-10-21 12:25")

        state.yieldToDueAlarm(now: date("2026-10-21 12:29"), calendar: cal())
        XCTAssertNotNil(state.ringSession, "Nothing is due yet")
        state.yieldToDueAlarm(now: date("2026-10-21 12:30"), calendar: cal())
        XCTAssertNil(state.ringSession, "The 12:30 alarm has to be able to ring")
    }

    func testUnlockGivesWayAtItsOwnAlarmTime() {
        let alarm = locked(lockHours: 0)
        var state = AppState()
        state.alarms = [alarm]
        state.ringSession = unlockSession(for: Occurrence(alarm: alarm, fireDate: date("2026-10-21 06:30")), at: "2026-10-21 06:29")
        state.yieldToDueAlarm(now: date("2026-10-21 06:30"), calendar: cal())
        XCTAssertNil(state.ringSession)
    }

    func testEarlyClearStillEndsAtItsOwnTime() {
        let alarm = locked(always: false)
        var g = SeededGenerator(seed: 1)
        var state = AppState()
        state.alarms = [alarm]
        state.ringSession = RingSession.start(occurrence: OccurrenceKey(alarmID: alarm.id, fireDate: date("2026-10-21 06:30")),
                                              ringAfterMinutes: 10, isEarlyClear: true, objectIDs: [], missions: alarm.missions,
                                              now: date("2026-10-21 06:10"), using: &g)
        state.yieldToDueAlarm(now: date("2026-10-21 06:29"), calendar: cal())
        XCTAssertNotNil(state.ringSession)
        state.yieldToDueAlarm(now: date("2026-10-21 06:30"), calendar: cal())
        XCTAssertNil(state.ringSession)
    }

    func testARingIsNeverDropped() {
        let alarm = locked(always: false)
        var g = SeededGenerator(seed: 1)
        var state = AppState()
        state.alarms = [alarm]
        state.ringSession = RingSession.start(occurrence: OccurrenceKey(alarmID: alarm.id, fireDate: date("2026-10-21 06:30")),
                                              ringAfterMinutes: 10, isEarlyClear: false, objectIDs: [], missions: alarm.missions,
                                              now: date("2026-10-21 06:30"), using: &g)
        state.yieldToDueAlarm(now: date("2026-10-21 06:31"), calendar: cal())
        XCTAssertNotNil(state.ringSession)
    }

    // MARK: Saved files

    func testOlderFilesLoadWithTheOptionOff() throws {
        let data = try JSONEncoder().encode(locked())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["alwaysLocked"] as? Bool, true)
        object.removeValue(forKey: "alwaysLocked")
        let old = try JSONDecoder().decode(Alarm.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(old.alwaysLocked)

        let state = try JSONDecoder().decode(AppState.self, from: Data(#"{"alarms":[]}"#.utf8))
        XCTAssertNil(state.unlockedUntil)
    }

    func testUnlockSurvivesARestart() throws {
        let occurrence = Occurrence(alarm: locked(), fireDate: date("2026-10-22 06:30"))
        var state = AppState()
        state.alarms = [occurrence.alarm]
        state.ringSession = unlockSession(for: occurrence, at: "2026-10-21 12:00")
        state.unlockedUntil = date("2026-10-20 09:00")
        let reloaded = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(reloaded, state)
        XCTAssertEqual(reloaded.ringSession?.isUnlock, true)
        XCTAssertEqual(reloaded.alarms.first?.alwaysLocked, true)

        var g = SeededGenerator(seed: 1)
        let plain = RingSession.start(occurrence: occurrence.key, ringAfterMinutes: 10, isEarlyClear: true,
                                      objectIDs: [], missions: occurrence.alarm.missions, now: date("2026-10-22 06:10"), using: &g)
        let plainData = try JSONEncoder().encode(plain)
        XCTAssertFalse(String(decoding: plainData, as: UTF8.self).contains("unlock"), "An early clear shouldn't save an unlock flag")
        XCTAssertFalse(try JSONDecoder().decode(RingSession.self, from: plainData).isUnlock)
    }
}
