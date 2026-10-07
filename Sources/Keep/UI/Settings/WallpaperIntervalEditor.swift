import SwiftUI

/// Invalid or partially typed values stay local until a complete interval is applied.
struct WallpaperIntervalEditor: View {
    let preferences: AppPreferences
    @State private var hours: String
    @State private var minutes: String

    init(preferences: AppPreferences) {
        self.preferences = preferences
        let value = preferences.customRotationMinutes ?? 1
        _hours = State(initialValue: String(value / 60))
        _minutes = State(initialValue: String(value % 60))
    }
    private var value: Int? { WallpaperIntervalChoice.customMinutes(hours: hours, minutes: minutes) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 12) {
                field("Hours", text: $hours)
                field("Minutes", text: $minutes)
                Button("Apply") { apply() }
                    .buttonStyle(KeepButtonStyle(emphasis: .primary))
                    .disabled(value == nil || value == preferences.customRotationMinutes || !preferences.canEdit)
            }
            if value == nil {
                Text("Enter 0–999 hours and 0–59 minutes, totaling at least 1 minute.")
                    .font(.system(size: 12)).foregroundStyle(KeepTheme.accentStrong)
            }
        }
        .onChange(of: preferences.customRotationMinutes) { _, value in
            if let value { hours = String(value / 60); minutes = String(value % 60) }
        }
    }
    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12)).foregroundStyle(KeepTheme.mutedInk)
            TextField("0", text: text).modifier(KeepInputStyle()).frame(width: 82)
                .accessibilityLabel("Wallpaper interval \(title.lowercased())")
                .onSubmit { apply() }
        }
    }
    private func apply() {
        if let value { preferences.customRotationMinutes = value }
    }
}
