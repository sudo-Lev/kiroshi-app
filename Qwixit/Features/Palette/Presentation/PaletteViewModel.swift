import Foundation

struct PaletteChoice: Identifiable, Equatable {
    let id: String
    let action: PaletteAction
    let isTranslation: Bool
    let name: String
}

@MainActor
final class PaletteViewModel: ObservableObject {
    @Published var query = "" { didSet { rebuild() } }
    @Published private(set) var groups: [ActionGroup] = []
    @Published private(set) var selectedIndex = 0
    @Published private(set) var choices: [PaletteChoice] = []
    @Published private(set) var capture: PaletteCapture?
    @Published private(set) var detectedLanguage: DetectedLanguage?

    /// Two useful targets for the selected text. The source language is never offered.
    var languages: [TranslationLanguage] {
        TranslationLanguages.actionTargets(for: detectedLanguage?.code)
    }

    var onRun: ((PaletteAction) -> Void)?

    private let registry: ActionRegistering
    private let detector: LanguageDetecting
    private let defaults: UserDefaults
    private var baseGroups: [ActionGroup] = []
    private let lastUsedChoiceKey = "palette.lastUsedChoice"

    init(registry: ActionRegistering, detector: LanguageDetecting, defaults: UserDefaults = .standard) {
        self.registry = registry
        self.detector = detector
        self.defaults = defaults
    }

    var visibleActions: [PaletteAction] { choices.map(\.action) }
    var translationChoices: [PaletteChoice] { choices.filter(\.isTranslation) }
    var rewriteChoices: [PaletteChoice] { choices.filter { !$0.isTranslation } }
    var showsRewriteDivider: Bool { !translationChoices.isEmpty && !rewriteChoices.isEmpty }
    var selectedAction: PaletteAction? {
        actionChoice(at: selectedIndex)
    }
    var wordCount: Int { capture?.text.split(whereSeparator: \.isWhitespace).count ?? 0 }
    var contextLabel: String { "\(detectedLanguage?.displayName ?? "Unknown language") · \(wordCount) words" }

    var footerText: String { "Replaces selection · ⌘Z undo" }

    func open(capture: PaletteCapture) {
        self.capture = capture
        detectedLanguage = detector.detect(capture.text)
        query = ""
        baseGroups = registry.groups()
        groups = baseGroups
        rebuild()
    }

    func move(_ step: Int) {
        let count = choiceCount
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + step + count) % count
    }

    func chooseNumber(_ number: Int) {
        guard query.isEmpty else { return }
        runChoice(at: number - 1)
    }

    func runAction(_ action: PaletteAction) {
        guard let index = choiceIndex(for: action) else { return }
        runChoice(at: index)
    }

    func runLanguage(at index: Int) {
        guard languages.indices.contains(index) else { return }
        guard let choiceIndex = choices.firstIndex(where: { $0.id == "translate:\(languages[index].id)" }) else { return }
        runChoice(at: choiceIndex)
    }

    func runChoice(at index: Int) {
        guard choices.indices.contains(index) else { return }
        selectedIndex = index
        let choice = choices[index]
        defaults.set(choice.id, forKey: lastUsedChoiceKey)
        onRun?(choice.action)
    }

    func index(of action: PaletteAction, in group: ActionGroup) -> Int {
        choiceStartIndex(of: action)
    }

    func submit() {
        runChoice(at: selectedIndex)
    }

    func reset() {
        capture = nil
        query = ""
        groups = []
        choices = []
    }

    nonisolated static func translationTargets(for sourceLanguage: String?) -> [String] {
        TranslationLanguages.actionTargets(for: sourceLanguage).map(\.id)
    }

    private var choiceCount: Int {
        choices.count
    }

    private func choiceStartIndex(of target: PaletteAction) -> Int {
        choiceIndex(for: target) ?? 0
    }

    private func actionChoice(at targetIndex: Int) -> PaletteAction? {
        choices.indices.contains(targetIndex) ? choices[targetIndex].action : nil
    }

    private func rebuild() {
        groups = PaletteFilter.apply(query, to: baseGroups)
        let value = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let allActions = baseGroups.flatMap(\.actions)
        let translations = allActions.first(where: { $0.id == "translate" }).map { translate in
            prioritized(languages.map { language in
                var action = translate
                action.language = language.id
                return PaletteChoice(
                    id: "translate:\(language.id)",
                    action: action,
                    isTranslation: true,
                    name: language.name
                )
            })
        } ?? []
        let rewrites = prioritized(allActions.filter { $0.id != "translate" }.map {
            PaletteChoice(id: $0.id, action: $0, isTranslation: false, name: $0.name)
        })

        let matchingTranslations = value.isEmpty ? translations : translations.filter {
            guard let languageID = $0.action.language,
                  let language = languages.first(where: { $0.id == languageID }) else { return false }
            return matches(value, in: language.name + " " + englishLanguageName(for: language.id))
        }
        let matchingRewrites = value.isEmpty ? rewrites : rewrites.filter {
            matches(value, in: $0.name + " " + $0.action.hint)
        }

        choices = matchingTranslations + matchingRewrites

        if value.isEmpty {
            let lastUsed = defaults.string(forKey: lastUsedChoiceKey)
            selectedIndex = choices.firstIndex(where: { $0.id == lastUsed }) ?? 0
        } else {
            selectedIndex = 0
        }
    }

    private func prioritized(_ choices: [PaletteChoice]) -> [PaletteChoice] {
        guard let lastUsed = defaults.string(forKey: lastUsedChoiceKey),
              let index = choices.firstIndex(where: { $0.id == lastUsed }) else { return choices }
        return [choices[index]] + choices.enumerated().filter { $0.offset != index }.map(\.element)
    }

    private func matches(_ query: String, in value: String) -> Bool {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .localizedCaseInsensitiveContains(query)
    }

    private func englishLanguageName(for id: String) -> String {
        switch id {
        case "uk": "Ukrainian"
        case "pl": "Polish"
        case "fr": "French"
        case "en": "English"
        default: ""
        }
    }

    private func choiceIndex(for action: PaletteAction) -> Int? {
        if action.id == "translate", let language = action.language {
            return choices.firstIndex(where: { $0.id == "translate:\(language)" })
        }
        return choices.firstIndex(where: { $0.action.id == action.id })
    }
}
