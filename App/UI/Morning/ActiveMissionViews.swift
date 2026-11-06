import SwiftUI
import AlarmyCore

extension MissionKind {
    var title: String {
        switch self {
        case .photo: return "Photo"
        case .steps: return "Steps"
        case .squats: return "Squats"
        case .shake: return "Shake"
        case .math: return "Math"
        }
    }

    var symbol: String {
        switch self {
        case .photo: return "camera.fill"
        case .steps: return "figure.walk"
        case .squats: return "figure.strengthtraining.traditional"
        case .shake: return "iphone.radiowaves.left.and.right"
        case .math: return "plus.forwardslash.minus"
        }
    }

    /// "30 steps", or "1 sum". Nil when there's no amount to choose.
    func amountText(_ amount: Int) -> String? {
        switch self {
        case .photo: return nil
        case .steps: return amount == 1 ? "1 step" : "\(amount) steps"
        case .squats: return amount == 1 ? "1 squat" : "\(amount) squats"
        case .shake: return amount == 1 ? "1 shake" : "\(amount) shakes"
        case .math: return amount == 1 ? "1 sum" : "\(amount) sums"
        }
    }
}

/// "Mission 2 of 3", only when there's more than one.
struct MissionPositionLabel: View {
    let session: RingSession

    var body: some View {
        if session.missions.count > 1 {
            Text("Mission \(session.missionIndex + 1) of \(session.missions.count)")
                .font(.system(size: 15, weight: .bold))
        }
    }
}

/// Backing out is only possible when clearing early: nothing is ringing yet.
private struct EarlyClearExit: View {
    @EnvironmentObject private var model: AppModel
    let session: RingSession

    var body: some View {
        if session.isEarlyClear {
            Button("Not now") { model.cancelEarlyClear() }
                .font(Theme.bodyStrong)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
        }
    }
}

/// Steps, squats or shakes. The count starts over if the app is closed partway through.
struct CountedMissionView: View {
    /// A sensor that doesn't count for this long is treated as broken, so the mission can always be finished.
    private static let stuckAfter: TimeInterval = 120
    private static let backupSums = 5

    @EnvironmentObject private var model: AppModel
    @StateObject private var sensor = MissionSensor()
    @State private var usingBackup = false
    let session: RingSession
    let step: MissionStep

    var body: some View {
        if usingBackup {
            MathMissionView(session: session, sums: Self.backupSums) { model.completeMission(step.kind) }
        } else {
            counting
        }
    }

    private var counting: some View {
        let done = min(sensor.count, step.amount)
        let stuck = sensor.unavailable || model.now.timeIntervalSince(sensor.lastProgress) >= Self.stuckAfter
        return VStack(alignment: .leading, spacing: 0) {
            MissionPositionLabel(session: session).padding(.top, 8)
            Text(heading)
                .font(Theme.display(44))
                .padding(.top, 14)
            Text(instructions)
                .font(Theme.body)
                .padding(.top, 8)
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(done)").font(Theme.clock(110))
                Text("of \(step.amount)").font(Theme.display(26))
            }
            .accessibilityElement(children: .combine)
            ProgressView(value: Double(done), total: Double(step.amount))
                .tint(Theme.night)
                .padding(.top, 10)
            Spacer()
            if stuck {
                PrimaryButton(title: sensor.unavailable ? "This can't be counted. Do sums instead" : "Not counting? Do sums instead",
                              background: Theme.night, foreground: Theme.sunlight) {
                    DiagnosticLog.shared.add("\(step.kind.rawValue) mission: sums instead, counted \(sensor.count)")
                    usingBackup = true
                }
            }
            EarlyClearExit(session: session)
        }
        .foregroundColor(Theme.night)
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sunlight.ignoresSafeArea())
        .onAppear { sensor.start(step.kind) }
        .onDisappear { sensor.stop() }
        .onChange(of: sensor.count) { count in
            guard count >= step.amount else { return }
            DiagnosticLog.shared.add("\(step.kind.rawValue) mission done: \(count)")
            model.completeMission(step.kind)
        }
    }

    private var heading: String {
        switch step.kind {
        case .steps: return "Start walking"
        case .squats: return "Do your squats"
        default: return "Shake your phone"
        }
    }

    private var instructions: String {
        switch step.kind {
        case .steps: return "Carry your phone with you. Steps can take a few seconds to show up."
        case .squats: return "Hold your phone against your chest. Go all the way down, then stand all the way up."
        default: return "Hold on tight and shake it hard."
        }
    }
}

/// A wrong answer gets a new sum, so answers can't be found by guessing.
struct MathMissionView: View {
    @State private var problem: MathProblem = Self.newProblem()
    @State private var entry = ""
    @State private var solved = 0
    @State private var wrong = false
    let session: RingSession
    let sums: Int
    let finish: () -> Void

    private static func newProblem() -> MathProblem {
        var rng = SystemRandomNumberGenerator()
        return MathProblem.random(using: &rng)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MissionPositionLabel(session: session).padding(.top, 8)
            Text("Sum \(min(solved + 1, sums)) of \(sums)")
                .font(.system(size: 17, weight: .medium))
                .padding(.top, 8)
            Text(problem.text)
                .font(Theme.display(40))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.top, 10)
            Text(entry.isEmpty ? " " : entry)
                .font(Theme.clock(56))
                .padding(.top, 8)
            Text(wrong ? "Not quite. Here's a new one." : " ")
                .font(Theme.bodyStrong)
                .foregroundColor(Theme.siren)
            Spacer(minLength: 8)
            keypad
            EarlyClearExit(session: session)
        }
        .foregroundColor(Theme.night)
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sunlight.ignoresSafeArea())
    }

    private var keypad: some View {
        VStack(spacing: 8) {
            ForEach([["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["⌫", "0", "OK"]], id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { key in
                        Button { press(key) } label: {
                            Text(key)
                                .font(.system(size: 26, weight: .bold))
                                .frame(maxWidth: .infinity, minHeight: 60)
                                .background(key == "OK" ? Theme.night : Theme.night.opacity(0.12))
                                .foregroundColor(key == "OK" ? Theme.sunlight : Theme.night)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(key == "⌫" ? "Delete" : key)
                    }
                }
            }
        }
    }

    private func press(_ key: String) {
        switch key {
        case "⌫":
            if !entry.isEmpty { entry.removeLast() }
        case "OK":
            guard let answer = Int(entry) else { return }
            entry = ""
            check(answer)
        default:
            if entry.count < 5 { entry.append(key) }
        }
    }

    private func check(_ answer: Int) {
        wrong = answer != problem.answer
        if !wrong { solved += 1 }
        DiagnosticLog.shared.add("math: \(wrong ? "wrong" : "right"), \(solved) of \(sums)")
        if solved >= sums {
            finish()
        } else {
            problem = Self.newProblem()
        }
    }
}
