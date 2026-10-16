import AppKit
import ApplicationServices

final class PaletteCapture {
    let element: AXUIElement?
    let text: String
    let range: CFRange?
    let bounds: CGRect?
    let fallbackPoint: CGPoint
    let processIdentifier: pid_t?

    init(
        element: AXUIElement?,
        text: String,
        range: CFRange?,
        bounds: CGRect?,
        fallbackPoint: CGPoint,
        processIdentifier: pid_t?
    ) {
        self.element = element
        self.text = text
        self.range = range
        self.bounds = bounds
        self.fallbackPoint = fallbackPoint
        self.processIdentifier = processIdentifier
    }
}

@MainActor
final class AXTextBridge {
    private var undoCapture: PaletteCapture?

    func capture() async -> PaletteCapture? {
        let fallbackPoint = NSEvent.mouseLocation
        let processIdentifier = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let element = focusedElement()
        let selectedRange = element.flatMap(range(of:))
        let bounds = element.flatMap { element in
            selectedRange.flatMap { selectionBounds(element: element, range: $0) }
        }

        if let element,
           let text = selectedText(in: element),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return PaletteCapture(
                element: element,
                text: text,
                range: selectedRange,
                bounds: bounds,
                fallbackPoint: fallbackPoint,
                processIdentifier: processIdentifier
            )
        }

        guard let text = await copySelection(),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return PaletteCapture(
            element: element,
            text: text,
            range: selectedRange,
            bounds: bounds,
            fallbackPoint: fallbackPoint,
            processIdentifier: processIdentifier
        )
    }

    func replace(_ capture: PaletteCapture, with text: String) async -> ReplacementAttemptReport {
        undoCapture = nil
        restoreFocus(capture)
        let report = await ClipboardCoordinator.shared.paste(text)
        if report.isSubmitted { undoCapture = capture }
        return report
    }

    func insert(_ capture: PaletteCapture, text: String) async -> ReplacementAttemptReport {
        undoCapture = nil
        restoreFocus(capture)
        let report = await ClipboardCoordinator.shared.paste(
            "\n" + text,
            collapseSelectionToEnd: true
        )
        if report.isSubmitted { undoCapture = capture }
        return report
    }

    func undo() async {
        guard let capture = undoCapture else { return }
        undoCapture = nil
        restoreFocus(capture)
        _ = await ClipboardCoordinator.shared.postCommandKey(virtualKey: 6)
    }

    func restoreFocus(_ capture: PaletteCapture) {
        ApplicationFocusRestorer.restore(
            processIdentifier: capture.processIdentifier,
            element: capture.element
        )
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

    private func selectedText(in element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success else { return nil }
        return value as? String
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

    private func copySelection() async -> String? {
        await ClipboardCoordinator.shared.copySelection()
    }
}
