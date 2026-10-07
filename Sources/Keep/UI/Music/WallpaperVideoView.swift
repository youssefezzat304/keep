import AVFoundation
import SwiftUI

/// One layer/player pair per visible presentation, with no transport or pointer handling.
struct WallpaperVideoView: NSViewRepresentable {
    let video: WallpaperVideo
    let onFailure: (WallpaperVideo) -> Void

    func makeNSView(context: Context) -> WallpaperVideoSurface { WallpaperVideoSurface() }
    func updateNSView(_ view: WallpaperVideoSurface, context: Context) {
        view.configure(video, onFailure: onFailure)
    }
    static func dismantleNSView(_ view: WallpaperVideoSurface, coordinator: ()) { view.stop() }
}

final class WallpaperVideoSurface: NSView {
    private let playback = WallpaperVideoPlayback()
    private let videoLayer = AVPlayerLayer()
    private var video: WallpaperVideo?
    private var onFailure: (WallpaperVideo) -> Void = { _ in }
    private var windowObservers: [NSObjectProtocol] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        videoLayer.videoGravity = .resizeAspectFill
        videoLayer.player = playback.player
        layer?.addSublayer(videoLayer)
    }
    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        videoLayer.frame = bounds
        CATransaction.commit()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeObservers()
        if let window {
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                         NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification] {
                windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] event in
                    let closing = event.name == NSWindow.willCloseNotification
                    Task { @MainActor [weak self] in
                        if closing { self?.playback.stop() } else { self?.refresh() }
                    }
                })
            }
        }
        refresh()
    }
    func configure(_ video: WallpaperVideo, onFailure: @escaping (WallpaperVideo) -> Void) {
        self.video = video; self.onFailure = onFailure
        refresh()
    }
    private func refresh() {
        let visible = window?.isVisible == true && window?.isMiniaturized == false && window?.occlusionState.contains(.visible) == true
        playback.configure(video, active: visible, onFailure: onFailure)
    }
    func stop() { removeObservers(); playback.stop(); video = nil }
    private func removeObservers() {
        for observer in windowObservers { NotificationCenter.default.removeObserver(observer) }
        windowObservers = []
    }
}
