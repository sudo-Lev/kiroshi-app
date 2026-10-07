import AppKit
import Foundation

enum OnboardingPhase: Equatable {
    case idle
    case processing
    case typing
    case palette
    case done
}

enum OnboardingChoice: Int, CaseIterable, Identifiable {
    case ukrainian
    case polish
    case german
    case english
    case slack
    case formal

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .slack: "Slack"
        case .formal: "Formal"
        case .ukrainian: "Ukrainian"
        case .polish: "Polish"
        case .german: "German"
        case .english: "English"
        }
    }

    var result: String {
        switch self {
        case .slack: "Hey, could you send me the file when you get a sec?"
        case .formal: "Could you please send me the file at your earliest convenience?"
        case .ukrainian: "Можеш надіслати мені файл якнайшвидше, будь ласка?"
        case .polish: "Możesz wysłać mi plik jak najszybciej?"
        case .german: "Kannst du mir die Datei bitte so schnell wie möglich schicken?"
        case .english: "Could you send me the file as soon as possible, please?"
        }
    }
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
    @Published private(set) var optionDown = false
    @Published private(set) var commandDown = false
    @Published private(set) var tapCount = 0
    @Published private(set) var selectionIndex = 0
    @Published private(set) var hasRealInput = false

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
        case 2...3: phase == .done
        case 4: true
        default: false
        }
    }

    var originalText: String {
        switch step {
        case 3: "yo can u send me the file asap pls"
        default: "helo i thnik this sentnce sound wierd"
        }
    }

    func refreshAccessibility() {
        let wasRequesting = isRequestingAccessibility
        accessibilityGranted = accessibility.isTrusted
        guard accessibilityGranted else { return }
        isRequestingAccessibility = false
        if wasRequesting, step == 1 { advance() }
    }

    func requestAccessibility() {
        accessibility.requestPermission()
        guard !accessibilityGranted, !isRequestingAccessibility else { return }
        isRequestingAccessibility = true
        addTask { [weak self] in
            for _ in 0..<120 {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, let self else { return }
                refreshAccessibility()
                guard accessibilityGranted else { continue }
                return
            }
            self?.isRequestingAccessibility = false
        }
    }

    func advance() {
        guard canContinue, step < 4 else { return }
        step += 1
    }

    func goBack() {
        guard step > 0 else { return }
        step -= 1
    }

    func skipPractice() {
        guard (2...3).contains(step) else { return }
        phase = .done
    }

    func updateModifiers(option: Bool, command: Bool) {
        optionDown = option
        commandDown = command
    }

    func handleMainHotkey() {
        hasRealInput = true
        guard phase == .idle else { return }
        switch step {
        case 2:
            runReplacement("Hello, I think this sentence sounds weird.")
        case 3:
            registerDoubleTap()
        default:
            break
        }
    }

    func moveSelection(by delta: Int) {
        if phase == .palette {
            selectionIndex = min(max(selectionIndex + delta, 0), OnboardingChoice.allCases.count - 1)
        }
    }

    func chooseNumber(_ number: Int) {
        if phase == .palette, OnboardingChoice.allCases.indices.contains(number) {
            chooseAction(OnboardingChoice.allCases[number])
        }
    }

    func confirmSelection() {
        if phase == .palette {
            chooseAction(OnboardingChoice.allCases[selectionIndex])
        }
    }

    func escapeOverlay() -> Bool {
        guard phase == .palette else { return false }
        cancelTasks()
        phase = .idle
        tapCount = 0
        return true
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

    private func registerDoubleTap() {
        tapCount += 1
        cancelTasks()
        if tapCount >= 2 {
            tapCount = 0
            phase = .palette
            selectionIndex = 0
        } else {
            addTask { [weak self] in
                try? await Task.sleep(for: .milliseconds(900))
                guard !Task.isCancelled else { return }
                self?.tapCount = 0
            }
        }
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

    private func resetStepState() {
        phase = .idle
        choice = nil
        typed = ""
        optionDown = false
        commandDown = false
        tapCount = 0
        selectionIndex = 0
        hasRealInput = false
    }

    private func addTask(_ operation: @escaping @MainActor () async -> Void) {
        tasks.append(Task { await operation() })
    }

    private func cancelTasks() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }
}
