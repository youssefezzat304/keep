import SwiftUI

struct ProjectEditorDialog: View {
    let project: FocusProject?
    let usedColors: Set<FocusProject.Accent>
    let onSave: (String, FocusProject.Accent, ProjectHourlyRate?) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var accent = FocusProject.Accent.terracotta
    @State private var rateText = ""
    @State private var currency = Locale.current.currency?.identifier ?? "USD"
    @State private var showsCurrency = false
    @State private var error: String?
    @State private var hoveredColor: FocusProject.Accent?
    @FocusState private var rateFocused: Bool
    @FocusState private var nameFocused: Bool
    @FocusState private var focusedColor: FocusProject.Accent?

    init(project: FocusProject? = nil, usedColors: Set<FocusProject.Accent> = [],
         onSave: @escaping (String, FocusProject.Accent, ProjectHourlyRate?) throws -> Void) {
        self.project = project
        self.usedColors = usedColors
        self.onSave = onSave
        _name = State(initialValue: project?.name ?? "")
        _accent = State(initialValue: project?.accent ?? FocusProject.Accent.projectColors.first { !usedColors.contains($0) } ?? .terracotta)
        _rateText = State(initialValue: project?.hourlyRate.map { $0.editableAmount } ?? "")
        _currency = State(initialValue: project?.hourlyRate?.currency ?? Locale.current.currency?.identifier ?? "USD")
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var validName: Bool { !trimmedName.isEmpty && trimmedName.count <= 80 }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                Text(project == nil ? "A new place to focus." : "Edit project.")
                    .font(KeepTheme.headingFont(size: 27))
                Text("Give your project a name and a color.")
                    .font(.system(size: 13))
                    .foregroundStyle(KeepTheme.mutedInk)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    nameField
                    if project?.isHabitsProject == true {
                        Label("Habits has its own reserved color.", systemImage: "lock.fill")
                            .font(.system(size: 13)).foregroundStyle(KeepTheme.secondaryInk)
                    } else { colorField }
                    rateField
                }.padding(4)
            }
            .frame(height: (project?.isHabitsProject == true ? 250 : 440) - (error == nil ? 0 : 60))

            if let error {
                Text(error).font(.system(size: 12)).foregroundStyle(KeepTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Project could not be saved: \(error)")
            }

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(KeepButtonStyle(emphasis: .quiet))
                    .keyboardShortcut(.cancelAction)
                Button(project == nil ? "Create project" : "Save changes", action: save)
                    .buttonStyle(KeepButtonStyle(emphasis: .primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!validName || (project?.isHabitsProject != true && usedColors.contains(accent) && project?.accent != accent))
            }
            .controlSize(.large)
        }
        .padding(24)
        .frame(width: 420)
        .foregroundStyle(KeepTheme.ink)
        .background(KeepTheme.paper)
        .onAppear { nameFocused = true }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Project name").font(.system(size: 13, weight: .medium))
            TextField("e.g. A little side project", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(12)
                .background(KeepTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(nameFocused ? KeepTheme.focusRing : KeepTheme.controlBorder, lineWidth: nameFocused ? 2 : 1)
                        .allowsHitTesting(false)
                }
                .focused($nameFocused)
                .accessibilityLabel("Project name")
                .onChange(of: name) { error = nil }
                .onSubmit(save)
            if trimmedName.count > 80 {
                Text("Use 80 characters or fewer.")
                    .font(.system(size: 12))
                    .foregroundStyle(KeepTheme.accentStrong)
            }
        }
    }

    private var colorField: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Project color").font(.system(size: 13, weight: .medium))
                Spacer()
                Text(accent.name).font(.system(size: 12)).foregroundStyle(KeepTheme.mutedInk)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 6) {
                ForEach(FocusProject.Accent.projectColors, id: \.self) { color in
                    colorOption(color)
                }
            }
            .accessibilityLabel("Choose from 30 project colors")
        }
    }

    private var rateField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Money per hour · optional").font(.system(size: 13, weight: .medium))
            HStack(spacing: 10) {
                TextField("No hourly rate", text: $rateText)
                    .textFieldStyle(.plain).font(.system(size: 14)).padding(10)
                    .background(KeepTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                    .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(rateFocused ? KeepTheme.focusRing : KeepTheme.controlBorder, lineWidth: rateFocused ? 2 : 1).allowsHitTesting(false) }
                    .focused($rateFocused)
                    .accessibilityLabel("Money per hour, optional")
                    .onChange(of: rateText) { error = nil }
                    .onSubmit(save)
                Button(currency) { showsCurrency = true }
                    .buttonStyle(KeepButtonStyle()).accessibilityLabel("Currency: \(currency)")
                    .popover(isPresented: $showsCurrency) {
                        ProjectCurrencyPicker(selection: currency) { currency = $0; showsCurrency = false }
                    }
            }
            Text("Stats estimates cost using your current rate. Leave empty to exclude this project.")
                .font(.system(size: 12)).foregroundStyle(KeepTheme.mutedInk).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func colorOption(_ color: FocusProject.Accent) -> some View {
        let selected = accent == color
        let used = usedColors.contains(color) && project?.accent != color
        return Button { accent = color } label: {
            Circle()
                .fill(color.color)
                .frame(width: 28, height: 28)
                .overlay {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(KeepTheme.ink)
                            .padding(4)
                            .background(KeepTheme.surface, in: Circle())
                    }
                }
                .padding(5)
                .background(hoveredColor == color ? KeepTheme.mutedWarm.opacity(0.5) : .clear, in: Circle())
                .overlay {
                    Circle().strokeBorder(used ? KeepTheme.projectUsedColorRing : KeepTheme.border, lineWidth: used ? 2 : 1)
                        .allowsHitTesting(false)
                    if selected || focusedColor == color {
                        Circle().strokeBorder(KeepTheme.focusRing, lineWidth: 2).padding(-3)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(used)
        .opacity(used ? 0.4 : 1)
        .onHover { hoveredColor = $0 ? color : nil }
        .focused($focusedColor, equals: color)
        .accessibilityLabel(used ? "\(color.name), already used" : color.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(used ? "\(color.name) · assigned to another project" : color.name)
    }

    private func save() {
        guard validName else { return }
        do {
            let rate = try ProjectHourlyRate.parse(rateText, currency: currency)
            try onSave(trimmedName, accent, rate)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

#Preview {
    ProjectEditorDialog { _, _, _ in }
}
