import UserNotifications
import AlarmyCore

/// Schedules the critical-alert backups and routes notification taps back to the app.
final class NotificationScheduler: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private var lastApplied: [String] = []

    var onTap: (@MainActor () -> Void)?
    /// While the app is on screen and already ringing, backups are not shown.
    var isRingingInForeground: @MainActor () -> Bool = { false }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .criticalAlert])) ?? false
    }

    func criticalAlertsEnabled() async -> Bool {
        await center.notificationSettings().criticalAlertSetting == .enabled
    }

    /// Replaces every pending request with `plan`. No-op when the plan hasn't changed.
    func apply(_ plan: [PlannedNotification], calendar: Calendar = .current) {
        let ids = plan.map(\.id)
        guard ids != lastApplied else { return }
        lastApplied = ids
        center.removeAllPendingNotificationRequests()
        for item in plan {
            let content = UNMutableNotificationContent()
            content.title = "Alarm"
            content.body = "Open Alarmy to do your mission."
            content.sound = .defaultCriticalSound(withAudioVolume: 1)
            content.interruptionLevel = .critical
            content.userInfo = [
                "alarmID": item.occurrence.alarmID.uuidString,
                "fireDate": item.occurrence.fireDate.timeIntervalSince1970,
            ]
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
        }
    }

    func clearDelivered() {
        center.removeAllDeliveredNotifications()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let suppress = await MainActor.run { isRingingInForeground() }
        return suppress ? [] : [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        await MainActor.run { onTap?() }
    }
}
