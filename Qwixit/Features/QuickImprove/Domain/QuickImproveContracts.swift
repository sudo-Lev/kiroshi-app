import CoreGraphics

enum AppPhase: Equatable {
    case ready
    case processing
    case success
    case pasteSent
    case noSelection
    case permissionDenied
    case limitReached
    /// Fix found nothing to change; the selection and clipboard stay untouched.
    case alreadyClean
    case retrying(attempt: Int, total: Int)
    case offline
    case error(String)
}

@MainActor
protocol ReviewPresenting: AnyObject {
    func show(
        original: String,
        proposed: String,
        anchor accessibilityBounds: CGRect?,
        fallbackPoint: CGPoint?,
        onApply: @escaping () -> Void,
        onCancel: @escaping (_ restoreFocus: Bool) -> Void
    )
    func hide()
}

protocol SelectionSnapshotProviding: AnyObject {
    func captureSelection() async -> TextSelectionSnapshot?
    func replaceSelection(_ snapshot: TextSelectionSnapshot, with replacement: String) async -> ReplacementAttemptReport
    func restoreFocus(_ snapshot: TextSelectionSnapshot)
}

protocol AccessibilityServicing: AnyObject {
    var isTrusted: Bool { get }
    func requestPermission()
    func selectedText() async -> String?
    func selectionBounds() -> CGRect?
    func fallbackPoint() -> CGPoint
}

protocol TextImproving: AnyObject {
    func improve(_ text: String) async throws -> FixOutcome
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
