import AppKit
import SwiftUI

@MainActor
final class PalettePanelController {
    private let viewModel: PaletteViewModel
    private let bridge: AXTextBridge
    private let improver: ActionPerforming
    private let hud: ResultHUDController
    private let replacementRecovery: ReplacementRecoveryPresenting
    private let popupDismiss: PopupDismissCoordinator
    private let resultCard: ResultCardController
    private var panel: KeyboardPanel?
    private var outsideMonitor: Any?
    private var hostApplication: NSRunningApplication?
    private var actionTask: Task<Void, Never>?
    private var refineTask: Task<Void, Never>?
    private var followUpTask: Task<Void, Never>?

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
        resultCard = ResultCardController(popupDismiss: popupDismiss)
        self.hud.onUndo = { [weak self] in Task { @MainActor in await self?.bridge.undo() } }
        resultCard.onHide = { [weak self] in self?.followUpTask?.cancel() }
        self.viewModel.onRun = { [weak self] action in self?.run(action) }
        self.viewModel.onRefine = { [weak self] action in self?.fetchQuestions(for: action) }
    }

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() async {
        if isVisible { close(); return }
        resultCard.hide()
        hostApplication = NSWorkspace.shared.frontmostApplication
        guard let capture = await bridge.capture() else {
            hud.showNeutral("Select some text first.", point: NSEvent.mouseLocation)
            return
        }
        viewModel.open(capture: capture)
        show(capture: capture)
    }

    func close() {
        refineTask?.cancel()
        if let panel { popupDismiss.hide(panel) }
        panel?.orderOut(nil)
        removeMonitors()
        if let capture = viewModel.capture { restoreHostFocus(capture) }
        viewModel.reset()
    }

    private func show(capture: PaletteCapture) {
        let size = NSSize(width: 440, height: 190)
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
        panel?.contentView = NSHostingView(rootView: PaletteView(
            viewModel: viewModel,
            onClose: { [weak self] in self?.close() }
        ))
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

    private func fetchQuestions(for action: PaletteAction) {
        guard let capture = viewModel.capture else { return }
        let service = improver
        refineTask?.cancel()
        refineTask = Task { [weak self] in
            guard let self else { return }
            do {
                let questions = try await NetworkRetry.perform(
                    operation: {
                        try await service.clarifyingQuestions(capture.text, goal: action.prompt)
                    },
                    onRetry: { [weak self] attempt, total in
                        self?.hud.showRetrying(attempt: attempt, total: total, capture: capture)
                    }
                )
                guard !Task.isCancelled else { return }
                viewModel.showQuestions(questions, for: action)
            } catch QwixitAPIError.quotaExceeded {
                close()
                hud.showLimitReached(capture: capture)
            } catch let error where QwixitAPI.isConnectivityError(error) {
                close()
                hud.showOffline(capture: capture)
            } catch {
                guard !Task.isCancelled else { return }
                // If refinement is unavailable, the original action remains useful.
                viewModel.showQuestions([], for: action)
            }
        }
    }

    private func run(_ action: PaletteAction) {
        refineTask?.cancel()
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
                var instruction = action.prompt
                if action.id == "translate" {
                    let language = action.language ?? "uk"
                    instruction += " Language: \(language)."
                }
                let output = try await NetworkRetry.perform(
                    operation: {
                        try await service.perform(capture.text, instruction: instruction)
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
                case .panel:
                    hud.hide()
                    resultCard.show(
                        action: action,
                        result: output,
                        capture: capture,
                        onInsert: { [weak self] in
                            guard let self else { return }
                            resultCard.hide()
                            Task { @MainActor in
                                let report = await self.bridge.insert(capture, text: output)
                                if report.isSubmitted {
                                    self.hud.showDone(action: action, detail: "Paste sent", capture: capture)
                                } else {
                                    self.showRecovery(freshText: "\n" + output, report: report, capture: capture)
                                }
                            }
                        },
                        onAsk: { [weak self] question in
                            guard let self else { return }
                            resultCard.setLoading(true)
                            self.followUpTask?.cancel()
                            self.followUpTask = Task {
                                do {
                                    let reply = try await NetworkRetry.perform(
                                        operation: {
                                            try await self.improver.perform(
                                                capture.text,
                                                instruction: "Answer about the text: \(question)"
                                            )
                                        },
                                        onRetry: { [weak self] attempt, total in
                                            self?.hud.showRetrying(attempt: attempt, total: total, capture: capture)
                                        }
                                    )
                                    try Task.checkCancellation()
                                    self.resultCard.update(result: reply)
                                } catch is CancellationError {
                                    return
                                } catch {
                                    guard !Task.isCancelled else { return }
                                    self.resultCard.update(result: error.localizedDescription)
                                }
                            }
                        }
                    )
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
        if viewModel.isRefining, let handled = handleRefining(event) { return handled }
        switch event.keyCode {
        case 53:
            if !viewModel.goBack() { close() }
        case 125: viewModel.move(1)
        case 126: viewModel.move(-1)
        case 36: viewModel.submit()
        case 48: viewModel.move(event.modifierFlags.contains(.shift) ? -1 : 1)
        case 124: return false
        case 123:
            if !viewModel.goBack() { return false }
        case 51:
            if viewModel.query.isEmpty, viewModel.goBack() { return true }
            return false
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

    /// Keys inside the quick-questions step; `nil` falls through to the regular handling.
    private func handleRefining(_ event: NSEvent) -> Bool? {
        switch event.keyCode {
        case 53:
            refineTask?.cancel()
            _ = viewModel.goBack()
        case 123: viewModel.shiftAnswer(-1)
        case 124: viewModel.shiftAnswer(1)
        case 48: viewModel.move(event.modifierFlags.contains(.shift) ? -1 : 1)
        default: return nil
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
