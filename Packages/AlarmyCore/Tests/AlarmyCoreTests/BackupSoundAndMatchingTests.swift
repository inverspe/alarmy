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
