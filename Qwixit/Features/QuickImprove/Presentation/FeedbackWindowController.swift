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
        let size: NSSize
        if phase == .limitReached { size = .init(width: 354, height: 126) }
        else if case .error = phase { size = .init(width: 354, height: 116) }
        else if phase == .permissionDenied { size = .init(width: 280, height: 68) }
        else if phase == .processing || phase == .success { size = .init(width: 236, height: 58) }
        else { size = .init(width: 260, height: 64) }
        if panel == nil {
            let panel = NSPanel(contentRect: .init(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.contentView = NSHostingView(rootView: FeedbackHost(state: state))
            self.panel = panel
        }
        state.reduceMotion = reduceMotion
        state.phase = phase
        panel?.setContentSize(size)
        position(anchor: accessibilityBounds, fallbackPoint: fallbackPoint, panelSize: size)
        panel?.alphaValue = 0
        panel?.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : 0.08
            panel?.animator().alphaValue = 1
        }
    }

    func hide() { panel?.orderOut(nil) }

    private func position(anchor accessibilityBounds: CGRect?, fallbackPoint: CGPoint?, panelSize: NSSize) {
        guard let panel else { return }
        guard let origin = ContextPanelPlacement.resolve(
            accessibilityBounds: accessibilityBounds,
            fallbackPoint: fallbackPoint ?? NSEvent.mouseLocation,
            panelSize: panelSize
        ) else { return }
        panel.setFrameOrigin(origin)
    }
}

@MainActor
private final class FeedbackWindowState: ObservableObject {
    @Published var phase: AppPhase = .ready
    @Published var reduceMotion = false
}

private struct FeedbackHost: View {
    @ObservedObject var state: FeedbackWindowState

    var body: some View {
        ZStack {
            FeedbackPill(phase: state.phase, reduceMotion: state.reduceMotion)
                .id(phaseKey)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.97)),
                        removal: .opacity.combined(with: .scale(scale: 1.015))
                    )
                )
        }
        .animation(state.reduceMotion ? nil : .snappy(duration: 0.13), value: phaseKey)
    }

    private var phaseKey: String {
        switch state.phase {
        case .ready: "ready"
        case .processing: "processing"
        case .success: "success"
        case .noSelection: "no-selection"
        case .permissionDenied: "permission"
        case .limitReached: "limit-reached"
        case .error(let message): "error-\(message)"
        }
    }
}
