import Foundation

/// A wall-clock reading paired with the monotonic clock at the same moment,
/// and the boot it was taken in.
public struct ClockAnchor: Codable, Equatable {
    public let wall: Date
    public let monotonic: TimeInterval
    /// `kern.bootsessionuuid`; nil when unavailable (or saved by an older build).
    public let bootID: String?

    public init(wall: Date, monotonic: TimeInterval, bootID: String? = nil) {
        self.wall = wall
        self.monotonic = monotonic
        self.bootID = bootID
    }
}

/// "Now" that ignores manual changes to the iPhone clock until the next reboot.
/// `monotonic` is seconds from `CLOCK_MONOTONIC` (counts sleep, resets on reboot).
public enum TrustedClock {
    public static let tolerance: TimeInterval = 120

    public static func now(wall: Date, monotonic: TimeInterval, bootID: String? = nil, anchor: ClockAnchor?) -> Date {
        guard let derived = derived(anchor, monotonic: monotonic, bootID: bootID) else { return wall }
        return abs(wall.timeIntervalSince(derived)) <= tolerance ? wall : derived
    }

    /// A fresh anchor when the wall clock is trusted; otherwise the old one is kept.
    public static func refreshedAnchor(_ anchor: ClockAnchor?, wall: Date, monotonic: TimeInterval,
                                       bootID: String? = nil) -> ClockAnchor {
        if let anchor, now(wall: wall, monotonic: monotonic, bootID: bootID, anchor: anchor) != wall { return anchor }
        return ClockAnchor(wall: wall, monotonic: monotonic, bootID: bootID)
    }

    /// Nil after a reboot: a different boot session, or (without boot IDs) uptime going backwards.
    /// Uptime alone can't tell: a new boot may already have run longer than the old anchor's uptime.
    private static func derived(_ anchor: ClockAnchor?, monotonic: TimeInterval, bootID: String?) -> Date? {
        guard let anchor, anchor.bootID == bootID, monotonic >= anchor.monotonic else { return nil }
        return anchor.wall.addingTimeInterval(monotonic - anchor.monotonic)
    }
}
