import XCTest
@testable import Qwixit

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

    func testChooseRequiresTwoTapsAndOpensPalette() {
        let model = makeModel()
        model.step = 3

        model.handleMainHotkey()
        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(model.tapCount, 1)

        model.handleMainHotkey()
        XCTAssertEqual(model.phase, .palette)
    }

    func testPaletteChoiceStartsReplacement() {
        let model = makeModel()
        model.step = 3
        model.handleMainHotkey()
        model.handleMainHotkey()

        model.chooseAction(.polish)

        XCTAssertEqual(model.choice, .polish)
        XCTAssertEqual(model.phase, .processing)
    }

    func testCanGoBackThroughCompletedSteps() {
        let model = makeModel()
        model.step = 3
        model.handleMainHotkey()

        model.goBack()

        XCTAssertEqual(model.step, 2)
        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(model.tapCount, 0)
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
    func replaceSelection(_ originalText: String, with replacement: String) async -> Bool { true }
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
