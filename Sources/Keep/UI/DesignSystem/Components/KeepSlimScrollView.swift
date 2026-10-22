import SwiftUI

/// A narrow, draggable indicator for the menu bar's compact lists.
struct KeepSlimScrollView<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var position = ScrollPosition(y: 0)
    @State private var metrics = Metrics()
    @State private var dragStart: CGFloat?

    private struct Metrics: Equatable {
        var content: CGFloat = 0
        var viewport: CGFloat = 0
        var offset: CGFloat = 0
        var topInset: CGFloat = 0
        var range: CGFloat { max(0, content - viewport) }
        var progress: CGFloat { range > 0 ? min(1, max(0, offset / range)) : 0 }
        var thumbHeight: CGFloat { min(viewport, max(24, viewport * viewport / max(1, content))) }
        var travel: CGFloat { max(0, viewport - thumbHeight) }
    }

    var body: some View {
        ScrollView {
            content.padding(.trailing, 12)
        }
        .scrollIndicators(.never)
        .scrollPosition($position)
        .onScrollGeometryChange(for: Metrics.self) { geometry in
            Metrics(content: geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom,
                    viewport: geometry.containerSize.height,
                    offset: geometry.contentOffset.y + geometry.contentInsets.top, topInset: geometry.contentInsets.top)
        } action: { _, value in metrics = value }
        .overlay(alignment: .topTrailing) {
            if metrics.range > 1 {
                Capsule().fill(KeepTheme.mutedInk.opacity(0.7))
                    .frame(width: 3, height: metrics.thumbHeight)
                    .frame(width: 12)
                    .contentShape(Rectangle())
                    .offset(y: metrics.progress * metrics.travel)
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        if dragStart == nil { dragStart = metrics.progress * metrics.travel }
                        let top = min(metrics.travel, max(0, (dragStart ?? 0) + value.translation.height))
                        position.scrollTo(y: top / max(1, metrics.travel) * metrics.range - metrics.topInset)
                    }.onEnded { _ in dragStart = nil })
                    .accessibilityLabel("Scroll list")
                    .accessibilityValue("\(Int(metrics.progress * 100)) percent")
                    .accessibilityAdjustableAction { direction in
                        let delta = direction == .increment ? metrics.viewport * 0.8 : -metrics.viewport * 0.8
                        position.scrollTo(y: min(metrics.range, max(0, metrics.offset + delta)) - metrics.topInset)
                    }
            }
        }
    }
}
