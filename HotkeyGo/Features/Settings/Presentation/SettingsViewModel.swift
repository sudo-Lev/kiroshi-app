import Foundation

protocol CheckoutOpening {
    func openStarterCheckout() -> Bool
}

@MainActor
final class SettingsViewModel: ObservableObject {
    let onboarding: OnboardingModel
    @Published private(set) var accessibilityGranted: Bool
    @Published private(set) var remainingActions: Int?
    @Published private(set) var isAdvanced: Bool
#if DEBUG
    @Published private(set) var developerUsageScenario: DeveloperUsageScenario
#endif
    @Published var showSuccess: Bool {
        didSet { defaults.set(showSuccess, forKey: AppPreferenceKey.showSuccess) }
    }
    @Published var reviewBeforeApplying: Bool {
        didSet { defaults.set(reviewBeforeApplying, forKey: AppPreferenceKey.reviewBeforeApplying) }
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
    @Published var aiProvider: HotkeyGoAIProvider {
        didSet { defaults.set(aiProvider.rawValue, forKey: AppPreferenceKey.aiProvider) }
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
    @Published private(set) var mainHotkey: HotkeyBinding
    @Published private(set) var actionsHotkey: HotkeyBinding
    @Published private(set) var peekHotkey: HotkeyBinding
    /// Set when macOS refused to register `mainHotkey` because another app owns it.
    @Published var mainHotkeyConflict = false
    /// Set when macOS refused to register `actionsHotkey` because another app owns it.
    @Published var actionHotkeyConflict = false
    /// Set when macOS refused to register `peekHotkey` because another app owns it.
    @Published var peekHotkeyConflict = false
    /// The new hotkeygo app identity can require Accessibility approval again.
    @Published private(set) var needsRenamePermission: Bool

    /// Registers the proposed binding before it becomes the saved setting.
    var onPeekHotkeyChanged: ((HotkeyBinding) -> Bool)?
    var onActionHotkeyChanged: ((HotkeyBinding) -> Bool)?
    var onMainHotkeyChanged: ((HotkeyBinding) -> Bool)?
    var hasCompletedOnboarding: Bool {
        defaults.bool(forKey: AppPreferenceKey.hasCompletedOnboarding)
    }

    private let accessibility: AccessibilityServicing
    private let checkout: CheckoutOpening
    private let billingStatus: BillingStatusChecking
    private let billingPollInterval: Duration
    private let defaults: UserDefaults
    private var permissionTask: Task<Void, Never>?
    private var billingTask: Task<Void, Never>?
    private var billingRefreshGeneration = 0
    private var isPollingAfterCheckout = false
    private var usageObserver: NSObjectProtocol?

    init(
        accessibility: AccessibilityServicing,
        checkout: CheckoutOpening = PaddleCheckoutOpener(),
        billingStatus: BillingStatusChecking = BillingStatusClient(),
        billingPollInterval: Duration = .seconds(2),
        defaults: UserDefaults = .standard
    ) {
        self.accessibility = accessibility
        onboarding = OnboardingModel(accessibility: accessibility)
        self.checkout = checkout
        self.billingStatus = billingStatus
        self.billingPollInterval = billingPollInterval
        self.defaults = defaults
        accessibilityGranted = accessibility.isTrusted
        showSuccess = defaults.object(forKey: AppPreferenceKey.showSuccess) as? Bool ?? true
        reviewBeforeApplying = AppPreferences(defaults: defaults).reviewBeforeApplying
        animationsEnabled = defaults.object(forKey: AppPreferenceKey.animationsEnabled) as? Bool ?? true
        priorityProcessing = defaults.bool(forKey: AppPreferenceKey.priorityProcessing)
        let preferences = AppPreferences(defaults: defaults)
        appearance = preferences.appearance
        aiProvider = preferences.aiProvider
#if DEBUG
        developerUsageScenario = preferences.developerUsageScenario
#endif
        remainingActions = preferences.remainingActions
        isAdvanced = preferences.isAdvanced
        peekTargetLanguage = preferences.peekTargetLanguage
        peekSmartDefault = preferences.peekSmartDefault
        peekRememberMode = preferences.peekRememberMode
        peekPrefetch = preferences.peekPrefetch
        mainHotkey = preferences.mainHotkey
        actionsHotkey = preferences.actionsHotkey
        peekHotkey = preferences.peekHotkey
        needsRenamePermission = defaults.bool(forKey: AppPreferenceKey.needsRenamePermission)
            && !accessibility.isTrusted
        usageObserver = NotificationCenter.default.addObserver(
            forName: HotkeyGoUsage.didChange,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.readCachedUsage() }
        }
    }

    deinit {
        if let usageObserver { NotificationCenter.default.removeObserver(usageObserver) }
    }

    @discardableResult
    func setHotkey(_ binding: HotkeyBinding, for action: HotkeyAction) -> Bool {
        guard (0...127).contains(Int(binding.keyCode)), !binding.modifiers.isEmpty else { return false }

        let current: [(HotkeyAction, HotkeyBinding)] = [
            (.fix, mainHotkey), (.actions, actionsHotkey), (.peek, peekHotkey)
        ]
        guard !current.contains(where: { $0.0 != action && $0.1 == binding }) else { return false }
        // ⌥⌘X remains the shared popup-dismiss shortcut when Fix is remapped.
        guard action == .fix || binding != HotkeyCatalog.popupDismiss else { return false }
        if current.first(where: { $0.0 == action })?.1 == binding { return true }

        let register: ((HotkeyBinding) -> Bool)? = switch action {
        case .fix: onMainHotkeyChanged
        case .actions: onActionHotkeyChanged
        case .peek: onPeekHotkeyChanged
        }
        guard register?(binding) ?? true else { return false }

        let preferences = AppPreferences(defaults: defaults)
        switch action {
        case .fix:
            preferences.setMainHotkey(binding)
            mainHotkey = binding
        case .actions:
            preferences.setActionsHotkey(binding)
            actionsHotkey = binding
        case .peek:
            preferences.setPeekHotkey(binding)
            peekHotkey = binding
        }
        return true
    }

    func restoreDefaultHotkey(for action: HotkeyAction) {
        let binding: HotkeyBinding = switch action {
        case .fix: .defaultMain
        case .actions: .actions
        case .peek: .peek
        }
        _ = setHotkey(binding, for: action)
    }

    func setMainHotkey(_ binding: HotkeyBinding) {
        _ = setHotkey(binding, for: .fix)
    }

    func restoreDefaultHotkey() {
        restoreDefaultHotkey(for: .fix)
    }

    func stop() {
        permissionTask?.cancel()
        billingRefreshGeneration += 1
        billingTask?.cancel()
        isPollingAfterCheckout = false
        onboarding.stop()
    }

    func completeOnboarding() {
        defaults.set(true, forKey: AppPreferenceKey.hasCompletedOnboarding)
        if accessibilityGranted { clearRenamePermission() }
    }

    private func clearRenamePermission() {
        defaults.removeObject(forKey: AppPreferenceKey.needsRenamePermission)
        needsRenamePermission = false
    }

    func refreshAccessibility() {
        accessibilityGranted = accessibility.isTrusted
    }

    func refreshUsage() {
        readCachedUsage()
        startBillingStatusRefresh(shouldPoll: isPollingAfterCheckout)
    }

#if DEBUG
    func setDeveloperUsageScenario(_ scenario: DeveloperUsageScenario) {
        defaults.set(scenario.rawValue, forKey: AppPreferenceKey.developerUsageScenario)
        developerUsageScenario = scenario
        readCachedUsage()
    }

    func resetOnboardingForTesting() {
        defaults.removeObject(forKey: AppPreferenceKey.hasCompletedOnboarding)
        restartOnboarding()
    }
#endif

    func restartOnboarding() {
        onboarding.restart()
    }

    func requestAccessibility() {
        accessibility.requestPermission()
        pollAccessibilityPermission()
    }

    func openStarterCheckout() {
        if checkout.openStarterCheckout() {
            startBillingStatusRefresh(shouldPoll: true)
        }
    }

    private func readCachedUsage() {
        let preferences = AppPreferences(defaults: defaults)
        remainingActions = preferences.remainingActions
        isAdvanced = preferences.isAdvanced
    }

    private func startBillingStatusRefresh(shouldPoll: Bool = false) {
        // Foreground, menu, and Settings refreshes should check immediately
        // without replacing an active checkout poll with a one-shot request.
        let keepPolling = shouldPoll || isPollingAfterCheckout
        billingRefreshGeneration += 1
        let generation = billingRefreshGeneration
        billingTask?.cancel()
        isPollingAfterCheckout = keepPolling

        billingTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if generation == billingRefreshGeneration { isPollingAfterCheckout = false }
            }
            let attempts = keepPolling ? 100 : 1
            for attempt in 0..<attempts {
                guard !Task.isCancelled else { return }
                do {
                    let status = try await billingStatus.fetchStatus()
                    guard !Task.isCancelled else { return }
                    HotkeyGoUsage.record(status, defaults: defaults)
                    readCachedUsage()
                    if status.isAdvanced {
                        return
                    }
                } catch {
                    if !keepPolling { return }
                }

                guard keepPolling, attempt < attempts - 1 else { return }
                // Keep checking while checkout is open, but ease off if the
                // customer needs more than a minute to complete payment.
                let interval = attempt < 45 ? billingPollInterval : .seconds(10)
                do { try await Task.sleep(for: interval) }
                catch { return }
            }
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
