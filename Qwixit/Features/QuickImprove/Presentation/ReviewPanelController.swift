import AppKit
import SwiftUI

@MainActor
final class ReviewPanelController: ReviewPresenting {
    private let state = ReviewPanelState()
    private let popupDismiss: PopupDismissCoordinator
    private var panel: ReviewKeyboardPanel?
    private var outsideMonitor: Any?
    private var onApply: (() -> Void)?
    private var onCancel: ((Bool) -> Void)?

    init(popupDismiss: PopupDismissCoordinator) {
        self.popupDismiss = popupDismiss
    }

    func show(
        original: String,
        proposed: String,
        anchor accessibilityBounds: CGRect?,
        fallbackPoint: CGPoint?,
        onApply: @escaping () -> Void,
        onCancel: @escaping (Bool) -> Void
    ) {
        self.onApply = onApply
        self.onCancel = onCancel
        state.prepare(original: original, proposed: proposed)

        let size = NSSize(width: 480, height: 324)
        if panel == nil {
            let panel = ReviewKeyboardPanel(
                contentRect: .init(origin: .zero, size: size),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .popUpMenu
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            panel.keyHandler = { [weak self] event in self?.handle(event) ?? false }
            panel.contentView = NSHostingView(
                rootView: ReviewPanelView(
                    state: state,
                    onApply: { [weak self] in self?.apply() },
                    onCancel: { [weak self] in self?.cancel() }
                )
            )
            self.panel = panel
        }

        panel?.setContentSize(size)
        if let origin = ContextPanelPlacement.resolve(
            accessibilityBounds: accessibilityBounds,
            fallbackPoint: fallbackPoint ?? NSEvent.mouseLocation,
            panelSize: size
        ) {
            panel?.setFrameOrigin(origin)
        }
        panel?.alphaValue = 0
        panel?.orderFrontRegardless()
        panel?.makeKey()
        if let panel {
            popupDismiss.show(panel) { [weak self] in self?.cancel() }
        }
        installMonitor()

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : 0.14
            panel?.animator().alphaValue = 1
        }
    }

    func hide() {
        removeMonitor()
        if let panel { popupDismiss.hide(panel) }
        panel?.orderOut(nil)
        onApply = nil
        onCancel = nil
        state.clear()
    }

    private func apply() {
        let action = onApply
        hide()
        action?()
    }

    private func cancel(restoreFocus: Bool = true) {
        let action = onCancel
        hide()
        action?(restoreFocus)
    }

    private func handle(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 36, 76: apply()
        case 53: cancel()
        default: return false
        }
        return true
    }

    private func installMonitor() {
        removeMonitor()
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            Task { @MainActor in self?.cancel(restoreFocus: false) }
        }
    }

    private func removeMonitor() {
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        outsideMonitor = nil
    }
}

@MainActor
private final class ReviewPanelState: ObservableObject {
    @Published private(set) var chunks: [ReviewDiffChunk] = []
    @Published var showOriginal = false

    func prepare(original: String, proposed: String) {
        chunks = ReviewDiffEngine.chunks(original: original, proposed: proposed)
        showOriginal = false
    }

    func clear() {
        chunks = []
        showOriginal = false
    }
}

private final class ReviewKeyboardPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }
}

private struct ReviewPanelView: View {
    @ObservedObject var state: ReviewPanelState
    let onApply: () -> Void
    let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(KColor.line)
            content
            Divider().overlay(KColor.line)
            footer
        }
        .foregroundStyle(KColor.ink)
        .qwixitPanel()
        .qwixitTheme()
    }

    private var header: some View {
        HStack(spacing: 10) {
            QwixitFaceView(
                face: .ready,
                size: 12,
                bracketed: true,
                reduceMotion: reduceMotion,
                color: KColor.terminalGreen
            )

            Text("FIX · PREVIEW")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(KColor.terminalGreen)

            Spacer()

            Text("TEXT UNCHANGED")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(KColor.secondary)

            TokiriUI.PopupCloseButton(
                shortcut: HotkeyCatalog.popupDismiss.presentation,
                label: "Keep original text and close preview",
                action: onCancel
            )
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(KColor.canvasRaised)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    Text(state.showOriginal ? "ORIGINAL" : "SUGGESTED")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(1.1)
                        .foregroundStyle(state.showOriginal ? KColor.secondary : KColor.terminalGreen)

                    Spacer()

                    Button(state.showOriginal ? "Show suggested" : "Show original") {
                        let change = { state.showOriginal.toggle() }
                        if reduceMotion {
                            change()
                        } else {
                            withAnimation(.easeOut(duration: 0.14), change)
                        }
                    }
                    .buttonStyle(CompactButtonStyle(accent: KColor.secondary))
                    .accessibilityLabel(state.showOriginal ? "Show suggested text" : "Show original text")
                }

                diffCard(
                    text: render(
                        state.chunks,
                        showing: state.showOriginal ? .original : .inline
                    )
                )

                if !state.showOriginal {
                    diffLegend
                }
            }
            .padding(16)
        }
        .frame(maxHeight: .infinity)
    }

    private func diffCard(text: Text) -> some View {
        text
            .font(.system(size: 13))
            .lineSpacing(4)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(KColor.surfaceHover, in: QwixitControlShape(cut: 7))
            .overlay(QwixitControlShape(cut: 7).stroke(KColor.line))
    }

    private var diffLegend: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                TokiriUI.Icon(.added, size: 9)
                Text("added")
            }
                .foregroundStyle(KColor.terminalGreen)
            HStack(spacing: 4) {
                TokiriUI.Icon(.removed, size: 9)
                Text("removed")
            }
                .foregroundStyle(KColor.danger)
        }
        .font(.system(size: 8, weight: .bold, design: .monospaced))
        .foregroundStyle(KColor.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Green underlined text is added. Red struck-through text is removed.")
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("Return approves · Esc keeps original")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(KColor.secondary)
                .lineLimit(1)

            Spacer()

            Button("Keep original", action: onCancel)
                .buttonStyle(SubtleButtonStyle())
            Button("Approve & apply", action: onApply)
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityLabel("Approve suggested text and replace selection")
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(KColor.canvasRaised)
    }

    private enum DiffDisplay {
        case original
        case inline
    }

    private func render(_ chunks: [ReviewDiffChunk], showing display: DiffDisplay) -> Text {
        chunks.reduce(Text(verbatim: "")) { result, chunk in
            switch (display, chunk.kind) {
            case (.original, .added):
                return result
            case (.original, .removed):
                return result + Text(verbatim: chunk.text)
            case (.inline, .removed):
                return result + Text(verbatim: chunk.text)
                    .foregroundStyle(KColor.danger)
                    .strikethrough(true, color: KColor.danger)
            case (.inline, .added):
                return result + Text(verbatim: chunk.text)
                    .foregroundStyle(KColor.terminalGreen)
                    .underline(true, color: KColor.terminalGreen)
            case (_, .same):
                return result + Text(verbatim: chunk.text)
            }
        }
    }
}

enum ReviewDiffKind: Equatable {
    case same
    case added
    case removed
}

struct ReviewDiffChunk: Equatable {
    let kind: ReviewDiffKind
    let text: String
}

enum ReviewDiffEngine {
    static func chunks(original: String, proposed: String) -> [ReviewDiffChunk] {
        let source = tokenize(original)
        let target = tokenize(proposed)
        let sourceCount = source.count
        let targetCount = target.count
        // A full LCS table is useful for short edits, but must not stall the main thread.
        if sourceCount > 0, targetCount > 0,
           sourceCount > 1_000_000 / targetCount {
            return [
                ReviewDiffChunk(kind: .removed, text: original),
                ReviewDiffChunk(kind: .added, text: proposed)
            ]
        }
        var table = Array(
            repeating: Array(repeating: 0, count: targetCount + 1),
            count: sourceCount + 1
        )

        if sourceCount > 0, targetCount > 0 {
            for sourceIndex in stride(from: sourceCount - 1, through: 0, by: -1) {
                for targetIndex in stride(from: targetCount - 1, through: 0, by: -1) {
                    table[sourceIndex][targetIndex] = source[sourceIndex] == target[targetIndex]
                        ? table[sourceIndex + 1][targetIndex + 1] + 1
                        : max(table[sourceIndex + 1][targetIndex], table[sourceIndex][targetIndex + 1])
                }
            }
        }

        var chunks: [ReviewDiffChunk] = []
        var sourceIndex = 0
        var targetIndex = 0
        while sourceIndex < sourceCount || targetIndex < targetCount {
            if sourceIndex < sourceCount, targetIndex < targetCount, source[sourceIndex] == target[targetIndex] {
                append(&chunks, kind: .same, text: source[sourceIndex])
                sourceIndex += 1
                targetIndex += 1
            } else if targetIndex < targetCount,
                      sourceIndex == sourceCount || table[sourceIndex][targetIndex + 1] >= table[sourceIndex + 1][targetIndex] {
                append(&chunks, kind: .added, text: target[targetIndex])
                targetIndex += 1
            } else {
                append(&chunks, kind: .removed, text: source[sourceIndex])
                sourceIndex += 1
            }
        }
        return chunks
    }

    private static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var currentIsWhitespace: Bool?

        for character in text {
            let isWhitespace = character.isWhitespace
            if let currentIsWhitespace, currentIsWhitespace != isWhitespace, !current.isEmpty {
                tokens.append(current)
                current = ""
            }
            currentIsWhitespace = isWhitespace
            current.append(character)
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    private static func append(_ chunks: inout [ReviewDiffChunk], kind: ReviewDiffKind, text: String) {
        guard !text.isEmpty else { return }
        if let last = chunks.last, last.kind == kind {
            chunks[chunks.count - 1] = ReviewDiffChunk(kind: kind, text: last.text + text)
        } else {
            chunks.append(ReviewDiffChunk(kind: kind, text: text))
        }
    }
}
