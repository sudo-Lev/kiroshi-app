import Foundation

protocol APIKeyStoring {
    func apiKey() -> String?
    func saveAPIKey(_ value: String) throws
    func deleteAPIKey() throws
}

struct KeychainAPIKeyStore: APIKeyStoring {
    func apiKey() -> String? { KeychainStore.apiKey() }
    func saveAPIKey(_ value: String) throws { try KeychainStore.saveAPIKey(value) }
    func deleteAPIKey() throws { try KeychainStore.deleteAPIKey() }
}

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published private(set) var accessibilityGranted: Bool
    @Published private(set) var hasAPIKey: Bool
    @Published private(set) var apiKeyMessage: String?
    @Published var apiKeyInput = ""
    @Published var onboardingStep = 0
    @Published var showSuccess: Bool {
        didSet { defaults.set(showSuccess, forKey: AppPreferenceKey.showSuccess) }
    }
    @Published var animationsEnabled: Bool {
        didSet { defaults.set(animationsEnabled, forKey: AppPreferenceKey.animationsEnabled) }
    }
    @Published var priorityProcessing: Bool {
        didSet { defaults.set(priorityProcessing, forKey: AppPreferenceKey.priorityProcessing) }
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
    private let apiKeyStore: APIKeyStoring
    private let defaults: UserDefaults
    private var permissionTask: Task<Void, Never>?

    init(
        accessibility: AccessibilityServicing,
        apiKeyStore: APIKeyStoring,
        defaults: UserDefaults = .standard
    ) {
        self.accessibility = accessibility
        self.apiKeyStore = apiKeyStore
        self.defaults = defaults
        accessibilityGranted = accessibility.isTrusted
        hasAPIKey = apiKeyStore.apiKey() != nil
        showSuccess = defaults.object(forKey: AppPreferenceKey.showSuccess) as? Bool ?? true
        animationsEnabled = defaults.object(forKey: AppPreferenceKey.animationsEnabled) as? Bool ?? true
        priorityProcessing = defaults.bool(forKey: AppPreferenceKey.priorityProcessing)
        let preferences = AppPreferences(defaults: defaults)
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
        guard onboardingStep < 2 else { return }
        onboardingStep += 1
    }

    func refreshAccessibility() {
        accessibilityGranted = accessibility.isTrusted
    }

    func requestAccessibility() {
        accessibility.requestPermission()
        pollAccessibilityPermission()
    }

    func saveAPIKey() {
        do {
            try apiKeyStore.saveAPIKey(apiKeyInput)
            hasAPIKey = true
            apiKeyInput = ""
            apiKeyMessage = "Connected securely"
        } catch {
            apiKeyMessage = error.localizedDescription
        }
    }

    func removeAPIKey() {
        do {
            try apiKeyStore.deleteAPIKey()
            hasAPIKey = false
            apiKeyMessage = "API key removed"
        } catch {
            apiKeyMessage = error.localizedDescription
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
