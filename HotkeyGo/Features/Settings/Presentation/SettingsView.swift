import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    let onShowOnboarding: () -> Void
    let onQuit: () -> Void
    @StateObject private var shortcutRecorder = SettingsHotkeyRecorder()

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    appearanceSection
                    modelSection
                    shortcutsSection
                    accessSection
                    billingSection
#if DEBUG
                    developerSection
#endif
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.automatic)
            footer
        }
        .background(HotkeyGoColor.canvas)
        .foregroundStyle(HotkeyGoColor.ink)
        .hotkeygoTheme()
        .onAppear {
            viewModel.refreshAccessibility()
            viewModel.refreshUsage()
        }
        .onDisappear { shortcutRecorder.stop() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 22) {
                HotkeyGoWordmark()
                    .frame(width: 104, height: 28, alignment: .leading)
                Text("Settings")
                    .font(.system(size: 10))
                    .foregroundStyle(HotkeyGoColor.secondary)
            }

            Spacer()
            accessBadge
        }
        .padding(.horizontal, 18)
        .frame(height: 72)
        .background(HotkeyGoColor.canvasRaised)
        .overlay(alignment: .bottom) { Rectangle().fill(HotkeyGoColor.line).frame(height: 1) }
    }

    private var accessBadge: some View {
        AccessStatusBadge(granted: viewModel.accessibilityGranted)
    }

    private var appearanceSection: some View {
        SettingsSection(title: "Appearance") {
            SettingRow(
                icon: viewModel.appearance == .dark ? .themeDark : .themeLight,
                title: "Theme",
                detail: "Choose the look used by hotkeygo windows and feedback."
            ) {
                HotkeyGoUI.ThemePicker(selection: $viewModel.appearance)
            }
        }
    }

    private var modelSection: some View {
        SettingsSection(title: "AI model") {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(HotkeyGoAIProvider.allCases) { provider in
                    HotkeyGoUI.RadioOption(
                        title: provider.title,
                        value: provider,
                        selection: $viewModel.aiProvider
                    )
                }
                Text("Used for Fix, Actions, and Peek.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(HotkeyGoColor.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 2)
            }
            .padding(8)
        }
    }

    private var shortcutsSection: some View {
        SettingsSection(title: "Hot keys") {
            SettingRow(
                icon: .fix,
                title: "Fix selected text",
                detail: shortcutDetail(for: .fix)
            ) {
                hotkeyControl(for: .fix, binding: viewModel.mainHotkey)
            }

            rowDivider

            SettingRow(
                icon: .review,
                title: "Preview & Approve",
                detail: "See every edit first. Nothing changes until you approve it."
            ) {
                Toggle("Preview & Approve", isOn: $viewModel.reviewBeforeApplying)
                    .toggleStyle(HotkeyGoUI.Toggle(showsLabel: false))
                    .accessibilityLabel("Preview and approve Fix changes")
                    .accessibilityHint("Nothing changes until you approve the suggested fix.")
            }

            rowDivider

            SettingRow(
                icon: .actions,
                title: "Open actions",
                detail: shortcutDetail(for: .actions)
            ) {
                hotkeyControl(for: .actions, binding: viewModel.actionsHotkey)
            }

            rowDivider

            SettingRow(
                icon: .peek,
                title: "Peek",
                detail: shortcutDetail(for: .peek)
            ) {
                hotkeyControl(for: .peek, binding: viewModel.peekHotkey)
            }
        }
    }

    private func hotkeyControl(for action: HotkeyAction, binding: HotkeyBinding) -> some View {
        HStack(spacing: 5) {
            if shortcutRecorder.recordingAction == action {
                Text("Press keys…")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(HotkeyGoColor.violet)
                    .padding(.horizontal, 7)
                    .frame(height: 25)
                    .background(HotkeyGoColor.surfaceHover, in: HotkeyGoControlShape(cut: 5))
                    .overlay(HotkeyGoControlShape(cut: 5).stroke(HotkeyGoColor.violet))
            } else {
                HotkeyGoUI.ShortcutButton(
                    modifiers: binding.modifierSymbols,
                    key: binding.keySymbol,
                    label: "Change \(action.title) shortcut",
                    hint: "Click, then press a key combination. Escape cancels."
                ) {
                    let viewModel = viewModel
                    shortcutRecorder.begin(action) { [weak viewModel] binding, action in
                        viewModel?.setHotkey(binding, for: action) ?? false
                    }
                }
                .help("Change \(action.title) shortcut")
                .opacity(isHotkeyConflict(for: action) ? 0.55 : 1)
            }

            if binding != defaultHotkey(for: action) {
                Button("Default") { viewModel.restoreDefaultHotkey(for: action) }
                    .buttonStyle(SubtleButtonStyle())
                    .help("Restore the default \(action.title) shortcut")
            }
        }
    }

    private func shortcutDetail(for action: HotkeyAction) -> String {
        if shortcutRecorder.recordingAction == action {
            return shortcutRecorder.error ?? "Press a key combination. Escape cancels."
        }
        if isHotkeyConflict(for: action) {
            return "\(hotkey(for: action).displayString) is taken by another app. Choose another combo."
        }
        return switch action {
        case .fix: "Press once to clean up grammar and punctuation."
        case .actions: "Translate, rewrite for Slack, or make text formal."
        case .peek: "Read selected text without replacing it."
        }
    }

    private func isHotkeyConflict(for action: HotkeyAction) -> Bool {
        switch action {
        case .fix: viewModel.mainHotkeyConflict
        case .actions: viewModel.actionHotkeyConflict
        case .peek: viewModel.peekHotkeyConflict
        }
    }

    private func hotkey(for action: HotkeyAction) -> HotkeyBinding {
        switch action {
        case .fix: viewModel.mainHotkey
        case .actions: viewModel.actionsHotkey
        case .peek: viewModel.peekHotkey
        }
    }

    private func defaultHotkey(for action: HotkeyAction) -> HotkeyBinding {
        switch action {
        case .fix: .defaultMain
        case .actions: .actions
        case .peek: .peek
        }
    }

    private var accessSection: some View {
        SettingsSection(title: "Access") {
            SettingRow(
                icon: viewModel.accessibilityGranted ? .accessGranted : .accessNeeded,
                iconColor: viewModel.accessibilityGranted ? HotkeyGoColor.success : HotkeyGoColor.warning,
                title: "Accessibility",
                detail: viewModel.accessibilityGranted
                    ? "hotkeygo can read and replace only the text you select."
                    : "Allow hotkeygo in Privacy & Security › Accessibility for shortcuts to work in other apps."
            ) {
                if viewModel.accessibilityGranted {
                    Text("Allowed")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(HotkeyGoColor.success)
                } else {
                    Button("Allow") { viewModel.requestAccessibility() }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityLabel("Allow hotkeygo in Accessibility settings")
                }
            }
        }
    }

    private var billingSection: some View {
        SettingsSection(title: "Plan · Sandbox") {
            SettingRow(
                icon: .plan,
                iconColor: billingIconColor,
                title: billingTitle,
                detail: billingDetail
            ) {
                billingControl
            }
        }
    }

    @ViewBuilder
    private var billingControl: some View {
        if viewModel.isAdvanced {
            HStack(spacing: 4) {
                HotkeyGoUI.Icon(.statusSuccess, size: 10)
                Text("Active")
            }
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(HotkeyGoColor.success)
                .accessibilityLabel("hotkeygo Advanced subscription active")
        } else {
            Button("Get Advanced") { viewModel.openStarterCheckout() }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var billingIconColor: Color {
        viewModel.isAdvanced ? HotkeyGoColor.success : HotkeyGoColor.violet
    }

    private var billingTitle: String {
        if viewModel.isAdvanced { return "hotkeygo Advanced" }
        return "30 free AI actions / month"
    }

    private var billingDetail: String {
        if viewModel.isAdvanced { return "Active — more room to work. The same careful Fix quality applies." }
        return "Get Advanced for $10/month. More room to work, same quality bar. Sandbox test payments only."
    }

#if DEBUG
    private var developerSection: some View {
        SettingsSection(title: "Developer · local only") {
            VStack(alignment: .leading, spacing: 9) {
                Picker(
                    "Usage scenario",
                    selection: Binding(
                        get: { viewModel.developerUsageScenario },
                        set: { viewModel.setDeveloperUsageScenario($0) }
                    )
                ) {
                    ForEach(DeveloperUsageScenario.allCases) { scenario in
                        Text(scenario.title).tag(scenario)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                Text(viewModel.developerUsageScenario.detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(HotkeyGoColor.secondary)

                if viewModel.developerUsageScenario == .limitReached {
                    HStack(spacing: 4) {
                        HotkeyGoUI.Icon(.statusWarning, size: 10)
                        Text("This simulation intentionally disables AI actions.")
                    }
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(HotkeyGoColor.warning)
                }

                HStack(spacing: 10) {
                    Button("Show onboarding now", action: onShowOnboarding)
                    .buttonStyle(SubtleButtonStyle())

                    Text("Opens the real first-run flow. Debug only.")
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(HotkeyGoColor.secondary)
                }
            }
            .padding(12)
        }
    }
#endif

    private var footer: some View {
        HStack {
            Text("hotkeygo 1.0")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.3)
                .foregroundStyle(HotkeyGoColor.secondary)
            Spacer()
            Button(action: onQuit) {
                HStack(spacing: 7) {
                    HotkeyGoUI.Icon(.quit, size: 13)
                    Text("Quit")
                }
            }
            .buttonStyle(HotkeyGoUI.QuitButton(appearance: .soft))
            .accessibilityLabel("Quit hotkeygo")
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
        .background(HotkeyGoColor.canvasRaised)
        .overlay(alignment: .top) { Rectangle().fill(HotkeyGoColor.line).frame(height: 1) }
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(HotkeyGoColor.line)
            .frame(height: 1)
            .padding(.leading, 52)
    }
}

@MainActor
private final class SettingsHotkeyRecorder: ObservableObject {
    @Published private(set) var recordingAction: HotkeyAction?
    @Published private(set) var error: String?
    private var keyMonitor: Any?
    private var onCapture: ((HotkeyBinding, HotkeyAction) -> Bool)?

    func begin(_ action: HotkeyAction, onCapture: @escaping (HotkeyBinding, HotkeyAction) -> Bool) {
        recordingAction = action
        error = nil
        self.onCapture = onCapture
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, NSApp.keyWindow?.title == "hotkeygo Settings",
                  let action = self.recordingAction else { return event }
            return self.capture(event, for: action)
        }
    }

    func stop() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        recordingAction = nil
        error = nil
        onCapture = nil
    }

    private func capture(_ event: NSEvent, for action: HotkeyAction) -> NSEvent? {
        if event.keyCode == 53 {
            stop()
            return nil
        }

        var modifiers: GlobalHotKey.Modifiers = []
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        guard !modifiers.isEmpty else {
            error = "Include at least one modifier key."
            return nil
        }

        let binding = HotkeyBinding(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        guard onCapture?(binding, action) == true else {
            error = "That combination is assigned, reserved, or unavailable in macOS."
            return nil
        }
        stop()
        return nil
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            MonoLabel(title)
                .padding(.leading, 3)
            VStack(spacing: 0) { content }
                .kCard()
        }
    }
}

private struct SettingRow<Control: View>: View {
    let icon: HotkeyGoUI.IconName
    var iconColor: Color = HotkeyGoColor.violet
    let title: String
    let detail: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 10) {
            HotkeyGoUI.Icon(icon, size: 20)
                .foregroundStyle(iconColor)
                .frame(width: 30, height: 30)
                .background(iconColor.opacity(0.09))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                Text(detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(HotkeyGoColor.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 10)
            control
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 54)
    }
}

private struct ShortcutKeycaps: View {
    let modifiers: [String]
    let key: String

    init(modifiers: [String], key: String) {
        self.modifiers = modifiers
        self.key = key
    }

    init(binding: HotkeyBinding) {
        self.init(modifiers: binding.modifierSymbols, key: binding.keySymbol)
    }

    var body: some View {
        ShortcutBadge(modifiers: modifiers, key: key)
    }
}
