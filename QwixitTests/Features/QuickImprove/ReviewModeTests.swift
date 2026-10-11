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
        let service = "Tokiri service error 503: unavailable"

        XCTAssertEqual(QwixitErrorCopy.headline(for: replacement), "NOT REPLACED")
        XCTAssertEqual(QwixitErrorCopy.headline(for: service), "SERVICE ERROR")
        XCTAssertNotEqual(QwixitErrorCopy.headline(for: service), "FAILED")
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
    func replaceSelection(_ originalText: String, with replacement: String) async -> Bool { true }
}

private final class SelectionSnapshotSpy: SelectionSnapshotProviding {
    let snapshot = TextSelectionSnapshot(text: "original")
    private(set) var replaceCalls = 0

    func captureSelection() async -> TextSelectionSnapshot? { snapshot }
    func replaceSelection(_ snapshot: TextSelectionSnapshot, with replacement: String) async -> Bool {
        replaceCalls += 1
        return true
    }
    func restoreFocus(_ snapshot: TextSelectionSnapshot) {}
}

@MainActor
private final class ReviewPresentingSpy: ReviewPresenting {
    private(set) var didShow = false
    private(set) var proposed = ""
    private var applyAction: (() -> Void)?
    private var cancelAction: (() -> Void)?

    func show(
        original: String,
        proposed: String,
        anchor accessibilityBounds: CGRect?,
        fallbackPoint: CGPoint?,
        onApply: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        didShow = true
        self.proposed = proposed
        applyAction = onApply
        cancelAction = onCancel
    }

    func hide() {}
    func apply() { applyAction?() }
    func cancel() { cancelAction?() }
}

@MainActor
private final class FeedbackPresentingSpy: FeedbackPresenting {
    func show(phase: AppPhase, reduceMotion: Bool, anchor accessibilityBounds: CGRect?, fallbackPoint: CGPoint?) {}
    func hide() {}
}
