import SwiftUI

/// An elapsed-time outline, drawn inside the card from the top center clockwise.
struct PomodoroProgressBorder: View {
    let progress: Double
    let isRunning: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ClockwiseCardOutline(cornerRadius: KeepTheme.cardRadius, inset: 1.5)
            .trim(from: 0, to: min(1, max(0, progress)))
            .stroke(KeepTheme.ink, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
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
