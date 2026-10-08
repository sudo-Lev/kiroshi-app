import SwiftUI
import AppKit

@MainActor
final class FeedbackWindowController: FeedbackPresenting {
    private let state = FeedbackWindowState()
    private var panel: NSPanel?

    func show(
        phase: AppPhase,
        reduceMotion: Bool,
        anchor accessibilityBounds: CGRect? = nil,
        fallbackPoint: CGPoint? = nil
    ) {
        var isStatusChip = phase == .processing || phase == .success
        if case .error = phase { isStatusChip = true }
        let size: NSSize
        if phase == .limitReached { size = .init(width: 374, height: 158) }
        else if isStatusChip { size = .init(width: 216, height: 50) }
        else if phase == .permissionDenied || phase == .offline { size = .init(width: 326, height: 86) }
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
                    onClose: { [weak self] in self?.hide() }
                )
            )
            self.panel = panel
        }
        // The status chip draws its own shadow. A native shadow would trace the transparent
        // panel rectangle, so the chip gets a clear margin wide enough for the shadow to fade
        // out fully, and lets clicks pass through it since the chip has no controls.
        // The margin is SwiftUI padding because NSHostingView sizes the panel to its content.
        let shadowMargin: CGFloat = isStatusChip ? 36 : 0
        state.reduceMotion = reduceMotion
        state.shadowMargin = shadowMargin
        state.phase = phase
        panel?.hasShadow = !isStatusChip
        panel?.ignoresMouseEvents = isStatusChip
        panel?.setContentSize(NSSize(width: size.width + shadowMargin * 2, height: size.height + shadowMargin * 2))
        position(anchor: accessibilityBounds, fallbackPoint: fallbackPoint, visibleSize: size, margin: shadowMargin)
        panel?.alphaValue = 0
        panel?.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : 0.08
            panel?.animator().alphaValue = 1
        }
    }

    func hide() { panel?.orderOut(nil) }

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

    var body: some View {
        ZStack {
            FeedbackPill(
                phase: state.phase,
                reduceMotion: state.reduceMotion,
                onClose: onClose
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
        case .noSelection: "no-selection"
        case .permissionDenied: "permission"
        case .limitReached: "limit-reached"
        case .offline: "offline"
        case .error(let message): "error-\(message)"
        }
    }
}
