import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var planStatus: PlanStatus
    let onShowOnboarding: () -> Void
    let onQuit: () -> Void
    @StateObject private var shortcutRecorder = SettingsHotkeyRecorder()

    init(
        viewModel: SettingsViewModel,
        onShowOnboarding: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        planStatus = viewModel.planStatus
        self.onShowOnboarding = onShowOnboarding
        self.onQuit = onQuit
    }

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
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Theme")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(HotkeyGoColor.ink)
                    Text("Auto follows macOS. Light and Dark stay fixed.")
                        .font(.system(size: 11))
                        .foregroundStyle(HotkeyGoColor.secondary)
                }

                HotkeyGoUI.RadioTileGroup(
                    selection: $viewModel.appearance,
                    options: appearanceOptions,
                    layout: .grid(columns: 3),
                    label: "Theme"
                )
            }
            .padding(12)
        }
    }

    private var appearanceOptions: [HotkeyGoUI.RadioTileOption<AppAppearance>] {
        [
            .init(value: .auto, title: "Auto", preview: AnyView(ThemePreview(appearance: .auto))),
            .init(value: .light, title: "Light", preview: AnyView(ThemePreview(appearance: .light))),
            .init(value: .dark, title: "Dark", preview: AnyView(ThemePreview(appearance: .dark)))
        ]
    }

    private var modelOptions: [HotkeyGoUI.RadioTileOption<HotkeyGoAIProvider>] {
        HotkeyGoAIProvider.models.map { model in
            .init(
                value: model.id,
                title: model.name,
                subtitle: model.provider,
                icon: tileIcon(for: model.icon, provider: model.provider)
            )
        }
    }

    private func tileIcon(for icon: HotkeyGoAIModelIcon?, provider: String) -> HotkeyGoUI.TileIcon {
        guard let icon else { return .initial(String(provider.prefix(1))) }
        switch icon {
        case .template(let assetName): return .template(Image(assetName))
        case .original(let assetName): return .original(Image(assetName))
        case .initial(let value): return .initial(value)
        }
    }

    private var modelSection: some View {
        SettingsSection(title: "AI model") {
            VStack(alignment: .leading, spacing: 8) {
                HotkeyGoUI.RadioTileGroup(
                    selection: $viewModel.aiProvider,
                    options: modelOptions,
                    layout: .list,
                    label: "AI model"
                )
                Text("Used for Fix, Actions, and Peek.")
                    .font(.system(size: 11))
                    .foregroundStyle(HotkeyGoColor.secondary)
                    .padding(.horizontal, 12)
            }
            .padding(12)
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
            VStack(alignment: .leading, spacing: 0) {
                SettingRow(
                    icon: .plan,
                    iconColor: billingIconColor,
                    title: billingTitle,
                    detail: billingDetail
                ) {
                    billingControl
                }

                PlanMeterView(value: planStatus.meterValue, layout: .settings)
                    .padding(.horizontal, 12)
                    .padding(.top, 7)

                HStack {
                    Text("FREE")
                        .foregroundStyle(HotkeyGoColor.secondary)
                    Spacer()
                    Text("ADVANCED")
                        .foregroundStyle(planStatus.isAdvanced ? HotkeyGoColor.planGreen : HotkeyGoColor.secondary)
                }
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .tracking(1.2)
                .padding(.horizontal, 12)
                .padding(.top, 5)

                Text(planUsageDetail)
                    .font(.system(size: 11))
                    .foregroundStyle(planStatus.isAdvanced || !isAtPlanLimit ? HotkeyGoColor.secondary : HotkeyGoColor.danger)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 11)
                    .accessibilityLabel(planUsageAccessibilityLabel)
            }
        }
    }

    @ViewBuilder
    private var billingControl: some View {
        if !planStatus.isAdvanced {
            Button("Get Advanced") { viewModel.openStarterCheckout() }
                .buttonStyle(HotkeyGoUI.PrimaryButton(compact: true))
                .accessibilityLabel("Get Advanced")
        }
    }

    private var billingIconColor: Color {
        planStatus.isAdvanced ? HotkeyGoColor.planGreen : HotkeyGoColor.violet
    }

    private var billingTitle: String {
        if planStatus.isAdvanced { return "Advanced" }
        return "30 free AI actions / month"
    }

    private var billingDetail: String {
        if planStatus.isAdvanced, let renewsAt = planStatus.snapshot.renewsAt {
            return "Renews \(formattedPlanDate(renewsAt))"
        }
        if planStatus.isAdvanced { return "More room to work. The same careful Fix quality applies." }
        return "Get Advanced for $10/month. More room to work, same quality bar. Sandbox test payments only."
    }

    private var isAtPlanLimit: Bool {
        !planStatus.isAdvanced && planStatus.used == 30
    }

    private var planUsageDetail: String {
        if planStatus.isAdvanced { return "More room to work" }
        guard let usage = planStatus.snapshot.usage else { return "0 / 30 this month" }
        return "\(usage.used) / \(usage.limit) this month · resets \(formattedPlanDate(usage.resetsAt))"
    }

    private var planUsageAccessibilityLabel: String {
        if planStatus.isAdvanced { return "Advanced plan" }
        if let usage = planStatus.snapshot.usage, usage.used == usage.limit {
            return "Free plan limit reached, resets \(formattedPlanDate(usage.resetsAt))"
        }
        return "Free plan, \(planStatus.used) of 30 actions used this month"
    }

    private func formattedPlanDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
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

private struct ThemePreview: View {
    let appearance: AppAppearance

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .topLeading) {
                background

                Rectangle()
                    .fill(titleBar)
                    .frame(width: width * 0.4, height: 5)
                    .offset(x: 14, y: 12)

                line(width: width * 0.56, height: 3)
                    .offset(x: 14, y: 23)
                line(width: width * 0.30, height: 3)
                    .offset(x: 14, y: 30)
            }
            .frame(width: width, height: geometry.size.height)
            .clipped()
        }
        .frame(height: 58)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var background: some View {
        switch appearance {
        case .auto:
            HStack(spacing: 0) {
                fixed(0xF9F8FC)
                fixed(0x17141F)
            }
        case .light:
            fixed(0xF9F8FC)
        case .dark:
            fixed(0x17141F)
        }
    }

    private var titleBar: Color {
        switch appearance {
        case .auto: fixed(0x6D28FF)
        case .light: fixed(0xDCDBE2)
        case .dark: fixed(0x34323C)
        }
    }

    private func line(width: CGFloat, height: CGFloat) -> some View {
        let colors: (Color, Color) = switch appearance {
        case .auto: (fixed(0xDCDBE2), fixed(0x34323C))
        case .light: (fixed(0xE8E6EE), fixed(0xE8E6EE))
        case .dark: (fixed(0x2A2732), fixed(0x2A2732))
        }
        return HStack(spacing: 0) {
            Rectangle().fill(colors.0)
            Rectangle().fill(colors.1)
        }
        .frame(width: width, height: height)
    }

    private func fixed(_ value: UInt32) -> Color {
        Color(nsColor: HotkeyGoColor.hex(value))
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
