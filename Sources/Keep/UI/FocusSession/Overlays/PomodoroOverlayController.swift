import AppKit
import Observation
import SwiftUI

/// One app-owned presenter, driven by the recorder's existing refresh and observation.
final class PomodoroOverlayController: NSObject {
    private weak var workspace: WorkspaceModel?
    private weak var preferences: AppPreferences?
    private weak var sounds: TimerSoundPlayer?
    private var started = false
    private var topPanel: PomodoroOverlayPanel?
    private var breakPanels: [NSPanel] = []
    private var seenNoticeID: String?
    private var visibleNoticeID: String?
    private var visibleBreakNoticeID: String?
    private var dismissedBreakID: UUID?
    private var lastRepetition: SoundRepetition?
    private var lastScreenFrames: [CGRect] = []

    func start(workspace: WorkspaceModel, preferences: AppPreferences, sounds: TimerSoundPlayer) {
        guard !started else { return }
        started = true; self.workspace = workspace; self.preferences = preferences; self.sounds = sounds
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        observe()
    }

    private func observe() {
        guard started, let workspace, let preferences else { return }
        let input = withObservationTracking {
            (workspace.pomodoro, workspace.flow, workspace.pomodoroCompletion, workspace.displayInstant, preferences.snapshot,
             workspace.canTrack && preferences.canEdit)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observe() }
        }
        update(timer: input.0, flow: input.1, notice: input.2, instant: input.3, settings: input.4, available: input.5)
    }

    @objc private func screensChanged() {
        lastScreenFrames = []
        refresh()
    }

    private func refresh() {
        guard let workspace, let preferences else { return }
        update(timer: workspace.pomodoro, flow: workspace.flow, notice: workspace.pomodoroCompletion, instant: workspace.displayInstant,
               settings: preferences.snapshot, available: workspace.canTrack && preferences.canEdit)
    }

    private func update(timer: FocusTimer, flow: FocusTimer, notice: PomodoroCompletionNotice?, instant: ContinuousClock.Instant,
                        settings: SettingsArchive, available: Bool) {
        let repetition: SoundRepetition = settings.repeatPomodoroSound == true
            ? (settings.pomodoroSoundRepeatMode == .count ? .count(settings.pomodoroSoundRepeatCount ?? 3) : .untilDismissed) : .once
        if notice == nil || !available || settings.timerSoundsEnabled == false || repetition == .once || (lastRepetition != nil && lastRepetition != repetition) {
            sounds?.stopRepeating()
        }
        lastRepetition = repetition
        if notice?.id != seenNoticeID {
            seenNoticeID = notice?.id
            visibleBreakNoticeID = available && settings.blurPomodoroBreaks == true && notice?.isBreak == false ? notice?.id : nil
            visibleNoticeID = available && settings.notchPomodoroCompletion == true && visibleBreakNoticeID == nil ? notice?.id : nil
        }
        if settings.blurPomodoroBreaks != true || !available { visibleBreakNoticeID = nil }
        if settings.notchPomodoroCompletion != true || !available {
            visibleNoticeID = nil
        }
        let visibleNotice = notice.flatMap { $0.id == visibleNoticeID ? $0 : nil }
        let phase = timer.phase(at: instant)
        let timers = [settings.notchPomodoroTimer == true ? timer : nil, settings.notchFlowTimer == true ? flow : nil]
            .compactMap { $0 }.filter { $0.phase(at: instant) == .running || $0.phase(at: instant) == .stopped }
        if available, visibleNotice != nil || !timers.isEmpty, let screen = preferredScreen {
            let layout = PomodoroOverlayLayout(screen: screen.frame, topInset: screen.safeAreaInsets.top,
                leftArea: screen.auxiliaryTopLeftArea ?? .zero, rightArea: screen.auxiliaryTopRightArea ?? .zero, expanded: visibleNotice != nil,
                compactSideWidth: PomodoroOverlayLayout.compactSideWidth(for: timers, at: instant))
            let isNew = topPanel == nil
            let panel = topPanel ?? makePanel(frame: layout.frame, level: NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2))
            let changed = panel.frame != layout.frame
            panel.title = "Keep timers"
            panel.onEscape = { [weak self] in self?.dismissNotice() }
            panel.ignoresMouseEvents = visibleNotice == nil
            install(TimerNotchView(timers: timers, instant: instant, layout: layout, notice: visibleNotice,
                dismiss: { [weak self] in self?.dismissNotice() }, next: { [weak self] in self?.nextInterval() }), in: panel)
            if changed { panel.setFrame(layout.frame, display: true, animate: !isNew && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) }
            panel.orderFrontRegardless(); topPanel = panel
        } else { topPanel?.close(); topPanel = nil }

        if timer.interval != .rest { dismissedBreakID = nil }
        let showsBreakNotice = notice != nil && notice?.id == visibleBreakNoticeID
        let showsRunningBreak = timer.interval == .rest && phase == .running && dismissedBreakID != timer.intervalID
        let showBreak = available && settings.blurPomodoroBreaks == true && (showsBreakNotice || showsRunningBreak)
        if showBreak {
            let screens = NSScreen.screens
            if breakPanels.count != screens.count || lastScreenFrames != screens.map(\.frame) {
                closeBreakPanels()
                lastScreenFrames = screens.map(\.frame)
                breakPanels = screens.map { screen in
                    let panel = makePanel(frame: screen.frame, level: NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1))
                    panel.title = "Keep Pomodoro break"
                    panel.onEscape = { [weak self] in self?.dismissBreak() }
                    return panel
                }
            }
            for (panel, screen) in zip(breakPanels, screens) {
                let isNew = !panel.isVisible
                install(PomodoroBreakView(timer: timer, instant: instant, date: .now, screenTopInset: screen.safeAreaInsets.top,
                    dismiss: { [weak self] in self?.dismissBreak() }, start: { [weak self] in self?.workspace?.startBreak() }, skip: { [weak self] in self?.workspace?.skipPomodoroBreak() }), in: panel)
                if isNew {
                    let animate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                    panel.alphaValue = animate ? 0 : 1
                    if panel.frame == preferredScreen?.frame { panel.makeKeyAndOrderFront(nil) }
                    else { panel.orderFrontRegardless() }
                    if animate {
                        NSAnimationContext.runAnimationGroup { context in
                            context.duration = 0.3; panel.animator().alphaValue = 1
                        }
                    }
                }
            }
        } else { closeBreakPanels() }
    }

    private func install<V: View>(_ root: V, in panel: NSPanel) {
        if let host = panel.contentView as? NSHostingView<V> { host.rootView = root }
        else {
            let host = NSHostingView(rootView: root); host.sizingOptions = []
            panel.contentView = host
        }
    }

    private var preferredScreen: NSScreen? { NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first }
    private func makePanel(frame: CGRect, level: NSWindow.Level) -> PomodoroOverlayPanel {
        let panel = PomodoroOverlayPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.isFloatingPanel = true; panel.hidesOnDeactivate = false; panel.worksWhenModal = true
        panel.level = level; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
        panel.animationBehavior = .utilityWindow
        return panel
    }
    private func dismissNotice() { workspace?.dismissPomodoroCompletion(); sounds?.stopRepeating(); visibleNoticeID = nil; refresh() }
    private func nextInterval() {
        guard let workspace else { return }
        if workspace.pomodoro.interval == .focus { workspace.startBreak() } else { workspace.play(.pomodoro) }
    }
    private func dismissBreak() {
        guard let workspace else { return }
        if workspace.pomodoro.interval == .rest { dismissedBreakID = workspace.pomodoro.intervalID }
        visibleBreakNoticeID = nil
        workspace.dismissPomodoroCompletion()
        sounds?.stopRepeating()
        closeBreakPanels()
    }
    private func closeBreakPanels() { breakPanels.forEach { $0.close() }; breakPanels = [] }

    func shutdown() {
        started = false; NotificationCenter.default.removeObserver(self)
        topPanel?.close(); topPanel = nil; closeBreakPanels(); sounds?.stopRepeating()
    }
}

private final class PomodoroOverlayPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { !ignoresMouseEvents }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}
