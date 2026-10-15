import SwiftUI

struct TimerSettingsControls: View {
    @Bindable var preferences: AppPreferences
    @Environment(TimerSoundPlayer.self) private var sounds: TimerSoundPlayer?
    @State private var showsReminder = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            timerToggle("Show Pomodoro timer", isOn: $preferences.showPomodoroTimer)
            timerToggle("Show Pomodoro progress outline", isOn: $preferences.showPomodoroProgress)
                .disabled(!preferences.showPomodoroTimer)
            timerToggle("Show Flow timer", isOn: $preferences.showFlowTimer)
            Divider().overlay(KeepTheme.border)
            timerToggle("Show Flow at the notch", isOn: $preferences.notchFlowTimer)
            timerToggle("Show Pomodoro at the notch", isOn: $preferences.notchPomodoroTimer)
            timerToggle("Animate interval completion at the notch", isOn: $preferences.notchPomodoroCompletion)
            timerToggle("Blur screens during Pomodoro breaks", isOn: $preferences.blurPomodoroBreaks)
            Divider().overlay(KeepTheme.border)
            timerToggle("Play timer sounds", isOn: $preferences.timerSoundsEnabled)
                .onChange(of: preferences.timerSoundsEnabled) { _, enabled in
                    if !enabled { sounds?.stop() }
                }
            timerToggle("Repeat Pomodoro completion sound", isOn: $preferences.repeatPomodoroSound)
                .disabled(!preferences.timerSoundsEnabled)
            if preferences.repeatPomodoroSound {
                KeepSelectionMenu(label: "Repeat sound", selection: $preferences.pomodoroSoundRepeatMode,
                                  options: PomodoroSoundRepeatMode.allCases, title: { $0.title })
                    .frame(maxWidth: .infinity, alignment: .trailing)
                if preferences.pomodoroSoundRepeatMode == .count {
                    Stepper(value: $preferences.pomodoroSoundRepeatCount, in: 2...20) {
                        Text("Play \(preferences.pomodoroSoundRepeatCount) times")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            if sounds?.isRepeating == true {
                Button("Stop completion sound") { sounds?.stopRepeating() }
                    .buttonStyle(KeepButtonStyle(emphasis: .quiet))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            ForEach(TimerSound.allCases, id: \.self) { sound in soundPreview(sound) }
            reminderControl
            if let error = sounds?.errorMessage {
                Text(error).font(.system(size: 12)).foregroundStyle(KeepTheme.accentStrong)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.system(size: 13)).toggleStyle(.switch).controlSize(.small)
        .disabled(!preferences.canEdit)
    }

    private func timerToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func soundPreview(_ sound: TimerSound) -> some View {
        HStack {
            Text(sound.title)
            Spacer()
            Button { sounds?.play(sound) } label: { Image(systemName: "speaker.wave.2").frame(width: 14) }
                .buttonStyle(KeepButtonStyle(emphasis: .quiet))
                .accessibilityLabel("Preview \(sound.title.lowercased()) sound")
                .help("Preview \(sound.title.lowercased()) sound")
                .disabled(sounds == nil || sounds?.isPlaying == true)
        }
    }

    private var reminderControl: some View {
        HStack {
            Text("Flow reminders")
            Spacer()
            Button(preferences.flowReminderMinutes.map { "Every \($0) min" } ?? "Off") { showsReminder = true }
                .buttonStyle(KeepButtonStyle(emphasis: .quiet))
                .accessibilityLabel("Configure Flow reminders")
                .popover(isPresented: $showsReminder) {
                    FlowReminderPopover(minutes: preferences.flowReminderMinutes) { preferences.setFlowReminder(minutes: $0) }
                }
        }
    }
}
