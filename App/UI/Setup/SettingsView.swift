import SwiftUI
import AlarmyCore

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var log = DiagnosticLog.shared

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "Version \(info?["CFBundleShortVersionString"] as? String ?? "?"), build \(info?["CFBundleVersion"] as? String ?? "?")"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(title: "Settings")

                if let holder = model.lockHolder {
                    LockBanner(text: "Locked until your \(Theme.timeString(holder.fireDate)) alarm is done")
                        .padding(.bottom, 14)
                }

                Button("Show setup guide again") { model.restartOnboarding() }
                    .font(Theme.bodyStrong)
                    .foregroundColor(Theme.sunlight)
                    .padding(.top, 32)

                DisclosureGroup("Troubleshooting log") {
                    VStack(alignment: .leading, spacing: 4) {
                        Button("Copy log") { UIPasteboard.general.string = log.lines.joined(separator: "\n") }
                            .foregroundColor(Theme.sunlight)
                            .padding(.vertical, 6)
                        ForEach(Array(log.lines.reversed().enumerated()), id: \.offset) { _, line in
                            Text(line).font(.caption.monospaced()).foregroundColor(Theme.dusk)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(Theme.bodyStrong)
                .foregroundColor(Theme.moon)
                .tint(Theme.dusk)
                .padding(.top, 24)

                Text(version)
                    .font(Theme.caption)
                    .foregroundColor(Theme.dusk)
                    .padding(.top, 24)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 32)
        }
        .background(Theme.night.ignoresSafeArea())
    }
}
