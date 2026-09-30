import Foundation

enum AppPreferenceKey {
    static let showSuccess = "showSuccess"
    static let animationsEnabled = "animationsEnabled"
    static let priorityProcessing = "priorityProcessing"
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    static let paletteDoubleTapMS = "palette.doubleTapMS"
    static let mainHotkeyKeyCode = "hotkey.main.keyCode"
    static let mainHotkeyModifiers = "hotkey.main.modifiers"
    static let legacyMigrationDone = "migration.legacyImportDone"
    static let needsRenamePermission = "migration.needsRenamePermission"

    /// Every app-owned key; used when carrying settings over from the pre-rename build.
    static let all = [
        showSuccess, animationsEnabled, priorityProcessing, hasCompletedOnboarding,
        paletteDoubleTapMS, mainHotkeyKeyCode, mainHotkeyModifiers
    ] + PeekPreferenceKey.all
}

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
