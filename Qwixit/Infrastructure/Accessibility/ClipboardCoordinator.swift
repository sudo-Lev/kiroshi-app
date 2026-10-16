import AppKit
import ApplicationServices

enum ClipboardCopyReadback {
    static func text(from pasteboard: NSPasteboard, after clearedCount: Int) -> String? {
        guard pasteboard.changeCount > clearedCount,
              let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
}

enum ClipboardAfterPaste {
    case restorePrevious
    case keepReplacement
}

/// Serializes clipboard capture and the shared paste path used by Fix and Actions.
@MainActor
final class ClipboardCoordinator {
    static let shared = ClipboardCoordinator()

    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private init() {}

    func copySelection() async -> String? {
        await enter()
        defer { leave() }
        guard !Task.isCancelled else { return nil }

        let pasteboard = NSPasteboard.general
        let archive = PasteboardArchive(pasteboard)
        pasteboard.clearContents()
        let clearedCount = pasteboard.changeCount
        var restoreCount = clearedCount
        defer { archive.restore(to: pasteboard, ifChangeCountAtMost: restoreCount) }

        try? await Task.sleep(for: .milliseconds(55))
        guard !Task.isCancelled, await postKey(virtualKey: 8, flags: .maskCommand) else { return nil }

        // Some apps publish rich and plain text in separate writes.
        let earliestRead = ContinuousClock.now.advanced(by: .milliseconds(140))
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(550))
        var lastCount = clearedCount
        var unchangedSamples = 0
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(30))
            guard !Task.isCancelled else {
                restoreCount = pasteboard.changeCount
                return nil
            }
            let count = pasteboard.changeCount
            if count != lastCount {
                lastCount = count
                unchangedSamples = 0
            } else if count > clearedCount {
                unchangedSamples += 1
            }
            if ContinuousClock.now >= earliestRead, unchangedSamples >= 2,
               let text = ClipboardCopyReadback.text(from: pasteboard, after: clearedCount) {
                restoreCount = count
                return text
            }
        }

        restoreCount = pasteboard.changeCount
        return ClipboardCopyReadback.text(from: pasteboard, after: clearedCount)
    }

    func paste(
        _ text: String,
        collapseSelectionToEnd: Bool = false,
        clipboardAfterPaste: ClipboardAfterPaste = .restorePrevious
    ) async -> ReplacementAttemptReport {
        await enter()
        defer { leave() }
        guard !Task.isCancelled else { return .notSubmitted }

        let pasteboard = NSPasteboard.general
        let archive = PasteboardArchive(pasteboard)
        var restoreCount = pasteboard.changeCount
        var replacementWritten = false
        defer {
            archive.finishPaste(
                to: pasteboard,
                ifChangeCountAtMost: restoreCount,
                clipboardAfterPaste: clipboardAfterPaste,
                replacementWritten: replacementWritten
            )
        }

        pasteboard.clearContents()
        restoreCount = pasteboard.changeCount
        guard pasteboard.setString(text, forType: .string),
              pasteboard.string(forType: .string) == text else {
            restoreCount = pasteboard.changeCount
            var report = ReplacementAttemptReport()
            report.clipboardWrite = .failed
            return report
        }

        let ownedChangeCount = pasteboard.changeCount
        restoreCount = ownedChangeCount
        replacementWritten = true
        var report = ReplacementAttemptReport()
        report.clipboardWrite = .completed

        try? await Task.sleep(for: .milliseconds(45))
        guard !Task.isCancelled,
              pasteboard.changeCount == ownedChangeCount,
              pasteboard.string(forType: .string) == text else {
            report.clipboardWrite = .failed
            return report
        }

        if collapseSelectionToEnd {
            let sent = await postKey(virtualKey: 0x7C, flags: [])
            report.caretMove = sent ? .completed : .failed
            guard sent, !Task.isCancelled else { return report }
        }

        let sent = await postKey(virtualKey: 9, flags: .maskCommand)
        report.pasteEvent = sent ? .completed : .failed
        if sent {
            try? await Task.sleep(for: .milliseconds(180))
        }
        return report
    }

    func postCommandKey(virtualKey: CGKeyCode) async -> Bool {
        await postKey(virtualKey: virtualKey, flags: .maskCommand)
    }

    private func enter() async {
        if !isBusy {
            isBusy = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func leave() {
        if waiters.isEmpty {
            isBusy = false
        } else {
            waiters.removeFirst().resume()
        }
    }

    private func postKey(virtualKey: CGKeyCode, flags: CGEventFlags) async -> Bool {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: false) else { return false }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        try? await Task.sleep(for: .milliseconds(18))
        up.post(tap: .cghidEventTap)
        return true
    }
}

enum ApplicationFocusRestorer {
    static func restore(processIdentifier: pid_t?, element: AXUIElement?) {
        if let processIdentifier,
           NSWorkspace.shared.frontmostApplication?.processIdentifier != processIdentifier,
           let application = NSWorkspace.shared.runningApplications.first(where: {
               $0.processIdentifier == processIdentifier
           }) {
            _ = application.activate()
        }
        if let element {
            AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        }
    }
}

struct PasteboardArchive {
    let items: [[NSPasteboard.PasteboardType: Data]]

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
    }

    func restore(to pasteboard: NSPasteboard, ifChangeCountAtMost expected: Int) {
        // Preserve clipboard changes made by the user while the transaction was in flight.
        guard pasteboard.changeCount <= expected else { return }
        pasteboard.clearContents()
        let values = items.map { archived -> NSPasteboardItem in
            let item = NSPasteboardItem()
            archived.forEach { item.setData($0.value, forType: $0.key) }
            return item
        }
        if !values.isEmpty { pasteboard.writeObjects(values) }
    }

    func finishPaste(
        to pasteboard: NSPasteboard,
        ifChangeCountAtMost expected: Int,
        clipboardAfterPaste: ClipboardAfterPaste,
        replacementWritten: Bool
    ) {
        if case .keepReplacement = clipboardAfterPaste, replacementWritten { return }
        restore(to: pasteboard, ifChangeCountAtMost: expected)
    }
}
