import AppKit
import SwiftUI

@MainActor
final class ResultCardController {
    private let state = ResultCardState()
    private var panel: NSPanel?

    func show(
        action: PaletteAction,
        result: String,
        capture: PaletteCapture,
        onInsert: @escaping () -> Void,
        onAsk: @escaping (String) -> Void
    ) {
        state.action = action
        state.result = result
        state.isLoading = false
        state.onInsert = onInsert
        state.onAsk = onAsk
        let size = NSSize(width: 480, height: 360)
        if panel == nil {
            let panel = NSPanel(contentRect: .init(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .popUpMenu
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            panel.contentView = NSHostingView(rootView: ResultCard(state: state, onClose: { [weak self] in self?.panel?.orderOut(nil) }))
            self.panel = panel
        }
        panel?.setContentSize(size)
        if let origin = ContextPanelPlacement.resolve(
            accessibilityBounds: capture.bounds,
            fallbackPoint: capture.fallbackPoint,
            panelSize: size
        ) {
            panel?.setFrameOrigin(origin)
        }
        panel?.orderFrontRegardless()
        panel?.makeKey()
    }

    func setLoading(_ value: Bool) { state.isLoading = value }
    func update(result: String) { state.result = result; state.isLoading = false }
}

@MainActor
private final class ResultCardState: ObservableObject {
    @Published var action = PaletteAction(id: "result", name: "Result", hint: "", mode: .panel, prompt: "")
    @Published var result = ""
    @Published var isLoading = false
    var onInsert: () -> Void = { }
    var onAsk: (String) -> Void = { _ in }
}

private struct ResultCard: View {
    @ObservedObject var state: ResultCardState
    let onClose: () -> Void
    @State private var followUp = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("◆ \(state.action.name)").foregroundStyle(KColor.magenta)
                Spacer()
                Text("Text unchanged").foregroundStyle(KColor.secondary)
                Button("Esc", action: onClose)
                    .buttonStyle(CompactButtonStyle(accent: KColor.secondary))
            }
            .font(.system(size: 10, weight: .bold, design: .monospaced)).padding(16)
            Divider().overlay(KColor.line)
            ScrollView {
                if state.isLoading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small).tint(KColor.magenta)
                        Text("Qwixing…").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(0.35)
                    }
                    .padding(18)
                }
                Text(state.result).font(.system(size: 13)).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(18)
            }
            HStack {
                TextField("Ask about this text…", text: $followUp)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        let question = followUp.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !question.isEmpty else { return }
                        state.onAsk(question)
                        followUp = ""
                    }
                Button("Copy ⌘C") {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(state.result, forType: .string)
                }.buttonStyle(SubtleButtonStyle())
                Button("Insert below", action: state.onInsert).buttonStyle(PrimaryButtonStyle())
            }
            .padding(14)
        }
        .foregroundStyle(KColor.ink)
        .qwixitPanel()
        .qwixitTheme()
    }
}
