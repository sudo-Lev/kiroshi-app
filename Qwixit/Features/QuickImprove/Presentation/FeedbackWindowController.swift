import SwiftUI
import AppKit

@MainActor
final class FeedbackWindowController: FeedbackPresenting {
    private let state = FeedbackWindowState()
    private let popupDismiss: PopupDismissCoordinator
    private let onUpgrade: () -> Void
    private var panel: NSPanel?

    init(popupDismiss: PopupDismissCoordinator, onUpgrade: @escaping () -> Void) {
        self.popupDismiss = popupDismiss
        self.onUpgrade = onUpgrade
    }

    func show(
        phase: AppPhase,
        reduceMotion: Bool,
        anchor accessibilityBounds: CGRect? = nil,
        fallbackPoint: CGPoint? = nil
    ) {
        let isError: Bool = if case .error = phase { true } else { false }
        let isRetrying: Bool = if case .retrying = phase { true } else { false }
        let isCyberStatus = phase == .processing || phase == .success || phase == .pasteSent || phase == .offline || isRetrying || isError
        let isInteractiveStatus = phase == .offline || isError || phase == .limitReached
        let size: NSSize
        if phase == .limitReached { size = .init(width: 420, height: 232) }
        else if isError { size = .init(width: 400, height: 72) }
        else if phase == .offline { size = .init(width: 360, height: 56) }
        else if isCyberStatus { size = .init(width: 216, height: 50) }
        else if phase == .permissionDenied { size = .init(width: 326, height: 86) }
        else if phase == .noSelection { size = .init(width: 306, height: 82) }
        else { size = .init(width: 272, height: 66) }
        if panel == nil {
            let panel = NSPanel(contentRect: .init(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.contentView = NSHostingView(
                rootView: FeedbackHost(
                    state: state,
                    onClose: { [weak self] in self?.hide() },
                    onUpgrade: onUpgrade
                )
            )
            self.panel = panel
        }
        // Status notices stay click-through so the HUD never interferes with
        // the active app. Error/offline/limit states contain controls and remain
        // interactive.
        let shadowMargin: CGFloat = isCyberStatus && !isInteractiveStatus ? 36 : 0
        state.reduceMotion = reduceMotion
        state.shadowMargin = shadowMargin
        state.phase = phase
        panel?.hasShadow = !isCyberStatus
        panel?.ignoresMouseEvents = !isInteractiveStatus
        panel?.setContentSize(NSSize(width: size.width + shadowMargin * 2, height: size.height + shadowMargin * 2))
        position(anchor: accessibilityBounds, fallbackPoint: fallbackPoint, visibleSize: size, margin: shadowMargin)
        let shouldAnimateAppearance = panel?.isVisible != true
        panel?.orderFrontRegardless()
        if let panel {
            if isInteractiveStatus {
                popupDismiss.show(panel) { [weak self] in self?.hide() }
            } else {
                popupDismiss.hide(panel)
            }
        }
        if shouldAnimateAppearance {
            panel?.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = reduceMotion ? 0 : 0.08
                panel?.animator().alphaValue = 1
            }
        } else {
            panel?.alphaValue = 1
        }
    }

    func hide() {
        if let panel { popupDismiss.hide(panel) }
        panel?.orderOut(nil)
    }

    private func position(anchor accessibilityBounds: CGRect?, fallbackPoint: CGPoint?, visibleSize: NSSize, margin: CGFloat) {
        guard let panel else { return }
        guard let origin = ContextPanelPlacement.resolve(
            accessibilityBounds: accessibilityBounds,
            fallbackPoint: fallbackPoint ?? NSEvent.mouseLocation,
            panelSize: visibleSize
        ) else { return }
        panel.setFrameOrigin(NSPoint(x: origin.x - margin, y: origin.y - margin))
    }
}

@MainActor
private final class FeedbackWindowState: ObservableObject {
    @Published var phase: AppPhase = .ready
    @Published var reduceMotion = false
    @Published var shadowMargin: CGFloat = 0
}

private struct FeedbackHost: View {
    @ObservedObject var state: FeedbackWindowState
    let onClose: () -> Void
    let onUpgrade: () -> Void

    var body: some View {
        ZStack {
            FeedbackPill(
                phase: state.phase,
                reduceMotion: state.reduceMotion,
                onClose: onClose,
                onUpgrade: onUpgrade
            )
                .id(phaseKey)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.97)),
                        removal: .opacity.combined(with: .scale(scale: 1.015))
                    )
                )
        }
        .animation(state.reduceMotion ? nil : .snappy(duration: 0.13), value: phaseKey)
        .padding(state.shadowMargin)
    }

    private var phaseKey: String {
        switch state.phase {
        case .ready: "ready"
        case .processing: "processing"
        case .success: "success"
        case .pasteSent: "paste-sent"
        case .alreadyClean: "already-clean"
        case .noSelection: "no-selection"
        case .permissionDenied: "permission"
        case .limitReached: "limit-reached"
        case .retrying(_, _): "processing"
        case .offline: "offline"
        case .error(let message): "error-\(message)"
        }
    }
}
