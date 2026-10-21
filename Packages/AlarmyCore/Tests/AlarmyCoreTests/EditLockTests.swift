import XCTest
@testable import AlarmyCore

// One 6:30 daily alarm (America/New_York).
final class EditLockTests: XCTestCase {
    private let id = UUID()

    private func make(lockHours: Int = 8, earlyMinutes: Int = 30) -> Alarm {
        Alarm(id: id, hour: 6, minute: 30, repeatDays: Set(Weekday.allCases),
              lockHours: lockHours, earlyClearMinutes: earlyMinutes)
    }

    private func completed(_ at: String?) -> [OccurrenceKey: Date] {
        guard let at else { return [:] }
        return [OccurrenceKey(alarmID: id, fireDate: date("2026-10-21 06:30")): date(at)]
    }

    private func lock(now: String, completedAt: String? = nil, lockHours: Int = 8, session: Occurrence? = nil) -> Occurrence? {
        EditLock.lockedUntilDone([make(lockHours: lockHours)], completed: completed(completedAt),
                                 session: session, now: date(now), calendar: cal())
    }

    private func early(now: String, completedAt: String? = nil, earlyMinutes: Int = 30) -> Occurrence? {
        EditLock.earlyClearable([make(earlyMinutes: earlyMinutes)], completed: completed(completedAt),
                                now: date(now), calendar: cal())
    }

    func testUnlockedBeforeWindow() { XCTAssertNil(lock(now: "2026-10-20 22:29")) }

    func testLockedAtWindowStart() {
        XCTAssertEqual(lock(now: "2026-10-20 22:30")?.fireDate, date("2026-10-21 06:30"))
    }

    func testLockedWhileRingingUncompleted() { XCTAssertNotNil(lock(now: "2026-10-21 06:45")) }

    func testUnlockedAfterCompletion() {
        XCTAssertNil(lock(now: "2026-10-21 06:43", completedAt: "2026-10-21 06:42"))
    }

    func testUnlockedAfterEarlyClear() {
        XCTAssertNil(lock(now: "2026-10-21 06:06", completedAt: "2026-10-21 06:05"))
    }

    func testUnlockedAtHardCap() { XCTAssertNil(lock(now: "2026-10-21 08:30")) }

    func testLockHoursZeroOnlyLocksDuringRing() {
        XCTAssertNil(lock(now: "2026-10-21 06:29", lockHours: 0))
        XCTAssertNotNil(lock(now: "2026-10-21 06:31", lockHours: 0))
    }

    func testLockedWhileSessionActive() {
        let session = Occurrence(alarm: make(lockHours: 0), fireDate: date("2026-10-21 06:30"))
        XCTAssertEqual(lock(now: "2026-10-21 09:00", lockHours: 0, session: session), session)
    }

    func testEarlyClearWindow() {
        XCTAssertNil(early(now: "2026-10-21 05:59"))
        XCTAssertEqual(early(now: "2026-10-21 06:00")?.fireDate, date("2026-10-21 06:30"))
        XCTAssertNil(early(now: "2026-10-21 06:30"))
        XCTAssertNil(early(now: "2026-10-21 06:10", completedAt: "2026-10-21 06:05"))
        XCTAssertNil(early(now: "2026-10-21 06:10", earlyMinutes: 0))
    }
}
