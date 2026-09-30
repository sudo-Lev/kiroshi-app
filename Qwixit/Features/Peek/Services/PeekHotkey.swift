import Carbon

final class PeekHotkey {
    private let hotKey: HotKeyManaging

    init(hotKey: HotKeyManaging = GlobalHotKey()) {
        self.hotKey = hotKey
    }

    func start(key: String, action: @escaping () -> Void) {
        let keyCode: UInt32 = switch key.uppercased() {
        case "J": 38
        case "P": 35
        case "L": 37
        default: UInt32(kVK_ANSI_Z)
        }
        hotKey.register(keyCode: keyCode, modifiers: [.option, .command], action: action)
    }

    func stop() {
        hotKey.unregister()
    }
}
