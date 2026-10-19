import XCTest
@testable import Tokiri

@MainActor
final class OnboardingViewModelTests: XCTestCase {
    func testStartsAtWelcomeAndAdvancesToAccess() {
        let model = makeModel()

        XCTAssertEqual(model.step, 0)
        XCTAssertEqual(model.phase, .idle)
        XCTAssertTrue(model.canContinue)

        model.advance()

        XCTAssertEqual(model.step, 1)
        XCTAssertTrue(model.canContinue)
    }

    func testAccessCanBeDeferredWithoutChangingStepState() {
        let accessibility = OnboardingAccessibilityStub()
        let model = makeModel(accessibility: accessibility)
        model.step = 1

        model.requestAccessibility()

        XCTAssertTrue(accessibility.didRequestPermission)
        XCTAssertTrue(model.isRequestingAccessibility)
        XCTAssertEqual(model.phase, .idle)
        XCTAssertTrue(model.canContinue)
    }

    func testGrantedAccessibilityAdvancesFromAccessStep() {
        let accessibility = OnboardingAccessibilityStub()
        let model = makeModel(accessibility: accessibility)
        model.step = 1

        model.requestAccessibility()
        accessibility.isTrusted = true
        model.refreshAccessibility()

        XCTAssertTrue(model.accessibilityGranted)
        XCTAssertFalse(model.isRequestingAccessibility)
        XCTAssertEqual(model.step, 2)
    }

    func testFixHotkeyStartsLocalProcessing() {
        let model = makeModel()
        model.step = 2

        model.handleMainHotkey()

        XCTAssertEqual(model.phase, .processing)
        XCTAssertEqual(model.originalText, "helo i thnik this sentnce sound wierd")
        XCTAssertTrue(model.hasRealInput)
    }

    func testActionsHotkeyOpensPalette() {
        let model = makeModel()
        model.step = 3

        model.handleActionHotkey()
        XCTAssertEqual(model.phase, .palette)
    }

    func testPaletteChoiceStartsReplacement() {
        let model = makeModel()
        model.step = 3
        model.handleActionHotkey()

        model.chooseAction(.polish)

        XCTAssertEqual(model.choice, .polish)
        XCTAssertEqual(model.phase, .processing)
    }

    func testCanGoBackThroughCompletedSteps() {
        let model = makeModel()
        model.step = 3
        model.handleActionHotkey()

        model.goBack()

        XCTAssertEqual(model.step, 2)
        XCTAssertEqual(model.phase, .idle)
    }

    func testSkipCompletesOnlyPracticeSteps() {
        let model = makeModel()
        model.step = 2

        model.skipPractice()

        XCTAssertEqual(model.phase, .done)
        XCTAssertTrue(model.canContinue)
    }

    private func makeModel(accessibility: OnboardingAccessibilityStub = OnboardingAccessibilityStub()) -> OnboardingModel {
        OnboardingModel(accessibility: accessibility)
    }
}

private final class OnboardingAccessibilityStub: AccessibilityServicing {
    var isTrusted = false
    private(set) var didRequestPermission = false
    func requestPermission() { didRequestPermission = true }
    func selectedText() async -> String? { nil }
    func selectionBounds() -> CGRect? { nil }
    func fallbackPoint() -> CGPoint { .zero }
}

@MainActor
final class SettingsBillingTests: XCTestCase {
    func testCheckoutPollSurvivesRefreshUntilSubscriptionBecomesActive() async throws {
        let suiteName = "SettingsBillingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let billing = BillingSequenceStub(statuses: [
            BillingStatus(plan: "free", subscriptionStatus: "none", remaining: 0, period: "2026-10"),
            BillingStatus(plan: "free", subscriptionStatus: "none", remaining: 0, period: "2026-10"),
            BillingStatus(plan: "advanced", subscriptionStatus: "active", remaining: nil, period: "2026-10"),
        ])
        let model = SettingsViewModel(
            accessibility: OnboardingAccessibilityStub(),
            checkout: SuccessfulCheckoutStub(),
            billingStatus: billing,
            billingPollInterval: .milliseconds(100),
            defaults: defaults
        )
        defer { model.stop() }

        model.openStarterCheckout()
        for _ in 0..<100 where await billing.fetchCount() == 0 {
            try await Task.sleep(for: .milliseconds(5))
        }
        model.refreshUsage()

        for _ in 0..<100 where !model.isAdvanced {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(model.isAdvanced)
        let fetchCount = await billing.fetchCount()
        XCTAssertEqual(fetchCount, 3)
    }
}

private struct SuccessfulCheckoutStub: CheckoutOpening {
    func openStarterCheckout() -> Bool { true }
}

private actor BillingSequenceStub: BillingStatusChecking {
    private let statuses: [BillingStatus]
    private var count = 0

    init(statuses: [BillingStatus]) {
        self.statuses = statuses
    }

    func fetchStatus() async throws -> BillingStatus {
        count += 1
        return statuses[min(count - 1, statuses.count - 1)]
    }

    func fetchCount() -> Int { count }
}

final class QwixitUsageTests: XCTestCase {
    func testOlderResponseCannotMoveUsageCountBackwardsWithinSamePeriod() throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        QwixitUsage.record(try response(remaining: 10, period: "2026-10"), defaults: defaults)
        QwixitUsage.record(try response(remaining: 16, period: "2026-10"), defaults: defaults)

        XCTAssertEqual(AppPreferences(defaults: defaults).remainingActions, 10)
    }

    func testNewPeriodCanResetRemainingActions() throws {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        QwixitUsage.record(try response(remaining: 2, period: "2026-09"), defaults: defaults)
        QwixitUsage.record(try response(remaining: 29, period: "2026-10"), defaults: defaults)

        XCTAssertEqual(AppPreferences(defaults: defaults).remainingActions, 29)
    }

    private var defaultsSuiteName: String { "QwixitUsageTests" }

    private func makeDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        return defaults
    }

    private func response(remaining: Int, period: String) throws -> HTTPURLResponse {
        try XCTUnwrap(HTTPURLResponse(
            url: URL(string: "https://qwixit.test/v1/responses")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: [
                "X-Qwixit-Plan": "free",
                "X-Qwixit-Remaining": String(remaining),
                "X-Qwixit-Period": period,
            ]
        ))
    }
}
