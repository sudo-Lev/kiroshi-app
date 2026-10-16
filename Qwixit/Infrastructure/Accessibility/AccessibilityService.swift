import AppKit
import ApplicationServices

final class TextSelectionSnapshot {
    let text: String
    let bounds: CGRect?
    let fallbackPoint: CGPoint
    let processIdentifier: pid_t?

    fileprivate let element: AXUIElement?
    fileprivate let focusElement: AXUIElement?

    fileprivate init(
        text: String,
        bounds: CGRect?,
        fallbackPoint: CGPoint,
        processIdentifier: pid_t?,
        element: AXUIElement?,
        focusElement: AXUIElement?
    ) {
        self.text = text
        self.bounds = bounds
        self.fallbackPoint = fallbackPoint
        self.processIdentifier = processIdentifier
        self.element = element
        self.focusElement = focusElement
    }

    convenience init(text: String, bounds: CGRect? = nil, fallbackPoint: CGPoint = .zero) {
        self.init(
            text: text,
            bounds: bounds,
            fallbackPoint: fallbackPoint,
            processIdentifier: nil,
            element: nil,
            focusElement: nil
        )
    }
}

final class AccessibilityService: AccessibilityServicing, SelectionSnapshotProviding {
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
        let processIdentifier = NSWorkspace.shared.frontmostApplication?.processIdentifier
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
                    processIdentifier: processIdentifier,
                    element: element,
                    focusElement: focusElement
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
            processIdentifier: processIdentifier,
            element: element,
            focusElement: focusElement ?? element
        )
    }

    func replaceSelection(_ snapshot: TextSelectionSnapshot, with replacement: String) async -> ReplacementAttemptReport {
        restoreFocus(snapshot)
        return await ClipboardCoordinator.shared.paste(replacement)
    }

    func restoreFocus(_ snapshot: TextSelectionSnapshot) {
        ApplicationFocusRestorer.restore(
            processIdentifier: snapshot.processIdentifier,
            element: snapshot.focusElement ?? snapshot.element
        )
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
        await ClipboardCoordinator.shared.copySelection()
    }

}
