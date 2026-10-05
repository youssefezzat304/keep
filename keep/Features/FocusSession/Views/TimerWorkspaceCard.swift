import SwiftUI

struct TimerWorkspaceCard: View {
    @Binding var pomodoro: FocusTimer
    @Binding var flow: FocusTimer
    var isCompact = false

    var body: some View {
        if isCompact {
            VStack(spacing: 18) { panels }
        } else {
            HStack(alignment: .top, spacing: 18) { panels }
        }
    }

    @ViewBuilder private var panels: some View {
        PomodoroTimerPanel(timer: $pomodoro)
        FlowTimerPanel(timer: $flow)
    }
}

#Preview {
    TimerWorkspaceCard(
        pomodoro: .constant(FocusTimer(mode: .pomodoro)),
        flow: .constant(FocusTimer(mode: .flow))
    )
    .padding().frame(width: 900)
}
