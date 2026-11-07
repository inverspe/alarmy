import SwiftUI
import AlarmyCore

/// Says why changes are blocked. When the only thing holding them is an alarm that can't be
/// turned off, offers its missions as the way to unlock.
struct LockNotice: View {
    @EnvironmentObject private var model: AppModel
    /// Off inside the alarm editor: it's a sheet, and the missions take over the whole screen.
    var offersUnlock = true

    var body: some View {
        if let holder = model.untilDoneLock {
            LockBanner(text: "Locked until your \(Theme.timeString(holder.fireDate)) alarm is done")
                .padding(.bottom, 14)
        } else if let holder = model.standingLock {
            VStack(alignment: .leading, spacing: 10) {
                LockBanner(text: offersUnlock
                           ? "Your \(Theme.timeString(holder.fireDate)) alarm can't be turned off. Do its missions to unlock."
                           : "Your \(Theme.timeString(holder.fireDate)) alarm can't be turned off. Unlock it from the Alarms screen.")
                if offersUnlock, model.unlockable != nil {
                    Button { model.startUnlock() } label: {
                        Text("Unlock with mission")
                            .font(Theme.bodyStrong)
                            .foregroundColor(Theme.sunlight)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .overlay(RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous)
                                .stroke(Theme.sunlight, lineWidth: 2))
                            .contentShape(RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 14)
        } else if let until = model.unlockedUntil {
            LockBanner(text: "Unlocked until \(Theme.timeString(until))", symbol: "lock.open.fill")
                .padding(.bottom, 14)
        }
    }
}
