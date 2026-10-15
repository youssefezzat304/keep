import SwiftUI

struct CalendarProjectBlockView: View {
    let block: CalendarProjectBlock
    let hourHeight: CGFloat

    var body: some View {
        GeometryReader { bounds in
            ZStack(alignment: .topLeading) {
                block.project.accentColor.opacity(0.3)
                ForEach(Array(block.gaps.enumerated()), id: \.offset) { _, gap in
                    let height = CGFloat(gap.upperBound - gap.lowerBound) / 60 * hourHeight
                    CalendarGapFill()
                        .overlay {
                            if height >= 24 {
                                Text("Gap").font(.system(size: 9)).foregroundStyle(KeepTheme.secondaryInk)
                            }
                        }
                        .frame(height: height)
                        .offset(y: CGFloat(gap.lowerBound - block.startMinute) / 60 * hourHeight)
                        .accessibilityHidden(true)
                }
                Rectangle().fill(block.project.accentColor).frame(width: 4)
                VStack(alignment: .leading, spacing: 4) {
                    Text(block.sessions.count == 1 ? block.sessions[0].title : block.project.name)
                        .font(.system(size: 11, weight: .medium)).lineLimit(bounds.size.height >= 90 ? 2 : 1)
                    if bounds.size.height >= 74 {
                        Text(block.sessions.count == 1 ? block.project.name : block.titles.joined(separator: " · "))
                            .font(.system(size: 10)).lineLimit(2)
                    }
                    if bounds.size.height >= 48 {
                        Spacer(minLength: 0)
                        HStack {
                            Text(calendarTime(block.startMinute)).font(.system(size: 9))
                                .lineLimit(1).fixedSize()
                            Spacer(minLength: 2)
                            Text(TimesheetDuration.clock(block.seconds)).font(.system(size: 10, weight: .medium))
                                .lineLimit(1).fixedSize()
                        }.monospacedDigit()
                    }
                }
                .padding(bounds.size.height < 48 ? 6 : 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(KeepTheme.ink)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(block.project.accentColor.opacity(0.7), lineWidth: 1) }
        }
    }
}

private struct CalendarGapFill: View {
    var body: some View {
        KeepTheme.surface.overlay(KeepTheme.mutedInk.opacity(0.12))
            .overlay {
                Canvas { context, size in
                    var path = Path()
                    for x in stride(from: -size.height, through: size.width, by: 9) {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                    }
                    context.stroke(path, with: .color(KeepTheme.mutedInk.opacity(0.20)), lineWidth: 1)
                }
            }
            .clipped().allowsHitTesting(false)
    }
}

struct CalendarBlockEntries: View {
    let block: CalendarProjectBlock
    let workspace: WorkspaceModel
    let onSelect: (RecordedSession) -> Void
    @Environment(\.dismiss) private var dismiss
    private var sessions: [RecordedSession] {
        _ = workspace.readIndex.revision
        return block.sessions.compactMap { workspace.readIndex.sessions[$0.id] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(block.project.name).font(KeepTheme.headingFont(size: 26)).fixedSize(horizontal: false, vertical: true)
            Text("\(sessions.count) recorded entries · \(TimesheetDuration.total(sessions.reduce(0) { $0 + $1.seconds }))")
                .font(.system(size: 13)).foregroundStyle(KeepTheme.mutedInk)
            KeepScrollView {
                VStack(spacing: 8) {
                    ForEach(sessions) { session in
                        Button { onSelect(session) } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(session.title).font(.system(size: 14, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                                    Text("\(session.startTime) – \(session.editableEndTime) · \(session.source.title)")
                                        .font(.system(size: 11)).foregroundStyle(KeepTheme.secondaryInk)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "pencil").accessibilityHidden(true)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                        }
                        .buttonStyle(KeepButtonStyle(emphasis: .quiet))
                        .accessibilityLabel("Edit \(session.title), \(session.startTime) to \(session.editableEndTime)")
                    }
                }
            }.frame(height: min(340, max(84, CGFloat(sessions.count) * 84)))
            Text("Shaded gaps contain no recorded time.").font(.system(size: 12)).foregroundStyle(KeepTheme.mutedInk)
            HStack {
                Spacer()
                Button("Close") { dismiss() }.buttonStyle(KeepButtonStyle(emphasis: .quiet)).keyboardShortcut(.cancelAction)
            }
        }.padding(24).frame(width: 430).foregroundStyle(KeepTheme.ink).background(KeepTheme.paper)
    }
}

private func calendarTime(_ minute: Double) -> String {
    let value = Int(minute)
    return String(format: "%02d:%02d", value / 60, value % 60)
}

