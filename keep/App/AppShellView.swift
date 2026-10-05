import SwiftUI

enum WorkspaceTab {
    case focus
    case timesheet
}

struct AppShellView: View {
    @State private var workspace: WorkspaceModel
    @State private var selectedTab: WorkspaceTab

    init(initialTab: WorkspaceTab = .focus, workspace: WorkspaceModel = WorkspaceModel()) {
        _workspace = State(initialValue: workspace)
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
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

                    // Keep the focus view mounted so changing tabs preserves its local state.
                    ZStack(alignment: .top) {
                        FocusSessionView(workspace: workspace, isCompact: geometry.size.width < 820)
                            .frame(height: selectedTab == .focus ? nil : 0, alignment: .top)
                            .clipped()
                            .opacity(selectedTab == .focus ? 1 : 0)
                            .allowsHitTesting(selectedTab == .focus)
                            .accessibilityHidden(selectedTab != .focus)

                        TimesheetView(workspace: workspace)
                            .frame(height: selectedTab == .timesheet ? nil : 0, alignment: .top)
                            .clipped()
                            .opacity(selectedTab == .timesheet ? 1 : 0)
                            .allowsHitTesting(selectedTab == .timesheet)
                            .accessibilityHidden(selectedTab != .timesheet)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .background(KeepTheme.paper, in: RoundedRectangle(cornerRadius: 28))
                .overlay {
                    RoundedRectangle(cornerRadius: 28)
                        .strokeBorder(KeepTheme.border.opacity(0.5), lineWidth: 1)
                }
                .padding(16)
                // Center the panel when it fits; let taller layouts scroll naturally.
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
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
