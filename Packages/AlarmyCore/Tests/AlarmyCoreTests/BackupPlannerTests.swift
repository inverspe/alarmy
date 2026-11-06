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

    // MARK: Gentle wake-up

    func testUpcomingBackupsWaitForTheGentleRamp() {
        var gentle = alarm(6, 30)
        gentle.gentleSeconds = 30
        let p = plan(upcoming: [occ(gentle, "2026-10-21 06:30")], now: "2026-10-20 22:00")
        XCTAssertEqual(p.first?.fireDate, date("2026-10-21 06:30") + 30)
        XCTAssertEqual(p.count, 40)
    }

    func testRingingBackupsWaitForTheGentleRamp() {
        let fire = date("2026-10-21 06:30")
        let s = RingSession.start(occurrence: occ(a, "2026-10-21 06:30").key, ringAfterMinutes: 10, isEarlyClear: false,
                                  objectIDs: [UUID()], gentleSeconds: 60, now: fire, using: &g)
        let p = BackupPlanner.plan(upcoming: [], completed: [], session: s, now: fire)
        XCTAssertEqual(p.first?.fireDate, fire + 60)
        XCTAssertEqual(p.dropFirst().first?.fireDate, fire + 90)
    }

    func testRingingBackupsSlideAgainOnceTheRampIsOver() {
        let fire = date("2026-10-21 06:30")
        let s = RingSession.start(occurrence: occ(a, "2026-10-21 06:30").key, ringAfterMinutes: 10, isEarlyClear: false,
                                  objectIDs: [UUID()], gentleSeconds: 15, now: fire, using: &g)
        let p = BackupPlanner.plan(upcoming: [], completed: [], session: s, now: fire + 120)
        XCTAssertEqual(p.first?.fireDate, fire + 150)
    }

    // MARK: Wake-up check

    private func checking(_ o: Occurrence, now: Date, minutes: Int = 5) -> RingSession {
        var s = RingSession.start(occurrence: o.key, ringAfterMinutes: 10, isEarlyClear: false,
                                  objectIDs: [UUID()], wakeCheckMinutes: minutes, now: o.fireDate, using: &g)
        s.recordMatch(now: now)
        return s
    }

    func testCountdownPlansTheCheckAndTheRepeatAfterIt() {
        let o = occ(a, "2026-10-21 06:30")
        let t = date("2026-10-21 06:35")
        let p = BackupPlanner.plan(upcoming: [], completed: [], session: checking(o, now: t), now: t)
        let checkAt = t + 600 + 300
        let checks = p.filter { $0.kind == .wakeCheck }
        XCTAssertEqual(checks.map(\.fireDate), [checkAt])
        XCTAssertTrue(p.contains { $0.kind == .alarm && $0.fireDate == checkAt + 100 })
        XCTAssertFalse(p.contains { $0.kind == .alarm && $0.fireDate >= t + 600 && $0.fireDate < checkAt + 100 })
    }

    func testWaitingPlansTheCheckAndTheRepeatAfterIt() {
        let o = occ(a, "2026-10-21 06:30")
        let t = date("2026-10-21 06:35")
        var s = checking(o, now: t)
        s.tick(now: t + 600)
        let p = BackupPlanner.plan(upcoming: [], completed: [], session: s, now: t + 600)
        XCTAssertEqual(p.first?.kind, .wakeCheck)
        XCTAssertEqual(p.first?.fireDate, t + 900)
        XCTAssertEqual(p.dropFirst().first?.kind, .alarm)
        XCTAssertEqual(p.dropFirst().first?.fireDate, t + 1000)
    }

    func testPromptPlansOnlyTheRepeat() {
        let o = occ(a, "2026-10-21 06:30")
        let t = date("2026-10-21 06:35")
        var s = checking(o, now: t)
        s.tick(now: t + 600)
        s.tick(now: t + 900)
        let p = BackupPlanner.plan(upcoming: [], completed: [], session: s, now: t + 900)
        XCTAssertTrue(p.allSatisfy { $0.kind == .alarm })
        XCTAssertEqual(p.first?.fireDate, t + 1000)
    }

    func testRepeatStopsAtTheHardCap() {
        let o = occ(a, "2026-10-21 06:30")
        let t = o.fireDate + Schedule.hardCap - 1200
        let p = BackupPlanner.plan(upcoming: [], completed: [], session: checking(o, now: t), now: t)
        XCTAssertTrue(p.allSatisfy { $0.fireDate < o.fireDate + Schedule.hardCap })
    }

    func testCheckIdIsDifferentFromAnAlarmAtTheSameMoment() {
        let k = occ(a, "2026-10-21 06:30").key
        let fire = date("2026-10-21 06:50")
        XCTAssertNotEqual(PlannedNotification(occurrence: k, fireDate: fire, kind: .wakeCheck).id,
                          PlannedNotification(occurrence: k, fireDate: fire).id)
    }

    func testLongRingWithACheckStaysWithinBudget() {
        let o = occ(a, "2026-10-21 06:30")
        var s = RingSession.start(occurrence: o.key, ringAfterMinutes: 60, isEarlyClear: false,
                                  objectIDs: [UUID()], wakeCheckMinutes: 5, now: o.fireDate, using: &g)
        let t = date("2026-10-21 06:31")
        s.recordMatch(now: t)
        let upcoming = [occ(b, "2026-10-22 07:30")]
        let p = BackupPlanner.plan(upcoming: upcoming, completed: [], session: s, now: t)
        XCTAssertLessThanOrEqual(p.count, BackupPlanner.budget)
        XCTAssertEqual(p.filter { $0.kind == .wakeCheck }.count, 1)
        XCTAssertTrue(p.contains { $0.fireDate >= t + 3900 + 100 && $0.kind == .alarm })
    }

    func testNeverExceedsBudget() {
        let upcoming = (0..<5).map { occ(alarm(7, $0 * 10), "2026-10-21 07:\(String(format: "%02d", $0 * 10))") }
        let p = plan(upcoming: upcoming, session: mission(occ(a, "2026-10-21 06:30")), now: "2026-10-21 06:31")
        XCTAssertEqual(p.count, 60)
        XCTAssertEqual(p.map(\.fireDate), p.map(\.fireDate).sorted())
    }
}
