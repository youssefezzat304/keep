import AppKit
import SwiftUI

/// Display refresh only; the workspace remains the single timing and recording owner.
struct MenuBarLabel: View {
    let workspace: WorkspaceModel
    let timer: MenuBarTimer
    var showFlowSeconds = true
    @State private var renderedImage: NSImage?

    private struct Readout: Equatable {
        let text: String?
        let progress: Double?
    }

    var body: some View {
        let instant = workspace.displayInstant
        let selection = Self.displayedTimer(preference: timer, pomodoro: workspace.pomodoro,
                                            flow: workspace.flow, at: instant)
        let selectedTimer: FocusTimer? = switch selection {
        case .pomodoro: workspace.pomodoro
        case .flow: workspace.flow
        case .none: nil
        }
        let readout = Readout(text: selectedTimer.map { Self.display($0, showFlowSeconds: showFlowSeconds, at: instant) },
            progress: selection == .pomodoro ? min(1, workspace.pomodoro.elapsed(at: instant) / workspace.pomodoro.intervalDuration) : nil)
        Group {
            if let renderedImage {
                Image(nsImage: renderedImage)
            } else {
                // Retain a native readout if an image cannot be rendered.
                HStack(spacing: 4) {
                    Image(systemName: "leaf.fill")
                    if let text = readout.text { Text(text).monospacedDigit() }
                }
            }
        }
        .onChange(of: readout, initial: true) { _, value in
            renderedImage = Self.renderImage(text: value.text, progress: value.progress)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Keep")
        .accessibilityValue(selectedTimer.map {
            let title = selection == .pomodoro && $0.interval == .rest ? "Pomodoro break" : selection.title
            return "\(title) \(Self.display($0, showFlowSeconds: showFlowSeconds, at: instant))"
        } ?? "Open focus controls")
    }

    /// Native status labels extract images/text, so render the perimeter into a
    /// small template image. macOS supplies the correct ink in either appearance.
    /// Called only when the workspace's readout changes, outside view composition.
    static func renderImage(text: String?, progress: Double?) -> NSImage? {
        let content = HStack(spacing: 4) {
            Image(systemName: "leaf.fill")
            if let text {
                Text(text).monospacedDigit()
                    .padding(.horizontal, 3)
                    .frame(height: 18)
                    .overlay {
                        if let progress {
                            PomodoroProgressBorder(progress: progress, isRunning: false,
                                cornerRadius: 4, lineWidth: 1, color: .black)
                        }
                    }
            }
        }.font(.system(size: 13)).foregroundStyle(.black).fixedSize()
        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = true
        return image
    }

    /// A single running timer takes priority; icon-only remains an explicit opt-out.
    static func displayedTimer(preference: MenuBarTimer, pomodoro: FocusTimer, flow: FocusTimer,
                               at instant: ContinuousClock.Instant) -> MenuBarTimer {
        guard preference != .none else { return .none }
        let pomodoroRunning = pomodoro.phase(at: instant) == .running
        let flowRunning = flow.phase(at: instant) == .running
        if pomodoroRunning != flowRunning { return pomodoroRunning ? .pomodoro : .flow }
        return preference
    }

    static func display(_ timer: FocusTimer, showFlowSeconds: Bool, at instant: ContinuousClock.Instant) -> String {
        guard timer.mode == .flow, !showFlowSeconds else { return timer.display(at: instant) }
        let seconds = timer.seconds(at: instant)
        return String(format: "%02d:%02d", seconds / 3600, seconds / 60 % 60)
    }

}
