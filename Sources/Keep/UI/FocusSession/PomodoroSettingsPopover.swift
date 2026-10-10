import SwiftUI

struct PomodoroSettingsPopover: View {
    private enum Section: String, CaseIterable { case settings = "Settings", presets = "Presets" }

    let onApply: (PomodoroSettings) -> Bool
    let presets: [PomodoroPreset]
    let onSavePreset: ((String, PomodoroSettings) throws -> Void)?
    let onRemovePreset: ((UUID) throws -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var section: Section = .settings
    @State private var presetName = ""
    @State private var focus: String
    @State private var shortBreak: String
    @State private var longBreak: String
    @State private var iterations: String
    @State private var error: String?

    init(settings: PomodoroSettings, presets: [PomodoroPreset] = [],
         onSavePreset: ((String, PomodoroSettings) throws -> Void)? = nil,
         onRemovePreset: ((UUID) throws -> Void)? = nil,
         onApply: @escaping (PomodoroSettings) -> Bool) {
        self.onApply = onApply
        self.presets = presets
        self.onSavePreset = onSavePreset
        self.onRemovePreset = onRemovePreset
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
            KeepSegmentedPicker(label: "Focus rhythm", selection: $section,
                options: Section.allCases, title: { $0.rawValue })

            VStack(alignment: .leading, spacing: 6) {
                Text("Your focus rhythm")
                    .font(KeepTheme.headingFont(size: 23))
                Text(section == .settings ? "A little focus, a little rest." : "Saved rhythms, ready when you are.")
                    .font(.system(size: 12))
                    .foregroundStyle(KeepTheme.mutedInk)
            }

            if section == .settings {
                TextField("Name your preset", text: $presetName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .accessibilityLabel("Preset name")
                    .onSubmit(savePreset)

                VStack(spacing: 14) {
                    settingRow("Focus", value: $focus, unit: "min")
                    settingRow("Short break", value: $shortBreak, unit: "min")
                    settingRow("Long break", value: $longBreak, unit: "min")
                    settingRow("Long break after", value: $iterations, unit: "intervals")
                }

                if settings == nil {
                    Text("Focus: 1–180 min · short break: 1–60 min · long break: 1–120 min · intervals: 1–12.")
                        .font(.system(size: 11))
                        .foregroundStyle(KeepTheme.accentStrong)
                }
                if presetName.trimmingCharacters(in: .whitespacesAndNewlines).count > PomodoroPreset.maximumNameLength {
                    Text("Keep your preset name within 80 characters.")
                        .font(.system(size: 11)).foregroundStyle(KeepTheme.accentStrong)
                }
            } else {
                presetList
            }
            if let error {
                Text(error).font(.system(size: 12)).foregroundStyle(KeepTheme.accentStrong)
            }

            HStack(spacing: 8) {
                Button(section == .settings ? "Cancel" : "Close") { dismiss() }
                    .buttonStyle(KeepButtonStyle(emphasis: .quiet))
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if section == .settings {
                    Button("Save", action: apply)
                        .buttonStyle(KeepButtonStyle(emphasis: .primary))
                        .keyboardShortcut(.defaultAction)
                        .disabled(settings == nil)
                    Button("Save preset", action: savePreset)
                        .buttonStyle(KeepButtonStyle())
                        .disabled(!canSavePreset)
                        .help("Save these values as a named preset without applying them to your timer")
                }
            }
            .controlSize(.large)
        }
        .padding(20)
        .frame(width: 390)
        .foregroundStyle(KeepTheme.ink)
        .background(KeepTheme.paper)
        .onChange(of: section) { _, _ in error = nil }
        .onChange(of: presetName) { _, _ in error = nil }
        .onChange(of: settings) { _, _ in error = nil }
    }

    private var canSavePreset: Bool {
        let name = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        return settings != nil && !name.isEmpty && name.count <= PomodoroPreset.maximumNameLength && onSavePreset != nil
    }

    @ViewBuilder private var presetList: some View {
        if presets.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("No presets yet").font(.system(size: 14, weight: .medium))
                Text("Set your focus and break times in Settings, name your rhythm, then choose Save preset.")
                    .font(.system(size: 12)).foregroundStyle(KeepTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(KeepTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        } else {
            KeepScrollView {
                VStack(spacing: 10) {
                    ForEach(presets) { preset in
                        HStack(alignment: .center, spacing: 10) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(preset.name).font(.system(size: 13, weight: .medium))
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(preset.summary).font(.system(size: 11)).foregroundStyle(KeepTheme.mutedInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Button("Use") { apply(preset.settings) }
                                .buttonStyle(KeepButtonStyle(emphasis: .primary))
                                .accessibilityLabel("Use preset \(preset.name)")
                                .help("Apply this rhythm; running and paused intervals keep their current duration")
                            if onRemovePreset != nil {
                                Button { removePreset(preset.id) } label: { Image(systemName: "trash") }
                                .buttonStyle(KeepButtonStyle(emphasis: .quiet))
                                .accessibilityLabel("Delete preset \(preset.name)")
                                .help("Delete preset")
                            }
                        }
                        .padding(12)
                        .background(KeepTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .frame(height: min(260, CGFloat(presets.count) * 110))
        }
    }

    private func settingRow(_ title: String, value: Binding<String>, unit: String) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 13, weight: .medium))
            Spacer(minLength: 4)
            TextField(title, text: value)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 13).monospacedDigit())
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                .accessibilityLabel(title)
                .onSubmit(apply)
            Text(unit).font(.system(size: 11)).foregroundStyle(KeepTheme.mutedInk)
                .frame(width: 48, alignment: .leading)
        }
    }

    private func savePreset() {
        guard canSavePreset, let settings, let onSavePreset else { return }
        do {
            try onSavePreset(presetName, settings)
            presetName = ""
            section = .presets
            error = nil
        } catch let failure { error = failure.localizedDescription }
    }

    private func removePreset(_ id: UUID) {
        guard let onRemovePreset else { return }
        do { try onRemovePreset(id); error = nil }
        catch let failure { error = failure.localizedDescription }
    }

    private func apply() {
        guard let settings else { return }
        apply(settings)
    }

    private func apply(_ settings: PomodoroSettings) {
        if onApply(settings) { dismiss() }
        else { error = "Couldn’t apply settings. Retry loading your saved workspace." }
    }
}

#Preview {
    PomodoroSettingsPopover(settings: .defaults) { _ in true }
}
