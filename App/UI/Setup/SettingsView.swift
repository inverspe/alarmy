import SwiftUI
import AlarmyCore

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var log = DiagnosticLog.shared
    @State private var newSentence = ""

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

                HStack {
                    Text("Mission time limit").font(Theme.body).foregroundColor(Theme.moon)
                    Spacer()
                    Picker("Mission time limit", selection: Binding(
                        get: { model.state.missionTimeLimit }, set: { model.setMissionTimeLimit($0) }
                    )) {
                        ForEach(MissionAttempt.limitChoices, id: \.self) { Text("\($0) s").tag($0) }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.dusk)
                }
                .disabled(model.isLocked)
                Text("How long a mission waits for you before it closes and the sound comes back.")
                    .font(Theme.caption)
                    .foregroundColor(Theme.dusk)

                DisclosureGroup("My own sentences") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("For the typing mission. Up to \(Sentences.maxCustom), \(Sentences.maxCustomLength) characters each.")
                            .font(Theme.caption)
                            .foregroundColor(Theme.dusk)
                        ForEach(Array(model.state.customSentences.enumerated()), id: \.offset) { index, sentence in
                            HStack {
                                Text(sentence).font(Theme.body).foregroundColor(Theme.moon)
                                Spacer()
                                Button { model.removeSentence(at: index) } label: {
                                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundColor(Theme.dusk)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Delete sentence")
                            }
                        }
                        HStack {
                            TextField("", text: $newSentence, prompt: Text("Add a sentence").foregroundColor(Theme.dusk))
                                .font(Theme.body)
                                .foregroundColor(Theme.moon)
                            Button("Add") {
                                if model.addSentence(newSentence) { newSentence = "" }
                            }
                            .foregroundColor(Theme.sunlight)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(Theme.bodyStrong)
                .foregroundColor(Theme.moon)
                .tint(Theme.dusk)
                .disabled(model.isLocked)
                .padding(.top, 24)

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
