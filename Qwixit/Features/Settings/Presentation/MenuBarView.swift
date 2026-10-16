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
                brandHeader
                reviewModeRow
                if showsBillingStatus {
                    billingStatusRow
                }
                actionArea
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
            settingsViewModel.refreshUsage()
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

    private var brandHeader: some View {
        HStack(spacing: 7) {
            QwixitLockup()
                .frame(width: 108, height: 34, alignment: .leading)
            Spacer(minLength: 2)
            TokiriUI.PopupCloseButton(
                shortcut: HotkeyCatalog.popupDismiss.presentation,
                label: "Close Tokiri menu",
                action: onClose
            )
            Button(action: onOpenSettings) {
                AccessStatusBadge(
                    granted: settingsViewModel.accessibilityGranted,
                    compact: true
                )
            }
            .buttonStyle(.plain)
            .help(
                settingsViewModel.accessibilityGranted
                    ? "Tokiri can read and replace selected text"
                    : "Open Settings to allow Accessibility access"
            )
        }
        .padding(.horizontal, 14)
        .frame(height: 60)
        .background(KColor.canvasRaised)
        .overlay(alignment: .bottom) { Rectangle().fill(KColor.line).frame(height: 1) }
    }

    private var actionArea: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                CompactMenuAction(icon: .settings, title: "Settings") { onOpenSettings() }
                CompactMenuAction(icon: .quit, title: "Quit", destructive: true) { onQuit() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .frame(height: 40)

#if DEBUG
            // Testing-only controls. Keep this block DEBUG-gated so Release builds
            // expose only the user-facing Settings and Quit actions.
            HStack(spacing: 6) {
                CompactMenuAction(icon: .onboarding, title: "Onboarding", compact: true) { onShowOnboarding() }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 5)
            .frame(height: 35)
            .background(KColor.canvas)
            .overlay(alignment: .top) {
                Rectangle().fill(KColor.line.opacity(0.7)).frame(height: 1)
            }
#endif
        }
        .background(KColor.canvasRaised)
        .overlay(alignment: .top) { Rectangle().fill(KColor.line).frame(height: 1) }
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

    private var billingStatusRow: some View {
        HStack(spacing: 9) {
            QwixitFaceView(
                face: billingFace,
                size: 12,
                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            )
            Text(billingTitle)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
            Spacer()
            if showsCheckoutAction {
                Button("Get Advanced") {
                    settingsViewModel.openStarterCheckout()
                }
                .buttonStyle(PrimaryButtonStyle())
                .help("Open the Paddle sandbox checkout for Advanced · $10/month")
                .accessibilityLabel("Subscribe to Tokiri Advanced for ten dollars per month")
            } else {
                Text(billingDetail)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(KColor.secondary)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: showsCheckoutAction ? 44 : 34)
        .background(billingColor.opacity(0.055))
        .overlay(alignment: .top) { Rectangle().fill(billingColor.opacity(0.22)).frame(height: 1) }
    }

    private var showsCheckoutAction: Bool {
        settingsViewModel.remainingActions == 0
            && !settingsViewModel.isUnlimited
    }

    private var showsBillingStatus: Bool {
        settingsViewModel.isUnlimited
            || settingsViewModel.remainingActions != nil
    }

    private var billingFace: QwixitFace {
        if settingsViewModel.isUnlimited { return .advanced }
        return usedActions == 30 ? .pay : .hello
    }

    private var billingTitle: String {
        settingsViewModel.isUnlimited ? "Advanced active" : "\(usedActions) / 30 used"
    }

    private var billingDetail: String {
        if settingsViewModel.isUnlimited { return "no monthly cap" }
        return remainingActions == 0 ? "free plan complete" : "\(remainingActions) free left"
    }

    private var billingColor: Color {
        settingsViewModel.isUnlimited ? KColor.success : KColor.ink
    }

    private var remainingActions: Int {
        min(max(settingsViewModel.remainingActions ?? 30, 0), 30)
    }

    private var usedActions: Int { 30 - remainingActions }

}

private struct CompactMenuAction: View {
    let icon: TokiriUI.IconName
    let title: String
    var destructive = false
    var compact = false
    let action: () -> Void

    @ViewBuilder
    var body: some View {
        let label = HStack(spacing: 7) {
            TokiriUI.Icon(icon, size: 11)
            Text(title)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity)

        if compact {
            Button(action: action) {
                label
            }
            .buttonStyle(CompactButtonStyle(accent: destructive ? KColor.danger : KColor.violet))
        } else {
            Button(action: action) {
                label
            }
            .buttonStyle(PrimaryButtonStyle(compact: true))
        }
    }
}
