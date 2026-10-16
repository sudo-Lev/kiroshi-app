import CoreGraphics
import Foundation

enum ReplacementStepStatus: Equatable {
    case completed
    case failed
    case notAttempted
}

/// Text-free record of the shared clipboard-and-paste path.
struct ReplacementAttemptReport: Equatable {
    var clipboardWrite: ReplacementStepStatus = .notAttempted
    var caretMove: ReplacementStepStatus = .notAttempted
    var pasteEvent: ReplacementStepStatus = .notAttempted

    /// Means the fresh text was written to the clipboard and ⌘V was posted.
    /// It does not claim that the receiving app accepted the paste.
    var isSubmitted: Bool {
        clipboardWrite == .completed
            && caretMove != .failed
            && pasteEvent == .completed
    }

    static let notSubmitted = ReplacementAttemptReport()

    static let submitted = ReplacementAttemptReport(
        clipboardWrite: .completed,
        pasteEvent: .completed
    )

    static let pasteFailed = ReplacementAttemptReport(
        clipboardWrite: .completed,
        pasteEvent: .failed
    )
}

@MainActor
protocol ReplacementRecoveryPresenting: AnyObject {
    func show(
        freshText: String,
        report: ReplacementAttemptReport,
        anchor accessibilityBounds: CGRect?,
        fallbackPoint: CGPoint?,
        onClose: @escaping () -> Void
    )
    func hide()
}
