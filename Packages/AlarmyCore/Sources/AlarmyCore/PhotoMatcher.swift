import CoreGraphics
import Foundation
import Vision

/// Compares a mission photo against an object's reference photos, on-device.
public struct PhotoMatcher {
    public enum MatcherError: Error {
        case noFeaturePrint
        case unreadableReference
    }

    public init() {}

    /// Archived `VNFeaturePrintObservation`, stored with each reference photo.
    public func featurePrint(for image: CGImage) throws -> Data {
        try NSKeyedArchiver.archivedData(withRootObject: observation(for: image), requiringSecureCoding: true)
    }

    /// Smallest distance from `candidate` to any reference (0 = identical).
    public func distance(_ candidate: CGImage, toReferences refs: [Data]) throws -> Float {
        let observed = try observation(for: candidate)
        var best = Float.greatestFiniteMagnitude
        for ref in refs {
            guard let reference = try NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: ref) else {
                throw MatcherError.unreadableReference
            }
            var d: Float = 0
            try observed.computeDistance(&d, to: reference)
            best = min(best, d)
        }
        return best
    }

    public func evaluate(_ candidate: CGImage, references: [Data],
                         strictness: Strictness) throws -> (matched: Bool, distance: Float, threshold: Float) {
        let d = try distance(candidate, toReferences: references)
        let threshold = Self.threshold(for: strictness)
        return (d <= threshold, d, threshold)
    }

    /// Provisional values; calibrated from `testCalibrationReport`.
    public static func threshold(for strictness: Strictness) -> Float {
        let medium: Float = 15
        switch strictness {
        case .loose: return medium * 1.3
        case .medium: return medium
        case .strict: return medium * 0.75
        }
    }

    private func observation(for image: CGImage) throws -> VNFeaturePrintObservation {
        let request = VNGenerateImageFeaturePrintRequest()
        // Pinned so the iOS 16 device and the macOS CI produce comparable distances.
        request.revision = VNGenerateImageFeaturePrintRequestRevision1
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        guard let result = request.results?.first as? VNFeaturePrintObservation else {
            throw MatcherError.noFeaturePrint
        }
        return result
    }
}
