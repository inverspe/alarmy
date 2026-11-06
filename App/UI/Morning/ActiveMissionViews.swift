import SwiftUI
import UIKit
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

    /// What the level setting is called. Nil when this mission has none.
    var levelTitle: String? {
        switch self {
        case .math: return "Difficulty"
        case .shake: return "Strength"
        case .photo, .steps, .squats: return nil
        }
    }

    func levelName(_ level: Int) -> String {
        switch self {
        case .math:
            return MathLevel(rawValue: level)?.example ?? ""
        case .shake:
            let names = ["Very light", "Light", "Medium", "Hard", "Very hard"]
            return names.indices.contains(level) ? names[level] : ""
        case .photo, .steps, .squats:
            return ""
        }
    }
}

/// "Mission 2 of 3" when there's more than one, and a reminder after a missed wake-up check.
struct MissionPositionLabel: View {
    let session: RingSession

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if session.missedWakeChecks > 0 {
                Text("You missed your check")
                    .font(.system(size: 17, weight: .heavy))
            }
            if session.missions.count > 1 {
                Text("Mission \(session.missionIndex + 1) of \(session.missions.count)")
                    .font(.system(size: 15, weight: .bold))
            }
        }
    }
}

/// The time left before an idle mission closes, and a switch for the sound while it's open.
struct MissionTopBar: View {
    @EnvironmentObject private var model: AppModel
    var tint: Color = Theme.night

    var body: some View {
        let fraction = max(0, min(1, model.missionSecondsLeft / MissionAttempt.idleLimit))
        HStack(spacing: 12) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.2))
                    Capsule()
                        .fill(fraction > 0.5 ? tint : fraction > 0.25 ? Theme.horizon : Theme.siren)
                        .frame(width: geo.size.width * fraction)
                        .animation(.linear(duration: 1), value: fraction)
                }
            }
            .frame(height: 8)
            .accessibilityElement()
            .accessibilityLabel("Time left")
            .accessibilityIdentifier("mission-time")

            if model.state.ringSession?.isRinging == true {
                Button { model.toggleMissionSound() } label: {
                    Image(systemName: model.isMissionSoundOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .foregroundColor(tint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.isMissionSoundOn ? "Turn sound off" : "Turn sound on")
            }
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

/// Tells how many fingers are resting on it, which SwiftUI gestures can't be relied on for.
private struct FingerPad: UIViewRepresentable {
    let onChange: (Int) -> Void

    func makeUIView(context: Context) -> PadView {
        let view = PadView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ view: PadView, context: Context) {
        view.onChange = onChange
    }

    final class PadView: UIView {
        var onChange: ((Int) -> Void)?
        private var held = Set<UITouch>()

        override init(frame: CGRect) {
            super.init(frame: frame)
            isMultipleTouchEnabled = true
            backgroundColor = .clear
        }

        required init?(coder: NSCoder) {
            fatalError("Not used from a storyboard")
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            held.formUnion(touches)
            onChange?(held.count)
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            held.subtract(touches)
            onChange?(held.count)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            held.subtract(touches)
            onChange?(held.count)
        }
    }
}

/// Steps, squats or shakes. The count starts over if the mission closes or the app is closed partway through.
struct CountedMissionView: View {
    private static let backupSums = 5

    @EnvironmentObject private var model: AppModel
    @StateObject private var sensor = MissionSensor()
    @State private var usingBackup = false
    @State private var lastCount = 0
    @State private var fingersDown = 0
    @State private var holdStage = 0
    @State private var started = false
    let session: RingSession
    let step: MissionStep

    var body: some View {
        if usingBackup {
            MathMissionView(session: session, sums: Self.backupSums, level: .level5) { model.completeMission(step.kind) }
        } else {
            counting
        }
    }

    /// Squats start with two fingers held on the screen, which shows the phone is in both hands.
    private var waitingForFingers: Bool {
        guard step.kind == .squats, !started, !sensor.unavailable else { return false }
        #if DEBUG
        if UITestHarness.sensorMode != nil && !UITestHarness.wantsTwoFingerStart { return false }
        #endif
        return true
    }

    private var bothHeld: Bool { fingersDown >= 2 }

    private var counting: some View {
        let done = min(sensor.count, step.amount)
        let stuck = sensor.unavailable || model.isMissionStuck(step.kind)
        return VStack(alignment: .leading, spacing: 0) {
            MissionTopBar().padding(.top, 8)
            MissionPositionLabel(session: session).padding(.top, 8)
            Text(heading)
                .font(Theme.display(44))
                .padding(.top, 14)
            Text(instructions)
                .font(Theme.body)
                .padding(.top, 8)
            Spacer()
            if waitingForFingers {
                fingerPad
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(done)").font(Theme.clock(110))
                    Text("of \(step.amount)").font(Theme.display(26))
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("mission-count")
                ProgressView(value: Double(done), total: Double(step.amount))
                    .tint(Theme.night)
                    .padding(.top, 10)
                Text(noteText ?? " ")
                    .font(Theme.bodyStrong)
                    .foregroundColor(Theme.siren)
                    .padding(.top, 10)
            }
            Spacer()
            if stuck {
                PrimaryButton(title: sensor.unavailable ? "This can't be counted. Do sums instead" : "Not counting? Do sums instead",
                              background: Theme.night, foreground: Theme.sunlight) {
                    DiagnosticLog.shared.add("\(step.kind.rawValue) mission: sums instead, counted \(sensor.count)")
                    model.noteMissionInput()
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
        .onAppear {
            if !waitingForFingers { sensor.start(step) }
        }
        .onDisappear { sensor.stop() }
        .task(id: bothHeld) { await holdFingers() }
        .onChange(of: sensor.count) { count in
            guard count > lastCount else {
                lastCount = count
                return
            }
            lastCount = count
            model.noteMissionProgress(step.kind)
            if step.kind == .squats { Haptics.tap() }
            guard count >= step.amount else { return }
            DiagnosticLog.shared.add("\(step.kind.rawValue) mission done: \(count)")
            Haptics.success()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { model.completeMission(step.kind) }
        }
    }

    private var fingerPad: some View {
        VStack(spacing: 16) {
            ZStack {
                FingerPad { fingersDown = $0 }
                HStack(spacing: 40) {
                    ForEach(0..<2, id: \.self) { _ in
                        Circle()
                            .fill(Theme.night.opacity(bothHeld ? 0.35 : 0.1))
                            .overlay(Circle().stroke(Theme.night, lineWidth: 5))
                            .frame(width: 110, height: 110)
                    }
                }
                .allowsHitTesting(false)
            }
            .frame(height: 220)
            Text(holdStage == 0 ? "Hold two fingers on the circles to start" : holdStage == 1 ? "Keep holding" : "Ready")
                .font(Theme.bodyStrong)
        }
        .frame(maxWidth: .infinity)
    }

    /// Letting go at any point starts it over, as this task is cancelled and run again.
    private func holdFingers() async {
        guard bothHeld, waitingForFingers else {
            holdStage = 0
            return
        }
        model.noteMissionInput()
        holdStage = 1
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        guard !Task.isCancelled else { return }
        model.noteMissionInput()
        holdStage = 2
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        guard !Task.isCancelled else { return }
        model.noteMissionInput()
        Haptics.tap()
        started = true
        sensor.start(step)
    }

    private var noteText: String? {
        switch sensor.note {
        case .paused: return "Paused. Keep shaking."
        case .resting: return "Don't stop. Keep walking."
        case .frozen: return "Too much shaking. That costs you 10 steps."
        case .notCounted: return "That didn't count. Hold your phone to your chest."
        case nil: return nil
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
        case .steps: return "Carry your phone and keep moving. Shaking it costs you steps."
        case .squats: return "Hold your phone against your chest. Go all the way down, then stand all the way up."
        default: return "Hold on tight and shake it hard."
        }
    }
}

/// A wrong answer has to be tried again.
struct MathMissionView: View {
    @EnvironmentObject private var model: AppModel
    @State private var problem: MathProblem
    @State private var entry = ""
    @State private var solved = 0
    @State private var wrong = false
    @State private var checking = false
    let session: RingSession
    let sums: Int
    let level: MathLevel
    let finish: () -> Void

    init(session: RingSession, sums: Int, level: MathLevel, finish: @escaping () -> Void) {
        self.session = session
        self.sums = sums
        self.level = level
        self.finish = finish
        _problem = State(initialValue: Self.newProblem(level))
    }

    private static func newProblem(_ level: MathLevel) -> MathProblem {
        var rng = SystemRandomNumberGenerator()
        return MathProblem.random(level: level, using: &rng)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MissionTopBar().padding(.top, 8)
            MissionPositionLabel(session: session).padding(.top, 8)
            Text("Sum \(min(solved + 1, sums)) of \(sums)")
                .font(.system(size: 17, weight: .medium))
                .padding(.top, 8)
            Text(problem.text)
                .accessibilityIdentifier("math-problem")
                .font(Theme.display(40))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(.top, 10)
            Text(entry.isEmpty ? " " : entry)
                .font(Theme.clock(56))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(.top, 8)
            Text(wrong ? "Not quite. Try again." : " ")
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
        model.noteMissionInput()
        guard !checking else { return }
        switch key {
        case "⌫":
            if !entry.isEmpty { entry.removeLast() }
        case "OK":
            guard let answer = Int(entry) else { return }
            check(answer)
        default:
            if entry.count < 7 { entry.append(key) }
        }
    }

    /// Shows the result for a moment before moving on.
    private func check(_ answer: Int) {
        let right = answer == problem.answer
        checking = true
        wrong = !right
        if right { Haptics.success() } else { Haptics.failure() }
        DiagnosticLog.shared.add("math: \(right ? "right" : "wrong"), \(solved + (right ? 1 : 0)) of \(sums)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            entry = ""
            guard right else {
                checking = false
                return
            }
            solved += 1
            if solved >= sums {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { finish() }
            } else {
                problem = Self.newProblem(level)
                checking = false
            }
        }
    }
}
