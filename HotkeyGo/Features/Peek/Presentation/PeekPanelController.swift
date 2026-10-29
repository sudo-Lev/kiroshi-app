import AppKit
import Combine
import SwiftUI

enum PeekHeaderLayout {
    static let height: CGFloat = 48
    static let dragWidth: CGFloat = 72
}

@MainActor
final class PeekPanelController {
    private let viewModel: PeekViewModel
    private let popupDismiss: PopupDismissCoordinator
    private let accessibility: AccessibilityServicing
    private let accessNotice: AccessibilityAccessNoticePresenting
    private let onUpgrade: () -> Void
    private var panel: PeekPanel?
    private var outsideMonitor: Any?
    private var activeSelection: PeekSelection?
    private var stateObserver: AnyCancellable?
    private var queryObserver: AnyCancellable?

    init(
        viewModel: PeekViewModel,
        popupDismiss: PopupDismissCoordinator,
        accessibility: AccessibilityServicing,
        accessNotice: AccessibilityAccessNoticePresenting,
        onUpgrade: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.popupDismiss = popupDismiss
        self.accessibility = accessibility
        self.accessNotice = accessNotice
        self.onUpgrade = onUpgrade
        // @Published emits before the value changes; hop a run-loop turn so SwiftUI swaps
        // the content first and the panel then grows around the new layout.
        stateObserver = viewModel.$loadState
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.resize(for: state) }
        queryObserver = viewModel.$query
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                resize(for: self.viewModel.loadState)
            }
    }

    var isVisible: Bool { panel?.isVisible == true }

    func toggle(selection: PeekSelection?) {
        if isVisible {
            close()
            return
        }
        guard accessibility.isTrusted else {
            accessNotice.showAccessibilityAccessNeeded(at: NSEvent.mouseLocation)
            return
        }
        activeSelection = selection
        if let selection { viewModel.open(text: selection.text) } else { viewModel.showNoSelection() }
        show()
    }

    func close() {
        if let panel { popupDismiss.hide(panel) }
        panel?.orderOut(nil)
        removeOutsideMonitor()
        activeSelection = nil
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
            self.panel = panel
        }
        panel?.contentView = NSHostingView(rootView: PeekView(
            viewModel: viewModel,
            onClose: { [weak self] in self?.close() },
            onTogglePin: { [weak self] in self?.togglePin() },
            onUpgrade: onUpgrade
        ))
        panel?.setContentSize(size)
        position(size: size)
        panel?.alphaValue = 0
        panel?.orderFrontRegardless()
        panel?.makeKey()
        if let panel {
            popupDismiss.show(panel) { [weak self] in self?.close() }
        }
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
        if viewModel.isPinned { return NSSize(width: 360, height: 560) }
        let height: CGFloat
        switch state {
        case .idle:
            let rowCount = max(viewModel.visibleLanguages.count, 1)
            height = CGFloat(2 + 48 + 1 + 20 + rowCount * 41 + max(rowCount - 1, 0) * 6 + 1 + 32)
        case .loading, .success:
            height = 150
        case .loaded:
            height = resultHeight
        case .limitReached:
            height = 300
        case .failed(let message):
            height = message == "Select some text first." ? 165 : 200
        }
        return NSSize(width: 360, height: height)
    }

    private var resultHeight: CGFloat {
        guard let result = viewModel.result else { return 150 }
        let font = NSFont.systemFont(ofSize: 15, weight: .regular)
        let textSize = (result.plainText as NSString).boundingRect(
            with: NSSize(width: 326, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        ).size
        let paragraphs = result.plainText.components(separatedBy: "\n\n").count
        let paragraphSpacing = CGFloat(max(paragraphs - 1, 0)) * 8
        let fixedHeight: CGFloat = 2 + 48 + 1 + 30 + 1 + 32
        let contentHeight = fixedHeight + ceil(textSize.height) + paragraphSpacing
        return min(max(contentHeight, 150), 334)
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
            case 126: viewModel.moveChoice(-1)
            case 125: viewModel.moveChoice(1)
            case 36: viewModel.submitChoice()
            default:
                guard viewModel.query.isEmpty else { return false }
                guard let number = event.charactersIgnoringModifiers.flatMap(Int.init) else { return false }
                viewModel.chooseNumber(number)
            }
            return true
        }
        switch event.keyCode {
        case 53: close()
        case 48: viewModel.cycleLanguage(step: event.modifierFlags.contains(.shift) ? -1 : 1)
        case 36:
            if case .failed = viewModel.loadState { viewModel.retry() }
            else { viewModel.copyResult() }
        case 18...21:
            guard let number = event.charactersIgnoringModifiers.flatMap(Int.init),
                  (1...viewModel.languages.count).contains(number) else { return false }
            viewModel.runTranslation(at: number - 1)
        default:
            switch event.charactersIgnoringModifiers?.lowercased() {
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

    override func sendEvent(_ event: NSEvent) {
        // The hosted header consumes background clicks. Reserve its visible Peek
        // title for native dragging, away from the search field and buttons.
        if event.type == .leftMouseDown, isInDragRegion(event.locationInWindow) {
            performDrag(with: event)
            return
        }
        if event.type == .keyDown, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }

    private func isInDragRegion(_ point: NSPoint) -> Bool {
        let bounds = NSRect(origin: .zero, size: frame.size)
        guard bounds.contains(point) else { return false }
        return point.y >= bounds.maxY - PeekHeaderLayout.height
            && point.x <= PeekHeaderLayout.dragWidth
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
