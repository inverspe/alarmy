import XCTest

/// Runs the real app on a simulated iPhone. The simulator has no motion sensors or camera,
/// so counts come from a stand-in and photos aren't taken, and sound isn't checked.
final class AlarmyUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(ring: String? = "now", missions: String = "photo", sensor: String = "count",
                        wakeCheck: Int = 0, ringAfter: Int = 1, gentle: Int = 0) {
        app = XCUIApplication()
        var environment = ["ALARMY_UITEST_SENSOR": sensor]
        if let ring {
            environment["ALARMY_UITEST_RING"] = ring
            environment["ALARMY_UITEST_MISSIONS"] = missions
            environment["ALARMY_UITEST_WAKE_CHECK"] = String(wakeCheck)
            environment["ALARMY_UITEST_RING_AFTER"] = String(ringAfter)
            environment["ALARMY_UITEST_GENTLE"] = String(gentle)
        }
        app.launchEnvironment = environment
        app.launch()
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func expect(_ text: String, within timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: timeout), "Never saw: \(text)", file: file, line: line)
    }

    /// Reads the sum on screen and types the answer, or a wrong one.
    private func answerSum(correctly: Bool = true, file: StaticString = #filePath, line: UInt = #line) {
        let problem = app.staticTexts["math-problem"]
        XCTAssertTrue(problem.waitForExistence(timeout: 10), "No sum on screen", file: file, line: line)
        let numbers = problem.label.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }
        XCTAssertEqual(numbers.count, 3, "Couldn't read: \(problem.label)", file: file, line: line)
        let answer = numbers[0] * numbers[1] + numbers[2] + (correctly ? 0 : 1)
        for digit in String(answer) { app.buttons[String(digit)].tap() }
        app.buttons["OK"].tap()
    }

    /// Does math:2, steps:10, squats:5, shake:10, as far as the keep-ringing countdown.
    private func doFullStack(screenshots: Bool) {
        expect("Mission 1 of 4")
        expect("Sum 1 of 2")
        if screenshots { shot("math") }
        answerSum()
        expect("Sum 2 of 2")
        answerSum()
        expect("Mission 2 of 4")
        expect("Start walking")
        if screenshots { shot("steps") }
        expect("Mission 3 of 4", within: 25)
        expect("Do your squats")
        if screenshots { shot("squats") }
        expect("Mission 4 of 4", within: 25)
        expect("Shake your phone")
        if screenshots { shot("shake") }
        expect("Mission done ✓", within: 25)
    }

    func testFullMorningWithAMissedCheck() {
        launch(missions: "math:2,steps:10,squats:5,shake:10", wakeCheck: 1, gentle: 30)
        doFullStack(screenshots: true)
        shot("countdown")

        expect("Ring's over", within: 70)
        shot("check-waiting")
        expect("Still up?", within: 70)
        shot("check-prompt")

        // Not answering: the alarm and every mission start over after 100 seconds.
        let promptAppeared = Date()
        expect("You missed your check", within: 110)
        let waited = Date().timeIntervalSince(promptAppeared)
        XCTAssertGreaterThan(waited, 90, "Started over too soon")
        shot("missed-check")

        doFullStack(screenshots: false)
        expect("Ring's over", within: 70)
        expect("Still up?", within: 70)
        app.buttons["Yes, I'm up"].tap()
        expect("Alarms")
        shot("finished")
    }

    func testWrongAnswerGetsANewSumAndDoesNotCount() {
        launch(missions: "math:2")
        expect("Sum 1 of 2")
        let first = app.staticTexts["math-problem"].label
        answerSum(correctly: false)
        expect("Not quite. Here's a new one.")
        shot("math-wrong")
        expect("Sum 1 of 2")
        XCTAssertNotEqual(app.staticTexts["math-problem"].label, first, "Same sum after a wrong answer")
        answerSum()
        expect("Sum 2 of 2")
    }

    func testPhotoMissionScreenInAStack() {
        launch(missions: "photo,math:1")
        expect("Mission 1 of 2")
        expect("Go find")
        expect("Test object")
        XCTAssertTrue(app.buttons["Open camera"].exists)
        shot("photo-ringing")
    }

    func testPhotoOnlyAlarmIsTheSameAsBefore() {
        launch(missions: "photo")
        expect("Go find")
        XCTAssertFalse(app.staticTexts["Mission 1 of 1"].exists)
    }

    func testNoSensorSwapsToSums() {
        launch(missions: "steps:10", sensor: "none")
        let swap = app.buttons["This can't be counted. Do sums instead"]
        XCTAssertTrue(swap.waitForExistence(timeout: 10), "No way to finish without a sensor")
        shot("sensor-unavailable")
        swap.tap()
        expect("Sum 1 of 5")
        for sum in 2...5 {
            answerSum()
            expect("Sum \(sum) of 5")
        }
        answerSum()
        expect("Mission done ✓")
    }

    func testStuckSensorOffersSumsAfterTwoMinutes() {
        launch(missions: "squats:5", sensor: "stuck")
        expect("Do your squats")
        let swap = app.buttons["Not counting? Do sums instead"]
        XCTAssertFalse(swap.exists, "Offered sums straight away")
        XCTAssertTrue(swap.waitForExistence(timeout: 130), "Never offered a way out")
        shot("sensor-stuck")
    }

    func testClosingTheAppKeepsYourPlaceButRestartsTheCount() {
        launch(missions: "math:1,steps:10", sensor: "stuck")
        expect("Sum 1 of 1")
        answerSum()
        expect("Mission 2 of 2")
        app.terminate()

        launch(ring: nil, sensor: "stuck")
        expect("Mission 2 of 2")
        expect("Start walking")
        let count = app.descendants(matching: .any)["mission-count"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        XCTAssertTrue(count.label.hasPrefix("0"), "Count was: \(count.label)")
        shot("after-relaunch")
    }

    func testEarlyClearCanBeBackedOutOfThenFinishes() {
        launch(ring: "soon", missions: "math:1")
        let clear = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Up early?'")).firstMatch
        XCTAssertTrue(clear.waitForExistence(timeout: 10), "No early clear offered")
        clear.tap()
        expect("Sum 1 of 1")
        shot("early-clear")
        app.buttons["Not now"].tap()
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        clear.tap()
        answerSum()
        expect("Alarms")
        XCTAssertFalse(clear.exists, "Could clear the same alarm twice")
    }

    func testMissionListEditor() {
        launch(ring: "later")
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'rings'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()

        let add = app.buttons["Add mission"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        scrollTo(add)
        XCTAssertFalse(app.buttons["Remove Photo"].isEnabled, "Could remove the only mission")
        shot("editor-photo-only")

        add.tap()
        app.buttons["Steps"].firstMatch.tap()
        expectAmount("50 steps")
        scrollTo(add)
        add.tap()
        app.buttons["Math"].firstMatch.tap()
        expectAmount("3 sums")
        shot("editor-three-missions")

        let stepsAmount = app.steppers["50 steps"]
        scrollTo(stepsAmount)
        stepsAmount.buttons["Increment"].tap()
        expectAmount("60 steps")

        let mathUp = app.buttons["Move Math up"]
        scrollTo(mathUp)
        mathUp.tap()
        XCTAssertFalse(app.buttons["Move Photo up"].isEnabled, "Photo should still be first")
        shot("editor-reordered")

        let removePhoto = app.buttons["Remove Photo"]
        scrollTo(removePhoto)
        removePhoto.tap()
        expect("Without a photo mission, you could finish this alarm from bed.")
        XCTAssertFalse(app.buttons["Remove Photo"].exists)
        shot("editor-no-photo")

        let save = app.buttons["Save alarm"]
        scrollTo(save)
        shot("editor-bottom")
        save.tap()

        // Saved and still there when reopened.
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        expectAmount("3 sums")
        expectAmount("60 steps")
        XCTAssertTrue(app.buttons["Remove Math"].exists)
        XCTAssertFalse(app.buttons["Remove Photo"].exists)
        shot("editor-reopened")
    }

    /// An amount is the label of its stepper, not separate text.
    private func expectAmount(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.steppers[text].waitForExistence(timeout: 5), "Never saw: \(text)", file: file, line: line)
    }

    /// The target may be above or below what's on screen.
    private func scrollTo(_ element: XCUIElement) {
        for _ in 0..<5 where !element.isHittable { app.swipeUp(velocity: .slow) }
        for _ in 0..<8 where !element.isHittable { app.swipeDown(velocity: .slow) }
        XCTAssertTrue(element.isHittable, "Couldn't reach \(element)")
    }
}
