final class ActionHotkey {
    private let hotKey: HotKeyManaging

    init(hotKey: HotKeyManaging = GlobalHotKey()) {
        self.hotKey = hotKey
    }

    @discardableResult
    func start(binding: HotkeyBinding = .actions, action: @escaping () -> Void) -> Bool {
        hotKey.register(
            keyCode: binding.keyCode,
            modifiers: binding.modifiers,
            action: action
        )
    }

    func stop() {
        hotKey.unregister()
    }
}
