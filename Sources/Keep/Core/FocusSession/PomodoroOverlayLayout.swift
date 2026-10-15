import Foundation
import CoreGraphics

/// All coordinates are AppKit screen points, including displays with negative origins.
struct PomodoroOverlayLayout {
    let frame: CGRect
    let cameraWidth: CGFloat
    let topPadding: CGFloat

    static func compactSideWidth(for timers: [FocusTimer], at instant: ContinuousClock.Instant) -> CGFloat {
        let characters = timers.map { TimerNotchFormat.display($0, at: instant).count }.max() ?? 0
        // Allow for monospaced digits, and an icon in each wing when showing both timers.
        return max(64, CGFloat(characters) * 9 + (timers.count > 1 ? 40 : 24))
    }

    init(screen: CGRect, topInset: CGFloat, leftArea: CGRect, rightArea: CGRect, expanded: Bool, compactSideWidth: CGFloat = 64) {
        let hasCamera = topInset > 0 && !leftArea.isEmpty && !rightArea.isEmpty && rightArea.minX > leftArea.maxX
        cameraWidth = hasCamera ? rightArea.minX - leftArea.maxX : 0
        topPadding = hasCamera ? topInset : 8
        let width = min(screen.width - 16, expanded ? max(420, cameraWidth + 180) : max(176, cameraWidth + compactSideWidth * 2))
        let height = expanded ? topPadding + 164 : (hasCamera ? topInset : 28)
        let center = hasCamera ? (leftArea.maxX + rightArea.minX) / 2 : screen.midX
        frame = CGRect(x: min(screen.maxX - width - 8, max(screen.minX + 8, center - width / 2)),
                       y: screen.maxY - height, width: width, height: height)
    }
}

/// Formatting belongs to the notch presentation, independently of the timer's timing precision.
enum TimerNotchFormat {
    static func display(_ timer: FocusTimer, at instant: ContinuousClock.Instant) -> String {
        guard timer.mode == .flow else { return timer.display(at: instant) }
        let seconds = timer.seconds(at: instant)
        return String(format: "%02d:%02d", seconds / 3600, seconds / 60 % 60)
    }
}
