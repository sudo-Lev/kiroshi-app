import AppKit
import SwiftUI

@MainActor
final class ReplacementRecoveryPanelController: ReplacementRecoveryPresenting {
    private let state = ReplacementRecoveryState()
    private let popupDismiss: PopupDismissCoordinator
    private var panel: RecoveryKeyboardPanel?
    private var outsideMonitor: Any?
    private var onClose: (() -> Void)?

    init(popupDismiss: PopupDismissCoordinator) {
        self.popupDismiss = popupDismiss
    }

    func show(
        freshText: String,
        report: ReplacementAttemptReport,
        anchor accessibilityBounds: CGRect?,
        fallbackPoint: CGPoint?,
        onClose: @escaping () -> Void
    ) {
        self.onClose = onClose
        state.prepare(freshText: freshText, report: report)

        let size = NSSize(width: 430, height: 242)
        if panel == nil {
            let panel = RecoveryKeyboardPanel(
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
                rootView: ReplacementRecoveryPanelView(
                    state: state,
                    onCopy: { [weak self] in self?.copyFreshText() },
                    onClose: { [weak self] in self?.close() }
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
            popupDismiss.show(panel) { [weak self] in self?.close() }
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
        onClose = nil
        state.clear()
    }

    private func copyFreshText() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(state.freshText, forType: .string),
              pasteboard.string(forType: .string) == state.freshText else {
            state.copyFailed = true
            return
        }
        close()
    }

    private func close() {
        let action = onClose
        hide()
        action?()
    }

    private func handle(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 36, 76: copyFreshText()
        case 53: close()
        default: return false
        }
        return true
    }

    private func installMonitor() {
        removeMonitor()
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }

    private func removeMonitor() {
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        outsideMonitor = nil
    }
}

@MainActor
private final class ReplacementRecoveryState: ObservableObject {
    @Published private(set) var freshText = ""
    @Published private(set) var report = ReplacementAttemptReport.notSubmitted
    @Published var copyFailed = false

    func prepare(freshText: String, report: ReplacementAttemptReport) {
        self.freshText = freshText
        self.report = report
        copyFailed = false
    }

    func clear() {
        freshText = ""
        report = .notSubmitted
        copyFailed = false
    }
}

private final class RecoveryKeyboardPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }
}

private struct ReplacementRecoveryPanelView: View {
    @ObservedObject var state: ReplacementRecoveryState
    let onCopy: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(KColor.line)
            content
            Divider().overlay(KColor.line)
            footer
        }
        .foregroundStyle(KColor.ink)
        .qwixitPanel(cornerRadius: 14, accent: KColor.danger)
        .qwixitTheme()
    }

    private var header: some View {
        HStack(spacing: 8) {
            TokiriUI.Icon(.warning, size: 13)
                .foregroundStyle(KColor.danger)
            Text("PASTE NOT SENT")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(KColor.danger)
            Spacer()
            TokiriUI.PopupCloseButton(
                shortcut: HotkeyCatalog.popupDismiss.presentation,
                label: "Close text recovery",
                action: onClose
            )
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(KColor.canvasRaised)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Paste wasn't sent.")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(KColor.ink)

            Text("Copy this text and paste it manually.")
                .font(.system(size: 10.5))
                .lineSpacing(2)
                .foregroundStyle(KColor.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                Text(state.freshText)
                    .font(.system(size: 10.5))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(KColor.surfaceHover, in: QwixitControlShape(cut: 5))
                    .overlay(QwixitControlShape(cut: 5).stroke(KColor.line))
            }
            .frame(height: 54)
            .accessibilityLabel("Fresh text available to copy")

            diagnostics
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var diagnostics: some View {
        VStack(spacing: 3) {
            HStack(spacing: 9) {
                diagnostic("CLIPBOARD", state.report.clipboardWrite)
                diagnostic("CARET", state.report.caretMove)
                diagnostic("⌘V EVENT", state.report.pasteEvent)
            }
        }
        .font(.system(size: 8, weight: .bold, design: .monospaced))
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Paste delivery steps")
    }

    private func diagnostic(_ title: String, _ status: ReplacementStepStatus) -> some View {
        HStack(spacing: 4) {
            Circle().fill(tone(for: status)).frame(width: 4, height: 4)
            Text(title).foregroundStyle(KColor.secondary)
            Text(label(for: status)).foregroundStyle(tone(for: status))
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("\(title): \(label(for: status))")
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if state.copyFailed {
                Text("Copy failed. Select the text above and copy it manually.")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(KColor.danger)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Original may be unchanged.")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(KColor.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button(action: onCopy) {
                Text("Copy fresh text")
                    .frame(minWidth: 108)
            }
            .buttonStyle(TokiriUI.PrimaryButton())
            .keyboardShortcut(.defaultAction)
            .accessibilityLabel("Copy fresh text to the clipboard")
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 42)
        .background(KColor.canvasRaised)
    }

    private func label(for status: ReplacementStepStatus) -> String {
        switch status {
        case .completed: "DONE"
        case .failed: "FAILED"
        case .notAttempted: "—"
        }
    }

    private func tone(for status: ReplacementStepStatus) -> Color {
        switch status {
        case .completed: KColor.success
        case .failed: KColor.danger
        case .notAttempted: KColor.secondary
        }
    }
}
