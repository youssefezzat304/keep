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

struct KeepSelectionMenu<Value: Hashable>: View {
    let label: String
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button { selection = option } label: {
                    if option == selection { Label(title(option), systemImage: "checkmark") }
                    else { Text(title(option)) }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Text(title(selection)).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(KeepTheme.accentStrong)
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(KeepTheme.ink)
            .padding(.horizontal, 12).frame(height: 36)
            .contentShape(Rectangle())
            .background(hovered ? KeepTheme.mutedWarm : KeepTheme.paper, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(focused ? KeepTheme.focusRing : KeepTheme.border, lineWidth: focused ? 2 : 1)
                    .allowsHitTesting(false)
            }
        }
        .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.4)
        .onHover { hovered = $0 }
        .accessibilityLabel(label).accessibilityValue(title(selection))
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
