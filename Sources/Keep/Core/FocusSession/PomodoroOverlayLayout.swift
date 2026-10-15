import Foundation
import CoreGraphics

/// All coordinates are AppKit screen points, including displays with negative origins.
struct PomodoroOverlayLayout {
    let frame: CGRect
    let cameraWidth: CGFloat
    let topPadding: CGFloat

    init(screen: CGRect, topInset: CGFloat, leftArea: CGRect, rightArea: CGRect, expanded: Bool) {
        let hasCamera = topInset > 0 && !leftArea.isEmpty && !rightArea.isEmpty && rightArea.minX > leftArea.maxX
        cameraWidth = hasCamera ? rightArea.minX - leftArea.maxX : 0
        topPadding = hasCamera ? topInset : 8
        let width = min(screen.width - 16, expanded ? max(420, cameraWidth + 180) : max(260, cameraWidth + 180))
        let height = expanded ? topPadding + 164 : max(32, topInset) + 6
        let center = hasCamera ? (leftArea.maxX + rightArea.minX) / 2 : screen.midX
        frame = CGRect(x: min(screen.maxX - width - 8, max(screen.minX + 8, center - width / 2)),
                       y: screen.maxY - height, width: width, height: height)
    }
}
