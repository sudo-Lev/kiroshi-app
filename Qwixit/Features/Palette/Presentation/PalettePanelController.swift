import AppKit
import Combine
import SwiftUI

@MainActor
final class PalettePanelController {
    private let viewModel: PaletteViewModel
    private let bridge: AXTextBridge
    private let improver: ActionPerforming
    private let hud: ResultHUDController
    private let replacementRecovery: ReplacementRecoveryPresenting
    private let popupDismiss: PopupDismissCoordinator
    private var panel: KeyboardPanel?
    private var outsideMonitor: Any?
    private var hostApplication: NSRunningApplication?
    private var actionTask: Task<Void, Never>?
    private var choicesObserver: AnyCancellable?

    init(
        viewModel: PaletteViewModel,
        bridge: AXTextBridge,
        improver: ActionPerforming,
        hud: ResultHUDController,
        replacementRecovery: ReplacementRecoveryPresenting,
        popupDismiss: PopupDismissCoordinator
    ) {
        self.viewModel = viewModel
        self.bridge = bridge
        self.improver = improver
        self.hud = hud
        self.replacementRecovery = replacementRecovery
        self.popupDismiss = popupDismiss
        choicesObserver = viewModel.$choices
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.resizeForCurrentChoices() }
        self.hud.onUndo = { [weak self] in Task { @MainActor in await self?.bridge.undo() } }
        self.viewModel.onRun = { [weak self] action in self?.run(action) }
    }

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() async {
        if isVisible { close(); return }
        hostApplication = NSWorkspace.shared.frontmostApplication
        guard let capture = await bridge.capture() else {
            hud.showNeutral("Select some text first.", point: NSEvent.mouseLocation)
            return
        }
        // Reject long selections before the palette opens: no request, no charge, text unchanged.
        guard QwixitAPI.accepts(capture.text) else {
            hud.showError(QwixitAPIError.textTooLong.localizedDescription, capture: capture)
            return
        }
        viewModel.open(capture: capture)
        show(capture: capture)
    }

    func close() {
        if let panel { popupDismiss.hide(panel) }
        panel?.orderOut(nil)
        removeMonitors()
        if let capture = viewModel.capture { restoreHostFocus(capture) }
        viewModel.reset()
    }

    private func show(capture: PaletteCapture) {
        let size = preferredSize()
        if panel == nil {
            let panel = KeyboardPanel(contentRect: .init(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .popUpMenu
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            panel.keyHandler = { [weak self] event in self?.handle(event) ?? false }
            self.panel = panel
        }
        // A reused NSPanel keeps the old SwiftUI FocusState alive. Rebuild the
        // host on every opening so arrow-key selection and its visual focus are
        // restored just like on the first invocation.
        panel?.contentView = NSHostingView(rootView: PaletteView(viewModel: viewModel))
        panel?.setContentSize(size)
        position(capture: capture, size: size)
        panel?.alphaValue = 0
        panel?.orderFrontRegardless()
        panel?.makeKey()
        if let panel {
            popupDismiss.show(panel) { [weak self] in self?.close() }
        }
        installMonitors()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.08 : 0.14
            panel?.animator().alphaValue = 1
        }
    }

    private func run(_ action: PaletteAction) {
        guard let capture = viewModel.capture else { return }
        if let panel { popupDismiss.hide(panel) }
        panel?.orderOut(nil)
        removeMonitors()
        restoreHostFocus(capture)
        hud.showRunning(action: action, capture: capture)
        actionTask?.cancel()
        let service = improver
        actionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let language = action.id == "translate" ? action.language ?? "uk" : nil
                let output = try await NetworkRetry.perform(
                    operation: {
                        try await service.perform(capture.text, action: action.id, language: language)
                    },
                    onRetry: { [weak self] attempt, total in
                        self?.hud.showRetrying(attempt: attempt, total: total, capture: capture)
                    }
                )
                try Task.checkCancellation()
                switch action.mode {
                case .replace:
                    let report = await bridge.replace(capture, with: output)
                    try Task.checkCancellation()
                    if report.isSubmitted {
                        hud.showDone(action: action, detail: "Paste sent", capture: capture)
                    } else {
                        showRecovery(freshText: output, report: report, capture: capture)
                    }
                case .insert:
                    let report = await bridge.insert(capture, text: output)
                    try Task.checkCancellation()
                    if report.isSubmitted {
                        hud.showDone(action: action, detail: "Paste sent", capture: capture)
                    } else {
                        showRecovery(freshText: "\n" + output, report: report, capture: capture)
                    }
                }
                viewModel.reset()
            } catch is CancellationError {
                hud.hide()
            } catch QwixitAPIError.quotaExceeded {
                hud.showLimitReached(capture: capture)
            } catch let error where QwixitAPI.isConnectivityError(error) {
                hud.showOffline(capture: capture)
            } catch {
                hud.showError((error as? LocalizedError)?.errorDescription ?? error.localizedDescription, capture: capture)
            }
        }
    }

    private func showRecovery(freshText: String, report: ReplacementAttemptReport, capture: PaletteCapture) {
        hud.hide()
        replacementRecovery.show(
            freshText: freshText,
            report: report,
            anchor: capture.bounds,
            fallbackPoint: capture.fallbackPoint,
            onClose: { [weak self] in self?.bridge.restoreFocus(capture) }
        )
    }

    private func handle(_ event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "z" {
            Task { await bridge.undo() }; return true
        }
        switch event.keyCode {
        case 53: close()
        case 125: viewModel.move(1)
        case 126: viewModel.move(-1)
        case 36: viewModel.submit()
        case 48: viewModel.move(event.modifierFlags.contains(.shift) ? -1 : 1)
        case 123, 124, 51: return false
        default:
            if viewModel.query.isEmpty,
               let number = event.charactersIgnoringModifiers.flatMap(Int.init),
               (1...9).contains(number) {
                viewModel.chooseNumber(number); return true
            }
            return false
        }
        return true
    }

    private func installMonitors() {
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }

    private func removeMonitors() {
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        outsideMonitor = nil
    }

    private func restoreHostFocus(_ capture: PaletteCapture) {
        hostApplication?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            self?.bridge.restoreFocus(capture)
        }
    }

    private func position(capture: PaletteCapture, size: NSSize) {
        guard let panel else { return }
        guard let origin = ContextPanelPlacement.resolve(
            accessibilityBounds: capture.bounds,
            fallbackPoint: capture.fallbackPoint,
            panelSize: size
        ) else { return }
        panel.setFrameOrigin(origin)
    }

    private func preferredSize() -> NSSize {
        let rowCount = max(viewModel.choices.count, 1)
        let dividerCount = viewModel.showsRewriteDivider ? 1 : 0
        let listGaps = max(rowCount - 1, 0) + dividerCount
        let height = 2 + 48 + 1 + 20 + rowCount * 41 + listGaps * 6
            + dividerCount + 1 + 32
        return NSSize(width: 360, height: CGFloat(height))
    }

    private func resizeForCurrentChoices() {
        guard let panel, panel.isVisible else { return }
        let size = preferredSize()
        let current = panel.frame
        guard current.size != size else { return }
        let visible = (panel.screen ?? NSScreen.main)?.visibleFrame
        var frame = NSRect(
            x: current.minX,
            y: current.maxY - size.height,
            width: size.width,
            height: size.height
        )
        if let visible {
            let inset = ContextPanelPlacement.edgeInset
            frame.origin.x = min(max(frame.minX, visible.minX + inset), visible.maxX - size.width - inset)
            frame.origin.y = min(max(frame.minY, visible.minY + inset), visible.maxY - size.height - inset)
        }
        panel.setFrame(frame, display: true)
    }
}
private final class KeyboardPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }
}
