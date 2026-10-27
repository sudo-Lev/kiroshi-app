import AppKit
import Foundation

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published private(set) var step: OnboardingStep {
        didSet {
            guard step != oldValue else { return }
            cancelTasks()
            resetStepState()
        }
    }
    @Published private(set) var phase: OnboardingPhase = .idle
    @Published private(set) var typed = ""
    @Published private(set) var accessibilityGranted: Bool
    @Published private(set) var isRequestingAccessibility = false
    @Published private(set) var permissionCheckTimedOut = false
    @Published private(set) var controlDown = false
    @Published private(set) var optionDown = false
    @Published private(set) var shiftDown = false
    @Published private(set) var commandDown = false
    @Published private(set) var actionSelectionIndex = 0
    @Published private(set) var peekSelectionIndex = 0
    @Published private(set) var peekLanguage = OnboardingPeekLanguage.ukrainian
    @Published private(set) var peekCopied = false
    @Published private(set) var hasRealInput = false
    let detectedLanguage: DetectedLanguage?
    @Published var actionQuery = "" {
        didSet {
            if actionQuery != oldValue { actionSelectionIndex = 0 }
        }
    }
    @Published var peekQuery = "" {
        didSet {
            if peekQuery != oldValue { peekSelectionIndex = 0 }
        }
    }

    private let accessibility: AccessibilityServicing
    private let defaults: UserDefaults
    private var activeTask: Task<Void, Never>?

    init(
        accessibility: AccessibilityServicing,
        detector: LanguageDetecting = LanguageDetector(),
        defaults: UserDefaults = .standard,
        initialStep: OnboardingStep = .welcome,
        initialPhase: OnboardingPhase = .idle
    ) {
        self.accessibility = accessibility
        self.defaults = defaults
        accessibilityGranted = accessibility.isTrusted
        detectedLanguage = detector.detect(Self.peekSampleText)
        step = initialStep
        phase = initialPhase
    }

    deinit { activeTask?.cancel() }

    func stop() { cancelTasks() }

    var hasCompletedOnboarding: Bool {
        defaults.bool(forKey: AppPreferenceKey.hasCompletedOnboarding)
    }

    var canContinue: Bool {
        switch step {
        case .welcome, .accessibility, .complete: true
        case .fix, .actions: phase == .done || phase == .skipped
        case .peek: phase == .peek || phase == .peekDone || phase == .done || phase == .skipped
        }
    }

    var originalText: String {
        switch step {
        case .actions: actionsSample
        case .peek: Self.peekSampleText
        case .welcome, .accessibility, .fix, .complete: "helo i thnik this sentnce sound wierd"
        }
    }

    var actionChoices: [OnboardingChoice] {
        let query = actionQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return OnboardingChoice.allCases }
        return OnboardingChoice.allCases.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var peekChoices: [OnboardingPeekLanguage] {
        let query = peekQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let orderedLanguages = [peekLanguage] + OnboardingPeekLanguage.allCases.filter { $0 != peekLanguage }
        guard !query.isEmpty else { return orderedLanguages }
        return orderedLanguages.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var peekWordCount: Int { Self.peekSampleText.split(whereSeparator: \.isWhitespace).count }
    var peekDetectedLanguageName: String { detectedLanguage?.displayName ?? "Unknown language" }
    var peekContextLabel: String { "\(peekDetectedLanguageName) · \(peekWordCount) words" }

    var actionContextLabel: String { "English · \(actionsSample.split(whereSeparator: \.isWhitespace).count) words" }

    func refreshAccessibility() {
        accessibilityGranted = accessibility.isTrusted
        guard accessibilityGranted else { return }
        isRequestingAccessibility = false
        permissionCheckTimedOut = false
    }

    func requestAccessibility() {
        accessibility.requestPermission()
        guard !accessibilityGranted, !isRequestingAccessibility else { return }
        permissionCheckTimedOut = false
        isRequestingAccessibility = true
        addTask { [weak self] in
            for _ in 0..<30 {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, let self else { return }
                refreshAccessibility()
                guard accessibilityGranted else { continue }
                return
            }
            self?.isRequestingAccessibility = false
            self?.permissionCheckTimedOut = true
        }
    }

    func advance() {
        guard canContinue, let nextStep = step.next else { return }
        step = nextStep
    }

    func goBack() {
        guard let previousStep = step.previous else { return }
        step = previousStep
    }

    func goBack(to destination: OnboardingStep) {
        guard destination.precedes(step) else { return }
        step = destination
    }

    func showAccessibilityStep() {
        guard hasCompletedOnboarding else { return }
        step = .accessibility
    }

    func skipPractice() {
        guard step.isPractice else { return }
        cancelTasks()
        phase = .skipped
    }

    func updateModifiers(control: Bool, option: Bool, shift: Bool, command: Bool) {
        controlDown = control
        optionDown = option
        shiftDown = shift
        commandDown = command
    }

    func handleMainHotkey() {
        hasRealInput = true
        guard step == .fix, phase == .idle else { return }
        runReplacement("Hello, I think this sentence sounds weird.")
    }

    func handleActionHotkey() {
        hasRealInput = true
        guard step == .actions, phase == .idle else { return }
        phase = .palette
        actionQuery = ""
        actionSelectionIndex = 0
    }

    func handlePeekHotkey() {
        hasRealInput = true
        guard step == .peek, phase == .idle || phase == .peekDone else { return }
        peekQuery = ""
        peekSelectionIndex = 0
        peekCopied = false
        phase = .peekChoice
    }

    func moveSelection(by delta: Int) {
        if phase == .palette {
            let count = actionChoices.count
            guard count > 0 else { return }
            actionSelectionIndex = (actionSelectionIndex + delta + count) % count
        } else if phase == .peekChoice {
            let count = peekChoices.count
            guard count > 0 else { return }
            peekSelectionIndex = (peekSelectionIndex + delta + count) % count
        }
    }

    @discardableResult
    func chooseNumber(_ number: Int) -> Bool {
        guard phase == .palette, actionQuery.isEmpty else { return false }
        let index = number - 1
        guard actionChoices.indices.contains(index) else { return false }
        chooseAction(actionChoices[index])
        return true
    }

    @discardableResult
    func choosePeekNumber(_ number: Int) -> Bool {
        guard phase == .peekChoice else { return false }
        let index = number - 1
        guard peekChoices.indices.contains(index) else { return false }
        choosePeekLanguage(at: index)
        return true
    }

    func confirmSelection() {
        if phase == .palette {
            guard actionChoices.indices.contains(actionSelectionIndex) else { return }
            chooseAction(actionChoices[actionSelectionIndex])
        } else if phase == .peekChoice {
            guard peekChoices.indices.contains(peekSelectionIndex) else { return }
            choosePeekLanguage(at: peekSelectionIndex)
        }
    }

    func escapeOverlay() -> Bool {
        guard phase == .palette || phase == .peekChoice || phase == .peekProcessing || phase == .peek else { return false }
        cancelTasks()
        phase = phase == .peek ? .peekDone : .idle
        return true
    }

    func choosePeekLanguage(at index: Int) {
        guard step == .peek, phase == .peekChoice, peekChoices.indices.contains(index) else { return }
        startPeekTranslation(peekChoices[index])
    }

    func cyclePeekLanguage(by delta: Int = 1) {
        guard phase == .peek else { return }
        let languages = OnboardingPeekLanguage.allCases
        let current = languages.firstIndex(of: peekLanguage) ?? 0
        let next = (current + delta + languages.count) % languages.count
        startPeekTranslation(languages[next])
    }

    @discardableResult
    func choosePeekResultNumber(_ number: Int) -> Bool {
        guard phase == .peek else { return false }
        let index = number - 1
        guard peekChoices.indices.contains(index) else { return false }
        startPeekTranslation(peekChoices[index])
        return true
    }

    func copyPeekResult() {
        guard phase == .peek else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(peekLanguage.result, forType: .string)
        peekCopied = true
    }

    func chooseAction(_ action: OnboardingChoice) {
        guard step == .actions, phase == .palette else { return }
        runReplacement(action.result)
    }

    func restart() {
        cancelTasks()
        step = .welcome
        resetStepState()
        refreshAccessibility()
    }

    func completeOnboarding() {
        defaults.set(true, forKey: AppPreferenceKey.hasCompletedOnboarding)
    }

#if DEBUG
    func resetOnboardingForTesting() {
        defaults.removeObject(forKey: AppPreferenceKey.hasCompletedOnboarding)
        restart()
    }
#endif

    private func runReplacement(_ result: String) {
        cancelTasks()
        phase = .processing
        typed = ""
        isRequestingAccessibility = false
        addTask { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled, let self else { return }
            phase = .typing
            var cursor = result.startIndex
            while cursor < result.endIndex {
                guard !Task.isCancelled else { return }
                cursor = result.index(cursor, offsetBy: min(2, result.distance(from: cursor, to: result.endIndex)))
                typed = String(result[..<cursor])
                try? await Task.sleep(for: .milliseconds(22))
            }
            phase = .done
        }
    }

    private func startPeekTranslation(_ language: OnboardingPeekLanguage) {
        cancelTasks()
        peekQuery = ""
        peekSelectionIndex = 0
        peekLanguage = language
        peekCopied = false
        phase = .peekProcessing
        typed = ""
        isRequestingAccessibility = false
        addTask { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled, let self, step == .peek, phase == .peekProcessing else { return }
            phase = .peek
        }
    }

    private func resetStepState() {
        phase = .idle
        typed = ""
        isRequestingAccessibility = false
        actionQuery = ""
        controlDown = false
        optionDown = false
        shiftDown = false
        commandDown = false
        actionSelectionIndex = 0
        peekQuery = ""
        peekSelectionIndex = 0
        peekLanguage = .ukrainian
        peekCopied = false
        hasRealInput = false
        permissionCheckTimedOut = false
    }

    private func addTask(_ operation: @escaping @MainActor () async -> Void) {
        activeTask?.cancel()
        activeTask = Task { await operation() }
    }

    private func cancelTasks() {
        activeTask?.cancel()
        activeTask = nil
    }

    private var actionsSample: String { "yo can u send me the file asap pls" }
    private static let peekSampleText = "¿Nos vemos frente a la estación sobre el mediodía?"
}
