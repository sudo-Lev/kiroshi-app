import Foundation

protocol CheckoutOpening {
    func openStarterCheckout() -> Bool
}

enum BillingActivationState: Equatable {
    case idle
    case confirming
    case delayed
    case ready
}

enum OnboardingDemoPhase: Equatable {
    case waiting
    case processing
    case typing
    case complete
}

enum OnboardingAction: Int, CaseIterable, Identifiable {
    case ukrainian
    case polish
    case slack
    case formal

    var id: Int { rawValue }

    var result: String {
        switch self {
        case .ukrainian: "Можеш надіслати мені файл якнайшвидше, будь ласка?"
        case .polish: "Możesz wysłać mi plik jak najszybciej, proszę?"
        case .slack: "Could you send me the file when you get a sec? Need it asap."
        case .formal: "Could you please send me the file at your earliest convenience?"
        }
    }
}

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published private(set) var accessibilityGranted: Bool
    @Published private(set) var checkoutMessage: String?
    @Published private(set) var remainingActions: Int?
    @Published private(set) var isUnlimited: Bool
    @Published private(set) var billingActivationState: BillingActivationState
#if DEBUG
    @Published private(set) var developerUsageScenario: DeveloperUsageScenario
#endif
    /// 0: Accessibility access, 1: single shortcut, 2: double-tap palette.
    @Published var onboardingStep = 0
    @Published private(set) var onboardingDemoPhase: OnboardingDemoPhase = .waiting
    @Published private(set) var onboardingTypedText = ""
    @Published private(set) var onboardingOriginalText = "helo i thnik this sentnce sound wierd"
    @Published private(set) var onboardingLevel2TapCount = 0
    @Published private(set) var onboardingMenuVisible = false
    @Published private(set) var onboardingMenuSelection = 0
    @Published private(set) var onboardingOptionDown = false
    @Published private(set) var onboardingCommandDown = false
    @Published var showSuccess: Bool {
        didSet { defaults.set(showSuccess, forKey: AppPreferenceKey.showSuccess) }
    }
    @Published var animationsEnabled: Bool {
        didSet { defaults.set(animationsEnabled, forKey: AppPreferenceKey.animationsEnabled) }
    }
    @Published var priorityProcessing: Bool {
        didSet { defaults.set(priorityProcessing, forKey: AppPreferenceKey.priorityProcessing) }
    }
    @Published var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: AppPreferenceKey.appearance) }
    }
    @Published var peekTargetLanguage: String {
        didSet { defaults.set(peekTargetLanguage, forKey: PeekPreferenceKey.targetLanguage) }
    }
    @Published var peekSmartDefault: Bool {
        didSet { defaults.set(peekSmartDefault, forKey: PeekPreferenceKey.smartDefault) }
    }
    @Published var peekRememberMode: Bool {
        didSet { defaults.set(peekRememberMode, forKey: PeekPreferenceKey.rememberMode) }
    }
    @Published var peekPrefetch: Bool {
        didSet { defaults.set(peekPrefetch, forKey: PeekPreferenceKey.prefetch) }
    }
    @Published var peekShortcutKey: String {
        didSet {
            defaults.set(peekShortcutKey, forKey: PeekPreferenceKey.shortcutKey)
            onPeekShortcutChanged?(peekShortcutKey)
        }
    }
    @Published var paletteDoubleTapMS: Int {
        didSet {
            defaults.set(paletteDoubleTapMS, forKey: AppPreferenceKey.paletteDoubleTapMS)
            onPaletteTimingChanged?(paletteDoubleTapMS)
        }
    }

    @Published private(set) var mainHotkey: HotkeyBinding
    /// Set when macOS refused to register `mainHotkey` because another app owns it.
    @Published var mainHotkeyConflict = false
    /// The rename to Qwixit reset Accessibility trust for an existing user.
    @Published private(set) var needsRenamePermission: Bool

    var onPeekShortcutChanged: ((String) -> Void)?
    var onPaletteTimingChanged: ((Int) -> Void)?
    var onMainHotkeyChanged: ((HotkeyBinding) -> Void)?

    var hasCompletedOnboarding: Bool {
        defaults.bool(forKey: AppPreferenceKey.hasCompletedOnboarding)
    }

    private let accessibility: AccessibilityServicing
    private let checkout: CheckoutOpening
    private let billingStatus: BillingStatusChecking
    private let defaults: UserDefaults
    private var permissionTask: Task<Void, Never>?
    private var billingTask: Task<Void, Never>?
    private var onboardingDemoTask: Task<Void, Never>?
    private var onboardingTapResetTask: Task<Void, Never>?

    init(
        accessibility: AccessibilityServicing,
        checkout: CheckoutOpening = PaddleCheckoutOpener(),
        billingStatus: BillingStatusChecking = BillingStatusClient(),
        defaults: UserDefaults = .standard
    ) {
        self.accessibility = accessibility
        self.checkout = checkout
        self.billingStatus = billingStatus
        self.defaults = defaults
        accessibilityGranted = accessibility.isTrusted
        showSuccess = defaults.object(forKey: AppPreferenceKey.showSuccess) as? Bool ?? true
        animationsEnabled = defaults.object(forKey: AppPreferenceKey.animationsEnabled) as? Bool ?? true
        priorityProcessing = defaults.bool(forKey: AppPreferenceKey.priorityProcessing)
        let preferences = AppPreferences(defaults: defaults)
        appearance = preferences.appearance
#if DEBUG
        developerUsageScenario = preferences.developerUsageScenario
#endif
        remainingActions = preferences.remainingActions
        isUnlimited = preferences.isUnlimited
        billingActivationState = preferences.isUnlimited
            ? .ready
            : (preferences.isBillingActivationPending ? .confirming : .idle)
        peekTargetLanguage = preferences.peekTargetLanguage
        peekSmartDefault = preferences.peekSmartDefault
        peekRememberMode = preferences.peekRememberMode
        peekPrefetch = preferences.peekPrefetch
        peekShortcutKey = "Z"
        paletteDoubleTapMS = defaults.object(forKey: AppPreferenceKey.paletteDoubleTapMS) as? Int ?? 300
        mainHotkey = preferences.mainHotkey
        needsRenamePermission = defaults.bool(forKey: AppPreferenceKey.needsRenamePermission)
            && !accessibility.isTrusted
    }

    func setMainHotkey(_ binding: HotkeyBinding) {
        AppPreferences(defaults: defaults).setMainHotkey(binding)
        mainHotkey = binding
        onMainHotkeyChanged?(binding)
    }

    func restoreDefaultHotkey() {
        setMainHotkey(.defaultMain)
    }

    func stop() {
        permissionTask?.cancel()
        billingTask?.cancel()
        onboardingDemoTask?.cancel()
        onboardingTapResetTask?.cancel()
    }

    func completeOnboarding() {
        defaults.set(true, forKey: AppPreferenceKey.hasCompletedOnboarding)
        if accessibilityGranted { clearRenamePermission() }
    }

    private func clearRenamePermission() {
        defaults.removeObject(forKey: AppPreferenceKey.needsRenamePermission)
        needsRenamePermission = false
    }

    func advanceOnboarding() {
        guard (onboardingStep == 0 ? accessibilityGranted : onboardingDemoPhase == .complete),
              onboardingStep < 2 else { return }
        onboardingStep += 1
        resetOnboardingLevel()
    }

    func handleOnboardingHotkey() {
        guard onboardingDemoPhase == .waiting, !onboardingMenuVisible else { return }
        switch onboardingStep {
        case 1:
            runOnboardingDemo(result: "Hello, I think this sentence sounds weird.")
        case 2:
            registerOnboardingDoubleTap()
        default:
            break
        }
    }

    func updateOnboardingModifiers(option: Bool, command: Bool) {
        onboardingOptionDown = option
        onboardingCommandDown = command
    }

    func moveOnboardingMenuSelection(by delta: Int) {
        guard onboardingMenuVisible else { return }
        onboardingMenuSelection = min(max(onboardingMenuSelection + delta, 0), OnboardingAction.allCases.count - 1)
    }

    func closeOnboardingMenu() {
        guard onboardingMenuVisible else { return }
        onboardingMenuVisible = false
        onboardingLevel2TapCount = 0
    }

    func chooseOnboardingAction(_ action: OnboardingAction) {
        guard onboardingStep == 2, onboardingMenuVisible, onboardingDemoPhase == .waiting else { return }
        onboardingMenuVisible = false
        onboardingMenuSelection = action.rawValue
        runOnboardingDemo(result: action.result)
    }

    func chooseHighlightedOnboardingAction() {
        guard let action = OnboardingAction(rawValue: onboardingMenuSelection) else { return }
        chooseOnboardingAction(action)
    }

    func runOnboardingDemo(result: String) {
        guard onboardingDemoPhase == .waiting else { return }
        onboardingDemoTask?.cancel()
        onboardingDemoPhase = .processing
        onboardingTypedText = ""
        onboardingDemoTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled, let self else { return }
            onboardingDemoPhase = .typing
            var cursor = result.startIndex
            while cursor < result.endIndex {
                guard !Task.isCancelled else { return }
                cursor = result.index(cursor, offsetBy: min(2, result.distance(from: cursor, to: result.endIndex)))
                onboardingTypedText = String(result[..<cursor])
                try? await Task.sleep(for: .milliseconds(22))
            }
            onboardingDemoPhase = .complete
        }
    }

    private func registerOnboardingDoubleTap() {
        onboardingTapResetTask?.cancel()
        onboardingLevel2TapCount += 1
        if onboardingLevel2TapCount >= 2 {
            onboardingLevel2TapCount = 0
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled, let self, onboardingStep == 2,
                      onboardingDemoPhase == .waiting else { return }
                onboardingMenuVisible = true
                onboardingMenuSelection = 0
            }
            return
        }
        onboardingTapResetTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            self?.onboardingLevel2TapCount = 0
        }
    }

    private func resetOnboardingLevel() {
        onboardingDemoTask?.cancel()
        onboardingTapResetTask?.cancel()
        onboardingDemoPhase = .waiting
        onboardingTypedText = ""
        onboardingLevel2TapCount = 0
        onboardingMenuVisible = false
        onboardingMenuSelection = 0
        onboardingOriginalText = onboardingStep == 2
            ? "yo can u send me the file asap pls"
            : "helo i thnik this sentnce sound wierd"
    }

    func refreshAccessibility() {
        accessibilityGranted = accessibility.isTrusted
    }

    func refreshUsage() {
        readCachedUsage()
        startBillingStatusRefresh()
    }

#if DEBUG
    func setDeveloperUsageScenario(_ scenario: DeveloperUsageScenario) {
        defaults.set(scenario.rawValue, forKey: AppPreferenceKey.developerUsageScenario)
        developerUsageScenario = scenario
        readCachedUsage()
        billingActivationState = scenario == .unlimited ? .ready : .idle
    }

    func resetOnboardingForTesting() {
        defaults.removeObject(forKey: AppPreferenceKey.hasCompletedOnboarding)
        restartOnboarding()
    }
#endif

    func restartOnboarding() {
        onboardingStep = 0
        resetOnboardingLevel()
    }

    func requestAccessibility() {
        accessibility.requestPermission()
        pollAccessibilityPermission()
    }

    func openStarterCheckout() {
        if checkout.openStarterCheckout() {
            billingActivationState = .confirming
            checkoutMessage = "Checkout opened. I’ll unlock Unlimited as soon as Paddle confirms it."
            startBillingStatusRefresh()
        } else {
            checkoutMessage = "Could not open the sandbox checkout."
        }
    }

    private func readCachedUsage() {
        let preferences = AppPreferences(defaults: defaults)
        remainingActions = preferences.remainingActions
        isUnlimited = preferences.isUnlimited
        if isUnlimited { billingActivationState = .ready }
    }

    private func startBillingStatusRefresh() {
        billingTask?.cancel()
        let shouldPoll = AppPreferences(defaults: defaults).isBillingActivationPending
        if shouldPoll && !isUnlimited { billingActivationState = .confirming }

        billingTask = Task { [weak self] in
            guard let self else { return }
            let attempts = shouldPoll ? 45 : 1
            for attempt in 0..<attempts {
                guard !Task.isCancelled else { return }
                do {
                    let status = try await billingStatus.fetchStatus()
                    QwixitUsage.record(status, defaults: defaults)
                    readCachedUsage()
                    if status.isUnlimited {
                        checkoutMessage = "Unlimited is ready. Go Qwix something."
                        return
                    }
                } catch {
                    if !shouldPoll { return }
                }

                guard shouldPoll else { return }
                if attempt == 9 { billingActivationState = .delayed }
                try? await Task.sleep(for: .seconds(2))
            }
            if !isUnlimited { billingActivationState = .delayed }
        }
    }

    func pollAccessibilityPermission() {
        permissionTask?.cancel()
        permissionTask = Task { [weak self] in
            for _ in 0..<30 {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, let self else { return }
                accessibilityGranted = accessibility.isTrusted
                if accessibilityGranted {
                    clearRenamePermission()
                    return
                }
            }
        }
    }
}
