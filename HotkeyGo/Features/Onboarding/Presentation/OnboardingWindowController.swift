import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
    private let viewModel: OnboardingViewModel
    private let shortcuts: () -> OnboardingShortcuts
    private let onFinish: () -> Void
    private var window: NSWindow?
    private var keyMonitor: Any?

    init(
        viewModel: OnboardingViewModel,
        shortcuts: @escaping () -> OnboardingShortcuts,
        onFinish: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.shortcuts = shortcuts
        self.onFinish = onFinish
    }

    var isVisible: Bool { window?.isVisible == true }

    func show() {
        installKeyMonitorIfNeeded()
        if window == nil {
            let window = NSWindow(
                contentRect: .init(x: 0, y: 0, width: 820, height: 640),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Welcome to hotkeygo"
            window.setAccessibilityLabel("hotkeygo onboarding")
            window.isReleasedWhenClosed = false
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true
            window.center()
            self.window = window
        }

        guard let window else { return }
        let root = OnboardingView(
            viewModel: viewModel,
            shortcuts: shortcuts(),
            onFinish: { [weak self] in
                self?.close()
                self?.onFinish()
            }
        )
        .frame(width: 820, height: 640)
        let hostingView = NSHostingView(rootView: root)
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 12
        hostingView.layer?.masksToBounds = true
        window.contentView = hostingView
        AppWindowPresenter.present(window)
    }

    func close() {
        window?.close()
        window = nil
    }

    private func installKeyMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, isVisible else { return event }

            if event.type == .flagsChanged {
                viewModel.updateModifiers(
                    control: event.modifierFlags.contains(.control),
                    option: event.modifierFlags.contains(.option),
                    shift: event.modifierFlags.contains(.shift),
                    command: event.modifierFlags.contains(.command)
                )
                return event
            }

            let currentShortcuts = shortcuts()
            if OnboardingHotkeyRouter.routePracticeShortcut(
                event,
                viewModel: viewModel,
                fix: currentShortcuts.fix,
                actions: currentShortcuts.actions,
                peek: currentShortcuts.peek
            ) {
                return nil
            }

            let onboarding = viewModel
            if onboarding.phase == .palette {
                switch event.keyCode {
                case 53:
                    _ = onboarding.escapeOverlay()
                case 126, 48:
                    onboarding.moveSelection(by: -1)
                case 125:
                    onboarding.moveSelection(by: 1)
                case 36, 76:
                    onboarding.confirmSelection()
                case 18...21:
                    guard onboarding.chooseNumber(Int(event.keyCode - 17)) else { return event }
                default:
                    return event
                }
                return nil
            }

            if onboarding.phase == .peekChoice {
                switch event.keyCode {
                case 53:
                    _ = onboarding.escapeOverlay()
                case 126:
                    onboarding.moveSelection(by: -1)
                case 125:
                    onboarding.moveSelection(by: 1)
                case 48:
                    onboarding.moveSelection(by: event.modifierFlags.contains(.shift) ? -1 : 1)
                case 36, 76:
                    onboarding.confirmSelection()
                case 18...21:
                    guard onboarding.choosePeekNumber(Int(event.keyCode - 17)) else { return event }
                default:
                    return event
                }
                return nil
            }

            if onboarding.step == .peek,
               (onboarding.phase == .peekProcessing || onboarding.phase == .peek),
               event.keyCode == 53 {
                _ = onboarding.escapeOverlay()
                return nil
            }

            if onboarding.step == .peek, onboarding.phase == .peek,
               event.keyCode == 8,
               event.modifierFlags.contains(.command) {
                onboarding.copyPeekResult()
                return nil
            }

            if onboarding.step == .peek, onboarding.phase == .peek {
                switch event.keyCode {
                case 48:
                    onboarding.cyclePeekLanguage(by: event.modifierFlags.contains(.shift) ? -1 : 1)
                    return nil
                case 18...21:
                    guard onboarding.choosePeekResultNumber(Int(event.keyCode - 17)) else { return event }
                    return nil
                default:
                    break
                }
            }

            if event.keyCode == 36 || event.keyCode == 76 {
                guard onboarding.canContinue else { return event }
                if onboarding.step == .complete { close(); onFinish() } else { onboarding.advance() }
                return nil
            }

            if event.keyCode == 53 { close(); return nil }

            return event
        }
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }
}

@MainActor
enum OnboardingHotkeyRouter {
    static func routePracticeShortcut(
        _ event: NSEvent,
        viewModel: OnboardingViewModel,
        fix: HotkeyBinding,
        actions: HotkeyBinding,
        peek: HotkeyBinding
    ) -> Bool {
        if actions.matches(event) {
            viewModel.handleActionHotkey()
            return true
        }
        if fix.matches(event) {
            viewModel.handleMainHotkey()
            return true
        }
        if peek.matches(event) {
            viewModel.handlePeekHotkey()
            return true
        }
        return false
    }
}
