import AVFoundation
import SwiftUI
import UIKit
import UserNotifications
import AlarmyCore

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var step = 0
    @State private var notificationsOK = false
    @State private var criticalOK = false
    @State private var cameraOK = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    @State private var addingObject = false

    private let lastStep = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    page
                }
                .padding(.top, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            PrimaryButton(title: step == lastStep ? "Done" : "Next") {
                if step == lastStep { model.completeOnboarding() } else { step += 1 }
            }
            .disabled(!canContinue)
            .opacity(canContinue ? 1 : 0.4)
            .padding(.bottom, 12)
        }
        .padding(.horizontal, Theme.gutter)
        .foregroundColor(Theme.moon)
        .background(Theme.night.ignoresSafeArea())
        .fullScreenCover(isPresented: $addingObject) {
            AddObjectView().environmentObject(model)
        }
        .task { await refreshNotificationStatus() }
        // Coming back from the Settings app with permissions changed.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            cameraOK = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
            Task { await refreshNotificationStatus() }
        }
    }

    private var canContinue: Bool {
        switch step {
        case 1: return notificationsOK && criticalOK && cameraOK
        case 2: return !model.state.objects.isEmpty
        default: return true
        }
    }

    @ViewBuilder private var page: some View {
        switch step {
        case 0:
            title("Alarmy")
            paragraph("Missions get you up. The 10-minute ring keeps you up.")
            paragraph("When the alarm goes off, you'll photograph one of your objects. Then it keeps ringing for the time you set, so you're properly awake before it stops.")
        case 1:
            title("Two permissions")
            paragraph("Notifications ring through silent mode and Do Not Disturb if the app gets closed. The camera is how you turn the alarm off.")
            permissionRow("Notifications", done: notificationsOK && criticalOK, detail: notificationsOK && !criticalOK ? "Critical alerts are off. Turn them on in Settings → Notifications → Alarmy, or backups stay silent in silent mode." : nil) {
                Task {
                    _ = await model.requestNotificationPermission()
                    await refreshNotificationStatus()
                }
            }
            permissionRow("Camera", done: cameraOK, detail: nil) {
                Task {
                    cameraOK = await AVCaptureDevice.requestAccess(for: .video)
                }
            }
            if !(notificationsOK && criticalOK && cameraOK) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .font(Theme.bodyStrong)
                .foregroundColor(Theme.sunlight)
                Button("Copy troubleshooting log") {
                    UIPasteboard.general.string = DiagnosticLog.shared.lines.joined(separator: "\n")
                }
                .font(Theme.caption)
                .foregroundColor(Theme.dusk)
                .padding(.top, 8)
            }
        case 2:
            title("Your objects")
            paragraph("Photograph things that don't move, in rooms away from your bed. We recommend at least 3, in different rooms.")
            Text(model.state.objects.isEmpty ? "No objects yet." : "\(model.state.objects.count) added: \(model.state.objects.map(\.name).joined(separator: ", "))")
                .font(Theme.bodyStrong)
            PrimaryButton(title: "Add object", background: Theme.nightSurface, foreground: Theme.moon) { addingObject = true }
        case 3:
            title("Make it undeletable")
            paragraph("Do this once in the iPhone Settings app, so sleepy you can't delete Alarmy.")
            numbered(1, "Settings → Screen Time → Use Screen Time Passcode. Let a friend type it, or pick a random one and hide it somewhere annoying.")
            numbered(2, "Settings → Screen Time → Content & Privacy Restrictions → turn it on → iTunes & App Store Purchases → Deleting Apps → Don't Allow.")
            numbered(3, "Settings → Screen Time → App Limits → Add Limit → TrollStore → 1 minute → Block at End of Limit on. TrollStore can uninstall apps too.")
        default:
            title("Keep it working")
            paragraph("Don't update iOS. TrollStore apps can stop opening after an update, and then the alarm can't ring.")
            paragraph("Keep your phone charging overnight. Alarmy stays awake in the background so it can ring on time.")
        }
    }

    private func title(_ text: String) -> some View {
        Text(text).font(Theme.display(32)).padding(.bottom, 4)
    }

    private func paragraph(_ text: String) -> some View {
        Text(text).font(Theme.body).foregroundColor(Theme.moon.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
    }

    private func numbered(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(n)").font(Theme.display(20)).foregroundColor(Theme.sunlight)
            Text(text).font(Theme.body).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func permissionRow(_ name: String, done: Bool, detail: String?, request: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name).font(Theme.bodyStrong)
                Spacer()
                if done {
                    Label("Allowed", systemImage: "checkmark.circle.fill").foregroundColor(Theme.sunlight)
                } else {
                    Button("Allow", action: request).font(Theme.bodyStrong).foregroundColor(Theme.sunlight)
                }
            }
            if let detail { Text(detail).font(Theme.caption).foregroundColor(Theme.horizon) }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsOK = settings.authorizationStatus == .authorized
        criticalOK = settings.criticalAlertSetting == .enabled
    }
}
