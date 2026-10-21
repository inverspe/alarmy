import XCTest
@testable import AlarmyCore

final class SmokeTests: XCTestCase {
    func testPackageLoads() {
        XCTAssertEqual(AlarmyCore.name, "AlarmyCore")
    }
}
