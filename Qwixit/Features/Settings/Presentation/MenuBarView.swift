import SwiftUI
import AppKit

struct MenuBarView: View {
    private let wrapperShape = QwixitControlShape(cut: 16)

    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var quickImproveViewModel: QuickImproveViewModel
    let onOpenSettings: () -> Void
    let onShowOnboarding: () -> Void
    let onShowRunningToast: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            utilityBar
            brandHeader
            if showsBillingStatus {
                billingStatusRow
            }
            actionArea
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
            Image(systemName: "info.circle.fill")
                .font(.system(size: 11))
            Text("v1.0")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
            Spacer()
            Text("Cloud")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.3)
                .foregroundStyle(KColor.cyan)
        }
        .foregroundStyle(KColor.secondary)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(KColor.canvasRaised)
        .overlay(alignment: .bottom) { Rectangle().fill(KColor.line).frame(height: 1) }
    }

    private var brandHeader: some View {
        HStack(spacing: 7) {
            QwixitLockup()
                .frame(width: 108, height: 34, alignment: .leading)
            Spacer(minLength: 2)
            ShortcutKeys()
            Button(action: onOpenSettings) {
                AccessStatusBadge(
                    granted: settingsViewModel.accessibilityGranted,
                    compact: true
                )
            }
            .buttonStyle(.plain)
            .help(
                settingsViewModel.accessibilityGranted
                    ? "Qwixit can read and replace selected text"
                    : "Open Settings to allow Accessibility access"
            )
        }
        .padding(.horizontal, 14)
        .frame(height: 68)
        .background(KColor.canvasRaised)
        .overlay(alignment: .bottom) { Rectangle().fill(KColor.line).frame(height: 1) }
    }

    private var actionArea: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                CompactMenuAction(icon: "gearshape.fill", title: "Settings") { onOpenSettings() }
                CompactMenuAction(icon: "power", title: "Quit", destructive: true) { onQuit() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .frame(height: 40)

#if DEBUG
            // Testing-only controls. Keep this block DEBUG-gated so Release builds
            // expose only the user-facing Settings and Quit actions.
            HStack(spacing: 6) {
                CompactMenuAction(icon: "sparkles", title: "Onboarding", compact: true) { onShowOnboarding() }
                CompactMenuAction(icon: "bubble.left.fill", title: "Toast", compact: true) { onShowRunningToast() }
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
                Button("Go unlimited") {
                    settingsViewModel.openStarterCheckout()
                }
                .buttonStyle(PrimaryButtonStyle())
                .help("Open the Paddle sandbox checkout · $10/month")
                .accessibilityLabel("Subscribe to Qwixit Unlimited for ten dollars per month")
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
        if settingsViewModel.isUnlimited { return .ready }
        return usedActions == 30 ? .pay : .hello
    }

    private var billingTitle: String {
        settingsViewModel.isUnlimited ? "Unlimited ready" : "\(usedActions) / 30 used"
    }

    private var billingDetail: String {
        if settingsViewModel.isUnlimited { return "all unlocked" }
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
    let icon: String
    let title: String
    var destructive = false
    var compact = false
    let action: () -> Void

    @ViewBuilder
    var body: some View {
        let label = HStack(spacing: 7) {
            Image(systemName: icon)
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
