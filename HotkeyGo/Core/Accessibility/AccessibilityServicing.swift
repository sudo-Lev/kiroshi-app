import CoreGraphics

protocol AccessibilityServicing: AnyObject {
    var isTrusted: Bool { get }
    func requestPermission()
    func selectedText() async -> String?
    func selectionBounds() -> CGRect?
    func fallbackPoint() -> CGPoint
}

@MainActor
protocol AccessibilityAccessNoticePresenting: AnyObject {
    func showAccessibilityAccessNeeded(at point: CGPoint)
}
