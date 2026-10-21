import Foundation

/// A wall-clock reading paired with the monotonic clock at the same moment.
public struct ClockAnchor: Codable, Equatable {
    public let wall: Date
    public let monotonic: TimeInterval

    public init(wall: Date, monotonic: TimeInterval) {
        self.wall = wall
        self.monotonic = monotonic
    }
}

/// "Now" that ignores manual changes to the iPhone clock until the next reboot.
/// `monotonic` is seconds from `CLOCK_MONOTONIC` (counts sleep, resets on reboot).
public enum TrustedClock {
    public static let tolerance: TimeInterval = 120

    public static func now(wall: Date, monotonic: TimeInterval, anchor: ClockAnchor?) -> Date {
        guard let derived = derived(anchor, monotonic: monotonic) else { return wall }
        return abs(wall.timeIntervalSince(derived)) <= tolerance ? wall : derived
    }

    /// A fresh anchor when the wall clock is trusted; otherwise the old one is kept.
    public static func refreshedAnchor(_ anchor: ClockAnchor?, wall: Date, monotonic: TimeInterval) -> ClockAnchor {
        if let anchor, now(wall: wall, monotonic: monotonic, anchor: anchor) != wall { return anchor }
        return ClockAnchor(wall: wall, monotonic: monotonic)
    }

    private static func derived(_ anchor: ClockAnchor?, monotonic: TimeInterval) -> Date? {
        guard let anchor, monotonic >= anchor.monotonic else { return nil }
        return anchor.wall.addingTimeInterval(monotonic - anchor.monotonic)
    }
}
