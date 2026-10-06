import SwiftUI

/// Navigation destination only; habit creation and tracking are not implemented yet.
struct HabitTrackerView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Habit tracker").font(.system(size: 36, design: .serif))
            VStack(spacing: 12) {
                Image(systemName: "checkmark.seal").font(.system(size: 32, weight: .light))
                    .foregroundStyle(KeepTheme.accentStrong)
                Text("A little room for daily rituals.").font(.system(size: 24, design: .serif))
                Text("Habit tracking hasn’t been set up yet.")
                    .font(.system(size: 13)).foregroundStyle(KeepTheme.mutedInk)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(KeepTheme.surface, in: RoundedRectangle(cornerRadius: KeepTheme.cardRadius))
            .overlay { RoundedRectangle(cornerRadius: KeepTheme.cardRadius).strokeBorder(KeepTheme.border, lineWidth: 1).allowsHitTesting(false) }
        }
        .foregroundStyle(KeepTheme.ink)
    }
}
