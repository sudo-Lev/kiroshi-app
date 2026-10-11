import AppKit
import ApplicationServices

final class TextSelectionSnapshot {
    let text: String
    let bounds: CGRect?
    let fallbackPoint: CGPoint

    fileprivate let element: AXUIElement?
    fileprivate let focusElement: AXUIElement?
    fileprivate let range: CFRange?

    fileprivate init(
        text: String,
        bounds: CGRect?,
        fallbackPoint: CGPoint,
        element: AXUIElement?,
        focusElement: AXUIElement?,
        range: CFRange?
    ) {
        self.text = text
        self.bounds = bounds
        self.fallbackPoint = fallbackPoint
        self.element = element
        self.focusElement = focusElement
        self.range = range
    }

    convenience init(text: String, bounds: CGRect? = nil, fallbackPoint: CGPoint = .zero) {
        self.init(
            text: text,
            bounds: bounds,
            fallbackPoint: fallbackPoint,
            element: nil,
            focusElement: nil,
            range: nil
        )
    }
}

final class AccessibilityService: AccessibilityServicing, SelectionSnapshotProviding {
    private struct PasteboardSnapshot {
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
            let restored = items.map { values -> NSPasteboardItem in
                let item = NSPasteboardItem()
                values.forEach { item.setData($0.value, forType: $0.key) }
                return item
            }
            if !restored.isEmpty { pasteboard.writeObjects(restored) }
        }
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }
    var isTrusted: Bool { Self.isTrusted }

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard !AXIsProcessTrustedWithOptions(options) else { return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func selectedText() async -> String? {
        for element in accessibilityCandidates() {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success,
               let text = value as? String,
               !text.isEmpty {
                return text
            }
        }
        return await selectedTextUsingCopy()
    }

    func captureSelection() async -> TextSelectionSnapshot? {
        let fallbackPoint = NSEvent.mouseLocation
        let focusElement = focusedElement()

        for element in accessibilityCandidates() {
            let range = selectedRange(of: element)
            let bounds = range.flatMap { selectionBounds(for: element, range: $0) }
            if let text = selectedText(in: element),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return TextSelectionSnapshot(
                    text: text,
                    bounds: bounds,
                    fallbackPoint: fallbackPoint,
                    element: element,
                    focusElement: focusElement,
                    range: range
                )
            }
        }

        guard let text = await selectedTextUsingCopy(),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let element = focusedElement()
        return TextSelectionSnapshot(
            text: text,
            bounds: nil,
            fallbackPoint: fallbackPoint,
            element: element,
            focusElement: focusElement ?? element,
            range: element.flatMap(selectedRange(of:))
        )
    }

    func replaceSelection(_ snapshot: TextSelectionSnapshot, with replacement: String) async -> Bool {
        restoreFocus(snapshot)
        if let element = snapshot.element, isInsideWebArea(element) {
            return await replaceUsingPasteboard(replacement)
        }

        if let element = snapshot.element,
           var range = snapshot.range,
           let rangeValue = AXValueCreate(.cfRange, &range) {
            _ = AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                rangeValue
            )
        }

        if let element = snapshot.element,
           AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, replacement as CFTypeRef) == .success {
            return true
        }
        return await replaceUsingPasteboard(replacement)
    }

    func restoreFocus(_ snapshot: TextSelectionSnapshot) {
        guard let focusElement = snapshot.focusElement ?? snapshot.element else { return }
        AXUIElementSetAttributeValue(focusElement, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

    func selectionBounds() -> CGRect? {
        for element in accessibilityCandidates() {
            if let bounds = selectedTextBounds(for: element) { return bounds }

            if let bounds = bounds(
                for: element,
                rangeAttribute: "AXSelectedTextMarkerRange",
                boundsAttribute: "AXBoundsForTextMarkerRange"
            ) { return bounds }
        }
        return nil
    }

    func fallbackPoint() -> CGPoint {
        NSEvent.mouseLocation
    }

    private func selectedText(in element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func selectedRange(of element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        return AXValueGetValue(value as! AXValue, .cfRange, &range) && range.length > 0 ? range : nil
    }

    private func selectionBounds(for element: AXUIElement, range: CFRange) -> CGRect? {
        var mutableRange = range
        guard let rangeValue = AXValueCreate(.cfRange, &mutableRange) else { return nil }
        return parameterizedBounds(
            for: element,
            attribute: kAXBoundsForRangeParameterizedAttribute as String,
            range: rangeValue
        )
    }

    @discardableResult
    func replaceSelection(_: String, with replacement: String) async -> Bool {
        if let element = focusedElement(), isInsideWebArea(element) {
            return await replaceUsingPasteboard(replacement)
        }

        if let element = focusedElement() {
            let result = AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextAttribute as CFString,
                replacement as CFTypeRef
            )
            if result == .success { return true }
        }

        return await replaceUsingPasteboard(replacement)
    }

    private func replaceUsingPasteboard(_ text: String) async -> Bool {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        try? await Task.sleep(for: .milliseconds(45))
        let posted = await postCommandKey(virtualKey: 9)
        try? await Task.sleep(for: .milliseconds(350))
        snapshot.restore(to: pasteboard)
        return posted
    }

    private func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success else { return nil }
        return (focused as! AXUIElement)
    }

    private func accessibilityCandidates() -> [AXUIElement] {
        guard var current = focusedElement() else { return [] }
        var elements = [current]
        for _ in 0..<7 {
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parent) == .success,
                  let parent else { break }
            current = parent as! AXUIElement
            elements.append(current)
        }
        return elements
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

    private func selectedTextBounds(for element: AXUIElement) -> CGRect? {
        var rangeReference: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeReference
        ) == .success, let rangeReference else { return nil }

        if CFGetTypeID(rangeReference) == AXValueGetTypeID() {
            var selectedRange = CFRange()
            if AXValueGetValue(rangeReference as! AXValue, .cfRange, &selectedRange), selectedRange.length > 0 {
                var trailingRange = CFRange(
                    location: selectedRange.location + selectedRange.length - 1,
                    length: 1
                )
                if let trailingReference = AXValueCreate(.cfRange, &trailingRange),
                   let bounds = parameterizedBounds(
                    for: element,
                    attribute: kAXBoundsForRangeParameterizedAttribute as String,
                    range: trailingReference
                   ) {
                    return bounds
                }
            }
        }

        return parameterizedBounds(
            for: element,
            attribute: kAXBoundsForRangeParameterizedAttribute as String,
            range: rangeReference
        )
    }

    private func bounds(for element: AXUIElement, rangeAttribute: String, boundsAttribute: String) -> CGRect? {
        var rangeReference: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, rangeAttribute as CFString, &rangeReference) == .success,
              let rangeReference else { return nil }
        return parameterizedBounds(for: element, attribute: boundsAttribute, range: rangeReference)
    }

    private func parameterizedBounds(for element: AXUIElement, attribute: String, range: CFTypeRef) -> CGRect? {
        var boundsReference: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, attribute as CFString, range, &boundsReference) == .success,
              let boundsReference,
              CFGetTypeID(boundsReference) == AXValueGetTypeID() else { return nil }
        var rectangle = CGRect.zero
        guard AXValueGetValue(boundsReference as! AXValue, .cgRect, &rectangle), rectangle.width > 1, rectangle.height > 1 else { return nil }
        return rectangle
    }

    private func selectedTextUsingCopy() async -> String? {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)
        pasteboard.clearContents()
        let clearedChangeCount = pasteboard.changeCount

        try? await Task.sleep(for: .milliseconds(55))
        guard await postCommandKey(virtualKey: 8) else {
            snapshot.restore(to: pasteboard)
            return nil
        }
        try? await Task.sleep(for: .milliseconds(140))

        let copied = pasteboard.changeCount != clearedChangeCount ? pasteboard.string(forType: .string) : nil
        snapshot.restore(to: pasteboard)
        return copied
    }

    @discardableResult
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
