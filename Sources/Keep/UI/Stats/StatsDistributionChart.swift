import SwiftUI
import Charts

struct StatsDistributionChart: View {
    let rows: [StatsSnapshot.Distribution]
    let showsTasks: Bool
    let onSelect: (StatsSnapshot.Distribution) -> Void
    var compact = false
    @State private var hoveredID: String?
    @State private var inspectedID: String?
    @FocusState private var focused: Bool
    @Environment(\.self) private var environment

    private var total: Double { rows.reduce(0) { $0 + $1.seconds } }
    private var selected: StatsSnapshot.Distribution? {
        rows.first { $0.id == (hoveredID ?? inspectedID) }
    }
    private var title: String { showsTasks ? "Time by task" : "Where your time went" }

    var body: some View {
        let colors = segmentColors
        VStack(alignment: .leading, spacing: 20) {
            Text(title).font(KeepTheme.headingFont(size: 23))
            if rows.isEmpty {
                Text("Your recorded projects and tasks will appear here.").foregroundStyle(KeepTheme.mutedInk)
            } else {
                if compact {
                    VStack(spacing: 20) { ring(colors: colors); legend(colors: colors) }
                } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 32) {
                        ring(colors: colors)
                        legend(colors: colors).frame(minWidth: 240, maxWidth: .infinity)
                    }
                    VStack(spacing: 24) { ring(colors: colors); legend(colors: colors) }
                }
                }
            }
        }
        .onChange(of: rows.map(\.id)) { _, _ in hoveredID = nil; inspectedID = nil }
    }

    private func ring(colors: [String: Color]) -> some View {
        Chart(rows) { row in
            SectorMark(angle: .value("Recorded focus", row.seconds), innerRadius: .ratio(0.76), outerRadius: .ratio(0.98), angularInset: 3)
                .cornerRadius(10)
                .foregroundStyle(colors[row.id] ?? KeepTheme.ink)
                .opacity(selected == nil || selected?.id == row.id ? 1 : 0.4)
        }
        .chartLegend(.hidden)
        .chartBackground { _ in
            VStack(spacing: 8) {
                Text(selected?.name ?? "Total focus")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(KeepTheme.secondaryInk)
                    .lineLimit(3).multilineTextAlignment(.center)
                Text(TimesheetDuration.total(selected?.seconds ?? total))
                    .font(KeepTheme.headingFont(size: 32)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                if let selected {
                    Text("\(percentage(selected))%")
                        .font(.system(size: 13)).foregroundStyle(KeepTheme.secondaryInk).monospacedDigit()
                }
            }
            .frame(width: 170)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let plotFrame = proxy.plotFrame {
                    let frame = geometry[plotFrame]
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location): hoveredID = row(at: location, in: frame)?.id
                            case .ended: hoveredID = nil
                            }
                        }
                        .onTapGesture { location in
                            if let row = row(at: location, in: frame) { onSelect(row) }
                        }
                }
            }
        }
        .frame(width: compact ? 230 : 270, height: compact ? 230 : 270)
        .focusable().focused($focused).focusEffectDisabled()
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(focused ? KeepTheme.focusRing : .clear, lineWidth: 2).allowsHitTesting(false)
        }
        .onMoveCommand { direction in
            if direction == .left || direction == .right { inspect(direction == .right ? 1 : -1) }
        }
        .onKeyPress(.return) {
            guard let selected else { return .ignored }
            onSelect(selected)
            return .handled
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(selected.map { "\($0.name), \(TimesheetDuration.total($0.seconds)), \(percentage($0)) percent" }
            ?? "Total focus, \(TimesheetDuration.total(total))")
        .accessibilityHint("Use arrow keys to inspect sections and Return to filter, or choose a row below.")
        .accessibilityAdjustableAction { direction in inspect(direction == .increment ? 1 : -1) }
        .accessibilityAction { if let selected { onSelect(selected) } }
    }

    private func legend(colors: [String: Color]) -> some View {
        VStack(spacing: 4) {
            ForEach(rows) { row in
                Button { onSelect(row) } label: {
                    HStack(spacing: 12) {
                        Circle().fill(colors[row.id] ?? KeepTheme.ink).frame(width: 10, height: 10).accessibilityHidden(true)
                        Text(row.name).font(.system(size: 14, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 12)
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("\(percentage(row))%").font(.system(size: 14, weight: .medium))
                            Text(TimesheetDuration.total(row.seconds)).font(.system(size: 12)).foregroundStyle(KeepTheme.secondaryInk)
                        }.monospacedDigit().fixedSize()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 10)
                    .background(selected?.id == row.id ? KeepTheme.mutedWarm : .clear, in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering { hoveredID = row.id }
                    else if hoveredID == row.id { hoveredID = nil }
                }
                .accessibilityLabel("Filter to \(row.name), \(TimesheetDuration.total(row.seconds)), \(percentage(row)) percent")
                .help("Show \(row.name)")
            }
        }
    }

    private func percentage(_ row: StatsSnapshot.Distribution) -> Int {
        Int((row.seconds / max(1, total) * 100).rounded())
    }

    private var segmentColors: [String: Color] {
        // Task names have no saved accent; use distinct existing project colors in name-key order.
        let accents: [FocusProject.Accent] = [.terracotta, .sage, .mistBlue, .butter, .plum, .teal, .rose, .honey, .denim, .olive]
        return Dictionary(uniqueKeysWithValues: rows.sorted { $0.id < $1.id }.enumerated().map { index, row in
            let accent = showsTasks ? accents[index % accents.count] : FocusProject.Accent(rawValue: row.accent) ?? .neutral
            return (row.id, KeepTheme.readableAccent(accent.color, on: [KeepTheme.surface, KeepTheme.mutedWarm], environment: environment))
        })
    }

    private func inspect(_ step: Int) {
        guard !rows.isEmpty else { return }
        let index = rows.firstIndex { $0.id == inspectedID } ?? (step > 0 ? -1 : rows.count)
        inspectedID = rows[min(rows.count - 1, max(0, index + step))].id
    }

    private func row(at point: CGPoint, in frame: CGRect) -> StatsSnapshot.Distribution? {
        let x = point.x - frame.midX, y = point.y - frame.midY
        let radius = min(frame.width, frame.height) / 2
        let distance = hypot(x, y)
        guard radius > 0, distance >= radius * 0.76, distance <= radius * 0.98, total > 0 else { return nil }
        // Charts starts at twelve o’clock and proceeds clockwise.
        let angle = (atan2(y, x) + .pi / 2 + 2 * .pi).truncatingRemainder(dividingBy: 2 * .pi)
        let value = angle / (2 * .pi) * total
        var end = 0.0
        return rows.first { row in end += row.seconds; return value < end }
    }
}
