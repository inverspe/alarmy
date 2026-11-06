import SwiftUI
import AlarmyCore

/// The alarm's missions, done top to bottom. Each kind can be added once.
struct MissionListEditor: View {
    @Binding var missions: [MissionStep]

    private var unused: [MissionKind] {
        MissionKind.allCases.filter { kind in !missions.contains { $0.kind == kind } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Missions").font(Theme.body).foregroundColor(Theme.moon)

            ForEach(Array(missions.enumerated()), id: \.element.id) { index, step in
                row(step, at: index)
            }

            if !unused.isEmpty {
                Menu {
                    ForEach(unused, id: \.self) { kind in
                        Button { add(kind) } label: { Label(kind.title, systemImage: kind.symbol) }
                    }
                } label: {
                    Label("Add mission", systemImage: "plus.circle.fill")
                        .font(Theme.bodyStrong)
                        .foregroundColor(Theme.sunlight)
                        .padding(.vertical, 6)
                }
            }

            if !missions.contains(where: { $0.kind == .photo }) {
                Text("Without a photo mission, you could finish this alarm from bed.")
                    .font(Theme.caption)
                    .foregroundColor(Theme.dusk)
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }

    private func row(_ step: MissionStep, at index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: step.kind.symbol)
                    .frame(width: 26)
                    .foregroundColor(Theme.sunlight)
                    .accessibilityHidden(true)
                Text(step.kind.title).font(Theme.bodyStrong).foregroundColor(Theme.moon)
                Spacer()
                iconButton("chevron.up", label: "Move \(step.kind.title) up", enabled: index > 0) {
                    missions.swapAt(index, index - 1)
                }
                iconButton("chevron.down", label: "Move \(step.kind.title) down", enabled: index < missions.count - 1) {
                    missions.swapAt(index, index + 1)
                }
                iconButton("xmark", label: "Remove \(step.kind.title)", enabled: missions.count > 1) {
                    missions.remove(at: index)
                }
            }
            if let text = step.kind.amountText(step.amount) {
                Stepper(value: amountBinding(at: index), in: step.kind.amountRange, step: step.kind.amountStep) {
                    Text(text).font(Theme.body.monospacedDigit()).foregroundColor(Theme.dusk)
                }
            }
        }
        .padding(12)
        .background(Theme.nightSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func iconButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .frame(width: 34, height: 34)
                .foregroundColor(enabled ? Theme.moon : Theme.dusk.opacity(0.4))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func amountBinding(at index: Int) -> Binding<Int> {
        Binding(get: { missions[index].amount }, set: { missions[index].amount = $0 })
    }

    private func add(_ kind: MissionKind) {
        missions.append(MissionStep(kind: kind))
        if kind == .steps { MissionSensor.requestStepPermission() }
    }
}
