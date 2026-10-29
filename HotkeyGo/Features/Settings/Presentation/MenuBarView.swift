import SwiftUI
import AppKit

struct MenuBarView: View {
    private let wrapperShape = HotkeyGoControlShape(cut: 16)
    @State private var isAboutHovered = false
    @State private var isPlanRowHovered = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var planStatus: PlanStatus
    @ObservedObject var quickImproveViewModel: QuickImproveViewModel
    let onShowAbout: () -> Void
    let onOpenSettings: () -> Void
    let onShowOnboarding: () -> Void
    let onQuit: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            utilityBar
            statusRow
            reviewModeRow
            actionsRow
        }
        .frame(width: 360)
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
            accessibilityStatus
        }
        .foregroundStyle(HotkeyGoColor.ink)
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(HotkeyGoColor.canvasRaised)
        .overlay(alignment: .bottom) { Rectangle().fill(HotkeyGoColor.line).frame(height: 1) }
    }

    private var accessibilityStatus: some View {
        HStack(spacing: 4) {
            Text(settingsViewModel.accessibilityGranted ? "Access" : "Access Needed")
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .foregroundStyle(settingsViewModel.accessibilityGranted ? HotkeyGoColor.success : HotkeyGoColor.warning)
            Circle()
                .fill(settingsViewModel.accessibilityGranted ? HotkeyGoColor.success : HotkeyGoColor.warning)
                .frame(width: 7, height: 7)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(settingsViewModel.accessibilityGranted
            ? "Accessibility access granted"
            : "Accessibility access needed")
        .help(settingsViewModel.accessibilityGranted ? "Accessibility access granted" : "Accessibility access required")
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: settingsViewModel.accessibilityGranted)
    }

    private var statusRow: some View {
        ZStack {
            if isLimitReached {
                Button(action: openCheckoutAndClose) {
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Free plan limit reached. Get Advanced.")
                .help("Open Advanced checkout")
            }

            HStack(spacing: 14) {
                HotkeyGoFaceView(
                    face: planStatus.isAdvanced ? .advanced : .hello,
                    size: 14.45,
                    reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                    color: planStatus.isAdvanced ? HotkeyGoColor.planGreen : HotkeyGoColor.ink,
                    chromaticSplit: 1.275,
                    shouldBlink: false
                )
                .accessibilityHidden(true)
                .contentTransition(.opacity)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(planStatus.isAdvanced ? "Advanced" : "Free")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(HotkeyGoColor.ink)
                            .fixedSize()
                        PlanMeterView(value: planStatus.meterValue)
                    }
                    Text(planDescription)
                        .font(.custom("JetBrains Mono Medium", size: 11))
                        .foregroundStyle(isLimitReached ? HotkeyGoColor.danger : HotkeyGoColor.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(planAccessibilityLabel)
                .accessibilityHidden(isLimitReached)

                if isLimitReached {
                    Button("Get Advanced", action: openCheckoutAndClose)
                        .buttonStyle(HotkeyGoUI.PrimaryButton(compact: true))
                        .fixedSize()
                        .transition(.opacity)
                        .help("Open the Paddle sandbox checkout for Advanced · $10/month")
                        .accessibilityLabel("Get Advanced")
                } else {
                    HotkeyGoUI.PopupCloseButton(
                        shortcut: settingsViewModel.mainHotkey.presentation,
                        label: "Close hotkeygo menu",
                        action: onClose
                    )
                    .transition(.opacity)
                }

            }
            .padding(.leading, 20)
            .padding(.trailing, 12)
            .frame(height: 66)
            .background {
                if isLimitReached {
                    HotkeyGoColor.danger.opacity(isPlanRowHovered
                        ? (colorScheme == .dark ? 0.12 : 0.09)
                        : (colorScheme == .dark ? 0.07 : 0.05))
                } else {
                    HotkeyGoColor.planMenuSurface
                }
            }
            .overlay(alignment: .bottom) {
                HotkeyGoUI.UsageTicks(
                    used: planStatus.isAdvanced ? 30 : planStatus.used,
                    tone: planStatus.meterValue.tone
                )
                .padding(.leading, 20)
                .padding(.trailing, 12)
            }
        }
        .frame(height: 66)
        .contentShape(Rectangle())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: planStatus.snapshot.plan)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isLimitReached)
        .onHover { hovering in
            isPlanRowHovered = hovering
            guard isLimitReached else { return }
            if hovering { NSCursor.pointingHand.push() }
            else { NSCursor.pop() }
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
                        .frame(width: halfWidth, height: 30)
                    quitActionCell
                        .frame(width: halfWidth, height: 30)
                }

                actionCell(
                    icon: .onboarding,
                    title: "Onboarding",
                    accessibilityLabel: "hotkeygo onboarding",
                    action: onShowOnboarding
                )
                    .frame(width: contentWidth, height: 30)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(height: 80)
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

    private var isLimitReached: Bool {
        !planStatus.isAdvanced && planStatus.used == 30
    }

    private var planDescription: String {
        if planStatus.isAdvanced { return "more room to work" }
        if let usage = planStatus.snapshot.usage, usage.used == usage.limit {
            return "Resets \(formattedDate(usage.resetsAt))"
        }
        return "\(planStatus.used) / 30 used"
    }

    private var planAccessibilityLabel: String {
        if planStatus.isAdvanced { return "Advanced plan" }
        if let usage = planStatus.snapshot.usage, usage.used == usage.limit {
            return "Free plan limit reached, resets \(formattedDate(usage.resetsAt))"
        }
        return "Free plan, \(planStatus.used) of 30 actions used this month"
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func openCheckoutAndClose() {
        if settingsViewModel.openStarterCheckout() { onClose() }
    }

}
