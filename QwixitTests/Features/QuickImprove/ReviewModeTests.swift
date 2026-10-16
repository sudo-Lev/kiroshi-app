import XCTest
@testable import Tokiri

@MainActor
final class ReviewModeTests: XCTestCase {
    func testReviewModeWaitsForApplyBeforeReplacing() async {
        let suite = #function
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: AppPreferenceKey.reviewBeforeApplying)

        let selection = SelectionSnapshotSpy()
        let review = ReviewPresentingSpy()
        let viewModel = QuickImproveViewModel(
            accessibility: ReviewAccessibilityStub(),
            improver: FixedImprover(output: "fixed text"),
            feedback: FeedbackPresentingSpy(),
            review: review,
            selectionSnapshots: selection,
            preferences: defaults
        )

        viewModel.improveSelection()
        for _ in 0..<20 where !review.didShow { await Task.yield() }

        XCTAssertTrue(review.didShow)
        XCTAssertEqual(review.proposed, "fixed text")
        XCTAssertEqual(selection.replaceCalls, 0)

        review.apply()
        for _ in 0..<20 where selection.replaceCalls == 0 { await Task.yield() }

        XCTAssertEqual(selection.replaceCalls, 1)
        viewModel.stop()
    }

    func testReviewDoesNotFallBackToImmediateReplacementWhenSnapshotIsUnavailable() async {
        let suite = #function
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: AppPreferenceKey.reviewBeforeApplying)

        let accessibility = ReviewAccessibilityStub()
        let selection = SelectionSnapshotSpy()
        selection.snapshot = nil
        let review = ReviewPresentingSpy()
        let viewModel = QuickImproveViewModel(
            accessibility: accessibility,
            improver: FixedImprover(output: "fixed text"),
            feedback: FeedbackPresentingSpy(),
            review: review,
            selectionSnapshots: selection,
            preferences: defaults
        )

        viewModel.improveSelection()
        for _ in 0..<20 where viewModel.phase == .ready { await Task.yield() }

        XCTAssertEqual(selection.replaceCalls, 0)
        XCTAssertFalse(review.didShow)
        if case .error = viewModel.phase {} else { XCTFail("Expected a recoverable Review error") }
        viewModel.stop()
    }

    func testReviewApplyIsOneShot() async {
        let suite = #function
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: AppPreferenceKey.reviewBeforeApplying)

        let selection = SelectionSnapshotSpy()
        let review = ReviewPresentingSpy()
        let viewModel = QuickImproveViewModel(
            accessibility: ReviewAccessibilityStub(),
            improver: FixedImprover(output: "fixed text"),
            feedback: FeedbackPresentingSpy(),
            review: review,
            selectionSnapshots: selection,
            preferences: defaults
        )
        viewModel.improveSelection()
        for _ in 0..<20 where !review.didShow { await Task.yield() }
        review.apply()
        review.apply()
        for _ in 0..<20 where selection.replaceCalls == 0 { await Task.yield() }
        XCTAssertEqual(selection.replaceCalls, 1)
        viewModel.stop()
    }

    func testPasteEventFailureOpensRecoveryInsteadOfShowingSubmittedStatus() async {
        let suite = #function
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: AppPreferenceKey.reviewBeforeApplying)

        let selection = SelectionSnapshotSpy()
        selection.replaceResult = false
        let review = ReviewPresentingSpy()
        let feedback = FeedbackPresentingSpy()
        let recovery = ReplacementRecoverySpy()
        let viewModel = QuickImproveViewModel(
            accessibility: ReviewAccessibilityStub(),
            improver: FixedImprover(output: "fixed text"),
            feedback: feedback,
            recovery: recovery,
            review: review,
            selectionSnapshots: selection,
            preferences: defaults
        )

        viewModel.improveSelection()
        for _ in 0..<20 where !review.didShow { await Task.yield() }
        review.apply()
        for _ in 0..<20 where !recovery.didShow { await Task.yield() }

        XCTAssertEqual(selection.replaceCalls, 1)
        XCTAssertTrue(recovery.didShow)
        XCTAssertEqual(recovery.freshText, "fixed text")
        XCTAssertEqual(recovery.report, .pasteFailed)
        XCTAssertFalse(feedback.phases.contains(.pasteSent))
        viewModel.stop()
    }

    func testUnsentAutomaticReplacementKeepsFreshTextForManualCopy() async {
        let defaults = UserDefaults(suiteName: #function)!
        defer { defaults.removePersistentDomain(forName: #function) }
        let selection = SelectionSnapshotSpy()
        selection.replaceResult = false
        let recovery = ReplacementRecoverySpy()
        let feedback = FeedbackPresentingSpy()
        let viewModel = QuickImproveViewModel(
            accessibility: ReviewAccessibilityStub(),
            improver: FixedImprover(output: "fresh correction"),
            feedback: feedback,
            recovery: recovery,
            selectionSnapshots: selection,
            preferences: defaults
        )

        viewModel.improveSelection()
        for _ in 0..<50 where !recovery.didShow { await Task.yield() }

        XCTAssertTrue(recovery.didShow)
        XCTAssertEqual(recovery.freshText, "fresh correction")
        XCTAssertEqual(recovery.report, .pasteFailed)
        XCTAssertFalse(feedback.phases.contains(.pasteSent))
        viewModel.stop()
    }

    func testMissingSelectionSnapshotDoesNotAttemptInsertionAndOffersRecovery() async {
        let defaults = UserDefaults(suiteName: #function)!
        defer { defaults.removePersistentDomain(forName: #function) }
        let selection = SelectionSnapshotSpy()
        selection.snapshot = nil
        let recovery = ReplacementRecoverySpy()
        let feedback = FeedbackPresentingSpy()
        let viewModel = QuickImproveViewModel(
            accessibility: ReviewAccessibilityStub(),
            improver: FixedImprover(output: "fresh correction"),
            feedback: feedback,
            recovery: recovery,
            selectionSnapshots: selection,
            preferences: defaults
        )

        viewModel.improveSelection()
        for _ in 0..<50 where !recovery.didShow { await Task.yield() }

        XCTAssertEqual(selection.replaceCalls, 0)
        XCTAssertTrue(recovery.didShow)
        XCTAssertEqual(recovery.report, .notSubmitted)
        XCTAssertFalse(feedback.phases.contains(.pasteSent))
        viewModel.stop()
    }

    func testEarlierFailedReplacementCannotOverwriteLaterSuccess() async {
        let defaults = UserDefaults(suiteName: #function)!
        defer { defaults.removePersistentDomain(forName: #function) }
        let selection = DeferredSelectionSnapshotSpy()
        let viewModel = QuickImproveViewModel(
            accessibility: ReviewAccessibilityStub(),
            improver: FixedImprover(output: "fixed text"),
            feedback: FeedbackPresentingSpy(),
            selectionSnapshots: selection,
            preferences: defaults
        )

        viewModel.improveSelection()
        for _ in 0..<50 where selection.firstContinuation == nil { await Task.yield() }
        guard selection.firstContinuation != nil else {
            viewModel.stop()
            return XCTFail("First replacement did not start")
        }

        viewModel.improveSelection()
        for _ in 0..<50 where viewModel.phase != .pasteSent { await Task.yield() }
        XCTAssertEqual(selection.replaceCalls, 2)
        XCTAssertEqual(viewModel.phase, .pasteSent)

        selection.failFirstReplacement()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(viewModel.phase, .pasteSent)
        viewModel.stop()
    }

    func testUnchangedTextProducesOneSameChunk() {
        XCTAssertEqual(
            ReviewDiffEngine.chunks(original: "same text", proposed: "same text"),
            [ReviewDiffChunk(kind: .same, text: "same text")]
        )
    }

    func testChangedTextContainsAddedAndRemovedSegments() {
        let chunks = ReviewDiffEngine.chunks(
            original: "helo team",
            proposed: "hello team"
        )

        XCTAssertTrue(chunks.contains { $0.kind == .added && $0.text.contains("hello") })
        XCTAssertTrue(chunks.contains { $0.kind == .removed && $0.text.contains("helo") })
        XCTAssertTrue(chunks.contains { $0.kind == .same && $0.text.contains("team") })
    }

    func testLongReviewFallsBackWithoutQuadraticDiff() {
        let original = String(repeating: "old ", count: 700)
        let proposed = String(repeating: "new ", count: 700)
        XCTAssertEqual(ReviewDiffEngine.chunks(original: original, proposed: proposed), [
            ReviewDiffChunk(kind: .removed, text: original),
            ReviewDiffChunk(kind: .added, text: proposed)
        ])
    }

    func testReviewPreferenceDefaultsOffAndPersists() {
        let suite = #function
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertFalse(AppPreferences(defaults: defaults).reviewBeforeApplying)

        defaults.set(true, forKey: AppPreferenceKey.reviewBeforeApplying)

        XCTAssertTrue(AppPreferences(defaults: defaults).reviewBeforeApplying)
    }

    func testErrorCopySeparatesReplacementFromServiceFailures() {
        let replacement = "The active app did not allow replacement. Your text is unchanged."
        let uncertain = "Couldn’t confirm replacement. Check the text before trying again."
        let service = "Tokiri service error 503: unavailable"

        XCTAssertEqual(QwixitErrorCopy.headline(for: replacement), "NOT REPLACED")
        XCTAssertEqual(QwixitErrorCopy.headline(for: uncertain), "CHECK THE TEXT")
        XCTAssertEqual(QwixitErrorCopy.title(for: uncertain), "Couldn’t confirm the change")
        XCTAssertEqual(QwixitErrorCopy.headline(for: service), "SERVICE ERROR")
        XCTAssertNotEqual(QwixitErrorCopy.headline(for: service), "FAILED")
    }

    func testErrorCopyNamesIncompleteResponsesAndKeepsDetail() {
        let message = "The AI service did not finish the result. Your text is unchanged."

        XCTAssertEqual(QwixitErrorCopy.headline(for: message), "INCOMPLETE REPLY")
        XCTAssertEqual(QwixitErrorCopy.detail(for: message), message)
    }

    func testErrorDetailIsSingleLineAndBounded() {
        let message = String(repeating: "provider detail\n", count: 40)

        XCTAssertFalse(QwixitErrorCopy.detail(for: message).contains("\n"))
        XCTAssertLessThanOrEqual(QwixitErrorCopy.detail(for: message).count, 180)
    }

    func testResponseTextPreservesLeadingAndTrailingFormatting() throws {
        let data = Data(#"{"output":[{"type":"message","content":[{"type":"output_text","text":"  fixed\n"}]}]}"#.utf8)
        XCTAssertEqual(try ResponseText.output(from: data), "  fixed\n")
    }

    func testIncompleteResponseCannotReplaceSelectedText() {
        let data = Data(#"{"status":"incomplete","output":[{"type":"message","content":[{"type":"output_text","text":"partial"}]}]}"#.utf8)
        XCTAssertThrowsError(try ResponseText.output(from: data)) { error in
            guard case QwixitAPIError.incompleteOutput = error else {
                return XCTFail("Expected incomplete output error")
            }
        }
    }

    func testNetworkRetrySucceedsOnTheThirdAttempt() async throws {
        var attempts = 0
        var retryAttempts: [Int] = []

        let result = try await NetworkRetry.perform(
            operation: {
                attempts += 1
                if attempts < 3 { throw URLError(.timedOut) }
                return "connected"
            },
            onRetry: { attempt, total in
                XCTAssertEqual(total, 3)
                retryAttempts.append(attempt)
            },
            sleep: { _ in }
        )

        XCTAssertEqual(result, "connected")
        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(retryAttempts, [2, 3])
    }

    func testNetworkRetryStopsAfterThreeAttempts() async {
        var attempts = 0

        do {
            _ = try await NetworkRetry.perform(
                operation: {
                    attempts += 1
                    throw URLError(.networkConnectionLost)
                },
                sleep: { _ in }
            ) as String
            XCTFail("Expected the final connectivity error")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .networkConnectionLost)
        } catch {
            XCTFail("Expected URLError, got \(error)")
        }

        XCTAssertEqual(attempts, 3)
    }
}

private final class FixedImprover: TextImproving {
    let output: String

    init(output: String) { self.output = output }

    func improve(_ text: String, instruction: String?) async throws -> String { output }
}

private final class ReviewAccessibilityStub: AccessibilityServicing {
    var isTrusted = true
    func requestPermission() {}
    func selectedText() async -> String? { "original" }
    func selectionBounds() -> CGRect? { nil }
    func fallbackPoint() -> CGPoint { .zero }
}

private final class SelectionSnapshotSpy: SelectionSnapshotProviding {
    var snapshot: TextSelectionSnapshot? = TextSelectionSnapshot(text: "original")
    var replaceResult = true
    private(set) var replaceCalls = 0

    func captureSelection() async -> TextSelectionSnapshot? { snapshot }
    func replaceSelection(_ snapshot: TextSelectionSnapshot, with replacement: String) async -> ReplacementAttemptReport {
        replaceCalls += 1
        return replaceResult ? .submitted : .pasteFailed
    }
    func restoreFocus(_ snapshot: TextSelectionSnapshot) {}
}

private final class DeferredSelectionSnapshotSpy: SelectionSnapshotProviding {
    private(set) var replaceCalls = 0
    private(set) var firstContinuation: CheckedContinuation<ReplacementAttemptReport, Never>?

    func captureSelection() async -> TextSelectionSnapshot? {
        TextSelectionSnapshot(text: "original")
    }

    func replaceSelection(_ snapshot: TextSelectionSnapshot, with replacement: String) async -> ReplacementAttemptReport {
        replaceCalls += 1
        if replaceCalls == 1 {
            return await withCheckedContinuation { firstContinuation = $0 }
        }
        return .submitted
    }

    func restoreFocus(_ snapshot: TextSelectionSnapshot) {}

    func failFirstReplacement() {
        firstContinuation?.resume(returning: .pasteFailed)
        firstContinuation = nil
    }
}

@MainActor
private final class ReviewPresentingSpy: ReviewPresenting {
    private(set) var didShow = false
    private(set) var proposed = ""
    private var applyAction: (() -> Void)?
    private var cancelAction: ((Bool) -> Void)?

    func show(
        original: String,
        proposed: String,
        anchor accessibilityBounds: CGRect?,
        fallbackPoint: CGPoint?,
        onApply: @escaping () -> Void,
        onCancel: @escaping (Bool) -> Void
    ) {
        didShow = true
        self.proposed = proposed
        applyAction = onApply
        cancelAction = onCancel
    }

    func hide() {}
    func apply() { applyAction?() }
    func cancel() { cancelAction?(true) }
}

@MainActor
private final class FeedbackPresentingSpy: FeedbackPresenting {
    private(set) var phases: [AppPhase] = []
    func show(phase: AppPhase, reduceMotion: Bool, anchor accessibilityBounds: CGRect?, fallbackPoint: CGPoint?) {
        phases.append(phase)
    }
    func hide() {}
}

@MainActor
private final class ReplacementRecoverySpy: ReplacementRecoveryPresenting {
    private(set) var didShow = false
    private(set) var freshText = ""
    private(set) var report = ReplacementAttemptReport.notSubmitted

    func show(
        freshText: String,
        report: ReplacementAttemptReport,
        anchor accessibilityBounds: CGRect?,
        fallbackPoint: CGPoint?,
        onClose: @escaping () -> Void
    ) {
        didShow = true
        self.freshText = freshText
        self.report = report
    }

    func hide() { didShow = false }
}
