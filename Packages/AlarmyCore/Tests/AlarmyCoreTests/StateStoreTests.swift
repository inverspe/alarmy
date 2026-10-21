import XCTest
@testable import AlarmyCore

final class StateStoreTests: XCTestCase {
    private var dir: URL!
    private var tmp: URL { dir.appendingPathComponent("state.json") }

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func corruptSiblings() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("state.corrupt-") }
    }

    func testDefaults() {
        let a = Alarm(hour: 6, minute: 30)
        XCTAssertEqual([a.ringAfterMinutes, a.lockHours, a.earlyClearMinutes], [10, 8, 30])
        XCTAssertEqual(a.sound, .klaxon)
        XCTAssertTrue(a.repeatDays.isEmpty)
        XCTAssertTrue(a.isEnabled)
        XCTAssertEqual(AppState().strictness, .medium)
        XCTAssertFalse(AppState().onboardingDone)
    }

    func testWeekdayMatchesCalendarNumbering() {
        XCTAssertEqual(Weekday.sunday.rawValue, 1)
        XCTAssertEqual(Weekday.saturday.rawValue, 7)
        XCTAssertEqual(cal().component(.weekday, from: date("2026-10-21 12:00")), Weekday.wednesday.rawValue)
    }

    func testRoundTrip() throws {
        let store = StateStore(fileURL: tmp)
        var s = AppState()
        s.alarms = [alarm(6, 30)]
        s.objects = [RegisteredObject(id: UUID(), name: "Kettle", referencePhotoIDs: [UUID(), UUID()])]
        s.strictness = .strict
        s.completed = [OccurrenceKey(alarmID: s.alarms[0].id, fireDate: date("2026-10-21 06:30")): date("2026-10-21 06:42")]
        try store.save(s)
        XCTAssertEqual(store.load(), s)
    }

    func testMissingFileLoadsDefaults() {
        XCTAssertEqual(StateStore(fileURL: tmp).load(), AppState())
    }

    func testCorruptFileIsSetAsideAndDefaultsLoaded() throws {
        try Data("{not json".utf8).write(to: tmp)
        XCTAssertEqual(StateStore(fileURL: tmp).load(), AppState())
        XCTAssertNil(FileManager.default.contents(atPath: tmp.path))
        XCTAssertEqual(try corruptSiblings().count, 1)
    }

    func testOccurrenceKey() {
        let a = alarm(6, 30)
        let o = Occurrence(alarm: a, fireDate: date("2026-10-21 06:30"))
        XCTAssertEqual(o.key, OccurrenceKey(alarmID: a.id, fireDate: date("2026-10-21 06:30")))
    }
}
