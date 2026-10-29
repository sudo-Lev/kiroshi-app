import XCTest
import CoreGraphics
@testable import HotkeyGo

final class PaletteViewModelTests: XCTestCase {
    private let actions = [
        ActionGroup(id: "replace", title: "REPLACE", actions: [
            PaletteAction(id: "fix", name: "Fix", hint: "typos and grammar", mode: .replace),
            PaletteAction(id: "translate", name: "Translate", hint: "English, Polski, Українська", mode: .replace)
        ]),
        ActionGroup(id: "insert", title: "INSERT", actions: [
            PaletteAction(id: "analyze", name: "Analyze", hint: "tone and risks", mode: .insert)
        ])
    ]

    func testFilteringMatchesNameHintAndMode() {
        XCTAssertEqual(PaletteFilter.apply("grammar", to: actions).flatMap(\.actions).map(\.id), ["fix"])
        XCTAssertEqual(PaletteFilter.apply("insert", to: actions).flatMap(\.actions).map(\.id), ["analyze"])
        XCTAssertEqual(PaletteFilter.apply("analyze", to: actions).flatMap(\.actions).map(\.id), ["analyze"])
    }

    func testFilteringRecognizesLocalizedLanguageName() {
        XCTAssertEqual(PaletteFilter.apply("polski", to: actions).flatMap(\.actions).map(\.id), ["translate"])
    }

    func testPaletteRegistersOptionCommandA() {
        let hotKey = PaletteHotKeySpy()
        ActionHotkey(hotKey: hotKey).start {}

        XCTAssertEqual(hotKey.keyCode, 0x00)
        XCTAssertEqual(hotKey.modifiers, [.option, .command])
    }

    func testPaletteRegistersTheConfiguredBinding() {
        let hotKey = PaletteHotKeySpy()
        let binding = HotkeyBinding(keyCode: 0x0F, modifiers: [.control, .shift])
        ActionHotkey(hotKey: hotKey).start(binding: binding) {}

        XCTAssertEqual(hotKey.keyCode, binding.keyCode)
        XCTAssertEqual(hotKey.modifiers, binding.modifiers)
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

    func testPasteIsSubmittedOnlyAfterClipboardAndCommandVEventComplete() {
        XCTAssertTrue(ReplacementAttemptReport.submitted.isSubmitted)

        var missingClipboard = ReplacementAttemptReport.submitted
        missingClipboard.clipboardWrite = .failed
        XCTAssertFalse(missingClipboard.isSubmitted)

        var missingPaste = ReplacementAttemptReport.submitted
        missingPaste.pasteEvent = .notAttempted
        XCTAssertFalse(missingPaste.isSubmitted)

        XCTAssertFalse(ReplacementAttemptReport.pasteFailed.isSubmitted)
    }

    func testInsertIsSubmittedOnlyAfterCaretCollapseAndPasteEventsComplete() {
        var report = ReplacementAttemptReport.submitted
        report.caretMove = .failed
        XCTAssertFalse(report.isSubmitted)

        report.caretMove = .completed
        XCTAssertTrue(report.isSubmitted)
    }

#if DEBUG
    func testDeveloperUsageScenariosResetToLiveWithoutChangingRealQuota() {
        let defaults = UserDefaults(suiteName: #function)!
        defer { defaults.removePersistentDomain(forName: #function) }
        defaults.set(17, forKey: AppPreferenceKey.quotaRemaining)
        defaults.set("free", forKey: AppPreferenceKey.quotaPlan)
        defaults.set(HotkeyGoUsage.currentUTCMonth(), forKey: AppPreferenceKey.quotaPeriod)
        defaults.set(DeveloperUsageScenario.limitReached.rawValue, forKey: AppPreferenceKey.developerUsageScenario)

        XCTAssertEqual(AppPreferences(defaults: defaults).remainingActions, 0)

        AppPreferences.resetDeveloperOverrides(defaults: defaults)

        XCTAssertEqual(AppPreferences(defaults: defaults).developerUsageScenario, .live)
        XCTAssertEqual(AppPreferences(defaults: defaults).remainingActions, 17)
        XCTAssertFalse(AppPreferences(defaults: defaults).isAdvanced)
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
        XCTAssertEqual(PaletteViewModel.translationTargets(for: "fr-FR"), ["en", "uk"])
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
    func testUnmatchedQueryOffersNoFreeformAction() {
        let defaults = UserDefaults(suiteName: #function)!
        defer { defaults.removePersistentDomain(forName: #function) }
        let viewModel = makePalette(sourceLanguage: "en", defaults: defaults)
        var ran: PaletteAction?
        viewModel.onRun = { ran = $0 }

        viewModel.query = "write a python script"
        viewModel.submit()

        XCTAssertTrue(viewModel.choices.isEmpty)
        XCTAssertNil(ran)
    }

    @MainActor
    func testSearchFiltersTargetNamesAndSelectsTheFirstMatch() {
        let defaults = UserDefaults(suiteName: #function)!
        defer { defaults.removePersistentDomain(forName: #function) }
        let viewModel = makePalette(sourceLanguage: "en", defaults: defaults)

        viewModel.query = "polish"

        XCTAssertEqual(viewModel.choices.map(\.id), ["translate:pl"])
        XCTAssertEqual(viewModel.selectedIndex, 0)
        XCTAssertEqual(viewModel.contextLabel, "English · 3 words")
    }

    @MainActor
    func testLastUsedChoiceIsPreselectedAndPrioritizedWithinItsGroup() {
        let defaults = UserDefaults(suiteName: #function)!
        defer { defaults.removePersistentDomain(forName: #function) }
        let first = makePalette(sourceLanguage: "en", defaults: defaults)
        first.runChoice(at: 3)

        let reopened = makePalette(sourceLanguage: "en", defaults: defaults)

        XCTAssertEqual(reopened.selectedAction?.id, "formal")
        XCTAssertEqual(reopened.choices[reopened.translationChoices.count].action.id, "formal")
    }

    @MainActor
    func testTypedTextNeverBecomesPartOfTheAction() {
        let viewModel = makePalette(sourceLanguage: "en")
        var ran: PaletteAction?
        viewModel.onRun = { ran = $0 }

        viewModel.query = "formal"
        viewModel.submit()

        XCTAssertEqual(ran, PaletteAction(id: "formal", name: "Make formal", hint: "polished professional tone", mode: .replace))
    }

    @MainActor
    private func makePalette(sourceLanguage: String, defaults: UserDefaults = UserDefaults(suiteName: UUID().uuidString)!) -> PaletteViewModel {
        let viewModel = PaletteViewModel(
            registry: ActionRegistry(),
            detector: FixedLanguageDetector(code: sourceLanguage),
            defaults: defaults
        )
        viewModel.open(capture: PaletteCapture(element: nil, text: "some selected text", range: nil, bounds: nil, fallbackPoint: .zero, processIdentifier: nil))
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

    func testNewServiceErrorsGetTheirOwnChips() {
        XCTAssertEqual(HotkeyGoErrorCopy.headline(for: HotkeyGoAPIError.textTooLong.localizedDescription), "TOO LONG")
        XCTAssertEqual(HotkeyGoErrorCopy.headline(for: HotkeyGoAPIError.outputRejected.localizedDescription), "NOT REPLACED")
        XCTAssertEqual(HotkeyGoErrorCopy.headline(for: HotkeyGoAPIError.dailyLimit.localizedDescription), "DAILY LIMIT")
        XCTAssertEqual(HotkeyGoErrorCopy.headline(for: HotkeyGoAPIError.monthlyLimit.localizedDescription), "MONTHLY LIMIT")
        XCTAssertEqual(HotkeyGoErrorCopy.headline(for: HotkeyGoAPIError.rateLimited(retryAfter: nil).localizedDescription), "SLOW DOWN")
    }

    func testFeedbackErrorTitlesNameTheActualFailure() {
        XCTAssertEqual(
            HotkeyGoErrorCopy.title(for: "The active app did not allow replacement. Your text is unchanged."),
            "Couldn’t replace the text"
        )
        XCTAssertEqual(
            HotkeyGoErrorCopy.title(for: "The AI service returned no text. Your text is unchanged."),
            "No text came back"
        )
        XCTAssertEqual(
            HotkeyGoErrorCopy.title(for: "hotkeygo service error 503: unavailable"),
            "The service couldn’t finish that"
        )
    }
}

private struct FixedLanguageDetector: LanguageDetecting {
    let code: String
    func detect(_ text: String) -> DetectedLanguage? {
        let name = switch code.split(separator: "-").first?.lowercased() {
        case "en": "English"
        case "uk": "Ukrainian"
        case "pl": "Polish"
        case "fr": "French"
        default: code
        }
        return DetectedLanguage(code: code, displayName: name)
    }
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
