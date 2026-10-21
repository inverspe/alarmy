import XCTest
@testable import AlarmyCore

final class RingSessionTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID()
    private var all: [UUID] { [a, b, c] }
    private let t0 = date("2026-10-21 06:35")
    private let key = OccurrenceKey(alarmID: UUID(), fireDate: date("2026-10-21 06:30"))
    private var g = SeededGenerator(seed: 1)

    private func start(_ ids: [UUID], now: Date? = nil, early: Bool = false) -> RingSession {
        RingSession.start(occurrence: key, ringAfterMinutes: 10, isEarlyClear: early,
                          objectIDs: ids, now: now ?? t0, using: &g)
    }

    private func miss(_ s: inout RingSession, _ n: Int, available: [UUID]? = nil) {
        for _ in 0..<n { s.recordMiss(availableObjectIDs: available ?? all, using: &g) }
    }

    func testStartPicksRandomObject() {
        let s = start(all)
        XCTAssertEqual(s.phase, .mission)
        XCTAssertTrue(all.contains(s.currentObjectID!))
        XCTAssertEqual(s.triedObjectIDs, [s.currentObjectID!])
        XCTAssertEqual(s.missesOnCurrent, 0)
        XCTAssertTrue(s.isRinging)
    }

    func testStartIsRandomAcrossSeeds() {
        let picks = Set((1...20).map { seed -> UUID in
            var gen = SeededGenerator(seed: UInt64(seed))
            return RingSession.start(occurrence: key, ringAfterMinutes: 10, isEarlyClear: false,
                                     objectIDs: all, now: t0, using: &gen).currentObjectID!
        })
        XCTAssertGreaterThan(picks.count, 1)
    }

    func testStartWithNoObjectsGoesStraightToCountdown() {
        let s = start([], now: t0)
        XCTAssertEqual(s.phase, .countdown(endsAt: t0 + 600))
        XCTAssertNil(s.currentObjectID)
        XCTAssertTrue(s.isRinging)
    }

    func testFourMissesKeepsObject() {
        var s = start(all)
        let first = s.currentObjectID
        miss(&s, 4)
        XCTAssertEqual(s.currentObjectID, first)
        XCTAssertEqual(s.missesOnCurrent, 4)
    }

    func testFifthMissSwitchesToUntried() {
        var s = start(all)
        let first = s.currentObjectID
        miss(&s, 5)
        XCTAssertNotEqual(s.currentObjectID, first)
        XCTAssertEqual(s.missesOnCurrent, 0)
        XCTAssertEqual(Set(s.triedObjectIDs).count, 2)
        XCTAssertEqual(s.phase, .mission)
    }

    func testCyclesAfterAllTried() {
        var s = start(all)
        miss(&s, 15)
        let current = s.currentObjectID
        miss(&s, 5)
        XCTAssertNotEqual(s.currentObjectID, current)
        XCTAssertNotNil(s.currentObjectID)
    }

    func testSingleObjectStaysAndResets() {
        var s = start([a])
        miss(&s, 5, available: [a])
        XCTAssertEqual(s.currentObjectID, a)
        XCTAssertEqual(s.missesOnCurrent, 0)
    }

    func testMissSkipsUnavailableObjects() {
        var s = start(all)
        let current = s.currentObjectID!
        let other = all.first { $0 != current }!
        miss(&s, 5, available: [current, other])
        XCTAssertEqual(s.currentObjectID, other)
    }

    func testMatchStartsCountdown() {
        var s = start([a])
        s.recordMatch(now: t0)
        XCTAssertEqual(s.phase, .countdown(endsAt: t0 + 600))
        XCTAssertTrue(s.isRinging)
    }

    func testTickFinishesAtEnd() {
        var s = start([a])
        s.recordMatch(now: t0)
        s.tick(now: t0 + 599)
        XCTAssertNotEqual(s.phase, .finished)
        s.tick(now: t0 + 600)
        XCTAssertEqual(s.phase, .finished)
        XCTAssertFalse(s.isRinging)
    }

    func testTickDuringMissionDoesNothing() {
        var s = start([a])
        s.tick(now: t0 + 3600)
        XCTAssertEqual(s.phase, .mission)
    }

    func testEarlyClearFinishesOnMatchAndNeverRings() {
        var s = start([a], early: true)
        XCTAssertFalse(s.isRinging)
        s.recordMatch(now: t0)
        XCTAssertEqual(s.phase, .finished)
        XCTAssertFalse(s.isRinging)
    }

    func testCodableRoundTrip() throws {
        var s = start([a, b])
        s.recordMatch(now: t0)
        let decoded = try JSONDecoder().decode(RingSession.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(decoded, s)
    }
}
