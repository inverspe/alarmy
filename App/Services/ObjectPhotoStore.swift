import UIKit
import AlarmyCore

/// Reference photos on disk: `<id>.jpg` for display and `<id>.fp` (feature print) for matching.
final class ObjectPhotoStore {
    enum StoreError: Error { case encoding }

    private let directory: URL
    private let matcher = PhotoMatcher()

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func add(_ image: UIImage) throws -> UUID {
        let id = UUID()
        let normalized = image.normalized(maxSide: 1280)
        guard let jpeg = normalized.jpegData(compressionQuality: 0.8), let cg = normalized.cgImage else {
            throw StoreError.encoding
        }
        let print = try matcher.featurePrint(for: cg)
        try jpeg.write(to: url(id, "jpg"), options: .atomic)
        try print.write(to: url(id, "fp"), options: .atomic)
        return id
    }

    func image(_ id: UUID) -> UIImage? {
        UIImage(contentsOfFile: url(id, "jpg").path)
    }

    func featurePrint(_ id: UUID) -> Data? {
        try? Data(contentsOf: url(id, "fp"))
    }

    func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: url(id, "jpg"))
        try? FileManager.default.removeItem(at: url(id, "fp"))
    }

    private func url(_ id: UUID, _ ext: String) -> URL {
        directory.appendingPathComponent("\(id.uuidString).\(ext)")
    }
}

extension UIImage {
    /// Upright pixels (EXIF orientation applied), longest side at most `maxSide`, scale 1.
    /// Reference and mission photos both go through this so they compare like for like.
    func normalized(maxSide: CGFloat) -> UIImage {
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
