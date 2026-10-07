import SwiftUI

struct PrimaryButton: View {
    let buttonTitle: String
    var systemImage: String? = nil
    let action: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 11))
                }
                Text(buttonTitle).font(.system(size: 13, weight: .medium))
            }
        }
        .buttonStyle(KeepPrimaryButtonStyle())
        .focused($isFocused)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isFocused ? KeepTheme.focusRing : .clear, lineWidth: 3)
                .padding(-4)
        }
    }
}

private struct KeepPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(KeepTheme.surface)
            .padding(.horizontal, 18)
            .frame(height: 40)
            .background(KeepTheme.ink, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .fill(KeepTheme.paper.opacity(configuration.isPressed ? 0.15 : 0))
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    PrimaryButton(buttonTitle: "Play", systemImage: "play.fill") {}
        .padding().background(KeepTheme.accent)
}
