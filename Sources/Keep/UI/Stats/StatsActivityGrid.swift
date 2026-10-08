import SwiftUI

struct StatsActivityGrid: View {
    let snapshot: FocusActivitySnapshot
    let availableWidth: CGFloat
    @State private var inspected: String?
    @Environment(\.self) private var environment

    private var inspection: String? {
        guard let inspected, let day = snapshot.weeks.lazy.flatMap(\.days).first(where: { $0.id == inspected }) else { return nil }
        return dayLabel(day)
    }
    private func dayLabel(_ day: FocusActivitySnapshot.Day) -> String {
        "\(day.label): \(TimesheetDuration.total(day.seconds)) recorded focus\(day.selected ? "" : ", outside selected dates")"
    }

    private var ink: Color { HabitVisualStyle.ink(.fern, in: environment) }
    private func fill(_ seconds: Double) -> Color {
        let level = FocusActivitySnapshot.intensity(seconds: seconds)
        return ActivityGridStyle.fill(level: level, ink: ink)
    }
    var body: some View {
        let size = ActivityGridStyle.tileSize(availableWidth: availableWidth - 44, columns: snapshot.weeks.count)
        VStack(alignment: .leading, spacing: ActivityGridStyle.spacing) {
            title
            HStack(alignment: .top, spacing: ActivityGridStyle.tileSpacing) {
                ForEach(snapshot.weeks.indices, id: \.self) { index in
                    let week = snapshot.weeks[index]
                    VStack(spacing: ActivityGridStyle.monthSpacing) {
                        VStack(spacing: ActivityGridStyle.tileSpacing) {
                            ForEach(week.days, id: \.id) { day in tile(day, size: size) }
                        }
                        Text(week.month).font(.system(size: 10)).foregroundStyle(KeepTheme.mutedInk)
                            .fixedSize().frame(width: size, alignment: .leading)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .center)

            ViewThatFits(in: .horizontal) {
                HStack { total; Spacer(); legend }
                VStack(alignment: .leading, spacing: 8) { total; legend }
            }
            if let inspection { Text(inspection).font(.system(size: 12)).foregroundStyle(KeepTheme.secondaryInk) }
        }
        .onChange(of: snapshot.year) { inspected = nil }
    }
    private var title: some View {
        HStack { Text("Focus activity").font(KeepTheme.headingFont(size: 24)); Text(String(snapshot.year)).font(.system(size: 13)).foregroundStyle(KeepTheme.mutedInk) }
    }
    private var total: some View { Text("\(TimesheetDuration.total(snapshot.seconds)) in the displayed year and selected dates").font(.system(size: 12)).foregroundStyle(KeepTheme.secondaryInk) }
    private var legend: some View {
        HStack(spacing: 4) {
            Text("Less")
            ForEach(0..<5) { level in
                RoundedRectangle(cornerRadius: 2).fill(ActivityGridStyle.fill(level: level, ink: ink)).frame(width: 9, height: 9)
            }
            Text("8+ h / day")
        }.font(.system(size: 10)).foregroundStyle(KeepTheme.mutedInk)
            .accessibilityElement(children: .ignore).accessibilityLabel("Intensity: zero, under two, two to four, four to eight, or eight or more hours per day")
    }
    private func tile(_ day: FocusActivitySnapshot.Day, size: CGFloat) -> some View {
        let label = dayLabel(day)
        return Button { inspected = day.id } label: {
            RoundedRectangle(cornerRadius: 2).fill(fill(day.seconds)).frame(width: size, height: size)
        }.buttonStyle(ActivitySquareButtonStyle())
            .opacity(day.inYear ? 1 : 0)
            .disabled(!day.inYear || day.future || !day.selected).help(label).accessibilityLabel(label).accessibilityHidden(!day.inYear)
    }
}
