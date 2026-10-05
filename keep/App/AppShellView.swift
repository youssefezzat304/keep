import SwiftUI

struct AppShellView: View {
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    NavBar()
                    FocusSessionView(isCompact: geometry.size.width < 820)
                }
                .padding(24)
                .frame(maxWidth: 1100)
                .background(KeepTheme.paper, in: RoundedRectangle(cornerRadius: 28))
                .overlay {
                    RoundedRectangle(cornerRadius: 28)
                        .strokeBorder(KeepTheme.border.opacity(0.5), lineWidth: 1)
                }
                .padding(16)
                .frame(maxWidth: .infinity)
            }
            .background(KeepTheme.background)
        }
        .frame(minWidth: 680, minHeight: 650)
        .foregroundStyle(KeepTheme.ink)
        .tint(KeepTheme.accentStrong)
        .preferredColorScheme(.light)
    }
}

#Preview {
    AppShellView()
        .frame(width: 1000, height: 900)
}
