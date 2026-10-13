import SwiftUI

struct CalendarEntryTaskPicker: View {
    @Binding var name: String
    let suggestions: [CalendarEntryTaskSuggestion]
    let onSelect: (CalendarEntryTaskSuggestion) -> Void
    let onUseName: () -> Void
    let onClose: () -> Void
    @FocusState private var searchFocused: Bool
    private var matches: [CalendarEntryTaskSuggestion] { CalendarEntryTaskSuggestion.matching(name, in: suggestions) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(KeepTheme.mutedInk).accessibilityHidden(true)
                TextField("Search or name a task", text: $name).textFieldStyle(.plain).font(.system(size: 14))
                    .focused($searchFocused).accessibilityLabel("Search or name an entry task").onSubmit(onUseName)
            }.padding(12).background(KeepTheme.paper, in: RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(searchFocused ? KeepTheme.focusRing : KeepTheme.controlBorder, lineWidth: searchFocused ? 2 : 1).allowsHitTesting(false) }
            if matches.isEmpty {
                Text("No matching tasks").font(.system(size: 13)).foregroundStyle(KeepTheme.mutedInk).padding(.vertical, 8)
            } else {
                KeepScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(matches) { suggestion in
                            Button { onSelect(suggestion) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(suggestion.title).font(.system(size: 14)).foregroundStyle(KeepTheme.ink).lineLimit(2)
                                    Text(suggestion.detail).font(.system(size: 11)).foregroundStyle(KeepTheme.mutedInk).lineLimit(1)
                                }.frame(maxWidth: .infinity, minHeight: 42, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 5)
                                    .contentShape(RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(CalendarEntrySuggestionStyle())
                                .accessibilityLabel("Choose \(suggestion.title), \(suggestion.detail)")
                        }
                    }
                }.frame(height: min(240, CGFloat(matches.count) * 56))
            }
            HStack {
                Button("Close", action: onClose).buttonStyle(KeepButtonStyle(emphasis: .quiet))
                Spacer()
                Button(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Use unnamed task" : "Use entered name", action: onUseName)
                    .buttonStyle(KeepButtonStyle(emphasis: .primary)).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).count > 200)
            }
        }.padding(16).frame(width: 360).background(KeepTheme.surface).foregroundStyle(KeepTheme.ink)
            .onAppear { searchFocused = true }.onExitCommand(perform: onClose)
    }
}
private struct CalendarEntrySuggestionStyle: ButtonStyle {
    @State private var hovered = false
    @Environment(\.isFocused) private var focused
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(hovered || configuration.isPressed ? KeepTheme.mutedWarm : .clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(focused ? KeepTheme.focusRing : .clear, lineWidth: 2).allowsHitTesting(false) }
            .onHover { hovered = $0 }
    }
}
