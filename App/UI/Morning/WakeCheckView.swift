import SwiftUI

/// The ring has stopped, but the alarm isn't over yet. Nothing to tap until the check comes.
struct WakeCheckWaitingView: View {
    @EnvironmentObject private var model: AppModel
    let checkAt: Date

    var body: some View {
        let remaining = max(0, checkAt.timeIntervalSince(model.now))
        VStack(alignment: .leading, spacing: 0) {
            Text("Ring's over")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Theme.sunlight)
            Text(Theme.countdown(remaining))
                .font(Theme.clock(92))
                .foregroundColor(Theme.moon)
                .padding(.top, 18)
                .accessibilityLabel("\(Int(remaining / 60)) minutes \(Int(remaining) % 60) seconds until your check")
            Text("until your check, at \(Theme.timeString(checkAt))")
                .font(Theme.body)
                .foregroundColor(Theme.moon.opacity(0.75))
                .padding(.top, 8)
            Text("Don't go back to bed.\nYou'll be asked if you're up.")
                .font(Theme.display(26))
                .foregroundColor(Theme.moon)
                .padding(.top, 26)
            Spacer()
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.night.ignoresSafeArea())
    }
}

/// One big button. Run out of time and the alarm starts over.
struct WakeCheckPromptView: View {
    @EnvironmentObject private var model: AppModel
    let deadline: Date

    var body: some View {
        let remaining = max(0, deadline.timeIntervalSince(model.now))
        VStack(alignment: .leading, spacing: 0) {
            Text("Wake-up check")
                .font(.system(size: 17, weight: .semibold))
                .padding(.top, 8)
            Text("Still up?")
                .font(Theme.display(52))
                .padding(.top, 18)
            Text("\(Int(remaining.rounded(.up)))")
                .font(Theme.clock(120))
                .padding(.top, 24)
                .accessibilityLabel("\(Int(remaining.rounded(.up))) seconds left")
            Text("seconds, or the alarm and your mission start over.")
                .font(Theme.body)
            Spacer()
            PrimaryButton(title: "Yes, I'm up", background: Theme.night, foreground: Theme.sunlight) {
                model.confirmAwake()
            }
        }
        .foregroundColor(Theme.night)
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sunlight.ignoresSafeArea())
    }
}
