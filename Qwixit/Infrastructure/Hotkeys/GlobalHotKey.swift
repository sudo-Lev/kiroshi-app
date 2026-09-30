import AppKit
import Carbon

protocol HotKeyManaging: AnyObject {
    /// Returns `false` when macOS refuses the combo, usually because another app owns it.
    @discardableResult
    func register(keyCode: UInt32, modifiers: GlobalHotKey.Modifiers, action: @escaping () -> Void) -> Bool
    func unregister()
}

struct HotkeyBinding: Equatable {
    let keyCode: UInt32
    let modifiers: GlobalHotKey.Modifiers

    /// ⌥⌘X — single press fixes; double press opens the three-action palette.
    static let defaultMain = HotkeyBinding(keyCode: UInt32(kVK_ANSI_X), modifiers: [.option, .command])

    /// Defaults shipped before the rename; stored bindings equal to these move to `defaultMain`.
    static let legacyDefaults = [
        HotkeyBinding(keyCode: UInt32(kVK_ANSI_K), modifiers: [.option]),
        HotkeyBinding(keyCode: UInt32(kVK_ANSI_K), modifiers: [.option, .command])
    ]

    var modifierSymbols: [String] {
        var symbols: [String] = []
        if modifiers.contains(.control) { symbols.append("⌃") }
        if modifiers.contains(.option) { symbols.append("⌥") }
        if modifiers.contains(.shift) { symbols.append("⇧") }
        if modifiers.contains(.command) { symbols.append("⌘") }
        return symbols
    }

    var keySymbol: String { Self.letters[Int(keyCode)] ?? "?" }

    var displayString: String { (modifierSymbols + [keySymbol]).joined() }

    private static let letters: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
        kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
        kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
        kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
        kVK_ANSI_Z: "Z"
    ]
}

final class GlobalHotKey: HotKeyManaging {
    struct Modifiers: OptionSet {
        let rawValue: UInt32
        static let command = Modifiers(rawValue: UInt32(cmdKey))
        static let option = Modifiers(rawValue: UInt32(optionKey))
        static let control = Modifiers(rawValue: UInt32(controlKey))
        static let shift = Modifiers(rawValue: UInt32(shiftKey))
    }

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var action: (() -> Void)?
    private let hotKeyID: EventHotKeyID

    private static let identifierLock = NSLock()
    private static var nextIdentifier: UInt32 = 1

    init() {
        Self.identifierLock.lock()
        let identifier = Self.nextIdentifier
        Self.nextIdentifier &+= 1
        Self.identifierLock.unlock()
        hotKeyID = EventHotKeyID(signature: OSType(0x51574958), id: identifier)
    }

    @discardableResult
    func register(keyCode: UInt32, modifiers: Modifiers, action: @escaping () -> Void) -> Bool {
        unregister()
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            var receivedID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &receivedID
            )
            guard status == noErr,
                  receivedID.signature == owner.hotKeyID.signature,
                  receivedID.id == owner.hotKeyID.id else { return OSStatus(eventNotHandledErr) }
            owner.action?()
            return noErr
        }, 1, &eventType, pointer, &handlerRef)
        let status = RegisterEventHotKey(keyCode, modifiers.rawValue, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        return status == noErr
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }

    deinit { unregister() }
}
