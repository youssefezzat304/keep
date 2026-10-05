import SwiftUI

struct ActiveTargetHeader: View {
    @Binding var target: String
    var isCompact = false
    @FocusState private var isFocused: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 24) {
                heading
                Spacer(minLength: 16)
                targetField
            }
            VStack(alignment: .leading, spacing: 16) {
                heading
                targetField
            }
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("A little space to focus.")
                .font(.system(size: isCompact ? 30 : 36, weight: .regular, design: .serif))
                .fixedSize(horizontal: true, vertical: false)
            Text("One thing at a time. At your own pace.")
                .font(.system(size: 14))
                .foregroundStyle(KeepTheme.mutedInk)
        }
    }

    private var targetField: some View {
        HStack(spacing: 12) {
            Image(systemName: "scope")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(KeepTheme.accentStrong)
            VStack(alignment: .leading, spacing: 5) {
                Text("WORKING ON")
                    .font(.system(size: 9, weight: .medium))
                    .tracking(1.5)
                    .foregroundStyle(KeepTheme.mutedInk)
                TextField("Name your focus", text: $target)
                    .font(.system(size: 13, weight: .medium))
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .accessibilityLabel("Current focus")
            }
        }
        .padding(14)
        .frame(width: 235)
        .background(KeepTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isFocused ? KeepTheme.focusRing : KeepTheme.border, lineWidth: isFocused ? 2 : 1)
        }
    }
}

#Preview {
    ActiveTargetHeader(target: .constant("Your next good idea"))
        .padding().background(KeepTheme.paper)
}
