import Foundation

/// How loud the first ring is while it builds up to full volume.
public enum GentleRamp {
    public static let startLevel: Float = 0.05
    public static let choices = [0, 15, 30, 60]
    static let steepness: Float = 3

    /// Slow at first, then quick near the end. Never below `startLevel`, so the alarm can be heard from the first moment.
    public static func level(elapsed: TimeInterval, duration: TimeInterval) -> Float {
        guard duration > 0, elapsed < duration else { return 1 }
        guard elapsed > 0 else { return startLevel }
        let progress = Float(elapsed / duration)
        return startLevel + (1 - startLevel) * progress * progress
    }
}
