import SwiftUI

/// Display refresh only; the workspace remains the single timing and recording owner.
struct MenuBarLabel: View {
    let workspace: WorkspaceModel
    let timer: MenuBarTimer
    var showFlowSeconds = true

    private var selectedTimer: FocusTimer? {
        switch timer { case .pomodoro: workspace.pomodoro; case .flow: workspace.flow; case .none: nil }
    }

    var body: some View {
        let instant = workspace.displayInstant
        HStack(spacing: 4) {
            Image(systemName: "leaf.fill")
            if let selectedTimer {
                Text(Self.display(selectedTimer, showFlowSeconds: showFlowSeconds, at: instant)).monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Keep")
        .accessibilityValue(selectedTimer.map { "\(timer.title) \(Self.display($0, showFlowSeconds: showFlowSeconds, at: instant))" } ?? "Open focus controls")
    }

    static func display(_ timer: FocusTimer, showFlowSeconds: Bool, at instant: ContinuousClock.Instant) -> String {
        guard timer.mode == .flow, !showFlowSeconds else { return timer.display(at: instant) }
        let seconds = timer.seconds(at: instant)
        return String(format: "%02d:%02d", seconds / 3600, seconds / 60 % 60)
    }

}
