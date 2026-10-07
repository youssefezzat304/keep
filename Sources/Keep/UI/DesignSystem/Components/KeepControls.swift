import SwiftUI

/// Shared warm controls, with native button/menu behavior and visible keyboard focus.
struct KeepButtonStyle: ButtonStyle {
    enum Emphasis { case primary, secondary, quiet }
    var emphasis: Emphasis = .secondary
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(emphasis == .primary ? KeepTheme.surface : KeepTheme.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(fill, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(focused ? KeepTheme.focusRing : emphasis == .quiet ? .clear : KeepTheme.border,
                                  lineWidth: focused ? 2 : 1)
            }
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .onHover { hovered = $0 }
    }

    private var fill: Color {
        if emphasis == .primary { return KeepTheme.accentStrong }
        if emphasis == .quiet { return KeepTheme.mutedWarm.opacity(hovered ? 0.6 : 0.25) }
        return hovered ? KeepTheme.mutedWarm : KeepTheme.paper
    }
}

/// Two-choice pickers use the same selected-button treatment as Appearance.
struct KeepSegmentedPicker<Value: Hashable>: View {
    let label: String
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                Button { selection = option } label: {
                    HStack(spacing: 5) {
                        if selection == option { Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)) }
                        Text(title(option)).fixedSize(horizontal: true, vertical: false)
                    }
                }
                .buttonStyle(KeepButtonStyle(emphasis: selection == option ? .primary : .quiet))
                .accessibilityLabel("\(label): \(title(option))")
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        .padding(4).background(KeepTheme.paper, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain).accessibilityLabel(label)
    }
}

struct KeepSelectionMenu<Value: Hashable>: View {
    let label: String
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String
    @State private var isPresented = false

    var body: some View {
        if options.count == 2 {
            KeepSegmentedPicker(label: label, selection: $selection, options: options, title: title)
        } else {
            Button { isPresented.toggle() } label: {
                HStack(spacing: 12) {
                    Text(title(selection)).lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(KeepTheme.accentStrong)
                }
                .frame(maxWidth: .infinity).contentShape(Rectangle())
            }
            .buttonStyle(KeepButtonStyle())
            .accessibilityLabel(label).accessibilityValue(title(selection))
            .popover(isPresented: $isPresented) {
                KeepOptionList(label: label, options: options, selection: selection, title: title) { option in
                    selection = option; isPresented = false
                }
                .onExitCommand { isPresented = false }
            }
        }
    }
}

/// Themed dropdown contents with complete row hit areas and native button accessibility.
struct KeepOptionList<Value: Hashable>: View {
    let label: String
    let options: [Value]
    let selection: Value
    let title: (Value) -> String
    let onSelect: (Value) -> Void
    @FocusState private var focused: Value?

    var body: some View {
        ScrollViewReader { reader in
            KeepScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(options, id: \.self) { option in
                        Button { onSelect(option) } label: {
                            HStack(spacing: 10) {
                                Text(title(option)).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 8)
                                Image(systemName: "checkmark").opacity(option == selection ? 1 : 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }
                        .buttonStyle(KeepButtonStyle(emphasis: option == selection ? .secondary : .quiet))
                        .focused($focused, equals: option)
                        .accessibilityAddTraits(option == selection ? .isSelected : [])
                        .id(option)
                    }
                }.padding(8)
            }
            .frame(width: 260, height: CGFloat(min(options.count, 7)) * 40 + 16)
            .background(KeepTheme.surface).foregroundStyle(KeepTheme.ink)
            .accessibilityElement(children: .contain).accessibilityLabel(label)
            .onAppear { focused = selection; reader.scrollTo(selection) }
            .onChange(of: focused) { _, value in if let value { reader.scrollTo(value) } }
            .onKeyPress(.downArrow) { moveFocus(1); return .handled }
            .onKeyPress(.upArrow) { moveFocus(-1); return .handled }
        }
    }
    private func moveFocus(_ step: Int) {
        guard !options.isEmpty else { return }
        let index = options.firstIndex(of: focused ?? selection) ?? 0
        focused = options[(index + step + options.count) % options.count]
    }
}

struct KeepInputStyle: ViewModifier {
    @Environment(\.isFocused) private var focused
    func body(content: Content) -> some View {
        content.textFieldStyle(.plain).font(.system(size: 13))
            .padding(.horizontal, 12).frame(minHeight: 36)
            .background(KeepTheme.paper, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(focused ? KeepTheme.focusRing : KeepTheme.border, lineWidth: focused ? 2 : 1)
            }
    }
}

/// A compact paper checkbox with the same borders and focus treatment as other controls.
struct KeepCheckboxStyle: ToggleStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(configuration.isOn ? KeepTheme.accentStrong : KeepTheme.surface)
                    .frame(width: 19, height: 19)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5).strokeBorder(focused ? KeepTheme.focusRing : configuration.isOn ? KeepTheme.accentStrong : KeepTheme.controlBorder, lineWidth: focused ? 2 : 1)
                    }
                    .overlay {
                        if configuration.isOn { Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(KeepTheme.surface) }
                    }
                configuration.label.font(.system(size: 13)).foregroundStyle(KeepTheme.ink)
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain).opacity(enabled ? 1 : 0.5)
        .accessibilityValue(configuration.isOn ? "Checked" : "Unchecked")
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}
