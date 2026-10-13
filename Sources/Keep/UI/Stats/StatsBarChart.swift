import SwiftUI
import Charts

struct StatsBarChart: View {
    struct Point: Identifiable {
        let id: Int
        let label: String
        let seconds: Double
        var projects: [StatsSnapshot.BucketProject] = []
    }
    let title: String
    let points: [Point]
    var color: Color = KeepTheme.accentStrong
    var plotHeight: CGFloat = 190
    var subtitle: String?
    @State private var selected: String?
    @State private var hovered: String?
    @FocusState private var focused: Bool
    @Environment(\.self) private var environment

    private var inspectedID: String? { hovered ?? selected }
    private var selectedPoint: Point? { points.first { String($0.id) == inspectedID } }
    private var projects: [StatsSnapshot.BucketProject] {
        var values: [String: StatsSnapshot.BucketProject] = [:]
        for point in points { for project in point.projects { values[project.id] = project } }
        return values.values.sorted { $0.id < $1.id }
    }
    private var axisValues: [String] {
        let step = max(1, Int(ceil(Double(points.count) / 8)))
        return points.enumerated().compactMap { $0.offset % step == 0 ? String($0.element.id) : nil }
    }
    var body: some View {
        let projectColors = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, projectColor($0)) })
        let scaleDomain: [String] = projects.isEmpty ? [""] : projects.map(\.id)
        let scaleRange: [Color] = projects.isEmpty ? [color] : projects.map { projectColors[$0.id] ?? color }
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(KeepTheme.headingFont(size: 23))
                if let subtitle { Text(subtitle).font(.system(size: 12)).foregroundStyle(KeepTheme.mutedInk) }
            }
            Chart {
                ForEach(points) { point in
                    if point.projects.isEmpty {
                        BarMark(x: .value("Period", String(point.id)), y: .value("Hours", point.seconds / 3600), width: .ratio(0.65))
                            .foregroundStyle(color).cornerRadius(4)
                            .opacity(inspectedID == nil || inspectedID == String(point.id) ? 1 : 0.45)
                            .accessibilityLabel(point.label)
                            .accessibilityValue(TimesheetDuration.total(point.seconds))
                    } else {
                        ForEach(point.projects) { project in
                            BarMark(x: .value("Period", String(point.id)), y: .value("Hours", project.seconds / 3600), width: .ratio(0.65))
                                .foregroundStyle(by: .value("Project", project.id))
                                .opacity(inspectedID == nil || inspectedID == String(point.id) ? 1 : 0.45)
                                .accessibilityLabel("\(point.label), \(project.name)")
                                .accessibilityValue("\(TimesheetDuration.total(project.seconds)), \(percentage(project, in: point)) percent of the period")
                        }
                    }
                }
                if let point = selectedPoint {
                    RuleMark(x: .value("Period", String(point.id)))
                        .foregroundStyle(KeepTheme.mutedInk)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .accessibilityHidden(true)
                }
            }
            .chartForegroundStyleScale(domain: scaleDomain, range: scaleRange)
            .chartLegend(.hidden)
            .chartXSelection(value: $selected)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    if let plotFrame = proxy.plotFrame {
                        let frame = geometry[plotFrame]
                        ZStack(alignment: .topTrailing) {
                            Rectangle().fill(.clear).contentShape(Rectangle())
                                .onContinuousHover { phase in
                                    switch phase {
                                    case .active(let location):
                                        hovered = frame.contains(location) ? proxy.value(atX: location.x - frame.minX, as: String.self) : nil
                                    case .ended: hovered = nil
                                    }
                                }
                            if let point = selectedPoint {
                                inspection(point, colors: projectColors, width: min(300, max(120, frame.width - 36)))
                                    .padding(8)
                                    .frame(width: frame.width, height: frame.height, alignment: .topTrailing)
                                    .offset(x: frame.minX, y: frame.minY)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: axisValues) { value in
                    if let id = value.as(String.self), axisValues.contains(id), let point = points.first(where: { String($0.id) == id }) {
                        AxisValueLabel(anchor: .top, collisionResolution: .greedy) { Text(point.label).font(.system(size: 10)) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) {
                    AxisGridLine()
                    AxisValueLabel(anchor: .trailing)
                }
            }
            .chartYScale(domain: 0...max(1, (points.map(\.seconds).max() ?? 0) / 3600 * 1.1))
            .frame(height: plotHeight)
            .focusable().focused($focused).focusEffectDisabled()
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(focused ? KeepTheme.focusRing : .clear, lineWidth: 2).allowsHitTesting(false) }
            .onMoveCommand { direction in
                if direction == .left || direction == .right { inspect(direction == .right ? 1 : -1) }
            }
            .accessibilityLabel(subtitle.map { title + ", " + $0 } ?? title)
            .accessibilityValue(selectedPoint.map(accessibilitySummary) ?? "Recorded focus in hours")
            .accessibilityHint("Use left and right arrow keys to inspect values.")
            .accessibilityAdjustableAction { direction in inspect(direction == .increment ? 1 : -1) }
            if !projects.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading, spacing: 8) {
                    ForEach(projects) { project in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(projectColors[project.id] ?? color).frame(width: 9, height: 9).accessibilityHidden(true)
                            Text(project.name).font(.system(size: 12)).foregroundStyle(KeepTheme.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func inspection(_ point: Point, colors: [String: Color], width: CGFloat) -> some View {
        VStack(spacing: 4) {
            Text(point.label).font(.system(size: 12, weight: .medium))
            Text(TimesheetDuration.total(point.seconds)).font(.system(size: 13)).monospacedDigit()
            ForEach(point.projects) { project in
                HStack(spacing: 8) {
                    Circle().fill(colors[project.id] ?? color).frame(width: 8, height: 8)
                    Text(project.name).lineLimit(2)
                    Spacer(minLength: 4)
                    Text("\(TimesheetDuration.total(project.seconds)) · \(percentage(project, in: point))%")
                        .monospacedDigit().fixedSize()
                }.font(.system(size: 11))
            }
        }
        .frame(width: point.projects.isEmpty ? nil : width)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(KeepTheme.ink).padding(10)
        .background(KeepTheme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(KeepTheme.border) }
    }

    private func projectColor(_ project: StatsSnapshot.BucketProject) -> Color {
        let accent = FocusProject.Accent(rawValue: project.accent) ?? .neutral
        return KeepTheme.readableAccent(accent.color, on: [KeepTheme.paper, KeepTheme.surface, KeepTheme.mutedWarm], environment: environment)
    }

    private func percentage(_ project: StatsSnapshot.BucketProject, in point: Point) -> Int {
        point.seconds > 0 ? Int((project.seconds / point.seconds * 100).rounded()) : 0
    }

    private func accessibilitySummary(_ point: Point) -> String {
        (["\(point.label), \(TimesheetDuration.total(point.seconds))"] + point.projects.map {
            "\($0.name), \(TimesheetDuration.total($0.seconds)), \(percentage($0, in: point)) percent"
        }).joined(separator: "; ")
    }

    private func inspect(_ step: Int) {
        guard !points.isEmpty else { return }
        hovered = nil
        let index = points.firstIndex { String($0.id) == selected } ?? (step > 0 ? -1 : points.count)
        selected = String(points[min(points.count - 1, max(0, index + step))].id)
    }
}
