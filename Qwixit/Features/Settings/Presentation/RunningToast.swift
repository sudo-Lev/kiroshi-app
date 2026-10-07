import AppKit
import SwiftUI

@MainActor
final class RunningToastState: ObservableObject {
    @Published var title = "Yo. I’m working"
    @Published var isVisible = false
    @Published var isHovering = false
    @Published var blink = false
    @Published var arrowOffset: CGFloat = 0
    @Published var remainingActions: Int?
    @Published var isUnlimited = false
}

final class RunningToastPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class RunningToastController {
    static let size = NSSize(width: 328, height: 140)

    private let state = RunningToastState()
    private var panel: RunningToastPanel?
    private var dismissTask: Task<Void, Never>?
    private var blinkTask: Task<Void, Never>?
    private var escapeMonitor: Any?

    var isVisible: Bool { panel?.isVisible == true }

    func show(statusFrame: @escaping () -> NSRect?, pulse: @escaping () -> Void) {
        show(statusFrame: statusFrame, pulse: pulse, attemptsRemaining: 8)
    }

    private func show(
        statusFrame: @escaping () -> NSRect?,
        pulse: @escaping () -> Void,
        attemptsRemaining: Int
    ) {
        guard let anchor = statusFrame() else {
            guard attemptsRemaining > 0 else { return }
            dismissTask?.cancel()
            dismissTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                self?.show(
                    statusFrame: statusFrame,
                    pulse: pulse,
                    attemptsRemaining: attemptsRemaining - 1
                )
            }
            return
        }

        let preferences = AppPreferences()
        state.title = "Yo. I’m working"
        state.remainingActions = preferences.remainingActions
        state.isUnlimited = preferences.isUnlimited
        state.isVisible = false
        state.blink = false
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.appearance = NSAppearance(
            named: preferences.appearance == .dark ? .darkAqua : .aqua
        )
        position(panel, below: anchor)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        installEscapeMonitor()

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.35, dampingFraction: 0.85)) {
            state.isVisible = true
        }
        if !reduceMotion { pulse() }
        scheduleDismiss(after: .seconds(7))
        blinkTask?.cancel()
        blinkTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self else { return }
            state.blink = true
            try? await Task.sleep(for: .milliseconds(150))
            state.blink = false
        }
        announce()
    }

    func statusItemClicked() { hide() }

    func hotkeyPressed() {
        guard isVisible else { return }
        dismissTask?.cancel()
        state.title = "Nice — that's it."
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            self?.hide()
        }
    }

    func hide() {
        dismissTask?.cancel()
        guard let panel, panel.isVisible else { return }
        blinkTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { state.isVisible = false }
        dismissTask = Task { [weak self, weak panel] in
            try? await Task.sleep(for: .milliseconds(200))
            panel?.orderOut(nil)
            self?.removeEscapeMonitor()
        }
    }

    private func makePanel() -> RunningToastPanel {
        let panel = RunningToastPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: RunningToastView(
            state: state,
            onDismiss: { [weak self] in self?.hide() },
            onHover: { [weak self] hovering in self?.hoverChanged(hovering) }
        ))
        return panel
    }

    private func position(_ panel: NSPanel, below anchor: NSRect) {
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let preferredX = anchor.midX - Self.size.width / 2
        let x = min(max(preferredX, visible.minX + 8), visible.maxX - Self.size.width - 8)
        let y = anchor.minY - Self.size.height - 6
        state.arrowOffset = min(max(anchor.midX - (x + Self.size.width / 2), -138), 138)
        panel.setFrameOrigin(NSPoint(x: x, y: max(y, visible.minY + 8)))
    }

    private func hoverChanged(_ hovering: Bool) {
        state.isHovering = hovering
        dismissTask?.cancel()
        if !hovering { scheduleDismiss(after: .seconds(2)) }
    }

    private func scheduleDismiss(after duration: Duration) {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, self?.state.isHovering == false else { return }
            self?.hide()
        }
    }

    private func installEscapeMonitor() {
        removeEscapeMonitor()
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            Task { @MainActor in self?.hide() }
        }
    }

    private func removeEscapeMonitor() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
    }

    private func announce() {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                NSAccessibility.NotificationUserInfoKey.announcement: "Qwixit is working. Select text anywhere, then press Option Command X to fix, press it twice to choose an action, or press Option Command Z to peek.",
                NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.medium.rawValue
            ]
        )
    }
}

struct RunningToastView: View {
    @ObservedObject var state: RunningToastState
    let onDismiss: () -> Void
    let onHover: (Bool) -> Void
    @AppStorage(AppPreferenceKey.appearance) private var rawAppearance = AppAppearance.light.rawValue
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            Triangle().fill(KColor.surface).frame(width: 16, height: 8).offset(x: state.arrowOffset)
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 9) {
                        QwixitMark(size: 23)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(state.title)
                                .font(.system(size: 13.5, weight: .bold))
                            Text("Select text anywhere, then:")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(KColor.secondary)
                        }
                        Spacer()
                        if hovering {
                            Button(action: onDismiss) {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(IconButtonStyle())
                            .accessibilityLabel("Dismiss")
                        }
                    }

                    HStack(spacing: 12) {
                        shortcut(modifiers: "⌥⌘", key: "X", title: "Fix")
                        shortcut(modifiers: "⌥⌘", key: "X", suffix: "×2", title: "Choose")
                        shortcut(modifiers: "⌥⌘", key: "Z", title: "Peek")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 13)
                .padding(.bottom, 12)

                HStack(spacing: 8) {
                    Text(state.blink ? "[ -_- ]" : "[ ^_^ ]")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(KColor.ink)
                    Text(usageLabel)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(KColor.ink)
                    Spacer()
                    Text(remainingLabel)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(KColor.secondary)
                }
                .padding(.horizontal, 14)
                .frame(height: 35)
                .background(KColor.canvas)
                .overlay(alignment: .top) { Rectangle().fill(KColor.line).frame(height: 1) }
            }
            .frame(width: 300, alignment: .leading)
            .background(KColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
        }
        .frame(width: Self.viewWidth, height: 140, alignment: .top)
        .contentShape(Rectangle()).onTapGesture(perform: onDismiss)
        .onHover { hovering = $0; onHover($0) }
        .opacity(state.isVisible ? 1 : 0).offset(y: state.isVisible ? 0 : -6)
        .accessibilityHidden(true)
        .preferredColorScheme(appearance.colorScheme)
    }

    static let viewWidth: CGFloat = 328

    private var appearance: AppAppearance {
        AppAppearance(rawValue: rawAppearance) ?? .light
    }

    private var remainingActions: Int {
        min(max(state.remainingActions ?? 30, 0), 30)
    }

    private var usageLabel: String {
        state.isUnlimited ? "Unlimited" : "\(30 - remainingActions) / 30 used"
    }

    private var remainingLabel: String {
        state.isUnlimited ? "all unlocked" : "\(remainingActions) free left"
    }

    private func shortcut(
        modifiers: String,
        key: String,
        suffix: String? = nil,
        title: String
    ) -> some View {
        HStack(spacing: 5) {
            HStack(spacing: 2) {
                Text(modifiers).foregroundStyle(KColor.secondary)
                Text(key).foregroundStyle(KColor.violet)
                if let suffix {
                    Text(suffix).foregroundStyle(KColor.secondary)
                }
            }
            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
            .padding(.horizontal, 6)
            .frame(height: 22)
            .background(KColor.surfaceHover)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(KColor.line, lineWidth: 1)
            }

            Text(title)
                .font(.system(size: 10.5, weight: .bold))
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in path.move(to: CGPoint(x: rect.midX, y: rect.minY)); path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY)); path.closeSubpath() }
    }
}

#Preview("Running toast") {
    let state = RunningToastState(); state.isVisible = true
    return RunningToastView(state: state, onDismiss: {}, onHover: { _ in })
}
