import SwiftUI
import AppKit

@main
struct QwixitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

/// The supplied menu-bar asset is a monochrome template image, so AppKit
/// handles the correct contrast for the current menu bar appearance.
private enum MenuBarTokiriGlyph {
    static func image() -> NSImage {
        guard let source = NSImage(named: "QwixitMenuBar")?.copy() as? NSImage else {
            return NSImage()
        }
        source.isTemplate = true
        return source
    }
}

@MainActor
final class AppContainer {
    let settingsViewModel: SettingsViewModel
    let quickImproveViewModel: QuickImproveViewModel
    let popupDismiss = PopupDismissCoordinator()
    let feedback: FeedbackWindowController
    let review: ReviewPanelController
    let replacementRecovery: ReplacementRecoveryPanelController
    let peekHotkey = PeekHotkey()
    let fixHotkey = GlobalHotKey()
    let actionHotkey = ActionHotkey()
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
        let settings = SettingsViewModel(accessibility: accessibility)
        settingsViewModel = settings
        feedback = FeedbackWindowController(
            popupDismiss: popupDismiss,
            onUpgrade: { settings.openStarterCheckout() }
        )
        review = ReviewPanelController(popupDismiss: popupDismiss)
        replacementRecovery = ReplacementRecoveryPanelController(popupDismiss: popupDismiss)
        peekPanel = PeekPanelController(
            viewModel: peekViewModel,
            popupDismiss: popupDismiss,
            onUpgrade: { settings.openStarterCheckout() }
        )
        palettePanel = PalettePanelController(
            viewModel: PaletteViewModel(registry: ActionRegistry(), detector: LanguageDetector()),
            bridge: AXTextBridge(),
            improver: improver,
            hud: ResultHUDController(feedback: feedback),
            replacementRecovery: replacementRecovery,
            popupDismiss: popupDismiss
        )
        quickImproveViewModel = QuickImproveViewModel(
            accessibility: accessibility,
            improver: improver,
            feedback: feedback,
            recovery: replacementRecovery,
            review: review,
            selectionSnapshots: accessibility
        )
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let container = AppContainer()
    private let singleInstanceCoordinator = SingleInstanceCoordinator()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private lazy var menuPopover = MenuBarPopoverController(popupDismiss: container.popupDismiss)
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
        registerPeekHotkey(binding: container.settingsViewModel.peekHotkey)
        container.settingsViewModel.onPeekHotkeyChanged = { [weak self] binding in
            self?.registerPeekHotkey(binding: binding)
        }
        container.settingsViewModel.onActionHotkeyChanged = { [weak self] binding in
            self?.registerActionHotkey(binding: binding)
        }
        container.settingsViewModel.onAppearanceChanged = { [weak self] appearance in
            self?.updateStatusItemAppearance(appearance)
        }
        registerFixHotkey()
        registerActionHotkey(binding: container.settingsViewModel.actionsHotkey)
        container.settingsViewModel.onMainHotkeyChanged = { [weak self] _ in
            self?.registerFixHotkey()
        }

        let settings = container.settingsViewModel
        settings.refreshUsage()
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
        container.fixHotkey.unregister()
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
        if container.peekPanel.isVisible {
            container.peekPanel.close()
            return
        }
        let selection = await container.selectionReader.read()
        container.peekPanel.toggle(selection: selection)
    }

    private func registerPeekHotkey(binding: HotkeyBinding) {
        let registered = container.peekHotkey.start(binding: binding) { [weak self] in
            Task { @MainActor in await self?.togglePeek() }
        }
        container.settingsViewModel.peekHotkeyConflict = !registered
    }

    private func registerFixHotkey() {
        let settings = container.settingsViewModel
        // Release the old Fix registration before the shared close binding is
        // updated; either one may own ⌥⌘X while a popup is visible.
        container.fixHotkey.unregister()
        container.popupDismiss.setMainBinding(settings.mainHotkey)
        let registered = container.fixHotkey.register(
            keyCode: settings.mainHotkey.keyCode,
            modifiers: settings.mainHotkey.modifiers
        ) { [weak self] in
            Task { @MainActor in self?.handleFixHotkey() }
        }
        settings.mainHotkeyConflict = !registered
    }

    private func registerActionHotkey(binding: HotkeyBinding) {
        let registered = container.actionHotkey.start(binding: binding) { [weak self] in
            Task { @MainActor in await self?.handleActionHotkey() }
        }
        container.settingsViewModel.actionHotkeyConflict = !registered
    }

    private func handleFixHotkey() {
        if onboardingWindowController?.isVisible == true {
            container.settingsViewModel.onboarding.handleMainHotkey()
            return
        }
        if menuPopover.isShown {
            menuPopover.close()
            return
        }
        if container.settingsViewModel.mainHotkey == HotkeyCatalog.popupDismiss,
           container.popupDismiss.dismissTop() {
            return
        }
        container.quickImproveViewModel.improveSelection()
    }

    private func handleActionHotkey() async {
        if onboardingWindowController?.isVisible == true {
            container.settingsViewModel.onboarding.handleActionHotkey()
            return
        }
        await container.palettePanel.toggle()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        updateStatusItemAppearance(container.settingsViewModel.appearance)
        button.toolTip = "Tokiri"
        button.target = self
        button.action = #selector(toggleMenuPopover(_:))

        menuPopover.setContentView(NSHostingView(rootView: MenuBarView(
            settingsViewModel: container.settingsViewModel,
            quickImproveViewModel: container.quickImproveViewModel,
            onOpenSettings: { [weak self] in self?.menuPopover.close(); self?.showSettings() },
            onShowOnboarding: { [weak self] in self?.menuPopover.close(); self?.showOnboardingReplay() },
            onQuit: { NSApp.terminate(nil) },
            onClose: { [weak self] in self?.menuPopover.close() }
        )))
    }

    private func updateStatusItemAppearance(_ appearance: AppAppearance) {
        guard let button = statusItem.button else { return }
        button.image = MenuBarTokiriGlyph.image()
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
    }

    @objc private func toggleMenuPopover(_ sender: Any?) {
        if menuPopover.isShown {
            menuPopover.close()
        } else if let button = statusItem.button {
            container.settingsViewModel.refreshAccessibility()
            container.settingsViewModel.refreshUsage()
            menuPopover.show(relativeTo: button)
        }
    }

    private func finishOnboarding() {
        container.settingsViewModel.completeOnboarding()
    }
}

@MainActor
private final class MenuBarPopoverController: NSObject {
    private let panel: MenuBarPopoverPanel
    private let popupDismiss: PopupDismissCoordinator
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?

    var isShown: Bool { panel.isVisible }

    init(popupDismiss: PopupDismissCoordinator) {
        self.popupDismiss = popupDismiss
        panel = MenuBarPopoverPanel(
            contentRect: NSRect(x: 0, y: 0, width: 318, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        // The app is an accessory process, so it remains inactive when the
        // status item is clicked. Closing on deactivation would hide the panel
        // immediately after it is ordered front; the mouse monitors below keep
        // the transient behavior instead.
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.onCancel = { [weak self] in self?.close() }
    }

    deinit {
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
    }

    func setContentView(_ contentView: NSView) {
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = contentView
        contentView.frame = NSRect(x: 0, y: 0, width: 318, height: 1)
        contentView.layoutSubtreeIfNeeded()

        let fittingSize = contentView.fittingSize
        panel.setContentSize(NSSize(
            width: 318,
            height: max(1, fittingSize.height)
        ))
    }

    func show(relativeTo button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }

        let buttonRect = buttonWindow.convertToScreen(
            button.convert(button.bounds, to: nil)
        )
        var visibleFrame = NSScreen.main?.visibleFrame
        let buttonCenter = NSPoint(x: buttonRect.midX, y: buttonRect.midY)
        for screen in NSScreen.screens where screen.frame.contains(buttonCenter) {
            visibleFrame = screen.visibleFrame
            break
        }
        guard let visibleFrame else { return }

        let panelSize = panel.frame.size
        let x = min(
            max(buttonRect.midX - panelSize.width / 2, visibleFrame.minX + 8),
            visibleFrame.maxX - panelSize.width - 8
        )
        let y = min(
            max(buttonRect.minY - panelSize.height - 8, visibleFrame.minY + 8),
            visibleFrame.maxY - panelSize.height - 8
        )

        panel.setFrameOrigin(NSPoint(x: x, y: y))
        installMouseMonitorsIfNeeded()
        panel.orderFrontRegardless()
        popupDismiss.show(panel) { [weak self] in self?.close() }
    }

    func close() {
        popupDismiss.hide(panel)
        panel.orderOut(nil)
    }

    private func installMouseMonitorsIfNeeded() {
        guard globalMouseMonitor == nil else { return }

        let events: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            guard let self, self.isShown, !self.panel.frame.contains(NSEvent.mouseLocation) else { return }
            self.close()
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            guard let self, self.isShown, !self.panel.frame.contains(NSEvent.mouseLocation) else { return event }
            self.close()
            return event
        }
    }
}

private final class MenuBarPopoverPanel: NSPanel {
    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
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
            window.title = "Tokiri Settings"
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
                fixShortcut: viewModel.mainHotkey,
                actionShortcut: viewModel.actionsHotkey,
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
            window.title = "Welcome to Tokiri"
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
                    control: event.modifierFlags.contains(.control),
                    option: event.modifierFlags.contains(.option),
                    shift: event.modifierFlags.contains(.shift),
                    command: event.modifierFlags.contains(.command)
                )
                return event
            }

            if matchesActionHotkey(event) {
                viewModel.onboarding.handleActionHotkey()
                return nil
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
        matches(event, binding: viewModel.mainHotkey)
    }

    private func matchesActionHotkey(_ event: NSEvent) -> Bool {
        matches(event, binding: viewModel.actionsHotkey)
    }

    private func matches(_ event: NSEvent, binding: HotkeyBinding) -> Bool {
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
