import CoreGraphics

enum AppPhase: Equatable {
    case ready
    case processing
    case success
    case noSelection
    case permissionDenied
    case error(String)
}

protocol AccessibilityServicing: AnyObject {
    var isTrusted: Bool { get }
    func requestPermission()
    func selectedText() async -> String?
    func selectionBounds() -> CGRect?
    func fallbackPoint() -> CGPoint
    func replaceSelection(with text: String) async -> Bool
}

protocol TextImproving: AnyObject {
    func improve(_ text: String, instruction: String?) async throws -> String
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
