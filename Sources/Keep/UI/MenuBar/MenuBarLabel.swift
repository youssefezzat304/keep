import SwiftUI

/// Display refresh only; the workspace remains the single timing and recording owner.
struct MenuBarLabel: View {
    let workspace: WorkspaceModel
    let timer: MenuBarTimer

    private var selectedTimer: FocusTimer? {
        switch timer { case .pomodoro: workspace.pomodoro; case .flow: workspace.flow; case .none: nil }
    }

    var body: some View {
        let instant = workspace.displayInstant
        HStack(spacing: 4) {
            Image(systemName: "leaf.fill")
            if let selectedTimer {
                Text(selectedTimer.display(at: instant)).monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Keep")
        .accessibilityValue(selectedTimer.map { "\(timer.title) \($0.display(at: instant))" } ?? "Open focus controls")
    }
}
