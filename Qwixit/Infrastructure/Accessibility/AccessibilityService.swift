import AppKit
import ApplicationServices

final class AccessibilityService: AccessibilityServicing {
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

    @discardableResult
    func replaceSelection(_ originalText: String, with replacement: String) async -> Bool {
        if let element = focusedElement(), isInsideWebArea(element) {
            return await replaceUsingPasteboard(originalText, with: replacement)
        }

        if let element = focusedElement() {
            let result = AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextAttribute as CFString,
                replacement as CFTypeRef
            )
            if result == .success {
                try? await Task.sleep(for: .milliseconds(80))
                let selectedAfter = selectedTextFromAccessibility()
                if ReplacementVerification.succeeded(
                    original: originalText,
                    replacement: replacement,
                    selectedAfter: selectedAfter
                ) {
                    return true
                }
            }
        }

        return await replaceUsingPasteboard(originalText, with: replacement)
    }

    private func replaceUsingPasteboard(_ originalText: String, with replacement: String) async -> Bool {
        guard let ownerPID = focusedElement().flatMap(processIdentifier) else { return false }

        for attempt in 0..<2 {
            guard !Task.isCancelled else { return false }
            guard focusedElement().flatMap(processIdentifier) == ownerPID else { return false }
            let pasteboard = NSPasteboard.general
            let snapshot = PasteboardSnapshot(pasteboard)
            pasteboard.clearContents()
            pasteboard.setString(replacement, forType: .string)
            try? await Task.sleep(for: .milliseconds(attempt == 0 ? 55 : 120))
            guard await postCommandKey(virtualKey: 9) else {
                snapshot.restore(to: pasteboard)
                return false
            }
            try? await Task.sleep(for: .milliseconds(attempt == 0 ? 320 : 460))
            snapshot.restore(to: pasteboard)

            guard focusedElement().flatMap(processIdentifier) == ownerPID else { return false }
            let selectedAfter = await selectedText()
            if ReplacementVerification.succeeded(
                original: originalText,
                replacement: replacement,
                selectedAfter: selectedAfter
            ) {
                return true
            }
        }

        return false
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

    private func selectedTextFromAccessibility() -> String? {
        for element in accessibilityCandidates() {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success,
               let text = value as? String,
               !text.isEmpty {
                return text
            }
        }
        return nil
    }

    private func processIdentifier(for element: AXUIElement) -> pid_t? {
        var processIdentifier = pid_t()
        return AXUIElementGetPid(element, &processIdentifier) == .success ? processIdentifier : nil
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
