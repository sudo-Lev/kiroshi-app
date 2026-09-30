import SwiftUI

struct MenuBarView: View {
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var quickImproveViewModel: QuickImproveViewModel
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            utilityBar
            brandHeader
            statusPanel
            actionArea
        }
        .frame(width: 318)
        .background(KColor.canvas)
        .foregroundStyle(KColor.ink)
        .preferredColorScheme(.light)
        .onAppear { settingsViewModel.refreshAccessibility() }
    }

    private var utilityBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 11))
            Text("v1.0")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
            Spacer()
            Text(settingsViewModel.hasAPIKey ? "OPENAI" : "LOCAL")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(settingsViewModel.hasAPIKey ? KColor.cyan : KColor.secondary)
        }
        .foregroundStyle(KColor.secondary)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(KColor.canvasRaised)
        .overlay(alignment: .bottom) { Rectangle().fill(KColor.line).frame(height: 1) }
    }

    private var brandHeader: some View {
        HStack(spacing: 11) {
            VStack(alignment: .leading, spacing: 2) {
                QwixitLockup()
                    .frame(width: 108, height: 29, alignment: .leading)
                Text("Writing, refined in place")
                    .font(.system(size: 9.5))
                    .foregroundStyle(KColor.secondary)
            }
            Spacer()
            Circle()
                .fill(settingsViewModel.accessibilityGranted ? KColor.success : KColor.warning)
                .frame(width: 9, height: 9)
                .shadow(color: (settingsViewModel.accessibilityGranted ? KColor.success : KColor.warning).opacity(0.6), radius: 5)
        }
        .padding(.horizontal, 14)
        .frame(height: 68)
        .background(KColor.canvasRaised)
        .overlay(alignment: .bottom) { Rectangle().fill(KColor.line).frame(height: 1) }
    }

    private var statusPanel: some View {
        HStack(spacing: 10) {
            Image(systemName: settingsViewModel.accessibilityGranted ? "bolt.fill" : "lock.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(settingsViewModel.accessibilityGranted ? KColor.violet : KColor.warning)
                .frame(width: 34, height: 34)
                .background((settingsViewModel.accessibilityGranted ? KColor.violet : KColor.warning).opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                Text(statusDetail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(KColor.secondary)
            }
            Spacer()
            ShortcutKeys()
        }
        .padding(12)
        .kCard()
        .padding(12)
    }

    private var actionArea: some View {
        HStack(spacing: 0) {
            CompactMenuAction(icon: "gearshape.fill", title: "Settings") { onOpenSettings() }
            Rectangle().fill(KColor.line).frame(width: 1, height: 24)
            CompactMenuAction(icon: "power", title: "Quit", destructive: true) { onQuit() }
        }
        .frame(height: 43)
        .background(KColor.canvasRaised)
        .overlay(alignment: .top) { Rectangle().fill(KColor.line).frame(height: 1) }
    }

    private var statusTitle: String {
        if quickImproveViewModel.isProcessing { return "QWIXING" }
        return settingsViewModel.accessibilityGranted ? "READY" : "ACCESS NEEDED"
    }

    private var statusDetail: String {
        if quickImproveViewModel.isProcessing { return "Qwixing selected text" }
        return settingsViewModel.accessibilityGranted
            ? "\(settingsViewModel.mainHotkey.displayString) is active"
            : "Grant Accessibility access"
    }
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
