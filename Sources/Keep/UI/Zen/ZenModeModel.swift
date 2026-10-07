import Observation

@MainActor protocol ZenWindow: AnyObject {
    var isFullScreen: Bool { get }
    func toggleFullScreen()
}

/// Window-local presentation only. Timer recording and music retain their existing owners.
@Observable @MainActor final class ZenModeModel {
    enum Phase { case inactive, entering, active, leaving }
    private(set) var phase: Phase = .inactive
    @ObservationIgnored private weak var window: (any ZenWindow)?
    @ObservationIgnored private var restoresWindow = false

    var isPresented: Bool { phase == .entering || phase == .active }

    func attach(_ window: any ZenWindow) { self.window = window }

    func detach() {
        window = nil
        phase = .inactive
        restoresWindow = false
    }

    func enter() {
        guard phase == .inactive, let window else { return }
        restoresWindow = !window.isFullScreen
        phase = restoresWindow ? .entering : .active
        if restoresWindow { window.toggleFullScreen() }
    }

    func exit() {
        guard isPresented else { return }
        if !restoresWindow {
            phase = .inactive
        } else if phase == .entering {
            // AppKit must finish entering before another full-screen transition can start.
            phase = .leaving
        } else {
            phase = .leaving
            window?.toggleFullScreen()
        }
    }

    func didEnterFullScreen() {
        if phase == .entering { phase = .active }
        else if phase == .leaving { window?.toggleFullScreen() }
    }

    func willExitFullScreen() {
        if phase != .inactive { phase = .leaving }
    }

    func didExitFullScreen() {
        phase = .inactive
        restoresWindow = false
    }
}
