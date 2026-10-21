import SwiftUI
import UserNotifications
import AlarmyCore

/// Temporary screen for checking platform behaviour on the device (Task 2).
/// Removed once the real app flow exists.
struct DiagnosticsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var status = "Ready"
    @State private var timer: Timer?

    private var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?" }

    var body: some View {
        NavigationStack {
            List {
                Section("Status") { Text(status) }
                Section("Checks") {
                    Button("Allow critical alerts") { requestAuthorization() }
                    Button("Critical alert in 10 s") { scheduleCriticalAlert() }
                    Button("Ring in 2 min (then lock the phone)") { ringLater() }
                    Button("Stop", role: .destructive) { stopAll() }
                }
            }
            .navigationTitle("Alarmy · build \(build)")
        }
    }

    private func requestAuthorization() {
        Task {
            let granted = await model.requestNotificationPermission()
            let critical = await model.notifications.criticalAlertsEnabled()
            status = "Granted: \(granted), critical: \(critical)"
        }
    }

    private func scheduleCriticalAlert() {
        let content = UNMutableNotificationContent()
        content.title = "Alarmy test"
        content.body = "Critical alert check"
        content.sound = .defaultCriticalSound(withAudioVolume: 1)
        content.interruptionLevel = .critical
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "diagnostics-critical", content: content, trigger: trigger))
        status = "Critical alert scheduled for 10 s from now"
    }

    private func ringLater() {
        model.audio.startKeepAlive()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: false) { _ in
            Task { @MainActor in
                model.audio.startRinging(.klaxon)
                model.volume.start()
            }
        }
        status = "Will ring at \(Date().addingTimeInterval(120).formatted(date: .omitted, time: .standard))"
    }

    private func stopAll() {
        timer?.invalidate()
        model.audio.stopRinging()
        model.audio.stopKeepAlive()
        model.volume.stop()
        status = "Stopped"
    }
}
