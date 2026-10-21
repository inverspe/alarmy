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
        /// Best distance to the requested object (0 = identical).
        public let distance: Float
        public let threshold: Float
        /// Best distance to any other registered object, if there are any.
        public let closestOther: Float?
        /// Index into `others` of that closest object.
        public let closestOtherIndex: Int?

        public init(matched: Bool, distance: Float, threshold: Float, closestOther: Float?, closestOtherIndex: Int?) {
            self.matched = matched
            self.distance = distance
            self.threshold = threshold
            self.closestOther = closestOther
            self.closestOtherIndex = closestOtherIndex
        }
    }

    /// The mission photo is also compared as a center crop of this size, so standing
    /// a step closer or further than for the reference photo costs less.
    public static let cropFraction: CGFloat = 0.8

    public init() {}

    /// Archived `VNFeaturePrintObservation`, stored with each reference photo.
    public func featurePrint(for image: CGImage) throws -> Data {
        try NSKeyedArchiver.archivedData(withRootObject: observation(for: image), requiringSecureCoding: true)
    }

    /// Smallest distance from `candidate` (whole and center-cropped) to any reference.
    public func distance(_ candidate: CGImage, toReferences refs: [Data]) throws -> Float {
        try distance(candidatePrints(candidate), toReferences: refs)
    }

    /// Distance between a stored print and references, e.g. to spot look-alike objects.
    public func distance(fromPrint print: Data, toReferences refs: [Data]) throws -> Float {
        try distance([unarchive(print)], toReferences: refs)
    }

    /// Matched when the requested object is within the threshold and closer than every
    /// other registered object — so photographing a different object never passes.
    public func evaluate(_ candidate: CGImage, target: [Data], others: [[Data]],
                         strictness: Strictness) throws -> MatchResult {
        let prints = try candidatePrints(candidate)
        let d = try distance(prints, toReferences: target)
        let closest = try others.enumerated()
            .filter { !$0.element.isEmpty }
            .map { (index: $0.offset, distance: try distance(prints, toReferences: $0.element)) }
            .min { $0.distance < $1.distance }
        let threshold = Self.threshold(for: strictness)
        let matched = d <= threshold && (closest.map { d < $0.distance } ?? true)
        return MatchResult(matched: matched, distance: d, threshold: threshold,
                           closestOther: closest?.distance, closestOtherIndex: closest?.index)
    }

    public func evaluate(_ candidate: CGImage, references: [Data],
                         strictness: Strictness) throws -> (matched: Bool, distance: Float, threshold: Float) {
        let result = try evaluate(candidate, target: references, others: [], strictness: strictness)
        return (result.matched, result.distance, result.threshold)
    }

    /// Calibrated from `testCalibrationReport` on CI (Revision1, synthetic scenes):
    /// same scene 3.05–8.73 (dimmed to 60–80%, shifted 2–4%), different scenes 12.96–16.27.
    /// Medium is the midpoint; tune on the device with real photos.
    public static func threshold(for strictness: Strictness) -> Float {
        let medium: Float = 10.8
        switch strictness {
        case .loose: return medium * 1.3
        case .medium: return medium
        case .strict: return medium * 0.75
        }
    }

    public static func centerCrop(_ image: CGImage, fraction: CGFloat) -> CGImage? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let cw = (w * fraction).rounded(), ch = (h * fraction).rounded()
        return image.cropping(to: CGRect(x: ((w - cw) / 2).rounded(), y: ((h - ch) / 2).rounded(), width: cw, height: ch))
    }

    private func candidatePrints(_ image: CGImage) throws -> [VNFeaturePrintObservation] {
        var prints = [try observation(for: image)]
        if let crop = Self.centerCrop(image, fraction: Self.cropFraction) {
            prints.append(try observation(for: crop))
        }
        return prints
    }

    private func distance(_ prints: [VNFeaturePrintObservation], toReferences refs: [Data]) throws -> Float {
        var best = Float.greatestFiniteMagnitude
        for ref in refs {
            let reference = try unarchive(ref)
            for print in prints {
                var d: Float = 0
                try print.computeDistance(&d, to: reference)
                best = min(best, d)
            }
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
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        guard let result = request.results?.first as? VNFeaturePrintObservation else {
            throw MatcherError.noFeaturePrint
        }
        return result
    }
}
