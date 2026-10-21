import SwiftUI
import AlarmyCore

/// The morning flow is the app's root while a session is active — not a sheet,
/// so there is nothing to swipe away.
struct MorningFlowView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showCamera = false

    var body: some View {
        if let session = model.state.ringSession {
            switch session.phase {
            case .mission:
                if showCamera {
                    MissionCameraView()
                } else {
                    RingingView(session: session) { showCamera = true }
                }
            case .countdown(let endsAt):
                CountdownView(endsAt: endsAt,
                              total: TimeInterval(session.ringAfterMinutes) * 60,
                              hadMission: session.currentObjectID != nil)
            case .finished:
                Theme.night.ignoresSafeArea()
            }
        }
    }
}

struct RingingView: View {
    @EnvironmentObject private var model: AppModel
    let session: RingSession
    let openCamera: () -> Void

    var body: some View {
        let now = Calendar.current.dateComponents([.hour, .minute], from: model.now)
        let object = model.currentObject
        VStack(alignment: .leading, spacing: 0) {
            ClockText(hour: now.hour ?? 0, minute: now.minute ?? 0, size: 76, color: Theme.night)
                .padding(.top, 8)

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

            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    if let id = object?.referencePhotoIDs.first, let image = model.photos.image(id) {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        Theme.night.opacity(0.1)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.photoRadius, style: .continuous))
                .padding(.top, 18)
                .accessibilityLabel("Reference photo of \(object?.name ?? "the object")")

            PrimaryButton(title: "Open camera", background: Theme.night, foreground: Theme.sunlight, action: openCamera)
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
}
