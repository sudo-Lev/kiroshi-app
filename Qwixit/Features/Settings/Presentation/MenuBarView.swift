import SwiftUI
import AppKit

struct MenuBarView: View {
    private let wrapperShape = QwixitControlShape(cut: 16)
    @State private var isEnvironmentMenuPresented = false

    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var quickImproveViewModel: QuickImproveViewModel
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
        .background(KColor.canvas, in: wrapperShape)
        .clipShape(wrapperShape)
        .overlay {
            wrapperShape
                .stroke(KColor.line, lineWidth: 1)
        }
        .contentShape(wrapperShape)
        .foregroundStyle(KColor.ink)
        .qwixitTheme()
        .onAppear {
            settingsViewModel.refreshAccessibility()
        }
    }

    private var utilityBar: some View {
        HStack(spacing: 7) {
            TokiriUI.Icon(.info, size: 11)
            Text("v1.0")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
            Spacer()
            environmentMenu
        }
        .foregroundStyle(KColor.ink)
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(KColor.canvasRaised)
        .overlay(alignment: .bottom) { Rectangle().fill(KColor.line).frame(height: 1) }
    }

    private var environmentMenu: some View {
        Button {
            isEnvironmentMenuPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                Text("Cloud")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.3)
                    .foregroundStyle(KColor.cyan)
                TokiriUI.Icon(.chevronDown, size: 9)
                    .foregroundStyle(KColor.ink)
            }
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("Processing environment")
        .accessibilityValue("Cloud")
        .accessibilityHint("Show processing environment options")
        .help("Choose Tokiri's processing environment")
    }

    private var environmentDropdown: some View {
        VStack(spacing: 4) {
            environmentOption(title: "Cloud", selected: true) {
                isEnvironmentMenuPresented = false
            }

            Rectangle()
                .fill(KColor.line)
                .frame(height: 1)
                .padding(.horizontal, 6)

            environmentOption(title: "Local", detail: "<in development>", isEnabled: false) { }
        }
        .padding(6)
        .frame(width: 188)
        .background(KColor.surface, in: QwixitControlShape(cut: 8))
        .overlay(QwixitControlShape(cut: 8).stroke(KColor.line))
        .shadow(color: KColor.cardShadow, radius: 10, y: 4)
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
                    .foregroundStyle(KColor.ink)
                Spacer(minLength: 4)
                if let detail {
                    Text(detail)
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(KColor.secondary)
                } else if selected {
                    TokiriUI.Icon(.check, size: 12)
                        .foregroundStyle(KColor.cyan)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 27)
            .background(selected ? KColor.cyan.opacity(0.08) : .clear, in: QwixitControlShape(cut: 4))
            .contentShape(QwixitControlShape(cut: 4))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.46)
        .accessibilityLabel(detail == nil ? title : "Local, in development")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var statusRow: some View {
        HStack(spacing: 7) {
            QwixitFaceView(
                face: settingsViewModel.isUnlimited ? .advanced : .hello,
                size: 13,
                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                color: settingsViewModel.isUnlimited ? KColor.terminalGreen : KColor.ink
            )
            .frame(width: 56, height: 30)
            .accessibilityLabel(settingsViewModel.isUnlimited ? "Advanced plan active" : "Free plan")
            VStack(alignment: .leading, spacing: 2) {
                Text(billingTitle)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(settingsViewModel.isUnlimited ? KColor.terminalGreen : KColor.ink)
                Text(billingDetail)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(KColor.secondary)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)

            if showsCheckoutAction {
                Button("Get Advanced") {
                    settingsViewModel.openStarterCheckout()
                }
                .buttonStyle(TokiriUI.PrimaryButton(compact: true))
                .help("Open the Paddle sandbox checkout for Advanced · $10/month")
                .accessibilityLabel("Subscribe to Tokiri Advanced for ten dollars per month")
            } else {
                Spacer(minLength: 0)
                TokiriUI.PopupCloseButton(
                    shortcut: HotkeyCatalog.popupDismiss.presentation,
                    label: "Close Tokiri menu",
                    action: onClose
                )
            }
            Button(action: onOpenSettings) {
                TokiriUI.AccessBadge(
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
                    ? "Tokiri can read and replace selected text"
                    : "Open Settings to allow Accessibility access"
            )
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background {
            if settingsViewModel.isUnlimited {
                LinearGradient(
                    colors: [KColor.success.opacity(0.18), KColor.success.opacity(0.07)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                KColor.surface
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(settingsViewModel.isUnlimited ? KColor.success.opacity(0.38) : KColor.line)
                .frame(height: 1)
        }
    }

    private var actionsRow: some View {
        GeometryReader { geometry in
            let contentWidth = geometry.size.width - 24
            let halfWidth = (contentWidth - 8) / 2

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    actionCell(icon: .settings, title: "Settings", action: onOpenSettings)
                        .frame(width: halfWidth, height: 32)
                    quitActionCell
                        .frame(width: halfWidth, height: 32)
                }

                actionCell(icon: .onboarding, title: "Onboarding", action: onShowOnboarding)
                    .frame(width: contentWidth, height: 32)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(height: 90)
        .background(KColor.canvasRaised)
    }

    private func actionCell(
        icon: TokiriUI.IconName,
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                TokiriUI.Icon(icon, size: 11)
                Text(title)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(TokiriUI.PrimaryButton(compact: true, appearance: .filled))
        .contentShape(Rectangle())
        .accessibilityLabel(title)
    }

    private var quitActionCell: some View {
        Button(action: onQuit) {
            HStack(spacing: 5) {
                TokiriUI.Icon(.quit, size: 11)
                Text("Quit")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(TokiriUI.QuitButton(compact: true, appearance: .soft))
        .contentShape(Rectangle())
        .accessibilityLabel("Quit Tokiri")
    }

    private var reviewModeRow: some View {
        Toggle(isOn: $settingsViewModel.reviewBeforeApplying) {
            HStack(spacing: 9) {
                TokiriUI.Icon(.review, size: 16)
                    .foregroundStyle(KColor.violet)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Preview & Approve")
                        .font(.system(size: 10.5, weight: .semibold))
                    Text("Nothing changes until you approve")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.1)
                        .foregroundStyle(KColor.secondary)
                }
            }
        }
        .toggleStyle(TokiriUI.Toggle(compact: true))
        .help("Preview every Fix change before it replaces your selection")
        .accessibilityLabel("Preview and approve Fix changes")
        .accessibilityHint("Nothing changes until you approve the suggested fix.")
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(KColor.canvasRaised)
        .overlay(alignment: .bottom) { Rectangle().fill(KColor.line).frame(height: 1) }
    }

    private var showsCheckoutAction: Bool {
        settingsViewModel.remainingActions == 0
            && !settingsViewModel.isUnlimited
    }

    private var billingTitle: String {
        settingsViewModel.isUnlimited ? "Advanced" : "Free"
    }

    private var billingDetail: String {
        if settingsViewModel.isUnlimited { return "no monthly cap" }
        guard settingsViewModel.remainingActions != nil else { return "30 free / month" }
        return "\(usedActions) / 30 used"
    }

    private var remainingActions: Int {
        min(max(settingsViewModel.remainingActions ?? 30, 0), 30)
    }

    private var usedActions: Int { 30 - remainingActions }

}
