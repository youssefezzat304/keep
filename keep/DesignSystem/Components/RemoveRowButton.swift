import SwiftUI

struct RemoveRowButton: View {
    let label: String
    let action: () -> Void
    @State private var hovered = false
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(hovered ? KeepTheme.accentStrong : KeepTheme.mutedInk)
                .frame(width: 28, height: 28)
                .background(KeepTheme.mutedWarm.opacity(hovered ? 0.7 : 0.3), in: RoundedRectangle(cornerRadius: 7))
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .focused($focused)
        .overlay {
            RoundedRectangle(cornerRadius: 7).strokeBorder(focused ? KeepTheme.focusRing : .clear, lineWidth: 2)
        }
        .accessibilityLabel(label)
        .help(label)
    }
}
