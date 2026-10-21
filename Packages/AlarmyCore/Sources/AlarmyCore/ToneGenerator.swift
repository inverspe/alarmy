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
}
