import XCTest
import CoreGraphics
@testable import AlarmyCore

final class BackupSoundTests: XCTestCase {
    private func u32(_ d: Data, _ at: Int) -> UInt32 { d.subdata(in: at..<at + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } }
    private func u16(_ d: Data, _ at: Int) -> UInt16 { d.subdata(in: at..<at + 2).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) } }

    func testWavHeaderIsMono16BitPCM() {
        let wav = ToneGenerator.wav(.klaxon, duration: 2, sampleRate: 22_050)
        XCTAssertEqual(String(data: wav.subdata(in: 0..<4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: wav.subdata(in: 8..<12), encoding: .ascii), "WAVE")
        XCTAssertEqual(u16(wav, 20), 1)          // PCM
        XCTAssertEqual(u16(wav, 22), 1)          // mono
        XCTAssertEqual(u32(wav, 24), 22_050)     // sample rate
        XCTAssertEqual(u16(wav, 34), 16)         // bits per sample
        XCTAssertEqual(String(data: wav.subdata(in: 36..<40), encoding: .ascii), "data")
        XCTAssertEqual(u32(wav, 40), 2 * 22_050 * 2)
        XCTAssertEqual(wav.count, 44 + 2 * 22_050 * 2)
        XCTAssertEqual(u32(wav, 4), UInt32(wav.count - 8))
    }

    func testWavSamplesFollowTheTone() {
        let rate = 22_050.0
        let wav = ToneGenerator.wav(.siren, duration: 1, sampleRate: Int(rate))
        for index in [10, 1_000, 12_345] {
            let stored = Int16(bitPattern: u16(wav, 44 + index * 2))
            let expected = Int16((ToneGenerator.sample(.siren, at: Double(index) / rate) * 32_767).rounded())
            XCTAssertEqual(Int(stored), Int(expected), accuracy: 1)
        }
    }
}

final class MatchingAccuracyTests: XCTestCase {
    private let m = PhotoMatcher()

    private func scene(_ seed: UInt64, brightness: CGFloat = 1, offset: CGFloat = 0) -> CGImage {
        SceneRenderer.render(seed: seed, brightness: brightness, offset: offset)
    }

    private func fp(_ image: CGImage) throws -> Data { try m.featurePrint(for: image) }

    func testRejectedWhenAnotherObjectLooksCloser() throws {
        // Within the target's threshold, but another registered object is an even better match.
        let target = [try fp(scene(1, offset: 0.04))]
        let other = [try fp(scene(1))]
        let result = try m.evaluate(scene(1), target: target, others: [other], strictness: .medium)
        XCTAssertLessThanOrEqual(result.distance, result.threshold)
        XCTAssertFalse(result.matched)
        XCTAssertEqual(result.closestOther ?? 1, 0, accuracy: 0.001)
    }

    func testReportsWhichOtherObjectWasClosest() throws {
        let others = [[try fp(scene(3))], [try fp(scene(1))], []]
        let result = try m.evaluate(scene(1), target: [try fp(scene(2))], others: others, strictness: .medium)
        XCTAssertEqual(result.closestOtherIndex, 1)
    }

    func testAcceptedWhenTargetIsClosest() throws {
        let result = try m.evaluate(scene(1, brightness: 0.7), target: [try fp(scene(1))],
                                    others: [[try fp(scene(2))], [try fp(scene(3))]], strictness: .medium)
        XCTAssertTrue(result.matched)
    }

    func testNoOtherObjectsBehavesLikeThreshold() throws {
        let result = try m.evaluate(scene(1, brightness: 0.7), target: [try fp(scene(1))], others: [], strictness: .medium)
        XCTAssertTrue(result.matched)
        XCTAssertNil(result.closestOther)
    }

    func testCenterCropSize() throws {
        let crop = try XCTUnwrap(PhotoMatcher.centerCrop(scene(1), fraction: 0.8))
        XCTAssertEqual(crop.width, Int((512 * 0.8).rounded()))
        XCTAssertEqual(crop.height, Int((512 * 0.8).rounded()))
    }

    func testDistanceBetweenStoredPrints() throws {
        let a = try fp(scene(1))
        XCTAssertLessThan(try m.distance(fromPrint: a, toReferences: [a]), 0.001)
        XCTAssertGreaterThan(try m.distance(fromPrint: a, toReferences: [try fp(scene(2))]), PhotoMatcher.threshold(for: .medium))
    }
}
