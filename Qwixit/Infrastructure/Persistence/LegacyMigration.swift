import Foundation

/// One-time import of settings from the app's previous name (Kiroshi, `com.kiroshi.mac`).
/// This is the only place allowed to reference the old identifiers.
enum LegacyMigration {
    static let legacyBundleIdentifier = "com.kiroshi.mac"
    static let renameNotice = "Qwixit is the new name of Kiroshi. macOS needs you to allow Accessibility once more."

    /// Runs once per install. Returns `true` when data from the old build was found and carried over.
    @discardableResult
    static func run(
        defaults: UserDefaults = .standard,
        legacyDefaults: UserDefaults? = UserDefaults(suiteName: legacyBundleIdentifier),
        isAccessibilityTrusted: Bool
    ) -> Bool {
        guard !defaults.bool(forKey: AppPreferenceKey.legacyMigrationDone) else { return false }
        defer { defaults.set(true, forKey: AppPreferenceKey.legacyMigrationDone) }

        let importedDefaults = legacyDefaults.map { migrateDefaults(from: $0, to: defaults) } ?? false
        migrateHotkey(defaults: defaults)

        // Accessibility trust is tied to the bundle ID, so the rename resets it.
        if importedDefaults && !isAccessibilityTrusted {
            defaults.set(true, forKey: AppPreferenceKey.needsRenamePermission)
        }
        return importedDefaults
    }

    private static func migrateDefaults(from legacy: UserDefaults, to defaults: UserDefaults) -> Bool {
        var found = false
        for key in AppPreferenceKey.all {
            guard let value = legacy.object(forKey: key) else { continue }
            found = true
            if defaults.object(forKey: key) == nil { defaults.set(value, forKey: key) }
            legacy.removeObject(forKey: key)
        }
        return found
    }

    /// Stored bindings that equal an old default follow the new default; custom bindings are kept.
    static func migrateHotkey(defaults: UserDefaults) {
        let preferences = AppPreferences(defaults: defaults)
        if HotkeyBinding.legacyDefaults.contains(preferences.mainHotkey) {
            preferences.setMainHotkey(nil)
        }
    }
}
