import AVFoundation
import SwiftUI

/// Back camera that reads any barcode or QR code it can see.
final class BarcodeScanner: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {
    @Published var torchOn = false { didSet { applyTorch() } }
    @Published private(set) var authorization = AVCaptureDevice.authorizationStatus(for: .video)

    let session = AVCaptureSession()
    var onScan: (@MainActor (String) -> Void)?

    private let output = AVCaptureMetadataOutput()
    private let queue = DispatchQueue(label: "alarmy.scanner")
    private var device: AVCaptureDevice?
    private var configured = false
    private var lastSeen: [String: Date] = [:]
    #if DEBUG
    private var fakeTimer: Timer?
    private var fakeLeft: [String] = []
    #endif

    @MainActor
    func start() async {
        #if DEBUG
        if let scans = UITestHarness.fakeScans {
            startFake(scans)
            return
        }
        #endif
        if authorization == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
            authorization = AVCaptureDevice.authorizationStatus(for: .video)
        }
        guard authorization == .authorized else { return }
        queue.async {
            self.configureIfNeeded()
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stop() {
        #if DEBUG
        fakeTimer?.invalidate()
        #endif
        queue.async {
            self.setTorch(false)
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    #if DEBUG
    /// The simulator has no camera, so the codes are handed over one at a time.
    private func startFake(_ scans: [String]) {
        fakeLeft = scans
        fakeTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.nextFake()
        }
    }

    private func nextFake() {
        guard !fakeLeft.isEmpty else {
            fakeTimer?.invalidate()
            return
        }
        report(fakeLeft.removeFirst())
    }
    #endif

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        // More than one code can be in view, and each is reported many times a second.
        for object in metadataObjects {
            guard let code = (object as? AVMetadataMachineReadableCodeObject)?.stringValue,
                  Date().timeIntervalSince(lastSeen[code] ?? .distantPast) >= 2 else { continue }
            lastSeen[code] = Date()
            report(code)
        }
    }

    private func report(_ code: String) {
        Task { @MainActor [weak self] in self?.onScan?(code) }
    }

    /// Only codes: the camera can also report faces and bodies, which aren't what's being looked for.
    private static let codeTypes: [AVMetadataObject.ObjectType] = [
        .qr, .ean8, .ean13, .upce, .code39, .code39Mod43, .code93, .code128, .pdf417, .aztec, .dataMatrix, .itf14,
        .interleaved2of5, .microQR, .microPDF417, .codabar, .gs1DataBar, .gs1DataBarExpanded, .gs1DataBarLimited,
    ]

    private func configureIfNeeded() {
        guard !configured else { return }
        session.beginConfiguration()
        session.sessionPreset = .high
        if let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input) {
            session.addInput(input)
            device = camera
        }
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = Self.codeTypes.filter(output.availableMetadataObjectTypes.contains)
        }
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
