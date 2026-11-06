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

final class MathProblemTests: XCTestCase {
    func testAnswerFollowsMultiplicationBeforeAddition() {
        let p = MathProblem(a: 12, b: 3, c: 40)
        XCTAssertEqual(p.answer, 76)
        XCTAssertEqual(p.text, "12 × 3 + 40")
    }

    func testRandomProblemsVary() {
        var g = SeededGenerator(seed: 2)
        let problems = (0..<20).map { _ in MathProblem.random(using: &g) }
        XCTAssertGreaterThan(Set(problems.map(\.answer)).count, 5)
    }

    func testRandomProblemsStayDoableHalfAsleep() {
        var g = SeededGenerator(seed: 4)
        for _ in 0..<200 {
            let p = MathProblem.random(using: &g)
            XCTAssertTrue((11...29).contains(p.a))
            XCTAssertTrue((2...9).contains(p.b))
            XCTAssertTrue((10...99).contains(p.c))
        }
    }
}

final class ShakeCounterTests: XCTestCase {
    /// `hz` shakes a second at `strength` g, sampled at 50 Hz.
    private func count(strength: Double, hz: Double, seconds: Double) -> Int {
        var counter = ShakeCounter()
        for i in 0..<Int(seconds * 50) {
            let t = Double(i) / 50
            counter.add(acceleration: abs(strength * sin(.pi * hz * t)), at: t)
        }
        return counter.count
    }

    func testCountsRealShakes() {
        XCTAssertEqual(count(strength: 3, hz: 3, seconds: 5), 15)
    }

    func testIgnoresGentleMovement() {
        XCTAssertEqual(count(strength: 0.6, hz: 3, seconds: 5), 0)
    }

    func testOneLongPushIsOneShake() {
        var counter = ShakeCounter()
        for i in 0..<100 { counter.add(acceleration: 3, at: Double(i) / 50) }
        XCTAssertEqual(counter.count, 1)
    }

    func testVibrationIsNotManyShakes() {
        XCTAssertLessThanOrEqual(count(strength: 3, hz: 25, seconds: 1), 8)
    }
}

final class SquatCounterTests: XCTestCase {
    /// One squat: down (accelerating, then braking), up (accelerating, then braking).
    private func feed(_ counter: inout SquatCounter, reps: Int, seconds: Double, strength: Double, from start: Double = 0) -> Double {
        let samples = Int(Double(reps) * seconds * 50)
        for i in 0..<samples {
            let t = Double(i) / 50
            counter.add(verticalAcceleration: -strength * cos(2 * .pi * t / seconds), at: start + t)
        }
        return start + Double(samples) / 50
    }

    private func rest(_ counter: inout SquatCounter, seconds: Double, from start: Double) -> Double {
        for i in 0..<Int(seconds * 50) { counter.add(verticalAcceleration: 0, at: start + Double(i) / 50) }
        return start + seconds
    }

    func testCountsSteadySquats() {
        var counter = SquatCounter()
        _ = feed(&counter, reps: 10, seconds: 2.5, strength: 0.3)
        XCTAssertEqual(counter.count, 10)
    }

    func testCountsSlowSquats() {
        var counter = SquatCounter()
        _ = feed(&counter, reps: 5, seconds: 5, strength: 0.15)
        XCTAssertEqual(counter.count, 5)
    }

    func testCountsSquatsWithRestsBetween() {
        var counter = SquatCounter()
        var t = 0.0
        for _ in 0..<4 {
            t = feed(&counter, reps: 1, seconds: 2.5, strength: 0.3, from: t)
            t = rest(&counter, seconds: 3, from: t)
        }
        XCTAssertEqual(counter.count, 4)
    }

    func testIgnoresSmallMovements() {
        var counter = SquatCounter()
        _ = feed(&counter, reps: 10, seconds: 2.5, strength: 0.03)
        XCTAssertEqual(counter.count, 0)
    }

    func testIgnoresFastWiggling() {
        var counter = SquatCounter()
        _ = feed(&counter, reps: 30, seconds: 0.3, strength: 1)
        XCTAssertEqual(counter.count, 0)
    }

    func testBeingStillCountsNothing() {
        var counter = SquatCounter()
        _ = rest(&counter, seconds: 30, from: 0)
        XCTAssertEqual(counter.count, 0)
    }

    func testAPartLeftHangingDoesNotJoinALaterMove() {
        var counter = SquatCounter()
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
