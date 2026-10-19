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
    @Published private(set) var mainHotkey: HotkeyBinding
    /// Set when macOS refused to register `mainHotkey` because another app owns it.
    @Published var mainHotkeyConflict = false
    /// Set when macOS refuses the fixed ⌥⌘A Actions shortcut.
    @Published var actionHotkeyConflict = false
    /// The rename to Qwixit reset Accessibility trust for an existing user.
    @Published private(set) var needsRenamePermission: Bool

    var onPeekShortcutChanged: ((String) -> Void)?
    var onMainHotkeyChanged: ((HotkeyBinding) -> Void)?
    var onAppearanceChanged: ((AppAppearance) -> Void)?

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
#if DEBUG
        developerUsageScenario = preferences.developerUsageScenario
#endif
        remainingActions = preferences.remainingActions
        isAdvanced = preferences.isAdvanced
        peekTargetLanguage = preferences.peekTargetLanguage
        peekSmartDefault = preferences.peekSmartDefault
        peekRememberMode = preferences.peekRememberMode
        peekPrefetch = preferences.peekPrefetch
        peekShortcutKey = HotkeyCatalog.peek.keySymbol
        mainHotkey = preferences.mainHotkey
        needsRenamePermission = defaults.bool(forKey: AppPreferenceKey.needsRenamePermission)
            && !accessibility.isTrusted
        usageObserver = NotificationCenter.default.addObserver(
            forName: QwixitUsage.didChange,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.readCachedUsage() }
        }
    }

    deinit {
        if let usageObserver { NotificationCenter.default.removeObserver(usageObserver) }
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
        startBillingStatusRefresh()
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
        // A window appearing or the app reactivating must not replace the
        // checkout poll with a single request before Paddle's webhook arrives.
        guard !isPollingAfterCheckout else { return }
        billingTask?.cancel()
        isPollingAfterCheckout = shouldPoll

        billingTask = Task { [weak self] in
            guard let self else { return }
            defer { if shouldPoll { isPollingAfterCheckout = false } }
            let attempts = shouldPoll ? 100 : 1
            for attempt in 0..<attempts {
                guard !Task.isCancelled else { return }
                do {
                    let status = try await billingStatus.fetchStatus()
                    guard !Task.isCancelled else { return }
                    QwixitUsage.record(status, defaults: defaults)
                    readCachedUsage()
                    if status.isAdvanced {
                        return
                    }
                } catch {
                    if !shouldPoll { return }
                }

                guard shouldPoll, attempt < attempts - 1 else { return }
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
