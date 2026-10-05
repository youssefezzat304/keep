import SwiftUI

struct TimesheetView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center) {
                    heading
                    Spacer(minLength: 16)
                    sampleLabel
                }
                VStack(alignment: .leading, spacing: 12) {
                    heading
                    sampleLabel
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) {
                    weekPicker
                    Spacer(minLength: 12)
                    weekSummary
                }
                VStack(alignment: .leading, spacing: 16) {
                    weekPicker
                    weekSummary
                }
            }

            TimesheetTable()

            HStack {
                Button {} label: {
                    Label("Add project", systemImage: "plus")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(KeepTheme.accentStrong)
                .disabled(true)
                .help("Add a project")

                Spacer()

                Button {} label: {
                    HStack(spacing: 8) {
                        Text("Copy last week")
                        Image(systemName: "chevron.down").font(.system(size: 9))
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(KeepTheme.surface, in: RoundedRectangle(cornerRadius: 9))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(KeepTheme.border, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(true)
            }

            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .accessibilityHidden(true)
                Text("Daily entries are shown as hours : minutes")
                Spacer()
                Text("A week of small steps.")
            }
            .font(.system(size: 11))
            .foregroundStyle(KeepTheme.mutedInk)
        }
        .foregroundStyle(KeepTheme.ink)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Your week, at a glance.")
                .font(.system(size: 36, weight: .regular, design: .serif))
                .fixedSize(horizontal: true, vertical: false)
            Text("Time spent across your projects, Monday to Sunday.")
                .font(.system(size: 14))
                .foregroundStyle(KeepTheme.mutedInk)
        }
    }

    private var sampleLabel: some View {
        Label("Sample week", systemImage: "sparkle")
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(KeepTheme.highlight.opacity(0.6), in: Capsule())
    }

    private var weekPicker: some View {
        HStack(spacing: 12) {
            weekArrow("chevron.left", label: "Previous week")
            Image(systemName: "calendar")
                .foregroundStyle(KeepTheme.accentStrong)
                .accessibilityHidden(true)
            Text(TimesheetMockData.weekRange)
                .font(.system(size: 13, weight: .medium))
                .fixedSize(horizontal: true, vertical: false)
            Text(TimesheetMockData.weekNumber)
                .font(.system(size: 10, weight: .medium))
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(KeepTheme.mutedInk)
            weekArrow("chevron.right", label: "Next week")
        }
        .padding(.horizontal, 8)
        .frame(height: 46)
        .background(KeepTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(KeepTheme.border, lineWidth: 1)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var weekSummary: some View {
        HStack(spacing: 14) {
            VStack(alignment: .trailing, spacing: 4) {
                Text("WEEK TOTAL")
                    .font(.system(size: 9, weight: .medium))
                    .tracking(1.4)
                    .foregroundStyle(KeepTheme.mutedInk)
                Text(TimesheetMockData.projectCount)
                    .font(.system(size: 11))
                    .foregroundStyle(KeepTheme.mutedInk)
            }
            Text(TimesheetMockData.weekTotal)
                .font(.system(size: 29, weight: .regular, design: .serif))
                .foregroundStyle(KeepTheme.accentStrong)
                .monospacedDigit()
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
    }

    private func weekArrow(_ symbol: String, label: String) -> some View {
        Button {} label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .frame(width: 24, height: 32)
        }
        .buttonStyle(.plain)
        .disabled(true)
        .accessibilityLabel(label)
    }
}

#Preview {
    TimesheetView()
        .padding(24).frame(width: 1000).background(KeepTheme.paper)
}
