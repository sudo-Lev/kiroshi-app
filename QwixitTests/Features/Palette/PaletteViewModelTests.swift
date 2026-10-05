import XCTest
@testable import Qwixit

final class PaletteViewModelTests: XCTestCase {
    private let actions = [
        ActionGroup(id: "replace", title: "REPLACE", actions: [
            PaletteAction(id: "fix", name: "Fix", hint: "typos and grammar", mode: .replace, prompt: "fix"),
            PaletteAction(id: "translate", name: "Translate", hint: "English, Polski, Українська", mode: .replace, prompt: "translate")
        ]),
        ActionGroup(id: "panel", title: "PANEL", actions: [
            PaletteAction(id: "analyze", name: "Analyze", hint: "tone and risks", mode: .panel, prompt: "analyze")
        ])
    ]

    func testFilteringMatchesNameHintAndMode() {
        XCTAssertEqual(PaletteFilter.apply("grammar", to: actions).flatMap(\.actions).map(\.id), ["fix"])
        XCTAssertEqual(PaletteFilter.apply("panel", to: actions).flatMap(\.actions).map(\.id), ["analyze"])
        XCTAssertEqual(PaletteFilter.apply("analyze", to: actions).flatMap(\.actions).map(\.id), ["analyze"])
    }

    func testFilteringRecognizesLocalizedLanguageName() {
        XCTAssertEqual(PaletteFilter.apply("polski", to: actions).flatMap(\.actions).map(\.id), ["translate"])
    }

    func testDoubleTapInsideIntervalWinsAndCancelsSingle() {
        var classifier = DoubleTapClassifier(interval: 0.3)
        XCTAssertEqual(classifier.registerTap(at: 10), .pendingSingle)
        XCTAssertEqual(classifier.registerTap(at: 10.299), .double)
        XCTAssertFalse(classifier.consumePendingSingle(at: 10.6))
    }

    func testTapOutsideIntervalStartsANewSingle() {
        var classifier = DoubleTapClassifier(interval: 0.3)
        XCTAssertEqual(classifier.registerTap(at: 10), .pendingSingle)
        XCTAssertEqual(classifier.registerTap(at: 10.301), .pendingSingle)
        XCTAssertFalse(classifier.consumePendingSingle(at: 10.5))
        XCTAssertTrue(classifier.consumePendingSingle(at: 10.601))
    }

    func testPaletteRegistersOptionCommandX() {
        let hotKey = PaletteHotKeySpy()
        HotkeyManager(hotKey: hotKey).start(intervalMilliseconds: 300, onSingle: {}, onDouble: {})

        XCTAssertEqual(hotKey.keyCode, 0x07)
        XCTAssertEqual(hotKey.modifiers, [.option, .command])
    }

    func testPaletteRegistersCustomBinding() {
        let hotKey = PaletteHotKeySpy()
        let custom = HotkeyBinding(keyCode: 0x0F, modifiers: [.control, .shift])
        HotkeyManager(hotKey: hotKey).start(binding: custom, intervalMilliseconds: 300, onSingle: {}, onDouble: {})

        XCTAssertEqual(hotKey.keyCode, 0x0F)
        XCTAssertEqual(hotKey.modifiers, [.control, .shift])
    }

    func testLegacyDefaultHotkeyMigratesToOptionCommandX() {
        let defaults = UserDefaults(suiteName: #function)!
        defer { defaults.removePersistentDomain(forName: #function) }
        for legacy in HotkeyBinding.legacyDefaults {
            defaults.set(Int(legacy.keyCode), forKey: AppPreferenceKey.mainHotkeyKeyCode)
            defaults.set(Int(legacy.modifiers.rawValue), forKey: AppPreferenceKey.mainHotkeyModifiers)
            LegacyMigration.migrateHotkey(defaults: defaults)
            XCTAssertEqual(AppPreferences(defaults: defaults).mainHotkey, .defaultMain)
        }
    }

    func testCustomHotkeySurvivesMigration() {
        let defaults = UserDefaults(suiteName: #function)!
        defer { defaults.removePersistentDomain(forName: #function) }
        let custom = HotkeyBinding(keyCode: 0x0F, modifiers: [.control, .shift])
        AppPreferences(defaults: defaults).setMainHotkey(custom)

        LegacyMigration.migrateHotkey(defaults: defaults)

        XCTAssertEqual(AppPreferences(defaults: defaults).mainHotkey, custom)
    }

    func testReplacementVerificationRejectsFalseSuccessWhenOriginalTextIsStillSelected() {
        XCTAssertFalse(
            ReplacementVerification.succeeded(
                original: "a bit awkrad",
                replacement: "a bit awkward",
                selectedAfter: "a bit awkrad"
            )
        )
    }

    func testReplacementVerificationAcceptsCollapsedOrReplacedSelection() {
        XCTAssertTrue(
            ReplacementVerification.succeeded(
                original: "a bit awkrad",
                replacement: "a bit awkward",
                selectedAfter: nil
            )
        )
        XCTAssertTrue(
            ReplacementVerification.succeeded(
                original: "a bit awkrad",
                replacement: "a bit awkward",
                selectedAfter: "a bit awkward"
            )
        )
    }

#if DEBUG
    func testDeveloperUsageScenariosResetToLiveWithoutChangingRealQuota() {
        let defaults = UserDefaults(suiteName: #function)!
        defer { defaults.removePersistentDomain(forName: #function) }
        defaults.set(17, forKey: AppPreferenceKey.quotaRemaining)
        defaults.set("free", forKey: AppPreferenceKey.quotaPlan)
        defaults.set(DeveloperUsageScenario.limitReached.rawValue, forKey: AppPreferenceKey.developerUsageScenario)

        XCTAssertEqual(AppPreferences(defaults: defaults).remainingActions, 0)

        AppPreferences.resetDeveloperOverrides(defaults: defaults)

        XCTAssertEqual(AppPreferences(defaults: defaults).developerUsageScenario, .live)
        XCTAssertEqual(AppPreferences(defaults: defaults).remainingActions, 17)
        XCTAssertFalse(AppPreferences(defaults: defaults).isUnlimited)
    }
#endif

    func testAppearancePreferencePersistsDarkTheme() {
        let defaults = UserDefaults(suiteName: #function)!
        defer { defaults.removePersistentDomain(forName: #function) }
        defaults.set(AppAppearance.dark.rawValue, forKey: AppPreferenceKey.appearance)

        XCTAssertEqual(AppPreferences(defaults: defaults).appearance, .dark)
    }

    func testTranslationOffersTwoTargetsThatExcludeTheSourceLanguage() {
        XCTAssertEqual(PaletteViewModel.translationTargets(for: "en"), ["uk", "pl"])
        XCTAssertEqual(PaletteViewModel.translationTargets(for: "uk-UA"), ["en", "pl"])
        XCTAssertEqual(PaletteViewModel.translationTargets(for: "pl"), ["en", "uk"])
        XCTAssertEqual(PaletteViewModel.translationTargets(for: "de-DE"), ["en", "uk"])
        XCTAssertEqual(PaletteViewModel.translationTargets(for: nil), ["en", "uk"])
    }

    func testRegistryKeepsPaletteFocused() {
        let groups = ActionRegistry().groups()

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.flatMap(\.actions).map(\.id), ["translate", "slack", "formal"])
    }

    @MainActor
    func testTranslateRunsDirectlyFromInlineLanguageChoices() {
        let viewModel = makePalette(sourceLanguage: "en")
        var ran: PaletteAction?
        viewModel.onRun = { ran = $0 }

        viewModel.chooseNumber(1)

        XCTAssertEqual(viewModel.languages.map(\.code), ["UA", "PL"])
        XCTAssertEqual(ran?.id, "translate")
        XCTAssertEqual(ran?.language, "uk")

        ran = nil
        viewModel.chooseNumber(2)

        XCTAssertEqual(ran?.id, "translate")
        XCTAssertEqual(ran?.language, "pl")
    }

    @MainActor
    func testRefiningActionAsksQuestionsThenRunsWithAnswers() {
        let viewModel = makeRefiningPalette()
        var refined: PaletteAction?
        var ran: PaletteAction?
        viewModel.onRefine = { refined = $0 }
        viewModel.onRun = { ran = $0 }

        viewModel.chooseNumber(1)
        XCTAssertEqual(refined?.id, "prompt")
        XCTAssertNil(ran)

        viewModel.showQuestions([
            RefineQuestion(question: "Which model?", options: ["Any", "Coding agent"]),
            RefineQuestion(question: "Output?", options: ["Steps", "Code"])
        ], for: refined!)
        viewModel.chooseNumber(2)
        viewModel.shiftAnswer(1)
        viewModel.submit()

        XCTAssertEqual(ran?.id, "prompt")
        XCTAssertTrue(ran?.prompt.contains("Which model? → Coding agent") == true)
        XCTAssertTrue(ran?.prompt.contains("Output? → Code") == true)
    }

    @MainActor
    func testRefiningWithoutQuestionsRunsImmediately() {
        let viewModel = makeRefiningPalette()
        var ran: PaletteAction?
        viewModel.onRun = { ran = $0 }

        viewModel.chooseNumber(2)
        viewModel.showQuestions([], for: viewModel.refinement!.action)

        XCTAssertEqual(ran?.id, "expand")
    }

    @MainActor
    private func makePalette(sourceLanguage: String) -> PaletteViewModel {
        let viewModel = PaletteViewModel(registry: ActionRegistry(), detector: FixedLanguageDetector(code: sourceLanguage))
        viewModel.open(capture: PaletteCapture(element: nil, text: "some selected text", range: nil, bounds: nil, fallbackPoint: .zero))
        return viewModel
    }

    @MainActor
    private func makeRefiningPalette() -> PaletteViewModel {
        let viewModel = PaletteViewModel(registry: RefineActionRegistry(), detector: FixedLanguageDetector(code: "en"))
        viewModel.open(capture: PaletteCapture(element: nil, text: "some selected text", range: nil, bounds: nil, fallbackPoint: .zero))
        return viewModel
    }

    func testContextPanelOpensToTheRightOfTextWhenThereIsRoom() {
        let origin = ContextPanelPlacement.origin(
            anchorRect: CGRect(x: 300, y: 500, width: 100, height: 20),
            fallbackPoint: .zero,
            visibleFrame: CGRect(x: 0, y: 0, width: 1400, height: 900),
            panelSize: NSSize(width: 432, height: 310)
        )

        XCTAssertEqual(origin.x, 414)
        XCTAssertEqual(origin.y, 242)
    }

    func testContextPanelFlipsToTheLeftNearTheRightEdge() {
        let origin = ContextPanelPlacement.origin(
            anchorRect: CGRect(x: 1200, y: 500, width: 100, height: 20),
            fallbackPoint: .zero,
            visibleFrame: CGRect(x: 0, y: 0, width: 1400, height: 900),
            panelSize: NSSize(width: 432, height: 310)
        )

        XCTAssertEqual(origin.x, 754)
        XCTAssertEqual(origin.y, 242)
    }

    func testContextPanelUsesEdgeDockWhenNeitherSideHasRoom() {
        let origin = ContextPanelPlacement.origin(
            anchorRect: CGRect(x: 350, y: 300, width: 100, height: 20),
            fallbackPoint: .zero,
            visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 600),
            panelSize: NSSize(width: 432, height: 310)
        )

        XCTAssertEqual(origin.x, 356)
        XCTAssertEqual(origin.y, 42)
    }
}

private struct RefineActionRegistry: ActionRegistering {
    func groups() -> [ActionGroup] {
        [ActionGroup(id: "refine", title: "REFINE", actions: [
            PaletteAction(id: "prompt", name: "Prompt", hint: "", mode: .replace, prompt: "prompt", refines: true),
            PaletteAction(id: "expand", name: "Expand", hint: "", mode: .replace, prompt: "expand", refines: true)
        ])]
    }
}

private struct FixedLanguageDetector: LanguageDetecting {
    let code: String
    func detect(_ text: String) -> DetectedLanguage? { DetectedLanguage(code: code, displayName: code) }
}

private final class PaletteHotKeySpy: HotKeyManaging {
    private(set) var keyCode: UInt32?
    private(set) var modifiers: GlobalHotKey.Modifiers?

    func register(
        keyCode: UInt32,
        modifiers: GlobalHotKey.Modifiers,
        action: @escaping () -> Void
    ) -> Bool {
        self.keyCode = keyCode
        self.modifiers = modifiers
        return true
    }

    func unregister() {}
}
