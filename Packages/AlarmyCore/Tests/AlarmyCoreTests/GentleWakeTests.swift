import XCTest
@testable import AlarmyCore

final class GentleWakeTests: XCTestCase {
    private let fire = date("2026-10-21 06:30")
    private let key = OccurrenceKey(alarmID: UUID(), fireDate: date("2026-10-21 06:30"))
    private var g = SeededGenerator(seed: 5)

    private func session(gentle: Int, check: Int = 5, now: Date? = nil) -> RingSession {
        RingSession.start(occurrence: key, ringAfterMinutes: 10, isEarlyClear: false, objectIDs: [UUID()],
                          wakeCheckMinutes: check, gentleSeconds: gentle, now: now ?? fire, using: &g)
    }

    func testStartsQuietButAudible() {
        XCTAssertEqual(GentleRamp.level(elapsed: 0, duration: 30), GentleRamp.startLevel)
        XCTAssertGreaterThan(GentleRamp.startLevel, 0)
    }

    func testNeverBelowStartLevel() {
        XCTAssertEqual(GentleRamp.level(elapsed: -5, duration: 30), GentleRamp.startLevel)
    }

    func testRisesEveryStep() {
        let levels = stride(from: 0.0, through: 30, by: 3).map { GentleRamp.level(elapsed: $0, duration: 30) }
        for (earlier, later) in zip(levels, levels.dropFirst()) { XCTAssertLessThan(earlier, later) }
    }

    func testFullAtTheEnd() {
        XCTAssertEqual(GentleRamp.level(elapsed: 30, duration: 30), 1)
        XCTAssertEqual(GentleRamp.level(elapsed: 90, duration: 30), 1)
    }

    func testOffIsAlwaysFull() {
        XCTAssertEqual(GentleRamp.level(elapsed: 0, duration: 0), 1)
    }

    func testSessionRampCountsFromTheAlarmTime() {
        let s = session(gentle: 30)
        XCTAssertEqual(s.ringLevel(now: fire), GentleRamp.startLevel)
        XCTAssertEqual(s.ringLevel(now: fire + 15), GentleRamp.level(elapsed: 15, duration: 30))
        XCTAssertEqual(s.gentleEndsAt, fire + 30)
    }

    func testReopeningTheAppDoesNotRestartTheRamp() {
        let s = session(gentle: 30, now: fire + 120)
        XCTAssertEqual(s.ringLevel(now: fire + 120), 1)
    }

    func testRepeatAfterAMissedCheckIsFullVolumeAtOnce() {
        var s = session(gentle: 30)
        s.recordMatch(now: fire + 60)
        let end = fire + 660, check = end + 300, late = check + 100
        s.tick(now: end)
        s.tick(now: check)
        s.tick(now: late, availableObjectIDs: [UUID()], using: &g)
        XCTAssertEqual(s.ringLevel(now: late), 1)
        XCTAssertNil(s.gentleEndsAt)
    }

    func testOffHasNoRamp() {
        let s = session(gentle: 0)
        XCTAssertEqual(s.ringLevel(now: fire), 1)
        XCTAssertNil(s.gentleEndsAt)
    }

    func testAlarmFromAnOlderBuildHasBothFeaturesOff() throws {
        let json = #"{"id":"\#(UUID().uuidString)","hour":7,"minute":0}"#
        let decoded = try JSONDecoder().decode(Alarm.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.gentleSeconds, 0)
        XCTAssertEqual(decoded.wakeCheckMinutes, 0)
    }

    func testAlarmKeepsItsSettingsThroughSaving() throws {
        let original = Alarm(hour: 7, minute: 0, gentleSeconds: 30, wakeCheckMinutes: 5)
        let decoded = try JSONDecoder().decode(Alarm.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
    }
}
