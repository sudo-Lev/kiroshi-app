import AppKit
import XCTest
@testable import HotkeyGo

@MainActor
final class OnboardingViewModelTests: XCTestCase {
    func testStartsAtWelcomeAndAdvancesToAccess() {
        let model = makeModel()

        XCTAssertEqual(model.step, .welcome)
        XCTAssertEqual(model.phase, .idle)
        XCTAssertTrue(model.canContinue)

        model.advance()

        XCTAssertEqual(model.step, .accessibility)
        XCTAssertTrue(model.canContinue)
    }

    func testAccessCanBeDeferredWithoutChangingStepState() {
        let accessibility = OnboardingAccessibilityStub()
        let model = makeModel(step: .accessibility, accessibility: accessibility)

        model.requestAccessibility()

        XCTAssertTrue(accessibility.didRequestPermission)
        XCTAssertTrue(model.isRequestingAccessibility)
        XCTAssertEqual(model.phase, .idle)
        XCTAssertTrue(model.canContinue)
    }

    func testGrantedAccessibilityWaitsForExplicitContinue() {
        let accessibility = OnboardingAccessibilityStub()
        let model = makeModel(step: .accessibility, accessibility: accessibility)

        model.requestAccessibility()
        accessibility.isTrusted = true
        model.refreshAccessibility()

        XCTAssertTrue(model.accessibilityGranted)
        XCTAssertFalse(model.isRequestingAccessibility)
        XCTAssertTrue(model.canContinue)
        XCTAssertEqual(model.step, .accessibility)

        model.advance()
        XCTAssertEqual(model.step, .fix)
    }

    func testAlreadyGrantedAccessibilityDoesNotSkipAccessStep() {
        let accessibility = OnboardingAccessibilityStub()
        accessibility.isTrusted = true
        let model = OnboardingViewModel(accessibility: accessibility, initialStep: .accessibility)

        model.refreshAccessibility()

        XCTAssertTrue(model.accessibilityGranted)
        XCTAssertEqual(model.step, .accessibility)
        XCTAssertTrue(model.canContinue)
    }

    func testFixHotkeyStartsLocalProcessing() {
        let model = makeModel(step: .fix)

        model.handleMainHotkey()

        XCTAssertEqual(model.phase, .processing)
        XCTAssertEqual(model.originalText, "helo i thnik this sentnce sound wierd")
        XCTAssertTrue(model.hasRealInput)
    }

    func testActionsHotkeyOpensPalette() {
        let model = makeModel(step: .actions)

        model.handleActionHotkey()
        XCTAssertEqual(model.phase, .palette)
    }

    func testPaletteChoiceStartsReplacement() {
        let model = makeModel(step: .actions)
        model.handleActionHotkey()

        model.chooseAction(.polish)

        XCTAssertEqual(model.phase, .processing)
    }

    func testActionsNumberKeysMatchTheFourVisibleChoices() {
        let model = makeModel(step: .actions)
        model.handleActionHotkey()

        XCTAssertEqual(model.actionChoices.map(\.title), ["Ukrainian", "Polish", "Slack style", "Make formal"])
        model.chooseNumber(3)

        XCTAssertEqual(model.phase, .processing)
    }

    func testActionSearchKeepsNumberEntryAndReturnSelectionInSync() {
        let model = makeModel(step: .actions)
        model.handleActionHotkey()
        model.actionQuery = "formal"

        XCTAssertEqual(model.actionChoices.map(\.title), ["Make formal"])
        XCTAssertFalse(model.chooseNumber(1))
        model.confirmSelection()

        XCTAssertEqual(model.phase, .processing)
    }

    func testPeekHotkeyOpensLanguageChooserAndEscapeClosesIt() async throws {
        let model = makeModel(step: .peek)
        let originalText = model.originalText

        model.handlePeekHotkey()

        XCTAssertEqual(model.phase, .peekChoice)
        XCTAssertEqual(model.peekChoices.map(\.name), ["Українська", "Polski", "Français", "English"])
        XCTAssertFalse(model.canContinue)
        XCTAssertEqual(model.originalText, originalText)
        XCTAssertTrue(model.escapeOverlay())
        XCTAssertEqual(model.phase, .idle)
        XCTAssertFalse(model.canContinue)

        try await Task.sleep(for: .milliseconds(1_000))
        XCTAssertEqual(model.phase, .idle)
    }

    func testPeekPracticeShortcutIsConsumedAndOpensLanguageChooser() throws {
        let model = makeModel(step: .peek)
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.option, .command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "z",
            charactersIgnoringModifiers: "z",
            isARepeat: false,
            keyCode: 0x06
        ))

        XCTAssertTrue(OnboardingHotkeyRouter.routePracticeShortcut(
            event,
            viewModel: model,
            fix: .defaultMain,
            actions: .actions,
            peek: .peek
        ))
        XCTAssertEqual(model.phase, .peekChoice)
        XCTAssertFalse(model.canContinue)
    }

    func testPeekChooserSelectionShowsProcessingThenTranslation() async throws {
        let model = makeModel(step: .peek)
        model.handlePeekHotkey()

        XCTAssertTrue(model.choosePeekNumber(2))
        XCTAssertEqual(model.phase, .peekProcessing)
        XCTAssertEqual(model.peekLanguage, .polish)
        XCTAssertFalse(model.canContinue)

        try await Task.sleep(for: .milliseconds(1_100))

        XCTAssertEqual(model.phase, .peek)
        XCTAssertTrue(model.canContinue)
        XCTAssertEqual(model.originalText, "¿Nos vemos frente a la estación sobre el mediodía?")
        XCTAssertEqual(model.peekLanguage.result, "Czy spotkamy się przed dworcem około południa?")
        XCTAssertTrue(model.escapeOverlay())
        XCTAssertEqual(model.phase, .peekDone)
        XCTAssertTrue(model.canContinue)
    }

    func testPeekSearchFiltersLanguagesAndNumbersChooseVisibleRows() {
        let model = makeModel(step: .peek)
        model.handlePeekHotkey()
        model.peekQuery = "fran"

        XCTAssertEqual(model.peekChoices.map(\.name), ["Français"])
        XCTAssertTrue(model.choosePeekNumber(1))
        XCTAssertEqual(model.peekLanguage, .french)
        XCTAssertEqual(model.phase, .peekProcessing)
    }

    func testPeekResultCanSwitchLanguageAndRunsProcessingAgain() async throws {
        let model = makeModel(step: .peek)
        model.handlePeekHotkey()
        model.choosePeekLanguage(at: 0)
        try await Task.sleep(for: .milliseconds(1_000))
        XCTAssertEqual(model.phase, .peek)

        model.cyclePeekLanguage()

        XCTAssertEqual(model.peekLanguage, .polish)
        XCTAssertEqual(model.phase, .peekProcessing)
        try await Task.sleep(for: .milliseconds(1_000))
        XCTAssertEqual(model.phase, .peek)
    }

    func testSkippingPeekCancelsItsLoadingTask() async throws {
        let model = makeModel(step: .peek)
        model.handlePeekHotkey()
        model.choosePeekLanguage(at: 0)

        model.skipPractice()

        XCTAssertEqual(model.phase, .skipped)
        XCTAssertTrue(model.canContinue)
        try await Task.sleep(for: .milliseconds(1_000))
        XCTAssertEqual(model.phase, .skipped)
    }

    func testCanGoBackThroughCompletedSteps() {
        let model = makeModel(step: .actions)
        model.handleActionHotkey()

        model.goBack()

        XCTAssertEqual(model.step, .fix)
        XCTAssertEqual(model.phase, .idle)
    }

    func testSkipCompletesOnlyPracticeSteps() {
        let model = makeModel(step: .fix)

        model.skipPractice()

        XCTAssertEqual(model.phase, .skipped)
        XCTAssertTrue(model.canContinue)
    }

    func testSkippingPeekCanStillContinue() {
        let model = makeModel(step: .peek)

        model.skipPractice()

        XCTAssertEqual(model.phase, .skipped)
        XCTAssertTrue(model.canContinue)
    }

    private func makeModel(
        step: OnboardingStep = .welcome,
        accessibility: OnboardingAccessibilityStub = OnboardingAccessibilityStub()
    ) -> OnboardingViewModel {
        OnboardingViewModel(accessibility: accessibility, initialStep: step)
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
