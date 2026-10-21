import Foundation

/// Synthesized alarm sounds, so no audio assets (or licences) are needed.
public enum ToneGenerator {
    private static let amplitude = 0.9

    /// Sample value in [-1, 1] for `sound` at `t` seconds.
    public static func sample(_ sound: AlarmSound, at t: Double) -> Float {
        switch sound {
        case .klaxon:
            // Square wave: 880 Hz for 0.25 s, then 660 Hz for 0.25 s.
            let frequency = t.truncatingRemainder(dividingBy: 0.5) < 0.25 ? 880.0 : 660.0
            return Float(sin(2 * .pi * frequency * t) >= 0 ? amplitude : -amplitude)
        case .beeper:
            // 1 kHz sine, 0.15 s on / 0.10 s off.
            guard t.truncatingRemainder(dividingBy: 0.25) < 0.15 else { return 0 }
            return Float(amplitude * sin(2 * .pi * 1000 * t))
        case .siren:
            // Frequency 1000 + 400·sin(2πt) Hz, from the integrated phase.
            let phase = 2 * .pi * (1000 * t - (400 / (2 * .pi)) * cos(2 * .pi * t))
            return Float(amplitude * sin(phase))
        }
    }

    /// The tone as a mono 16-bit PCM WAV file, used as the backup notification sound
    /// (iOS plays notification sounds of up to 30 seconds).
    public static func wav(_ sound: AlarmSound, duration: Double, sampleRate: Int) -> Data {
        let frames = Int(duration * Double(sampleRate))
        let dataSize = frames * 2
        var data = Data(capacity: 44 + dataSize)
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))                    // fmt chunk size
        append(UInt16(1))                     // PCM
        append(UInt16(1))                     // mono
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))        // byte rate
        append(UInt16(2))                     // block align
        append(UInt16(16))                    // bits per sample
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(dataSize))
        for i in 0..<frames {
            let value = sample(sound, at: Double(i) / Double(sampleRate))
            append(Int16((max(-1, min(1, value)) * 32_767).rounded()))
        }
        return data
    }
}
