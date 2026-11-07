import AVFoundation
import NaturalLanguage

/// Reads lines out with the phone's own speech. `AppModel` decides when, using `VoiceCycle`,
/// which also brings the sound back if iOS never says the speech has finished.
final class VoiceAnnouncer: NSObject, AVSpeechSynthesizerDelegate {
    var onStarted: (@MainActor () -> Void)?
    var onFinished: (@MainActor () -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private var remaining = 0

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ lines: [String]) {
        remaining = lines.count
        guard !lines.isEmpty else {
            finish()
            return
        }
        var language = "en-US"
        for line in lines {
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(line)
            // A label in another language gets a voice that can say it, as do the lines after it.
            if let best = recognizer.languageHypotheses(withMaximum: 1).first, best.value > 0.9, best.key != .english {
                language = best.key.rawValue
            }
            let utterance = AVSpeechUtterance(string: line)
            utterance.rate = 0.4
            utterance.postUtteranceDelay = 0.8
            utterance.volume = 1
            utterance.voice = AVSpeechSynthesisVoice(language: language)
            synthesizer.speak(utterance)
        }
    }

    func stop() {
        remaining = 0
        synthesizer.stopSpeaking(at: .immediate)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.onStarted?() }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        lineEnded()
    }

    /// When iOS cancels a line. Stopping it from here has already set `remaining` to zero.
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        lineEnded()
    }

    private func lineEnded() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.remaining > 0 else { return }
            self.remaining -= 1
            if self.remaining == 0 { self.finish() }
        }
    }

    private func finish() {
        Task { @MainActor [weak self] in self?.onFinished?() }
    }
}
