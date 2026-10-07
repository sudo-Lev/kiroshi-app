import SwiftUI
import AppKit

@main
struct QwixitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

/// The full-color brand mark stays recognizable in the menu bar instead of
/// being flattened into a monochrome macOS template glyph.
private enum MenuBarQwixitGlyph {
    static let image: NSImage = {
        guard let source = NSImage(named: "QwixitMarkLight")?.copy() as? NSImage else {
            return NSImage()
        }
        source.size = NSSize(width: 18, height: 18)
        source.isTemplate = false
        return source
    }()
}

@MainActor
final class AppContainer {
    let settingsViewModel: SettingsViewModel
    let quickImproveViewModel: QuickImproveViewModel
    let feedback = FeedbackWindowController()
    let peekHotkey = PeekHotkey()
    let actionHotkey = HotkeyManager()
    let selectionReader: SelectionReading = SelectionReader()
    let peekPanel: PeekPanelController
    let palettePanel: PalettePanelController

    init() {
#if DEBUG
        // Simulations are session-scoped so a paywall preview can never leave
        // the next launch unable to make live requests.
        AppPreferences.resetDeveloperOverrides()
#endif
        let accessibility = AccessibilityService()
        LegacyMigration.run(isAccessibilityTrusted: accessibility.isTrusted)
        let improver = TextImprovementService()
        let peekViewModel = PeekViewModel(client: PeekClient(), detector: LanguageDetector())
        peekPanel = PeekPanelController(viewModel: peekViewModel)
        palettePanel = PalettePanelController(
            viewModel: PaletteViewModel(registry: ActionRegistry(), detector: LanguageDetector()),
            bridge: AXTextBridge(),
            improver: improver,
            hud: ResultHUDController(feedback: feedback)
        )
        settingsViewModel = SettingsViewModel(accessibility: accessibility)
        quickImproveViewModel = QuickImproveViewModel(
            accessibility: accessibility,
            improver: improver,
            feedback: feedback
        )
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let container = AppContainer()
    private let singleInstanceCoordinator = SingleInstanceCoordinator()
    private let runningToast = RunningToastController()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menuPopover = NSPopover()
    private var onboardingWindowController: OnboardingWindowController?
    private lazy var settingsWindowController = SettingsWindowController(
        viewModel: container.settingsViewModel,
        onShowOnboarding: { [weak self] in self?.showOnboardingForTesting() }
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { [weak self] in
            guard let self else { return }
            await singleInstanceCoordinator.terminateOtherInstances()
            finishLaunching()
        }
    }

    private func finishLaunching() {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        registerPeekHotkey(key: container.settingsViewModel.peekShortcutKey)
        container.settingsViewModel.onPeekShortcutChanged = { [weak self] key in
            self?.registerPeekHotkey(key: key)
        }
        registerActionHotkey()
        container.settingsViewModel.onPaletteTimingChanged = { [weak self] _ in
            self?.registerActionHotkey()
        }
        container.settingsViewModel.onMainHotkeyChanged = { [weak self] _ in
            self?.registerActionHotkey()
        }

        let settings = container.settingsViewModel
        if !settings.hasCompletedOnboarding || settings.needsRenamePermission {
            // Upgrading users only need the permission step again.
            if settings.hasCompletedOnboarding { settings.onboarding.step = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.showOnboarding()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        container.settingsViewModel.stop()
        container.quickImproveViewModel.stop()
        container.peekHotkey.stop()
        container.actionHotkey.stop()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        container.settingsViewModel.refreshAccessibility()
        container.settingsViewModel.refreshUsage()
    }

    func showSettings() {
        settingsWindowController.show()
    }

    func showOnboardingReplay() {
        container.settingsViewModel.restartOnboarding()
        showOnboarding()
    }

    private func showOnboarding() {
        let controller = onboardingWindowController
            ?? OnboardingWindowController(
                viewModel: container.settingsViewModel,
                onFinish: { [weak self] in self?.finishOnboarding() }
            )
        onboardingWindowController = controller
        controller.show()
    }

    private func showOnboardingForTesting() {
#if DEBUG
        container.settingsViewModel.resetOnboardingForTesting()
        showOnboarding()
#endif
    }

    private func togglePeek() async {
        if onboardingWindowController?.isVisible == true {
            return
        }
        runningToast.hotkeyPressed()
        if container.peekPanel.isVisible {
            container.peekPanel.close()
            return
        }
        let selection = await container.selectionReader.read()
        container.peekPanel.toggle(selection: selection)
    }

    private func registerPeekHotkey(key: String) {
        container.peekHotkey.start(key: key) { [weak self] in
            Task { @MainActor in await self?.togglePeek() }
        }
    }

    private func registerActionHotkey() {
        let settings = container.settingsViewModel
        let registered = container.actionHotkey.start(
            binding: settings.mainHotkey,
            intervalMilliseconds: settings.paletteDoubleTapMS,
            onSingle: { [weak self] in
                Task { @MainActor in self?.handleSingleActionHotkey() }
            },
            onDouble: { [weak self] in
                Task { @MainActor in await self?.handleDoubleActionHotkey() }
            }
        )
        settings.mainHotkeyConflict = !registered
    }

    private func handleSingleActionHotkey() {
        if onboardingWindowController?.isVisible == true {
            container.settingsViewModel.onboarding.handleMainHotkey()
            return
        }
        runningToast.hotkeyPressed()
        container.quickImproveViewModel.improveSelection()
    }

    private func handleDoubleActionHotkey() async {
        if onboardingWindowController?.isVisible == true {
            let onboarding = container.settingsViewModel.onboarding
            if onboarding.step == 3 {
                // The global classifier consumes both physical taps when it
                // recognizes a double press, so replay both for the tutorial.
                onboarding.handleMainHotkey()
                onboarding.handleMainHotkey()
            } else {
                onboarding.handleMainHotkey()
            }
            return
        }
        runningToast.hotkeyPressed()
        await container.palettePanel.toggle()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = MenuBarQwixitGlyph.image
        button.image?.size = NSSize(width: 18, height: 18)
        button.imagePosition = .imageOnly
        button.toolTip = "Qwixit"
        button.target = self
        button.action = #selector(toggleMenuPopover(_:))

        menuPopover.behavior = .transient
        menuPopover.animates = true
        menuPopover.contentSize = NSSize(width: 318, height: 360)
        menuPopover.contentViewController = NSHostingController(rootView: MenuBarView(
            settingsViewModel: container.settingsViewModel,
            quickImproveViewModel: container.quickImproveViewModel,
            onOpenSettings: { [weak self] in self?.menuPopover.performClose(nil); self?.showSettings() },
            onShowOnboarding: { [weak self] in self?.menuPopover.performClose(nil); self?.showOnboardingReplay() },
            onShowRunningToast: { [weak self] in self?.menuPopover.performClose(nil); self?.showRunningToast() },
            onQuit: { NSApp.terminate(nil) }
        ))
    }

    @objc private func toggleMenuPopover(_ sender: Any?) {
        runningToast.statusItemClicked()
        if menuPopover.isShown {
            menuPopover.performClose(sender)
        } else if let button = statusItem.button {
            menuPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func finishOnboarding() {
        container.settingsViewModel.completeOnboarding()
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.showRunningToast()
        }
    }

    private func showRunningToast() {
        let frame: () -> NSRect? = { [weak self] in
            self?.statusItem.button?.window?.frame
        }
        let pulse: () -> Void = { [weak self] in
            self?.pulseStatusItem()
        }
        runningToast.show(statusFrame: frame, pulse: pulse)
    }

    private func pulseStatusItem() {
        guard let button = statusItem.button else { return }
        button.wantsLayer = true
        let animation = CAKeyframeAnimation(keyPath: "transform.scale")
        animation.values = [1, 1.12, 1]
        animation.keyTimes = [0, 0.5, 1]
        animation.duration = 0.4
        button.layer?.add(animation, forKey: "qwixit.runningPulse")
    }
}

@MainActor
private final class SingleInstanceCoordinator {
    func terminateOtherInstances() async {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }

        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        let otherInstances = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != currentProcessIdentifier }

        guard !otherInstances.isEmpty else { return }
        otherInstances.forEach { $0.terminate() }

        for _ in 0..<10 {
            if otherInstances.allSatisfy(\.isTerminated) { return }
            try? await Task.sleep(for: .milliseconds(100))
        }

        otherInstances
            .filter { !$0.isTerminated }
            .forEach { $0.forceTerminate() }
    }
}

@MainActor
final class SettingsWindowController {
    private let viewModel: SettingsViewModel
    private let onShowOnboarding: () -> Void
    private var window: NSWindow?

    init(viewModel: SettingsViewModel, onShowOnboarding: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onShowOnboarding = onShowOnboarding
    }

    func show() {
        if window == nil {
#if DEBUG
            let windowHeight: CGFloat = 704
#else
            let windowHeight: CGFloat = 624
#endif
            let root = SettingsView(
                viewModel: viewModel,
                onShowOnboarding: onShowOnboarding,
                onQuit: { NSApp.terminate(nil) }
            )
            .frame(width: 500, height: windowHeight)

            let window = NSWindow(
                contentRect: .init(x: 0, y: 0, width: 500, height: windowHeight),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Qwixit Settings"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: root)
            window.center()
            self.window = window
        }

        if let window { AppWindowPresenter.present(window) }
    }
}

@MainActor
final class OnboardingWindowController {
    private let viewModel: SettingsViewModel
    private let onFinish: () -> Void
    private var window: NSWindow?
    private var keyMonitor: Any?

    init(viewModel: SettingsViewModel, onFinish: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onFinish = onFinish
    }

    var isVisible: Bool { window?.isVisible == true }

    func show() {
        installKeyMonitorIfNeeded()
        if window == nil {
            let root = OnboardingView(
                model: viewModel.onboarding,
                onFinish: { [weak self] in
                    self?.close()
                    self?.onFinish()
                }
            )
            .frame(width: 820, height: 640)

            let window = NSWindow(
                contentRect: .init(x: 0, y: 0, width: 820, height: 640),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Welcome to Qwixit"
            window.isReleasedWhenClosed = false
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true
            window.contentView = NSHostingView(rootView: root)
            window.contentView?.wantsLayer = true
            window.contentView?.layer?.cornerRadius = 12
            window.contentView?.layer?.masksToBounds = true
            window.center()
            self.window = window
        }

        if let window { AppWindowPresenter.present(window) }
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
                viewModel.onboarding.updateModifiers(
                    option: event.modifierFlags.contains(.option),
                    command: event.modifierFlags.contains(.command)
                )
                return event
            }

            if matchesMainHotkey(event) {
                viewModel.onboarding.handleMainHotkey()
                return nil
            }

            let onboarding = viewModel.onboarding
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
                    onboarding.chooseNumber(Int(event.keyCode - 18))
                default:
                    return event
                }
                return nil
            }

            if event.keyCode == 36 || event.keyCode == 76 {
                guard onboarding.canContinue else { return event }
                if onboarding.step == 4 { close(); onFinish() } else { onboarding.advance() }
                return nil
            }

            if event.keyCode == 53 { close(); return nil }

            return event
        }
    }

    private func matchesMainHotkey(_ event: NSEvent) -> Bool {
        let binding = viewModel.mainHotkey
        var expected: NSEvent.ModifierFlags = []
        if binding.modifiers.contains(.control) { expected.insert(.control) }
        if binding.modifiers.contains(.option) { expected.insert(.option) }
        if binding.modifiers.contains(.shift) { expected.insert(.shift) }
        if binding.modifiers.contains(.command) { expected.insert(.command) }
        let significant: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
        return UInt32(event.keyCode) == binding.keyCode
            && event.modifierFlags.intersection(significant) == expected
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }
}

/// Brings app windows to the front from a menu-bar-only (`.accessory`) app.
/// Since macOS 14 an accessory app's activation request can be ignored, which left
/// Settings ordered behind the frontmost app. While any presented window is open the
/// app runs as `.regular`; it drops back to `.accessory` when the last one closes.
@MainActor
enum AppWindowPresenter {
    private static var closeObservers: [ObjectIdentifier: NSObjectProtocol] = [:]

    static func present(_ window: NSWindow) {
        let id = ObjectIdentifier(window)
        if closeObservers[id] == nil {
            closeObservers[id] = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated { windowWillClose(id) }
            }
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private static func windowWillClose(_ id: ObjectIdentifier) {
        if let observer = closeObservers.removeValue(forKey: id) {
            NotificationCenter.default.removeObserver(observer)
        }
        if closeObservers.isEmpty { NSApp.setActivationPolicy(.accessory) }
    }
}
