import SwiftUI
import AlarmyCore

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

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

                Text("Photo matching").font(Theme.bodyStrong).foregroundColor(Theme.moon)
                Picker("Photo matching", selection: Binding(
                    get: { model.state.strictness },
                    set: { value in model.update { $0.strictness = value } }
                )) {
                    Text("Loose").tag(Strictness.loose)
                    Text("Medium").tag(Strictness.medium)
                    Text("Strict").tag(Strictness.strict)
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 10)
                .disabled(model.isLocked)

                Text("Loose accepts rougher photos. Strict needs a close match to your reference photo.")
                    .font(Theme.caption)
                    .foregroundColor(Theme.dusk)

                Text(version)
                    .font(Theme.caption)
                    .foregroundColor(Theme.dusk)
                    .padding(.top, 40)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 32)
        }
        .background(Theme.night.ignoresSafeArea())
    }
}
