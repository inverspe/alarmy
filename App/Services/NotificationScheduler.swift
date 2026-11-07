import UserNotifications
import AlarmyCore

/// Schedules the backups and routes notification taps back to the app. They're critical
/// alerts where iOS allows it, and otherwise Time Sensitive, so they still get through Focus.
final class NotificationScheduler: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private var lastApplied: [String] = []
    /// Refreshed whenever permissions are read; critical sounds are used only when allowed.
    private(set) var criticalEnabled = false

    var onTap: (@MainActor () -> Void)?
    /// While the app is on screen and already ringing, backups are not shown.
    var isRingingInForeground: @MainActor () -> Bool = { false }

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .criticalAlert])
            DiagnosticLog.shared.add("notification request granted=\(granted)")
            await logPermissions("after request")
            return granted
        } catch {
            DiagnosticLog.shared.add("notification request failed: \((error as NSError).code) \(error.localizedDescription)")
            return false
        }
    }

    func criticalAlertsEnabled() async -> Bool {
        await center.notificationSettings().criticalAlertSetting == .enabled
    }

    /// Writes what iOS reports about this app's notification permissions to the log.
    func logPermissions(_ context: String) async {
        let s = await center.notificationSettings()
        func name(_ setting: UNNotificationSetting) -> String {
            switch setting {
            case .enabled: return "on"
            case .disabled: return "off"
            case .notSupported: return "notSupported"
            @unknown default: return "unknown"
            }
        }
        let status: String
        switch s.authorizationStatus {
        case .authorized: status = "authorized"
        case .denied: status = "denied"
        case .notDetermined: status = "notDetermined"
        case .provisional: status = "provisional"
        case .ephemeral: status = "ephemeral"
        @unknown default: status = "unknown"
        }
        criticalEnabled = s.criticalAlertSetting == .enabled
        DiagnosticLog.shared.add("notifications \(context): status=\(status) alert=\(name(s.alertSetting)) sound=\(name(s.soundSetting)) critical=\(name(s.criticalAlertSetting)) timeSensitive=\(name(s.timeSensitiveSetting))")
    }

    /// Replaces every pending request with `plan`. No-op when the plan hasn't changed.
    func apply(_ plan: [PlannedNotification], soundFor: (OccurrenceKey) -> AlarmSound, calendar: Calendar = .current,
               wall: Date, trusted: Date) {
        let critical = criticalEnabled
        // A new time zone or a changed clock moves when the triggers fire, even though the plan is the same.
        let clock = "\(calendar.timeZone.identifier)-\(Int(wall.timeIntervalSince(trusted) / 60))"
        let ids = plan.map { "\($0.id)-\(soundFor($0.occurrence).rawValue)-\(critical)-\(clock)" }
        guard ids != lastApplied else { return }
        lastApplied = ids
        center.removeAllPendingNotificationRequests()
        for (index, item) in plan.enumerated() {
            let content = UNMutableNotificationContent()
            switch item.kind {
            case .alarm:
                content.title = BackupCopy.title(at: index)
                content.body = "Open Alarmy to do your mission."
                content.sound = BackupSounds.notificationSound(soundFor(item.occurrence), critical: critical)
            case .wakeCheck:
                content.title = "Still up?"
                content.body = "Tap now to confirm, or the alarm and your mission start over."
                content.sound = .default
            case .nudge:
                content.title = BackupCopy.title(at: index)
                content.body = "Open Alarmy to do your mission."
            }
            content.interruptionLevel = level(item.kind.urgency(criticalAllowed: critical))
            content.userInfo = [
                "alarmID": item.occurrence.alarmID.uuidString,
                "fireDate": item.occurrence.fireDate.timeIntervalSince1970,
                "kind": item.kind.rawValue,
            ]
            let onScreen = BackupPlanner.wallClockFireDate(item.fireDate, wall: wall, trusted: trusted)
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: onScreen)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
        }
    }

    private func level(_ urgency: NotificationUrgency) -> UNNotificationInterruptionLevel {
        urgency == .critical ? .critical : .timeSensitive
    }

    func clearDelivered() {
        center.removeAllDeliveredNotifications()
    }

    /// Tells the owner that they closed the app. Pending backups carry on regardless,
    /// but they can't ring through the silent switch the way the running app can.
    func postAppClosedNotice(ringing: Bool) {
        let content = UNMutableNotificationContent()
        content.title = ringing ? "The alarm isn't over" : "Alarmy was closed"
        content.body = ringing
            ? "Closing the app doesn't stop it. Open Alarmy to do your mission."
            : "Open it again so your alarm can ring at full volume, even in silent mode."
        content.sound = .default
        content.interruptionLevel = level(PlannedNotification.Kind.alarm.urgency(criticalAllowed: criticalEnabled))
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: BackupPlanner.appClosedNoticeDelay, repeats: false)
        center.add(UNNotificationRequest(identifier: "app-closed", content: content, trigger: trigger))
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        if notification.request.content.userInfo["kind"] as? String == PlannedNotification.Kind.wakeCheck.rawValue {
            return [.sound]
        }
        let suppress = await MainActor.run { isRingingInForeground() }
        return suppress ? [] : [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        await MainActor.run { onTap?() }
    }
}
