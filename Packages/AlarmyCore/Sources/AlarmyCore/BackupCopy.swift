import Foundation

/// Wording for the backup notifications. The title changes from one to the next, so a
/// lock screen full of them doesn't read as the same message repeated.
public enum BackupCopy {
    public static let titles = ["Alarm", "Wake up", "Still ringing", "Time to get up", "Do your mission"]

    public static func title(at index: Int) -> String {
        titles[index % titles.count]
    }
}
