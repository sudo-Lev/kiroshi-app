final class ActionHotkey {
    private let hotKey: HotKeyManaging

    init(hotKey: HotKeyManaging = GlobalHotKey()) {
        self.hotKey = hotKey
    }

    @discardableResult
    func start(action: @escaping () -> Void) -> Bool {
        hotKey.register(
            keyCode: HotkeyBinding.actions.keyCode,
            modifiers: HotkeyBinding.actions.modifiers,
            action: action
        )
    }

    func stop() {
        hotKey.unregister()
    }
}
