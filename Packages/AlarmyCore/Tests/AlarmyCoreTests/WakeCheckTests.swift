import XCTest
@testable import AlarmyCore

final class WakeCheckTests: XCTestCase {
    private let a = UUID(), b = UUID()
    private let fire = date("2026-10-21 06:30")
    private let key = OccurrenceKey(alarmID: UUID(), fireDate: date("2026-10-21 06:30"))
    private var g = SeededGenerator(seed: 3)

    /// Mission matched at 06:35, so the 10-minute ring ends at 06:45.
    private func ringing(check: Int = 5, objects: [UUID]? = nil, ringAfter: Int = 10) -> RingSession {
        var s = RingSession.start(occurrence: key, ringAfterMinutes: ringAfter, isEarlyClear: false,
                                  objectIDs: objects ?? [a], wakeCheckMinutes: check, now: fire, using: &g)
        s.recordMatch(now: date("2026-10-21 06:35"))
        return s
    }

    private let ringEnd = date("2026-10-21 06:45")
    private let checkAt = date("2026-10-21 06:50")
    private var deadline: Date { checkAt + RingSession.wakeCheckResponseTime }

    func testOffFinishesWhenTheRingEnds() {
        var s = ringing(check: 0)
        s.tick(now: ringEnd)
        XCTAssertEqual(s.phase, .finished)
    }

    func testRingEndStartsWaitingAndGoesQuiet() {
        var s = ringing()
        s.tick(now: ringEnd)
        XCTAssertEqual(s.phase, .wakeCheckWaiting(checkAt: checkAt))
        XCTAssertFalse(s.isRinging)
        XCTAssertTrue(s.isAwaitingWakeCheck)
    }

    func testPromptAppearsAtCheckTimeWithA100SecondLimit() {
        var s = ringing()
        s.tick(now: ringEnd)
        s.tick(now: checkAt - 1)
        XCTAssertEqual(s.phase, .wakeCheckWaiting(checkAt: checkAt))
        s.tick(now: checkAt)
        XCTAssertEqual(s.phase, .wakeCheckPrompt(deadline: checkAt + 100))
        XCTAssertFalse(s.isRinging)
    }

    func testAnsweringFinishes() {
        var s = ringing()
        s.tick(now: ringEnd)
        s.tick(now: checkAt)
        s.confirmAwake()
        XCTAssertEqual(s.phase, .finished)
    }

    func testAnsweringOnlyCountsDuringThePrompt() {
        var s = ringing()
        s.tick(now: ringEnd)
        s.confirmAwake()
        XCTAssertEqual(s.phase, .wakeCheckWaiting(checkAt: checkAt))
    }

    func testNoAnswerStartsTheMissionOverAndRings() {
        var s = ringing()
        s.tick(now: ringEnd)
        s.tick(now: checkAt)
        s.tick(now: deadline, availableObjectIDs: [a], using: &g)
        XCTAssertEqual(s.phase, .mission)
        XCTAssertTrue(s.isRinging)
        XCTAssertEqual(s.missedWakeChecks, 1)
    }

    func testMissedCheckPicksADifferentObject() {
        var s = ringing(objects: [a])
        s.tick(now: ringEnd)
        s.tick(now: checkAt)
        s.tick(now: deadline, availableObjectIDs: [a, b], using: &g)
        XCTAssertEqual(s.currentObjectID, b)
        XCTAssertEqual(s.missesOnCurrent, 0)
    }

    func testMissedCheckKeepsTheOnlyObject() {
        var s = ringing(objects: [a])
        s.tick(now: ringEnd)
        s.tick(now: checkAt)
        s.tick(now: deadline, availableObjectIDs: [a], using: &g)
        XCTAssertEqual(s.currentObjectID, a)
    }

    func testMissedCheckWithNoObjectsRingsTheCountdownAgain() {
        var s = RingSession.start(occurrence: key, ringAfterMinutes: 10, isEarlyClear: false,
                                  objectIDs: [], wakeCheckMinutes: 5, now: fire, using: &g)
        let end = fire + 600, check = end + 300, late = check + 100
        s.tick(now: end)
        s.tick(now: check)
        s.tick(now: late, availableObjectIDs: [], using: &g)
        XCTAssertEqual(s.phase, .countdown(endsAt: late + 600))
        XCTAssertTrue(s.isRinging)
    }

    func testAfterARepeatTheCheckComesBackToo() {
        var s = ringing()
        s.tick(now: ringEnd)
        s.tick(now: checkAt)
        s.tick(now: deadline, availableObjectIDs: [a], using: &g)
        s.recordMatch(now: deadline + 60)
        let end = deadline + 660
        s.tick(now: end)
        XCTAssertEqual(s.phase, .wakeCheckWaiting(checkAt: end + 300))
    }

    func testAppReturningAfterTheDeadlineCatchesUpInOneTick() {
        var s = ringing()
        s.tick(now: deadline + 45, availableObjectIDs: [a], using: &g)
        XCTAssertEqual(s.phase, .mission)
        XCTAssertEqual(s.missedWakeChecks, 1)
    }

    func testNoNewRingPastTheHardCap() {
        var s = ringing()
        s.tick(now: fire + Schedule.hardCap, availableObjectIDs: [a], using: &g)
        XCTAssertEqual(s.phase, .finished)
    }

    func testRingEndingPastTheHardCapSkipsTheCheck() {
        var s = RingSession.start(occurrence: key, ringAfterMinutes: 10, isEarlyClear: false,
                                  objectIDs: [a], wakeCheckMinutes: 5, now: fire, using: &g)
        s.recordMatch(now: fire + Schedule.hardCap - 60)
        s.tick(now: fire + Schedule.hardCap + 540)
        XCTAssertEqual(s.phase, .finished)
    }

    func testEarlyClearSkipsTheCheck() {
        var s = RingSession.start(occurrence: key, ringAfterMinutes: 10, isEarlyClear: true,
                                  objectIDs: [a], wakeCheckMinutes: 5, now: fire - 600, using: &g)
        s.recordMatch(now: fire - 300)
        XCTAssertEqual(s.phase, .finished)
    }

    func testSessionFromAnOlderBuildHasNoCheck() throws {
        let s = ringing(check: 5)
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as! [String: Any]
        object.removeValue(forKey: "wakeCheckMinutesStored")
        object.removeValue(forKey: "gentleSecondsStored")
        object.removeValue(forKey: "missedWakeChecksStored")
        var decoded = try JSONDecoder().decode(RingSession.self, from: JSONSerialization.data(withJSONObject: object))
        decoded.tick(now: ringEnd)
        XCTAssertEqual(decoded.phase, .finished)
    }

    func testCodableRoundTripDuringTheCheck() throws {
        var s = ringing()
        s.tick(now: ringEnd)
        s.tick(now: checkAt)
        let decoded = try JSONDecoder().decode(RingSession.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(decoded, s)
        XCTAssertEqual(decoded.wakeCheckMinutes, 5)
    }
}
