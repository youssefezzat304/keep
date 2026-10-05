import SwiftUI

struct TimesheetTable: View {
    private let projectWidth: CGFloat = 205
    private let totalWidth: CGFloat = 88
    private let headerHeight: CGFloat = 68
    private let rowHeight: CGFloat = 78
    private let totalHeight: CGFloat = 64

    var body: some View {
        GeometryReader { geometry in
            let tableWidth = max(850, geometry.size.width)
            let dayWidth = (tableWidth - projectWidth - totalWidth - 32) / 7

            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    header(dayWidth: dayWidth)
                    divider
                    ForEach(TimesheetMockData.projects) { project in
                        projectRow(project, dayWidth: dayWidth)
                        divider
                    }
                    totals(dayWidth: dayWidth)
                }
                .padding(.horizontal, 16)
                .frame(width: tableWidth)
            }
            .scrollIndicators(.visible)
        }
        .frame(height: headerHeight + rowHeight * 4 + totalHeight + 5)
        .background(KeepTheme.surface, in: RoundedRectangle(cornerRadius: KeepTheme.cardRadius))
        .clipShape(RoundedRectangle(cornerRadius: KeepTheme.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: KeepTheme.cardRadius)
                .strokeBorder(KeepTheme.border, lineWidth: 1)
        }
        .accessibilityLabel("Sample weekly timesheet. Times are hours and minutes. Scroll horizontally for all seven days on smaller windows.")
    }

    private func header(dayWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                Text("PROJECT")
                    .tracking(1.3)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(KeepTheme.mutedInk)
            .frame(width: projectWidth, alignment: .leading)

            ForEach(TimesheetMockData.days) { day in
                VStack(spacing: 5) {
                    Text(day.id)
                        .font(.system(size: 10, weight: .medium))
                        .tracking(1)
                        .foregroundStyle(KeepTheme.mutedInk)
                    Text(day.date)
                        .font(.system(size: 20, weight: .regular, design: .serif))
                }
                .frame(width: dayWidth, height: headerHeight)
                .background { Rectangle().fill(day.isWeekend ? KeepTheme.paper : .clear) }
                .accessibilityElement(children: .combine)
            }

            Text("TOTAL")
                .font(.system(size: 10, weight: .medium))
                .tracking(1.3)
                .foregroundStyle(KeepTheme.mutedInk)
                .frame(width: totalWidth, height: headerHeight, alignment: .trailing)
        }
        .frame(height: headerHeight)
    }

    private func projectRow(_ project: TimesheetProjectPreview, dayWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 11) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(project.color)
                    .frame(width: 12, height: 30)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(project.name)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                    Text(project.category)
                        .font(.system(size: 11))
                        .foregroundStyle(KeepTheme.mutedInk)
                        .lineLimit(1)
                }
            }
            .frame(width: projectWidth, alignment: .leading)

            ForEach(Array(TimesheetMockData.days.enumerated()), id: \.element.id) { index, day in
                Text(project.hours[index])
                    .font(.system(size: 14))
                    .monospacedDigit()
                    .foregroundStyle(project.hours[index] == "—" ? KeepTheme.mutedInk : KeepTheme.ink)
                    .frame(width: dayWidth - 16, height: 34)
                    .background(project.hours[index] == "—" ? KeepTheme.paper : project.color.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(KeepTheme.border.opacity(0.65), lineWidth: 1)
                    }
                    .frame(width: dayWidth, height: rowHeight)
                    .background { Rectangle().fill(day.isWeekend ? KeepTheme.paper : .clear) }
                    .accessibilityLabel("\(project.name), \(day.id): \(project.hours[index] == "—" ? "no time recorded" : project.hours[index])")
            }

            Text(project.total)
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .frame(width: totalWidth, alignment: .trailing)
                .accessibilityLabel("\(project.name) total: \(project.total)")
        }
        .frame(height: rowHeight)
    }

    private func totals(dayWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text("DAILY TOTAL")
                .font(.system(size: 10, weight: .medium))
                .tracking(1.3)
                .foregroundStyle(KeepTheme.secondaryInk)
                .frame(width: projectWidth, alignment: .leading)

            ForEach(Array(TimesheetMockData.days.enumerated()), id: \.element.id) { index, day in
                Text(TimesheetMockData.dailyTotals[index])
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .frame(width: dayWidth, height: totalHeight)
                    .background { Rectangle().fill(day.isWeekend ? KeepTheme.mutedWarm.opacity(0.28) : .clear) }
                    .accessibilityLabel("\(day.id) total: \(TimesheetMockData.dailyTotals[index])")
            }

            Text(TimesheetMockData.weekTotal)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(KeepTheme.accentStrong)
                .frame(width: totalWidth, alignment: .trailing)
                .accessibilityLabel("Week total: \(TimesheetMockData.weekTotal)")
        }
        .frame(height: totalHeight)
        .background { Rectangle().fill(KeepTheme.paper) }
    }

    private var divider: some View {
        Rectangle().fill(KeepTheme.border).frame(height: 1)
    }
}

#Preview {
    TimesheetTable()
        .padding().frame(width: 950).background(KeepTheme.paper)
}
