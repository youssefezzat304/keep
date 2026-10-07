import SwiftUI

struct PomodoroSettingsPopover: View {
    let onApply: (PomodoroSettings) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var focus: String
    @State private var shortBreak: String
    @State private var longBreak: String
    @State private var iterations: String
    @State private var error: String?

    init(settings: PomodoroSettings, onApply: @escaping (PomodoroSettings) -> Bool) {
        self.onApply = onApply
        _focus = State(initialValue: String(settings.focusMinutes))
        _shortBreak = State(initialValue: String(settings.shortBreakMinutes))
        _longBreak = State(initialValue: String(settings.longBreakMinutes))
        _iterations = State(initialValue: String(settings.iterationsBeforeLongBreak))
    }

    private var settings: PomodoroSettings? {
        guard let focus = Int(focus), let shortBreak = Int(shortBreak), let longBreak = Int(longBreak), let iterations = Int(iterations) else { return nil }
        let value = PomodoroSettings(focusMinutes: focus, shortBreakMinutes: shortBreak, longBreakMinutes: longBreak, iterationsBeforeLongBreak: iterations)
        return value.isValid ? value : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your focus rhythm")
                    .font(KeepTheme.headingFont(size: 23))
                Text("A little focus, a little rest.")
                    .font(.system(size: 12))
                    .foregroundStyle(KeepTheme.mutedInk)
            }

            VStack(spacing: 14) {
                settingRow("Focus", value: $focus, range: PomodoroSettings.focusRange, unit: "min")
                settingRow("Short break", value: $shortBreak, range: PomodoroSettings.shortBreakRange, unit: "min")
                settingRow("Long break", value: $longBreak, range: PomodoroSettings.longBreakRange, unit: "min")
                settingRow("Long break after", value: $iterations, range: PomodoroSettings.iterationsRange, unit: "intervals")
            }

            if settings == nil {
                Text("Focus: 1–180 min · short break: 1–60 min · long break: 1–120 min · intervals: 1–12.")
                    .font(.system(size: 11))
                    .foregroundStyle(KeepTheme.accentStrong)
            }
            if let error {
                Text(error).font(.system(size: 12)).foregroundStyle(KeepTheme.accentStrong)
            }

            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save", action: apply)
                    .buttonStyle(.borderedProminent)
                    .tint(KeepTheme.accentStrong)
                    .keyboardShortcut(.defaultAction)
                    .disabled(settings == nil)
            }
            .controlSize(.large)
        }
        .padding(20)
        .frame(width: 350)
        .foregroundStyle(KeepTheme.ink)
        .background(KeepTheme.paper)
    }

    private func settingRow(_ title: String, value: Binding<String>, range: ClosedRange<Int>, unit: String) -> some View {
        Stepper(value: Binding(get: { min(range.upperBound, max(range.lowerBound, Int(value.wrappedValue) ?? range.lowerBound)) }, set: { value.wrappedValue = String($0) }), in: range) {
            HStack(spacing: 8) {
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer(minLength: 4)
                TextField(title, text: value)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 13).monospacedDigit())
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 46)
                    .accessibilityLabel(title)
                    .onSubmit(apply)
                Text(unit).font(.system(size: 11)).foregroundStyle(KeepTheme.mutedInk)
                    .frame(width: 48, alignment: .leading)
            }
        }
        .accessibilityLabel("\(title), \(value.wrappedValue) \(unit)")
    }

    private func apply() {
        guard let settings else { return }
        if onApply(settings) { dismiss() }
        else { error = "Couldn’t apply settings. Retry loading your saved workspace." }
    }
}

#Preview {
    PomodoroSettingsPopover(settings: .defaults) { _ in true }
}
