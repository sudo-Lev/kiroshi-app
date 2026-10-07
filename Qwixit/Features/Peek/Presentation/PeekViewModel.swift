import AppKit
import CryptoKit
import Foundation

enum PeekLoadState: Equatable {
    case idle
    case loading
    case loaded
    case limitReached
    case failed(String)
}

struct PeekSentence: Codable, Equatable, Identifiable {
    var id: String { source + "\u{0}" + target }
    let source: String
    let target: String
    let lead: String?

    init(source: String, target: String, lead: String? = nil) {
        self.source = source
        self.target = target
        self.lead = lead
    }
}

enum PeekResult: Equatable {
    case translation([PeekSentence])
    case summary([String])

    var plainText: String {
        return switch self {
        case .translation(let sentences): sentences.enumerated().map { index, sentence in
            let lead = sentence.lead?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let cleanLead = lead.trimmingCharacters(in: .punctuationCharacters)
            guard !cleanLead.isEmpty else { return sentence.target }
            return index == 0
                ? "# \(cleanLead)\n\n\(sentence.target)"
                : "**\(cleanLead):** \(sentence.target)"
        }.joined(separator: "\n\n")
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
    @Published var isPinned = false
    @Published private(set) var selectedChoiceIndex = 0

    private let client: PeekClientProtocol
    private let detector: LanguageDetecting
    private let defaults: UserDefaults
    private var cache: [PeekCacheKey: PeekResult] = [:]
    private var requestTask: Task<Void, Never>?
    private var prefetchTasks: [Task<Void, Never>] = []
    private var copyResetTask: Task<Void, Never>?
    private var offlineTask: Task<Void, Never>?
    private var isManualMode = false

    var isAwaitingChoice: Bool { loadState == .idle }
    var languages: [TranslationLanguage] { TranslationLanguages.targets(for: sourceLanguage?.code) }
    var choiceCount: Int { languages.count }

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

    var footerText: String {
        if isManualMode, let result {
            let outputCount = result.plainText.split(whereSeparator: \.isWhitespace).count
            return "\(wordCount) → \(outputCount) words"
        }
        let detected = sourceLanguage?.displayName ?? "Language unknown"
        return "Auto · \(detected) · \(wordCount) words"
    }

    var targetLanguageName: String {
        Locale.current.localizedString(forLanguageCode: targetLanguage)?.uppercased() ?? targetLanguage.uppercased()
    }

    func open(text: String) {
        cancelAll()
        sourceText = String(text.prefix(24_000))
        sourceLanguage = detector.detect(sourceText)
        let rememberedTarget = AppPreferences(defaults: defaults).peekTargetLanguage
        targetLanguage = languages.contains { $0.id == rememberedTarget }
            ? rememberedTarget
            : Self.translationTarget(for: sourceLanguage?.code)
        summaryLength = rememberedLength()
        mode = .translate
        selectedChoiceIndex = languages.firstIndex { $0.id == targetLanguage } ?? 0
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
        isRetrying = false
        if !isPinned { cache.removeAll() }
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

    func cycleLanguage() {
        let codes = languages.map(\.id)
        guard !codes.isEmpty else { return }
        let index = codes.firstIndex(of: targetLanguage) ?? 0
        targetLanguage = codes[(index + 1) % codes.count]
        defaults.set(targetLanguage, forKey: PeekPreferenceKey.targetLanguage)
        resetChoiceIfNeeded()
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
        selectedChoiceIndex = number - 1
        submitChoice()
    }

    func submitChoice() {
        guard languages.indices.contains(selectedChoiceIndex) else { return }
        runTranslation(at: selectedChoiceIndex)
    }

    func runTranslation(at index: Int) {
        guard languages.indices.contains(index) else { return }
        cancelAll()
        selectedChoiceIndex = index
        mode = .translate
        targetLanguage = languages[index].id
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
            return .translation(value.sentences.filter { !$0.target.isEmpty })
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
            loadState = .loaded
            receivedFirstToken = true
            return
        }

        result = nil
        receivedFirstToken = false
        loadState = .loading
        requestTask = Task { [weak self] in
            guard let self else { return }
            do {
                let value = try await fetch(mode: requestedMode, length: summaryLength)
                try Task.checkCancellation()
                guard mode == requestedMode else { return }
                cache[key] = value
                result = value
                loadState = .loaded
                isRetrying = false
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

    private func fetch(mode: PeekMode, length: PeekSummaryLength) async throws -> PeekResult {
        let responseLanguage = mode == .translate
            ? targetLanguage
            : sourceLanguage?.code ?? targetLanguage
        let request = PeekRequest(
            text: sourceText,
            sourceLanguage: sourceLanguage?.code,
            targetLanguage: responseLanguage,
            mode: mode,
            length: length
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

    private func resetChoiceIfNeeded() {
        guard loadState != .idle else { return }
        cancelAll()
        result = nil
        receivedFirstToken = false
        loadState = .idle
    }
}

private struct TranslationEnvelope: Decodable { let sentences: [PeekSentence] }
private struct SummaryEnvelope: Decodable { let content: [String] }
