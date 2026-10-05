import Foundation

enum AppPreferenceKey {
    static let showSuccess = "showSuccess"
    static let animationsEnabled = "animationsEnabled"
    static let priorityProcessing = "priorityProcessing"
    static let appearance = "appearance"
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    static let paletteDoubleTapMS = "palette.doubleTapMS"
    static let mainHotkeyKeyCode = "hotkey.main.keyCode"
    static let mainHotkeyModifiers = "hotkey.main.modifiers"
    static let legacyMigrationDone = "migration.legacyImportDone"
    static let needsRenamePermission = "migration.needsRenamePermission"
    static let quotaRemaining = "quota.remaining"
    static let quotaPlan = "quota.plan"
    static let billingActivationStartedAt = "billing.activationStartedAt"
#if DEBUG
    static let developerUsageScenario = "developer.usageScenario"
#endif

    /// Every app-owned key; used when carrying settings over from the pre-rename build.
    static var all: [String] {
        var keys = [
            showSuccess, animationsEnabled, priorityProcessing, appearance, hasCompletedOnboarding,
            paletteDoubleTapMS, mainHotkeyKeyCode, mainHotkeyModifiers, quotaRemaining, quotaPlan,
            billingActivationStartedAt
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

#if DEBUG
enum DeveloperUsageScenario: String, CaseIterable, Identifiable {
    case live
    case lastFree
    case limitReached
    case unlimited

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live: "Live"
        case .lastFree: "29 / 30"
        case .limitReached: "30 / 30"
        case .unlimited: "Unlimited"
        }
    }

    var detail: String {
        switch self {
        case .live: "Use the real Worker response."
        case .lastFree: "Simulate one free action remaining. Resets to Live on launch."
        case .limitReached: "Blocks AI requests to preview the paywall. Resets to Live on launch."
        case .unlimited: "Preview Unlimited UI only. Resets to Live on launch."
        }
    }
}
#endif

enum PeekPreferenceKey {
    static let shortcutKey = "peek.shortcutKey"
    static let targetLanguage = "peek.targetLanguage"
    static let smartDefault = "peek.smartDefault"
    static let rememberMode = "peek.rememberMode"
    static let prefetch = "peek.prefetch"
    static let lastMode = "peek.lastMode"
    static let lastLength = "peek.lastLength"

    static let all = [shortcutKey, targetLanguage, smartDefault, rememberMode, prefetch, lastMode, lastLength]
}

struct AppPreferences {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var showSuccess: Bool { bool(for: AppPreferenceKey.showSuccess, default: true) }
    var animationsEnabled: Bool { bool(for: AppPreferenceKey.animationsEnabled, default: true) }
    var appearance: AppAppearance {
        defaults.string(forKey: AppPreferenceKey.appearance)
            .flatMap(AppAppearance.init(rawValue:))
            ?? .light
    }
    var remainingActions: Int? {
#if DEBUG
        switch developerUsageScenario {
        case .live: break
        case .lastFree: return 1
        case .limitReached: return 0
        case .unlimited: return nil
        }
#endif
        return defaults.object(forKey: AppPreferenceKey.quotaRemaining) as? Int
    }

    var isUnlimited: Bool {
#if DEBUG
        switch developerUsageScenario {
        case .live, .lastFree, .limitReached: break
        case .unlimited: return true
        }
#endif
        return defaults.string(forKey: AppPreferenceKey.quotaPlan) == "unlimited"
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
    var isBillingActivationPending: Bool {
        guard !isUnlimited,
              let startedAt = defaults.object(forKey: AppPreferenceKey.billingActivationStartedAt) as? Date else {
            return false
        }
        return Date().timeIntervalSince(startedAt) < 15 * 60
    }

    func markBillingActivationStarted() {
        defaults.set(Date(), forKey: AppPreferenceKey.billingActivationStartedAt)
    }

    func clearBillingActivation() {
        defaults.removeObject(forKey: AppPreferenceKey.billingActivationStartedAt)
    }

    var peekTargetLanguage: String {
        defaults.string(forKey: PeekPreferenceKey.targetLanguage)
            ?? Locale.preferredLanguages.first.flatMap { Locale(identifier: $0).language.languageCode?.identifier }
            ?? "en"
    }
    var peekSmartDefault: Bool { bool(for: PeekPreferenceKey.smartDefault, default: true) }
    var peekRememberMode: Bool { bool(for: PeekPreferenceKey.rememberMode, default: true) }
    var peekPrefetch: Bool { bool(for: PeekPreferenceKey.prefetch, default: true) }

    var mainHotkey: HotkeyBinding {
        guard let keyCode = defaults.object(forKey: AppPreferenceKey.mainHotkeyKeyCode) as? Int,
              let modifiers = defaults.object(forKey: AppPreferenceKey.mainHotkeyModifiers) as? Int else {
            return .defaultMain
        }
        return HotkeyBinding(keyCode: UInt32(keyCode), modifiers: .init(rawValue: UInt32(modifiers)))
    }

    func setMainHotkey(_ binding: HotkeyBinding?) {
        guard let binding, binding != .defaultMain else {
            defaults.removeObject(forKey: AppPreferenceKey.mainHotkeyKeyCode)
            defaults.removeObject(forKey: AppPreferenceKey.mainHotkeyModifiers)
            return
        }
        defaults.set(Int(binding.keyCode), forKey: AppPreferenceKey.mainHotkeyKeyCode)
        defaults.set(Int(binding.modifiers.rawValue), forKey: AppPreferenceKey.mainHotkeyModifiers)
    }

    private func bool(for key: String, default defaultValue: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? defaultValue
    }
}
