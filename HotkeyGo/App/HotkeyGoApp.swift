import SwiftUI
import AppKit

@main
struct HotkeyGoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppContainer {
    let settingsViewModel: SettingsViewModel
    let onboardingViewModel: OnboardingViewModel
    let quickImproveViewModel: QuickImproveViewModel
    let planStatus: PlanStatus
    let popupDismiss = PopupDismissCoordinator()
    let feedback: FeedbackWindowController
    let accessibility: AccessibilityServicing
    let accessNotice: AccessibilityAccessNoticePresenting
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
        self.accessibility = accessibility
        let planStatus = PlanStatus.shared
        self.planStatus = planStatus
        LegacyMigration.run(isAccessibilityTrusted: accessibility.isTrusted)
        let improver = TextImprovementService()
        let languageDetector = LanguageDetector()
        let peekViewModel = PeekViewModel(client: PeekClient(), detector: languageDetector)
        let settings = SettingsViewModel(accessibility: accessibility, planStatus: planStatus)
        settingsViewModel = settings
        onboardingViewModel = OnboardingViewModel(
            accessibility: accessibility,
            detector: languageDetector
        )
        feedback = FeedbackWindowController(
            popupDismiss: popupDismiss,
            planStatus: planStatus,
            onUpgrade: { settings.openStarterCheckout() }
        )
        let accessNotice = AccessibilityAccessNoticeController(
            accessibility: accessibility,
            onPermissionRequested: { [weak settings] in settings?.pollAccessibilityPermission() }
        )
        self.accessNotice = accessNotice
        review = ReviewPanelController(popupDismiss: popupDismiss)
        replacementRecovery = ReplacementRecoveryPanelController(popupDismiss: popupDismiss)
        peekPanel = PeekPanelController(
            viewModel: peekViewModel,
            popupDismiss: popupDismiss,
            accessibility: accessibility,
            accessNotice: accessNotice,
            onUpgrade: { settings.openStarterCheckout() }
        )
        palettePanel = PalettePanelController(
            viewModel: PaletteViewModel(registry: ActionRegistry(), detector: languageDetector),
            bridge: AXTextBridge(),
            accessibility: accessibility,
            accessNotice: accessNotice,
            improver: improver,
            hud: ResultHUDController(feedback: feedback),
            replacementRecovery: replacementRecovery,
            popupDismiss: popupDismiss
        )
        quickImproveViewModel = QuickImproveViewModel(
            accessibility: accessibility,
            improver: improver,
            feedback: feedback,
            accessNotice: accessNotice,
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
        _ = registerPeekHotkey(binding: container.settingsViewModel.peekHotkey)
        container.settingsViewModel.onPeekHotkeyChanged = { [weak self] binding in
            guard let self else { return false }
            let previous = self.container.settingsViewModel.peekHotkey
            guard self.registerPeekHotkey(binding: binding) else {
                _ = self.registerPeekHotkey(binding: previous)
                return false
            }
            return true
        }
        container.settingsViewModel.onActionHotkeyChanged = { [weak self] binding in
            guard let self else { return false }
            let previous = self.container.settingsViewModel.actionsHotkey
            guard self.registerActionHotkey(binding: binding) else {
                _ = self.registerActionHotkey(binding: previous)
                return false
            }
            return true
        }
        _ = registerFixHotkey(binding: container.settingsViewModel.mainHotkey)
        _ = registerActionHotkey(binding: container.settingsViewModel.actionsHotkey)
        container.settingsViewModel.onMainHotkeyChanged = { [weak self] binding in
            guard let self else { return false }
            let previous = self.container.settingsViewModel.mainHotkey
            guard self.registerFixHotkey(binding: binding) else {
                _ = self.registerFixHotkey(binding: previous)
                return false
            }
            return true
        }

        let settings = container.settingsViewModel
        settings.refreshUsage()
        let onboarding = container.onboardingViewModel
        if !onboarding.hasCompletedOnboarding || settings.needsRenamePermission {
            // Upgrading users only need the permission step again.
            if onboarding.hasCompletedOnboarding { onboarding.showAccessibilityStep() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.showOnboarding()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        container.settingsViewModel.stop()
        container.onboardingViewModel.stop()
        container.quickImproveViewModel.stop()
        container.peekHotkey.stop()
        container.fixHotkey.unregister()
        container.actionHotkey.stop()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        container.settingsViewModel.refreshAccessibility()
        container.onboardingViewModel.refreshAccessibility()
        container.settingsViewModel.refreshUsage()
    }

    func showSettings() {
        settingsWindowController.show()
    }

    func showOnboardingReplay() {
        container.onboardingViewModel.restart()
        showOnboarding()
    }

    private func showOnboarding() {
        let controller = onboardingWindowController
            ?? OnboardingWindowController(
                viewModel: container.onboardingViewModel,
                shortcuts: { [weak self] in
                    guard let self else { return .standard }
                    return OnboardingShortcuts(
                        fix: container.settingsViewModel.mainHotkey,
                        actions: container.settingsViewModel.actionsHotkey,
                        peek: container.settingsViewModel.peekHotkey
                    )
                },
                onFinish: { [weak self] in self?.finishOnboarding() }
            )
        onboardingWindowController = controller
        controller.show()
    }

    private func showOnboardingForTesting() {
#if DEBUG
        container.onboardingViewModel.resetOnboardingForTesting()
        showOnboarding()
#endif
    }

    private func togglePeek() async {
        if onboardingWindowController?.isVisible == true {
            container.onboardingViewModel.handlePeekHotkey()
            return
        }
        if container.peekPanel.isVisible {
            container.peekPanel.close()
            return
        }
        guard container.accessibility.isTrusted else {
            container.accessNotice.showAccessibilityAccessNeeded(at: NSEvent.mouseLocation)
            return
        }
        let selection = await container.selectionReader.read()
        guard container.accessibility.isTrusted else {
            container.accessNotice.showAccessibilityAccessNeeded(at: NSEvent.mouseLocation)
            return
        }
        container.peekPanel.toggle(selection: selection)
    }

    @discardableResult
    private func registerPeekHotkey(binding: HotkeyBinding) -> Bool {
        let registered = container.peekHotkey.start(binding: binding) { [weak self] in
            Task { @MainActor in await self?.togglePeek() }
        }
        container.settingsViewModel.peekHotkeyConflict = !registered
        return registered
    }

    @discardableResult
    private func registerFixHotkey(binding: HotkeyBinding) -> Bool {
        let settings = container.settingsViewModel
        // Release the old Fix registration before the shared close binding is
        // updated; either one may own ⌥⌘X while a popup is visible.
        container.fixHotkey.unregister()
        container.popupDismiss.setMainBinding(binding)
        let registered = container.fixHotkey.register(
            keyCode: binding.keyCode,
            modifiers: binding.modifiers
        ) { [weak self] in
            Task { @MainActor in self?.handleFixHotkey() }
        }
        settings.mainHotkeyConflict = !registered
        return registered
    }

    @discardableResult
    private func registerActionHotkey(binding: HotkeyBinding) -> Bool {
        let registered = container.actionHotkey.start(binding: binding) { [weak self] in
            Task { @MainActor in await self?.handleActionHotkey() }
        }
        container.settingsViewModel.actionHotkeyConflict = !registered
        return registered
    }

    private func handleFixHotkey() {
        if onboardingWindowController?.isVisible == true {
            container.onboardingViewModel.handleMainHotkey()
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
        guard container.accessibility.isTrusted else {
            container.accessNotice.showAccessibilityAccessNeeded(at: NSEvent.mouseLocation)
            return
        }
        container.quickImproveViewModel.improveSelection()
    }

    private func handleActionHotkey() async {
        if onboardingWindowController?.isVisible == true {
            container.onboardingViewModel.handleActionHotkey()
            return
        }
        await container.palettePanel.toggle()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.title = ""
        let icon = NSImage(named: "MenuBarIcon")?.copy() as? NSImage
        icon?.size = NSSize(width: 22, height: 16)
        icon?.isTemplate = true
        button.image = icon
        button.imageScaling = .scaleProportionallyDown
        button.imagePosition = .imageOnly
        button.setAccessibilityLabel("hotkeygo menu")
        button.toolTip = "hotkeygo menu"
        button.target = self
        button.action = #selector(toggleMenuPopover(_:))

        menuPopover.setContentView(NSHostingView(rootView: MenuBarView(
            settingsViewModel: container.settingsViewModel,
            planStatus: container.planStatus,
            quickImproveViewModel: container.quickImproveViewModel,
            onShowAbout: { [weak self] in self?.menuPopover.close(); self?.showAbout() },
            onOpenSettings: { [weak self] in self?.menuPopover.close(); self?.showSettings() },
            onShowOnboarding: { [weak self] in self?.menuPopover.close(); self?.showOnboardingReplay() },
            onQuit: { NSApp.terminate(nil) },
            onClose: { [weak self] in self?.menuPopover.close() }
        )))
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
        container.onboardingViewModel.completeOnboarding()
        container.settingsViewModel.clearRenamePermissionAfterOnboarding()
    }

    private func showAbout() {
        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "hotkeygo"
        ]
        if let applicationIcon = NSApp.applicationIconImage {
            options[.applicationIcon] = applicationIcon
        }
        NSApp.orderFrontStandardAboutPanel(options: options)
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
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 1),
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
        contentView.frame = NSRect(x: 0, y: 0, width: 360, height: 1)
        contentView.layoutSubtreeIfNeeded()

        let fittingSize = contentView.fittingSize
        panel.setContentSize(NSSize(
            width: 360,
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
            window.title = "hotkeygo Settings"
            window.setAccessibilityLabel("hotkeygo settings")
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
