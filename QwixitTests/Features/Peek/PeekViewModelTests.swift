import XCTest
@testable import Qwixit

final class PeekViewModelTests: XCTestCase {
    func testPeekRegistersOptionCommandZ() {
        let hotKey = HotKeySpy()
        PeekHotkey(hotKey: hotKey).start(key: "Z") {}

        XCTAssertEqual(hotKey.keyCode, 0x06)
        XCTAssertEqual(hotKey.modifiers, [.option, .command])
    }

    func testSmartDefaultChoosesTranslationForDifferentLanguage() {
        XCTAssertEqual(
            PeekViewModel.smartDefault(sourceLanguage: "de", targetLanguage: "en", wordCount: 12),
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
        XCTAssertEqual(PeekViewModel.translationTarget(for: "de"), "en")
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
        for _ in 0..<4 { await Task.yield() }

        XCTAssertEqual(client.requests.map(\.mode), [.summary])
        XCTAssertEqual(client.requests.map(\.targetLanguage), ["en"])
    }

    @MainActor
    func testInlineTranslationChoiceRunsImmediately() async {
        let client = PeekClientSpy()
        let viewModel = PeekViewModel(client: client, detector: StubLanguageDetector(code: "en"))
        viewModel.open(text: "A short selected sentence.")

        XCTAssertEqual(viewModel.languages.map(\.code), ["UA", "PL"])
        viewModel.chooseNumber(2)
        for _ in 0..<4 { await Task.yield() }

        XCTAssertEqual(client.requests.map(\.mode), [.translate])
        XCTAssertEqual(client.requests.map(\.targetLanguage), ["pl"])
    }

    @MainActor
    func testInlineSummaryChoiceRunsImmediately() async {
        let client = PeekClientSpy()
        let viewModel = PeekViewModel(client: client, detector: StubLanguageDetector(code: "en"))
        viewModel.open(text: "A short selected sentence.")

        viewModel.chooseNumber(3)
        for _ in 0..<4 { await Task.yield() }

        XCTAssertEqual(client.requests.map(\.mode), [.summary])
        XCTAssertEqual(client.requests.map(\.length), [.tldr])
    }

    func testTranslationDecodePreservesSentenceAlignment() throws {
        let data = Data(#"{"sentences":[{"source":"One.","target":"Один."},{"source":"Two.","target":"Два."}]}"#.utf8)
        let result = try PeekViewModel.decodeResult(data, mode: .translate)

        XCTAssertEqual(
            result,
            .translation([
                PeekSentence(source: "One.", target: "Один."),
                PeekSentence(source: "Two.", target: "Два.")
            ])
        )
    }

    func testCacheKeyIncludesModeLanguageAndLength() {
        let base = PeekCacheKey(text: "same", mode: .summary, language: "en", length: .points)
        XCTAssertEqual(base, PeekCacheKey(text: "same", mode: .summary, language: "en", length: .points))
        XCTAssertNotEqual(base, PeekCacheKey(text: "same", mode: .translate, language: "en", length: .points))
        XCTAssertNotEqual(base, PeekCacheKey(text: "same", mode: .summary, language: "uk", length: .points))
        XCTAssertNotEqual(base, PeekCacheKey(text: "same", mode: .summary, language: "en", length: .full))
        XCTAssertNotEqual(base, PeekCacheKey(text: "different", mode: .summary, language: "en", length: .points))
    }
}

private final class PeekClientSpy: PeekClientProtocol {
    private(set) var requests: [PeekRequest] = []

    func stream(_ request: PeekRequest) -> AsyncThrowingStream<String, Error> {
        requests.append(request)
        return AsyncThrowingStream { continuation in
            let value = switch request.mode {
            case .translate: #"{"sentences":[{"source":"A.","target":"Б."}]}"#
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
