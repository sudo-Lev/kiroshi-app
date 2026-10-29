import AppKit
import SwiftUI

@MainActor
final class AccessibilityAccessNoticeController: AccessibilityAccessNoticePresenting {
    private let accessibility: AccessibilityServicing
    private let onPermissionRequested: () -> Void
    private let state = AccessibilityAccessNoticeState()
    private let dismissAfter: TimeInterval
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?

    init(
        accessibility: AccessibilityServicing,
        dismissAfter: TimeInterval = 8,
        onPermissionRequested: @escaping () -> Void = {}
    ) {
        self.accessibility = accessibility
        self.onPermissionRequested = onPermissionRequested
        self.dismissAfter = min(max(dismissAfter, 5), 10)
        state.duration = self.dismissAfter
    }

    func showAccessibilityAccessNeeded(at point: CGPoint) {
        guard !accessibility.isTrusted else {
            dismissImmediately()
            return
        }

        hideTask?.cancel()
        hideTask = nil
        state.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            || !AppPreferences().animationsEnabled

        let panel = makePanelIfNeeded()
        panel.setContentSize(AccessibilityAccessNoticePlate.size)
        position(panel, around: point)

        let wasVisible = panel.isVisible
        panel.orderFrontRegardless()
        if !wasVisible {
            state.isPresented = false
            withAnimation(.easeOut(duration: 0.25)) {
                state.isPresented = true
            }
        } else {
            state.isPresented = true
        }

        let pointerIsHovering = NSMouseInRect(NSEvent.mouseLocation, panel.frame, false)
        restartCountdown(pointerIsHovering: pointerIsHovering)
        announceNotice()
    }

    private func makePanelIfNeeded() -> NSPanel {
        if let panel { return panel }

        let panel = AccessibilityNoticePanel(
            contentRect: NSRect(origin: .zero, size: AccessibilityAccessNoticePlate.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(
            rootView: AccessibilityAccessNoticePlate(
                state: state,
                onHoverChanged: { [weak self] isHovering in self?.setHovering(isHovering) },
                onOpenSettings: { [weak self] in self?.openSettings() }
            )
        )
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel, around point: CGPoint) {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
        guard let screen else { return }
        let visibleFrame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: visibleFrame.midX - AccessibilityAccessNoticePlate.size.width / 2,
            y: visibleFrame.maxY - AccessibilityAccessNoticePlate.size.height - 12
        ))
    }

    private func restartCountdown(pointerIsHovering: Bool) {
        dismissTask?.cancel()
        dismissTask = nil
        state.startCountdown(
            duration: dismissAfter,
            hovering: pointerIsHovering,
            now: ProcessInfo.processInfo.systemUptime
        )
        guard !pointerIsHovering else { return }
        scheduleDismiss(after: dismissAfter)
    }

    private func setHovering(_ isHovering: Bool) {
        guard state.isHovering != isHovering else { return }
        let now = ProcessInfo.processInfo.systemUptime
        state.isHovering = isHovering
        if isHovering {
            state.pauseCountdown(at: now)
            dismissTask?.cancel()
            dismissTask = nil
        } else {
            state.resumeCountdown(at: now)
            scheduleDismiss(after: state.remainingTime(at: now))
        }
    }

    private func scheduleDismiss(after interval: TimeInterval) {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(max(interval, 0)))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.dismissAfterTimeout()
        }
    }

    private func dismissAfterTimeout() {
        dismissTask = nil
        state.finishCountdown()
        withAnimation(.easeOut(duration: 0.25)) {
            state.isPresented = false
        }
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
            self?.hideTask = nil
        }
    }

    private func openSettings() {
        accessibility.requestPermission()
        onPermissionRequested()
        dismissImmediately()
    }

    private func dismissImmediately() {
        dismissTask?.cancel()
        dismissTask = nil
        hideTask?.cancel()
        hideTask = nil
        state.finishCountdown()
        state.isPresented = false
        panel?.orderOut(nil)
    }

    private func announceNotice() {
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                NSAccessibility.NotificationUserInfoKey.announcement: "Accessibility access needed. Open System Settings.",
                NSAccessibility.NotificationUserInfoKey.priority: NSNumber(value: 90)
            ]
        )
    }
}

@MainActor
private final class AccessibilityAccessNoticeState: ObservableObject {
    @Published var isPresented = false
    @Published var isHovering = false
    @Published var isCountdownRunning = false
    @Published var reduceMotion = false

    var duration: TimeInterval = 8
    private var remainingWhenPaused: TimeInterval = 8
    private var countdownStartedAt: TimeInterval?

    func startCountdown(duration: TimeInterval, hovering: Bool, now: TimeInterval) {
        self.duration = duration
        remainingWhenPaused = duration
        isHovering = hovering
        countdownStartedAt = hovering ? nil : now
        isCountdownRunning = !hovering
    }

    func remainingTime(at now: TimeInterval) -> TimeInterval {
        guard let countdownStartedAt else { return remainingWhenPaused }
        return max(0, remainingWhenPaused - (now - countdownStartedAt))
    }

    func progress(at now: TimeInterval) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(min(max(remainingTime(at: now) / duration, 0), 1))
    }

    func pauseCountdown(at now: TimeInterval) {
        guard isCountdownRunning else { return }
        remainingWhenPaused = remainingTime(at: now)
        countdownStartedAt = nil
        isCountdownRunning = false
    }

    func resumeCountdown(at now: TimeInterval) {
        guard !isCountdownRunning, remainingWhenPaused > 0 else { return }
        countdownStartedAt = now
        isCountdownRunning = true
    }

    func finishCountdown() {
        remainingWhenPaused = 0
        countdownStartedAt = nil
        isCountdownRunning = false
    }
}

@MainActor
private struct AccessibilityAccessNoticePlate: View {
    static let size = NSSize(width: 372, height: 62)

    @ObservedObject var state: AccessibilityAccessNoticeState
    let onHoverChanged: (Bool) -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        Button(action: onOpenSettings) {
            plate
        }
        .buttonStyle(AccessibilityNoticeButtonStyle(
            isPresented: state.isPresented,
            reduceMotion: state.reduceMotion
        ))
        .onHover(perform: onHoverChanged)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Accessibility access needed. Open System Settings.")
        .accessibilityHint("Opens Privacy & Security, Accessibility.")
    }

    private var plate: some View {
        HStack(spacing: 14) {
            HotkeyGoFaceView(
                face: .boot,
                size: 11,
                reduceMotion: state.reduceMotion,
                color: AccessNoticeColor.warning,
                chromaticSplit: 1
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility access needed")
                    .font(.system(size: 13.5, weight: .heavy, design: .default))
                    .tracking(-0.1)
                    .foregroundStyle(AccessNoticeColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .frame(height: 17)

                Text("Privacy & Security › Accessibility")
                    .font(Self.detailFont)
                    .foregroundStyle(AccessNoticeColor.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .allowsTightening(true)
                    .frame(height: 14)
            }
            .layoutPriority(1)

            Spacer(minLength: 0)

            openKey
        }
        .padding(.leading, 16)
        .padding(.trailing, 18)
        .padding(.top, 13)
        .padding(.bottom, 15)
        .frame(width: Self.size.width, height: Self.size.height)
        .background {
            ZStack {
                CutCornerShape(cut: 12)
                    .fill(borderGradient)
                CutCornerShape(cut: 11.4)
                    .fill(AccessNoticeColor.plate)
                    .padding(1.5)
            }
        }
        .clipShape(CutCornerShape(cut: 12))
        .overlay(alignment: .topLeading) {
            Rectangle()
                .fill(AccessNoticeColor.ink.opacity(0.7))
                .frame(width: 30, height: 1.5)
                .offset(x: 20)
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(AccessNoticeColor.warning)
                .frame(width: 2, height: Self.size.height - 32)
        }
        .overlay(alignment: .bottom) {
            countdownLine
                .padding(.leading, 18)
                .padding(.trailing, 12)
        }
        .shadow(color: AccessNoticeColor.cyan, radius: 0, x: -1, y: 0)
        .shadow(color: AccessNoticeColor.magenta, radius: 0, x: 1, y: 0)
        .shadow(color: .black.opacity(0.45), radius: 22, x: 0, y: 10)
        .compositingGroup()
    }

    private var borderGradient: LinearGradient {
        LinearGradient(
            colors: [
                AccessNoticeColor.warning.opacity(state.isHovering ? 1 : 0.7),
                AccessNoticeColor.violet.opacity(state.isHovering ? 0.7 : 0.6)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var openKey: some View {
        HStack(spacing: 6) {
            Text("OPEN")
                .font(Self.keyFont)
                .tracking(1)
            Text("↗")
                .font(.system(size: 12, weight: .medium))
                .offset(x: shouldNudgeArrow ? 1.5 : 0, y: shouldNudgeArrow ? -1.5 : 0)
                .animation(.easeOut(duration: 0.12), value: state.isHovering)
        }
        .foregroundStyle(state.isHovering ? AccessNoticeColor.plate : AccessNoticeColor.warning)
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .frame(height: 30)
        .background {
            ZStack {
                CutCornerShape(cut: 7)
                    .fill(AccessNoticeColor.warning)
                CutCornerShape(cut: 6.4)
                    .fill(AccessNoticeColor.plate)
                    .padding(1.5)
                CutCornerShape(cut: 6.4)
                    .fill(state.isHovering ? AccessNoticeColor.warning : AccessNoticeColor.warning.opacity(0.16))
                    .padding(1.5)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityHidden(true)
    }

    private var shouldNudgeArrow: Bool {
        state.isHovering && !state.reduceMotion
    }

    private var countdownLine: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !state.isCountdownRunning)) { _ in
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle().fill(AccessNoticeColor.ink.opacity(0.08))
                    Rectangle()
                        .fill(AccessNoticeColor.warning)
                        .frame(width: geometry.size.width * state.progress(at: ProcessInfo.processInfo.systemUptime))
                }
            }
            .frame(height: 1.5)
        }
        .accessibilityHidden(true)
    }

    private static var detailFont: Font {
        NSFont(name: "JetBrains Mono Medium", size: 10.5) != nil
            ? .custom("JetBrains Mono Medium", fixedSize: 10.5)
            : .system(size: 10.5, weight: .medium, design: .monospaced)
    }

    private static var keyFont: Font {
        NSFont(name: "JetBrains Mono ExtraBold", size: 11) != nil
            ? .custom("JetBrains Mono ExtraBold", fixedSize: 11)
            : .system(size: 11, weight: .heavy, design: .monospaced)
    }
}

private struct AccessibilityNoticeButtonStyle: ButtonStyle {
    let isPresented: Bool
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: isPresented ? (configuration.isPressed && !reduceMotion ? 1 : 0) : (reduceMotion ? 0 : -6))
            .opacity(isPresented ? 1 : 0)
            .animation(.easeOut(duration: 0.25), value: isPresented)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private enum AccessNoticeColor {
    static let ink = Color(nsColor: HotkeyGoColor.hex(0xF1EDFA))
    static let secondary = Color(nsColor: HotkeyGoColor.hex(0xB0ABBF))
    static let plate = Color(nsColor: HotkeyGoColor.hex(0x14111C))
    static let warning = Color(nsColor: HotkeyGoColor.hex(0xFAA629))
    static let violet = Color(nsColor: HotkeyGoColor.hex(0x9661FF))
    static let cyan = Color(nsColor: HotkeyGoColor.hex(0x26C9E3))
    static let magenta = Color(nsColor: HotkeyGoColor.hex(0xFF4FAD))
}

private final class AccessibilityNoticePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
