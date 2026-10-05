import SwiftUI

enum WorkspaceTab {
    case focus
    case timesheet
}

struct AppShellView: View {
    @State private var workspace: WorkspaceModel
    @State private var music: MusicPlayerModel
    @State private var selectedTab: WorkspaceTab

    init(initialTab: WorkspaceTab = .focus, workspace: WorkspaceModel = WorkspaceModel(), music: MusicPlayerModel = MusicPlayerModel()) {
        _workspace = State(initialValue: workspace)
        _music = State(initialValue: music)
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 24) {
                NavBar(
                    isTimesheetSelected: selectedTab == .timesheet,
                    onSelectFocus: { selectedTab = .focus },
                    onSelectTimesheet: { selectedTab = .timesheet }
                )

                if let message = workspace.persistenceError {
                    HStack {
                        Text(message).font(.system(size: 13))
                        Spacer()
                        Button("Retry") { workspace.retryPersistence() }
                    }
                    .padding(12)
                    .background(KeepTheme.highlight, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityElement(children: .contain)
                }

                // Each tab keeps its content and scroll position inside the same viewport.
                ZStack(alignment: .top) {
                    GeometryReader { viewport in
                        ScrollView {
                            FocusSessionView(workspace: workspace, music: music, isCompact: geometry.size.width < 820, minimumHeight: viewport.size.height)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    }
                    .opacity(selectedTab == .focus ? 1 : 0)
                    .allowsHitTesting(selectedTab == .focus)
                    .accessibilityHidden(selectedTab != .focus)

                    ScrollView {
                        TimesheetView(workspace: workspace)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .opacity(selectedTab == .timesheet ? 1 : 0)
                    .allowsHitTesting(selectedTab == .timesheet)
                    .accessibilityHidden(selectedTab != .timesheet)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(KeepTheme.paper, in: RoundedRectangle(cornerRadius: 28))
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .overlay {
                RoundedRectangle(cornerRadius: 28)
                    .strokeBorder(KeepTheme.border.opacity(0.5), lineWidth: 1)
            }
            .padding(16)
            .background(KeepTheme.background)
        }
        .frame(minWidth: 680, minHeight: 650)
        .foregroundStyle(KeepTheme.ink)
        .tint(KeepTheme.accentStrong)
        .preferredColorScheme(.light)
        .onAppear { workspace.startUpdating() }
    }
}

#Preview("Focus") {
    AppShellView().frame(width: 1000, height: 900)
}

#Preview("Timesheet") {
    AppShellView(initialTab: .timesheet, workspace: TimesheetPreviewData.workspace()).frame(width: 1000, height: 900)
}

#Preview("Wide window") {
    AppShellView().frame(width: 1710, height: 1080)
}
