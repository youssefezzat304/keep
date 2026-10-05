import SwiftUI

struct NavBar: View {
    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(KeepTheme.accentStrong)
                Text("keep")
                    .font(.system(size: 28, weight: .medium, design: .serif))
            }
            .accessibilityElement(children: .combine)

            Spacer()

            Label("Focus", systemImage: "sun.max")
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(KeepTheme.mutedWarm, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityAddTraits(.isSelected)

            futureDestination("Stats", symbol: "chart.bar")
            futureDestination("Settings", symbol: "slider.horizontal.3")
        }
        .foregroundStyle(KeepTheme.ink)
    }

    private func futureDestination(_ title: String, symbol: String) -> some View {
        Button {} label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .frame(height: 36)
        }
        .buttonStyle(.plain)
        .foregroundStyle(KeepTheme.mutedInk)
        .disabled(true)
        .help("\(title) will be available later")
    }
}

#Preview {
    NavBar().padding().background(KeepTheme.paper)
}
