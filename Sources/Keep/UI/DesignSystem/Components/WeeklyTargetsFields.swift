import SwiftUI

struct WeeklyTargetsFields: View {
    @Binding var enabled: Bool
    @Binding var goal: String
    @Binding var minimum: String
    let unit: String
    let maximum: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Weekly targets", isOn: $enabled).toggleStyle(KeepCheckboxStyle())
            if enabled {
                target("Goal", text: $goal)
                target("At least", text: $minimum)
                Text("Aim for Goal; At least is your minimum for a busy week. Up to \(maximum) \(unit) per week.")
                    .font(.system(size: 12)).foregroundStyle(KeepTheme.mutedInk).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func target(_ label: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Text(label).font(.system(size: 13, weight: .medium)).frame(width: 90, alignment: .leading)
            TextField(label, text: text).modifier(KeepInputStyle()).frame(width: 90)
                .accessibilityLabel("\(label), \(unit) per week")
            Text("\(unit) / week").font(.system(size: 13)).foregroundStyle(KeepTheme.secondaryInk)
        }
    }
}

struct WeeklyTargetsProgress: View {
    let targets: WeeklyTargets
    let amount: Double
    let format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(format(amount)) this week").font(.system(size: 14, weight: .medium)).monospacedDigit()
            HStack {
                Text("At least \(format(Double(targets.minimum)))")
                Spacer()
                Text("Goal \(format(Double(targets.goal)))")
            }.font(.system(size: 12)).foregroundStyle(KeepTheme.secondaryInk).monospacedDigit()
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(KeepTheme.mutedWarm)
                    Capsule().fill(amount >= Double(targets.minimum) ? KeepTheme.sageInk : KeepTheme.accentStrong)
                        .frame(width: geometry.size.width * min(1, max(0, amount / Double(targets.goal))))
                    Rectangle().fill(KeepTheme.ink).frame(width: 2, height: 12)
                        .offset(x: min(max(0, geometry.size.width - 2), geometry.size.width * Double(targets.minimum) / Double(targets.goal)))
                }
            }.frame(height: 8).accessibilityHidden(true)
            Text(amount >= Double(targets.goal) ? "Goal reached" : amount >= Double(targets.minimum) ? "Weekly minimum reached" : "Working toward your weekly minimum")
                .font(.system(size: 12)).foregroundStyle(KeepTheme.secondaryInk)
        }.accessibilityElement(children: .combine)
    }
}
