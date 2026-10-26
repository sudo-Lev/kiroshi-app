import XCTest
@testable import HotkeyGo

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
        let service = "hotkeygo service error 503: unavailable"

        XCTAssertEqual(HotkeyGoErrorCopy.headline(for: replacement), "NOT REPLACED")
        XCTAssertEqual(HotkeyGoErrorCopy.headline(for: uncertain), "CHECK THE TEXT")
        XCTAssertEqual(HotkeyGoErrorCopy.title(for: uncertain), "Couldn’t confirm the change")
        XCTAssertEqual(HotkeyGoErrorCopy.headline(for: service), "SERVICE ERROR")
        XCTAssertNotEqual(HotkeyGoErrorCopy.headline(for: service), "FAILED")
    }

    func testErrorCopyNamesIncompleteResponsesAndKeepsDetail() {
        let message = "The AI service did not finish the result. Your text is unchanged."

        XCTAssertEqual(HotkeyGoErrorCopy.headline(for: message), "INCOMPLETE REPLY")
        XCTAssertEqual(HotkeyGoErrorCopy.detail(for: message), message)
    }

    func testErrorDetailIsSingleLineAndBounded() {
        let message = String(repeating: "provider detail\n", count: 40)

        XCTAssertFalse(HotkeyGoErrorCopy.detail(for: message).contains("\n"))
        XCTAssertLessThanOrEqual(HotkeyGoErrorCopy.detail(for: message).count, 180)
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

    func testNetworkRetrySendsOneOperationIDOnEveryAttempt() async throws {
        var ids: [String?] = []
        var delays: [Duration] = []

        _ = try await NetworkRetry.perform(
            operation: {
                ids.append(HotkeyGoOperation.id)
                if ids.count < 3 { throw URLError(.timedOut) }
                return "done"
            },
            sleep: { delays.append($0) }
        )

        XCTAssertEqual(ids.count, 3)
        XCTAssertNotNil(ids[0])
        XCTAssertEqual(Set(ids).count, 1)
        XCTAssertEqual(delays, [.seconds(1), .seconds(2)])
        XCTAssertNil(HotkeyGoOperation.id)
    }

    func testSeparateActionsGetSeparateOperationIDs() async throws {
        let first = try await NetworkRetry.perform(operation: { HotkeyGoOperation.id }, sleep: { _ in })
        let second = try await NetworkRetry.perform(operation: { HotkeyGoOperation.id }, sleep: { _ in })
        XCTAssertNotEqual(first, second)
    }

    func testNonRecoverableErrorsAreNotRetried() async {
        let errors: [Error] = [
            HotkeyGoAPIError.incompleteOutput,
            HotkeyGoAPIError.emptyOutput,
            HotkeyGoAPIError.quotaExceeded(checkoutURL: nil),
            HotkeyGoAPIError.operationExhausted,
            HotkeyGoAPIError.api(status: 400, message: "bad"),
            HotkeyGoAPIError.api(status: 413, message: "too long"),
            HotkeyGoAPIError.api(status: 422, message: "rejected")
        ]
        for error in errors {
            var attempts = 0
            _ = try? await NetworkRetry.perform(
                operation: { () async throws -> String in
                    attempts += 1
                    throw error
                },
                sleep: { _ in }
            )
            XCTAssertEqual(attempts, 1, "\(error)")
        }
    }

    func testRateLimitWaitsForRetryAfter() async throws {
        var attempts = 0
        var delays: [Duration] = []

        _ = try await NetworkRetry.perform(
            operation: {
                attempts += 1
                if attempts == 1 { throw HotkeyGoAPIError.rateLimited(retryAfter: .seconds(4)) }
                return "done"
            },
            sleep: { delays.append($0) }
        )

        XCTAssertEqual(delays, [.seconds(4)])
        XCTAssertFalse(HotkeyGoAPI.isRetryableError(HotkeyGoAPIError.rateLimited(retryAfter: .seconds(60))))
    }

    func testCleanFixLeavesTextAndClipboardAloneEvenInReviewMode() async {
        for reviewFirst in [false, true] {
            let suite = "\(#function)-\(reviewFirst)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(reviewFirst, forKey: AppPreferenceKey.reviewBeforeApplying)

            let selection = SelectionSnapshotSpy()
            let review = ReviewPresentingSpy()
            let feedback = FeedbackPresentingSpy()
            let viewModel = QuickImproveViewModel(
                accessibility: ReviewAccessibilityStub(),
                improver: FixedImprover(output: nil),
                feedback: feedback,
                review: review,
                selectionSnapshots: selection,
                preferences: defaults
            )

            viewModel.improveSelection()
            for _ in 0..<40 where viewModel.phase != .alreadyClean { await Task.yield() }

            XCTAssertEqual(viewModel.phase, .alreadyClean)
            XCTAssertEqual(feedback.phases.last, .alreadyClean)
            XCTAssertFalse(review.didShow)
            XCTAssertEqual(selection.replaceCalls, 0)
            viewModel.stop()
        }
    }

    func testTooLongSelectionIsRejectedBeforeAnyRequest() async {
        let suite = #function
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let selection = SelectionSnapshotSpy()
        selection.snapshot = TextSelectionSnapshot(text: String(repeating: "x", count: HotkeyGoAPI.maxTextUTF16Units + 1))
        let improver = FixedImprover(output: "fixed")
        let viewModel = QuickImproveViewModel(
            accessibility: ReviewAccessibilityStub(),
            improver: improver,
            feedback: FeedbackPresentingSpy(),
            selectionSnapshots: selection,
            preferences: defaults
        )

        viewModel.improveSelection()
        for _ in 0..<40 where viewModel.phase == .ready { await Task.yield() }

        XCTAssertEqual(improver.calls, 0)
        XCTAssertEqual(selection.replaceCalls, 0)
        guard case .error(let message) = viewModel.phase else { return XCTFail("Expected an error chip") }
        XCTAssertEqual(HotkeyGoErrorCopy.headline(for: message), "TOO LONG")
        viewModel.stop()
    }

    func testFixRequestBodyCarriesOnlyTheTaskAndText() throws {
        let data = try JSONEncoder().encode(HotkeyGoTask(task: "fix", text: "helo"))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: data) as? [String: String], ["task": "fix", "text": "helo"])

        let claudeFix = try JSONEncoder().encode(HotkeyGoTask(task: "fix", text: "helo", provider: "anthropic"))
        XCTAssertEqual(
            try JSONSerialization.jsonObject(with: claudeFix) as? [String: String],
            ["task": "fix", "text": "helo", "provider": "anthropic"]
        )

        let action = try JSONEncoder().encode(HotkeyGoTask(task: "action", text: "hi", action: "translate", language: "pl"))
        XCTAssertEqual(
            try JSONSerialization.jsonObject(with: action) as? [String: String],
            ["task": "action", "text": "hi", "action": "translate", "language": "pl"]
        )

        let claudeAction = try JSONEncoder().encode(HotkeyGoTask(
            task: "action", text: "hi", provider: "anthropic", action: "translate", language: "pl"
        ))
        XCTAssertEqual(
            try JSONSerialization.jsonObject(with: claudeAction) as? [String: String],
            ["task": "action", "text": "hi", "provider": "anthropic", "action": "translate", "language": "pl"]
        )
    }

    func testOnlyTheAdvancedPlanValueMeansAdvanced() {
        XCTAssertTrue(HotkeyGoUsage.isAdvancedPlan("advanced"))
        XCTAssertFalse(HotkeyGoUsage.isAdvancedPlan("unlimited"))
        XCTAssertFalse(HotkeyGoUsage.isAdvancedPlan("free"))
        XCTAssertFalse(HotkeyGoUsage.isAdvancedPlan(nil))
    }

    func testResponseErrorMapsWorkerCodes() throws {
        let url = HotkeyGoAPI.endpoint
        func error(_ status: Int, _ code: String) throws -> HotkeyGoAPIError {
            let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
            return HotkeyGoAPI.responseError(response, data: Data(#"{"error":{"message":"m","code":"\#(code)"}}"#.utf8))
        }
        guard case .textTooLong = try error(413, "text_too_long") else { return XCTFail("413") }
        guard case .outputRejected = try error(422, "output_rejected") else { return XCTFail("422") }
        guard case .dailyLimit = try error(429, "daily_limit") else { return XCTFail("daily") }
        guard case .monthlyLimit = try error(429, "monthly_limit") else { return XCTFail("monthly") }
        guard case .rateLimited = try error(429, "rate_limited") else { return XCTFail("rate") }
        XCTAssertFalse(HotkeyGoAPI.isRetryableError(HotkeyGoAPIError.dailyLimit))
        XCTAssertFalse(HotkeyGoAPI.isRetryableError(HotkeyGoAPIError.outputRejected))
    }

    func testResponseErrorMapsRateLimitAndExhaustedOperation() throws {
        let url = HotkeyGoAPI.endpoint
        let limited = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "3"]))
        guard case .rateLimited(let retryAfter) = HotkeyGoAPI.responseError(limited, data: Data()) else {
            return XCTFail("Expected rate limit")
        }
        XCTAssertEqual(retryAfter, .seconds(3))

        let exhausted = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 409, httpVersion: nil, headerFields: nil))
        let body = Data(#"{"error":{"message":"no","code":"operation_exhausted"}}"#.utf8)
        guard case .operationExhausted = HotkeyGoAPI.responseError(exhausted, data: body) else {
            return XCTFail("Expected exhausted operation")
        }
    }
}

private final class FixedImprover: TextImproving {
    /// `nil` makes the Worker answer "clean".
    let output: String?
    private(set) var calls = 0

    init(output: String?) { self.output = output }

    func improve(_ text: String) async throws -> FixOutcome {
        calls += 1
        return output.map(FixOutcome.fixed) ?? .clean
    }
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
