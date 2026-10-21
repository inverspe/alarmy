import SwiftUI
import AlarmyCore

struct AlarmListView: View {
    @EnvironmentObject private var model: AppModel
    @State private var editing: EditTarget?
    @State private var message: String?

    struct EditTarget: Identifiable {
        let alarm: Alarm
        let isNew: Bool
        var id: UUID { alarm.id }
    }

    private var alarms: [Alarm] {
        model.state.alarms.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(title: "Alarms") {
                    Button {
                        editing = EditTarget(alarm: Alarm(hour: 7, minute: 0,
                                                          repeatDays: [.monday, .tuesday, .wednesday, .thursday, .friday]),
                                             isNew: true)
                    } label: {
                        Image(systemName: "plus").font(.system(size: 22, weight: .bold))
                    }
                    .foregroundColor(model.isLocked ? Theme.dusk : Theme.sunlight)
                    .disabled(model.isLocked)
                    .accessibilityLabel("Add alarm")
                }

                if let holder = model.lockHolder {
                    LockBanner(text: "Locked until your \(Theme.timeString(holder.fireDate)) alarm is done")
                        .padding(.bottom, 8)
                }

                if alarms.isEmpty {
                    Text("No alarms yet. Tap + to add one.")
                        .font(Theme.body)
                        .foregroundColor(Theme.dusk)
                        .padding(.vertical, 24)
                }

                ForEach(alarms) { alarm in
                    row(alarm)
                }

                if let message {
                    Text(message).font(Theme.caption).foregroundColor(Theme.siren).padding(.top, 12)
                }

                if let early = model.earlyClearable {
                    PrimaryButton(title: "Up early? Clear your \(Theme.timeString(early.fireDate)) alarm") {
                        model.startEarlyClear()
                    }
                    .padding(.top, 28)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 32)
        }
        .background(Theme.night.ignoresSafeArea())
        .sheet(item: $editing) { target in
            AlarmEditView(alarm: target.alarm, isNew: target.isNew)
                .environmentObject(model)
        }
    }

    private func row(_ alarm: Alarm) -> some View {
        HStack(alignment: .center) {
            Button {
                editing = EditTarget(alarm: alarm, isNew: false)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    ClockText(hour: alarm.hour, minute: alarm.minute, size: 46,
                              color: alarm.isEnabled ? Theme.moon : Theme.dusk)
                    Text(summary(alarm)).font(Theme.caption).foregroundColor(Theme.dusk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle("", isOn: Binding(
                get: { alarm.isEnabled },
                set: { setEnabled(alarm, $0) }
            ))
            .labelsHidden()
            .tint(Theme.horizon)
            .disabled(model.isLocked)
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }

    private func setEnabled(_ alarm: Alarm, _ enabled: Bool) {
        let ok = model.update { state in
            if let i = state.alarms.firstIndex(where: { $0.id == alarm.id }) { state.alarms[i].isEnabled = enabled }
        }
        message = ok ? nil : (model.isLocked ? "Alarms can't be changed right now." : "Add at least one object first.")
    }

    private func summary(_ alarm: Alarm) -> String {
        "\(RepeatText.describe(alarm.repeatDays)), rings \(alarm.ringAfterMinutes) min after the mission"
    }
}

enum RepeatText {
    static func describe(_ days: Set<Weekday>) -> String {
        let weekdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
        switch days {
        case []: return "Once"
        case Set(Weekday.allCases): return "Every day"
        case weekdays: return "Weekdays"
        case [.saturday, .sunday]: return "Weekends"
        default:
            let symbols = Calendar.current.shortWeekdaySymbols
            return Weekday.allCases.filter(days.contains).map { symbols[$0.rawValue - 1] }.joined(separator: ", ")
        }
    }
}
