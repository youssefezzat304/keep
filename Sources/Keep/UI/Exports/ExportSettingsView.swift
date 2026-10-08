import SwiftUI
import AppKit

struct ExportSettingsView: View {
    @State private var model: ExportModel
    @State private var showingProjects = false
    @State private var showingTasks = false
    init(capture: SnapshotCapture) { _model = State(initialValue: ExportModel(capture: capture)) }
    init(model: ExportModel) { _model = State(initialValue: model) }

    private var projectTitle: String {
        model.projects.first { $0.id == model.projectID }.map { $0.name + ($0.deleted ? " (Deleted)" : "") } ?? "All projects"
    }
    private var taskTitle: String { model.taskKeys.map { "\($0.count) selected" } ?? "All tasks" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Export", systemImage: "square.and.arrow.up").font(KeepTheme.headingFont(size: 24))
            VStack(alignment: .leading, spacing: 16) {
                row("Data") {
                    KeepSelectionMenu(label: "Export data", selection: $model.data, options: ExportData.allCases, title: { $0.rawValue }).frame(width: 180)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { dateField("From", date: $model.from); dateField("Through", date: $model.through) }
                    VStack(alignment: .leading, spacing: 12) { dateField("From", date: $model.from); dateField("Through", date: $model.through) }
                }
                row("Project") {
                    Button { showingProjects = true } label: {
                        Text(projectTitle).lineLimit(1)
                    }.buttonStyle(KeepButtonStyle()).accessibilityLabel("Export project").accessibilityValue(projectTitle)
                }
                .popover(isPresented: $showingProjects) {
                    StatsProjectPicker(options: model.projects, selection: model.projectID) { model.projectID = $0; model.taskKeys = nil }
                }
                if model.data != .timesheet, model.projectID != nil {
                    row("Tasks") {
                        Button { showingTasks = true } label: { Text(taskTitle) }
                            .buttonStyle(KeepButtonStyle()).accessibilityLabel("Export tasks").accessibilityValue(taskTitle)
                    }
                    .popover(isPresented: $showingTasks) {
                        StatsTaskPicker(options: model.taskOptions, selection: model.taskKeys) { model.taskKeys = $0 }
                    }
                }
            }.disabled(model.status.busy)
            HStack {
                Text(model.data.format).font(.system(size: 13)).foregroundStyle(KeepTheme.mutedInk)
                Spacer()
                if model.status.busy { ProgressView().controlSize(.small) }
                if model.status == .preparing { Button("Cancel") { model.cancel() }.accessibilityLabel("Cancel export preparation") }
                Button("Export…") { model.start() }.buttonStyle(KeepButtonStyle(emphasis: .primary))
                    .disabled(!model.valid || model.status.busy || model.capture.gate?.isLocked == true)
            }
            if !model.valid { Text(ExportFailure.invalidRequest.localizedDescription).font(.system(size: 13)).foregroundStyle(KeepTheme.accentStrong) }
            if let message = model.status.message {
                Text(message).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("exportStatus")
                if case .error = model.status { Button("Retry") { model.retry() }.accessibilityLabel("Retry export data") }
            }
        }
        .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        .background(KeepTheme.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(KeepTheme.border).allowsHitTesting(false) }
        .background(ExportWindowBridge(model: model).frame(width: 0, height: 0))
        .onDisappear { model.cancel() }
        .onChange(of: model.capture.gate?.generation) { model.cancel() }
        .onChange(of: model.capture.gate?.isLocked) { _, locked in if locked == true { model.cancel() } }
    }
    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 16) { Text(title); Spacer(minLength: 12); content() }
    }
    private func dateField(_ title: String, date: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13))
            HabitDateField(label: "Export \(title.lowercased()) date", date: date, calendar: model.calendar).frame(minWidth: 180)
        }
    }
}

/// Binds the save sheet to this window, and cancels work when that window closes.
private struct ExportWindowBridge: NSViewRepresentable {
    let model: ExportModel
    func makeNSView(context: Context) -> Reader { Reader(model: model) }
    func updateNSView(_ view: Reader, context: Context) { view.connect() }
    static func dismantleNSView(_ view: Reader, coordinator: ()) { view.disconnect(); view.model.cancel() }
    final class Reader: NSView {
        let model: ExportModel
        var observer: NSObjectProtocol?
        init(model: ExportModel) { self.model = model; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); connect() }
        func disconnect() {
            if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
        }
        func connect() {
            guard model.window !== window else { return }
            disconnect(); model.window = window
            if let window {
                observer = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak model] _ in
                    MainActor.assumeIsolated { model?.cancel() }
                }
            }
        }
    }
}
