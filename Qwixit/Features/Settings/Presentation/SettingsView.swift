import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    let onShowOnboarding: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    appearanceSection
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
        .background(KColor.canvas)
        .foregroundStyle(KColor.ink)
        .qwixitTheme()
        .onAppear {
            viewModel.refreshAccessibility()
            viewModel.refreshUsage()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                QwixitLockup()
                    .frame(width: 104, height: 28, alignment: .leading)
                Text("Shortcuts & access")
                    .font(.system(size: 10))
                    .foregroundStyle(KColor.secondary)
            }

            Spacer()
            accessBadge
        }
        .padding(.horizontal, 18)
        .frame(height: 72)
        .background(KColor.canvasRaised)
        .overlay(alignment: .bottom) { Rectangle().fill(KColor.line).frame(height: 1) }
    }

    private var accessBadge: some View {
        AccessStatusBadge(granted: viewModel.accessibilityGranted)
    }

    private var appearanceSection: some View {
        SettingsSection(title: "Appearance") {
            SettingRow(
                icon: viewModel.appearance == .dark ? "moon.stars.fill" : "sun.max.fill",
                title: "Theme",
                detail: "Choose the look used by Qwixit windows and feedback."
            ) {
                Picker("Theme", selection: $viewModel.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 132)
            }
        }
    }

    private var shortcutsSection: some View {
        SettingsSection(title: "Hot keys") {
            SettingRow(
                icon: "wand.and.stars",
                title: "Fix selected text",
                detail: viewModel.mainHotkeyConflict
                    ? "\(viewModel.mainHotkey.displayString) is taken by another app. Choose another combo."
                    : "Press once to clean up grammar and punctuation."
            ) {
                HStack(spacing: 6) {
                    if viewModel.mainHotkey != .defaultMain {
                        Button("Restore default") { viewModel.restoreDefaultHotkey() }
                            .buttonStyle(SubtleButtonStyle())
                    }
                    ShortcutKeycaps(binding: viewModel.mainHotkey)
                        .opacity(viewModel.mainHotkeyConflict ? 0.45 : 1)
                }
            }

            rowDivider

            SettingRow(
                icon: "command.square.fill",
                title: "Open actions",
                detail: "Press twice for Translate, Slack style, and Make formal."
            ) {
                HStack(spacing: 6) {
                    ShortcutKeycaps(binding: viewModel.mainHotkey)
                    Text("×2")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(KColor.secondary)
                }
            }

            rowDivider

            SettingRow(
                icon: "text.magnifyingglass",
                title: "Peek",
                detail: "Read selected text without replacing it."
            ) {
                ShortcutKeycaps(modifiers: ["⌥", "⌘"], key: viewModel.peekShortcutKey)
            }
        }
    }

    private var accessSection: some View {
        SettingsSection(title: "Access") {
            SettingRow(
                icon: viewModel.accessibilityGranted ? "checkmark.shield.fill" : "lock.shield.fill",
                iconColor: viewModel.accessibilityGranted ? KColor.success : KColor.warning,
                title: "Accessibility",
                detail: viewModel.accessibilityGranted
                    ? "Qwixit can read and replace only the text you select."
                    : "Required for shortcuts to work in other apps."
            ) {
                if viewModel.accessibilityGranted {
                    Text("Allowed")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(KColor.success)
                } else {
                    Button("Allow") { viewModel.requestAccessibility() }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
    }

    private var billingSection: some View {
        SettingsSection(title: "Plan · Sandbox") {
            SettingRow(
                icon: "creditcard.fill",
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
        if viewModel.isUnlimited {
            Label("Active", systemImage: "checkmark.circle.fill")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(KColor.success)
                .accessibilityLabel("Qwixit Unlimited subscription active")
        } else {
            Button("Go unlimited") { viewModel.openStarterCheckout() }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var billingIconColor: Color {
        viewModel.isUnlimited ? KColor.success : KColor.violet
    }

    private var billingTitle: String {
        if viewModel.isUnlimited { return "Qwixit Unlimited" }
        return "30 free AI actions / month"
    }

    private var billingDetail: String {
        if viewModel.isUnlimited { return "Active — every Qwixit action is unlocked." }
        return "Go unlimited for $10/month. Sandbox test payments only."
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
                    .foregroundStyle(KColor.secondary)

                if viewModel.developerUsageScenario == .limitReached {
                    Label("This simulation intentionally disables AI actions.", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(KColor.warning)
                }

                HStack(spacing: 10) {
                    Button("Show onboarding now", action: onShowOnboarding)
                    .buttonStyle(SubtleButtonStyle())

                    Text("Opens the real first-run flow. Debug only.")
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(KColor.secondary)
                }
            }
            .padding(12)
        }
    }
#endif

    private var footer: some View {
        HStack {
            Text("Qwixit 1.0")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.3)
                .foregroundStyle(KColor.secondary)
            Spacer()
            Button("Quit Qwixit") { onQuit() }
                .buttonStyle(SubtleButtonStyle())
                .foregroundStyle(KColor.danger)
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
        .background(KColor.canvasRaised)
        .overlay(alignment: .top) { Rectangle().fill(KColor.line).frame(height: 1) }
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(KColor.line)
            .frame(height: 1)
            .padding(.leading, 52)
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
    let icon: String
    var iconColor: Color = KColor.violet
    let title: String
    let detail: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 30, height: 30)
                .background(iconColor.opacity(0.09))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                Text(detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(KColor.secondary)
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
