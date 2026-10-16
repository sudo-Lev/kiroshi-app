import CoreGraphics
import Foundation

@MainActor
final class QuickImproveViewModel: ObservableObject {
    @Published private(set) var phase: AppPhase = .ready

    var isProcessing: Bool { phase == .processing }

    private let accessibility: AccessibilityServicing
    private let improver: TextImproving
    private let feedback: FeedbackPresenting
    private let recovery: ReplacementRecoveryPresenting?
    private let review: ReviewPresenting?
    private let selectionSnapshots: SelectionSnapshotProviding?
    private let preferences: UserDefaults
    private var resetTask: Task<Void, Never>?
    private var improvementTask: Task<Void, Never>?
    private var processingFeedbackTask: Task<Void, Never>?
    private var applyTask: Task<Void, Never>?
    private var runID = UUID()
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
        recovery: ReplacementRecoveryPresenting? = nil,
        review: ReviewPresenting? = nil,
        selectionSnapshots: SelectionSnapshotProviding? = nil,
        preferences: UserDefaults = .standard
    ) {
        self.accessibility = accessibility
        self.improver = improver
        self.feedback = feedback
        self.recovery = recovery
        self.review = review
        self.selectionSnapshots = selectionSnapshots
        self.preferences = preferences
    }

    func stop() {
        runID = UUID()
        improvementTask?.cancel()
        applyTask?.cancel()
        resetTask?.cancel()
        processingFeedbackTask?.cancel()
        pendingReview = nil
        review?.hide()
        recovery?.hide()
        feedback.hide()
        phase = .ready
    }

    func improveSelection(instruction: String? = nil) {
        runID = UUID()
        let currentRun = runID
        improvementTask?.cancel()
        applyTask?.cancel()
        resetTask?.cancel()
        processingFeedbackTask?.cancel()
        pendingReview = nil
        review?.hide()
        recovery?.hide()
        feedback.hide()
        phase = .ready
        improvementTask = Task { [weak self] in
            await self?.runImprovement(instruction: instruction, runID: currentRun)
        }
    }

    private func runImprovement(instruction: String?, runID currentRun: UUID) async {
        guard runID == currentRun, !Task.isCancelled else { return }
        activeSelectionBounds = nil
        activeFallbackPoint = accessibility.fallbackPoint()

        guard accessibility.isTrusted else {
            show(.permissionDenied, duration: 4)
            return
        }

        let snapshot = await selectionSnapshots?.captureSelection()
        guard runID == currentRun, !Task.isCancelled else { return }
        let wantsReview = AppPreferences(defaults: preferences).reviewBeforeApplying
        if wantsReview && (snapshot == nil || review == nil) {
            show(.error("Preview could not preserve this selection. Your text is unchanged."), duration: 4)
            return
        }
        let selection: String?
        if let snapshot {
            selection = snapshot.text
            activeSelectionBounds = snapshot.bounds
            activeFallbackPoint = snapshot.fallbackPoint
        } else {
            selection = await accessibility.selectedText()
            guard runID == currentRun, !Task.isCancelled else { return }
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
            let improved = try await NetworkRetry.perform(
                operation: {
                    try await improver.improve(selection, instruction: instruction)
                },
                onRetry: { [weak self] attempt, total in
                    guard let self,
                          self.runID == currentRun,
                          !Task.isCancelled else { return }
                    self.processingFeedbackTask?.cancel()
                    self.processingFeedbackTask = nil
                    self.show(.retrying(attempt: attempt, total: total), duration: nil)
                }
            )
            try Task.checkCancellation()
            guard runID == currentRun else { return }
            processingFeedbackTask?.cancel()
            processingFeedbackTask = nil

            if wantsReview, let snapshot, let review {
                pendingReview = PendingReview(snapshot: snapshot, proposed: improved)
                feedback.hide()
                phase = .ready
                review.show(
                    original: selection,
                    proposed: improved,
                    anchor: activeSelectionBounds,
                    fallbackPoint: activeFallbackPoint,
                    onApply: { [weak self] in
                        self?.applyTask = Task { @MainActor [weak self] in
                            await self?.applyReview(runID: currentRun)
                        }
                    },
                    onCancel: { [weak self] restoreFocus in
                        self?.discardReview(restoreFocus: restoreFocus)
                    }
                )
                return
            }

            guard let snapshot, let selectionSnapshots else {
                guard runID == currentRun, !Task.isCancelled else { return }
                showRecovery(
                    freshText: improved,
                    report: .notSubmitted,
                    snapshot: snapshot,
                    runID: currentRun
                )
                return
            }
            let report = await selectionSnapshots.replaceSelection(snapshot, with: improved)
            guard runID == currentRun, !Task.isCancelled else { return }
            guard report.isSubmitted else {
                showRecovery(freshText: improved, report: report, snapshot: snapshot, runID: currentRun)
                return
            }
            try Task.checkCancellation()
            guard runID == currentRun else { return }
            show(.pasteSent, duration: 1.25)
        } catch is CancellationError {
            guard runID == currentRun else { return }
            processingFeedbackTask?.cancel()
            processingFeedbackTask = nil
            feedback.hide()
            phase = .ready
        } catch QwixitAPIError.quotaExceeded {
            guard runID == currentRun, !Task.isCancelled else { return }
            processingFeedbackTask?.cancel()
            processingFeedbackTask = nil
            show(.limitReached, duration: nil)
        } catch let error where QwixitAPI.isConnectivityError(error) {
            guard runID == currentRun, !Task.isCancelled else { return }
            processingFeedbackTask?.cancel()
            processingFeedbackTask = nil
            show(.offline, duration: nil)
        } catch {
            guard runID == currentRun, !Task.isCancelled else { return }
            processingFeedbackTask?.cancel()
            processingFeedbackTask = nil
            let message = (error as? LocalizedError)?.errorDescription
                ?? "Tokiri couldn’t improve the text. Your text is unchanged."
            show(.error(message), duration: 4)
        }
    }

    private func applyReview(runID currentRun: UUID) async {
        guard runID == currentRun, let pendingReview else { return }
        review?.hide()
        self.pendingReview = nil

        guard let selectionSnapshots else {
            guard runID == currentRun, !Task.isCancelled else { return }
            showRecovery(
                freshText: pendingReview.proposed,
                report: .notSubmitted,
                snapshot: pendingReview.snapshot,
                runID: currentRun
            )
            return
        }

        let report = await selectionSnapshots.replaceSelection(
            pendingReview.snapshot,
            with: pendingReview.proposed
        )
        guard runID == currentRun, !Task.isCancelled else { return }
        guard report.isSubmitted else {
            showRecovery(
                freshText: pendingReview.proposed,
                report: report,
                snapshot: pendingReview.snapshot,
                runID: currentRun
            )
            return
        }

        guard runID == currentRun, !Task.isCancelled else { return }
        show(.pasteSent, duration: 1.25)
    }

    private func discardReview(restoreFocus: Bool) {
        guard let pendingReview else { return }
        if restoreFocus { selectionSnapshots?.restoreFocus(pendingReview.snapshot) }
        self.pendingReview = nil
        show(.ready, duration: nil)
    }

    private func showRecovery(
        freshText: String,
        report: ReplacementAttemptReport,
        snapshot: TextSelectionSnapshot?,
        runID currentRun: UUID
    ) {
        feedback.hide()
        phase = .ready
        guard let recovery else {
            show(.error("Couldn’t send the paste. The fresh text is ready to copy."), duration: 4)
            return
        }
        recovery.show(
            freshText: freshText,
            report: report,
            anchor: activeSelectionBounds,
            fallbackPoint: activeFallbackPoint,
            onClose: { [weak self] in
                guard let self, self.runID == currentRun else { return }
                if let snapshot { self.selectionSnapshots?.restoreFocus(snapshot) }
            }
        )
    }

    private func show(_ newPhase: AppPhase, duration: Double?) {
        resetTask?.cancel()
        phase = newPhase
        let appPreferences = AppPreferences(defaults: preferences)
        let animationsEnabled = appPreferences.animationsEnabled
        let showSuccess = appPreferences.showSuccess

        if newPhase == .ready
            || ((newPhase == .success || newPhase == .pasteSent) && !showSuccess) {
            feedback.hide()
        } else {
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
