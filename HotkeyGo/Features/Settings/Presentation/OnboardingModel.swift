import AppKit
import Foundation

enum OnboardingPhase: Equatable {
    case idle
    case processing
    case typing
    case palette
    case peekChoice
    case peekProcessing
    case peek
    case peekDone
    case skipped
    case done
}

enum OnboardingPeekLanguage: Int, CaseIterable, Identifiable, Equatable {
    case ukrainian
    case polish
    case french
    case english

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .ukrainian: "Українська"
        case .polish: "Polski"
        case .french: "Français"
        case .english: "English"
        }
    }

    var result: String {
        switch self {
        case .ukrainian: "Чи зустрінемося біля вокзалу близько полудня?"
        case .polish: "Czy spotkamy się przed dworcem około południa?"
        case .french: "On se retrouve devant la gare vers midi ?"
        case .english: "Shall we meet in front of the station around noon?"
        }
    }
}

enum OnboardingChoice: Int, CaseIterable, Identifiable {
    case ukrainian
    case polish
    case slack
    case formal

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .slack: "Slack style"
        case .formal: "Make formal"
        case .ukrainian: "Ukrainian"
        case .polish: "Polish"
        }
    }

    var result: String {
        switch self {
        case .slack: "Hey, could you send me the file when you get a sec?"
        case .formal: "Could you please send me the file at your earliest convenience?"
        case .ukrainian: "Можеш надіслати мені файл якнайшвидше, будь ласка?"
        case .polish: "Możesz wysłać mi plik jak najszybciej?"
        }
    }

    var isRewrite: Bool { self == .slack || self == .formal }
}

@MainActor
final class OnboardingModel: ObservableObject {
    @Published var step = 0 {
        didSet {
            guard step != oldValue else { return }
            cancelTasks()
            resetStepState()
        }
    }
    @Published private(set) var phase: OnboardingPhase = .idle
    @Published private(set) var choice: OnboardingChoice?
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

    let accessibility: AccessibilityServicing
    private var tasks: [Task<Void, Never>] = []

    init(
        accessibility: AccessibilityServicing,
        initialStep: Int = 0,
        initialPhase: OnboardingPhase = .idle
    ) {
        self.accessibility = accessibility
        accessibilityGranted = accessibility.isTrusted
        step = initialStep
        phase = initialPhase
    }

    deinit { tasks.forEach { $0.cancel() } }

    func stop() { cancelTasks() }

    var canContinue: Bool {
        switch step {
        case 0: true
        case 1: true
        case 2...3: phase == .done || phase == .skipped
        case 4: phase == .peek || phase == .peekDone || phase == .done || phase == .skipped
        case 5: true
        default: false
        }
    }

    var originalText: String {
        switch step {
        case 3: actionsSample
        case 4: "¿Nos vemos frente a la estación sobre el mediodía?"
        default: "helo i thnik this sentnce sound wierd"
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

    var peekContextLabel: String { "Spanish · \(originalText.split(whereSeparator: \.isWhitespace).count) words" }

    var actionPaletteRows: [HotkeyGoUI.ActionPaletteRow] {
        var hasTranslation = false
        var hasSeenRewrite = false
        return actionChoices.map { choice in
            let startsNewGroup = choice.isRewrite && hasTranslation && !hasSeenRewrite
            if !choice.isRewrite { hasTranslation = true }
            if choice.isRewrite { hasSeenRewrite = true }
            return HotkeyGoUI.ActionPaletteRow(
                id: String(describing: choice),
                title: choice.title,
                startsNewGroup: startsNewGroup
            )
        }
    }

    var actionContextLabel: String { "English · \(actionsSample.split(whereSeparator: \.isWhitespace).count) words" }
    var actionPaletteSeparatorCount: Int { actionPaletteRows.filter(\.startsNewGroup).count }
    var actionPaletteFooter: String { "Sample only · no request is sent" }

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
        guard canContinue, step < 5 else { return }
        step += 1
    }

    func goBack() {
        guard step > 0 else { return }
        step -= 1
    }

    func skipPractice() {
        guard (2...4).contains(step) else { return }
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
        guard step == 2, phase == .idle else { return }
        runReplacement("Hello, I think this sentence sounds weird.")
    }

    func handleActionHotkey() {
        hasRealInput = true
        guard step == 3, phase == .idle else { return }
        phase = .palette
        actionQuery = ""
        actionSelectionIndex = 0
    }

    func handlePeekHotkey() {
        hasRealInput = true
        guard step == 4, phase == .idle || phase == .peekDone else { return }
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
        guard step == 4, phase == .peekChoice, peekChoices.indices.contains(index) else { return }
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
        guard step == 3, phase == .palette else { return }
        choice = action
        runReplacement(action.result)
    }

    func restart() {
        cancelTasks()
        step = 0
        resetStepState()
        refreshAccessibility()
    }

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
            guard !Task.isCancelled, let self, step == 4, phase == .peekProcessing else { return }
            phase = .peek
        }
    }

    private func resetStepState() {
        phase = .idle
        choice = nil
        typed = ""
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
        tasks.append(Task { await operation() })
    }

    private func cancelTasks() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }

    private var actionsSample: String { "yo can u send me the file asap pls" }
}
