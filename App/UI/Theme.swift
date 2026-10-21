import SwiftUI
import AlarmyCore

/// "Night, then sunrise" — approved in docs/design/visual-direction.html.
/// Night indigo for setup, a sunlight field while ringing, a rising sun for the countdown.
enum Theme {
    static let night = Color(hex: 0x1B2140)
    static let nightSurface = Color(hex: 0x262E57)
    static let moon = Color(hex: 0xE8ECF8)
    static let dusk = Color(hex: 0x8B93B8)
    static let sunlight = Color(hex: 0xFFD84D)
    static let horizon = Color(hex: 0xFF9F1C)
    static let siren = Color(hex: 0xE0335C)
    static let divider = Color(hex: 0x8B93B8).opacity(0.25)

    /// SF Pro Expanded, black, tabular digits — the clock.
    static func clock(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black).width(.expanded).monospacedDigit()
    }

    /// SF Pro Expanded, heavy — screen titles and object names.
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy).width(.expanded)
    }

    static let body = Font.system(size: 16)
    static let bodyStrong = Font.system(size: 16, weight: .semibold)
    static let caption = Font.system(size: 14)
    static let button = Font.system(size: 19, weight: .bold)

    static let gutter: CGFloat = 22
    static let buttonHeight: CGFloat = 64
    static let buttonRadius: CGFloat = 18
    static let photoRadius: CGFloat = 24

    static var uses12HourClock: Bool {
        DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") ?? false
    }

    /// ("6:30", "AM") in 12-hour locales, ("06:30", nil) in 24-hour ones.
    static func timeParts(hour: Int, minute: Int) -> (time: String, period: String?) {
        if uses12HourClock {
            let h = hour % 12 == 0 ? 12 : hour % 12
            return (String(format: "%d:%02d", h, minute), hour < 12 ? "AM" : "PM")
        }
        return (String(format: "%02d:%02d", hour, minute), nil)
    }

    static func timeString(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let parts = timeParts(hour: c.hour ?? 0, minute: c.minute ?? 0)
        return parts.period.map { "\(parts.time) \($0)" } ?? parts.time
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Full-width, 64 pt tall: the one obvious action on a screen.
struct PrimaryButton: View {
    let title: String
    var background: Color = Theme.sunlight
    var foreground: Color = Theme.night
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.button)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: Theme.buttonHeight)
                .padding(.horizontal, 12)
                .foregroundColor(foreground)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct LockBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
            Text(text)
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(Theme.horizon)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.horizon, lineWidth: 1.5))
    }
}

/// Big clock digits with a small AM/PM beside them.
struct ClockText: View {
    let hour: Int
    let minute: Int
    let size: CGFloat
    var color: Color = Theme.moon

    var body: some View {
        let parts = Theme.timeParts(hour: hour, minute: minute)
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(parts.time).font(Theme.clock(size))
            if let period = parts.period {
                Text(period).font(.system(size: size * 0.3, weight: .bold).width(.expanded))
            }
        }
        .foregroundColor(color)
    }
}

/// Screen title row used on the night screens.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center) {
            Text(title).font(Theme.display(30)).foregroundColor(Theme.moon)
            Spacer()
            trailing
        }
        .padding(.top, 12)
        .padding(.bottom, 18)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}
