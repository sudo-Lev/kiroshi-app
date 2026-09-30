import AppKit
import ApplicationServices

struct PeekSelection: Equatable {
    let text: String
    let bounds: CGRect?
    let fallbackPoint: CGPoint
}

protocol SelectionReading: AnyObject {
    func read() async -> PeekSelection?
}

final class SelectionReader: SelectionReading {
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
            let objects = items.map { values -> NSPasteboardItem in
                let item = NSPasteboardItem()
                values.forEach { item.setData($0.value, forType: $0.key) }
                return item
            }
            if !objects.isEmpty { pasteboard.writeObjects(objects) }
        }
    }

    func read() async -> PeekSelection? {
        let fallbackPoint = NSEvent.mouseLocation
        let elements = accessibilityCandidates()
        let bounds = elements.lazy.compactMap(selectionBounds).first

        for element in elements {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success,
               let text = value as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return PeekSelection(text: text, bounds: bounds, fallbackPoint: fallbackPoint)
            }
        }

        guard let copied = await readUsingCopy(),
              !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return PeekSelection(text: copied, bounds: bounds, fallbackPoint: fallbackPoint)
    }

    private func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value else { return nil }
        return (value as! AXUIElement)
    }

    private func accessibilityCandidates() -> [AXUIElement] {
        guard var current = focusedElement() else { return [] }
        var result = [current]
        for _ in 0..<7 {
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parent) == .success,
                  let parent else { break }
            current = parent as! AXUIElement
            result.append(current)
        }
        return result
    }

    private func selectionBounds(_ element: AXUIElement) -> CGRect? {
        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let rangeValue else { return markerBounds(element) }

        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsValue
        ) == .success, let boundsValue, CFGetTypeID(boundsValue) == AXValueGetTypeID() else {
            return markerBounds(element)
        }
        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect), rect.width > 0, rect.height > 0 else { return nil }
        return rect
    }

    private func markerBounds(_ element: AXUIElement) -> CGRect? {
        var markerRange: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &markerRange) == .success,
              let markerRange else { return nil }
        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXBoundsForTextMarkerRange" as CFString,
            markerRange,
            &boundsValue
        ) == .success, let boundsValue, CFGetTypeID(boundsValue) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect), rect.width > 0, rect.height > 0 else { return nil }
        return rect
    }

    private func readUsingCopy() async -> String? {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)
        pasteboard.clearContents()
        let changeCount = pasteboard.changeCount

        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: false) else {
            snapshot.restore(to: pasteboard)
            return nil
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        try? await Task.sleep(for: .milliseconds(18))
        up.post(tap: .cghidEventTap)
        try? await Task.sleep(for: .milliseconds(125))

        let text = pasteboard.changeCount == changeCount ? nil : pasteboard.string(forType: .string)
        snapshot.restore(to: pasteboard)
        return text
    }
}
