import AudioToolbox
import UIKit

@MainActor
enum Haptics {
    /// The full vibration. Works from any thread and while the app is in the background.
    nonisolated static func vibrate() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func failure() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    static func tap() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
