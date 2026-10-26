import AppKit
import XCTest
@testable import HotkeyGo

final class PeekViewModelTests: XCTestCase {
    func testAPIUsesTheCurrentlyDeployedWorkerRoute() {
        XCTAssertEqual(HotkeyGoAPI.endpoint.path, "/v2/qwix")
    }

    func testPeekRegistersOptionCommandZ() {
        let hotKey = HotKeySpy()
        PeekHotkey(hotKey: hotKey).start(key: "Z") {}

        XCTAssertEqual(hotKey.keyCode, 0x06)
        XCTAssertEqual(hotKey.modifiers, [.option, .command])
    }

    func testPeekShortcutMatchesItsOnboardingKeyEvent() throws {
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

        XCTAssertTrue(HotkeyCatalog.peek.matches(event))
        XCTAssertFalse(HotkeyCatalog.actions.matches(event))
        XCTAssertFalse(HotkeyCatalog.fix.matches(event))
    }

    func testPeekRegistersTheConfiguredBinding() {
        let hotKey = HotKeySpy()
        let binding = HotkeyBinding(keyCode: 0x0F, modifiers: [.control, .shift])
        PeekHotkey(hotKey: hotKey).start(binding: binding) {}

        XCTAssertEqual(hotKey.keyCode, binding.keyCode)
        XCTAssertEqual(hotKey.modifiers, binding.modifiers)
    }

    func testSmartDefaultChoosesTranslationForDifferentLanguage() {
        XCTAssertEqual(
            PeekViewModel.smartDefault(sourceLanguage: "fr", targetLanguage: "en", wordCount: 12),
            .translate
        )
    }

    func testSmartDefaultChoosesSummaryForLongSameLanguageText() {
        XCTAssertEqual(
            PeekViewModel.smartDefault(sourceLanguage: "en", targetLanguage: "en-US", wordCount: 81),
            .summary
        )
    }

    func testSmartDefaultChoosesSummaryForShortSameLanguageText() {
        XCTAssertEqual(
            PeekViewModel.smartDefault(sourceLanguage: "uk", targetLanguage: "uk", wordCount: 80),
            .summary
        )
    }

    func testTranslationTargetUsesTheFirstInlineChoice() {
        XCTAssertEqual(PeekViewModel.translationTarget(for: "uk"), "en")
        XCTAssertEqual(PeekViewModel.translationTarget(for: "uk-UA"), "en")
        XCTAssertEqual(PeekViewModel.translationTarget(for: "en"), "uk")
        XCTAssertEqual(PeekViewModel.translationTarget(for: "pl"), "en")
        XCTAssertEqual(PeekViewModel.translationTarget(for: "fr"), "en")
    }

    @MainActor
    func testForeignSelectionOverridesRememberedModeWithTranslation() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set(PeekMode.summary.rawValue, forKey: PeekPreferenceKey.lastMode)
        defaults.set(true, forKey: PeekPreferenceKey.rememberMode)
        defaults.set(true, forKey: PeekPreferenceKey.smartDefault)
        let viewModel = PeekViewModel(
            client: PeekClientSpy(),
            detector: StubLanguageDetector(code: "en"),
            defaults: defaults
        )

        viewModel.open(text: "A selected English sentence.")

        XCTAssertEqual(viewModel.mode, .translate)
        XCTAssertEqual(viewModel.targetLanguage, "uk")
        defaults.removePersistentDomain(forName: #function)
    }

    @MainActor
    func testPeekWaitsForExplicitSubmit() async {
        let client = PeekClientSpy()
        let viewModel = PeekViewModel(client: client, detector: StubLanguageDetector(code: "en"))

        viewModel.open(text: "A short selected sentence.")
        viewModel.selectMode(.summary)
        await Task.yield()

        XCTAssertEqual(viewModel.loadState, .idle)
        XCTAssertTrue(client.requests.isEmpty)

        viewModel.submit()
        await waitUntil { !client.requests.isEmpty }

        XCTAssertEqual(client.requests.map(\.mode), [.summary])
        XCTAssertEqual(client.requests.map(\.targetLanguage), ["en"])
    }

    @MainActor
    func testLongSelectionIsRejectedInsteadOfSilentlyTruncated() {
        let client = PeekClientSpy()
        let viewModel = PeekViewModel(client: client, detector: StubLanguageDetector(code: "en"))
        viewModel.open(text: String(repeating: "x", count: PeekInputLimit.maxUTF16Units + 1))

        XCTAssertTrue(viewModel.sourceText.isEmpty)
        XCTAssertTrue(client.requests.isEmpty)
        if case .failed = viewModel.loadState {} else { XCTFail("Expected visible length error") }
    }

    @MainActor
    func testClosingPeekClearsSelectedText() {
        let viewModel = PeekViewModel(client: PeekClientSpy(), detector: StubLanguageDetector(code: "en"))
        viewModel.open(text: "Private selection")
        viewModel.close()
        XCTAssertEqual(viewModel.sourceText, "")
        XCTAssertNil(viewModel.result)
    }

    @MainActor
    func testInlineTranslationChoiceRunsImmediately() async {
        let client = PeekClientSpy()
        let defaults = UserDefaults(suiteName: #function)!
        defer { defaults.removePersistentDomain(forName: #function) }
        let viewModel = PeekViewModel(
            client: client,
            detector: StubLanguageDetector(code: "en"),
            defaults: defaults
        )
        viewModel.open(text: "A short selected sentence.")

        XCTAssertEqual(viewModel.languages.map(\.code), ["UA", "PL", "FR", "EN"])
        viewModel.chooseNumber(2)
        await waitUntil { !client.requests.isEmpty }

        XCTAssertEqual(client.requests.map(\.mode), [.translate])
        XCTAssertEqual(client.requests.map(\.targetLanguage), ["pl"])
    }

    @MainActor
    func testSearchFiltersFullLanguageNamesAndDigitsChooseVisibleRows() async {
        let defaults = UserDefaults(suiteName: #function)!
        defer { defaults.removePersistentDomain(forName: #function) }
        let client = PeekClientSpy()
        let viewModel = PeekViewModel(
            client: client,
            detector: StubLanguageDetector(code: "en"),
            defaults: defaults
        )
        viewModel.open(text: "A short selected sentence.")
        viewModel.query = "French"

        XCTAssertEqual(viewModel.visibleLanguages.map(\.id), ["fr"])
        XCTAssertEqual(viewModel.selectedChoiceIndex, 0)
        viewModel.chooseNumber(1)
        await waitUntil { !client.requests.isEmpty }

        XCTAssertEqual(client.requests.first?.targetLanguage, "fr")
    }

    @MainActor
    func testRememberedTargetAppearsFirstAndIsPreselected() {
        let defaults = UserDefaults(suiteName: #function)!
        defer { defaults.removePersistentDomain(forName: #function) }
        defaults.set("pl", forKey: PeekPreferenceKey.targetLanguage)
        let viewModel = PeekViewModel(
            client: PeekClientSpy(),
            detector: StubLanguageDetector(code: "en"),
            defaults: defaults
        )

        viewModel.open(text: "A short selected sentence.")

        XCTAssertEqual(viewModel.visibleLanguages.first?.id, "pl")
        XCTAssertEqual(viewModel.selectedChoiceIndex, 0)
    }

    @MainActor
    func testCyclingLanguageRunsTheNextTranslationInPlace() async {
        let defaults = UserDefaults(suiteName: #function)!
        defer { defaults.removePersistentDomain(forName: #function) }
        let client = PeekClientSpy()
        let viewModel = PeekViewModel(
            client: client,
            detector: StubLanguageDetector(code: "en"),
            defaults: defaults
        )
        viewModel.open(text: "A short selected sentence.")
        viewModel.chooseNumber(1)
        await waitUntil { viewModel.loadState == .loaded }

        viewModel.cycleLanguage()
        await waitUntil { client.requests.count > 1 }

        XCTAssertEqual(client.requests.map(\.targetLanguage), ["uk", "pl"])
        XCTAssertEqual(viewModel.targetLanguageName, "Polski")
    }

    @MainActor
    func testThirdInlineTranslationChoiceRunsImmediately() async {
        let client = PeekClientSpy()
        let viewModel = PeekViewModel(client: client, detector: StubLanguageDetector(code: "en"))
        viewModel.open(text: "A short selected sentence.")

        viewModel.chooseNumber(3)
        await waitUntil { !client.requests.isEmpty }

        XCTAssertEqual(client.requests.map(\.mode), [.translate])
        XCTAssertEqual(client.requests.map(\.targetLanguage), ["fr"])
    }

    @MainActor
    func testCompletedTranslationShowsSuccessBeforeResult() async {
        let viewModel = PeekViewModel(
            client: PeekClientSpy(),
            detector: StubLanguageDetector(code: "en")
        )
        viewModel.open(text: "A short selected sentence.")

        viewModel.chooseNumber(1)
        await waitUntil { viewModel.loadState == .success }

        XCTAssertEqual(viewModel.loadState, .success)
        XCTAssertNotNil(viewModel.result)
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func testTranslationDecodeKeepsParagraphsAndDropsEmptyOnes() throws {
        let data = Data(#"{"paragraphs":["Один.","  ","Два."]}"#.utf8)
        let result = try PeekViewModel.decodeResult(data, mode: .translate)

        XCTAssertEqual(result, .translation(["Один.", "Два."]))
        XCTAssertEqual(result.plainText, "Один.\n\nДва.")
    }

    func testPeekRequestSendsOnlyTheTaskAndItsParameters() throws {
        let request = PeekRequest(
            text: "Jedno.\n\nDwa.",
            sourceLanguage: "pl-PL",
            targetLanguage: "uk",
            mode: .translate,
            length: .points,
            operationID: HotkeyGoOperation.makeID()
        )
        let data = try PeekClient().makeBody(request)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])

        XCTAssertEqual(body, [
            "task": "peek",
            "provider": "openai",
            "text": "Jedno.\n\nDwa.",
            "mode": "translate",
            "length": "points",
            "language": "uk",
            "sourceLanguage": "pl"
        ])
    }

    func testPeekRequestIncludesTheSelectedProvider() throws {
        let request = PeekRequest(
            text: "Selected text",
            sourceLanguage: nil,
            targetLanguage: "en",
            mode: .summary,
            length: .points,
            operationID: HotkeyGoOperation.makeID(),
            provider: .anthropic
        )
        let data = try PeekClient().makeBody(request)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])

        XCTAssertEqual(body["provider"], "anthropic")
    }

    @MainActor
    func testRetryReusesTheOperationIDAndANewChoiceGetsANewOne() async {
        let client = PeekClientSpy()
        client.failuresRemaining = 1
        let viewModel = PeekViewModel(client: client, detector: StubLanguageDetector(code: "en"))
        viewModel.open(text: "A short selected sentence.")

        viewModel.chooseNumber(1)
        await waitUntil { if case .failed = viewModel.loadState { true } else { false } }
        viewModel.retry()
        await waitUntil { viewModel.loadState == .loaded }
        viewModel.cycleLanguage()
        await waitUntil { client.requests.count > 2 }

        let ids = client.requests.map(\.operationID)
        XCTAssertEqual(ids.count, 3)
        XCTAssertEqual(ids[0], ids[1])
        XCTAssertNotEqual(ids[1], ids[2])
    }

    func testCacheKeyIncludesModeLanguageAndLength() {
        let base = PeekCacheKey(text: "same", mode: .summary, language: "en", length: .points)
        XCTAssertEqual(base, PeekCacheKey(text: "same", mode: .summary, language: "en", length: .points))
        XCTAssertNotEqual(base, PeekCacheKey(text: "same", mode: .translate, language: "en", length: .points))
        XCTAssertNotEqual(base, PeekCacheKey(text: "same", mode: .summary, language: "uk", length: .points))
        XCTAssertNotEqual(base, PeekCacheKey(text: "same", mode: .summary, language: "en", length: .full))
        XCTAssertNotEqual(base, PeekCacheKey(text: "different", mode: .summary, language: "en", length: .points))
        XCTAssertNotEqual(base, PeekCacheKey(text: "same", mode: .summary, language: "en", length: .points, provider: .anthropic))
    }
}

private final class PeekClientSpy: PeekClientProtocol {
    private(set) var requests: [PeekRequest] = []
    var failuresRemaining = 0

    func stream(_ request: PeekRequest) -> AsyncThrowingStream<String, Error> {
        requests.append(request)
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            return AsyncThrowingStream { $0.finish(throwing: URLError(.badServerResponse)) }
        }
        return AsyncThrowingStream { continuation in
            let value = switch request.mode {
            case .translate: #"{"paragraphs":["Б."]}"#
            case .summary: #"{"content":["Short summary."]}"#
            }
            continuation.yield(value)
            continuation.finish()
        }
    }
}

private struct StubLanguageDetector: LanguageDetecting {
    let code: String
    func detect(_ text: String) -> DetectedLanguage? {
        DetectedLanguage(code: code, displayName: code.uppercased())
    }
}

private final class HotKeySpy: HotKeyManaging {
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
