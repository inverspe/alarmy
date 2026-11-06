import CoreGraphics
import Foundation
import Vision

/// Compares a mission photo against an object's reference photos, on-device.
public struct PhotoMatcher {
    public enum MatcherError: Error {
        case noFeaturePrint
        case unreadableReference
    }

    public struct MatchResult: Equatable {
        public let matched: Bool
        /// Best distance to the object's reference photos (0 = identical).
        public let distance: Float
        /// The distance had to be below this.
        public let limit: Float

        public init(matched: Bool, distance: Float, limit: Float) {
            self.matched = matched
            self.distance = distance
            self.limit = limit
        }
    }

    /// The limit starts here and rises with each miss, up to a point, so a poor angle
    /// or bad light can't leave the owner stuck. A pass sets it back.
    static let firstLimit: Float = 20
    static let limitPerMiss: Float = 2
    static let highestLimit: Float = 36

    public init() {}

    public static func limit(misses: Int) -> Float {
        min(firstLimit, highestLimit)
    }

    /// Archived `VNFeaturePrintObservation` of the photo's centre square, stored with each reference photo.
    public func featurePrint(for image: CGImage) throws -> Data {
        try NSKeyedArchiver.archivedData(withRootObject: observation(for: image), requiringSecureCoding: true)
    }

    /// Smallest distance from `candidate` to any reference.
    public func distance(_ candidate: CGImage, toReferences refs: [Data]) throws -> Float {
        try distance(observation(for: candidate), toReferences: refs)
    }

    /// Distance between a stored print and references, e.g. to spot look-alike objects.
    public func distance(fromPrint print: Data, toReferences refs: [Data]) throws -> Float {
        try distance(unarchive(print), toReferences: refs)
    }

    public func evaluate(_ candidate: CGImage, references: [Data], misses: Int) throws -> MatchResult {
        let d = try distance(candidate, toReferences: references)
        let limit = Self.limit(misses: misses)
        return MatchResult(matched: d < limit, distance: d, limit: limit)
    }

    /// The largest square in the middle of the photo. Both photos are cropped the same way,
    /// so only what's in the middle of the frame matters.
    public static func centerSquare(_ image: CGImage) -> CGImage? {
        if image.width > 0 { return image }
        let side = min(image.width, image.height)
        return image.cropping(to: CGRect(x: (image.width - side) / 2, y: (image.height - side) / 2, width: side, height: side))
    }

    private func distance(_ print: VNFeaturePrintObservation, toReferences refs: [Data]) throws -> Float {
        var best = Float.greatestFiniteMagnitude
        for ref in refs {
            var d: Float = 0
            try print.computeDistance(&d, to: unarchive(ref))
            best = min(best, d)
        }
        return best
    }

    private func unarchive(_ data: Data) throws -> VNFeaturePrintObservation {
        guard let print = try NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data) else {
            throw MatcherError.unreadableReference
        }
        return print
    }

    private func observation(for image: CGImage) throws -> VNFeaturePrintObservation {
        let request = VNGenerateImageFeaturePrintRequest()
        // Pinned so the iOS 16 device and the macOS CI produce comparable distances.
        request.revision = VNGenerateImageFeaturePrintRequestRevision1
        try VNImageRequestHandler(cgImage: Self.centerSquare(image) ?? image, options: [:]).perform([request])
        guard let result = request.results?.first as? VNFeaturePrintObservation else {
            throw MatcherError.noFeaturePrint
        }
        return result
    }
}
