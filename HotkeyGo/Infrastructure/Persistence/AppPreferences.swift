import Foundation

enum AppPreferenceKey {
    static let showSuccess = "showSuccess"
    static let reviewBeforeApplying = "reviewBeforeApplying"
    static let animationsEnabled = "animationsEnabled"
    static let priorityProcessing = "priorityProcessing"
    static let appearance = "appearance"
    static let aiProvider = "aiProvider"
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    static let mainHotkeyKeyCode = "hotkey.main.keyCode"
    static let mainHotkeyModifiers = "hotkey.main.modifiers"
    static let actionsHotkeyKeyCode = "hotkey.actions.keyCode"
    static let actionsHotkeyModifiers = "hotkey.actions.modifiers"
    static let legacyMigrationDone = "migration.legacyImportDone"
    static let needsRenamePermission = "migration.needsRenamePermission"
    static let quotaRemaining = "quota.remaining"
    static let quotaPlan = "quota.plan"
    static let quotaPeriod = "quota.period"
#if DEBUG
    static let developerUsageScenario = "developer.usageScenario"
#endif

    /// Every app-owned key; used when carrying settings over from the pre-rename build.
    static var all: [String] {
        var keys = [
            showSuccess, reviewBeforeApplying, animationsEnabled, priorityProcessing, appearance, aiProvider, hasCompletedOnboarding,
            mainHotkeyKeyCode, mainHotkeyModifiers, actionsHotkeyKeyCode, actionsHotkeyModifiers,
            quotaRemaining, quotaPlan,
            quotaPeriod
        ] + PeekPreferenceKey.all
#if DEBUG
        keys.append(developerUsageScenario)
#endif
        return keys
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum HotkeyGoAIProvider: String, CaseIterable, Identifiable {
    case openAI = "openai"
    case anthropic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAI: "GPT-5.6 Luna"
        case .anthropic: "Claude Haiku 5.5"
        }
    }
}

#if DEBUG
enum DeveloperUsageScenario: String, CaseIterable, Identifiable {
    case live
    case limitReached
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live: "Live"
        case .limitReached: "30 / 30"
        case .advanced: "Advanced"
        }
    }

    var detail: String {
        switch self {
        case .live: "Use the real Worker response."
        case .limitReached: "Blocks AI requests to preview the paywall. Resets to Live on launch."
        case .advanced: "Preview Advanced UI only. Resets to Live on launch."
        }
    }
}
#endif

enum PeekPreferenceKey {
    static let hotkeyKeyCode = "peek.hotkey.keyCode"
    static let hotkeyModifiers = "peek.hotkey.modifiers"
    /// Pre-full-shortcut preference retained for upgrades from builds that stored only a key.
    static let shortcutKey = "peek.shortcutKey"
    static let targetLanguage = "peek.targetLanguage"
    static let smartDefault = "peek.smartDefault"
    static let rememberMode = "peek.rememberMode"
    static let prefetch = "peek.prefetch"
    static let lastMode = "peek.lastMode"
    static let lastLength = "peek.lastLength"

    static let all = [hotkeyKeyCode, hotkeyModifiers, shortcutKey, targetLanguage, smartDefault, rememberMode, prefetch, lastMode, lastLength]
}

struct AppPreferences {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var showSuccess: Bool { bool(for: AppPreferenceKey.showSuccess, default: true) }
    var reviewBeforeApplying: Bool { bool(for: AppPreferenceKey.reviewBeforeApplying, default: false) }
    var animationsEnabled: Bool { bool(for: AppPreferenceKey.animationsEnabled, default: true) }
    var appearance: AppAppearance {
        defaults.string(forKey: AppPreferenceKey.appearance)
            .flatMap(AppAppearance.init(rawValue:))
            ?? .light
    }
    var aiProvider: HotkeyGoAIProvider {
        defaults.string(forKey: AppPreferenceKey.aiProvider)
            .flatMap(HotkeyGoAIProvider.init(rawValue:))
            ?? .openAI
    }
    var remainingActions: Int? {
#if DEBUG
        switch developerUsageScenario {
        case .live: break
        case .limitReached: return 0
        case .advanced: return nil
        }
#endif
        return defaults.object(forKey: AppPreferenceKey.quotaRemaining) as? Int
    }

    var isAdvanced: Bool {
#if DEBUG
        switch developerUsageScenario {
        case .live, .limitReached: break
        case .advanced: return true
        }
#endif
        return HotkeyGoUsage.isAdvancedPlan(defaults.string(forKey: AppPreferenceKey.quotaPlan))
    }

#if DEBUG
    var developerUsageScenario: DeveloperUsageScenario {
        defaults.string(forKey: AppPreferenceKey.developerUsageScenario)
            .flatMap(DeveloperUsageScenario.init(rawValue:))
            ?? .live
    }

    static func resetDeveloperOverrides(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: AppPreferenceKey.developerUsageScenario)
    }
#endif
    var peekTargetLanguage: String {
        defaults.string(forKey: PeekPreferenceKey.targetLanguage)
            ?? Locale.preferredLanguages.first.flatMap { Locale(identifier: $0).language.languageCode?.identifier }
            ?? "en"
    }
    var peekSmartDefault: Bool { bool(for: PeekPreferenceKey.smartDefault, default: true) }
    var peekRememberMode: Bool { bool(for: PeekPreferenceKey.rememberMode, default: true) }
    var peekPrefetch: Bool { bool(for: PeekPreferenceKey.prefetch, default: true) }

    var mainHotkey: HotkeyBinding {
        hotkey(
            keyCodeKey: AppPreferenceKey.mainHotkeyKeyCode,
            modifiersKey: AppPreferenceKey.mainHotkeyModifiers,
            default: .defaultMain
        )
    }

    func setMainHotkey(_ binding: HotkeyBinding?) {
        setHotkey(
            binding,
            default: .defaultMain,
            keyCodeKey: AppPreferenceKey.mainHotkeyKeyCode,
            modifiersKey: AppPreferenceKey.mainHotkeyModifiers
        )
    }

    var actionsHotkey: HotkeyBinding {
        hotkey(
            keyCodeKey: AppPreferenceKey.actionsHotkeyKeyCode,
            modifiersKey: AppPreferenceKey.actionsHotkeyModifiers,
            default: .actions
        )
    }

    func setActionsHotkey(_ binding: HotkeyBinding?) {
        setHotkey(
            binding,
            default: .actions,
            keyCodeKey: AppPreferenceKey.actionsHotkeyKeyCode,
            modifiersKey: AppPreferenceKey.actionsHotkeyModifiers
        )
    }

    var peekHotkey: HotkeyBinding {
        let configured = hotkey(
            keyCodeKey: PeekPreferenceKey.hotkeyKeyCode,
            modifiersKey: PeekPreferenceKey.hotkeyModifiers,
            default: .peek
        )
        if defaults.object(forKey: PeekPreferenceKey.hotkeyKeyCode) != nil,
           defaults.object(forKey: PeekPreferenceKey.hotkeyModifiers) != nil {
            return configured
        }
        if let legacyKey = defaults.string(forKey: PeekPreferenceKey.shortcutKey) {
            return HotkeyCatalog.peekBinding(for: legacyKey)
        }
        return .peek
    }

    func setPeekHotkey(_ binding: HotkeyBinding?) {
        setHotkey(
            binding,
            default: .peek,
            keyCodeKey: PeekPreferenceKey.hotkeyKeyCode,
            modifiersKey: PeekPreferenceKey.hotkeyModifiers
        )
        defaults.removeObject(forKey: PeekPreferenceKey.shortcutKey)
    }

    private func hotkey(keyCodeKey: String, modifiersKey: String, default fallback: HotkeyBinding) -> HotkeyBinding {
        guard let keyCode = defaults.object(forKey: keyCodeKey) as? Int,
              let modifiers = defaults.object(forKey: modifiersKey) as? Int,
              (0...127).contains(keyCode),
              modifiers > 0 else {
            return fallback
        }
        return HotkeyBinding(keyCode: UInt32(keyCode), modifiers: .init(rawValue: UInt32(modifiers)))
    }

    private func setHotkey(
        _ binding: HotkeyBinding?,
        default fallback: HotkeyBinding,
        keyCodeKey: String,
        modifiersKey: String
    ) {
        guard let binding, binding != fallback else {
            defaults.removeObject(forKey: keyCodeKey)
            defaults.removeObject(forKey: modifiersKey)
            return
        }
        defaults.set(Int(binding.keyCode), forKey: keyCodeKey)
        defaults.set(Int(binding.modifiers.rawValue), forKey: modifiersKey)
    }

    private func bool(for key: String, default defaultValue: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? defaultValue
    }
}
