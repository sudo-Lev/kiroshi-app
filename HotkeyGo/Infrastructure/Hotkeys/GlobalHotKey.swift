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

    func matches(_ event: NSEvent) -> Bool {
        var expected: NSEvent.ModifierFlags = []
        if modifiers.contains(.control) { expected.insert(.control) }
        if modifiers.contains(.option) { expected.insert(.option) }
        if modifiers.contains(.shift) { expected.insert(.shift) }
        if modifiers.contains(.command) { expected.insert(.command) }
        let significant: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
        return UInt32(event.keyCode) == keyCode
            && event.modifierFlags.intersection(significant) == expected
    }

    /// ⌥⌘X — fixes the selected text immediately.
    static let defaultMain = HotkeyCatalog.fix

    /// ⌥⌘A — opens the action palette.
    static let actions = HotkeyCatalog.actions

    /// ⌥⌘Z — opens Peek.
    static let peek = HotkeyCatalog.peek

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

    var keySymbol: String { Self.keySymbols[Int(keyCode)] ?? "KEY \(keyCode)" }

    var displayString: String { (modifierSymbols + [keySymbol]).joined() }

    var presentation: ShortcutPresentation {
        ShortcutPresentation(modifiers: modifierSymbols, key: keySymbol)
    }

    private static let keySymbols: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
        kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
        kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
        kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
        kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
        kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Backslash: "\\", kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",",
        kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/", kVK_ANSI_Grave: "`",
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_Escape: "Esc", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_DownArrow: "↓", kVK_UpArrow: "↑", kVK_Home: "Home", kVK_End: "End",
        kVK_PageUp: "Page Up", kVK_PageDown: "Page Down",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15",
        kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20"
    ]
}

enum HotkeyAction: CaseIterable, Equatable {
    case fix
    case actions
    case peek

    var title: String {
        switch self {
        case .fix: "Fix"
        case .actions: "Actions"
        case .peek: "Peek"
        }
    }
}

/// Default shortcuts live here so registration and visible hints cannot drift.
/// User overrides are resolved by SettingsViewModel; popup dismissal stays fixed.
enum HotkeyCatalog {
    static let fix = HotkeyBinding(keyCode: UInt32(kVK_ANSI_X), modifiers: [.option, .command])
    static let actions = HotkeyBinding(keyCode: UInt32(kVK_ANSI_A), modifiers: [.option, .command])
    static let peek = HotkeyBinding(keyCode: UInt32(kVK_ANSI_Z), modifiers: [.option, .command])
    static let popupDismiss = HotkeyBinding(keyCode: UInt32(kVK_ANSI_X), modifiers: [.option, .command])

    static func peekBinding(for key: String) -> HotkeyBinding {
        let keyCode: UInt32 = switch key.uppercased() {
        case "J": UInt32(kVK_ANSI_J)
        case "P": UInt32(kVK_ANSI_P)
        case "L": UInt32(kVK_ANSI_L)
        default: peek.keyCode
        }
        return HotkeyBinding(keyCode: keyCode, modifiers: peek.modifiers)
    }
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
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
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
        guard handlerStatus == noErr else {
            unregister()
            return false
        }
        let status = RegisterEventHotKey(keyCode, modifiers.rawValue, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr else {
            unregister()
            return false
        }
        return true
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
        action = nil
    }

    deinit { unregister() }
}

/// Tracks only interactive transient panels. The most recently frontmost visible
/// panel receives the shared close shortcut, including pinned Peek panels.
@MainActor
final class PopupDismissCoordinator {
    private final class Entry {
        weak var window: NSWindow?
        let dismiss: () -> Void

        init(window: NSWindow, dismiss: @escaping () -> Void) {
            self.window = window
            self.dismiss = dismiss
        }
    }

    private let hotkey: HotKeyManaging
    private var entries: [Entry] = []
    private var mainBinding: HotkeyBinding = .defaultMain

    init(hotkey: HotKeyManaging = GlobalHotKey()) {
        self.hotkey = hotkey
    }

    func setMainBinding(_ binding: HotkeyBinding) {
        mainBinding = binding
        updateRegistration()
    }

    func show(_ window: NSWindow, dismiss: @escaping () -> Void) {
        entries.removeAll { $0.window == nil || $0.window === window }
        entries.append(Entry(window: window, dismiss: dismiss))
        updateRegistration()
    }

    func hide(_ window: NSWindow) {
        entries.removeAll { $0.window == nil || $0.window === window }
        updateRegistration()
    }

    @discardableResult
    func dismissTop() -> Bool {
        entries.removeAll { $0.window?.isVisible != true }
        let ordered = NSApp.orderedWindows
        let target = ordered.compactMap { orderedWindow in
            entries.first { $0.window === orderedWindow }
        }.first ?? entries.last
        guard let target else {
            updateRegistration()
            return false
        }
        target.dismiss()
        return true
    }

    private func updateRegistration() {
        hotkey.unregister()
        entries.removeAll { $0.window?.isVisible != true }
        guard !entries.isEmpty, mainBinding != HotkeyCatalog.popupDismiss else { return }
        _ = hotkey.register(
            keyCode: HotkeyCatalog.popupDismiss.keyCode,
            modifiers: HotkeyCatalog.popupDismiss.modifiers
        ) { [weak self] in
            Task { @MainActor in self?.dismissTop() }
        }
    }
}
