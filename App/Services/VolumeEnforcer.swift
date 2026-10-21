import AVFoundation
import MediaPlayer
import UIKit

/// Pushes the system volume back to maximum whenever it drops while started.
final class VolumeEnforcer {
    private let volumeView = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 10, height: 10))
    private var observation: NSKeyValueObservation?
    private var active = false

    func start() {
        active = true
        attachIfNeeded()
        setMax()
        observation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let self, self.active, let volume = change.newValue, volume < 0.99 else { return }
            DispatchQueue.main.async { self.setMax() }
        }
    }

    func stop() {
        active = false
        observation = nil
    }

    private func attachIfNeeded() {
        guard volumeView.superview == nil,
              let window = UIApplication.shared.connectedScenes
                .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return }
        volumeView.alpha = 0.01
        window.addSubview(volumeView)
    }

    private func setMax() {
        attachIfNeeded()
        // The slider only takes effect once MPVolumeView has laid out.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let slider = self?.volumeView.subviews.compactMap({ $0 as? UISlider }).first else { return }
            slider.value = 1
        }
    }
}
