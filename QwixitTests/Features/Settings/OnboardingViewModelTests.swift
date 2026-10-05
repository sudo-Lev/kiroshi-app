import XCTest
@testable import Qwixit

@MainActor
final class OnboardingViewModelTests: XCTestCase {
    func testAccessibilityComesBeforePractice() {
        let viewModel = makeViewModel()

        viewModel.handleOnboardingHotkey()

        XCTAssertEqual(viewModel.onboardingStep, 0)
        XCTAssertEqual(viewModel.onboardingDemoPhase, .waiting)
    }

    func testFirstShortcutStartsLocalProcessingAfterPermissionStep() {
        let viewModel = makeViewModel()
        viewModel.onboardingStep = 1

        viewModel.handleOnboardingHotkey()

        XCTAssertEqual(viewModel.onboardingDemoPhase, .processing)
        XCTAssertEqual(viewModel.onboardingOriginalText, "helo i thnik this sentnce sound wierd")
    }

    func testPermissionMustBeGrantedBeforeAdvancing() {
        let viewModel = makeViewModel()
        viewModel.advanceOnboarding()
        XCTAssertEqual(viewModel.onboardingStep, 0)

        let accessibility = OnboardingAccessibilityStub()
        accessibility.isTrusted = true
        let trustedViewModel = makeViewModel(accessibility: accessibility)
        trustedViewModel.refreshAccessibility()
        trustedViewModel.advanceOnboarding()
        XCTAssertEqual(trustedViewModel.onboardingStep, 1)
    }

    func testPaletteLevelRequiresTwoTapsAndOpensMenu() async {
        let viewModel = makeViewModel()
        viewModel.onboardingStep = 2

        viewModel.handleOnboardingHotkey()
        XCTAssertEqual(viewModel.onboardingLevel2TapCount, 1)
        XCTAssertFalse(viewModel.onboardingMenuVisible)

        viewModel.handleOnboardingHotkey()
        try? await Task.sleep(for: .milliseconds(160))
        XCTAssertTrue(viewModel.onboardingMenuVisible)
    }

    func testPaletteActionCanBeChosenFromKeyboardSelection() async {
        let viewModel = makeViewModel()
        viewModel.onboardingStep = 2
        viewModel.handleOnboardingHotkey()
        viewModel.handleOnboardingHotkey()
        try? await Task.sleep(for: .milliseconds(160))
        viewModel.chooseOnboardingAction(.polish)

        XCTAssertEqual(viewModel.onboardingDemoPhase, .processing)
        XCTAssertFalse(viewModel.onboardingMenuVisible)
    }

    private func makeViewModel(accessibility: OnboardingAccessibilityStub = OnboardingAccessibilityStub()) -> SettingsViewModel {
        let suiteName = "OnboardingViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return SettingsViewModel(
            accessibility: accessibility,
            checkout: OnboardingCheckoutStub(),
            billingStatus: OnboardingBillingStub(),
            defaults: defaults
        )
    }
}

private final class OnboardingAccessibilityStub: AccessibilityServicing {
    var isTrusted = false
    func requestPermission() {}
    func selectedText() async -> String? { nil }
    func selectionBounds() -> CGRect? { nil }
    func fallbackPoint() -> CGPoint { .zero }
    func replaceSelection(_ originalText: String, with replacement: String) async -> Bool { true }
}

private struct OnboardingCheckoutStub: CheckoutOpening {
    func openStarterCheckout() -> Bool { false }
}

private struct OnboardingBillingStub: BillingStatusChecking {
    func fetchStatus() async throws -> BillingStatus {
        BillingStatus(plan: "free", subscriptionStatus: "inactive", remaining: 30)
    }
}
