import SwiftUI

/// Keeps ringing until `endsAt`. The sun rises as the time runs out. Nothing to tap.
struct CountdownView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let endsAt: Date
    let total: TimeInterval
    let hadMission: Bool

    private static let sky = LinearGradient(stops: [
        .init(color: Theme.night, location: 0),
        .init(color: Color(hex: 0x3A3566), location: 0.45),
        .init(color: Color(hex: 0xB4566A), location: 0.72),
        .init(color: Theme.horizon, location: 0.88),
        .init(color: Theme.sunlight, location: 1),
    ], startPoint: .top, endPoint: .bottom)

    var body: some View {
        let remaining = max(0, endsAt.timeIntervalSince(model.now))
        let progress = total > 0 ? min(1, max(0, 1 - remaining / total)) : 1
        ZStack(alignment: .topLeading) {
            Self.sky.ignoresSafeArea()

            GeometryReader { geo in
                let start = geo.size.height + 60
                let end = geo.size.height * 0.62
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: 0xFFF3B0), Theme.sunlight], center: .center,
                                         startRadius: 0, endRadius: 110))
                    .frame(width: 220, height: 220)
                    .shadow(color: Theme.sunlight.opacity(0.8), radius: 40)
                    .position(x: geo.size.width / 2, y: start - progress * (start - end))
                    .animation(reduceMotion ? nil : .linear(duration: 1), value: progress)
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)

            LinearGradient(colors: [Theme.night.opacity(0), Theme.night.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .frame(height: 180)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text(hadMission ? "Mission done ✓" : "No objects to find, so it just rings")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Theme.sunlight)
                Text(format(remaining))
                    .font(Theme.clock(92))
                    .foregroundColor(Theme.moon)
                    .padding(.top, 18)
                    .accessibilityLabel("\(Int(remaining / 60)) minutes \(Int(remaining) % 60) seconds left")
                Text("until it stops, at \(Theme.timeString(endsAt))")
                    .font(Theme.body)
                    .foregroundColor(Theme.moon.opacity(0.75))
                    .padding(.top, 8)
                Text("You're up.\nStay up.")
                    .font(Theme.display(26))
                    .foregroundColor(Theme.moon)
                    .padding(.top, 26)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 20)
        }
    }

    private func format(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
