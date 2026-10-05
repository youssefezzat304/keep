import SwiftUI

struct ProjectCreationDialog: View {
    let onCreate: (String, FocusProject.Accent) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var accent = FocusProject.Accent.terracotta
    @State private var error: String?
    @State private var hoveredColor: FocusProject.Accent?
    @FocusState private var nameFocused: Bool
    @FocusState private var focusedColor: FocusProject.Accent?

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var validName: Bool { !trimmedName.isEmpty && trimmedName.count <= 80 }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                Text("A new place to focus.")
                    .font(.system(size: 27, design: .serif))
                Text("Give your project a name and a color.")
                    .font(.system(size: 13))
                    .foregroundStyle(KeepTheme.mutedInk)
            }

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
                    }
                    .focused($nameFocused)
                    .accessibilityLabel("Project name")
                    .onChange(of: name) { error = nil }
                    .onSubmit(create)
                if trimmedName.count > 80 {
                    Text("Use 80 characters or fewer.")
                        .font(.system(size: 12))
                        .foregroundStyle(KeepTheme.accentStrong)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Project color").font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text(accent.name).font(.system(size: 12)).foregroundStyle(KeepTheme.mutedInk)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 8) {
                    ForEach(FocusProject.Accent.projectColors, id: \.self) { color in
                        colorOption(color)
                    }
                }
                .accessibilityLabel("Choose from 30 project colors")
            }

            if let error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(KeepTheme.accentStrong)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create project", action: create)
                    .buttonStyle(.borderedProminent)
                    .tint(KeepTheme.accentStrong)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!validName)
            }
            .controlSize(.large)
        }
        .padding(24)
        .frame(width: 420)
        .foregroundStyle(KeepTheme.ink)
        .background(KeepTheme.paper)
        .onAppear { nameFocused = true }
    }

    private func colorOption(_ color: FocusProject.Accent) -> some View {
        let selected = accent == color
        return Button { accent = color } label: {
            Circle()
                .fill(color.color)
                .frame(width: 32, height: 32)
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
                    Circle().strokeBorder(selected || focusedColor == color ? KeepTheme.focusRing : KeepTheme.border, lineWidth: selected || focusedColor == color ? 2 : 1)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredColor = $0 ? color : nil }
        .focused($focusedColor, equals: color)
        .accessibilityLabel(color.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(color.name)
    }

    private func create() {
        guard validName else { return }
        do {
            try onCreate(trimmedName, accent)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

#Preview {
    ProjectCreationDialog { _, _ in }
}
