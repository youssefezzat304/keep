import SwiftUI

/// An elapsed-time outline, drawn inside the card from the top center clockwise.
struct PomodoroProgressBorder: View {
    /// Breaks reuse the focus interval ID, but must start a fresh outline.
    struct Identity: Hashable {
        let intervalID: UUID
        let isBreak: Bool

        init(timer: FocusTimer) {
            intervalID = timer.intervalID
            isBreak = timer.interval == .rest
        }
    }

    let progress: Double
    let isRunning: Bool
    var cornerRadius: CGFloat = KeepTheme.cardRadius
    var lineWidth: CGFloat = 3
    var color: Color = KeepTheme.ink
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ClockwiseCardOutline(cornerRadius: cornerRadius, inset: lineWidth / 2)
            .trim(from: 0, to: min(1, max(0, progress)))
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .animation(isRunning && !reduceMotion ? .linear(duration: 0.2) : nil, value: progress)
            .opacity(progress > 0 ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct ClockwiseCardOutline: Shape {
    let cornerRadius: CGFloat
    let inset: CGFloat

    func path(in rect: CGRect) -> Path {
        // Rotate the native rounded rectangle's right-center start to the top center.
        // Swapping its dimensions preserves the card's continuous corners and bounds.
        let rotatedRect = CGRect(x: -rect.height / 2, y: -rect.width / 2,
                                 width: rect.height, height: rect.width)
        let outline = RoundedRectangle(cornerRadius: cornerRadius)
            .inset(by: inset)
            .path(in: rotatedRect)
        // Materialize the path so SwiftUI's rectangle optimization cannot move its start.
        return Path(outline.cgPath)
            .applying(CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: rect.midX, ty: rect.midY))
    }
}
