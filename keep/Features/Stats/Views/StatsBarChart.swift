import SwiftUI
import Charts

struct StatsBarChart: View {
    struct Point: Identifiable {
        let id: Int
        let label: String
        let seconds: Double
    }
    let title: String
    let points: [Point]
    var color: Color = KeepTheme.accentStrong
    @State private var selected: String?
    @State private var hovered: String?
    @FocusState private var focused: Bool

    private var inspectedID: String? { hovered ?? selected }
    private var selectedPoint: Point? { points.first { String($0.id) == inspectedID } }
    private var axisValues: [String] {
        let step = max(1, Int(ceil(Double(points.count) / 8)))
        return points.enumerated().compactMap { $0.offset % step == 0 ? String($0.element.id) : nil }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(KeepTheme.headingFont(size: 23))
            Chart {
                ForEach(points) { point in
                    BarMark(x: .value("Period", String(point.id)), y: .value("Hours", point.seconds / 3600), width: .ratio(0.65))
                        .foregroundStyle(color).cornerRadius(4)
                        .opacity(inspectedID == nil || inspectedID == String(point.id) ? 1 : 0.45)
                        .accessibilityLabel(point.label)
                        .accessibilityValue(TimesheetDuration.total(point.seconds))
                }
                if let point = selectedPoint {
                    RuleMark(x: .value("Period", String(point.id)))
                        .foregroundStyle(KeepTheme.mutedInk)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, spacing: 0,
                            overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            VStack(spacing: 4) {
                                Text(point.label).font(.system(size: 12, weight: .medium))
                                Text(TimesheetDuration.total(point.seconds)).font(.system(size: 13)).monospacedDigit()
                            }
                            .foregroundStyle(KeepTheme.ink).padding(10)
                            .background(KeepTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(KeepTheme.border) }
                            .allowsHitTesting(false)
                        }
                        .accessibilityHidden(true)
                }
            }
            .chartXSelection(value: $selected)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    if let plotFrame = proxy.plotFrame {
                        let frame = geometry[plotFrame]
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    hovered = frame.contains(location) ? proxy.value(atX: location.x - frame.minX, as: String.self) : nil
                                case .ended: hovered = nil
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
            .frame(height: 190)
            .focusable().focused($focused).focusEffectDisabled()
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(focused ? KeepTheme.focusRing : .clear, lineWidth: 2).allowsHitTesting(false) }
            .onMoveCommand { direction in
                if direction == .left || direction == .right { inspect(direction == .right ? 1 : -1) }
            }
            .accessibilityLabel(title)
            .accessibilityValue(selectedPoint.map { "\($0.label), \(TimesheetDuration.total($0.seconds))" } ?? "Recorded focus in hours")
            .accessibilityHint("Use left and right arrow keys to inspect values.")
            .accessibilityAdjustableAction { direction in inspect(direction == .increment ? 1 : -1) }
            Text("Recorded focus · hours")
                .font(.system(size: 12)).foregroundStyle(KeepTheme.secondaryInk).monospacedDigit()
        }
    }

    private func inspect(_ step: Int) {
        guard !points.isEmpty else { return }
        hovered = nil
        let index = points.firstIndex { String($0.id) == selected } ?? (step > 0 ? -1 : points.count)
        selected = String(points[min(points.count - 1, max(0, index + step))].id)
    }
}
