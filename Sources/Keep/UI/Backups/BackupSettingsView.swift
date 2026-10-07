import SwiftUI

struct BackupSettingsView: View {
    @Bindable var backup: BackupModel
    @State private var showingRestore = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("iCloud Backup", systemImage: "icloud.and.arrow.up")
                .font(KeepTheme.headingFont(size: 24))
            Toggle("Automatic iCloud backup", isOn: Binding(get: { backup.automatic }, set: { enabled in
                Task { await backup.setAutomatic(enabled) }
            }))
            .toggleStyle(.switch).controlSize(.small)
            .disabled(backup.busy || backup.configurationError != nil || backup.gate.isLocked)
            Text("Hourly when your data changes, while Keep is open. Backups replace saved data only when you choose Restore.")
                .font(.system(size: 13)).foregroundStyle(KeepTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Back up now") { Task { await backup.backUpNow() } }
                    .disabled(backup.busy || backup.configurationError != nil || backup.gate.isLocked)
                Button("Restore backup…") {
                    showingRestore = true
                    Task { await backup.refreshVersions() }
                }.disabled(backup.busy || backup.gate.isLocked)
                if backup.busy { ProgressView().controlSize(.small) }
            }
            if let date = backup.lastUploadConfirmed {
                Text("Last upload confirmed: \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 13)).foregroundStyle(KeepTheme.mutedInk)
            } else {
                Text("No upload confirmed yet.").font(.system(size: 13)).foregroundStyle(KeepTheme.mutedInk)
            }
            Text(backup.configurationError ?? backup.gate.recoveryError ?? backup.status.message)
                .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("backupStatus")
            if case .error = backup.status, !backup.gate.isLocked, backup.canRetryUpload {
                Button("Retry upload") { Task { await backup.retryPending() } }.disabled(backup.busy)
            }
            if backup.status == .offline, backup.canRetryUpload {
                Button("Retry") { Task { await backup.retryPending() } }.disabled(backup.busy)
            }
        }
        .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        .background(KeepTheme.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(KeepTheme.border).allowsHitTesting(false) }
        .sheet(isPresented: $showingRestore, onDismiss: { backup.cancelPreview() }) {
            BackupRestoreView(backup: backup)
        }
    }
}

struct BackupRestoreView: View {
    @Bindable var backup: BackupModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirming = false
    @State private var selection: Task<Void, Never>?
    @FocusState private var focusedVersion: String?
    private var groups: [String] { Set(backup.versions.map { $0.isRecovery ? "On this Mac — before restore" : $0.deviceID }).sorted() }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Restore a backup").font(KeepTheme.headingFont(size: 28))
            Text("Choose a dated version. This replaces projects, recorded time, tasks, habits, suggestions and portable settings on this Mac.")
                .font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
            if backup.versions.isEmpty && !backup.busy {
                Text("No backups found. Check iCloud Drive or try Refresh.").foregroundStyle(KeepTheme.mutedInk)
            }
            KeepScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(groups, id: \.self) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group == backup.localState.deviceID.uuidString ? "This Mac" : group.hasPrefix("On this Mac") ? group : "Mac \(group.prefix(8))")
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(KeepTheme.mutedInk)
                            ForEach(backup.versions.filter { ($0.isRecovery ? "On this Mac — before restore" : $0.deviceID) == group }) { version in
                                Button {
                                    selection?.cancel()
                                    selection = Task { await backup.prepareRestore(version) }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(version.createdAt.formatted(date: .abbreviated, time: .standard))
                                            Text(version.isRecovery ? "Local recovery copy" : version.downloaded ? "Available on this Mac" : "Download from iCloud")
                                                .font(.system(size: 12)).foregroundStyle(KeepTheme.mutedInk)
                                        }
                                        Spacer()
                                        if backup.preview?.filename == version.url.lastPathComponent { Image(systemName: "checkmark") }
                                    }.padding(10).contentShape(Rectangle())
                                }.buttonStyle(.plain).disabled(backup.busy)
                                .focused($focusedVersion, equals: version.id)
                                .background(KeepTheme.paper, in: RoundedRectangle(cornerRadius: 10))
                                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(focusedVersion == version.id ? KeepTheme.focusRing : .clear, lineWidth: 2).allowsHitTesting(false) }
                            }
                        }
                    }
                }
            }.frame(minHeight: 80, maxHeight: 200)
            if let preview = backup.preview {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Backup from \(preview.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 14, weight: .semibold))
                    Text(backup.previewSummary).font(.system(size: 13))
                    Text("Timers will stop and music will pause. A recovery copy is saved first. Wallpaper folders stay local; reselect a folder if it is unavailable.")
                        .font(.system(size: 13)).foregroundStyle(KeepTheme.mutedInk).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let warning = backup.recoveryWarning { Text(warning).font(.system(size: 13)) }
            Text(backup.restoreActivity ?? backup.status.message).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Refresh") { Task { await backup.refreshVersions() } }.disabled(backup.busy)
                Spacer()
                if backup.busy { ProgressView().controlSize(.small) }
                Button("Cancel") { selection?.cancel(); backup.cancelPreview(); dismiss() }.keyboardShortcut(.cancelAction).disabled(backup.gate.isLocked)
                Button("Restore…") { confirming = true }.disabled(backup.preview == nil || backup.busy)
            }
        }
        .padding(24).frame(width: 520)
        .foregroundStyle(KeepTheme.ink).background(KeepTheme.paper)
        .interactiveDismissDisabled(backup.gate.isLocked)
        .onDisappear { selection?.cancel(); backup.cancelPreview() }
        .confirmationDialog("Replace this Mac’s saved Keep data?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Replace data and restore", role: .destructive) { Task { await backup.restore(); if !backup.gate.isLocked && backup.preview == nil { dismiss() } } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Timers stop and music pauses. Your current saved data is copied to local recovery storage before replacement.")
        }
    }
}
