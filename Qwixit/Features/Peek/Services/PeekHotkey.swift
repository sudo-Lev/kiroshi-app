final class PeekHotkey {
    private let hotKey: HotKeyManaging

    init(hotKey: HotKeyManaging = GlobalHotKey()) {
        self.hotKey = hotKey
    }

    func start(key: String, action: @escaping () -> Void) {
        let binding = HotkeyCatalog.peekBinding(for: key)
        hotKey.register(keyCode: binding.keyCode, modifiers: binding.modifiers, action: action)
    }

    func stop() {
        hotKey.unregister()
    }
}
