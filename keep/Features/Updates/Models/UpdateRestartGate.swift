import Foundation
import Observation

/// Retains Sparkle's continuation until the user agrees to end any active timers.
@Observable
final class UpdateRestartGate {
    private(set) var isPending = false
    @ObservationIgnored private var continuation: (() -> Void)?
    @ObservationIgnored private let needsConfirmation: () -> Bool
    @ObservationIgnored private let prepare: () -> Bool

    init(needsConfirmation: @escaping () -> Bool, prepare: @escaping () -> Bool) {
        self.needsConfirmation = needsConfirmation
        self.prepare = prepare
    }

    var requiresConfirmation: Bool { needsConfirmation() }

    func postpone(_ continuation: @escaping () -> Void) {
        self.continuation = continuation
        isPending = true
    }

    @discardableResult
    func resume(confirmed: Bool) -> Bool {
        guard let continuation, !needsConfirmation() || confirmed else { return false }
        guard prepare() else { return false }
        self.continuation = nil
        isPending = false
        continuation()
        return true
    }

    func cancel() {
        continuation = nil
        isPending = false
    }
}
