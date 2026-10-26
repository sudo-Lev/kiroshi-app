import SwiftUI
import AppKit

struct MenuBarView: View {
    private let wrapperShape = HotkeyGoControlShape(cut: 16)
    @State private var isAboutHovered = false
    @State private var isEnvironmentMenuPresented = false

    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var quickImproveViewModel: QuickImproveViewModel
    let onShowAbout: () -> Void
    let onOpenSettings: () -> Void
    let onShowOnboarding: () -> Void
    let onQuit: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                utilityBar
                statusRow
                reviewModeRow
                actionsRow
            }

            if isEnvironmentMenuPresented {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { isEnvironmentMenuPresented = false }
                    .zIndex(1)

                environmentDropdown
                    .padding(.trailing, 10)
                    .offset(y: 24)
                    .zIndex(2)
            }
        }
        .frame(width: 318)
        .background(HotkeyGoColor.canvas, in: wrapperShape)
        .clipShape(wrapperShape)
        .overlay {
            wrapperShape
                .stroke(HotkeyGoColor.line, lineWidth: 1)
        }
        .contentShape(wrapperShape)
        .foregroundStyle(HotkeyGoColor.ink)
        .hotkeygoTheme()
        .onAppear {
            settingsViewModel.refreshAccessibility()
        }
    }

    private var utilityBar: some View {
        HStack(spacing: 7) {
            Button(action: onShowAbout) {
                HotkeyGoUI.Icon(.info, size: 14)
                    .foregroundStyle(HotkeyGoColor.secondary)
                    .frame(width: 28, height: 26)
                    .background(isAboutHovered ? HotkeyGoColor.surfaceHover : .clear, in: Circle())
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isAboutHovered = $0 }
            .accessibilityLabel("About hotkeygo")
            .help("About hotkeygo")
            Text("v1.0")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
            Spacer()
            environmentMenu
        }
        .foregroundStyle(HotkeyGoColor.ink)
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(HotkeyGoColor.canvasRaised)
        .overlay(alignment: .bottom) { Rectangle().fill(HotkeyGoColor.line).frame(height: 1) }
    }

    private var environmentMenu: some View {
        Button {
            isEnvironmentMenuPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                Text("Cloud")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.3)
                    .foregroundStyle(HotkeyGoColor.cyan)
                HotkeyGoUI.Icon(.chevronDown, size: 9)
                    .foregroundStyle(HotkeyGoColor.ink)
            }
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("Processing environment")
        .accessibilityValue("Cloud")
        .accessibilityHint("Show processing environment options")
        .help("Choose hotkeygo's processing environment")
    }

    private var environmentDropdown: some View {
        VStack(spacing: 4) {
            environmentOption(title: "Cloud", selected: true) {
                isEnvironmentMenuPresented = false
            }

            Rectangle()
                .fill(HotkeyGoColor.line)
                .frame(height: 1)
                .padding(.horizontal, 6)

            environmentOption(title: "Local", detail: "<in development>", isEnabled: false) { }
        }
        .padding(6)
        .frame(width: 188)
        .background(HotkeyGoColor.surface, in: HotkeyGoControlShape(cut: 8))
        .overlay(HotkeyGoControlShape(cut: 8).stroke(HotkeyGoColor.line))
        .shadow(color: HotkeyGoColor.cardShadow, radius: 10, y: 4)
        .accessibilityElement(children: .contain)
    }

    private func environmentOption(
        title: String,
        detail: String? = nil,
        selected: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(HotkeyGoColor.ink)
                Spacer(minLength: 4)
                if let detail {
                    Text(detail)
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(HotkeyGoColor.secondary)
                } else if selected {
                    HotkeyGoUI.Icon(.check, size: 12)
                        .foregroundStyle(HotkeyGoColor.cyan)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 27)
            .background(selected ? HotkeyGoColor.cyan.opacity(0.08) : .clear, in: HotkeyGoControlShape(cut: 4))
            .contentShape(HotkeyGoControlShape(cut: 4))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.46)
        .accessibilityLabel(detail == nil ? title : "Local, in development")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var statusRow: some View {
        HStack(spacing: 7) {
            HotkeyGoFaceView(
                face: settingsViewModel.isAdvanced ? .advanced : .hello,
                size: 13,
                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                color: settingsViewModel.isAdvanced ? HotkeyGoColor.terminalGreen : HotkeyGoColor.ink
            )
            .frame(width: 56, height: 30)
            .accessibilityLabel(settingsViewModel.isAdvanced ? "Advanced plan active" : "Free plan")
            VStack(alignment: .leading, spacing: 2) {
                Text(billingTitle)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(settingsViewModel.isAdvanced ? HotkeyGoColor.terminalGreen : HotkeyGoColor.ink)
                Text(billingDetail)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(HotkeyGoColor.secondary)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)

            if showsCheckoutAction {
                Button("Get Advanced") {
                    settingsViewModel.openStarterCheckout()
                }
                .buttonStyle(HotkeyGoUI.PrimaryButton(compact: true))
                .help("Open the Paddle sandbox checkout for Advanced · $10/month")
                .accessibilityLabel("Subscribe to hotkeygo Advanced for ten dollars per month")
            } else {
                Spacer(minLength: 0)
                HotkeyGoUI.PopupCloseButton(
                    shortcut: settingsViewModel.mainHotkey.presentation,
                    label: "Close hotkeygo menu",
                    action: onClose
                )
            }
            Button(action: onOpenSettings) {
                HotkeyGoUI.AccessBadge(
                    granted: settingsViewModel.accessibilityGranted,
                    compact: true,
                    iconOnly: true
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(settingsViewModel.accessibilityGranted
                ? "Accessibility access allowed. Open Settings"
                : "Accessibility access required. Open Settings")
            .help(
                settingsViewModel.accessibilityGranted
                    ? "hotkeygo can read and replace selected text"
                    : "Open Settings to allow Accessibility access"
            )
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background {
            if settingsViewModel.isAdvanced {
                LinearGradient(
                    colors: [HotkeyGoColor.success.opacity(0.18), HotkeyGoColor.success.opacity(0.07)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                HotkeyGoColor.surface
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(settingsViewModel.isAdvanced ? HotkeyGoColor.success.opacity(0.38) : HotkeyGoColor.line)
                .frame(height: 1)
        }
    }

    private var actionsRow: some View {
        GeometryReader { geometry in
            let contentWidth = geometry.size.width - 24
            let halfWidth = (contentWidth - 8) / 2

            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    actionCell(
                        icon: .settings,
                        title: "Settings",
                        accessibilityLabel: "hotkeygo settings",
                        action: onOpenSettings
                    )
                        .frame(width: halfWidth, height: 28)
                    quitActionCell
                        .frame(width: halfWidth, height: 28)
                }

                actionCell(
                    icon: .onboarding,
                    title: "Onboarding",
                    accessibilityLabel: "hotkeygo onboarding",
                    action: onShowOnboarding
                )
                    .frame(width: contentWidth, height: 28)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(height: 76)
        .background(HotkeyGoColor.canvasRaised)
    }

    private func actionCell(
        icon: HotkeyGoUI.IconName,
        title: String,
        accessibilityLabel: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                HotkeyGoUI.Icon(icon, size: 11)
                Text(title)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(HotkeyGoUI.PrimaryButton(compact: true, appearance: .filled))
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel ?? title)
    }

    private var quitActionCell: some View {
        Button(action: onQuit) {
            HStack(spacing: 5) {
                HotkeyGoUI.Icon(.quit, size: 11)
                Text("Quit")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(HotkeyGoUI.QuitButton(compact: true, appearance: .soft))
        .contentShape(Rectangle())
        .accessibilityLabel("Quit hotkeygo")
    }

    private var reviewModeRow: some View {
        Toggle(isOn: $settingsViewModel.reviewBeforeApplying) {
            HStack(spacing: 9) {
                HotkeyGoUI.Icon(.review, size: 16)
                    .foregroundStyle(HotkeyGoColor.violet)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Preview & Approve")
                        .font(.system(size: 10.5, weight: .semibold))
                    Text("Nothing changes until you approve")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.1)
                        .foregroundStyle(HotkeyGoColor.secondary)
                }
            }
        }
        .toggleStyle(HotkeyGoUI.Toggle(compact: true))
        .help("Preview every Fix change before it replaces your selection")
        .accessibilityLabel("Preview and approve Fix changes")
        .accessibilityHint("Nothing changes until you approve the suggested fix.")
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(HotkeyGoColor.canvasRaised)
        .overlay(alignment: .bottom) { Rectangle().fill(HotkeyGoColor.line).frame(height: 1) }
    }

    private var showsCheckoutAction: Bool {
        settingsViewModel.remainingActions == 0
            && !settingsViewModel.isAdvanced
    }

    private var billingTitle: String {
        settingsViewModel.isAdvanced ? "Advanced" : "Free"
    }

    private var billingDetail: String {
        if settingsViewModel.isAdvanced { return "more room to work" }
        guard settingsViewModel.remainingActions != nil else { return "30 free / month" }
        return "\(usedActions) / 30 used"
    }

    private var remainingActions: Int {
        min(max(settingsViewModel.remainingActions ?? 30, 0), 30)
    }

    private var usedActions: Int { 30 - remainingActions }

}
