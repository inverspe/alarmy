import XCTest
@testable import AlarmyCore

final class TrustedClockTests: XCTestCase {
    private let T = date("2026-10-20 23:00")
    private var A: ClockAnchor { ClockAnchor(wall: T, monotonic: 1000) }

    func testNoAnchorTrustsWall() {
        XCTAssertEqual(TrustedClock.now(wall: T, monotonic: 5, anchor: nil), T)
    }

    func testConsistentClock() {
        XCTAssertEqual(TrustedClock.now(wall: T + 600, monotonic: 1600, anchor: A), T + 600)
    }

    func testSmallDriftTrustsWall() {
        XCTAssertEqual(TrustedClock.now(wall: T + 650, monotonic: 1600, anchor: A), T + 650)
    }

    func testClockMovedForwardIsIgnored() {
        XCTAssertEqual(TrustedClock.now(wall: T + 600 + 3600 * 8, monotonic: 1600, anchor: A), T + 600)
    }

    func testClockMovedBackIsIgnored() {
        XCTAssertEqual(TrustedClock.now(wall: T - 3600, monotonic: 1600, anchor: A), T + 600)
    }

    func testRebootTrustsWall() {
        XCTAssertEqual(TrustedClock.now(wall: T + 99, monotonic: 5, anchor: A), T + 99)
    }

    func testAnchorRefreshedWhenTrusted() {
        XCTAssertEqual(TrustedClock.refreshedAnchor(A, wall: T + 600, monotonic: 1600), ClockAnchor(wall: T + 600, monotonic: 1600))
        XCTAssertEqual(TrustedClock.refreshedAnchor(nil, wall: T, monotonic: 7), ClockAnchor(wall: T, monotonic: 7))
    }

    func testAnchorNotRefreshedWhileTampered() {
        XCTAssertEqual(TrustedClock.refreshedAnchor(A, wall: T + 9999, monotonic: 1600), A)
    }
}
