import SwiftUI

struct FlowTimerPanel: View {
    @Binding var timer: FocusTimer

    var body: some View {
        FocusTimerCard(timer: $timer)
    }
}

#Preview {
    FlowTimerPanel(timer: .constant(FocusTimer(mode: .flow)))
        .padding().frame(width: 450)
}
