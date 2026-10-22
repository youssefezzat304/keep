import SwiftUI

struct SessionDeletionDialog: View {
    let session: RecordedSession
    let canDelete: Bool
    let onDelete: () throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Delete this session?").font(KeepTheme.headingFont(size: 27))
            Text(session.title).font(.system(size: 15, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            Text("This removes the session from Calendar and subtracts its recorded time from Timesheet. This cannot be undone.")
                .font(.system(size: 13)).foregroundStyle(KeepTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            if let error {
                Text(error).font(.system(size: 12)).foregroundStyle(KeepTheme.accentStrong)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(KeepButtonStyle(emphasis: .quiet))
                    .keyboardShortcut(.cancelAction)
                Button("Delete", role: .destructive) {
                    do { try onDelete(); dismiss() }
                    catch { self.error = error.localizedDescription }
                }
                .buttonStyle(KeepButtonStyle(emphasis: .primary))
                .disabled(!canDelete)
            }
        }
        .padding(24).frame(width: 420)
        .foregroundStyle(KeepTheme.ink).background(KeepTheme.paper)
    }
}
