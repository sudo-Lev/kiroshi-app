import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            VStack(alignment: .leading, spacing: 14) {
                shortcutsSection
                accessSection
                billingSection
            }
            .padding(18)

            Spacer(minLength: 0)
            footer
        }
        .background(KColor.canvas)
        .foregroundStyle(KColor.ink)
        .preferredColorScheme(.light)
        .onAppear { viewModel.refreshAccessibility() }
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
        HStack(spacing: 6) {
            Circle()
                .fill(viewModel.accessibilityGranted ? KColor.success : KColor.warning)
                .frame(width: 7, height: 7)
            Text(viewModel.accessibilityGranted ? "READY" : "ACCESS NEEDED")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.5)
        }
        .foregroundStyle(KColor.secondary)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(KColor.surface)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(KColor.line))
    }

    private var shortcutsSection: some View {
        SettingsSection(title: "HOT KEYS") {
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
        SettingsSection(title: "ACCESS") {
            SettingRow(
                icon: viewModel.accessibilityGranted ? "checkmark.shield.fill" : "lock.shield.fill",
                iconColor: viewModel.accessibilityGranted ? KColor.success : KColor.warning,
                title: "Accessibility",
                detail: viewModel.accessibilityGranted
                    ? "Qwixit can read and replace only the text you select."
                    : "Required for shortcuts to work in other apps."
            ) {
                if viewModel.accessibilityGranted {
                    Text("ALLOWED")
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
        SettingsSection(title: "PLAN · SANDBOX") {
            VStack(spacing: 0) {
                SettingRow(
                    icon: "creditcard.fill",
                    title: "30 free AI actions / month",
                    detail: "Go unlimited for $10/month. Sandbox test payments only."
                ) {
                    Button("Go unlimited") { viewModel.openStarterCheckout() }
                        .buttonStyle(PrimaryButtonStyle())
                }

                if let message = viewModel.checkoutMessage {
                    Text(message)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(KColor.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("QWIXIT 1.0")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.7)
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
        HStack(spacing: 3) {
            ForEach(modifiers, id: \.self) { Keycap(symbol: $0) }
            Keycap(symbol: key, active: true)
        }
    }
}
