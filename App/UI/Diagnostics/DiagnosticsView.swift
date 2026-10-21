import SwiftUI
import UserNotifications
import UIKit
import AVFoundation
import AlarmyCore

/// Temporary screen for checking platform behaviour on the device.
/// Removed once the real app flow exists.
struct DiagnosticsView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var log = DiagnosticLog.shared
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
                    Button("Test A: ring in 1 min (normal)") { ringLater(options: [], label: "A") }
                    Button("Test B: ring in 1 min (turn music down)") { ringLater(options: [.duckOthers], label: "B") }
                    Button("Stop", role: .destructive) { stopAll() }
                }
                Section("Log") {
                    Button("Copy log") { UIPasteboard.general.string = log.lines.joined(separator: "\n") }
                    Button("Clear log") { log.clear() }
                    ForEach(Array(log.lines.reversed().enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption.monospaced())
                    }
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

    private func ringLater(options: AVAudioSession.CategoryOptions, label: String) {
        log.add("test \(label) armed")
        model.audio.ringOptions = options
        model.audio.startKeepAlive()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { _ in
            Task { @MainActor in
                let state = UIApplication.shared.applicationState
                log.add("test \(label) timer fired, app state \(state == .background ? "background" : state == .active ? "active" : "inactive")")
                model.audio.startRinging(.klaxon)
                model.volume.start()
            }
        }
        status = "Test \(label) rings at \(Date().addingTimeInterval(60).formatted(date: .omitted, time: .standard)). Lock the phone now."
    }

    private func stopAll() {
        timer?.invalidate()
        model.audio.stopRinging()
        model.audio.stopKeepAlive()
        model.volume.stop()
        log.add("stopped")
        status = "Stopped"
    }
}
