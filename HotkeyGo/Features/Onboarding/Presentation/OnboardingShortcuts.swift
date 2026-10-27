struct OnboardingShortcuts {
    let fix: HotkeyBinding
    let actions: HotkeyBinding
    let peek: HotkeyBinding

    static let standard = OnboardingShortcuts(
        fix: .defaultMain,
        actions: .actions,
        peek: .peek
    )
}
