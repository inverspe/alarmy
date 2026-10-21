import XCTest
@testable import AlarmyCore

final class CompletionTests: XCTestCase {
    func testMarkFinishedCoversOverlappingAlarms() {
        let a = alarm(6, 30), b = alarm(6, 35), c = alarm(7, 0)
        let k = OccurrenceKey(alarmID: a.id, fireDate: date("2026-10-21 06:30"))
        let result = Completion.markFinished(k, at: date("2026-10-21 06:42"), alarms: [a, b, c], completed: [:], calendar: cal())
        XCTAssertEqual(Set(result.keys), [k, OccurrenceKey(alarmID: b.id, fireDate: date("2026-10-21 06:35"))])
        XCTAssertEqual(result[k], date("2026-10-21 06:42"))
    }

    func testMarkFinishedKeepsSessionKeyEvenIfAlarmWasDeleted() {
        let k = OccurrenceKey(alarmID: UUID(), fireDate: date("2026-10-21 06:30"))
        let result = Completion.markFinished(k, at: date("2026-10-21 06:42"), alarms: [], completed: [:], calendar: cal())
        XCTAssertEqual(Array(result.keys), [k])
    }

    func testPrunesOlderThan7Days() {
        let a = alarm(6, 30)
        let old = OccurrenceKey(alarmID: a.id, fireDate: date("2026-10-13 06:30"))
        let recent = OccurrenceKey(alarmID: a.id, fireDate: date("2026-10-15 06:30"))
        let k = OccurrenceKey(alarmID: a.id, fireDate: date("2026-10-21 06:30"))
        let result = Completion.markFinished(k, at: date("2026-10-21 06:42"), alarms: [a],
                                             completed: [old: date("2026-10-13 06:41"), recent: date("2026-10-15 06:41")],
                                             calendar: cal())
        XCTAssertNil(result[old])
        XCTAssertNotNil(result[recent])
        XCTAssertNotNil(result[k])
    }
}
