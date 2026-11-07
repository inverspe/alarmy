import XCTest
@testable import AlarmyCore

final class NewMissionKindTests: XCTestCase {
    func testDefaults() {
        XCTAssertEqual(MissionStep(kind: .typing).amount, 1)
        XCTAssertEqual(MissionStep(kind: .typing).level, SentenceKind.motivational.rawValue)
        XCTAssertEqual(MissionStep(kind: .memory).amount, 3)
        XCTAssertEqual(MissionStep(kind: .memory).level, 0)
        XCTAssertEqual(MissionStep(kind: .barcode).amount, 1)
    }

    func testRanges() {
        XCTAssertEqual(MissionKind.typing.amountRange, 1...20)
        XCTAssertEqual(MissionKind.memory.amountRange, 1...99)
        XCTAssertEqual(MissionKind.barcode.amountRange, 1...1)
        XCTAssertEqual(MissionKind.memory.levelCount, 5)
        XCTAssertEqual(MissionKind.typing.levelCount, 7)
        XCTAssertEqual(MissionKind.barcode.levelCount, 0)
    }

    func testOnlyMissionsThatCanGetStuckOfferAWayOut() {
        XCTAssertEqual(MissionKind.allCases.filter(\.canGetStuck), [.steps, .squats, .shake, .barcode])
    }

    func testBarcodeKeptThroughSaving() throws {
        let step = MissionStep(kind: .barcode, code: "12345")
        XCTAssertEqual(try JSONDecoder().decode(MissionStep.self, from: JSONEncoder().encode(step)), step)
        XCTAssertEqual([step].cleaned.first?.code, "12345")
    }

    func testBarcodeMissionWithoutItsBarcodeIsLeftOut() {
        let known = MissionStep(kind: .barcode, code: "known")
        let gone = MissionStep(kind: .barcode, code: "gone")
        let none = MissionStep(kind: .barcode)
        let barcodes = [RegisteredBarcode(name: "Toothpaste", code: "known")]
        XCTAssertEqual([known, .photo].runnable(barcodes: barcodes), [known, .photo])
        XCTAssertEqual([gone, .photo].runnable(barcodes: barcodes), [.photo])
        XCTAssertEqual([none].runnable(barcodes: barcodes), [])
    }

    func testAlarmAndStateFromAnOlderBuild() throws {
        let alarm = try JSONDecoder().decode(Alarm.self, from: Data(#"{"id":"\#(UUID().uuidString)","hour":7,"minute":0}"#.utf8))
        XCTAssertEqual(alarm.label, "")
        XCTAssertFalse(alarm.snoozeOn)
        XCTAssertEqual(alarm.snoozeMinutes, 5)
        XCTAssertEqual(alarm.snoozeLimit, 3)
        XCTAssertFalse(alarm.voiceTime || alarm.voiceLabel || alarm.voiceWeather)
        XCTAssertFalse(alarm.voiceIsOn)
        let state = try JSONDecoder().decode(AppState.self, from: Data("{}".utf8))
        XCTAssertEqual(state.barcodes, [])
        XCTAssertEqual(state.customSentences, [])
        XCTAssertEqual(state.missionTimeLimit, 20)
        XCTAssertNil(state.weatherPlace)
    }

    func testEverythingNewIsKeptThroughSaving() throws {
        var state = AppState()
        state.alarms = [Alarm(hour: 7, minute: 0, label: "Gym", snoozeOn: true, snoozeMinutes: 10, snoozeLimit: -1,
                              voiceTime: true, voiceLabel: true, voiceWeather: true)]
        state.barcodes = [RegisteredBarcode(name: "Toothpaste", code: "123")]
        state.customSentences = ["Up you get."]
        state.missionTimeLimit = 40
        state.weatherPlace = WeatherPlace(latitude: 51.5, longitude: -0.12)
        XCTAssertEqual(try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state)), state)
    }

    func testVoiceIsOnOnlyWithSomethingToSay() {
        XCTAssertFalse(Alarm(hour: 7, minute: 0, voiceLabel: true).voiceIsOn)
        XCTAssertTrue(Alarm(hour: 7, minute: 0, label: "Gym", voiceLabel: true).voiceIsOn)
        XCTAssertTrue(Alarm(hour: 7, minute: 0, voiceTime: true).voiceIsOn)
        XCTAssertTrue(Alarm(hour: 7, minute: 0, voiceWeather: true).voiceIsOn)
    }
}

final class SnoozeTests: XCTestCase {
    private let fire = date("2026-10-21 06:30")
    private let key = OccurrenceKey(alarmID: UUID(), fireDate: date("2026-10-21 06:30"))
    private var g = SeededGenerator(seed: 21)

    private func session(minutes: Int = 5, limit: Int = 3, gentle: Int = 0, check: Int = 0, early: Bool = false) -> RingSession {
        RingSession.start(occurrence: key, ringAfterMinutes: 10, isEarlyClear: early, objectIDs: [UUID()],
                          wakeCheckMinutes: check, gentleSeconds: gentle, snoozeMinutes: minutes, snoozeLimit: limit,
                          now: fire, using: &g)
    }

    func testChoices() {
        XCTAssertEqual(Alarm.snoozeMinuteChoices, [1, 3, 5, 10, 15, 20, 25, 30, 45, 60])
        XCTAssertEqual(Alarm.snoozeLimitChoices, [-1, 1, 2, 3, 5, 10])
    }

    func testOffByDefault() {
        let s = RingSession.start(occurrence: key, ringAfterMinutes: 10, isEarlyClear: false, objectIDs: [UUID()], now: fire, using: &g)
        XCTAssertFalse(s.canSnooze(now: fire))
    }

    func testSnoozingStopsTheRingUntilItIsTime() {
        var s = session()
        s.snooze(now: fire + 10)
        XCTAssertEqual(s.phase, .snoozed(until: fire + 310))
        XCTAssertFalse(s.isRinging)
        XCTAssertEqual(s.snoozesLeft, 2)
        s.tick(now: fire + 309)
        XCTAssertFalse(s.isRinging)
        s.tick(now: fire + 310)
        XCTAssertEqual(s.phase, .mission)
        XCTAssertTrue(s.isRinging)
    }

    func testSnoozeDoesNotCountAsDoingTheMission() {
        var s = session()
        s.snooze(now: fire)
        XCTAssertNil(s.currentMission)
        s.tick(now: fire + 300)
        XCTAssertEqual(s.currentMission, .photo)
    }

    func testRunsOutAtTheLimit() {
        var s = session(limit: 2)
        for (index, left) in [1, 0].enumerated() {
            let t = fire + Double(index) * 400
            XCTAssertTrue(s.canSnooze(now: t))
            s.snooze(now: t)
            XCTAssertEqual(s.snoozesLeft, left)
            s.tick(now: t + 300)
        }
        XCTAssertFalse(s.canSnooze(now: fire + 800))
        s.snooze(now: fire + 800)
        XCTAssertEqual(s.phase, .mission, "Snoozed past the limit")
    }

    func testNoLimit() {
        var s = session(limit: -1)
        XCTAssertNil(s.snoozesLeft)
        for i in 0..<12 {
            let t = fire + Double(i) * 301
            XCTAssertTrue(s.canSnooze(now: t))
            s.snooze(now: t)
            s.tick(now: t + 300)
        }
        XCTAssertEqual(s.snoozeCount, 12)
    }

    func testCantSnoozeOnceTheMissionIsDone() {
        var s = session()
        s.completeMission(now: fire + 60)
        XCTAssertFalse(s.canSnooze(now: fire + 60))
        let phase = s.phase
        s.snooze(now: fire + 60)
        XCTAssertEqual(s.phase, phase)
    }

    func testCantSnoozeAnEarlyClear() {
        XCTAssertFalse(session(early: true).canSnooze(now: fire))
    }

    func testCantSnoozePastTheHardCap() {
        let s = session(minutes: 60)
        XCTAssertTrue(s.canSnooze(now: fire + Schedule.hardCap - 3601))
        XCTAssertFalse(s.canSnooze(now: fire + Schedule.hardCap - 3600))
    }

    func testNotWaitingRingsAgainAtOnce() {
        var s = session()
        s.snooze(now: fire)
        s.endSnooze(now: fire + 20)
        XCTAssertEqual(s.phase, .mission)
        XCTAssertEqual(s.ringStart, fire + 20)
        XCTAssertEqual(s.snoozeCount, 1)
    }

    func testEndingOnlyWorksDuringASnooze() {
        var s = session()
        s.endSnooze(now: fire + 20)
        XCTAssertEqual(s.ringStart, fire)
    }

    func testRingAfterASnoozeRampsUpAgain() {
        var s = session(gentle: 30)
        s.snooze(now: fire + 40)
        s.tick(now: fire + 340)
        XCTAssertEqual(s.ringStart, fire + 340)
        XCTAssertEqual(s.gentleEndsAt, fire + 370)
        XCTAssertEqual(s.ringLevel(now: fire + 340), GentleRamp.startLevel)
        XCTAssertEqual(s.ringLevel(now: fire + 370), 1)
    }

    func testAppClosedThroughTheSnoozeCatchesUp() {
        var s = session()
        s.snooze(now: fire)
        s.tick(now: fire + 2000)
        XCTAssertEqual(s.phase, .mission)
        XCTAssertEqual(s.ringStart, fire + 300)
    }

    func testPastTheHardCapItGivesUpInsteadOfRinging() {
        var s = session()
        s.snooze(now: fire)
        s.tick(now: fire + Schedule.hardCap + 1)
        XCTAssertEqual(s.phase, .finished)
    }

    func testMissedCheckGivesSnoozesBack() {
        var s = session(limit: 1, check: 5)
        s.snooze(now: fire)
        s.tick(now: fire + 300)
        XCTAssertEqual(s.snoozesLeft, 0)
        s.completeMission(now: fire + 310)
        let end = fire + 910, check = end + 300, late = check + 100
        s.tick(now: end)
        s.tick(now: check)
        s.tick(now: late, availableObjectIDs: [UUID()], using: &g)
        XCTAssertEqual(s.phase, .mission)
        XCTAssertEqual(s.snoozesLeft, 1)
        XCTAssertEqual(s.ringStart, late)
    }

    func testSurvivesSaving() throws {
        var s = session()
        s.snooze(now: fire)
        XCTAssertEqual(try JSONDecoder().decode(RingSession.self, from: JSONEncoder().encode(s)), s)
    }

    func testSessionFromAnOlderBuildCantSnooze() throws {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(session())) as! [String: Any]
        for name in ["snoozeMinutesStored", "snoozeLimitStored", "snoozeCountStored", "ringStartStored"] { object.removeValue(forKey: name) }
        let decoded = try JSONDecoder().decode(RingSession.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(decoded.canSnooze(now: fire))
        XCTAssertEqual(decoded.ringStart, fire)
    }

    // MARK: Backups

    func testBackupsWaitUntilTheSnoozeEnds() {
        var s = session()
        s.snooze(now: fire)
        let p = BackupPlanner.plan(upcoming: [], completed: [], session: s, now: fire)
        XCTAssertEqual(p.first?.fireDate, fire + 300)
        XCTAssertGreaterThan(p.count, 10)
        XCTAssertTrue(p.allSatisfy { $0.kind == .alarm })
    }

    func testBackupsAfterASnoozeLeaveRoomForTheRamp() {
        var s = session(gentle: 30)
        s.snooze(now: fire)
        let p = BackupPlanner.plan(upcoming: [], completed: [], session: s, now: fire)
        XCTAssertEqual(p.first?.fireDate, fire + 330)
    }

    func testBannersFollowTheRingAfterASnooze() {
        var s = session()
        s.snooze(now: fire)
        s.tick(now: fire + 300)
        let p = BackupPlanner.plan(upcoming: [], completed: [], session: s, now: fire + 300)
        XCTAssertEqual(p.filter { $0.kind == .nudge }.first?.fireDate, fire + 301.5)
    }
}

final class VoiceCycleTests: XCTestCase {
    func testSpeaksAfterThreeSeconds() {
        var cycle = VoiceCycle(now: 100)
        XCTAssertEqual(cycle.tick(now: 102.9), .none)
        XCTAssertFalse(cycle.holdsSoundBack)
        XCTAssertEqual(cycle.tick(now: 103), .speak)
        XCTAssertTrue(cycle.holdsSoundBack)
        XCTAssertEqual(cycle.announcements, 1)
    }

    func testSoundComesBackThenSpeaksAgainThirtySecondsLater() {
        var cycle = VoiceCycle(now: 0)
        _ = cycle.tick(now: 3)
        cycle.speechFinished(now: 10)
        XCTAssertFalse(cycle.holdsSoundBack)
        XCTAssertEqual(cycle.tick(now: 39), .none)
        XCTAssertEqual(cycle.tick(now: 40), .speak)
        XCTAssertEqual(cycle.announcements, 2)
    }

    func testOnlySpeaksOnceEachTime() {
        var cycle = VoiceCycle(now: 0)
        XCTAssertEqual(cycle.tick(now: 3), .speak)
        XCTAssertEqual(cycle.tick(now: 4), .none)
        XCTAssertEqual(cycle.announcements, 1)
    }

    /// The speech-finished call might never come, and the alarm must not stay silent.
    func testGivesUpOnSpeechThatNeverFinishes() {
        var cycle = VoiceCycle(now: 0)
        _ = cycle.tick(now: 3)
        XCTAssertEqual(cycle.tick(now: 47), .none)
        XCTAssertTrue(cycle.holdsSoundBack)
        XCTAssertEqual(cycle.tick(now: 48), .gaveUp)
        XCTAssertFalse(cycle.holdsSoundBack)
        XCTAssertEqual(cycle.tick(now: 78), .speak)
    }

    func testAMissionStopsItAndClosingOneWaitsThirtySeconds() {
        var cycle = VoiceCycle(now: 0)
        _ = cycle.tick(now: 3)
        cycle.pause()
        XCTAssertTrue(cycle.isPaused)
        XCTAssertFalse(cycle.holdsSoundBack)
        XCTAssertEqual(cycle.tick(now: 500), .none)
        cycle.resume(now: 500)
        XCTAssertFalse(cycle.isPaused)
        XCTAssertEqual(cycle.tick(now: 529), .none)
        XCTAssertEqual(cycle.tick(now: 530), .speak)
    }

    func testLateFinishIsIgnored() {
        var cycle = VoiceCycle(now: 0)
        _ = cycle.tick(now: 3)
        cycle.pause()
        cycle.speechFinished(now: 5)
        XCTAssertTrue(cycle.isPaused)
    }
}

final class VoiceScriptTests: XCTestCase {
    private let zone = TimeZone(identifier: "America/New_York")!
    private let morning = date("2026-11-07 07:05")

    func testFirstTimeSaysTheDateToo() {
        XCTAssertEqual(VoiceScript.lines(sayTime: true, weather: nil, label: nil, first: true, date: morning, timeZone: zone),
                       ["Saturday, November 07, 7:05 AM"])
    }

    func testAfterThatJustTheTime() {
        XCTAssertEqual(VoiceScript.lines(sayTime: true, weather: nil, label: nil, first: false, date: morning, timeZone: zone),
                       ["7:05 AM"])
    }

    func testOrderIsTimeThenWeatherThenLabel() {
        XCTAssertEqual(VoiceScript.lines(sayTime: true, weather: "Rain", label: "Gym", first: false, date: morning, timeZone: zone),
                       ["7:05 AM", "Rain", "Gym"])
    }

    func testOnlyWhatWasAskedFor() {
        XCTAssertEqual(VoiceScript.lines(sayTime: false, weather: nil, label: "Gym", first: true, date: morning, timeZone: zone), ["Gym"])
        XCTAssertEqual(VoiceScript.lines(sayTime: false, weather: nil, label: "", first: true, date: morning, timeZone: zone), [])
    }
}

final class WeatherReportTests: XCTestCase {
    private let sample = #"{"current":{"temperature_2m":12.7,"weather_code":3},"daily":{"temperature_2m_max":[15.9],"temperature_2m_min":[8.2]}}"#

    func testReadsTheForecast() throws {
        let report = try XCTUnwrap(WeatherReport.parse(Data(sample.utf8)))
        XCTAssertEqual(report, WeatherReport(condition: .cloudy, temperature: 12, high: 15, low: 8))
    }

    func testBadDataGivesNothing() {
        XCTAssertNil(WeatherReport.parse(Data("{}".utf8)))
        XCTAssertNil(WeatherReport.parse(Data("not json".utf8)))
        XCTAssertNil(WeatherReport.parse(Data(#"{"current":{"temperature_2m":1,"weather_code":3},"daily":{"temperature_2m_max":[],"temperature_2m_min":[]}}"#.utf8)))
    }

    func testSpokenLine() {
        XCTAssertEqual(WeatherReport(condition: .rainy, temperature: 7, high: 9, low: 2).spokenLine,
                       "Today's weather: rainy, currently 7 degrees, high of 9, low of 2.")
        XCTAssertEqual(WeatherReport(condition: .unknown, temperature: -3, high: 0, low: -5).spokenLine,
                       "Today's weather: currently -3 degrees, high of 0, low of -5.")
    }

    func testConditionCodes() {
        let expected: [(Int, WeatherReport.Condition)] = [
            (0, .sunny), (1, .lightlyCloudy), (2, .lightlyCloudy), (3, .cloudy), (45, .misty), (48, .misty), (51, .rainy), (67, .rainy),
            (71, .snowy), (77, .snowy), (80, .rainy), (82, .rainy), (85, .snowy), (86, .snowy), (95, .stormy), (99, .stormy), (200, .unknown),
        ]
        for (code, condition) in expected { XCTAssertEqual(WeatherReport.condition(code: code), condition, "code \(code)") }
    }

    func testPlaceIsRoundedToAboutAKilometre() {
        let place = WeatherPlace(latitude: 51.50739, longitude: -0.12764)
        XCTAssertEqual(place.latitude, 51.51)
        XCTAssertEqual(place.longitude, -0.13)
    }

    func testAddressSendsOnlyTheRoundedPlace() throws {
        let url = try XCTUnwrap(WeatherReport.url(for: WeatherPlace(latitude: 51.50739, longitude: -0.12764), fahrenheit: true))
        XCTAssertEqual(url.host, "api.open-meteo.com")
        XCTAssertTrue(url.absoluteString.contains("latitude=51.51"))
        XCTAssertTrue(url.absoluteString.contains("longitude=-0.13"))
        XCTAssertTrue(url.absoluteString.contains("temperature_unit=fahrenheit"))
    }
}

final class MemoryBoardTests: XCTestCase {
    func testGridSizesAndHowManyLightUp() {
        XCTAssertEqual(MemoryBoard.sides, [3, 4, 5, 6, 7])
        XCTAssertEqual(MemoryBoard.sides.map(MemoryBoard.targetCount), [3, 5, 8, 9, 9])
    }

    func testRandomBoardsFitTheirLevel() {
        var g = SeededGenerator(seed: 3)
        for level in 0..<5 {
            for _ in 0..<50 {
                let board = MemoryBoard.random(level: level, using: &g)
                XCTAssertEqual(board.side, MemoryBoard.sides[level])
                XCTAssertEqual(board.targets.count, MemoryBoard.targetCount(side: board.side))
                XCTAssertTrue(board.targets.allSatisfy { (0..<board.cellCount).contains($0) })
            }
        }
    }

    func testBoardsVaryAndCanUseEveryTile() {
        var g = SeededGenerator(seed: 8)
        var used = Set<Int>()
        for _ in 0..<200 { used.formUnion(MemoryBoard.random(level: 0, using: &g).targets) }
        XCTAssertEqual(used.count, 9)
    }

    func testFindingThemAllFinishesTheRound() {
        var board = MemoryBoard(side: 3, targets: [0, 4, 8])
        XCTAssertEqual(board.tap(0), .right)
        XCTAssertEqual(board.tap(4), .right)
        XCTAssertEqual(board.unflippedTargets, [8])
        XCTAssertEqual(board.tap(8), .finished)
    }

    func testTappingOneTwiceIsIgnored() {
        var board = MemoryBoard(side: 3, targets: [0, 4, 8])
        _ = board.tap(0)
        XCTAssertEqual(board.tap(0), .ignored)
        XCTAssertEqual(board.wrongAttempts, 0)
    }

    func testTappingOutsideTheGridIsIgnored() {
        var board = MemoryBoard(side: 3, targets: [0])
        XCTAssertEqual(board.tap(9), .ignored)
        XCTAssertEqual(board.tap(-1), .ignored)
    }

    func testEverySecondWrongTapGivesAHint() {
        var board = MemoryBoard(side: 3, targets: [0])
        XCTAssertEqual(board.tap(1), .wrong(showHint: false))
        XCTAssertEqual(board.tap(1), .wrong(showHint: true))
        XCTAssertEqual(board.tap(2), .wrong(showHint: false))
        XCTAssertEqual(board.tap(2), .wrong(showHint: true))
        XCTAssertEqual(board.wrongAttempts, 4)
    }

    func testWrongTapsDontLoseProgress() {
        var board = MemoryBoard(side: 3, targets: [0, 4])
        _ = board.tap(0)
        _ = board.tap(1)
        XCTAssertEqual(board.flipped, [0])
        XCTAssertEqual(board.tap(4), .finished)
    }
}

final class SentencesTests: XCTestCase {
    func testEveryKindHasSentencesThatCanBeTyped() {
        for kind in SentenceKind.allCases {
            let list = Sentences.list(kind, custom: [])
            XCTAssertGreaterThanOrEqual(list.count, 10, "\(kind)")
            XCTAssertEqual(Set(list).count, list.count, "\(kind) repeats itself")
            for sentence in list {
                XCTAssertTrue(sentence.allSatisfy { $0.isASCII }, sentence)
                XCTAssertLessThanOrEqual(sentence.count, Sentences.maxCustomLength, sentence)
                XCTAssertEqual(sentence, sentence.trimmingCharacters(in: .whitespaces), sentence)
            }
        }
    }

    func testOwnSentencesAreUsedWhenThereAreAny() {
        XCTAssertEqual(Sentences.list(.custom, custom: ["Up you get."]), ["Up you get."])
    }

    func testPicksOnePerRoundWithoutRepeatsWhenItCan() {
        var g = SeededGenerator(seed: 1)
        let picked = Sentences.pick(from: ["a", "b", "c", "d"], rounds: 3, using: &g)
        XCTAssertEqual(picked.count, 3)
        XCTAssertEqual(Set(picked).count, 3)
    }

    func testRepeatsWhenThereAreTooFew() {
        var g = SeededGenerator(seed: 1)
        let picked = Sentences.pick(from: ["a", "b"], rounds: 5, using: &g)
        XCTAssertEqual(picked.count, 5)
        XCTAssertEqual(Set(picked), ["a", "b"])
    }

    func testNothingToPickFrom() {
        var g = SeededGenerator(seed: 1)
        XCTAssertEqual(Sentences.pick(from: [], rounds: 3, using: &g), [])
    }

    func testHasToBeExact() {
        XCTAssertTrue(Sentences.matches("Wake up.", "Wake up."))
        XCTAssertFalse(Sentences.matches("wake up.", "Wake up."))
        XCTAssertFalse(Sentences.matches("Wake up", "Wake up."))
        XCTAssertFalse(Sentences.matches("Wake up. ", "Wake up."))
    }

    func testCurlyQuotesCountAsStraight() {
        XCTAssertTrue(Sentences.matches("It\u{2019}s \u{201C}time\u{201D}", "It's \"time\""))
    }

    func testOwnSentencesGetTidied() {
        XCTAssertEqual(Sentences.cleaned("  Up you get. \n"), "Up you get.")
        XCTAssertNil(Sentences.cleaned("   "))
        XCTAssertEqual(Sentences.cleaned(String(repeating: "a", count: 200))?.count, 120)
    }
}
