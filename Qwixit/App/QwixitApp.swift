import SwiftUI
import AppKit

@main
struct QwixitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                settingsViewModel: appDelegate.container.settingsViewModel,
                quickImproveViewModel: appDelegate.container.quickImproveViewModel,
                onOpenSettings: { appDelegate.showSettings() },
                onQuit: { NSApp.terminate(nil) }
            )
        } label: {
            Image(nsImage: MenuBarQwixitGlyph.image)
                .accessibilityLabel("Qwixit")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Purpose-built 18pt template artwork, tinted by macOS for either menu-bar appearance.
private enum MenuBarQwixitGlyph {
    static let image: NSImage = {
        guard let source = NSImage(named: "QwixitMenuBar")?.copy() as? NSImage else {
            return NSImage()
        }
        source.size = NSSize(width: 18, height: 18)
        source.isTemplate = true
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
    private var onboardingWindowController: OnboardingWindowController?
    private lazy var settingsWindowController = SettingsWindowController(
        viewModel: container.settingsViewModel
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
            if settings.hasCompletedOnboarding { settings.onboardingStep = 2 }
            let controller = OnboardingWindowController(viewModel: container.settingsViewModel)
            onboardingWindowController = controller
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                controller.show()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        container.settingsViewModel.stop()
        container.quickImproveViewModel.stop()
        container.peekHotkey.stop()
        container.actionHotkey.stop()
    }

    func showSettings() {
        settingsWindowController.show()
    }

    private func togglePeek() async {
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
                Task { @MainActor in self?.container.quickImproveViewModel.improveSelection() }
            },
            onDouble: { [weak self] in
                Task { @MainActor in await self?.container.palettePanel.toggle() }
            }
        )
        settings.mainHotkeyConflict = !registered
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
    private var window: NSWindow?

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    func show() {
        if window == nil {
            let root = SettingsView(
                viewModel: viewModel,
                onQuit: { NSApp.terminate(nil) }
            )
            .frame(width: 500, height: 560)

            let window = NSWindow(
                contentRect: .init(x: 0, y: 0, width: 500, height: 560),
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
    private var window: NSWindow?

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    func show() {
        if window == nil {
            let root = OnboardingView(viewModel: viewModel) { [weak self] in
                self?.close()
            }
            .frame(width: 640, height: 450)

            let window = NSWindow(
                contentRect: .init(x: 0, y: 0, width: 640, height: 450),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Welcome to Qwixit"
            window.isReleasedWhenClosed = false
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.contentView = NSHostingView(rootView: root)
            window.center()
            self.window = window
        }

        if let window { AppWindowPresenter.present(window) }
    }

    func close() {
        window?.close()
        window = nil
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
