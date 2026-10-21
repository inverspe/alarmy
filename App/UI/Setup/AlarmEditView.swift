import SwiftUI
import AlarmyCore

struct AlarmEditView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var alarm: Alarm
    @State private var time: Date
    @State private var error: String?
    private let isNew: Bool

    init(alarm: Alarm, isNew: Bool) {
        _alarm = State(initialValue: alarm)
        _time = State(initialValue: Calendar.current.date(from: DateComponents(hour: alarm.hour, minute: alarm.minute)) ?? Date())
        self.isNew = isNew
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(title: isNew ? "New alarm" : "Edit alarm") {
                    Button("Cancel") { dismiss() }.foregroundColor(Theme.dusk)
                }

                if let holder = model.lockHolder {
                    LockBanner(text: "Locked until your \(Theme.timeString(holder.fireDate)) alarm is done")
                        .padding(.bottom, 8)
                }

                Group {
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)

                    DayChips(days: $alarm.repeatDays).padding(.vertical, 10)

                    field("Sound") {
                        HStack(spacing: 12) {
                            Picker("Sound", selection: $alarm.sound) {
                                ForEach(AlarmSound.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                            }
                            .pickerStyle(.menu)
                            .tint(Theme.dusk)
                            Button { model.previewSound(alarm.sound) } label: { Image(systemName: "play.circle.fill") }
                                .font(.system(size: 24))
                                .foregroundColor(Theme.sunlight)
                                .accessibilityLabel("Play sound")
                        }
                    }

                    stepperField("Keep ringing after mission", value: $alarm.ringAfterMinutes, range: 1...60, step: 1) { "\($0) min" }
                    stepperField("Lock edits before alarm", value: $alarm.lockHours, range: 0...12, step: 1) { $0 == 0 ? "Off" : "\($0) h" }
                    stepperField("Clear early window", value: $alarm.earlyClearMinutes, range: 0...60, step: 5) { $0 == 0 ? "Off" : "\($0) min" }
                }
                .disabled(model.isLocked)

                if let error {
                    Text(error).font(Theme.caption).foregroundColor(Theme.siren).padding(.top, 14)
                }

                PrimaryButton(title: "Save alarm") { save() }
                    .padding(.top, 24)
                    .disabled(model.isLocked)
                    .opacity(model.isLocked ? 0.4 : 1)

                if !isNew {
                    Button("Delete alarm", role: .destructive) { delete() }
                        .font(Theme.bodyStrong)
                        .foregroundColor(Theme.siren)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                        .disabled(model.isLocked)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 32)
        }
        .background(Theme.night.ignoresSafeArea())
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label).font(Theme.body).foregroundColor(Theme.moon)
            Spacer()
            content()
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }

    private func stepperField(_ label: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int,
                              format: @escaping (Int) -> String) -> some View {
        field(label) {
            Stepper(value: value, in: range, step: step) {
                Text(format(value.wrappedValue))
                    .font(Theme.body.monospacedDigit())
                    .foregroundColor(Theme.dusk)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .fixedSize()
        }
    }

    private func save() {
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        alarm.hour = c.hour ?? alarm.hour
        alarm.minute = c.minute ?? alarm.minute
        let edited = alarm
        let ok = model.update { state in
            if let i = state.alarms.firstIndex(where: { $0.id == edited.id }) {
                state.alarms[i] = edited
            } else {
                state.alarms.append(edited)
            }
        }
        if ok {
            dismiss()
        } else {
            error = model.isLocked
                ? "Alarms can't be changed right now."
                : "Add at least one object before turning on an alarm."
        }
    }

    private func delete() {
        let id = alarm.id
        if model.update({ $0.alarms.removeAll { $0.id == id } }) { dismiss() }
    }
}

struct DayChips: View {
    @Binding var days: Set<Weekday>

    var body: some View {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        HStack(spacing: 6) {
            ForEach(Weekday.allCases, id: \.self) { day in
                let on = days.contains(day)
                Button {
                    if on { days.remove(day) } else { days.insert(day) }
                } label: {
                    Text(symbols[day.rawValue - 1])
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 38, height: 38)
                        .background(on ? Theme.moon : Theme.nightSurface)
                        .foregroundColor(on ? Theme.night : Theme.dusk)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Calendar.current.weekdaySymbols[day.rawValue - 1])
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}
