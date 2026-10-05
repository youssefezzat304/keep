import SwiftUI

struct PomodoroTimerPanel: View {
    @Binding var timer: FocusTimer

    var body: some View {
        FocusTimerCard(timer: $timer)
    }
}

#Preview {
    PomodoroTimerPanel(timer: .constant(FocusTimer(mode: .pomodoro)))
        .padding().frame(width: 450)
}
