import AppKit
import SwiftUI

struct PomodoroTopView: View {
    let timer: FocusTimer
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
            } else {
                let sideWidth = (layout.frame.width - layout.cameraWidth) / 2
                HStack(spacing: 0) {
                    Image(systemName: timer.phase(at: instant) == .stopped ? "pause.fill" : timer.interval == .rest ? "cup.and.saucer" : "timer")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: sideWidth)
                    Color.clear.frame(width: layout.cameraWidth)
                    Text(timer.display(at: instant))
                        .font(.system(size: 14, weight: .medium)).monospacedDigit()
                        .lineLimit(1).fixedSize().frame(width: sideWidth)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Pomodoro \(timer.interval == .rest ? "break" : "focus"), \(timer.phase(at: instant) == .stopped ? "paused" : "running"), \(timer.display(at: instant)) remaining")
            }
        }
        .padding(.top, notice == nil ? 0 : layout.topPadding + 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(KeepTheme.accentStrong)
        .background(.black, in: UnevenRoundedRectangle(bottomLeadingRadius: notice == nil ? 10 : 16, bottomTrailingRadius: notice == nil ? 10 : 16))
        .keepAppearance(.dark)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: notice?.id)
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

struct PomodoroBreakView: View {
    let timer: FocusTimer
    let instant: ContinuousClock.Instant
    let date: Date
    var screenTopInset: CGFloat = 0
    let dismiss: () -> Void
    let start: () -> Void
    let skip: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var waitingToStart: Bool { timer.interval == .focus }
    private var isLongBreak: Bool { waitingToStart ? timer.breakIsLong(at: instant) : timer.isLongBreak }
    private var breakDisplay: String {
        guard waitingToStart else { return timer.display(at: instant) }
        let seconds = Int(ceil(timer.upcomingBreakDuration(at: instant)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    var body: some View {
        GeometryReader { bounds in
            VStack(spacing: 24) {
                Text(date, format: .dateTime.hour().minute())
                    .font(.system(size: 18)).foregroundStyle(KeepTheme.secondaryInk)
                    .accessibilityLabel("Current time")
                    .accessibilityValue(date.formatted(.dateTime.hour().minute()))
                Spacer(minLength: 10)
                Image(systemName: "cup.and.saucer").font(.system(size: 40, weight: .light)).accessibilityHidden(true)
                Text(isLongBreak ? "Take a longer rest." : "Catch a quick rest.")
                    .font(KeepTheme.headingFont(size: bounds.size.width < 800 ? 38 : 64))
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Text(waitingToStart ? "Focus complete. Start your break when you’re ready." : "Look away from the screen. Your next focus interval can wait.")
                    .font(.system(size: 18)).foregroundStyle(KeepTheme.secondaryInk).multilineTextAlignment(.center)
                Text(breakDisplay).font(.system(size: 60, weight: .light)).monospacedDigit()
                    .accessibilityLabel("\(waitingToStart ? "Break duration" : "Break remaining"), \(breakDisplay)")
                Spacer(minLength: 10)
                HStack(spacing: 16) {
                    Button("Dismiss overlay", action: dismiss).keyboardShortcut(.cancelAction)
                    if waitingToStart {
                        Button("Start break", action: start).keyboardShortcut(.defaultAction)
                    } else {
                        Button("Skip break", action: skip)
                    }
                }.buttonStyle(KeepButtonStyle(emphasis: .quiet))
                Text(waitingToStart ? "Your break timer hasn’t started. Escape dismisses this screen." : "Escape dismisses this overlay. Your break keeps counting.")
                    .font(.system(size: 12)).foregroundStyle(KeepTheme.mutedInk)
            }
            .padding(.horizontal, 40)
            .padding(.top, max(32, max(bounds.safeAreaInsets.top, screenTopInset) + 16))
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(KeepTheme.ink)
            .background {
                if reduceTransparency { KeepTheme.paper }
                else { BreakScreenMaterial().overlay(KeepTheme.paper.opacity(0.6)) }
            }
        }
        .keepAppearance(.dark)
    }
}

private struct BreakScreenMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .fullScreenUI; view.blendingMode = .behindWindow; view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Remains available even when a user hides both visual timers.
struct StopPomodoroSoundButton: View {
    let workspace: WorkspaceModel
    @Environment(TimerSoundPlayer.self) private var sounds: TimerSoundPlayer?
    var body: some View {
        if sounds?.isRepeating == true {
            Button("Stop completion sound") {
                workspace.dismissPomodoroCompletion()
                sounds?.stopRepeating()
            }.buttonStyle(KeepButtonStyle(emphasis: .quiet))
        }
    }
}
