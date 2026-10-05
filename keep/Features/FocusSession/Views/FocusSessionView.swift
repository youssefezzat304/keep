import SwiftUI

struct FocusSessionView: View {
    var isCompact = false
    @State private var pomodoro = FocusTimer(mode: .pomodoro)
    @State private var flow = FocusTimer(mode: .flow)
    @State private var target = "Your next good idea"
    @State private var tasks = FocusTask.examples

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ActiveTargetHeader(target: $target, isCompact: isCompact)

            TimerWorkspaceCard(pomodoro: $pomodoro, flow: $flow, isCompact: isCompact)

            if isCompact {
                VStack(spacing: 18) { supportingCards }
            } else {
                HStack(alignment: .top, spacing: 18) { supportingCards }
            }

            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .foregroundStyle(KeepTheme.accentStrong)
                    .accessibilityHidden(true)
                Text("Less hurry. More here.")
                Spacer()
                Text(Date.now, format: .dateTime.month(.wide).day())
            }
            .font(.system(size: 12))
            .foregroundStyle(KeepTheme.mutedInk)
        }
    }

    @ViewBuilder private var supportingCards: some View {
        MusicPlayerCard()
        TasksCard(tasks: $tasks)
    }
}

#Preview {
    FocusSessionView()
        .padding().frame(width: 950).background(KeepTheme.paper)
}
