import SwiftUI

struct OnboardingView: View {
    @ObservedObject var viewModel: SettingsViewModel
    let onFinished: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .qwixitTheme()
    }

    private var pageTransition: AnyTransition {
        .opacity.combined(with: .move(edge: .trailing))
    }

    private var header: some View {
        HStack(spacing: 9) {
            QwixitLockup()
                .frame(width: 88, height: 28)
            Spacer()
            Text("Quick setup")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.35)
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
            if viewModel.onboardingStep == 1,
               viewModel.onboardingDemoPhase != .complete {
                Button("Skip demo") { viewModel.skipOnboardingDemo() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(KColor.secondary)
            }
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
            .disabled(
                (viewModel.onboardingStep == 1 && viewModel.onboardingDemoPhase != .complete)
                    || (viewModel.onboardingStep == 2 && !viewModel.accessibilityGranted)
            )
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
                QwixitFaceView(face: .hello, size: 40)
                MonoLabel("Meet Qwixit")
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
            MonoLabel("Your turn")
            Text("Fix this mess.")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .tracking(-0.8)
                .padding(.top, 7)

            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(KColor.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(viewModel.onboardingDemoPhase == .complete ? KColor.success.opacity(0.38) : KColor.line)
                    )

                HStack(spacing: 12) {
                    Text(demoPhrase)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(KColor.ink)
                        .id(demoPhrase)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))

                    Spacer(minLength: 8)

                    if viewModel.onboardingDemoPhase == .processing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(KColor.violet)
                    } else if viewModel.onboardingDemoPhase == .complete {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(KColor.success)
                    }
                }
                .padding(.horizontal, 20)
            }
            .frame(width: 500, height: 72)
            .padding(.top, 22)

            Button(action: viewModel.runOnboardingDemo) {
                HStack(spacing: 15) {
                    QwixitFaceView(
                        face: demoFace,
                        size: 21,
                        reduceMotion: reduceMotion
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(demoCallToAction)
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundStyle(KColor.ink)
                        Text(demoCallToActionDetail)
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(KColor.secondary)
                    }

                    Spacer(minLength: 10)

                    HStack(spacing: 5) {
                        ForEach(
                            Array((viewModel.mainHotkey.modifierSymbols + [viewModel.mainHotkey.keySymbol]).enumerated()),
                            id: \.offset
                        ) { index, symbol in
                            Keycap(
                                symbol: symbol,
                                active: index == viewModel.mainHotkey.modifierSymbols.count
                            )
                        }
                    }
                }
                .padding(.horizontal, 18)
                .frame(width: 500, height: 82)
                .background(KColor.violet.opacity(0.09))
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .overlay(
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(KColor.violet.opacity(0.34), lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.onboardingDemoPhase != .waiting || viewModel.mainHotkeyConflict)
            .scaleEffect(viewModel.onboardingDemoPhase == .processing ? 0.985 : 1)
            .padding(.top, 13)
            .help("Run the local shortcut demo")

            Text("local demo. nothing gets uploaded.")
                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(KColor.secondary)
                .padding(.top, 10)
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: viewModel.onboardingDemoPhase)
    }

    private var demoPhrase: String {
        switch viewModel.onboardingDemoPhase {
        case .waiting, .processing: "helo i thnik this sentnce sound wierd"
        case .complete: "Hello, I think this sentence sounds weird."
        }
    }

    private var demoFace: QwixitFace {
        switch viewModel.onboardingDemoPhase {
        case .waiting: .hello
        case .processing: .retry
        case .complete: .ready
        }
    }

    private var demoCallToAction: String {
        if viewModel.mainHotkeyConflict { return "Shortcut is busy." }
        return switch viewModel.onboardingDemoPhase {
        case .waiting: "Yo. Hit the hotkeys."
        case .processing: "Qwixing this mess…"
        case .complete: "Yep. That’s Qwixit."
        }
    }

    private var demoCallToActionDetail: String {
        if viewModel.mainHotkeyConflict { return "skip for now. change it in settings." }
        return switch viewModel.onboardingDemoPhase {
        case .waiting: "let’s see what happens."
        case .processing: "hold on. making it human."
        case .complete: "same thought. better words."
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
                QwixitFaceView(
                    face: viewModel.accessibilityGranted ? .ready : .boot,
                    size: 30,
                    stagger: 1
                )
                Text(viewModel.accessibilityGranted ? QwixitFace.ready.line : QwixitFace.boot.line)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(KColor.secondary)
                MonoLabel("Accessibility")
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

}
