import SwiftUI
import UniformTypeIdentifiers

struct ImportSettingsView: View {
    @Bindable var model: ImportCoordinator
    @State private var choosingFile = false
    @State private var showingReview = false
    @State private var fileError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Import", systemImage: "square.and.arrow.down").font(KeepTheme.headingFont(size: 24))
            Text("Import all information or selected dates from a Keep data archive (.keepdata) or backup (.keepbackup). App configuration stays on this Mac.")
                .font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
            Text("Existing information is reviewed before replacement. Keep saves a verified local recovery file first.")
                .font(.system(size: 13)).foregroundStyle(KeepTheme.mutedInk).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                if model.phase.busy { ProgressView().controlSize(.small) }
                Spacer(minLength: 8)
                if model.source != nil && !model.phase.busy { Button("Review import…") { showingReview = true } }
                Button("Choose file…") { choosingFile = true }.buttonStyle(KeepButtonStyle(emphasis: .primary))
                    .disabled(!model.canChooseFile)
            }
            if let message = fileError ?? model.message {
                Text(message).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(model.phase == .failed || fileError != nil ? KeepTheme.accentStrong : KeepTheme.secondaryInk)
                    .accessibilityIdentifier("importStatus")
            }
            if model.recoveryURL != nil {
                Button("Show recovery file in Finder") { model.revealRecovery() }
                Text("Importing a recovery file restores overwritten values by merging. It does not remove newly added records.")
                    .font(.system(size: 12)).foregroundStyle(KeepTheme.mutedInk).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        .background(KeepTheme.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(KeepTheme.border).allowsHitTesting(false) }
        // Archives copied from another Mac may still be cached as plain text before
        // Launch Services registers their type. Validate extension and contents on open.
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.data]) { result in
            switch result {
            case .success(let url): fileError = nil; model.open(url); showingReview = true
            case .failure(let error): fileError = "Couldn’t open the file. Choose it again. \(error.localizedDescription)"
            }
        }
        .sheet(isPresented: $showingReview) { ImportReviewView(model: model) }
    }
}

struct ImportReviewView: View {
    @Bindable var model: ImportCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var useDates = false
    @State private var from = Calendar.current.startOfDay(for: .now)
    @State private var through = Calendar.current.startOfDay(for: .now)
    @State private var confirming = false

    private var calendar: Calendar { model.capture.workspace.calendar }
    private func updateScope() {
        model.setScope(useDates ? .dates(from: TaskDay.id(for: from, calendar: calendar), through: TaskDay.id(for: through, calendar: calendar)) : .all)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import Keep data").font(KeepTheme.headingFont(size: 28))
            Text(model.fileName).font(.system(size: 13)).foregroundStyle(KeepTheme.mutedInk).lineLimit(2)
            KeepScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.source != nil {
                        Picker("Import", selection: $useDates) {
                            Text("All information").tag(false)
                            Text("Date range").tag(true)
                        }.pickerStyle(.segmented).disabled(model.phase.busy)
                        if useDates {
                            HStack {
                                Text("From"); Spacer()
                                HabitDateField(label: "Import from date", date: $from, calendar: calendar).frame(width: 180)
                            }.disabled(model.phase.busy)
                            HStack {
                                Text("Through"); Spacer()
                                HabitDateField(label: "Import through date", date: $through, calendar: calendar).frame(width: 180)
                            }.disabled(model.phase.busy)
                        }
                        Text("Related projects, habits and goals are included. Definition and goal changes apply beyond the selected dates. Saved channels are included with All information only.")
                            .font(.system(size: 13)).foregroundStyle(KeepTheme.mutedInk).fixedSize(horizontal: false, vertical: true)
                    }
                    if let review = model.review {
                        Text("\(review.additions) added · \(review.identical) unchanged · \(review.replacements) replaced")
                            .font(.system(size: 14, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                        Text("\(review.supportingRecords) supporting definitions or linked tasks. Timers stop when you apply the import; elapsed time is saved first. Music continues.")
                            .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                        if !review.hasChanges { Text("This import contains no changes.").foregroundStyle(KeepTheme.secondaryInk) }
                        if !review.issues.isEmpty {
                            Text("Review conflicts").font(KeepTheme.headingFont(size: 20))
                            ForEach(review.issues) { issue in issueView(issue) }
                        }
                        DisclosureGroup("Review records") {
                            LazyVStack(alignment: .leading, spacing: 10) {
                                ForEach(Array(review.changes.enumerated()), id: \.offset) { _, change in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("\(change.kind.rawValue) · \(change.category)").font(.system(size: 12, weight: .semibold))
                                        Text(change.detail).font(.system(size: 13)).textSelection(.enabled)
                                    }.fixedSize(horizontal: false, vertical: true)
                                }
                            }.padding(.top, 8)
                        }
                        ForEach(Array(review.blockers.enumerated()), id: \.offset) { _, blocker in
                            Text(blocker).font(.system(size: 13)).foregroundStyle(KeepTheme.accentStrong).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let message = model.message {
                        Text(message).font(.system(size: 13)).foregroundStyle(model.phase == .failed ? KeepTheme.accentStrong : KeepTheme.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("importReviewStatus")
                    }
                    if model.isWaitingForBackup { Text("Wait for backup to finish before applying this import.").font(.system(size: 13)) }
                    if model.recoveryURL != nil { Button("Show recovery file in Finder") { model.revealRecovery() } }
                }.padding(.trailing, 8)
            }.frame(minHeight: 180, maxHeight: .infinity)
            if model.phase.busy {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(progressLabel).font(.system(size: 13))
                }.accessibilityElement(children: .combine)
            }
            HStack(spacing: 12) {
                Spacer(minLength: 8)
                if model.phase == .failed && model.source != nil { Button("Retry review") { model.recalculate() }.disabled(model.phase.busy) }
                Button(model.phase == .success ? "Done" : "Cancel") { if model.phase != .success { model.cancel() }; dismiss() }
                    .keyboardShortcut(.cancelAction).disabled(!model.canCancel)
                Button("Import…") { confirming = true }.buttonStyle(KeepButtonStyle(emphasis: .primary)).disabled(!model.canApply)
            }
        }
        .padding(24).frame(width: 552, height: 540)
        .foregroundStyle(KeepTheme.ink).background(KeepTheme.paper)
        .buttonStyle(KeepButtonStyle()).tint(KeepTheme.accentStrong)
        .interactiveDismissDisabled(!model.canCancel)
        .onAppear {
            if case .dates(let start, let end) = model.scope {
                from = TaskDay.date(for: start, calendar: calendar) ?? from
                through = TaskDay.date(for: end, calendar: calendar) ?? through; useDates = true
            }
        }
        .onChange(of: useDates) { updateScope() }
        .onChange(of: from) { updateScope() }
        .onChange(of: through) { updateScope() }
        .onDisappear { if model.canCancel && model.phase != .success { model.cancel() } }
        .confirmationDialog(model.review?.replacements ?? 0 > 0 ? "Some existing information will be overwritten. Keep will save a backup first." : "Save a recovery file and import this data?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Back up and import", role: model.review?.replacements ?? 0 > 0 ? .destructive : nil) { model.apply() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Add: \(model.review?.additions ?? 0) · Replace: \(model.review?.replacements ?? 0).\n" + confirmationDetails + "\nTimers stop and elapsed time is saved first. A verified recovery file is saved on this Mac before imported data is written.")
        }
    }
    private var progressLabel: String {
        switch model.phase {
        case .loading: "Opening and validating file…"
        case .calculating: "Comparing saved information…"
        case .backingUp: "Saving and verifying recovery file…"
        case .applying: "Applying import…"
        default: "Preparing…"
        }
    }
    private var confirmationDetails: String {
        (model.review?.changes.filter { $0.kind == .replacement }.prefix(6).map { "\($0.category): \($0.detail)" } ?? []).joined(separator: "\n")
    }
    private func issueView(_ issue: ImportIssue) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(issue.title).font(.system(size: 14, weight: .medium)).fixedSize(horizontal: false, vertical: true)
            Text(issue.detail).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Picker(issue.title, selection: Binding<ImportResolution?>(get: {
                model.decisions.resolutions[issue.id] ?? (issue.requiresChoice ? nil : .incoming)
            }, set: { if let value = $0 { model.resolve(issue.id, value) } })) {
                if issue.requiresChoice { Text("Choose…").tag(Optional<ImportResolution>.none) }
                ForEach(issue.choices, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
            }.labelsHidden().accessibilityLabel(issue.title).disabled(model.phase.busy)
            if issue.needsName && model.decisions.resolutions[issue.id] == .both {
                TextField("Unique name", text: Binding(get: { model.decisions.names[issue.id] ?? "" }, set: { model.rename(issue.id, $0) }))
                    .textFieldStyle(.roundedBorder).accessibilityLabel("Unique imported name").onSubmit { model.recalculate() }
                Button("Apply name") { model.recalculate() }.disabled(model.phase.busy)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(KeepTheme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}
