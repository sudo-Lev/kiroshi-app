import CoreGraphics
import Foundation

@MainActor
final class QuickImproveViewModel: ObservableObject {
    @Published private(set) var phase: AppPhase = .ready

    var isProcessing: Bool { phase == .processing }

    private let accessibility: AccessibilityServicing
    private let improver: TextImproving
    private let feedback: FeedbackPresenting
    private let review: ReviewPresenting?
    private let selectionSnapshots: SelectionSnapshotProviding?
    private let preferences: UserDefaults
    private var resetTask: Task<Void, Never>?
    private var improvementTask: Task<Void, Never>?
    private var processingFeedbackTask: Task<Void, Never>?
    private var activeSelectionBounds: CGRect?
    private var activeFallbackPoint: CGPoint?
    private var pendingReview: PendingReview?

    private struct PendingReview {
        let snapshot: TextSelectionSnapshot
        let proposed: String
    }

    init(
        accessibility: AccessibilityServicing,
        improver: TextImproving,
        feedback: FeedbackPresenting,
        review: ReviewPresenting? = nil,
        selectionSnapshots: SelectionSnapshotProviding? = nil,
        preferences: UserDefaults = .standard
    ) {
        self.accessibility = accessibility
        self.improver = improver
        self.feedback = feedback
        self.review = review
        self.selectionSnapshots = selectionSnapshots
        self.preferences = preferences
    }

    func stop() {
        improvementTask?.cancel()
        resetTask?.cancel()
        processingFeedbackTask?.cancel()
        pendingReview = nil
        review?.hide()
    }

    func improveSelection(instruction: String? = nil) {
        improvementTask?.cancel()
        processingFeedbackTask?.cancel()
        pendingReview = nil
        review?.hide()
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

        let snapshot = await selectionSnapshots?.captureSelection()
        let selection: String?
        if let snapshot {
            selection = snapshot.text
            activeSelectionBounds = snapshot.bounds
            activeFallbackPoint = snapshot.fallbackPoint
        } else {
            selection = await accessibility.selectedText()
            activeSelectionBounds = accessibility.selectionBounds()
            activeFallbackPoint = accessibility.fallbackPoint()
        }

        guard let selection,
              !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !Task.isCancelled else {
            if !Task.isCancelled { show(.noSelection, duration: 2.4) }
            return
        }
        scheduleProcessingFeedback()

        do {
            let improved = try await improver.improve(selection, instruction: instruction)
            try Task.checkCancellation()
            processingFeedbackTask?.cancel()
            processingFeedbackTask = nil

            if let snapshot,
               AppPreferences(defaults: preferences).reviewBeforeApplying,
               let review {
                pendingReview = PendingReview(snapshot: snapshot, proposed: improved)
                feedback.hide()
                phase = .ready
                review.show(
                    original: selection,
                    proposed: improved,
                    anchor: activeSelectionBounds,
                    fallbackPoint: activeFallbackPoint,
                    onApply: { [weak self] in
                        Task { @MainActor [weak self] in await self?.applyReview() }
                    },
                    onCancel: { [weak self] in self?.discardReview() }
                )
                return
            }

            let replaced: Bool
            if let snapshot, let selectionSnapshots {
                replaced = await selectionSnapshots.replaceSelection(snapshot, with: improved)
            } else {
                replaced = await accessibility.replaceSelection(selection, with: improved)
            }
            guard replaced else {
                show(.error("The active app did not allow replacement. Your text is unchanged."), duration: 4)
                return
            }
            try Task.checkCancellation()
            show(.success, duration: 1.25)
        } catch is CancellationError {
            processingFeedbackTask?.cancel()
            processingFeedbackTask = nil
            feedback.hide()
            phase = .ready
        } catch QwixitAPIError.quotaExceeded {
            processingFeedbackTask?.cancel()
            processingFeedbackTask = nil
            show(.limitReached, duration: nil)
        } catch let error where QwixitAPI.isConnectivityError(error) {
            processingFeedbackTask?.cancel()
            processingFeedbackTask = nil
            show(.offline, duration: nil)
        } catch {
            processingFeedbackTask?.cancel()
            processingFeedbackTask = nil
            let message = (error as? LocalizedError)?.errorDescription
                ?? "Tokiri couldn’t improve the text. Your text is unchanged."
            show(.error(message), duration: 4)
        }
    }

    private func applyReview() async {
        guard let pendingReview else { return }
        review?.hide()
        self.pendingReview = nil

        guard let selectionSnapshots,
              await selectionSnapshots.replaceSelection(
            pendingReview.snapshot,
            with: pendingReview.proposed
        ) else {
            show(.error("The active app did not allow replacement. Your text is unchanged."), duration: 4)
            return
        }

        show(.success, duration: 1.25)
    }

    private func discardReview() {
        guard let pendingReview else { return }
        selectionSnapshots?.restoreFocus(pendingReview.snapshot)
        self.pendingReview = nil
        show(.ready, duration: nil)
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

    private func scheduleProcessingFeedback() {
        processingFeedbackTask?.cancel()
        processingFeedbackTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(180))
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            self.show(.processing, duration: nil)
        }
    }

}
