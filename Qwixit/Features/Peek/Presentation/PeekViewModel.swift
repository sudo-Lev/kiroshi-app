import AppKit
import CryptoKit
import Foundation

enum PeekLoadState: Equatable {
    case idle
    case loading
    case success
    case loaded
    case limitReached
    case failed(String)
}

enum PeekResult: Equatable {
    case translation([String])
    case summary([String])

    var plainText: String {
        return switch self {
        case .translation(let paragraphs): paragraphs.joined(separator: "\n\n")
        case .summary(let content): content.joined(separator: "\n\n")
        }
    }
}

struct PeekCacheKey: Hashable {
    let selectionHash: String
    let mode: PeekMode
    let language: String
    let length: PeekSummaryLength

    init(text: String, mode: PeekMode, language: String, length: PeekSummaryLength) {
        selectionHash = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        self.mode = mode
        self.language = language
        self.length = length
    }
}

@MainActor
final class PeekViewModel: ObservableObject {
    @Published private(set) var loadState: PeekLoadState = .idle
    @Published private(set) var result: PeekResult?
    @Published private(set) var sourceLanguage: DetectedLanguage?
    @Published private(set) var sourceText = ""
    @Published private(set) var receivedFirstToken = false
    @Published private(set) var isRetrying = false
    @Published private(set) var copied = false
    @Published var mode: PeekMode = .translate
    @Published var summaryLength: PeekSummaryLength = .points
    @Published var targetLanguage: String
    @Published var query = "" {
        didSet { selectedChoiceIndex = 0 }
    }
    @Published var isPinned = false
    @Published private(set) var selectedChoiceIndex = 0

    private let client: PeekClientProtocol
    private let detector: LanguageDetecting
    private let defaults: UserDefaults
    private var cache: [PeekCacheKey: PeekResult] = [:]
    /// One operation per panel request, reused by Retry so a repeat is not charged again.
    private var operationIDs: [PeekCacheKey: String] = [:]
    private var requestTask: Task<Void, Never>?
    private var prefetchTasks: [Task<Void, Never>] = []
    private var copyResetTask: Task<Void, Never>?
    private var offlineTask: Task<Void, Never>?
    private var isManualMode = false

    var isAwaitingChoice: Bool { loadState == .idle }
    var languages: [TranslationLanguage] { TranslationLanguages.targets(for: sourceLanguage?.code) }
    var choiceCount: Int { visibleLanguages.count }

    init(
        client: PeekClientProtocol,
        detector: LanguageDetecting,
        defaults: UserDefaults = .standard
    ) {
        self.client = client
        self.detector = detector
        self.defaults = defaults
        targetLanguage = AppPreferences(defaults: defaults).peekTargetLanguage
    }

    var wordCount: Int {
        sourceText.split(whereSeparator: \.isWhitespace).count
    }

    var orderedLanguages: [TranslationLanguage] {
        guard let target = languages.first(where: { $0.id == targetLanguage }) else { return languages }
        return [target] + languages.filter { $0.id != target.id }
    }

    var visibleLanguages: [TranslationLanguage] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        guard !value.isEmpty else { return orderedLanguages }
        return orderedLanguages.filter { language in
            searchNames(for: language).contains { name in
                name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                    .localizedCaseInsensitiveContains(value)
            }
        }
    }

    var contextLabel: String { "\(sourceLanguage?.displayName ?? "Unknown language") · \(wordCount) words" }

    var footerText: String {
        if isManualMode, let result {
            let outputCount = result.plainText.split(whereSeparator: \.isWhitespace).count
            return "\(wordCount) → \(outputCount) words"
        }
        let detected = sourceLanguage?.displayName ?? "Language unknown"
        return "Auto · \(detected) · \(wordCount) words"
    }

    var targetLanguageName: String {
        languages.first(where: { $0.id == targetLanguage })?.name ?? "English"
    }

    func open(text: String) {
        cancelAll()
        query = ""
        operationIDs.removeAll()
        guard PeekInputLimit.accepts(text) else {
            sourceText = ""
            sourceLanguage = nil
            result = nil
            loadState = .failed(PeekClientError.inputTooLong.localizedDescription)
            return
        }
        sourceText = text
        sourceLanguage = detector.detect(sourceText)
        let rememberedTarget = AppPreferences(defaults: defaults).peekTargetLanguage
        let normalizedSource = sourceLanguage?.code
            .split(separator: "-")
            .first
            .map(String.init)?
            .lowercased()
        targetLanguage = rememberedTarget != normalizedSource && languages.contains { $0.id == rememberedTarget }
            ? rememberedTarget
            : Self.translationTarget(for: sourceLanguage?.code)
        summaryLength = rememberedLength()
        mode = .translate
        selectedChoiceIndex = 0
        isManualMode = false
        result = nil
        receivedFirstToken = false
        isRetrying = false
        loadState = .idle
    }

    func showNoSelection() {
        cancelAll()
        sourceText = ""
        result = nil
        loadState = .failed("Select some text first.")
    }

    func close() {
        cancelAll()
        query = ""
        isRetrying = false
        cache.removeAll()
        operationIDs.removeAll()
        sourceText = ""
        sourceLanguage = nil
        result = nil
        receivedFirstToken = false
        loadState = .idle
        copied = false
    }

    func selectMode(_ newMode: PeekMode, manual: Bool = true) {
        guard newMode != mode else { return }
        cancelAll()
        mode = newMode
        isManualMode = manual
        result = nil
        receivedFirstToken = false
        loadState = .idle
        if AppPreferences(defaults: defaults).peekRememberMode {
            defaults.set(newMode.rawValue, forKey: PeekPreferenceKey.lastMode)
        }
    }

    func nextMode(step: Int = 1) {
        let modes = PeekMode.allCases
        let index = modes.firstIndex(of: mode) ?? 0
        selectMode(modes[(index + step + modes.count) % modes.count])
    }

    func cycleLanguage(step: Int = 1) {
        let codes = languages.map(\.id)
        guard !codes.isEmpty else { return }
        let index = codes.firstIndex(of: targetLanguage) ?? 0
        runTranslation(at: (index + step + codes.count) % codes.count)
    }

    func changeLength(step: Int) {
        let lengths = PeekSummaryLength.allCases
        let index = lengths.firstIndex(of: summaryLength) ?? 0
        summaryLength = lengths[min(max(index + step, 0), lengths.count - 1)]
        defaults.set(summaryLength.rawValue, forKey: PeekPreferenceKey.lastLength)
        if mode == .summary { resetChoiceIfNeeded() }
    }

    func submit() { load() }

    func moveChoice(_ step: Int) {
        guard choiceCount > 0 else { return }
        selectedChoiceIndex = (selectedChoiceIndex + step + choiceCount) % choiceCount
    }

    func chooseNumber(_ number: Int) {
        guard (1...choiceCount).contains(number) else { return }
        chooseLanguage(at: number - 1)
    }

    func chooseLanguage(at visibleIndex: Int) {
        guard visibleLanguages.indices.contains(visibleIndex) else { return }
        selectedChoiceIndex = visibleIndex
        submitChoice()
    }

    func submitChoice() {
        guard visibleLanguages.indices.contains(selectedChoiceIndex),
              let index = languages.firstIndex(where: { $0.id == visibleLanguages[selectedChoiceIndex].id }) else { return }
        runTranslation(at: index)
    }

    func runTranslation(at index: Int) {
        guard languages.indices.contains(index) else { return }
        runTranslation(language: languages[index])
    }

    private func runTranslation(language: TranslationLanguage) {
        cancelAll()
        query = ""
        mode = .translate
        targetLanguage = language.id
        selectedChoiceIndex = 0
        defaults.set(targetLanguage, forKey: PeekPreferenceKey.targetLanguage)
        result = nil
        receivedFirstToken = false
        loadState = .idle
        load()
    }

    func runSummary(_ length: PeekSummaryLength) {
        cancelAll()
        summaryLength = length
        mode = .summary
        selectedChoiceIndex = languages.count + (PeekSummaryLength.allCases.firstIndex(of: length) ?? 0)
        defaults.set(length.rawValue, forKey: PeekPreferenceKey.lastLength)
        result = nil
        receivedFirstToken = false
        loadState = .idle
        load()
    }

    func retry() {
        isRetrying = true
        load()
    }

    func copyResult() {
        guard let result else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result.plainText, forType: .string)
        copied = true
        copyResetTask?.cancel()
        copyResetTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1_400))
            guard !Task.isCancelled else { return }
            self?.copied = false
        }
    }

    func togglePin() { isPinned.toggle() }

    nonisolated static func smartDefault(sourceLanguage: String?, targetLanguage: String, wordCount: Int) -> PeekMode {
        if let sourceLanguage,
           sourceLanguage.split(separator: "-").first?.lowercased() != targetLanguage.split(separator: "-").first?.lowercased() {
            return .translate
        }
        return .summary
    }

    nonisolated static func translationTarget(for sourceLanguage: String?) -> String {
        switch sourceLanguage?.split(separator: "-").first?.lowercased() {
        case "uk": "en"
        case "en": "uk"
        default: "en"
        }
    }

    nonisolated static func decodeResult(_ data: Data, mode: PeekMode) throws -> PeekResult {
        switch mode {
        case .translate:
            let value = try JSONDecoder().decode(TranslationEnvelope.self, from: data)
            return .translation(value.paragraphs.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        case .summary:
            return .summary(try JSONDecoder().decode(SummaryEnvelope.self, from: data).content)
        }
    }

    private func initialMode() -> PeekMode {
        let preferences = AppPreferences(defaults: defaults)
        // Foreign text should always open ready for translation into Ukrainian,
        // even when the user previously left Peek on another mode.
        if preferences.peekSmartDefault,
           sourceLanguage?.code.split(separator: "-").first?.lowercased() != "uk" {
            return .translate
        }
        if preferences.peekRememberMode,
           let raw = defaults.string(forKey: PeekPreferenceKey.lastMode),
           let remembered = PeekMode(rawValue: raw) { return remembered }
        return .translate
    }

    private func rememberedLength() -> PeekSummaryLength {
        guard AppPreferences(defaults: defaults).peekRememberMode,
              let raw = defaults.string(forKey: PeekPreferenceKey.lastLength),
              let value = PeekSummaryLength(rawValue: raw) else { return .points }
        return value
    }

    private func load() {
        requestTask?.cancel()
        offlineTask?.cancel()
        prefetchTasks.forEach { $0.cancel() }
        prefetchTasks.removeAll()
        guard !sourceText.isEmpty else { return }

        let requestedMode = mode
        let key = cacheKey(mode: requestedMode)
        if let cached = cache[key] {
            result = cached
            receivedFirstToken = true
            loadState = .success
            requestTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(520))
                guard !Task.isCancelled, let self, mode == requestedMode else { return }
                loadState = .loaded
            }
            return
        }

        result = nil
        receivedFirstToken = false
        loadState = .loading
        requestTask = Task { [weak self] in
            guard let self else { return }
            do {
                let value = try await fetch(mode: requestedMode, length: summaryLength, operationID: operationID(for: key))
                try Task.checkCancellation()
                guard mode == requestedMode else { return }
                cache[key] = value
                result = value
                isRetrying = false
                loadState = .success
                try await Task.sleep(for: .milliseconds(520))
                try Task.checkCancellation()
                guard mode == requestedMode else { return }
                loadState = .loaded
            } catch is CancellationError {
                return
            } catch QwixitAPIError.quotaExceeded {
                guard mode == requestedMode else { return }
                loadState = .limitReached
                isRetrying = false
            } catch {
                guard mode == requestedMode else { return }
                if QwixitAPI.isConnectivityError(error) {
                    loadState = .failed(QwixitFace.lost.line)
                    scheduleOfflineWaiting(for: requestedMode)
                } else {
                    loadState = .failed(error.localizedDescription)
                }
                isRetrying = false
            }
        }
    }

    private func operationID(for key: PeekCacheKey) -> String {
        if let existing = operationIDs[key] { return existing }
        let created = QwixitOperation.makeID()
        operationIDs[key] = created
        return created
    }

    private func fetch(mode: PeekMode, length: PeekSummaryLength, operationID: String) async throws -> PeekResult {
        let responseLanguage = mode == .translate
            ? targetLanguage
            : sourceLanguage?.code ?? targetLanguage
        let request = PeekRequest(
            text: sourceText,
            sourceLanguage: sourceLanguage?.code,
            targetLanguage: responseLanguage,
            mode: mode,
            length: length,
            operationID: operationID
        )
        var json = ""
        for try await delta in client.stream(request) {
            try Task.checkCancellation()
            if !delta.isEmpty { receivedFirstToken = true }
            json += delta
        }
        guard let data = json.data(using: .utf8), !json.isEmpty else { throw PeekClientError.invalidResponse }
        return try Self.decodeResult(data, mode: mode)
    }

    private func cacheKey(mode: PeekMode) -> PeekCacheKey {
        PeekCacheKey(text: sourceText, mode: mode, language: targetLanguage, length: summaryLength)
    }

    private func cancelAll() {
        requestTask?.cancel()
        offlineTask?.cancel()
        prefetchTasks.forEach { $0.cancel() }
        prefetchTasks.removeAll()
    }

    private func scheduleOfflineWaiting(for requestedMode: PeekMode) {
        offlineTask?.cancel()
        offlineTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self, mode == requestedMode,
                  loadState == .failed(QwixitFace.lost.line) else { return }
            loadState = .failed(QwixitFace.idle.line)
        }
    }

    private func searchNames(for language: TranslationLanguage) -> [String] {
        switch language.id {
        case "uk": [language.name, "Ukrainian"]
        case "pl": [language.name, "Polish"]
        case "fr": [language.name, "French"]
        case "en": [language.name, "English"]
        default: [language.name]
        }
    }

    private func resetChoiceIfNeeded() {
        guard loadState != .idle else { return }
        cancelAll()
        result = nil
        receivedFirstToken = false
        loadState = .idle
    }
}

private struct TranslationEnvelope: Decodable { let paragraphs: [String] }
private struct SummaryEnvelope: Decodable { let content: [String] }
