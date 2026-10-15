import SwiftUI

struct TimerSettingsControls: View {
    @Bindable var preferences: AppPreferences
    @Environment(TimerSoundPlayer.self) private var sounds: TimerSoundPlayer?
    @State private var showsReminder = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Show Pomodoro timer", isOn: $preferences.showPomodoroTimer)
            Toggle("Show Pomodoro progress outline", isOn: $preferences.showPomodoroProgress)
                .disabled(!preferences.showPomodoroTimer)
            Toggle("Show Flow timer", isOn: $preferences.showFlowTimer)
            Text("Hidden timers disappear from Focus, Zen and the menu bar. Running sessions keep counting, and their sound reminders stay enabled.")
                .font(.system(size: 12)).foregroundStyle(KeepTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
            Divider().overlay(KeepTheme.border)
            Toggle("Show Pomodoro at the notch", isOn: $preferences.notchPomodoroTimer)
            Toggle("Animate interval completion at the notch", isOn: $preferences.notchPomodoroCompletion)
            Text("These options work independently. Displays without a notch use a panel at the top center. The timer appears during running or paused intervals.")
                .font(.system(size: 12)).foregroundStyle(KeepTheme.mutedInk).fixedSize(horizontal: false, vertical: true)
            Toggle("Blur screens during Pomodoro breaks", isOn: $preferences.blurPomodoroBreaks)
            Text("When focus ends, starts the break automatically and covers connected screens instead of expanding the notch. Dismiss with Escape to keep the break counting, or choose Skip break to start focus.")
                .font(.system(size: 12)).foregroundStyle(KeepTheme.mutedInk).fixedSize(horizontal: false, vertical: true)
            Divider().overlay(KeepTheme.border)
            Toggle("Play timer sounds", isOn: $preferences.timerSoundsEnabled)
                .onChange(of: preferences.timerSoundsEnabled) { _, enabled in
                    if !enabled { sounds?.stop() }
                }
            Toggle("Repeat Pomodoro completion sound", isOn: $preferences.repeatPomodoroSound)
                .disabled(!preferences.timerSoundsEnabled)
            if preferences.repeatPomodoroSound {
                KeepSelectionMenu(label: "Repeat sound", selection: $preferences.pomodoroSoundRepeatMode,
                                  options: PomodoroSoundRepeatMode.allCases, title: { $0.title })
                if preferences.pomodoroSoundRepeatMode == .count {
                    Stepper("Play \(preferences.pomodoroSoundRepeatCount) times", value: $preferences.pomodoroSoundRepeatCount, in: 2...20)
                }
                Text("Applies to focus and break completion. Stops when dismissed, you manually start or stop a Pomodoro interval, or sounds are turned off. Automatic breaks do not interrupt repeats. Fixed counts include the first play.")
                    .font(.system(size: 12)).foregroundStyle(KeepTheme.mutedInk).fixedSize(horizontal: false, vertical: true)
            }
            if sounds?.isRepeating == true {
                Button("Stop completion sound") { sounds?.stopRepeating() }
                    .buttonStyle(KeepButtonStyle(emphasis: .quiet))
            }
            ForEach(TimerSound.allCases, id: \.self) { sound in soundPreview(sound) }
            reminderControl
            if let error = sounds?.errorMessage {
                Text(error).font(.system(size: 12)).foregroundStyle(KeepTheme.accentStrong)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Sounds play while Keep is open, including when its windows are closed. Flow reminders are off until you choose an interval.")
                .font(.system(size: 12)).foregroundStyle(KeepTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 13)).toggleStyle(.switch).controlSize(.small)
        .disabled(!preferences.canEdit)
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
