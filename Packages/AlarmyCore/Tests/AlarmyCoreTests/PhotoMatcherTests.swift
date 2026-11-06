import XCTest
import CoreGraphics
@testable import AlarmyCore

final class PhotoMatcherTests: XCTestCase {
    private let m = PhotoMatcher()

    private func scene(_ seed: UInt64, brightness: CGFloat = 1, offset: CGFloat = 0) -> CGImage {
        SceneRenderer.render(seed: seed, brightness: brightness, offset: offset)
    }

    private func fp(_ image: CGImage) throws -> Data { try m.featurePrint(for: image) }

    /// A scene with a coloured band above and below it, like a tall photo of something in the middle.
    private func tall(_ image: CGImage, band: Int, red: CGFloat, blue: CGFloat) -> CGImage {
        let width = image.width, height = image.height + band * 2
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: red, green: 0, blue: blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: band, width: width, height: image.height))
        return context.makeImage()!
    }

    func testIdenticalIsZero() throws {
        XCTAssertLessThan(try m.distance(scene(1), toReferences: [fp(scene(1))]), 0.001)
    }

    func testDarkerSameSceneMatchesFirstTime() throws {
        XCTAssertTrue(try m.evaluate(scene(1, brightness: 0.6), references: [fp(scene(1))], misses: 0).matched)
    }

    func testShiftedSameSceneMatchesFirstTime() throws {
        XCTAssertTrue(try m.evaluate(scene(1, offset: 0.04), references: [fp(scene(1))], misses: 0).matched)
    }

    func testUsesBestOfMultipleReferences() throws {
        XCTAssertLessThan(try m.distance(scene(1), toReferences: [fp(scene(2)), fp(scene(1))]), 0.001)
    }

    func testLimitRisesWithEachMissUpToAPoint() {
        XCTAssertEqual((0...10).map { PhotoMatcher.limit(misses: $0) }, [20, 22, 24, 26, 28, 30, 32, 34, 36, 36, 36])
    }

    func testEvaluateReportsTheLimitItUsed() throws {
        XCTAssertEqual(try m.evaluate(scene(1), references: [fp(scene(1))], misses: 3).limit, 26)
    }

    func testDistanceMustBeBelowTheLimit() throws {
        let reference = [try fp(scene(1))]
        let d = try m.distance(scene(2), toReferences: reference)
        XCTAssertEqual(try m.evaluate(scene(2), references: reference, misses: 0).matched, d < 20)
        XCTAssertEqual(try m.evaluate(scene(2), references: reference, misses: 8).matched, d < 36)
    }

    func testNoReferencesNeverMatches() throws {
        XCTAssertFalse(try m.evaluate(scene(1), references: [], misses: 8).matched)
    }

    func testCenterSquareOfATallPhoto() throws {
        let square = try XCTUnwrap(PhotoMatcher.centerSquare(tall(scene(1), band: 100, red: 1, blue: 0)))
        XCTAssertEqual(square.width, 512)
        XCTAssertEqual(square.height, 512)
    }

    func testCenterSquareOfAWidePhoto() throws {
        let context = CGContext(data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let square = try XCTUnwrap(PhotoMatcher.centerSquare(context.makeImage()!))
        XCTAssertEqual(square.width, 300)
        XCTAssertEqual(square.height, 300)
    }

    func testOnlyTheMiddleOfThePhotoMatters() throws {
        let redBands = tall(scene(1), band: 100, red: 1, blue: 0)
        let blueBands = tall(scene(1), band: 100, red: 0, blue: 1)
        XCTAssertLessThan(try m.distance(redBands, toReferences: [fp(blueBands)]), 0.001)
    }

    func testDistanceBetweenStoredPrints() throws {
        let a = try fp(scene(1))
        XCTAssertLessThan(try m.distance(fromPrint: a, toReferences: [a]), 0.001)
        XCTAssertGreaterThan(try m.distance(fromPrint: a, toReferences: [try fp(scene(2))]), 1)
    }

    /// Prints distances, to compare with real photos in the phone's log. No assertion.
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
