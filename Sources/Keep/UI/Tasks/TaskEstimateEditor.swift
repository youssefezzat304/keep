import SwiftUI

struct TaskEstimateEditor: View {
    let onSave: (String, Int?) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var estimate: String
    @State private var error: String?

    init(task: FocusTask, onSave: @escaping (String, Int?) throws -> Void) {
        self.onSave = onSave
        _title = State(initialValue: task.title)
        _estimate = State(initialValue: task.estimateMinutes.map(String.init) ?? "")
    }
    private var trimmed: String { estimate.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var validEstimate: Bool { trimmed.isEmpty || Int(trimmed).map { (1...1440).contains($0) } == true }
    private var valid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && validEstimate
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("A little plan").font(KeepTheme.headingFont(size: 24))
            TextField("Task name", text: $title).modifier(KeepInputStyle()).accessibilityLabel("Task name").onSubmit(save)
            VStack(alignment: .leading, spacing: 10) {
                Text("Estimate").font(.system(size: 13, weight: .medium))
                HStack {
                    TextField("Not estimated", text: $estimate).modifier(KeepInputStyle())
                        .accessibilityLabel("Estimated focus minutes").onSubmit(save)
                    Text("minutes").foregroundStyle(KeepTheme.mutedInk)
                }
                HStack(spacing: 8) {
                    ForEach([15, 30, 45, 60], id: \.self) { minutes in
                        Button("\(minutes)m") { estimate = String(minutes) }
                            .buttonStyle(KeepButtonStyle(emphasis: Int(trimmed) == minutes ? .secondary : .quiet))
                            .accessibilityLabel("Estimate \(minutes) minutes")
                    }
                    Button { estimate = "" } label: { Image(systemName: "xmark") }
                        .buttonStyle(KeepButtonStyle(emphasis: .quiet)).accessibilityLabel("Clear estimate")
                }
            }
            Text(validEstimate ? "Expected focus effort, independent of your timer intervals. Leave it blank if you’re unsure." : "Enter a whole number from 1 to 1,440 minutes, or leave the estimate blank.")
                .font(.system(size: 12)).foregroundStyle(validEstimate ? KeepTheme.mutedInk : KeepTheme.accentStrong).fixedSize(horizontal: false, vertical: true)
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(KeepTheme.accentStrong).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(KeepButtonStyle(emphasis: .quiet)).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save", action: save).buttonStyle(KeepButtonStyle(emphasis: .primary)).keyboardShortcut(.defaultAction).disabled(!valid)
            }
        }.font(.system(size: 13)).padding(24).frame(width: 380)
            .background(KeepTheme.surface).foregroundStyle(KeepTheme.ink).tint(KeepTheme.accentStrong)
    }
    private func save() {
        guard valid else { return }
        do { try onSave(title, trimmed.isEmpty ? nil : Int(trimmed)); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
