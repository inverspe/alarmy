import SwiftUI
import AlarmyCore

/// The morning flow is the app's root while a session is active — not a sheet,
/// so there is nothing to swipe away.
struct MorningFlowView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let session = model.state.ringSession {
            switch session.phase {
            case .mission:
                if model.missionOpen {
                    missionScreen(session)
                } else {
                    RingingView(session: session)
                }
            case .snoozed(let until):
                SnoozedView(session: session, until: until)
            case .countdown(let endsAt):
                CountdownView(endsAt: endsAt,
                              total: TimeInterval(session.ringAfterMinutes) * 60,
                              hadMission: session.hadMissions)
            case .wakeCheckWaiting(let checkAt):
                WakeCheckWaitingView(checkAt: checkAt)
            case .wakeCheckPrompt(let deadline):
                WakeCheckPromptView(deadline: deadline)
            case .finished:
                Theme.night.ignoresSafeArea()
            }
        }
    }

    @ViewBuilder
    private func missionScreen(_ session: RingSession) -> some View {
        switch session.currentMission?.kind {
        case .steps, .squats, .shake:
            if let step = session.currentMission {
                CountedMissionView(session: session, step: step).id(step.kind)
            }
        case .math:
            MathMissionView(session: session, sums: session.currentMission?.amount ?? 1,
                            level: MathLevel(rawValue: session.currentMission?.level ?? 0) ?? .level5) {
                model.completeMission(.math)
            }
        case .typing:
            if let step = session.currentMission {
                TypingMissionView(session: session, step: step, custom: model.state.customSentences).id(step.kind)
            }
        case .memory:
            if let step = session.currentMission {
                MemoryMissionView(session: session, step: step).id(step.kind)
            }
        case .barcode:
            if let step = session.currentMission {
                BarcodeMissionView(session: session, step: step).id(step.kind)
            }
        case .photo, nil:
            MissionCameraView()
        }
    }
}

/// The alarm is sounding and nothing has started yet. The only thing to do is start the mission.
struct RingingView: View {
    @EnvironmentObject private var model: AppModel
    let session: RingSession

    private var kind: MissionKind { session.currentMission?.kind ?? .photo }

    var body: some View {
        let now = Calendar.current.dateComponents([.hour, .minute], from: model.now)
        let object = model.currentObject
        VStack(alignment: .leading, spacing: 0) {
            ClockText(hour: now.hour ?? 0, minute: now.minute ?? 0, size: 76, color: Theme.night)
                .padding(.top, 8)

            if let label = model.sessionOccurrence?.alarm.label, !label.isEmpty {
                Text(label)
                    .font(Theme.bodyStrong)
                    .lineLimit(1)
                    .padding(.top, 4)
            }

            MissionPositionLabel(session: session).padding(.top, 8)

            if model.missionTimedOut {
                Text("Out of time. Start again.")
                    .font(Theme.bodyStrong)
                    .foregroundColor(Theme.siren)
                    .padding(.top, 8)
            }

            if kind == .photo {
                photoHeading(object)
            } else {
                missionHeading(object)
            }

            picture(object)
                .clipShape(RoundedRectangle(cornerRadius: Theme.photoRadius, style: .continuous))
                .padding(.top, 18)

            if model.canSnooze {
                snoozeButton.padding(.top, 14)
            }

            PrimaryButton(title: kind == .photo ? "Open camera" : "Start mission",
                          background: Theme.night, foreground: Theme.sunlight) { model.openMission() }
                .padding(.top, 18)

            if session.isEarlyClear {
                Button("Not now") { model.cancelEarlyClear() }
                    .font(Theme.bodyStrong)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)
            }
        }
        .foregroundColor(Theme.night)
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 12)
        .background(Theme.sunlight.ignoresSafeArea())
    }

    private var snoozeButton: some View {
        let left = session.snoozesLeft.map { ", \($0) left" } ?? ""
        return Button { model.snooze() } label: {
            Text("Snooze \(session.snoozeMinutes) min\(left)")
                .font(Theme.bodyStrong)
                .frame(maxWidth: .infinity, minHeight: 48)
                .overlay(RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous).stroke(Theme.night, lineWidth: 2))
                .contentShape(RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func photoHeading(_ object: RegisteredObject?) -> some View {
        Text(session.isEarlyClear
             ? "To clear your \(Theme.timeString(session.occurrence.fireDate)) alarm, go find"
             : "Go find")
            .font(.system(size: 17, weight: .medium))
            .padding(.top, 26)
            .padding(.bottom, 4)

        Text(object?.name ?? "")
            .font(Theme.display(40))
            .lineLimit(2)
            .minimumScaleFactor(0.6)
    }

    @ViewBuilder
    private func missionHeading(_ object: RegisteredObject?) -> some View {
        Text(session.isEarlyClear
             ? "To clear your \(Theme.timeString(session.occurrence.fireDate)) alarm"
             : "Your mission")
            .font(.system(size: 17, weight: .medium))
            .padding(.top, 26)
            .padding(.bottom, 4)

        Text(kind == .barcode
             ? "Scan \(model.barcodeName(session.currentMission?.code))"
             : session.currentMission.flatMap { $0.kind.amountText($0.amount) } ?? kind.title)
            .font(Theme.display(40))
            .lineLimit(2)
            .minimumScaleFactor(0.6)

        if let object {
            Text("Later you'll need to photograph \(object.name). Going there first saves time.")
                .font(Theme.caption)
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func picture(_ object: RegisteredObject?) -> some View {
        if kind == .photo {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    if let id = object?.referencePhotoIDs.first, let image = model.photos.image(id) {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        Theme.night.opacity(0.1)
                    }
                }
                .accessibilityLabel("Reference photo of \(object?.name ?? "the object")")
        } else {
            Theme.night.opacity(0.1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(Image(systemName: kind.symbol).font(.system(size: 96)))
                .accessibilityHidden(true)
        }
    }
}

/// The ring has stopped for a while. Nothing can be done here but wait, or get on with the mission.
struct SnoozedView: View {
    @EnvironmentObject private var model: AppModel
    let session: RingSession
    let until: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 34))
                .foregroundColor(Theme.sunlight)
                .accessibilityHidden(true)
                .padding(.top, 8)
            Text("Snoozed")
                .font(Theme.display(40))
                .foregroundColor(Theme.moon)
                .padding(.top, 14)
            Text(Theme.countdown(max(0, until.timeIntervalSince(model.now))))
                .font(Theme.clock(84))
                .foregroundColor(Theme.moon)
                .accessibilityIdentifier("snooze-countdown")
                .padding(.top, 10)
            Text("until it rings again")
                .font(Theme.body)
                .foregroundColor(Theme.dusk)
            if let left = session.snoozesLeft {
                Text(left == 0 ? "No snoozes left" : left == 1 ? "1 snooze left" : "\(left) snoozes left")
                    .font(Theme.bodyStrong)
                    .foregroundColor(Theme.sunlight)
                    .padding(.top, 14)
            }
            Spacer()
            PrimaryButton(title: "Do my mission now") { model.endSnooze() }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.night.ignoresSafeArea())
    }
}
