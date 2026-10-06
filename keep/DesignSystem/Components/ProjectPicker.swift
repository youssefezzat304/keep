import SwiftUI

struct ProjectPicker: View {
    let projects: [FocusProject]
    let selectedProject: FocusProject?
    let onSelect: (FocusProject?) -> Void
    let onCreate: (() -> Void)?
    @Environment(\.self) private var environment
    @State private var search: String
    @State private var hoveredOption: String?
    @FocusState private var searchFocused: Bool
    @FocusState private var focusedOption: String?

    init(
        projects: [FocusProject],
        selectedProject: FocusProject?,
        initialSearch: String = "",
        onCreate: (() -> Void)? = nil,
        onSelect: @escaping (FocusProject?) -> Void
    ) {
        self.projects = projects
        self.selectedProject = selectedProject
        self.onSelect = onSelect
        self.onCreate = onCreate
        _search = State(initialValue: initialSearch)
    }

    private var filteredProjects: [FocusProject] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? projects : projects.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(KeepTheme.mutedInk)
                    .accessibilityHidden(true)
                TextField("Search projects…", text: $search)
                    .font(.system(size: 14))
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .accessibilityLabel("Search projects")
                    .onSubmit {
                        if let project = filteredProjects.first { onSelect(project) }
                    }
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(KeepTheme.mutedInk)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear project search")
                }
            }
            .padding(12)
            .background(KeepTheme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(searchFocused ? KeepTheme.focusRing : KeepTheme.controlBorder, lineWidth: searchFocused ? 2 : 1)
            }

            ScrollViewReader { scroll in
                KeepScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        projectOption(nil)

                        Text("YOUR PROJECTS")
                            .font(.system(size: 10, weight: .medium))
                            .tracking(1.3)
                            .foregroundStyle(KeepTheme.mutedInk)
                            .padding(.horizontal, 12)
                            .padding(.top, 15)
                            .padding(.bottom, 7)

                        ForEach(filteredProjects) { project in
                            projectOption(project)
                        }

                        if filteredProjects.isEmpty {
                            VStack(spacing: 6) {
                                Text("No projects found")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Try a different project name.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(KeepTheme.mutedInk)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                        }
                    }
                }
                .onAppear { scroll.scrollTo(selectedProject?.id ?? "no-project", anchor: .center) }
            }
            .frame(height: 276)

            Rectangle().fill(KeepTheme.border).frame(height: 1)

            HStack {
                Button { onCreate?() } label: {
                    Label("Create a new project", systemImage: "plus")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(KeepTheme.accentStrong)
                .disabled(onCreate == nil)
                .focused($focusedOption, equals: "create-project")
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(focusedOption == "create-project" ? KeepTheme.focusRing : .clear, lineWidth: 2)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 2)
        }
        .padding(16)
        .frame(width: 340)
        .foregroundStyle(KeepTheme.ink)
        .background(KeepTheme.paper)
        .onAppear { searchFocused = true }
    }

    private func projectOption(_ project: FocusProject?) -> some View {
        let optionID = project?.id ?? "no-project"
        let isSelected = selectedProject?.id == project?.id
        let isHovered = hoveredOption == optionID
        return Button { onSelect(project) } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(project?.accentColor ?? KeepTheme.mutedInk)
                    .frame(width: 9, height: 9)
                    .accessibilityHidden(true)
                Text(project?.name ?? "No project")
                    .font(.system(size: 14, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(project?.labelColor(in: environment) ?? KeepTheme.mutedInk)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(KeepTheme.accentStrong)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .background(isSelected ? KeepTheme.mutedWarm.opacity(0.6) : isHovered ? KeepTheme.mutedWarm.opacity(0.3) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { hoveredOption = $0 ? optionID : nil }
        .focused($focusedOption, equals: optionID)
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(focusedOption == optionID ? KeepTheme.focusRing : .clear, lineWidth: 2)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(project?.name ?? "Work without a project")
        .id(optionID)
    }
}

#Preview {
    ProjectPicker(projects: FocusProject.defaults, selectedProject: FocusProject.defaults.first, onCreate: {}) { _ in }
}

#Preview("No matching projects") {
    ProjectPicker(projects: FocusProject.defaults, selectedProject: nil, initialSearch: "No match", onCreate: {}) { _ in }
}
