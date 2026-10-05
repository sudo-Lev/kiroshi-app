import AppKit
import SwiftUI

@MainActor
final class PalettePanelController {
    private let viewModel: PaletteViewModel
    private let bridge: AXTextBridge
    private let improver: ActionPerforming
    private let hud: ResultHUDController
    private let resultCard = ResultCardController()
    private var panel: KeyboardPanel?
    private var outsideMonitor: Any?
    private var hostApplication: NSRunningApplication?
    private var actionTask: Task<Void, Never>?
    private var refineTask: Task<Void, Never>?

    init(viewModel: PaletteViewModel, bridge: AXTextBridge, improver: ActionPerforming, hud: ResultHUDController) {
        self.viewModel = viewModel
        self.bridge = bridge
        self.improver = improver
        self.hud = hud
        self.hud.onUndo = { [weak self] in Task { @MainActor in await self?.bridge.undo() } }
        self.viewModel.onRun = { [weak self] action in self?.run(action) }
        self.viewModel.onRefine = { [weak self] action in self?.fetchQuestions(for: action) }
    }

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() async {
        if isVisible { close(); return }
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
        panel?.orderOut(nil)
        removeMonitors()
        if let capture = viewModel.capture { restoreHostFocus(capture) }
        viewModel.reset()
    }

    private func show(capture: PaletteCapture) {
        let size = NSSize(width: 432, height: 260)
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
        installMonitors()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.08 : 0.14
            panel?.animator().alphaValue = 1
        }
    }

    private func fetchQuestions(for action: PaletteAction) {
        guard let capture = viewModel.capture else { return }
        refineTask?.cancel()
        refineTask = Task { [weak self] in
            guard let self else { return }
            do {
                let questions = try await improver.clarifyingQuestions(capture.text, goal: action.prompt)
                guard !Task.isCancelled else { return }
                viewModel.showQuestions(questions, for: action)
            } catch QwixitAPIError.quotaExceeded {
                close()
                if AppPreferences().isBillingActivationPending {
                    hud.showSubscriptionActivating(capture: capture)
                } else {
                    hud.showLimitReached(capture: capture)
                }
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
        panel?.orderOut(nil)
        removeMonitors()
        restoreHostFocus(capture)
        hud.showRunning(action: action, capture: capture)
        actionTask?.cancel()
        actionTask = Task { [weak self] in
            guard let self else { return }
            do {
                var instruction = action.prompt
                if action.id == "translate" {
                    let language = action.language ?? "uk"
                    instruction += " Language: \(language)."
                }
                let output = try await improver.perform(capture.text, instruction: instruction)
                try Task.checkCancellation()
                switch action.mode {
                case .replace:
                    guard await bridge.replace(capture, with: output) else { throw PaletteError.writeFailed }
                    hud.showDone(action: action, detail: action.id == "translate" ? "Text translated · text replaced" : "Text replaced", capture: capture)
                case .insert:
                    guard await bridge.insert(capture, text: output) else { throw PaletteError.writeFailed }
                    hud.showDone(action: action, detail: "Text inserted · original kept", capture: capture)
                case .panel:
                    hud.hide()
                    resultCard.show(
                        action: action,
                        result: output,
                        capture: capture,
                        onInsert: { [weak self] in
                            Task { @MainActor in _ = await self?.bridge.insert(capture, text: output) }
                        },
                        onAsk: { [weak self] question in
                            guard let self else { return }
                            resultCard.setLoading(true)
                            Task {
                                do {
                                    let reply = try await self.improver.perform(
                                        capture.text,
                                        instruction: "Answer about the text: \(question)"
                                    )
                                    self.resultCard.update(result: reply)
                                } catch {
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
                if AppPreferences().isBillingActivationPending {
                    hud.showSubscriptionActivating(capture: capture)
                } else {
                    hud.showLimitReached(capture: capture)
                }
            } catch let error where QwixitAPI.isConnectivityError(error) {
                hud.showOffline(capture: capture)
            } catch {
                hud.showError((error as? LocalizedError)?.errorDescription ?? error.localizedDescription, capture: capture)
            }
        }
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

private enum PaletteError: LocalizedError {
    case writeFailed
    var errorDescription: String? { "The active app did not allow the text change. Your text is unchanged." }
}
