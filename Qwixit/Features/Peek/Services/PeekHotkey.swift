final class PeekHotkey {
    private let hotKey: HotKeyManaging

    init(hotKey: HotKeyManaging = GlobalHotKey()) {
        self.hotKey = hotKey
    }

    @discardableResult
    func start(binding: HotkeyBinding = .peek, action: @escaping () -> Void) -> Bool {
        hotKey.register(keyCode: binding.keyCode, modifiers: binding.modifiers, action: action)
    }

    func start(key: String, action: @escaping () -> Void) {
        _ = start(binding: HotkeyCatalog.peekBinding(for: key), action: action)
    }

    func stop() {
        hotKey.unregister()
    }
}
