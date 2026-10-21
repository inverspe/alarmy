import XCTest
@testable import AlarmyCore

final class BackupPlannerTests: XCTestCase {
    private let a = alarm(6, 30), b = alarm(7, 30), c = alarm(8, 30)
    private var g = SeededGenerator(seed: 7)

    private func occ(_ al: Alarm, _ s: String) -> Occurrence { Occurrence(alarm: al, fireDate: date(s)) }
    private func key(_ al: Alarm, _ s: String) -> OccurrenceKey { occ(al, s).key }

    private func plan(upcoming: [Occurrence] = [], completed: Set<OccurrenceKey> = [],
                      session: RingSession? = nil, now: String) -> [PlannedNotification] {
        BackupPlanner.plan(upcoming: upcoming, completed: completed, session: session, now: date(now))
    }

    private func mission(_ o: Occurrence, early: Bool = false) -> RingSession {
        RingSession.start(occurrence: o.key, ringAfterMinutes: 10, isEarlyClear: early,
                          objectIDs: [UUID()], now: o.fireDate, using: &g)
    }

    private func countdown(_ o: Occurrence, endsAt: Date) -> RingSession {
        var s = mission(o)
        s.recordMatch(now: endsAt - 600)
        return s
    }

    func testSingleUpcoming() {
        let p = plan(upcoming: [occ(a, "2026-10-21 06:30")], now: "2026-10-20 22:00")
        XCTAssertEqual(p.count, 40)
        XCTAssertEqual(p.first?.fireDate, date("2026-10-21 06:30"))
        XCTAssertEqual(p.last?.fireDate, date("2026-10-21 06:49") + 30)
        XCTAssertEqual(Set(p.map(\.id)).count, 40)
        XCTAssertEqual(p.first?.id, "\(a.id)-\(Int(date("2026-10-21 06:30").timeIntervalSince1970))")
    }

    func testBudgetSplitsAcrossOccurrences() {
        let p = plan(upcoming: [occ(a, "2026-10-21 06:30"), occ(b, "2026-10-21 07:30"), occ(c, "2026-10-21 08:30")],
                     now: "2026-10-20 22:00")
        XCTAssertEqual(p.count, 60)
        XCTAssertEqual(p.filter { $0.occurrence.alarmID == a.id }.count, 40)
        XCTAssertEqual(p.filter { $0.occurrence.alarmID == b.id }.count, 20)
        XCTAssertTrue(p.allSatisfy { $0.occurrence.alarmID != c.id })
    }

    func testMissionSessionSlidesFromNow() {
        let o = occ(a, "2026-10-21 06:30")
        let p = plan(session: mission(o), now: "2026-10-21 06:33")
        XCTAssertEqual(p.count, 40)
        XCTAssertEqual(p.first?.fireDate, date("2026-10-21 06:33") + 30)
        XCTAssertTrue(p.allSatisfy { $0.occurrence == o.key })
    }

    func testCountdownStopsBeforeEnd() {
        let t = date("2026-10-21 06:40")
        let p = BackupPlanner.plan(upcoming: [], completed: [], session: countdown(occ(a, "2026-10-21 06:30"), endsAt: t + 600), now: t)
        XCTAssertEqual(p.count, 19)
        XCTAssertTrue(p.allSatisfy { $0.fireDate < t + 600 })
    }

    func testEarlyClearSessionPlansNothingForItself() {
        let o = occ(a, "2026-10-21 06:30")
        XCTAssertTrue(plan(upcoming: [o], session: mission(o, early: true), now: "2026-10-21 06:10").isEmpty)
    }

    func testSessionOccurrenceNotDoubleBooked() {
        let o = occ(a, "2026-10-21 06:30")
        let p = plan(upcoming: [o], session: mission(o), now: "2026-10-21 06:31")
        XCTAssertEqual(p.count, 40)
        XCTAssertEqual(p.first?.fireDate, date("2026-10-21 06:31") + 30)
    }

    func testCompletedUpcomingSkipped() {
        XCTAssertTrue(plan(upcoming: [occ(a, "2026-10-21 06:30")], completed: [key(a, "2026-10-21 06:30")],
                           now: "2026-10-21 06:10").isEmpty)
    }

    func testNeverExceedsBudget() {
        let upcoming = (0..<5).map { occ(alarm(7, $0 * 10), "2026-10-21 07:\(String(format: "%02d", $0 * 10))") }
        let p = plan(upcoming: upcoming, session: mission(occ(a, "2026-10-21 06:30")), now: "2026-10-21 06:31")
        XCTAssertEqual(p.count, 60)
        XCTAssertEqual(p.map(\.fireDate), p.map(\.fireDate).sorted())
    }
}
