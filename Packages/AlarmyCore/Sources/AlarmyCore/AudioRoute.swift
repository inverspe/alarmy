import Foundation

/// Where the ring comes out. Earbuds left on the bedside table would ring perfectly and
/// wake nobody, so anything that isn't the phone's own speaker gets overridden.
public enum AudioRoute {
    /// `AVAudioSession.Port.builtInSpeaker.rawValue`.
    static let speaker = "Speaker"

    /// `outputs` are the current route's port types. `alreadyForced` keeps the override on:
    /// once forced, the route reads "Speaker", which on its own would turn the override off again.
    public static func shouldForceSpeaker(outputs: [String], alreadyForced: Bool) -> Bool {
        alreadyForced || (!outputs.isEmpty && !outputs.contains(speaker))
    }
}
