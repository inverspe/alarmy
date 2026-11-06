import XCTest
@testable import AlarmyCore

final class MissionStackTests: XCTestCase {
    private let a = UUID(), b = UUID()
    private let fire = date("2026-10-21 06:30")
    private let key = OccurrenceKey(alarmID: UUID(), fireDate: date("2026-10-21 06:30"))
    private var g = SeededGenerator(seed: 11)

    private let steps = MissionStep(kind: .steps, amount: 30)
    private let math = MissionStep(kind: .math, amount: 3)

    private func start(_ missions: [MissionStep], objects: [UUID]? = nil, check: Int = 0, early: Bool = false) -> RingSession {
        RingSession.start(occurrence: key, ringAfterMinutes: 10, isEarlyClear: early, objectIDs: objects ?? [a],
                          missions: missions, wakeCheckMinutes: check, now: fire, using: &g)
    }

    func testDefaultIsJustPhoto() {
        let s = RingSession.start(occurrence: key, ringAfterMinutes: 10, isEarlyClear: false,
                                  objectIDs: [a], now: fire, using: &g)
        XCTAssertEqual(s.missions, [.photo])
        XCTAssertEqual(s.currentMission, .photo)
    }

    func testStartsOnTheFirstMission() {
        let s = start([steps, .photo])
        XCTAssertEqual(s.phase, .mission)
        XCTAssertEqual(s.currentMission, steps)
        XCTAssertEqual(s.missionIndex, 0)
    }

    func testRunsThroughTheListInOrderThenCountsDown() {
        var s = start([steps, .photo, math])
        s.completeMission(now: fire + 60)
        XCTAssertEqual(s.currentMission, .photo)
        XCTAssertEqual(s.phase, .mission)
        s.completeMission(now: fire + 120)
        XCTAssertEqual(s.currentMission, math)
        s.completeMission(now: fire + 180)
        XCTAssertNil(s.currentMission)
        XCTAssertEqual(s.phase, .countdown(endsAt: fire + 180 + 600))
    }

    func testRunningOutOfTimeGoesBackToTheFirstMission() {
        var s = start([steps, .photo, math])
        s.completeMission(now: fire + 60)
        s.completeMission(now: fire + 120)
        s.restartMissions()
        XCTAssertEqual(s.currentMission, steps)
        XCTAssertEqual(s.phase, .mission)
        XCTAssertEqual(s.currentObjectID, a)
    }

    func testRestartingDoesNothingOutsideAMission() {
        var s = start([steps])
        s.completeMission(now: fire + 60)
        let countingDown = s.phase
        s.restartMissions()
        XCTAssertEqual(s.phase, countingDown)
    }

    func testKeepsRingingBetweenMissions() {
        var s = start([steps, math])
        s.completeMission(now: fire + 60)
        XCTAssertTrue(s.isRinging)
    }

    func testObjectChosenOnlyWhenThereIsAPhotoMission() {
        XCTAssertNil(start([steps]).currentObjectID)
        XCTAssertEqual(start([steps, .photo]).currentObjectID, a)
    }

    func testPhotoIsDroppedWhenThereAreNoObjects() {
        let s = start([.photo, steps], objects: [])
        XCTAssertEqual(s.missions, [steps])
        XCTAssertEqual(s.currentMission, steps)
    }

    func testNoObjectsDoesNotMatterWithoutAPhotoMission() {
        let s = start([steps], objects: [])
        XCTAssertEqual(s.phase, .mission)
    }

    func testOnlyPhotoAndNoObjectsJustRings() {
        let s = start([.photo], objects: [])
        XCTAssertEqual(s.phase, .countdown(endsAt: fire + 600))
        XCTAssertFalse(s.hadMissions)
    }

    func testEarlyClearFinishesOnlyAfterTheLastMission() {
        var s = start([steps, math], early: true)
        s.completeMission(now: fire - 300)
        XCTAssertEqual(s.currentMission, math)
        s.completeMission(now: fire - 200)
        XCTAssertEqual(s.phase, .finished)
    }

    func testCompletingDoesNothingOutsideAMission() {
        var s = start([steps])
        s.completeMission(now: fire + 60)
        let countdown = s.phase
        s.completeMission(now: fire + 90)
        XCTAssertEqual(s.phase, countdown)
    }

    func testMissedWakeCheckStartsTheWholeListOver() {
        var s = start([steps, .photo], check: 5)
        s.completeMission(now: fire + 60)
        s.completeMission(now: fire + 120)
        let end = fire + 720, check = end + 300, late = check + 100
        s.tick(now: end)
        s.tick(now: check)
        s.tick(now: late, availableObjectIDs: [a, b], using: &g)
        XCTAssertEqual(s.missionIndex, 0)
        XCTAssertEqual(s.currentMission, steps)
        XCTAssertEqual(s.currentObjectID, b)
    }

    func testMissedWakeCheckWithoutPhotoPicksNoObject() {
        var s = start([steps], check: 5)
        s.completeMission(now: fire + 60)
        let end = fire + 660, check = end + 300, late = check + 100
        s.tick(now: end)
        s.tick(now: check)
        s.tick(now: late, availableObjectIDs: [a, b], using: &g)
        XCTAssertNil(s.currentObjectID)
        XCTAssertEqual(s.currentMission, steps)
    }

    func testHardCapStillEndsAStack() {
        var s = start([steps, math])
        s.tick(now: fire + Schedule.hardCap)
        XCTAssertEqual(s.phase, .finished)
    }

    func testSessionFromAnOlderBuildIsJustPhoto() throws {
        let s = start([.photo])
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as! [String: Any]
        object.removeValue(forKey: "missionsStored")
        object.removeValue(forKey: "missionIndexStored")
        let decoded = try JSONDecoder().decode(RingSession.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.currentMission, .photo)
    }

    func testCodableRoundTripMidStack() throws {
        var s = start([steps, math])
        s.completeMission(now: fire + 60)
        let decoded = try JSONDecoder().decode(RingSession.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(decoded, s)
        XCTAssertEqual(decoded.currentMission, math)
    }
}

final class AlarmMissionTests: XCTestCase {
    func testNewAlarmUsesPhoto() {
        XCTAssertEqual(Alarm(hour: 7, minute: 0).missions, [.photo])
    }

    func testAlarmFromAnOlderBuildUsesPhoto() throws {
        let json = #"{"id":"\#(UUID().uuidString)","hour":7,"minute":0}"#
        XCTAssertEqual(try JSONDecoder().decode(Alarm.self, from: Data(json.utf8)).missions, [.photo])
    }

    func testAlarmKeepsItsListThroughSaving() throws {
        var alarm = Alarm(hour: 7, minute: 0)
        alarm.missions = [MissionStep(kind: .math, amount: 4), .photo]
        XCTAssertEqual(try JSONDecoder().decode(Alarm.self, from: JSONEncoder().encode(alarm)), alarm)
    }

    func testOnlyPhotoAlarmsNeedObjects() {
        var alarm = Alarm(hour: 7, minute: 0)
        XCTAssertTrue(alarm.needsObjects)
        alarm.missions = [MissionStep(kind: .steps)]
        XCTAssertFalse(alarm.needsObjects)
    }

    func testCleanedRemovesRepeatsAndKeepsOrder() {
        let list = [MissionStep(kind: .math, amount: 2), .photo, MissionStep(kind: .math, amount: 9)]
        XCTAssertEqual(list.cleaned, [MissionStep(kind: .math, amount: 2), .photo])
    }

    func testCleanedNeverLeavesAnEmptyList() {
        XCTAssertEqual([MissionStep]().cleaned, [.photo])
    }

    func testCleanedPullsAmountsIntoRange() {
        XCTAssertEqual([MissionStep(kind: .steps, amount: 100_000)].cleaned.first?.amount, MissionKind.steps.amountRange.upperBound)
        XCTAssertEqual([MissionStep(kind: .math, amount: 0)].cleaned.first?.amount, MissionKind.math.amountRange.lowerBound)
    }

    func testDefaultsAreInRange() {
        for kind in MissionKind.allCases {
            XCTAssertTrue(kind.amountRange.contains(kind.defaultAmount), kind.rawValue)
        }
        XCTAssertGreaterThan(MissionKind.steps.defaultAmount, 1)
        XCTAssertGreaterThan(MissionKind.squats.defaultAmount, 1)
        XCTAssertGreaterThan(MissionKind.shake.defaultAmount, 1)
        XCTAssertGreaterThan(MissionKind.math.defaultAmount, 1)
    }
}

final class MissionLevelTests: XCTestCase {
    func testLevelsDefaultToTheMiddleOfTheRange() {
        XCTAssertEqual(MissionStep(kind: .math).level, MathLevel.level5.rawValue)
        XCTAssertEqual(MissionStep(kind: .shake).level, 2)
        XCTAssertEqual(MissionStep(kind: .steps).level, 0)
    }

    func testStepSavedByAnOlderBuildGetsTheDefaultLevel() throws {
        let decoded = try JSONDecoder().decode(MissionStep.self, from: Data(#"{"kind":"math","amount":4}"#.utf8))
        XCTAssertEqual(decoded, MissionStep(kind: .math, amount: 4))
    }

    func testLevelKeptThroughSaving() throws {
        let original = MissionStep(kind: .shake, amount: 20, level: 4)
        XCTAssertEqual(try JSONDecoder().decode(MissionStep.self, from: JSONEncoder().encode(original)), original)
    }

    func testCleanedKeepsLevelsAndPullsThemIntoRange() {
        XCTAssertEqual([MissionStep(kind: .math, amount: 2, level: 6)].cleaned.first?.level, 6)
        XCTAssertEqual([MissionStep(kind: .math, amount: 2, level: 99)].cleaned.first?.level, 6)
        XCTAssertEqual([MissionStep(kind: .shake, amount: 20, level: -3)].cleaned.first?.level, 0)
        XCTAssertEqual([MissionStep(kind: .steps, amount: 20, level: 5)].cleaned.first?.level, 0)
    }
}

final class MissionAttemptTests: XCTestCase {
    func testGivesTwentySeconds() {
        let attempt = MissionAttempt(now: 100)
        XCTAssertEqual(attempt.remaining(at: 100), 20)
        XCTAssertEqual(attempt.remaining(at: 112), 8)
        XCTAssertFalse(attempt.timedOut(at: 119.9))
        XCTAssertTrue(attempt.timedOut(at: 120))
    }

    func testInputStartsTheTimeAgain() {
        var attempt = MissionAttempt(now: 100)
        attempt.input(at: 115)
        XCTAssertEqual(attempt.remaining(at: 115), 20)
        XCTAssertFalse(attempt.timedOut(at: 130))
        XCTAssertTrue(attempt.timedOut(at: 135))
    }

    func testNeverGoesBelowZero() {
        XCTAssertEqual(MissionAttempt(now: 0).remaining(at: 500), 0)
    }
}

final class MathProblemTests: XCTestCase {
    func testAnswerFollowsMultiplicationBeforeAddition() {
        let p = MathProblem(first: 12, times: 3, added: [40])
        XCTAssertEqual(p.answer, 76)
        XCTAssertEqual(p.text, "12 × 3 + 40")
    }

    func testAdditionOnly() {
        let p = MathProblem(first: 12, added: [34, 56])
        XCTAssertEqual(p.answer, 102)
        XCTAssertEqual(p.text, "12 + 34 + 56")
    }

    func testRandomProblemsVary() {
        var g = SeededGenerator(seed: 2)
        let problems = (0..<20).map { _ in MathProblem.random(using: &g) }
        XCTAssertGreaterThan(Set(problems.map(\.answer)).count, 5)
    }

    /// Each level as ranges: first, times, then what's added.
    func testEachLevelHasTheRightShape() {
        let shapes: [(MathLevel, ClosedRange<Int>, ClosedRange<Int>?, [ClosedRange<Int>])] = [
            (.level1, 1...9, nil, [1...9]),
            (.level2, 10...99, nil, [1...9]),
            (.level3, 10...99, nil, [10...99]),
            (.level4, 10...99, nil, [10...99, 10...99]),
            (.level5, 10...99, 1...9, [10...99]),
            (.level6, 10...99, 10...99, [100...999]),
            (.level7, 100...999, 10...99, [1000...9999]),
        ]
        var g = SeededGenerator(seed: 4)
        for (level, first, times, added) in shapes {
            for _ in 0..<200 {
                let p = MathProblem.random(level: level, using: &g)
                XCTAssertTrue(first.contains(p.first), "\(level): \(p.text)")
                XCTAssertEqual(p.times == nil, times == nil, "\(level): \(p.text)")
                if let t = p.times, let times { XCTAssertTrue(times.contains(t), "\(level): \(p.text)") }
                XCTAssertEqual(p.added.count, added.count, "\(level): \(p.text)")
                for (number, range) in zip(p.added, added) { XCTAssertTrue(range.contains(number), "\(level): \(p.text)") }
            }
        }
    }

    func testDefaultIsTheFifthLevel() {
        var g = SeededGenerator(seed: 9)
        let p = MathProblem.random(using: &g)
        XCTAssertNotNil(p.times)
        XCTAssertEqual(p.added.count, 1)
    }

    func testEveryLevelHasItsOwnExample() {
        XCTAssertEqual(MathLevel.allCases.count, 7)
        XCTAssertEqual(Set(MathLevel.allCases.map(\.example)).count, 7)
    }
}

final class ShakeCounterTests: XCTestCase {
    /// All three axes swing `size` g, `hz` times a second, read 100 times a second.
    @discardableResult
    private func run(_ counter: inout ShakeCounter, size: Double, hz: Double, seconds: Double, from start: Double = 0) -> Double {
        for i in 0..<Int(seconds * 100) {
            let t = Double(i) / 100
            let value = size * sin(2 * .pi * hz * t)
            counter.add(x: value, y: value, z: value, at: start + t)
        }
        return start + seconds
    }

    private func count(level: Int = ShakeCounter.defaultLevel, size: Double, hz: Double, seconds: Double) -> Int {
        var counter = ShakeCounter(level: level)
        run(&counter, size: size, hz: hz, seconds: seconds)
        return counter.count
    }

    func testCountsRealShakes() {
        XCTAssertTrue((18...26).contains(count(size: 3, hz: 5, seconds: 5)))
    }

    func testIgnoresGentleMovement() {
        XCTAssertEqual(count(size: 0.5, hz: 3, seconds: 5), 0)
    }

    func testNeverCountsMoreThanFiveASecond() {
        XCTAssertLessThanOrEqual(count(size: 4, hz: 20, seconds: 2), 11)
    }

    func testStrengthDecidesWhatCounts() {
        XCTAssertGreaterThan(count(level: 0, size: 1, hz: 5, seconds: 2), 0)
        XCTAssertEqual(count(level: 1, size: 1, hz: 5, seconds: 2), 0)
        XCTAssertGreaterThan(count(level: 3, size: 5, hz: 5, seconds: 2), 0)
        XCTAssertEqual(count(level: 4, size: 1, hz: 5, seconds: 2), 0)
    }

    func testStrengthsAndDefault() {
        XCTAssertEqual(ShakeCounter.levels, [0.25, 0.5, 0.83, 1.15, 1.5])
        XCTAssertEqual(ShakeCounter.levels[ShakeCounter.defaultLevel], 0.83)
    }

    func testPausesAfterThreeIdleSecondsWithoutLosingAnything() {
        var counter = ShakeCounter()
        var t = run(&counter, size: 3, hz: 5, seconds: 2)
        XCTAssertGreaterThan(counter.count, 0)
        t = run(&counter, size: 0, hz: 1, seconds: 2, from: t)
        let done = counter.count
        XCTAssertFalse(counter.isPaused)
        t = run(&counter, size: 0, hz: 1, seconds: 2, from: t)
        XCTAssertTrue(counter.isPaused)
        XCTAssertEqual(counter.pauses, 1)
        XCTAssertEqual(counter.count, done)

        run(&counter, size: 3, hz: 5, seconds: 1, from: t)
        XCTAssertFalse(counter.isPaused)
        XCTAssertGreaterThan(counter.count, done)
    }

    func testBeingStillFromTheStartPausesOnce() {
        var counter = ShakeCounter()
        run(&counter, size: 0, hz: 1, seconds: 10)
        XCTAssertTrue(counter.isPaused)
        XCTAssertEqual(counter.pauses, 1)
        XCTAssertEqual(counter.count, 0)
    }
}

final class WalkCounterTests: XCTestCase {
    /// Moving the way a phone does in a hand or pocket, read 100 times a second.
    @discardableResult
    private func walk(_ counter: inout WalkCounter, seconds: Double, size: Double = 0.3, from start: Double = 0) -> Double {
        for i in 0..<Int(seconds * 100) {
            let t = Double(i) / 100
            counter.add(x: 0, y: -1 + size * sin(2 * .pi * 2 * t), z: 0, at: start + t)
        }
        return start + seconds
    }

    private func shake(_ counter: inout WalkCounter, seconds: Double, from start: Double) -> Double {
        for i in 0..<Int(seconds * 100) {
            let t = Double(i) / 100
            let value = 3 * sin(2 * .pi * 4 * t)
            counter.add(x: value, y: value, z: value, at: start + t)
        }
        return start + seconds
    }

    /// One sharp knock every `gap` seconds, with the phone still in between.
    private func knock(_ counter: inout WalkCounter, every gap: Double, seconds: Double) {
        let samplesPerKnock = Int(gap * 100)
        for i in 0..<Int(seconds * 100) {
            counter.add(x: 0, y: i % samplesPerKnock == 0 ? 0.5 : -1, z: 0, at: Double(i) / 100)
        }
    }

    func testCountsOncePerSecondOfMovement() {
        var counter = WalkCounter()
        walk(&counter, seconds: 10)
        XCTAssertEqual(counter.count, 10)
    }

    func testBeingStillCountsNothing() {
        var counter = WalkCounter()
        walk(&counter, seconds: 10, size: 0)
        XCTAssertEqual(counter.count, 0)
    }

    func testSmallMovementsDoNotCount() {
        var counter = WalkCounter()
        walk(&counter, seconds: 10, size: 0.1)
        XCTAssertEqual(counter.count, 0)
    }

    func testRestingIsNoticedWithoutCostingAnything() {
        var counter = WalkCounter()
        let t = walk(&counter, seconds: 5)
        XCTAssertFalse(counter.isResting)
        let later = walk(&counter, seconds: 4, size: 0, from: t)
        XCTAssertTrue(counter.isResting)
        XCTAssertEqual(counter.rests, 1)
        XCTAssertEqual(counter.count, 5)
        walk(&counter, seconds: 2, from: later)
        XCTAssertFalse(counter.isResting)
        XCTAssertEqual(counter.count, 7)
    }

    func testShakingFreezesThenCostsTenThenCarriesOn() {
        var counter = WalkCounter()
        var t = walk(&counter, seconds: 20)
        t = shake(&counter, seconds: 1.5, from: t)
        XCTAssertTrue(counter.isFrozen)
        XCTAssertEqual(counter.freezes, 1)
        let frozenCount = counter.count
        XCTAssertGreaterThanOrEqual(frozenCount, 20)

        t = walk(&counter, seconds: 2, from: t)
        XCTAssertEqual(counter.count, frozenCount - 10, "The cost comes a second after freezing")
        XCTAssertFalse(counter.isFrozen)
        walk(&counter, seconds: 3, from: t)
        XCTAssertEqual(counter.count, frozenCount - 7)
    }

    func testCostNeverGoesBelowZero() {
        var counter = WalkCounter()
        var t = walk(&counter, seconds: 3)
        t = shake(&counter, seconds: 1.5, from: t)
        walk(&counter, seconds: 2, from: t)
        XCTAssertEqual(counter.freezes, 1)
        XCTAssertEqual(counter.count, 0)
    }

    func testTenKnocksInThreeSecondsIsCheating() {
        var counter = WalkCounter()
        knock(&counter, every: 0.2, seconds: 2.1)
        XCTAssertEqual(counter.freezes, 1)
    }

    func testOccasionalKnocksAreFine() {
        var counter = WalkCounter()
        knock(&counter, every: 0.4, seconds: 12)
        XCTAssertEqual(counter.freezes, 0)
    }

    func testOneLongPushIsOneKnock() {
        var counter = WalkCounter()
        for i in 0..<300 {
            let value = Double(i) * 0.5
            counter.add(x: value, y: value, z: value, at: Double(i) / 100)
        }
        XCTAssertEqual(counter.freezes, 0)
    }
}

final class SquatRepDetectorTests: XCTestCase {
    /// One squat: down (accelerating, then braking), up (accelerating, then braking).
    private func feed(_ counter: inout SquatRepDetector, reps: Int, seconds: Double, strength: Double, from start: Double = 0) -> Double {
        let samples = Int(Double(reps) * seconds * 50)
        for i in 0..<samples {
            let t = Double(i) / 50
            counter.add(verticalAcceleration: -strength * cos(2 * .pi * t / seconds), at: start + t)
        }
        return start + Double(samples) / 50
    }

    private func rest(_ counter: inout SquatRepDetector, seconds: Double, from start: Double) -> Double {
        for i in 0..<Int(seconds * 50) { counter.add(verticalAcceleration: 0, at: start + Double(i) / 50) }
        return start + seconds
    }

    func testCountsSteadySquats() {
        var counter = SquatRepDetector()
        _ = feed(&counter, reps: 10, seconds: 2.5, strength: 0.3)
        XCTAssertEqual(counter.count, 10)
    }

    func testCountsSlowSquats() {
        var counter = SquatRepDetector()
        _ = feed(&counter, reps: 5, seconds: 5, strength: 0.15)
        XCTAssertEqual(counter.count, 5)
    }

    func testCountsSquatsWithRestsBetween() {
        var counter = SquatRepDetector()
        var t = 0.0
        for _ in 0..<4 {
            t = feed(&counter, reps: 1, seconds: 2.5, strength: 0.3, from: t)
            t = rest(&counter, seconds: 3, from: t)
        }
        XCTAssertEqual(counter.count, 4)
    }

    func testIgnoresSmallMovements() {
        var counter = SquatRepDetector()
        _ = feed(&counter, reps: 10, seconds: 2.5, strength: 0.03)
        XCTAssertEqual(counter.count, 0)
    }

    func testIgnoresFastWiggling() {
        var counter = SquatRepDetector()
        _ = feed(&counter, reps: 30, seconds: 0.3, strength: 1)
        XCTAssertEqual(counter.count, 0)
    }

    func testBeingStillCountsNothing() {
        var counter = SquatRepDetector()
        _ = rest(&counter, seconds: 30, from: 0)
        XCTAssertEqual(counter.count, 0)
    }

    func testAPartLeftHangingDoesNotJoinALaterMove() {
        var counter = SquatRepDetector()
        for i in 0..<50 {
            let t = Double(i) / 50
            counter.add(verticalAcceleration: -0.3 * sin(.pi * t), at: t)
        }
        let t = rest(&counter, seconds: 20, from: 1)
        for i in 0..<100 {
            let u = Double(i) / 50
            counter.add(verticalAcceleration: 0.3 * sin(.pi * u), at: t + u)
        }
        XCTAssertEqual(counter.count, 0)
    }
}

final class SquatCounterTests: XCTestCase {
    /// Squats with the phone at `y` and `z`, 50 readings a second. `size` is how hard, in g.
    private func squats(_ counter: inout SquatCounter, seconds: Double, size: Double, period: Double = 2,
                        y: Double = -0.9, z: Double = -0.3, rotation: (Double) -> Double = { _ in 0.3 }) {
        for i in 0..<Int(seconds * 50) {
            let t = Double(i) / 50
            let push = -size * cos(2 * .pi * t / period)
            counter.add(x: 0, y: y + push * 0.95, z: z + push * 0.3, rotation: rotation(t), verticalAcceleration: push, at: t)
        }
    }

    func testHardSquatsCountOncePerTwoSeconds() {
        var counter = SquatCounter()
        squats(&counter, seconds: 10, size: 0.6)
        XCTAssertEqual(counter.windows, 5)
        XCTAssertEqual(counter.count, 5)
        XCTAssertEqual(counter.misses, 0)
    }

    func testNeverMoreThanOneEveryTwoSeconds() {
        var counter = SquatCounter()
        squats(&counter, seconds: 10, size: 0.6, period: 1)
        XCTAssertLessThanOrEqual(counter.count, 5)
    }

    func testGentleButCompleteSquatsStillCount() {
        var counter = SquatCounter()
        squats(&counter, seconds: 12.5, size: 0.15, period: 2.5)
        XCTAssertGreaterThanOrEqual(counter.count, 3)
        XCTAssertLessThanOrEqual(counter.count, 5)
    }

    func testPhoneFlatInBedCountsNothing() {
        var counter = SquatCounter()
        squats(&counter, seconds: 20, size: 0.6, y: 0, z: -1)
        XCTAssertEqual(counter.windows, 10)
        XCTAssertEqual(counter.count, 0)
    }

    func testPhoneUpsideDownCountsNothing() {
        var counter = SquatCounter()
        squats(&counter, seconds: 20, size: 0.6, y: 0.9, z: -0.3)
        XCTAssertEqual(counter.count, 0)
    }

    func testTwistingThePhoneCountsNothing() {
        var counter = SquatCounter()
        squats(&counter, seconds: 20, size: 0.6, rotation: { sin(8 * $0) > 0 ? 4 : 0 })
        XCTAssertEqual(counter.count, 0)
        XCTAssertGreaterThan(counter.misses, 0)
    }

    func testBeingStillCountsNothingAndIsNotAMiss() {
        var counter = SquatCounter()
        squats(&counter, seconds: 20, size: 0, rotation: { _ in 0 })
        XCTAssertEqual(counter.count, 0)
        XCTAssertEqual(counter.misses, 0)
        XCTAssertEqual(counter.lastWindow?.score, 0)
    }

    func testRuleScores() {
        XCTAssertEqual(SquatCounter.ruleScore(meanY: -0.9, meanZ: -0.3, accelerationSpread: 0.3, rotationSpread: 0.5), 0.7)
        XCTAssertEqual(SquatCounter.ruleScore(meanY: -0.9, meanZ: -0.3, accelerationSpread: 0.28, rotationSpread: 0.5), 0.2)
        XCTAssertEqual(SquatCounter.ruleScore(meanY: -0.2, meanZ: -0.3, accelerationSpread: 0.3, rotationSpread: 0.5), 0.2)
        XCTAssertEqual(SquatCounter.ruleScore(meanY: -0.9, meanZ: 0, accelerationSpread: 0.3, rotationSpread: 0.5), 0.2)
        XCTAssertEqual(SquatCounter.ruleScore(meanY: -0.9, meanZ: -0.3, accelerationSpread: 0.3, rotationSpread: 1.2), 0.2)
        XCTAssertEqual(SquatCounter.ruleScore(meanY: 0, meanZ: 0, accelerationSpread: 0.2, rotationSpread: 0.05), 0)
    }
}

final class MissionStuckTrackerTests: XCTestCase {
    func testStuckAfterTwoMinutesOfMissionTime() {
        var tracker = MissionStuckTracker()
        tracker.add(119, to: .squats)
        XCTAssertFalse(tracker.isStuck(.squats))
        tracker.add(1, to: .squats)
        XCTAssertTrue(tracker.isStuck(.squats))
    }

    func testTimeAddsUpAcrossTries() {
        var tracker = MissionStuckTracker()
        for _ in 0..<6 { tracker.add(20, to: .shake) }
        XCTAssertTrue(tracker.isStuck(.shake))
    }

    func testCountingStartsTheTimeAgain() {
        var tracker = MissionStuckTracker()
        tracker.add(119, to: .steps)
        tracker.counted(1, for: .steps)
        tracker.add(119, to: .steps)
        XCTAssertFalse(tracker.isStuck(.steps))
    }

    /// One shake now and then, with the count starting over each try, must not hide the way out.
    func testARareCountThatNeverGetsFurtherStillEndsUpStuck() {
        var tracker = MissionStuckTracker()
        tracker.counted(1, for: .shake)
        for _ in 0..<6 {
            tracker.add(20, to: .shake)
            tracker.counted(1, for: .shake)
        }
        XCTAssertTrue(tracker.isStuck(.shake))
    }

    func testEachMissionIsTrackedSeparately() {
        var tracker = MissionStuckTracker()
        tracker.add(120, to: .steps)
        XCTAssertTrue(tracker.isStuck(.steps))
        XCTAssertFalse(tracker.isStuck(.squats))
    }

    func testTimeNeverRunsBackwards() {
        var tracker = MissionStuckTracker()
        tracker.add(120, to: .steps)
        tracker.add(-500, to: .steps)
        XCTAssertTrue(tracker.isStuck(.steps))
    }
}
