import XCTest
@testable import AlarmyCore

// America/New_York; 2026-10-21 is a Wednesday.
final class ScheduleTests: XCTestCase {
    private let weekdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]

    func testDailyNextFire() {
        XCTAssertEqual(Schedule.nextFireDate(for: alarm(6, 30), after: date("2026-10-20 22:00"), calendar: cal()),
                       date("2026-10-21 06:30"))
    }

    func testNextFireIsStrictlyAfter() {
        XCTAssertEqual(Schedule.nextFireDate(for: alarm(6, 30), after: date("2026-10-21 06:30"), calendar: cal()),
                       date("2026-10-22 06:30"))
    }

    func testWeekdaysSkipWeekend() {
        XCTAssertEqual(Schedule.nextFireDate(for: alarm(6, 30, days: weekdays), after: date("2026-10-23 07:00"), calendar: cal()),
                       date("2026-10-26 06:30"))
    }

    func testOneTime() {
        XCTAssertEqual(Schedule.nextFireDate(for: Alarm(hour: 6, minute: 30), after: date("2026-10-21 07:00"), calendar: cal()),
                       date("2026-10-22 06:30"))
    }

    func testDisabledIsNil() {
        var a = alarm(6, 30)
        a.isEnabled = false
        XCTAssertNil(Schedule.nextFireDate(for: a, after: date("2026-10-21 07:00"), calendar: cal()))
    }

    // US DST starts 2026-03-08 at 02:00.
    func testDSTSpringForward() {
        XCTAssertEqual(Schedule.nextFireDate(for: alarm(6, 30), after: date("2026-03-07 23:00"), calendar: cal()),
                       date("2026-03-08 06:30"))
        XCTAssertEqual(Schedule.nextFireDate(for: alarm(2, 30), after: date("2026-03-07 23:00"), calendar: cal()),
                       date("2026-03-08 03:00"))
    }

    func testUsesCalendarTimeZone() {
        XCTAssertEqual(Schedule.nextFireDate(for: alarm(6, 30), after: date("2026-10-20 22:00", "Europe/London"),
                                             calendar: cal("Europe/London")),
                       date("2026-10-21 06:30", "Europe/London"))
    }

    func testUpcomingIsSortedAndLimited() {
        let a = alarm(6, 30), b = alarm(7, 0)
        let result = Schedule.upcoming([a, b], after: date("2026-10-20 22:00"), calendar: cal(), limit: 3)
        XCTAssertEqual(result.map(\.fireDate), [date("2026-10-21 06:30"), date("2026-10-21 07:00"), date("2026-10-22 06:30")])
        XCTAssertEqual(result.map(\.alarm.id), [a.id, b.id, a.id])
    }

    func testUpcomingSkipsDisabled() {
        var a = alarm(6, 30)
        a.isEnabled = false
        XCTAssertTrue(Schedule.upcoming([a], after: date("2026-10-20 22:00"), calendar: cal(), limit: 3).isEmpty)
    }

    func testOccurrencesInRangeAreInclusive() {
        let a = alarm(6, 30), b = alarm(6, 35), c = alarm(7, 0)
        let result = Schedule.occurrences([a, b, c], from: date("2026-10-21 06:30"), through: date("2026-10-21 06:35"), calendar: cal())
        XCTAssertEqual(result.map(\.alarm.id), [a.id, b.id])
    }

    func testActiveOccurrenceAfterLateTap() {
        XCTAssertEqual(Schedule.activeOccurrence([alarm(6, 30)], completed: [:], now: date("2026-10-21 06:40"), calendar: cal())?.fireDate,
                       date("2026-10-21 06:30"))
    }

    func testActiveOccurrenceAtFireTime() {
        XCTAssertNotNil(Schedule.activeOccurrence([alarm(6, 30)], completed: [:], now: date("2026-10-21 06:30"), calendar: cal()))
        XCTAssertNil(Schedule.activeOccurrence([alarm(6, 30)], completed: [:], now: date("2026-10-21 06:29"), calendar: cal()))
    }

    func testActiveOccurrenceExpiresAtHardCap() {
        XCTAssertNotNil(Schedule.activeOccurrence([alarm(6, 30)], completed: [:], now: date("2026-10-21 08:29"), calendar: cal()))
        XCTAssertNil(Schedule.activeOccurrence([alarm(6, 30)], completed: [:], now: date("2026-10-21 08:30"), calendar: cal()))
    }

    func testActiveOccurrenceIgnoresCompleted() {
        let a = alarm(6, 30)
        let k = OccurrenceKey(alarmID: a.id, fireDate: date("2026-10-21 06:30"))
        XCTAssertNil(Schedule.activeOccurrence([a], completed: [k: date("2026-10-21 06:42")], now: date("2026-10-21 06:50"), calendar: cal()))
    }

    func testActiveOccurrencePicksEarliestUncompleted() {
        let a = alarm(6, 30), b = alarm(6, 35)
        XCTAssertEqual(Schedule.activeOccurrence([b, a], completed: [:], now: date("2026-10-21 06:40"), calendar: cal())?.alarm.id, a.id)
    }
}
