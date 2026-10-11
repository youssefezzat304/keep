import SwiftUI

struct FlowReminderPopover: View {
    let onSave: (Int?) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var enabled: Bool
    @State private var minutes: String
    @State private var saveError = false

    init(minutes: Int?, onSave: @escaping (Int?) -> Bool) {
        self.onSave = onSave
        _enabled = State(initialValue: minutes != nil)
        _minutes = State(initialValue: String(minutes ?? 60))
    }

    private var value: Int? { Int(minutes.trimmingCharacters(in: .whitespacesAndNewlines)) }
    private var isValid: Bool { !enabled || value.map { FlowReminderSchedule.minuteRange.contains($0) } == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("A little check-in").font(KeepTheme.headingFont(size: 23))
                Text("Keep your rhythm. Remember to take a breather.")
                    .font(.system(size: 12)).foregroundStyle(KeepTheme.mutedInk)
            }
            Toggle("Remind me during Flow", isOn: $enabled)
                .toggleStyle(.switch).controlSize(.small)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text("Every")
                    TextField("60", text: $minutes).modifier(KeepInputStyle()).frame(width: 78)
                        .accessibilityLabel("Flow reminder interval in minutes").onSubmit(save)
                    Text("minutes")
                }
                HStack(spacing: 8) {
                    ForEach([15, 30, 60, 90], id: \.self) { interval in
                        Button("\(interval)m") { minutes = String(interval) }
                            .buttonStyle(KeepButtonStyle(emphasis: value == interval ? .secondary : .quiet))
                            .accessibilityLabel("Remind me every \(interval) minutes")
                    }
                }
            }.disabled(!enabled)
            Text(isValid ? "Counts running time only. Changing the interval starts a fresh countdown; pauses preserve it. Flow keeps running after each sound."
                         : "Enter a whole number from 1 to 1,440 minutes.")
                .font(.system(size: 12)).foregroundStyle(isValid ? KeepTheme.mutedInk : KeepTheme.accentStrong)
                .fixedSize(horizontal: false, vertical: true)
            if saveError {
                Text("Settings are unavailable. Close this panel and retry saving in Settings.")
                    .font(.system(size: 12)).foregroundStyle(KeepTheme.accentStrong)
            }
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(KeepButtonStyle(emphasis: .quiet))
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save", action: save).buttonStyle(KeepButtonStyle(emphasis: .primary))
                    .keyboardShortcut(.defaultAction).disabled(!isValid)
            }
        }
        .font(.system(size: 13)).padding(20).frame(width: 340)
        .background(KeepTheme.surface).foregroundStyle(KeepTheme.ink)
        .tint(KeepTheme.accentStrong)
    }

    private func save() {
        guard isValid else { return }
        if onSave(enabled ? value : nil) { dismiss() } else { saveError = true }
    }
}
