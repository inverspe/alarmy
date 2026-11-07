import XCTest

/// Runs the real app on a simulated iPhone. The simulator has no motion sensors or camera,
/// so counts come from a stand-in and photos aren't taken, and sound isn't checked.
final class AlarmyUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(ring: String? = "now", missions: String = "photo", sensor: String = "count",
                        wakeCheck: Int = 0, ringAfter: Int = 1, gentle: Int = 0, twoFinger: Bool = false,
                        snooze: String? = nil, voice: Bool = false, scans: String? = nil) {
        app = XCUIApplication()
        var environment = ["ALARMY_UITEST_SENSOR": sensor]
        if twoFinger { environment["ALARMY_UITEST_TWO_FINGER"] = "1" }
        if let snooze { environment["ALARMY_UITEST_SNOOZE"] = snooze }
        if voice { environment["ALARMY_UITEST_VOICE"] = "1" }
        if let scans { environment["ALARMY_UITEST_SCANS"] = scans }
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
        let text = problem.label
        let numbers = text.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }
        XCTAssertGreaterThanOrEqual(numbers.count, 2, "Couldn't read: \(text)", file: file, line: line)
        let sum = text.contains("×")
            ? numbers[0] * numbers[1] + numbers.dropFirst(2).reduce(0, +)
            : numbers.reduce(0, +)
        let answer = sum + (correctly ? 0 : 1)
        for digit in String(answer) { app.buttons[String(digit)].tap() }
        app.buttons["OK"].tap()
    }

    private func startMission(file: StaticString = #filePath, line: UInt = #line) {
        let start = app.buttons["Start mission"]
        XCTAssertTrue(start.waitForExistence(timeout: 10), "No way to start the mission", file: file, line: line)
        start.tap()
    }

    /// Does math:2, steps:10, squats:5, shake:10, as far as the keep-ringing countdown.
    private func doFullStack(screenshots: Bool) {
        expect("Mission 1 of 4")
        expect("Your mission")
        if screenshots { shot("ring-screen") }
        startMission()
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

    func testWrongAnswerKeepsTheSameSumAndDoesNotCount() {
        launch(missions: "math:2")
        startMission()
        expect("Sum 1 of 2")
        let first = app.staticTexts["math-problem"].label
        answerSum(correctly: false)
        expect("Not quite. Try again.")
        shot("math-wrong")
        expect("Sum 1 of 2")
        XCTAssertEqual(app.staticTexts["math-problem"].label, first, "A different sum after a wrong answer")
        sleep(1)
        answerSum()
        expect("Sum 2 of 2")
    }

    func testHardestSumsCanBeAnswered() {
        launch(missions: "math:1:6")
        startMission()
        expect("Sum 1 of 1")
        XCTAssertTrue(app.staticTexts["math-problem"].label.contains("×"))
        shot("math-hardest")
        answerSum()
        expect("Mission done ✓")
    }

    func testAddingSumsCanBeAnswered() {
        launch(missions: "math:1:3")
        startMission()
        expect("Sum 1 of 1")
        XCTAssertFalse(app.staticTexts["math-problem"].label.contains("×"))
        shot("math-adding")
        answerSum()
        expect("Mission done ✓")
    }

    /// With nothing happening, the mission closes after 20 seconds and the sound comes back.
    func testRunningOutOfTimeStartsTheMissionsOver() {
        launch(missions: "math:1,shake:10", sensor: "stuck")
        startMission()
        expect("Sum 1 of 1")
        answerSum()
        expect("Mission 2 of 2")
        expect("Shake your phone")
        let opened = Date()
        XCTAssertTrue(app.buttons["Turn sound on"].exists, "Sound should be off during a mission")
        shot("mission-quiet")

        expect("Out of time. Start again.", within: 25)
        XCTAssertGreaterThan(Date().timeIntervalSince(opened), 15, "Closed too soon")
        expect("Mission 1 of 2")
        shot("mission-timed-out")

        startMission()
        expect("Sum 1 of 1")
    }

    func testSoundCanBeSwitchedDuringAMission() {
        launch(missions: "math:1")
        startMission()
        let on = app.buttons["Turn sound on"]
        XCTAssertTrue(on.waitForExistence(timeout: 5))
        on.tap()
        let off = app.buttons["Turn sound off"]
        XCTAssertTrue(off.waitForExistence(timeout: 5))
        off.tap()
        XCTAssertTrue(on.waitForExistence(timeout: 5))
    }

    func testTypingKeepsTheMissionOpen() {
        launch(missions: "math:1")
        startMission()
        expect("Sum 1 of 1")
        for _ in 0..<5 {
            sleep(5)
            app.buttons["1"].tap()
        }
        XCTAssertFalse(app.staticTexts["Out of time. Start again."].exists)
        XCTAssertTrue(app.staticTexts["math-problem"].exists)
    }

    // MARK: Snooze

    func testSnoozeStopsTheRingThenItComesBack() {
        launch(missions: "math:1", snooze: "1:2")
        let first = app.buttons["Snooze 1 min, 2 left"]
        XCTAssertTrue(first.waitForExistence(timeout: 10), "No snooze button")
        shot("snooze-button")
        first.tap()
        expect("Snoozed")
        expect("1 snooze left")
        shot("snoozed")

        expect("Your mission", within: 70)
        let second = app.buttons["Snooze 1 min, 1 left"]
        XCTAssertTrue(second.exists, "Snoozes didn't count down")
        second.tap()
        expect("No snoozes left")

        expect("Your mission", within: 70)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Snooze'")).firstMatch.exists, "Could snooze past the limit")
        shot("snooze-used-up")
    }

    func testNotWaitingForTheSnoozeGoesToTheMission() {
        launch(missions: "math:1", snooze: "5:3")
        let snooze = app.buttons["Snooze 5 min, 3 left"]
        XCTAssertTrue(snooze.waitForExistence(timeout: 10))
        snooze.tap()
        expect("Snoozed")
        app.buttons["Do my mission now"].tap()
        expect("Sum 1 of 1")
        answerSum()
        expect("Mission done ✓")
    }

    func testNoSnoozeUnlessItIsTurnedOn() {
        launch(missions: "math:1")
        expect("Your mission")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Snooze'")).firstMatch.exists)
    }

    // MARK: Voice

    func testSpeakingDoesNotGetInTheWay() {
        launch(missions: "math:1", voice: true)
        expect("Your mission")
        expect("Test label")
        shot("ring-with-label")
        sleep(35)
        XCTAssertTrue(app.buttons["Start mission"].exists, "Ring screen went away while speaking")
        startMission()
        expect("Sum 1 of 1")
        answerSum()
        expect("Mission done ✓")
    }

    // MARK: Typing

    func testTypingMissionNeedsTheExactSentence() {
        launch(missions: "typing:1:0")
        startMission()
        let target = app.staticTexts["typing-target"]
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        let sentence = target.label
        let entry = app.textFields["typing-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        shot("typing")
        entry.tap()
        entry.typeText("x")
        app.buttons["Check"].tap()
        expect("Not quite. Check it and try again.")
        shot("typing-wrong")
        XCTAssertEqual(target.label, sentence, "A different sentence after a wrong one")
        entry.typeText(XCUIKeyboardKey.delete.rawValue)
        entry.typeText(sentence)
        app.buttons["Check"].tap()
        expect("Mission done ✓", within: 10)
    }

    // MARK: Memory

    func testMemoryMissionFindsTheTiles() {
        launch(missions: "memory:2:0")
        startMission()
        for round in 1...2 {
            expect("Round \(round) of 2")
            if round == 1 { shot("memory-waiting") }
            expect("Now find them", within: 6)
            sleep(1)
            let tiles = (0..<9).map { app.buttons["tile-\($0)"] }
            let targets = tiles.filter { ($0.value as? String) == "target" }
            XCTAssertEqual(targets.count, 3)
            if round == 1 {
                tiles.first { ($0.value as? String) == "other" }?.tap()
                shot("memory-wrong")
                sleep(1)
            }
            targets.forEach { $0.tap() }
            sleep(1)
        }
        expect("Mission done ✓", within: 10)
    }

    func testBiggestMemoryGridFits() {
        launch(missions: "memory:1:4")
        startMission()
        expect("Now find them", within: 6)
        XCTAssertTrue(app.buttons["tile-48"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tile-48"].isHittable, "Bottom corner is off the screen")
        shot("memory-biggest")
    }

    // MARK: Barcode

    func testBarcodeMissionOnlyTakesTheRightCode() {
        launch(missions: "barcode", scans: "WRONG-CODE,RIGHT-CODE")
        expect("Scan Test code")
        startMission()
        expect("That's not the right barcode.", within: 6)
        shot("barcode-wrong")
        expect("Mission done ✓", within: 10)
    }

    func testAddingABarcode() {
        launch(ring: "later", scans: "NEW-CODE")
        app.tabBars.buttons["Objects"].tap()
        let add = app.buttons["Add barcode"]
        scrollTo(add)
        add.tap()
        expect("Found NEW-CODE", within: 6)
        let name = app.textFields["barcode-name"]
        name.tap()
        name.typeText("Toothpaste")
        shot("barcode-add")
        app.buttons["Save barcode"].tap()
        expect("Toothpaste")
        shot("barcodes-list")
    }

    func testSettingsHasTheTimeLimitAndSentences() {
        launch(ring: "later")
        app.tabBars.buttons["Settings"].tap()
        expect("Mission time limit")
        XCTAssertTrue(app.buttons["My own sentences"].exists)
        shot("settings")
    }

    func testSquatsStartWithTwoFingers() {
        launch(missions: "squats:5", sensor: "stuck", twoFinger: true)
        startMission()
        expect("Do your squats")
        expect("Hold two fingers on the circles to start")
        XCTAssertFalse(app.descendants(matching: .any)["mission-count"].exists, "Counting before the fingers are down")
        shot("squats-two-fingers")
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
        startMission()
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

    /// Each try closes after 20 seconds, so the two minutes add up across tries.
    func testStuckSensorOffersSumsAfterTwoMinutes() {
        launch(missions: "squats:5", sensor: "stuck")
        startMission()
        expect("Do your squats")
        let swap = app.buttons["Not counting? Do sums instead"]
        XCTAssertFalse(swap.exists, "Offered sums straight away")
        let start = app.buttons["Start mission"]
        let began = Date()
        while !swap.exists && Date().timeIntervalSince(began) < 170 {
            if start.waitForExistence(timeout: 3) { start.tap() }
        }
        XCTAssertTrue(swap.exists, "Never offered a way out")
        XCTAssertGreaterThan(Date().timeIntervalSince(began), 100, "Offered sums too soon")
        shot("sensor-stuck")
        swap.tap()
        expect("Sum 1 of 5")
    }

    func testClosingTheAppKeepsYourPlaceButRestartsTheCount() {
        launch(missions: "math:1,steps:10", sensor: "stuck")
        startMission()
        expect("Sum 1 of 1")
        answerSum()
        expect("Mission 2 of 2")
        app.terminate()

        launch(ring: nil, sensor: "stuck")
        expect("Mission 2 of 2")
        startMission()
        expect("Start walking")
        let count = app.descendants(matching: .any)["mission-count"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        XCTAssertTrue(count.label.hasPrefix("0"), "Count was: \(count.label)")
        shot("after-relaunch")
    }

    /// A dialog here would cover the alarm screens. iOS only ever asks once per install, and
    /// no earlier test (tests run alphabetically) finishes a counted mission, so it's still unanswered.
    func testCountingMissionDoesNotAskForMotionAccess() {
        launch(missions: "shake:10")
        startMission()
        expect("Mission done ✓", within: 25)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertFalse(springboard.alerts.firstMatch.waitForExistence(timeout: 5), "A permission dialog covered the alarm")
        shot("no-motion-dialog")
    }

    func testEarlyClearCanBeBackedOutOfThenFinishes() {
        launch(ring: "soon", missions: "math:1")
        let clear = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Up early?'")).firstMatch
        XCTAssertTrue(clear.waitForExistence(timeout: 10), "No early clear offered")
        clear.tap()
        startMission()
        expect("Sum 1 of 1")
        shot("early-clear")
        app.buttons["Not now"].tap()
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        clear.tap()
        startMission()
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
        expect("Difficulty")
        shot("editor-three-missions")
        XCTAssertTrue(app.switches["Vibrate"].exists, "No vibrate setting")
        XCTAssertTrue(app.switches["Quiet during missions"].exists, "No quiet setting")
        XCTAssertTrue(app.switches["Snooze"].exists, "No snooze setting")
        XCTAssertTrue(app.switches["Say the time"].exists, "No voice setting")
        XCTAssertTrue(app.switches["Say the weather"].exists, "No weather setting")

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
        for _ in 0..<8 where !element.isHittable { app.swipeUp(velocity: .slow) }
        for _ in 0..<12 where !element.isHittable { app.swipeDown(velocity: .slow) }
        XCTAssertTrue(element.isHittable, "Couldn't reach \(element)")
    }
}
