import XCTest
@testable import AlarmyCore

final class AudioRouteTests: XCTestCase {
    func testPhoneSpeakerNeedsNoOverride() {
        XCTAssertFalse(AudioRoute.shouldForceSpeaker(outputs: ["Speaker"], alreadyForced: false))
    }

    func testBluetoothEarbudsForceTheSpeaker() {
        XCTAssertTrue(AudioRoute.shouldForceSpeaker(outputs: ["BluetoothA2DPOutput"], alreadyForced: false))
    }

    func testWiredHeadphonesForceTheSpeaker() {
        XCTAssertTrue(AudioRoute.shouldForceSpeaker(outputs: ["Headphones"], alreadyForced: false))
    }

    func testEarpieceForcesTheSpeaker() {
        XCTAssertTrue(AudioRoute.shouldForceSpeaker(outputs: ["Receiver"], alreadyForced: false))
    }

    func testUnknownRouteStaysOnThePlainSession() {
        XCTAssertFalse(AudioRoute.shouldForceSpeaker(outputs: [], alreadyForced: false))
    }

    func testSpeakerAlongsideAnotherOutputNeedsNoOverride() {
        XCTAssertFalse(AudioRoute.shouldForceSpeaker(outputs: ["Speaker", "HDMI"], alreadyForced: false))
    }

    /// Once forced, the route reads "Speaker". Going by that alone would drop back to the
    /// earbuds and flip between the two for the rest of the ring.
    func testStaysForcedOnceTheRouteReadsSpeaker() {
        XCTAssertTrue(AudioRoute.shouldForceSpeaker(outputs: ["Speaker"], alreadyForced: true))
    }
}

final class BackupCopyTests: XCTestCase {
    func testFirstBackupKeepsThePlainTitle() {
        XCTAssertEqual(BackupCopy.title(at: 0), "Alarm")
    }

    func testTitleChangesFromOneBackupToTheNext() {
        XCTAssertNotEqual(BackupCopy.title(at: 0), BackupCopy.title(at: 1))
    }

    func testTitlesWrapAroundForLongPlans() {
        XCTAssertEqual(BackupCopy.title(at: BackupPlanner.perOccurrenceMax), BackupCopy.title(at: BackupPlanner.perOccurrenceMax % BackupCopy.titles.count))
        XCTAssertFalse(BackupCopy.title(at: BackupPlanner.budget).isEmpty)
    }
}

final class AppClosedNoticeTests: XCTestCase {
    /// `add` hands the request over asynchronously, so a process that exits straight away can lose it.
    func testClosingHoldsTheProcessLongEnoughToHandTheNoticeOver() {
        XCTAssertGreaterThanOrEqual(BackupPlanner.appClosedHold, 1)
    }

    /// iOS kills an app that takes about 5 seconds to return from termination.
    func testClosingHoldStaysWellInsideWhatIOSAllows() {
        XCTAssertLessThan(BackupPlanner.appClosedHold, 4)
    }

    func testNoticeFiresAfterTheProcessHasGone() {
        XCTAssertGreaterThan(BackupPlanner.appClosedNoticeDelay, BackupPlanner.appClosedHold)
    }
}

final class ClockChangeTests: XCTestCase {
    private let fire = date("2026-10-21 06:30")
    private let trusted = date("2026-10-20 22:00")

    func testUntouchedClockKeepsTheFireTime() {
        XCTAssertEqual(BackupPlanner.wallClockFireDate(fire, wall: trusted, trusted: trusted), fire)
    }

    /// Triggers fire by the clock on screen. Set it 8 hours ahead and 14:30 on screen is 06:30 for real.
    func testClockSetForwardMovesTheTriggerForward() {
        let wall = trusted.addingTimeInterval(8 * 3600)
        XCTAssertEqual(BackupPlanner.wallClockFireDate(fire, wall: wall, trusted: trusted), fire.addingTimeInterval(8 * 3600))
    }

    func testClockSetBackMovesTheTriggerBack() {
        let wall = trusted.addingTimeInterval(-3 * 3600)
        XCTAssertEqual(BackupPlanner.wallClockFireDate(fire, wall: wall, trusted: trusted), fire.addingTimeInterval(-3 * 3600))
    }
}
