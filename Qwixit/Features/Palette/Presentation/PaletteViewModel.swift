import Foundation

/// Quick questions asked before a `refines` action runs. Every question starts on its first option,
/// so pressing ↵ straight away still produces a sensible result.
struct PaletteRefinement: Equatable {
    let action: PaletteAction
    var questions: [RefineQuestion] = []
    var answers: [Int] = []
    var focusedQuestion = 0
    var isLoading = true

    var instruction: String {
        let choices = zip(questions, answers).map { question, answer in
            "- \(question.question) → \(question.options[answer])"
        }
        guard !choices.isEmpty else { return action.prompt }
        return action.prompt + "\nChoices:\n" + choices.joined(separator: "\n")
    }
}

@MainActor
final class PaletteViewModel: ObservableObject {
    @Published var query = "" { didSet { rebuild() } }
    @Published private(set) var groups: [ActionGroup] = []
    @Published private(set) var selectedIndex = 0
    @Published private(set) var capture: PaletteCapture?
    @Published private(set) var detectedLanguage: DetectedLanguage?
    @Published private(set) var refinement: PaletteRefinement?

    /// Two useful targets for the selected text. The source language is never offered.
    var languages: [TranslationLanguage] {
        TranslationLanguages.targets(for: detectedLanguage?.code)
    }

    var onRun: ((PaletteAction) -> Void)?
    /// Asked to fetch clarifying questions for a `refines` action.
    var onRefine: ((PaletteAction) -> Void)?

    private let registry: ActionRegistering
    private let detector: LanguageDetecting
    private let defaults: UserDefaults
    private var baseGroups: [ActionGroup] = []

    init(registry: ActionRegistering, detector: LanguageDetecting, defaults: UserDefaults = .standard) {
        self.registry = registry
        self.detector = detector
        self.defaults = defaults
    }

    var visibleActions: [PaletteAction] { groups.flatMap(\.actions) }
    var selectedAction: PaletteAction? {
        actionChoice(at: selectedIndex)
    }
    var wordCount: Int { capture?.text.split(whereSeparator: \.isWhitespace).count ?? 0 }
    var contextLabel: String { "\(wordCount) words · \(detectedLanguage?.code.uppercased() ?? "—")" }
    var isRefining: Bool { refinement != nil }

    var footerText: String {
        if isRefining { return "Answer · ←→ or 1–4 · ↵ runs" }
        guard let mode = selectedAction?.mode else { return "Replace · custom instruction · ⌘Z undoes" }
        return switch mode {
        case .replace: "Replace · rewrites the selection · ⌘Z undoes"
        case .insert: "Insert · adds after the selection · original kept"
        case .panel: "Panel · opens a card · text untouched"
        }
    }

    func open(capture: PaletteCapture) {
        self.capture = capture
        detectedLanguage = detector.detect(capture.text)
        query = ""
        selectedIndex = 0
        refinement = nil
        baseGroups = registry.groups()
        rebuild()
    }

    func move(_ step: Int) {
        if var refinement {
            guard !refinement.questions.isEmpty else { return }
            let count = refinement.questions.count
            refinement.focusedQuestion = (refinement.focusedQuestion + step + count) % count
            self.refinement = refinement
            return
        }
        let count = choiceCount
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + step + count) % count
    }

    /// ←→ inside the refine step.
    func shiftAnswer(_ step: Int) {
        guard var refinement, !refinement.questions.isEmpty else { return }
        let question = refinement.focusedQuestion
        let count = refinement.questions[question].options.count
        refinement.answers[question] = (refinement.answers[question] + step + count) % count
        self.refinement = refinement
    }

    func chooseAnswer(question: Int, option: Int) {
        guard var refinement, refinement.questions.indices.contains(question),
              refinement.questions[question].options.indices.contains(option) else { return }
        refinement.answers[question] = option
        refinement.focusedQuestion = min(question + 1, refinement.questions.count - 1)
        self.refinement = refinement
    }

    func beginRefinement(_ action: PaletteAction) {
        refinement = PaletteRefinement(action: action)
        query = ""
    }

    func showQuestions(_ questions: [RefineQuestion], for action: PaletteAction) {
        guard refinement?.action.id == action.id else { return }
        guard !questions.isEmpty else { finishRefinement(); return }
        refinement = PaletteRefinement(
            action: action,
            questions: questions,
            answers: Array(repeating: 0, count: questions.count),
            isLoading: false
        )
    }

    /// Runs the refined action; with no questions loaded it runs with the base prompt.
    func finishRefinement() {
        guard let refinement else { return }
        var action = refinement.action
        let note = query.trimmingCharacters(in: .whitespacesAndNewlines)
        action = PaletteAction(
            id: action.id,
            name: action.name,
            hint: action.hint,
            mode: action.mode,
            prompt: refinement.instruction + (note.isEmpty ? "" : "\nAlso: \(note)"),
            language: action.language
        )
        onRun?(action)
    }

    func chooseNumber(_ number: Int) {
        guard query.isEmpty else { return }
        if let refinement {
            chooseAnswer(question: refinement.focusedQuestion, option: number - 1)
            return
        }
        guard (0..<choiceCount).contains(number - 1) else { return }
        selectedIndex = number - 1
        submit()
    }

    func runAction(_ action: PaletteAction) {
        selectedIndex = choiceStartIndex(of: action)
        select(action)
    }

    func runLanguage(at index: Int) {
        guard languages.indices.contains(index) else { return }
        selectedIndex = choiceStartIndexForTranslation + index
        guard let action = actionChoice(at: selectedIndex) else { return }
        run(action)
    }

    func index(of action: PaletteAction, in group: ActionGroup) -> Int {
        choiceStartIndex(of: action)
    }

    func goBack() -> Bool {
        if let refinement {
            self.refinement = nil
            query = ""
            selectedIndex = visibleActions.firstIndex { $0.id == refinement.action.id } ?? 0
            return true
        }
        return false
    }

    func submit() {
        if isRefining {
            // ↵ while questions are still loading runs with the base prompt.
            finishRefinement()
            return
        }
        if let language = matchedLanguage(), !query.isEmpty {
            var action = baseGroups.flatMap(\.actions).first(where: { $0.id == "translate" })!
            action.language = language.id
            run(action)
        } else if let action = actionChoice(at: selectedIndex) {
            select(action)
        } else if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            run(PaletteAction(id: "custom", name: "Custom", hint: query, mode: .replace, prompt: query))
        }
    }

    func reset() {
        capture = nil
        query = ""
        groups = []
        refinement = nil
    }

    /// Translation targets are already concrete actions; refining actions ask questions.
    private func select(_ action: PaletteAction) {
        if action.refines {
            beginRefinement(action)
            onRefine?(action)
        } else {
            run(action)
        }
    }

    private func run(_ action: PaletteAction) {
        onRun?(action)
    }

    nonisolated static func translationTargets(for sourceLanguage: String?) -> [String] {
        TranslationLanguages.targets(for: sourceLanguage).map(\.id)
    }

    private var choiceCount: Int {
        visibleActions.reduce(0) { count, action in
            count + (action.id == "translate" ? languages.count : 1)
        }
    }

    private var choiceStartIndexForTranslation: Int {
        guard let translate = visibleActions.first(where: { $0.id == "translate" }) else { return 0 }
        return choiceStartIndex(of: translate)
    }

    private func choiceStartIndex(of target: PaletteAction) -> Int {
        var index = 0
        for action in visibleActions {
            if action == target { return index }
            index += action.id == "translate" ? languages.count : 1
        }
        return 0
    }

    private func actionChoice(at targetIndex: Int) -> PaletteAction? {
        var index = 0
        for action in visibleActions {
            if action.id == "translate" {
                for language in languages {
                    if index == targetIndex {
                        var translation = action
                        translation.language = language.id
                        return translation
                    }
                    index += 1
                }
            } else {
                if index == targetIndex { return action }
                index += 1
            }
        }
        return nil
    }

    private func rebuild() {
        groups = PaletteFilter.apply(query, to: baseGroups)
        selectedIndex = min(selectedIndex, max(choiceCount - 1, 0))
    }

    private func matchedLanguage() -> TranslationLanguage? {
        let value = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return languages.first {
            $0.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) == value
                || $0.id.caseInsensitiveCompare(value) == .orderedSame
        }
    }
}
