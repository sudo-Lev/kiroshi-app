import AppKit
import XCTest
@testable import Tokiri

@MainActor
final class PopupDismissCoordinatorTests: XCTestCase {
    func testSharedShortcutClosesFrontmostVisiblePopup() {
        let hotkey = PopupHotkeySpy()
        let coordinator = PopupDismissCoordinator(hotkey: hotkey)
        let first = makePanel()
        let second = makePanel()
        defer { first.close(); second.close() }

        var dismissed: [String] = []
        first.orderFrontRegardless()
        coordinator.show(first) {
            dismissed.append("first")
            coordinator.hide(first)
            first.orderOut(nil)
        }
        second.orderFrontRegardless()
        coordinator.show(second) {
            dismissed.append("second")
            coordinator.hide(second)
            second.orderOut(nil)
        }

        XCTAssertNil(hotkey.binding, "Fix already owns the default ⌥⌘X registration")
        XCTAssertTrue(coordinator.dismissTop())
        XCTAssertEqual(dismissed, ["second"])
        XCTAssertTrue(coordinator.dismissTop())
        XCTAssertEqual(dismissed, ["second", "first"])
        XCTAssertFalse(coordinator.dismissTop())
    }

    func testRemappedFixRegistersCloseOnlyWhilePopupIsVisible() {
        let hotkey = PopupHotkeySpy()
        let coordinator = PopupDismissCoordinator(hotkey: hotkey)
        let customFix = HotkeyBinding(keyCode: 0x0F, modifiers: [.control, .shift])
        coordinator.setMainBinding(customFix)
        XCTAssertNil(hotkey.binding)

        let panel = makePanel()
        defer { panel.close() }
        panel.orderFrontRegardless()
        coordinator.show(panel) {
            coordinator.hide(panel)
            panel.orderOut(nil)
        }
        XCTAssertEqual(hotkey.binding, HotkeyCatalog.popupDismiss)

        coordinator.dismissTop()
        XCTAssertNil(hotkey.binding)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 40, y: 40, width: 100, height: 70),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        return panel
    }
}

private final class PopupHotkeySpy: HotKeyManaging {
    private(set) var binding: HotkeyBinding?

    func register(
        keyCode: UInt32,
        modifiers: GlobalHotKey.Modifiers,
        action: @escaping () -> Void
    ) -> Bool {
        binding = HotkeyBinding(keyCode: keyCode, modifiers: modifiers)
        return true
    }

    func unregister() { binding = nil }
}
