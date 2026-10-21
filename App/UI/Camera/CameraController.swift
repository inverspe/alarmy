import AVFoundation
import SwiftUI
import UIKit

/// Back camera with a torch and single-photo capture. Photos come back normalized
/// (upright, longest side 1280) like the stored reference photos.
final class CameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    enum CameraError: Error { case noImage, notRunning }

    @Published var torchOn: Bool { didSet { applyTorch() } }
    @Published private(set) var authorization = AVCaptureDevice.authorizationStatus(for: .video)

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "alarmy.camera")
    private var device: AVCaptureDevice?
    private var configured = false
    private var continuation: CheckedContinuation<UIImage, Error>?

    init(torchOn: Bool = false) {
        self.torchOn = torchOn
        super.init()
    }

    @MainActor
    func start() async {
        if authorization == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
            authorization = AVCaptureDevice.authorizationStatus(for: .video)
        }
        guard authorization == .authorized else { return }
        let torch = torchOn
        queue.async {
            self.configureIfNeeded()
            if !self.session.isRunning { self.session.startRunning() }
            self.setTorch(torch)
        }
    }

    func stop() {
        queue.async {
            self.setTorch(false)
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    @MainActor
    func capture() async throws -> UIImage {
        guard continuation == nil else { throw CameraError.notRunning }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            queue.async {
                guard self.session.isRunning else {
                    DispatchQueue.main.async { self.finish(.failure(CameraError.notRunning)) }
                    return
                }
                self.output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let result: Result<UIImage, Error>
        if let error {
            result = .failure(error)
        } else if let data = photo.fileDataRepresentation(), let image = UIImage(data: data) {
            result = .success(image.normalized(maxSide: 1280))
        } else {
            result = .failure(CameraError.noImage)
        }
        DispatchQueue.main.async { self.finish(result) }
    }

    private func finish(_ result: Result<UIImage, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }

    private func configureIfNeeded() {
        guard !configured else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo
        if let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input) {
            session.addInput(input)
            device = camera
        }
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        configured = true
    }

    private func applyTorch() {
        let torch = torchOn
        queue.async { self.setTorch(torch) }
    }

    /// Call on `queue`.
    private func setTorch(_ on: Bool) {
        guard let device, device.hasTorch, session.isRunning else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        } catch {}
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

/// Shown instead of the camera when access is off.
struct CameraAccessOff: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(message).font(Theme.bodyStrong)
            PrimaryButton(title: "Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        }
        .padding(Theme.gutter)
    }
}
