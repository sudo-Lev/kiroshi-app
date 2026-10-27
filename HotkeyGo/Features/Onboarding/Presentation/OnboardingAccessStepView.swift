import SwiftUI

struct OnboardingAccessStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var accessPulse = false

    var body: some View {
        ZStack {
            if viewModel.accessibilityGranted {
                grantedAccess
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else if viewModel.isRequestingAccessibility {
                gettingAccess
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                noAccess
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.16) : .timingCurve(0.2, 0.9, 0.3, 1, duration: 0.28),
            value: viewModel.isRequestingAccessibility
        )
        .animation(
            reduceMotion ? .easeOut(duration: 0.16) : .timingCurve(0.2, 0.9, 0.3, 1, duration: 0.28),
            value: viewModel.accessibilityGranted
        )
    }

    private var noAccess: some View {
        VStack(spacing: 18) {
            accessIcon(.accessNeeded, active: false)
            Text("hotkeygo needs Accessibility access.").onboardingTitle(30)
            Text("Allow hotkeygo in Privacy & Security › Accessibility. This lets hotkeygo read and replace selected text only when you use a shortcut.")
                .onboardingBody().multilineTextAlignment(.center).frame(maxWidth: 500)
            if viewModel.permissionCheckTimedOut {
                Text("Access wasn’t detected yet. You can reopen System Settings and try again.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(HotkeyGoColor.warning)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
            Button { viewModel.requestAccessibility() } label: {
                HStack(spacing: 9) {
                    Text(viewModel.permissionCheckTimedOut ? "Try again" : "Allow access")
                    HotkeyGoUI.Icon(.externalLink, size: 10)
                }
            }
                .buttonStyle(HotkeyGoUI.PrimaryButton())
                .accessibilityLabel("Allow hotkeygo in Accessibility settings")
                .accessibilityHint("Opens Accessibility settings in System Settings")
        }
        .padding(.top, 40)
    }

    private var grantedAccess: some View {
        VStack(spacing: 18) {
            accessIcon(.accessGranted, active: false, accent: HotkeyGoColor.success)
            Text("Access granted.").onboardingTitle(30)
            Text("Now try Fix, Actions, and Peek with a sample selection. Your text stays on your Mac during this rehearsal.")
                .onboardingBody().multilineTextAlignment(.center).frame(maxWidth: 500)
            HStack(spacing: 8) {
                HotkeyGoUI.Icon(.statusSuccess, size: 12)
                Text("ACCESS GRANTED · PRESS ENTER TO CONTINUE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(HotkeyGoColor.success)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(HotkeyGoColor.success.opacity(0.09), in: HotkeyGoControlShape(cut: 6))
        }
        .padding(.top, 40)
    }

    private var gettingAccess: some View {
        VStack(spacing: 18) {
            accessIcon(.accessGranted, active: true)
            Text("Finish in System Settings.").onboardingTitle(30)
            Text("Turn on hotkeygo under Accessibility. We’ll keep this screen here and confirm when access is detected.")
                .onboardingBody().multilineTextAlignment(.center).frame(maxWidth: 520)

            HStack(spacing: 13) {
                accessPathItem(.settings, "Privacy & Security")
                HotkeyGoUI.Icon(.chevronRight, size: 10)
                accessPathItem(.accessibility, "Accessibility")
                HotkeyGoUI.Icon(.chevronRight, size: 10)
                accessPathItem(.switchControl, "hotkeygo on")
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(HotkeyGoColor.secondary)
            .padding(.horizontal, 18)
            .frame(height: 46)
            .background(HotkeyGoColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(HotkeyGoColor.line) }

            HStack(spacing: 9) {
                ProgressView().controlSize(.small).tint(HotkeyGoColor.violet)
                Text("Waiting for access…")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(HotkeyGoColor.ink)
                Button { viewModel.requestAccessibility() } label: {
                    HStack(spacing: 7) {
                        Text("Open System Settings again")
                        HotkeyGoUI.Icon(.externalLink, size: 9)
                    }
                }
                    .buttonStyle(SubtleButtonStyle())
            }
        }
        .padding(.top, 38)
    }

    private func accessIcon(_ name: HotkeyGoUI.IconName, active: Bool, accent: Color = HotkeyGoColor.violet) -> some View {
        ZStack {
            if active {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(accent.opacity(0.28), lineWidth: 2)
                    .frame(width: 72, height: 72)
                    .scaleEffect(accessPulse ? 1.28 : 0.94)
                    .opacity(accessPulse ? 0 : 1)
            }
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(accent.opacity(active ? 0.14 : 0.09))
            HotkeyGoUI.Icon(name, size: 28)
                .foregroundStyle(accent)
        }
        .frame(width: 64, height: 64)
        .onAppear {
            accessPulse = false
            guard active, !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.45).repeatForever(autoreverses: false)) {
                accessPulse = true
            }
        }
    }

    private func accessPathItem(_ icon: HotkeyGoUI.IconName, _ title: String) -> some View {
        HStack(spacing: 6) {
            HotkeyGoUI.Icon(icon, size: 12).foregroundStyle(HotkeyGoColor.violet)
            Text(title)
        }
        .fixedSize()
    }
}
