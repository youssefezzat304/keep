import AppKit
import SwiftUI

struct TimerNotchView: View {
    let timers: [FocusTimer]
    let instant: ContinuousClock.Instant
    let layout: PomodoroOverlayLayout
    let notice: PomodoroCompletionNotice?
    let dismiss: () -> Void
    let next: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            if let notice {
                CompletionHeading(notice: notice)
                HStack(spacing: 12) {
                    Button("Dismiss", action: dismiss).keyboardShortcut(.cancelAction)
                    Button(notice.isBreak ? "Start focus" : "Start break", action: next)
                        .keyboardShortcut(.defaultAction)
                }.buttonStyle(KeepButtonStyle(emphasis: .quiet))
            } else if timers.count == 2 {
                let sideWidth = (layout.frame.width - layout.cameraWidth) / 2
                HStack(spacing: 0) {
                    readout(timers[0]).frame(width: sideWidth)
                    Color.clear.frame(width: layout.cameraWidth)
                    readout(timers[1]).frame(width: sideWidth)
                }
            } else if let timer = timers.first {
                let sideWidth = (layout.frame.width - layout.cameraWidth) / 2
                HStack(spacing: 0) {
                    timerIcon(timer).frame(width: sideWidth)
                    Color.clear.frame(width: layout.cameraWidth)
                    timerText(timer).frame(width: sideWidth)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel(timer))
            }
        }
        .padding(.top, notice == nil ? 0 : layout.topPadding + 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(KeepTheme.accentStrong)
        .background(.black, in: UnevenRoundedRectangle(bottomLeadingRadius: notice == nil ? 10 : 16, bottomTrailingRadius: notice == nil ? 10 : 16))
        .keepAppearance(.dark)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: notice?.id)
    }

    private func timerIcon(_ timer: FocusTimer) -> some View {
        Image(systemName: timer.phase(at: instant) == .stopped ? "pause.fill" : timer.mode == .flow ? "infinity" : timer.interval == .rest ? "cup.and.saucer" : "timer")
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(timerColor(timer))
    }
    private func timerText(_ timer: FocusTimer) -> some View {
        Text(TimerNotchFormat.display(timer, at: instant)).font(.system(size: 14, weight: .medium)).monospacedDigit()
            .lineLimit(1).fixedSize()
            .foregroundStyle(timerColor(timer))
    }
    private func timerColor(_ timer: FocusTimer) -> Color {
        if timer.phase(at: instant) == .stopped { return .white }
        return timer.mode == .flow ? KeepTheme.flowNotchInk : KeepTheme.accentStrong
    }
    private func readout(_ timer: FocusTimer) -> some View {
        HStack(spacing: 8) { timerIcon(timer); timerText(timer) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(timer))
    }
    private func accessibilityLabel(_ timer: FocusTimer) -> String {
        let name = timer.mode == .flow ? "Flow" : timer.interval == .rest ? "Pomodoro break" : "Pomodoro focus"
        let seconds = timer.seconds(at: instant)
        let duration = timer.mode == .flow ? "\(seconds / 3600) hours, \(seconds / 60 % 60) minutes" : timer.display(at: instant)
        return "\(name), \(timer.phase(at: instant) == .stopped ? "paused" : "running"), \(duration) \(timer.mode == .flow ? "elapsed" : "remaining")"
    }

}

private struct CompletionHeading: View {
    let notice: PomodoroCompletionNotice
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 28))
                .scaleEffect(appeared || reduceMotion ? 1 : 0.5)
                .opacity(appeared || reduceMotion ? 1 : 0)
            Text(notice.title).font(KeepTheme.headingFont(size: 23))
        }
        .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { appeared = true } }
    }
}

