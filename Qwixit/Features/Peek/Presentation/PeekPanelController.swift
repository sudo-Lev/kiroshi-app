import AppKit
import Combine
import SwiftUI

@MainActor
final class PeekPanelController {
    private let viewModel: PeekViewModel
    private var panel: PeekPanel?
    private var outsideMonitor: Any?
    private var activeSelection: PeekSelection?
    private var stateObserver: AnyCancellable?

    init(viewModel: PeekViewModel) {
        self.viewModel = viewModel
        // @Published emits before the value changes; hop a run-loop turn so SwiftUI swaps
        // the content first and the panel then grows around the new layout.
        stateObserver = viewModel.$loadState
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.resize(for: state) }
    }

    var isVisible: Bool { panel?.isVisible == true }

    func toggle(selection: PeekSelection?) {
        if isVisible {
            close()
            return
        }
        activeSelection = selection
        if let selection { viewModel.open(text: selection.text) } else { viewModel.showNoSelection() }
        show()
    }

    func close() {
        panel?.orderOut(nil)
        removeOutsideMonitor()
        viewModel.close()
    }

    private func show() {
        let size = preferredSize(for: viewModel.loadState)
        if panel == nil {
            let panel = PeekPanel(
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
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isMovableByWindowBackground = true
            panel.keyHandler = { [weak self] event in self?.handle(event) ?? false }
            panel.contentView = NSHostingView(rootView: PeekView(
                viewModel: viewModel,
                onClose: { [weak self] in self?.close() },
                onTogglePin: { [weak self] in self?.togglePin() }
            ))
            self.panel = panel
        }
        panel?.setContentSize(size)
        position(size: size)
        panel?.alphaValue = 0
        panel?.orderFrontRegardless()
        panel?.makeKey()
        installOutsideMonitorIfNeeded()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.08 : 0.15
            panel?.animator().alphaValue = 1
        }
    }

    private func togglePin() {
        viewModel.togglePin()
        guard let panel else { return }
        let size = preferredSize(for: viewModel.loadState)
        panel.setContentSize(size)
        position(size: size)
        if viewModel.isPinned { removeOutsideMonitor() } else { installOutsideMonitorIfNeeded() }
    }

    private func installOutsideMonitorIfNeeded() {
        guard !viewModel.isPinned, outsideMonitor == nil else { return }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }

    private func removeOutsideMonitor() {
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        outsideMonitor = nil
    }

    private func position(size: NSSize) {
        guard let panel else { return }
        let fallback = activeSelection?.fallbackPoint ?? NSEvent.mouseLocation
        let converted = activeSelection?.bounds.flatMap(appKitRect)
        let screen = converted.flatMap(screenContaining)
            ?? NSScreen.screens.first(where: { NSMouseInRect(fallback, $0.frame, false) })
            ?? NSScreen.main
        guard let screen else { return }

        if viewModel.isPinned {
            panel.setFrameOrigin(.init(
                x: screen.visibleFrame.maxX - size.width - 16,
                y: screen.visibleFrame.maxY - size.height - 56
            ))
            return
        }

        if let origin = ContextPanelPlacement.resolve(
            accessibilityBounds: activeSelection?.bounds,
            fallbackPoint: fallback,
            panelSize: size
        ) {
            panel.setFrameOrigin(origin)
        }
    }

    /// Grows or shrinks in place with the top edge fixed, instead of re-placing the panel.
    private func resize(for state: PeekLoadState) {
        guard let panel, panel.isVisible, !viewModel.isPinned else { return }
        let size = preferredSize(for: state)
        let current = panel.frame
        guard current.size != size else { return }

        var frame = NSRect(x: current.minX, y: current.maxY - size.height, width: size.width, height: size.height)
        if let visible = (panel.screen ?? NSScreen.main)?.visibleFrame {
            let inset = ContextPanelPlacement.edgeInset
            frame.origin.x = min(max(frame.minX, visible.minX + inset), visible.maxX - size.width - inset)
            frame.origin.y = min(max(frame.minY, visible.minY + inset), visible.maxY - size.height - inset)
        }

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.setFrame(frame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    private func preferredSize(for state: PeekLoadState) -> NSSize {
        if viewModel.isPinned { return NSSize(width: 440, height: 560) }
        return switch state {
        case .idle: NSSize(width: 440, height: 150)
        case .loading, .loaded: NSSize(width: 440, height: 360)
        case .limitReached: NSSize(width: 420, height: 220)
        case .subscriptionActivating: NSSize(width: 420, height: 190)
        case .failed: NSSize(width: 420, height: 220)
        }
    }

    private func appKitRect(_ rect: CGRect) -> CGRect? {
        guard rect.width > 0, rect.height > 0, let primary = NSScreen.screens.first else { return nil }
        let converted = CGRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        return screenContaining(converted) == nil ? nil : converted
    }

    private func screenContaining(_ rect: CGRect) -> NSScreen? {
        NSScreen.screens.max { lhs, rhs in
            lhs.frame.intersection(rect).area < rhs.frame.intersection(rect).area
        }.flatMap { $0.frame.intersection(rect).area > 0 ? $0 : nil }
    }

    private func handle(_ event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "c" {
            viewModel.copyResult(); return true
        }
        if viewModel.isAwaitingChoice {
            switch event.keyCode {
            case 53: close()
            case 48: viewModel.moveChoice(event.modifierFlags.contains(.shift) ? -1 : 1)
            case 123, 126: viewModel.moveChoice(-1)
            case 124, 125: viewModel.moveChoice(1)
            case 36: viewModel.submitChoice()
            default:
                guard let number = event.charactersIgnoringModifiers.flatMap(Int.init) else { return false }
                viewModel.chooseNumber(number)
            }
            return true
        }
        switch event.keyCode {
        case 53: close()
        case 18: viewModel.selectMode(.translate)
        case 19: viewModel.selectMode(.summary)
        case 48: viewModel.nextMode(step: event.modifierFlags.contains(.shift) ? -1 : 1)
        case 123: viewModel.nextMode(step: -1)
        case 124: viewModel.nextMode()
        case 36:
            if viewModel.isAwaitingChoice { viewModel.submit() }
            else if case .failed = viewModel.loadState { viewModel.retry() }
            else { return false }
        case 33: if viewModel.mode == .summary { viewModel.changeLength(step: -1) } else { return false }
        case 30: if viewModel.mode == .summary { viewModel.changeLength(step: 1) } else { return false }
        default:
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "l": viewModel.cycleLanguage()
            case "p": togglePin()
            default: return false
            }
        }
        return true
    }
}

private final class PeekPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) != true { super.keyDown(with: event) }
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
