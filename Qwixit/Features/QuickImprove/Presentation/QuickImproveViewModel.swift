import CoreGraphics
import Foundation

@MainActor
final class QuickImproveViewModel: ObservableObject {
    @Published private(set) var phase: AppPhase = .ready

    var isProcessing: Bool { phase == .processing }

    private let accessibility: AccessibilityServicing
    private let improver: TextImproving
    private let feedback: FeedbackPresenting
    private let preferences: UserDefaults
    private var resetTask: Task<Void, Never>?
    private var improvementTask: Task<Void, Never>?
    private var activeSelectionBounds: CGRect?
    private var activeFallbackPoint: CGPoint?

    init(
        accessibility: AccessibilityServicing,
        improver: TextImproving,
        feedback: FeedbackPresenting,
        preferences: UserDefaults = .standard
    ) {
        self.accessibility = accessibility
        self.improver = improver
        self.feedback = feedback
        self.preferences = preferences
    }

    func stop() {
        improvementTask?.cancel()
        resetTask?.cancel()
    }

    func improveSelection(instruction: String? = nil) {
        improvementTask?.cancel()
        improvementTask = Task { [weak self] in
            await self?.runImprovement(instruction: instruction)
        }
    }

    private func runImprovement(instruction: String?) async {
        activeSelectionBounds = nil
        activeFallbackPoint = accessibility.fallbackPoint()

        guard accessibility.isTrusted else {
            show(.permissionDenied, duration: 4)
            return
        }

        let selectionBounds = accessibility.selectionBounds()
        guard let selection = await accessibility.selectedText(),
              !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !Task.isCancelled else {
            if !Task.isCancelled { show(.noSelection, duration: 2.4) }
            return
        }
        activeSelectionBounds = selectionBounds ?? accessibility.selectionBounds()
        show(.processing, duration: nil)

        do {
            let improved = try await improver.improve(selection, instruction: instruction)
            try Task.checkCancellation()
            guard await accessibility.replaceSelection(with: improved) else {
                show(.error("The active app did not allow replacement. Your text is unchanged."), duration: 4)
                return
            }
            try Task.checkCancellation()
            show(.success, duration: 1.25)
        } catch is CancellationError {
            feedback.hide()
            phase = .ready
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? "Qwixit couldn’t improve the text. Your text is unchanged."
            show(.error(message), duration: 4)
        }
    }

    private func show(_ newPhase: AppPhase, duration: Double?) {
        resetTask?.cancel()
        phase = newPhase
        let appPreferences = AppPreferences(defaults: preferences)
        let animationsEnabled = appPreferences.animationsEnabled
        let showSuccess = appPreferences.showSuccess

        switch newPhase {
        case .success where !showSuccess, .ready:
            feedback.hide()
        default:
            feedback.show(
                phase: newPhase,
                reduceMotion: !animationsEnabled,
                anchor: activeSelectionBounds,
                fallbackPoint: activeFallbackPoint
            )
        }

        guard let duration else { return }
        resetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, let self else { return }
            feedback.hide()
            phase = .ready
            activeSelectionBounds = nil
            activeFallbackPoint = nil
        }
    }
}
