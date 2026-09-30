import SwiftUI

struct OnboardingView: View {
    @ObservedObject var viewModel: SettingsViewModel
    let onFinished: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            ZStack {
                if viewModel.onboardingStep == 0 {
                    welcome.transition(pageTransition)
                } else if viewModel.onboardingStep == 1 {
                    explanation.transition(pageTransition)
                } else {
                    permission.transition(pageTransition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
        }
        .background(KColor.canvas)
        .foregroundStyle(KColor.ink)
        .preferredColorScheme(.light)
    }

    private var pageTransition: AnyTransition {
        .opacity.combined(with: .move(edge: .trailing))
    }

    private var header: some View {
        HStack(spacing: 9) {
            QwixitLockup()
                .frame(width: 88, height: 28)
            Spacer()
            Text("QUICK SETUP")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(KColor.secondary)
        }
        .padding(.horizontal, 20)
        .frame(height: 50)
        .background(KColor.canvasRaised)
        .overlay(alignment: .bottom) { Rectangle().fill(KColor.line).frame(height: 1) }
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 5) {
                ForEach(0..<3) { index in
                    Capsule()
                        .fill(index <= viewModel.onboardingStep ? KColor.violet : KColor.line)
                        .frame(width: index == viewModel.onboardingStep ? 20 : 6, height: 4)
                }
            }
            Spacer()
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    if viewModel.onboardingStep < 2 {
                        viewModel.advanceOnboarding()
                    } else {
                        viewModel.completeOnboarding()
                        onFinished()
                    }
                }
            } label: {
                HStack(spacing: 16) {
                    Text(viewModel.onboardingStep == 2 ? "Start using Qwixit" : "Continue")
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(viewModel.onboardingStep == 2 && !viewModel.accessibilityGranted)
        }
        .padding(.horizontal, 20)
        .frame(height: 58)
        .background(KColor.canvasRaised)
        .overlay(alignment: .top) { Rectangle().fill(KColor.line).frame(height: 1) }
    }

    private var welcome: some View {
        HStack(spacing: 38) {
            QwixitMark(size: 112)
                .shadow(color: KColor.violet.opacity(0.16), radius: 18, y: 8)
            VStack(alignment: .leading, spacing: 9) {
                MonoLabel("MEET QWIXIT")
                Text("Better words.\nSame you.")
                    .font(.system(size: 37, weight: .black, design: .rounded))
                    .tracking(-1.1)
                Text("A tiny writing superpower for your Mac.")
                    .font(.system(size: 11))
                    .foregroundStyle(KColor.secondary)
            }
        }
        .padding(.horizontal, 54)
    }

    private var explanation: some View {
        VStack(spacing: 0) {
            MonoLabel("ONE SHORTCUT")
            Text("Improve text anywhere.")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .tracking(-0.8)
                .padding(.top, 7)
            Text("Select words in any app. Qwixit refines them in place without interrupting your flow.")
                .font(.system(size: 10.5))
                .foregroundStyle(KColor.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 430)
                .padding(.top, 9)

            HStack(spacing: 10) {
                demoTile(label: "SELECT") {
                    Text("sending a bit earlies")
                        .font(.system(size: 10))
                        .padding(4)
                        .background(KColor.violet.opacity(0.2))
                }
                Image(systemName: "arrow.right").foregroundStyle(KColor.secondary)
                demoTile(label: "PRESS") { ShortcutKeys() }
                Image(systemName: "arrow.right").foregroundStyle(KColor.secondary)
                demoTile(label: "CONTINUE") {
                    Text("Sending it a bit earlier.")
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            .padding(.top, 26)
        }
    }

    private var permission: some View {
        HStack(spacing: 34) {
            Image(systemName: viewModel.accessibilityGranted ? "checkmark" : "lock.shield.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(viewModel.accessibilityGranted ? KColor.success : KColor.violet)
                .frame(width: 84, height: 84)
                .background((viewModel.accessibilityGranted ? KColor.success : KColor.violet).opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke((viewModel.accessibilityGranted ? KColor.success : KColor.violet).opacity(0.28)))

            VStack(alignment: .leading, spacing: 10) {
                MonoLabel("ACCESSIBILITY")
                Text(viewModel.accessibilityGranted ? "You’re connected." : "One permission.")
                    .font(.system(size: 29, weight: .black, design: .rounded))
                Text(permissionDetail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(KColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 330, alignment: .leading)
                Button {
                    viewModel.requestAccessibility()
                } label: {
                    Label(viewModel.accessibilityGranted ? "Access granted" : "Open System Settings", systemImage: viewModel.accessibilityGranted ? "checkmark" : "arrow.up.forward.app")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(viewModel.accessibilityGranted)
            }
        }
        .padding(.horizontal, 52)
        .onAppear { viewModel.pollAccessibilityPermission() }
    }

    private var permissionDetail: String {
        if viewModel.accessibilityGranted { return "Qwixit can now improve selected text anywhere on your Mac." }
        if viewModel.needsRenamePermission { return LegacyMigration.renameNotice }
        return "Qwixit needs access to read and replace only the text you select. Nothing is monitored in the background."
    }

    private func demoTile<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 9) {
            content().frame(height: 28)
            Text(label)
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(KColor.secondary)
        }
        .frame(width: 142, height: 74)
        .background(KColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(KColor.line))
    }
}
