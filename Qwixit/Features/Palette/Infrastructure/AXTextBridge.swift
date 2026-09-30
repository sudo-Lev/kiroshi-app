import AppKit
import ApplicationServices

final class PaletteCapture {
    let element: AXUIElement?
    let text: String
    let range: CFRange?
    let bounds: CGRect?
    let fallbackPoint: CGPoint

    init(element: AXUIElement?, text: String, range: CFRange?, bounds: CGRect?, fallbackPoint: CGPoint) {
        self.element = element
        self.text = text
        self.range = range
        self.bounds = bounds
        self.fallbackPoint = fallbackPoint
    }
}

@MainActor
final class AXTextBridge {
    private struct UndoEntry {
        let element: AXUIElement?
        let range: CFRange?
        let previousText: String
        let usesSystemUndo: Bool
    }

    private var undoStack: [UndoEntry] = []

    func capture() async -> PaletteCapture? {
        let fallbackPoint = NSEvent.mouseLocation
        let element = focusedElement()
        var selectedRange: CFRange?
        var bounds: CGRect?

        if let element {
            selectedRange = range(of: element)
            bounds = selectedRange.flatMap { selectionBounds(element: element, range: $0) }
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success,
               let text = value as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return PaletteCapture(element: element, text: text, range: selectedRange, bounds: bounds, fallbackPoint: fallbackPoint)
            }
        }

        guard let text = await copySelection(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return PaletteCapture(element: element, text: text, range: selectedRange, bounds: bounds, fallbackPoint: fallbackPoint)
    }

    func replace(_ capture: PaletteCapture, with text: String) async -> Bool {
        restoreFocus(capture)
        // Web frameworks often keep an input's value in JavaScript state. Writing
        // AXSelectedText can report success without dispatching an input event, so
        // React/Vue then render the old value back. A real paste goes through the
        // browser's editing pipeline and keeps the DOM and framework state aligned.
        if let element = capture.element, isInsideWebArea(element) {
            let pasted = await paste(text)
            if pasted {
                undoStack.append(UndoEntry(element: element, range: nil, previousText: capture.text, usesSystemUndo: true))
            }
            return pasted
        }
        if let element = capture.element,
           AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success {
            let undoRange = capture.range.map { CFRange(location: $0.location, length: text.utf16.count) }
            undoStack.append(UndoEntry(element: element, range: undoRange, previousText: capture.text, usesSystemUndo: false))
            return true
        }
        let pasted = await paste(text)
        if pasted { undoStack.append(UndoEntry(element: capture.element, range: nil, previousText: capture.text, usesSystemUndo: true)) }
        return pasted
    }

    func insert(_ capture: PaletteCapture, text: String) async -> Bool {
        let insertion = "\n" + text
        restoreFocus(capture)
        if let element = capture.element, isInsideWebArea(element) {
            if let range = capture.range {
                var caret = CFRange(location: range.location + range.length, length: 0)
                if let caretValue = AXValueCreate(.cfRange, &caret) {
                    AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, caretValue)
                }
            }
            let pasted = await paste(insertion)
            if pasted {
                undoStack.append(UndoEntry(element: element, range: nil, previousText: "", usesSystemUndo: true))
            }
            return pasted
        }
        if let element = capture.element, let range = capture.range {
            var caret = CFRange(location: range.location + range.length, length: 0)
            if let caretValue = AXValueCreate(.cfRange, &caret),
               AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, caretValue) == .success,
               AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, insertion as CFTypeRef) == .success {
                undoStack.append(UndoEntry(
                    element: element,
                    range: CFRange(location: caret.location, length: insertion.utf16.count),
                    previousText: "",
                    usesSystemUndo: false
                ))
                return true
            }
        }
        let pasted = await paste(insertion)
        if pasted { undoStack.append(UndoEntry(element: capture.element, range: nil, previousText: "", usesSystemUndo: true)) }
        return pasted
    }

    func undo() async {
        guard let entry = undoStack.popLast() else { return }
        if entry.usesSystemUndo {
            _ = await postCommandKey(virtualKey: 6)
            return
        }
        guard let element = entry.element, var range = entry.range,
              let rangeValue = AXValueCreate(.cfRange, &range) else { return }
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        guard AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeValue) == .success else { return }
        AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, entry.previousText as CFTypeRef)
    }

    func restoreFocus(_ capture: PaletteCapture) {
        guard let element = capture.element else { return }
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

    private func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value else { return nil }
        return (value as! AXUIElement)
    }

    private func range(of element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        return AXValueGetValue(value as! AXValue, .cfRange, &range) && range.length > 0 ? range : nil
    }

    private func selectionBounds(element: AXUIElement, range: CFRange) -> CGRect? {
        var mutableRange = range
        guard let rangeValue = AXValueCreate(.cfRange, &mutableRange) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &value
        ) == .success, let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        return AXValueGetValue(value as! AXValue, .cgRect, &rect) ? rect : nil
    }

    private func isInsideWebArea(_ element: AXUIElement) -> Bool {
        var current = element
        for _ in 0..<12 {
            var roleValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &roleValue) == .success,
               roleValue as? String == "AXWebArea" {
                return true
            }

            var parentValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentValue) == .success,
                  let parentValue else { break }
            current = parentValue as! AXUIElement
        }
        return false
    }

    private func copySelection() async -> String? {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardArchive(pasteboard)
        pasteboard.clearContents()
        let changeCount = pasteboard.changeCount
        guard await postCommandKey(virtualKey: 8) else {
            snapshot.restore(to: pasteboard)
            return nil
        }
        try? await Task.sleep(for: .milliseconds(125))
        let value = pasteboard.changeCount == changeCount ? nil : pasteboard.string(forType: .string)
        snapshot.restore(to: pasteboard)
        return value
    }

    private func paste(_ text: String) async -> Bool {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardArchive(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        try? await Task.sleep(for: .milliseconds(35))
        guard await postCommandKey(virtualKey: 9) else {
            snapshot.restore(to: pasteboard)
            return false
        }
        try? await Task.sleep(for: .milliseconds(180))
        snapshot.restore(to: pasteboard)
        return true
    }

    private func postCommandKey(virtualKey: CGKeyCode) async -> Bool {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: false) else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        try? await Task.sleep(for: .milliseconds(18))
        up.post(tap: .cghidEventTap)
        return true
    }
}

private struct PasteboardArchive {
    let items: [[NSPasteboard.PasteboardType: Data]]

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let values = items.map { archived -> NSPasteboardItem in
            let item = NSPasteboardItem()
            archived.forEach { item.setData($0.value, forType: $0.key) }
            return item
        }
        if !values.isEmpty { pasteboard.writeObjects(values) }
    }
}
