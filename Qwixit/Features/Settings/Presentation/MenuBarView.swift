import SwiftUI
import AppKit

struct MenuBarView: View {
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var quickImproveViewModel: QuickImproveViewModel
    let onOpenSettings: () -> Void
    let onShowOnboarding: () -> Void
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
        .background(KColor.canvas)
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
        HStack(spacing: 0) {
            CompactMenuAction(icon: "gearshape.fill", title: "Settings") { onOpenSettings() }
            Rectangle().fill(KColor.line).frame(width: 1, height: 24)
            CompactMenuAction(icon: "sparkles", title: "Onboarding") { onShowOnboarding() }
            Rectangle().fill(KColor.line).frame(width: 1, height: 24)
            CompactMenuAction(icon: "power", title: "Quit", destructive: true) { onQuit() }
        }
        .frame(height: 43)
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
        settingsViewModel.billingActivationState == .idle
            && settingsViewModel.remainingActions == 0
            && !settingsViewModel.isUnlimited
    }

    private var showsBillingStatus: Bool {
        settingsViewModel.isUnlimited
            || settingsViewModel.remainingActions != nil
            || settingsViewModel.billingActivationState == .confirming
            || settingsViewModel.billingActivationState == .delayed
    }

    private var billingFace: QwixitFace {
        switch settingsViewModel.billingActivationState {
        case .confirming: .retry
        case .delayed: .lost
        case .ready: .ready
        case .idle: usedActions == 30 ? .pay : .hello
        }
    }

    private var billingTitle: String {
        switch settingsViewModel.billingActivationState {
        case .confirming: "Activating…"
        case .delayed: "Still syncing"
        case .ready: "Unlimited ready"
        case .idle: "\(usedActions) / 30 used"
        }
    }

    private var billingDetail: String {
        switch settingsViewModel.billingActivationState {
        case .confirming: "Unlimited sync"
        case .delayed: "Paddle is slow"
        case .ready: "all unlocked"
        case .idle: remainingActions == 0 ? "free plan complete" : "\(remainingActions) free left"
        }
    }

    private var billingColor: Color {
        switch settingsViewModel.billingActivationState {
        case .confirming, .delayed: KColor.cyan
        case .ready: KColor.success
        case .idle: KColor.ink
        }
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(destructive ? KColor.danger : KColor.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
