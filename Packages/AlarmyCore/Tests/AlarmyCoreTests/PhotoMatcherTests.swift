import XCTest
import CoreGraphics
@testable import AlarmyCore

final class PhotoMatcherTests: XCTestCase {
    private let m = PhotoMatcher()

    private func scene(_ seed: UInt64, brightness: CGFloat = 1, offset: CGFloat = 0) -> CGImage {
        SceneRenderer.render(seed: seed, brightness: brightness, offset: offset)
    }

    private func fp(_ image: CGImage) throws -> Data { try m.featurePrint(for: image) }

    func testIdenticalIsZero() throws {
        XCTAssertLessThan(try m.distance(scene(1), toReferences: [fp(scene(1))]), 0.001)
    }

    func testDarkerSameSceneMatchesMedium() throws {
        XCTAssertTrue(try m.evaluate(scene(1, brightness: 0.6), references: [fp(scene(1))], strictness: .medium).matched)
    }

    func testShiftedSameSceneMatchesMedium() throws {
        XCTAssertTrue(try m.evaluate(scene(1, offset: 0.04), references: [fp(scene(1))], strictness: .medium).matched)
    }

    func testDifferentSceneRejectedMediumAndStrict() throws {
        for strictness in [Strictness.medium, .strict] {
            for seed: UInt64 in 2...6 {
                XCTAssertFalse(try m.evaluate(scene(seed), references: [fp(scene(1))], strictness: strictness).matched,
                               "seed \(seed) matched at \(strictness)")
            }
        }
    }

    func testUsesBestOfMultipleReferences() throws {
        XCTAssertLessThan(try m.distance(scene(1), toReferences: [fp(scene(2)), fp(scene(1))]), 0.001)
    }

    func testEvaluateReportsThreshold() throws {
        let result = try m.evaluate(scene(1), references: [fp(scene(1))], strictness: .strict)
        XCTAssertEqual(result.threshold, PhotoMatcher.threshold(for: .strict))
    }

    func testThresholdOrdering() {
        XCTAssertLessThan(PhotoMatcher.threshold(for: .strict), PhotoMatcher.threshold(for: .medium))
        XCTAssertLessThan(PhotoMatcher.threshold(for: .medium), PhotoMatcher.threshold(for: .loose))
    }

    /// Prints distances used to pick the thresholds. No assertion.
    func testCalibrationReport() throws {
        let reference = try fp(scene(1))
        var same: [String] = []
        for (b, o) in [(0.6, 0.0), (0.8, 0.0), (1.0, 0.02), (1.0, 0.04), (0.7, 0.03)] as [(CGFloat, CGFloat)] {
            same.append(String(format: "b%.1f/o%.2f=%.3f", b, o, try m.distance(scene(1, brightness: b, offset: o), toReferences: [reference])))
        }
        var different: [String] = []
        for seed: UInt64 in 2...6 {
            different.append(String(format: "seed%d=%.3f", seed, try m.distance(scene(seed), toReferences: [reference])))
        }
        print("CALIBRATION same: \(same.joined(separator: " "))")
        print("CALIBRATION different: \(different.joined(separator: " "))")
    }
}
