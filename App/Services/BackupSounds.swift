import Foundation
import UserNotifications
import AlarmyCore

/// 29-second WAVs of each alarm sound in Library/Sounds, where iOS looks for custom
/// notification sounds — so a backup plays the alarm itself, not a short ding.
enum BackupSounds {
    static let duration = 29.0
    private static let version = "v1"

    static func fileName(_ sound: AlarmSound) -> String { "alarmy-\(sound.rawValue)-\(version).wav" }

    static func installIfNeeded() {
        guard let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else { return }
        let folder = library.appendingPathComponent("Sounds")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for sound in AlarmSound.allCases {
            let url = folder.appendingPathComponent(fileName(sound))
            guard !FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                try ToneGenerator.wav(sound, duration: duration, sampleRate: 22_050).write(to: url, options: .atomic)
            } catch {
                DiagnosticLog.shared.add("backup sound \(sound.rawValue) not written: \(error.localizedDescription)")
            }
        }
    }

    static func notificationSound(_ sound: AlarmSound, critical: Bool) -> UNNotificationSound {
        let name = UNNotificationSoundName(fileName(sound))
        return critical ? .criticalSoundNamed(name, withAudioVolume: 1) : UNNotificationSound(named: name)
    }
}
