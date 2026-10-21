import XCTest
@testable import AlarmyCore

/// Regression tests for the final whole-branch review findings.
final class ReviewFixTests: XCTestCase {
    // MARK: C1 — reboot detection by boot session, not uptime

    private let T = date("2026-10-20 20:05")

    func testRebootWithLongerUptimeTrustsWall() {
        let anchor = ClockAnchor(wall: T, monotonic: 7_200, bootID: "boot-A")
        let wall = date("2026-10-21 06:40")
        XCTAssertEqual(TrustedClock.now(wall: wall, monotonic: 30_000, bootID: "boot-B", anchor: anchor), wall)
    }

    func testSameBootStillIgnoresTamper() {
        let anchor = ClockAnchor(wall: T, monotonic: 1_000, bootID: "boot-A")
        XCTAssertEqual(TrustedClock.now(wall: T + 600 + 8 * 3600, monotonic: 1_600, bootID: "boot-A", anchor: anchor), T + 600)
    }

    func testAnchorReplacedOnNewBoot() {
        let anchor = ClockAnchor(wall: T, monotonic: 1_000, bootID: "boot-A")
        XCTAssertEqual(TrustedClock.refreshedAnchor(anchor, wall: T + 9_999, monotonic: 1_600, bootID: "boot-B"),
                       ClockAnchor(wall: T + 9_999, monotonic: 1_600, bootID: "boot-B"))
    }

    // MARK: C2 — saving an edit never rings straight away

    func testNewAlarmAlreadyPastDoesNotRing() {
        let a = alarm(6, 45)
        let now = date("2026-10-21 07:25")
        let completed = Completion.suppressFired(old: [], new: [a], completed: [:], now: now, calendar: cal())
        XCTAssertNil(Schedule.activeOccurrence([a], completed: completed, now: now, calendar: cal()))
        XCTAssertNotNil(Schedule.nextFireDate(for: a, after: now, calendar: cal()))
    }

    func testRescheduledAlarmAlreadyPastDoesNotRing() {
        var a = alarm(7, 0)
        let old = a
        a.hour = 6
        a.minute = 45
        let now = date("2026-10-21 07:25")
        let completed = Completion.suppressFired(old: [old], new: [a], completed: [:], now: now, calendar: cal())
        XCTAssertNil(Schedule.activeOccurrence([a], completed: completed, now: now, calendar: cal()))
    }

    func testReenabledAlarmAlreadyPastDoesNotRing() {
        var a = alarm(6, 45)
        a.isEnabled = false
        var on = a
        on.isEnabled = true
        let now = date("2026-10-21 07:25")
        let completed = Completion.suppressFired(old: [a], new: [on], completed: [:], now: now, calendar: cal())
        XCTAssertNil(Schedule.activeOccurrence([on], completed: completed, now: now, calendar: cal()))
    }

    func testUnchangedDueAlarmStillRings() {
        let a = alarm(6, 30)
        let now = date("2026-10-21 06:40")
        let completed = Completion.suppressFired(old: [a], new: [a], completed: [:], now: now, calendar: cal())
        XCTAssertNotNil(Schedule.activeOccurrence([a], completed: completed, now: now, calendar: cal()))
    }

    func testFutureTimeNotSuppressed() {
        let a = alarm(8, 0)
        let now = date("2026-10-21 07:25")
        XCTAssertTrue(Completion.suppressFired(old: [], new: [a], completed: [:], now: now, calendar: cal()).isEmpty)
    }

    // MARK: I1 — a mission gives up at the hard cap

    func testMissionFinishesAtHardCap() {
        var g = SeededGenerator(seed: 3)
        let key = OccurrenceKey(alarmID: UUID(), fireDate: date("2026-10-21 06:30"))
        var s = RingSession.start(occurrence: key, ringAfterMinutes: 10, isEarlyClear: false,
                                  objectIDs: [UUID()], now: date("2026-10-21 06:30"), using: &g)
        s.tick(now: date("2026-10-21 08:29"))
        XCTAssertEqual(s.phase, .mission)
        s.tick(now: date("2026-10-21 08:30"))
        XCTAssertEqual(s.phase, .finished)
    }

    // MARK: I3 — older or partial state files still load

    func testDecodesAlarmMissingNewerFields() throws {
        let id = UUID()
        let json = #"{"id":"\#(id.uuidString)","hour":6,"minute":30,"repeatDays":[2,3]}"#
        let a = try JSONDecoder().decode(Alarm.self, from: Data(json.utf8))
        XCTAssertEqual(a, Alarm(id: id, hour: 6, minute: 30, repeatDays: [.monday, .tuesday]))
    }

    func testDecodesEmptyAppState() throws {
        XCTAssertEqual(try JSONDecoder().decode(AppState.self, from: Data("{}".utf8)), AppState())
    }

    func testUnreadableSessionIsDroppedNotEverything() throws {
        var s = AppState()
        s.alarms = [alarm(6, 30)]
        s.onboardingDone = true
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as! [String: Any]
        object["ringSession"] = ["bogus": 1]
        let decoded = try JSONDecoder().decode(AppState.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.alarms, s.alarms)
        XCTAssertTrue(decoded.onboardingDone)
        XCTAssertNil(decoded.ringSession)
    }
}
