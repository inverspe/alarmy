import Foundation

/// How loud the first ring is while it builds up to full volume.
public enum GentleRamp {
    public static let startLevel: Float = 0.05
    public static let choices = [0, 15, 30, 60]

    public static func level(elapsed: TimeInterval, duration: TimeInterval) -> Float {
        1
    }
}
