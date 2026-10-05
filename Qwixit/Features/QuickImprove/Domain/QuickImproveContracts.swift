import CoreGraphics

enum AppPhase: Equatable {
    case ready
    case processing
    case success
    case noSelection
    case permissionDenied
    case lastFreeAction
    case subscriptionActivating
    case limitReached
    case offline
    case error(String)
}

protocol AccessibilityServicing: AnyObject {
    var isTrusted: Bool { get }
    func requestPermission()
    func selectedText() async -> String?
    func selectionBounds() -> CGRect?
    func fallbackPoint() -> CGPoint
    func replaceSelection(_ originalText: String, with replacement: String) async -> Bool
}

protocol TextImproving: AnyObject {
    func improve(_ text: String, instruction: String?) async throws -> String
}

enum ReplacementVerification {
    /// A successful replacement usually collapses the selection. Some editors
    /// keep the inserted text selected, so that exact value is also accepted.
    static func succeeded(original: String, replacement: String, selectedAfter: String?) -> Bool {
        if original == replacement { return true }
        guard let selectedAfter, !selectedAfter.isEmpty else { return true }
        return selectedAfter == replacement
    }
}

@MainActor
protocol FeedbackPresenting: AnyObject {
    func show(
        phase: AppPhase,
        reduceMotion: Bool,
        anchor accessibilityBounds: CGRect?,
        fallbackPoint: CGPoint?
    )
    func hide()
}
