import AppKit

/// Adapts palette operations to the feedback pill used by the primary ⌥⌘X flow.
@MainActor
final class ResultHUDController {
    private let feedback: FeedbackPresenting
    private var dismissTask: Task<Void, Never>?
    var onUndo: (() -> Void)?

    init(feedback: FeedbackPresenting) {
        self.feedback = feedback
    }

    func showRunning(action: PaletteAction, capture: PaletteCapture) {
        present(.processing, capture: capture)
    }

    func showDone(action: PaletteAction, detail: String, capture: PaletteCapture) {
        if QwixitUsage.remaining == 0 {
            present(.lastFreeAction, capture: capture)
        } else {
            present(.success, capture: capture)
            scheduleDismiss(after: 2.8)
        }
    }

    func showError(_ message: String, capture: PaletteCapture?) {
        if let capture {
            present(.error(message), capture: capture)
        } else {
            dismissTask?.cancel()
            feedback.show(
                phase: .error(message),
                reduceMotion: reduceMotion,
                anchor: nil,
                fallbackPoint: NSEvent.mouseLocation
            )
        }
    }

    func showLimitReached(capture: PaletteCapture?) {
        dismissTask?.cancel()
        feedback.show(
            phase: .limitReached,
            reduceMotion: reduceMotion,
            anchor: capture?.bounds,
            fallbackPoint: capture?.fallbackPoint ?? NSEvent.mouseLocation
        )
    }

    func showSubscriptionActivating(capture: PaletteCapture?) {
        dismissTask?.cancel()
        feedback.show(
            phase: .subscriptionActivating,
            reduceMotion: reduceMotion,
            anchor: capture?.bounds,
            fallbackPoint: capture?.fallbackPoint ?? NSEvent.mouseLocation
        )
        scheduleDismiss(after: 4)
    }

    func showOffline(capture: PaletteCapture?) {
        dismissTask?.cancel()
        feedback.show(
            phase: .offline,
            reduceMotion: reduceMotion,
            anchor: capture?.bounds,
            fallbackPoint: capture?.fallbackPoint ?? NSEvent.mouseLocation
        )
        scheduleDismiss(after: 4)
    }

    func showNeutral(_ message: String, point: CGPoint) {
        dismissTask?.cancel()
        feedback.show(
            phase: .noSelection,
            reduceMotion: reduceMotion,
            anchor: nil,
            fallbackPoint: point
        )
        scheduleDismiss(after: 2.4)
    }

    func hide() {
        dismissTask?.cancel()
        feedback.hide()
    }

    private func present(_ phase: AppPhase, capture: PaletteCapture) {
        dismissTask?.cancel()
        feedback.show(
            phase: phase,
            reduceMotion: reduceMotion,
            anchor: capture.bounds,
            fallbackPoint: capture.fallbackPoint
        )
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || !AppPreferences().animationsEnabled
    }

    private func scheduleDismiss(after seconds: Double) {
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.feedback.hide()
        }
    }
}
