import SwiftUI
import AlarmyCore

/// Type each sentence exactly. A wrong one stays in the box to be fixed.
struct TypingMissionView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var focused: Bool
    @State private var sentences: [String]
    @State private var index = 0
    @State private var entry = ""
    @State private var wrong = false
    @State private var right = false
    let session: RingSession
    let step: MissionStep

    init(session: RingSession, step: MissionStep, custom: [String]) {
        self.session = session
        self.step = step
        var rng = SystemRandomNumberGenerator()
        let kind = SentenceKind(rawValue: step.level) ?? .motivational
        _sentences = State(initialValue: Sentences.pick(from: Sentences.list(kind, custom: custom), rounds: step.amount, using: &rng))
    }

    private var target: String { sentences.indices.contains(index) ? sentences[index] : "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MissionTopBar().padding(.top, 8)
            MissionPositionLabel(session: session).padding(.top, 8)
            Text("Sentence \(min(index + 1, sentences.count)) of \(sentences.count)")
                .font(.system(size: 17, weight: .medium))
                .padding(.top, 8)
            Text(colored)
                .font(.system(size: 26, weight: .bold))
                .accessibilityIdentifier("typing-target")
                .padding(.top, 12)
            TextField("Type it here", text: $entry)
                .font(.system(size: 20))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .focused($focused)
                .onSubmit { submit() }
                .padding(14)
                .background(Theme.night.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityIdentifier("typing-entry")
                .padding(.top, 16)
            Text(wrong ? "Not quite. Check it and try again." : right ? "That's it" : " ")
                .font(Theme.bodyStrong)
                .foregroundColor(wrong ? Theme.siren : Theme.night)
                .padding(.top, 8)
            Spacer(minLength: 8)
            PrimaryButton(title: "Check", background: Theme.night, foreground: Theme.sunlight) { submit() }
            EarlyClearExit(session: session)
        }
        .foregroundColor(Theme.night)
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sunlight.ignoresSafeArea())
        .onAppear { focused = true }
        .onChange(of: entry) { _ in model.noteMissionInput() }
    }

    /// What's been typed so far shows in the sentence: dark when right, red when wrong.
    private var colored: AttributedString {
        let typed = Array(entry)
        var result = AttributedString()
        for (position, character) in target.enumerated() {
            var piece = AttributedString(String(character))
            if position >= typed.count {
                piece.foregroundColor = Theme.night.opacity(0.45)
            } else if Sentences.matches(String(typed[position]), String(character)) {
                piece.foregroundColor = Theme.night
            } else {
                piece.foregroundColor = Theme.siren
            }
            result += piece
        }
        return result
    }

    private func submit() {
        focused = true
        guard !right else { return }
        model.noteMissionInput()
        guard Sentences.matches(entry, target) else {
            Haptics.failure()
            wrong = true
            DiagnosticLog.shared.add("typing: wrong")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { wrong = false }
            return
        }
        wrong = false
        right = true
        Haptics.success()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            right = false
            entry = ""
            if index + 1 < sentences.count {
                index += 1
            } else {
                DiagnosticLog.shared.add("typing mission done")
                model.finishMissionSoon(.typing)
            }
        }
    }
}

/// Some tiles light up, then have to be found again. Wrong taps cost nothing but time,
/// and every second one shows where the rest are.
struct MemoryMissionView: View {
    private enum Stage {
        case waiting, memorizing, guessing
    }

    @EnvironmentObject private var model: AppModel
    @State private var board: MemoryBoard
    @State private var round = 1
    @State private var stage = Stage.waiting
    @State private var locked = true
    @State private var lit: Set<Int> = []
    @State private var litLevel = 0.7
    @State private var wrongTile: Int?
    let session: RingSession
    let step: MissionStep

    init(session: RingSession, step: MissionStep) {
        self.session = session
        self.step = step
        var rng = SystemRandomNumberGenerator()
        _board = State(initialValue: MemoryBoard.random(level: step.level, using: &rng))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MissionTopBar().padding(.top, 8)
            MissionPositionLabel(session: session).padding(.top, 8)
            Text("Round \(round) of \(step.amount)")
                .font(Theme.display(34))
                .padding(.top, 14)
            Text(stage == .guessing ? "Now find them" : "Remember the tiles that light up")
                .font(Theme.body)
                .padding(.top, 6)
            Spacer(minLength: 8)
            grid
            Spacer(minLength: 8)
            EarlyClearExit(session: session)
        }
        .foregroundColor(Theme.night)
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sunlight.ignoresSafeArea())
        .task(id: round) { await playRound() }
    }

    private var grid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: board.side)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(0..<board.cellCount, id: \.self) { cell in
                Button { tap(cell) } label: {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(color(cell))
                        .aspectRatio(1, contentMode: .fit)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tile-\(cell)")
                .accessibilityLabel("Tile \(cell + 1)")
                .accessibilityValue(tileValue(cell))
            }
        }
        .opacity(stage == .waiting ? 0.2 : 1)
        .animation(.linear(duration: 0.3), value: stage)
    }

    private func color(_ cell: Int) -> Color {
        if wrongTile == cell { return Theme.siren }
        if board.flipped.contains(cell) { return .white }
        if lit.contains(cell) { return Color.white.opacity(litLevel) }
        return Theme.night
    }

    /// A test run can read which tiles to tap. A phone build can't.
    private func tileValue(_ cell: Int) -> String {
        #if DEBUG
        return board.targets.contains(cell) ? "target" : "other"
        #else
        return board.flipped.contains(cell) ? "Found" : ""
        #endif
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func playRound() async {
        var rng = SystemRandomNumberGenerator()
        board = MemoryBoard.random(level: step.level, using: &rng)
        stage = .waiting
        locked = true
        lit = []
        wrongTile = nil
        model.noteMissionInput()
        await pause(1)
        guard !Task.isCancelled else { return }
        stage = .memorizing
        await pause(0.2)
        await blink(board.targets)
        guard !Task.isCancelled else { return }
        stage = .guessing
        await pause(0.1)
        guard !Task.isCancelled else { return }
        locked = false
        model.noteMissionInput()
    }

    /// Takes one second.
    private func blink(_ cells: Set<Int>) async {
        lit = cells
        litLevel = 0.7
        for _ in 0..<2 {
            await pause(0.05)
            withAnimation(.linear(duration: 0.2)) { litLevel = 1 }
            await pause(0.25)
            withAnimation(.linear(duration: 0.2)) { litLevel = 0.7 }
            await pause(0.2)
        }
        lit = []
    }

    private func tap(_ cell: Int) {
        guard !locked, stage == .guessing else { return }
        let result = board.tap(cell)
        guard result != .ignored else { return }
        model.noteMissionInput()
        switch result {
        case .ignored, .right:
            break
        case .finished:
            locked = true
            Task {
                await pause(0.7)
                if round < step.amount {
                    round += 1
                } else {
                    DiagnosticLog.shared.add("memory mission done")
                    model.finishMissionSoon(.memory)
                }
            }
        case .wrong(let showHint):
            Haptics.tap()
            wrongTile = cell
            locked = showHint
            Task {
                await pause(0.3)
                if wrongTile == cell { wrongTile = nil }
                guard showHint else { return }
                await pause(0.2)
                await blink(board.unflippedTargets)
                model.noteMissionInput()
                locked = false
            }
        }
    }
}

/// Scan the registered barcode with the camera. Anything else gets a message and it keeps looking.
struct BarcodeMissionView: View {
    private static let backupSums = 5

    @EnvironmentObject private var model: AppModel
    @StateObject private var scanner = BarcodeScanner()
    @State private var mismatch = false
    @State private var found = false
    @State private var usingBackup = false
    let session: RingSession
    let step: MissionStep

    var body: some View {
        if usingBackup {
            MathMissionView(session: session, sums: Self.backupSums, level: .level5) { model.completeMission(.barcode) }
        } else {
            scanning
        }
    }

    private var cameraOff: Bool {
        scanner.authorization == .denied || scanner.authorization == .restricted
    }

    private var scanning: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if cameraOff {
                CameraAccessOff(message: "Camera access is off. Turn it on to scan your barcode.")
                    .foregroundColor(Theme.moon)
            } else {
                CameraPreview(session: scanner.session).ignoresSafeArea()
            }

            VStack(alignment: .leading, spacing: 0) {
                MissionTopBar(tint: Theme.sunlight).padding(.bottom, 8)
                (Text("Scan: ").foregroundColor(Theme.moon) + Text(model.barcodeName(step.code)).foregroundColor(Theme.sunlight))
                    .font(.system(size: 15, weight: .bold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Theme.night)
                    .clipShape(Capsule())
                MissionPositionLabel(session: session)
                    .foregroundColor(Theme.moon)
                    .padding(.top, 8)
                Spacer()
                if mismatch {
                    Text("That's not the right barcode.")
                        .font(Theme.bodyStrong)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Theme.siren)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
                        .padding(.bottom, 12)
                }
                if cameraOff || model.isMissionStuck(.barcode) {
                    PrimaryButton(title: cameraOff ? "Can't scan. Do sums instead" : "Can't find it? Do sums instead") {
                        DiagnosticLog.shared.add("barcode mission: sums instead")
                        model.noteMissionInput()
                        usingBackup = true
                    }
                    .padding(.bottom, 12)
                }
                Button {
                    scanner.torchOn.toggle()
                    model.noteMissionInput()
                } label: {
                    Image(systemName: scanner.torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                        .font(.system(size: 20))
                        .frame(width: 48, height: 48)
                        .background(scanner.torchOn ? Theme.sunlight : Theme.night.opacity(0.8))
                        .foregroundColor(scanner.torchOn ? Theme.night : Theme.moon)
                        .clipShape(Circle())
                }
                .accessibilityLabel(scanner.torchOn ? "Turn torch off" : "Turn torch on")
                EarlyClearExit(session: session)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .onAppear { scanner.onScan = handle }
        .task { await scanner.start() }
        .onDisappear { scanner.stop() }
    }

    private func handle(_ code: String) {
        guard !found else { return }
        model.noteMissionInput()
        if code == step.code {
            found = true
            mismatch = false
            DiagnosticLog.shared.add("barcode mission done")
            model.finishMissionSoon(.barcode)
        } else {
            DiagnosticLog.shared.add("barcode mission: wrong code")
            Haptics.failure()
            mismatch = true
        }
    }
}
