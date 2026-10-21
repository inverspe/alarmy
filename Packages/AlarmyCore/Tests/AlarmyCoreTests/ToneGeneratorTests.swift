import XCTest
@testable import AlarmyCore

final class ToneGeneratorTests: XCTestCase {
    private let rate = 44_100.0

    private func zeroCrossings(_ sound: AlarmSound, from start: Double, to end: Double) -> Double {
        var count = 0
        var previous = ToneGenerator.sample(sound, at: start)
        var i = Int(start * rate) + 1
        while Double(i) / rate < end {
            let v = ToneGenerator.sample(sound, at: Double(i) / rate)
            if (previous < 0 && v >= 0) || (previous >= 0 && v < 0) { count += 1 }
            previous = v
            i += 1
        }
        return Double(count)
    }

    func testAllSamplesInRange() {
        for s in AlarmSound.allCases {
            for i in 0..<44_100 {
                let v = ToneGenerator.sample(s, at: Double(i) / rate)
                XCTAssert(v >= -1 && v <= 1, "\(s) out of range at \(i): \(v)")
            }
        }
    }

    // 0.15 s on, 0.10 s off, repeating every 0.25 s
    func testBeeperIsSilentInGap() {
        XCTAssertEqual(ToneGenerator.sample(.beeper, at: 0.20), 0)
        XCTAssertEqual(ToneGenerator.sample(.beeper, at: 0.45), 0)
    }

    func testBeeperIsAudibleWhenOn() {
        let peak = (0..<Int(0.15 * rate)).map { abs(ToneGenerator.sample(.beeper, at: Double($0) / rate)) }.max() ?? 0
        XCTAssertGreaterThan(peak, 0.5)
    }

    // 880 Hz for 0.25 s, then 660 Hz for 0.25 s
    func testKlaxonAlternatesFrequency() {
        XCTAssertEqual(zeroCrossings(.klaxon, from: 0.0, to: 0.25), 440, accuracy: 4)
        XCTAssertEqual(zeroCrossings(.klaxon, from: 0.25, to: 0.5), 330, accuracy: 4)
    }

    // f(t) = 1000 + 400 sin(2πt): over one full second the average is 1000 Hz → ~2000 crossings
    func testSirenAveragesOneKilohertz() {
        XCTAssertEqual(zeroCrossings(.siren, from: 0.0, to: 1.0), 2000, accuracy: 10)
    }
}
