import Foundation

/// Runtime access reported by macOS; permission is never stored as a preference.
nonisolated enum AppleMusicAccess: Equatable, Sendable {
    case notChecked, checking, notRequested, allowed, denied, failed

    var title: String {
        switch self {
        case .notChecked: "Not checked"
        case .checking: "Checking…"
        case .notRequested: "Not requested"
        case .allowed: "Allowed"
        case .denied: "Not allowed"
        case .failed: "Couldn’t connect"
        }
    }
}
