import SwiftUI

struct OnboardingView: View {
    @ObservedObject var viewModel: SettingsViewModel
    let onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .background(KColor.canvas)
        .foregroundStyle(KColor.ink)
        .qwixitTheme()
        .onAppear {
            viewModel.refreshAccessibility()
            if viewModel.onboardingStep == 0, viewModel.accessibilityGranted {
                viewModel.advanceOnboarding()
            }
        }
        .onChange(of: viewModel.onboardingStep) { _, step in
            if step == 0 { viewModel.pollAccessibilityPermission() }
        }
        .onChange(of: viewModel.accessibilityGranted) { _, granted in
            if granted, viewModel.onboardingStep == 0 {
                viewModel.advanceOnboarding()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            QwixitLockup().frame(width: 90, height: 30)
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<3) { index in
                    LevelPill(index: index, current: viewModel.onboardingStep)
                }
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 62)
        .background(KColor.canvasRaised)
        .overlay(alignment: .bottom) { Rectangle().fill(KColor.line).frame(height: 1) }
    }

    private var content: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .tracking(-0.8)
                .multilineTextAlignment(.center)
                .contentTransition(.interpolate)

            if viewModel.onboardingStep == 0 { permissionArea } else { demoArea }
            faceLine
        }
        .padding(.horizontal, 32)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: viewModel.onboardingDemoPhase)
        .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: viewModel.onboardingMenuVisible)
        .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: viewModel.onboardingStep)
    }

    private var demoArea: some View {
        VStack(spacing: 10) {
            demoCard
            actionZone.frame(height: 244)
        }
        .frame(maxWidth: 660)
    }

    private var demoCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(KColor.surface)
                .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(cardBorder, lineWidth: 1.5) }
                .shadow(color: KColor.violet.opacity(0.07), radius: 14, y: 6)

            HStack {
                Text(cardText)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(KColor.ink)
                    .contentTransition(.interpolate)
                    .animation(reduceMotion ? nil : .linear(duration: 0.02), value: viewModel.onboardingTypedText)
                    .padding(.horizontal, 4)
                    .background(preselected ? KColor.violet.opacity(0.18) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                if viewModel.onboardingDemoPhase == .typing {
                    Rectangle().fill(KColor.violet).frame(width: 3, height: 27).transition(.opacity)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 26)

            if viewModel.onboardingDemoPhase == .complete {
                Text("CLEAR")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 11)
                    .frame(height: 27)
                    .background(KColor.ink)
                    .clipShape(Capsule())
                    .rotationEffect(.degrees(-3))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .offset(x: -18, y: -13)
                    .transition(.scale(scale: 0.65).combined(with: .opacity))
            }
        }
        .frame(height: 92)
        .opacity(viewModel.onboardingDemoPhase == .processing ? 0.58 : 1)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var actionZone: some View {
        ZStack {
            if viewModel.onboardingMenuVisible {
                OnboardingPalette(viewModel: viewModel).transition(.scale(scale: 0.94).combined(with: .opacity))
            } else if isWorking {
                FeedbackPill(phase: .processing, reduceMotion: reduceMotion, onClose: {})
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            } else if viewModel.onboardingDemoPhase == .complete {
                FeedbackPill(phase: .success, reduceMotion: reduceMotion, onClose: {})
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            } else {
                OnboardingKeys(
                    level: viewModel.onboardingStep,
                    tapCount: viewModel.onboardingLevel2TapCount,
                    key: viewModel.mainHotkey.keySymbol,
                    optionDown: viewModel.onboardingOptionDown,
                    commandDown: viewModel.onboardingCommandDown,
                    reduceMotion: reduceMotion
                )
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var permissionArea: some View {
        VStack(spacing: 14) {
            Button(action: handlePermissionAction) {
                HStack(spacing: 14) {
                    Image(systemName: "accessibility")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(KColor.violet)
                        .frame(width: 42, height: 42)
                        .background(KColor.violet.opacity(0.09))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.accessibilityGranted ? "Continue to practice" : "Allow Accessibility access")
                            .font(.system(size: 16, weight: .bold))
                        Text(viewModel.accessibilityGranted
                             ? "Access granted"
                             : "System Settings → Privacy & Security → Accessibility")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(KColor.secondary)
                    }
                    Spacer()
                    Text(viewModel.accessibilityGranted ? "CONTINUE" : "ALLOW")
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(KColor.ink)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(16)
                .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [])
            .frame(maxWidth: 560)
            .qwixitPanel(cornerRadius: 15)
            .accessibilityHint(viewModel.accessibilityGranted
                               ? "Starts shortcut practice"
                               : "Opens Accessibility in System Settings")

            HStack(spacing: 8) {
                Circle().fill(viewModel.accessibilityGranted ? KColor.success : KColor.warning).frame(width: 7, height: 7)
                Text(viewModel.accessibilityGranted
                     ? "ACCESS GRANTED · PRESS ENTER TO CONTINUE"
                     : "PRESS ENTER TO OPEN SYSTEM SETTINGS")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(viewModel.accessibilityGranted ? KColor.success : KColor.ink)
            }
            .frame(height: 42)
        }
        .frame(height: 188)
        .onAppear { viewModel.pollAccessibilityPermission() }
    }

    private var faceLine: some View {
        HStack(spacing: 11) {
            QwixitFaceView(face: face, size: 12, reduceMotion: reduceMotion || isWorking)
                .frame(width: 58, height: 36)
                .background(KColor.violet.opacity(0.09))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(faceCopy)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(KColor.ink)
                .contentTransition(.interpolate)
                .frame(maxWidth: 500, alignment: .leading)
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .background(KColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: 11))
        }
        .frame(minHeight: 46)
        .accessibilityElement(children: .combine)
    }

    private func handlePermissionAction() {
        if viewModel.accessibilityGranted {
            viewModel.advanceOnboarding()
        } else {
            viewModel.requestAccessibility()
        }
    }

    private var footer: some View {
        HStack {
            Text(viewModel.onboardingStep == 0
                 ? "ACCESSIBILITY IS REQUIRED TO REPLACE SELECTED TEXT"
                 : "\(viewModel.onboardingStep) / 2 · PRACTICE TEXT STAYS ON YOUR MAC")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(KColor.secondary)
            Spacer()
            if canContinue {
                Button(action: continueOnboarding) {
                    HStack(spacing: 7) {
                        Text("PRESS ENTER TO CONTINUE")
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13)
                    .frame(height: 32)
                    .background(KColor.violet)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [])
                .accessibilityHint("Continues to the next onboarding step")
            } else {
                Text(footerPrompt)
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(KColor.violet)
            }
        }
        .padding(.horizontal, 28)
        .frame(height: 58)
        .background(KColor.canvasRaised)
        .overlay(alignment: .top) { Rectangle().fill(KColor.line).frame(height: 1) }
    }

    private var canContinue: Bool {
        viewModel.onboardingStep > 0 && viewModel.onboardingDemoPhase == .complete
    }

    private var footerPrompt: String {
        if viewModel.onboardingStep == 0 {
            return viewModel.accessibilityGranted
                ? "PRESS ENTER TO CONTINUE"
                : "PRESS ENTER TO OPEN SETTINGS"
        }
        return viewModel.mainHotkey.displayString
    }

    private func continueOnboarding() {
        guard canContinue else { return }
        if viewModel.onboardingStep == 2 {
            viewModel.completeOnboarding()
            onFinish()
        } else {
            viewModel.advanceOnboarding()
        }
    }

    private var title: String {
        switch viewModel.onboardingStep {
        case 0: "Let’s set up Qwixit."
        case 1: "Fix it with one shortcut."
        default: "Open the action palette."
        }
    }

    private var cardText: String {
        switch viewModel.onboardingDemoPhase {
        case .typing, .complete: viewModel.onboardingTypedText
        case .waiting, .processing: viewModel.onboardingOriginalText
        }
    }
    private var preselected: Bool { viewModel.onboardingDemoPhase == .waiting }
    private var cardBorder: Color {
        if viewModel.onboardingDemoPhase == .complete { return KColor.violet }
        return KColor.line
    }
    private var isWorking: Bool { viewModel.onboardingDemoPhase == .processing || viewModel.onboardingDemoPhase == .typing }

    private var face: QwixitFace {
        if isWorking { return .retry }
        if viewModel.onboardingDemoPhase == .complete { return .hello }
        if viewModel.onboardingStep == 0 { return viewModel.accessibilityGranted ? .ready : .boot }
        if viewModel.onboardingMenuVisible { return .pay }
        return viewModel.onboardingLevel2TapCount == 1 ? .lost : .hello
    }

    private var faceCopy: String {
        if isWorking { return "on it…" }
        if viewModel.onboardingDemoPhase == .complete {
            return switch viewModel.onboardingStep {
            case 1: "nice. that’s the main shortcut."
            default: "done. press Enter or click Continue to finish setup."
            }
        }
        switch viewModel.onboardingStep {
        case 1:
            return "sample text is selected. press \(viewModel.mainHotkey.displayString) once."
        case 2:
            if viewModel.onboardingMenuVisible { return "arrow keys choose. Enter applies." }
            return viewModel.onboardingLevel2TapCount == 1 ? "one tap. tap it again." : "press \(viewModel.mainHotkey.displayString) twice."
        default:
            return viewModel.accessibilityGranted
                ? "granted. press Enter to start practice."
                : "press Enter. I’ll open the right System Settings pane."
        }
    }
}

private struct LevelPill: View {
    let index: Int
    let current: Int
    private var done: Bool { index < current }
    private var active: Bool { index == current && !done }
    private var label: String {
        switch index {
        case 0: "ACCESS"
        case 1: "PRESS ONCE"
        default: "TAP TWICE"
        }
    }

    var body: some View {
        Text(done ? "✓ \(label)" : label)
            .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.45)
            .foregroundStyle(active ? .white : (done ? KColor.violet : KColor.secondary))
            .padding(.horizontal, 10).frame(height: 27)
            .background(active ? KColor.ink : (done ? KColor.violet.opacity(0.11) : .clear))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay {
                if !active && !done {
                    RoundedRectangle(cornerRadius: 7).stroke(KColor.line, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
    }
}

private struct OnboardingKeys: View {
    let level: Int
    let tapCount: Int
    let key: String
    let optionDown: Bool
    let commandDown: Bool
    let reduceMotion: Bool
    @State private var demoStage = 0

    var body: some View {
        VStack(spacing: 12) {
            Text(level == 1 ? "PRESS ONCE" : "DOUBLE TAP")
                .font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(1.6).foregroundStyle(KColor.violet)
            HStack(spacing: 12) {
                BigKey(symbol: "⌥", caption: "HOLD", accent: false, pressed: optionDown || demoStage >= 1)
                plus
                BigKey(symbol: "⌘", caption: "HOLD", accent: false, pressed: commandDown || demoStage >= 2)
                plus
                BigKey(symbol: key, caption: level == 2 ? (tapCount == 1 ? "TAP AGAIN" : "TAP ×2") : "TAP", accent: true, pressed: demoStage == 3)
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.16), value: tapCount)
        .task(id: "\(level)-\(optionDown)-\(commandDown)-\(reduceMotion)") {
            demoStage = 0
            guard !reduceMotion, !optionDown, !commandDown else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(850)); demoStage = 1
                try? await Task.sleep(for: .milliseconds(240)); demoStage = 2
                try? await Task.sleep(for: .milliseconds(240)); demoStage = 3
                try? await Task.sleep(for: .milliseconds(150))
                if level == 2 {
                    demoStage = 2
                    try? await Task.sleep(for: .milliseconds(160)); demoStage = 3
                    try? await Task.sleep(for: .milliseconds(150))
                }
                demoStage = 0
                try? await Task.sleep(for: .milliseconds(850))
            }
        }
    }
    private var plus: some View {
        Text("+").font(.system(size: 19, weight: .bold, design: .monospaced)).foregroundStyle(KColor.line)
    }
}

private struct BigKey: View {
    let symbol: String
    let caption: String
    let accent: Bool
    let pressed: Bool
    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 18).fill(accent ? KColor.violet.opacity(0.7) : KColor.ink).frame(width: 76, height: 78)
                RoundedRectangle(cornerRadius: 18)
                    .fill(accent ? KColor.violet : KColor.surface)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(accent ? KColor.violet : KColor.ink, lineWidth: 2))
                    .frame(width: 76, height: 70).offset(y: pressed ? 7 : 0)
                Text(symbol)
                    .font(.system(size: accent ? 31 : 30, weight: .black, design: accent ? .rounded : .default))
                    .foregroundStyle(accent ? .white : KColor.ink).offset(y: pressed ? 7 : 0)
            }
            Text(caption).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(accent ? KColor.violet : KColor.secondary)
        }
    }
}

private struct OnboardingPalette: View {
    @ObservedObject var viewModel: SettingsViewModel
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                QwixitMark(size: 26)
                Text("Action or instruction…").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(KColor.secondary)
                Spacer()
                Text("9 words · EN").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(KColor.secondary)
            }.padding(.horizontal, 14).frame(height: 45)
            Divider().overlay(KColor.line)
            VStack(spacing: 2) {
                Text("Actions").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(KColor.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.bottom, 2)
                paletteRow(action: .ukrainian, title: "Translate to Ukrainian", accent: KColor.cyan)
                paletteRow(action: .polish, title: "Translate to Polish", accent: KColor.cyan)
                paletteRow(action: .slack, title: "Slack style", accent: KColor.success)
                paletteRow(action: .formal, title: "Make formal", accent: KColor.success)
            }.padding(8)
            Divider().overlay(KColor.line)
            HStack {
                RoundedRectangle(cornerRadius: 2).fill(KColor.cyan).frame(width: 8, height: 8)
                Text("Replace · rewrites the selection · ⌘Z undoes")
                Spacer(); Text("↑↓ · ↵ · Esc")
            }
            .font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(KColor.secondary)
            .padding(.horizontal, 14).frame(height: 34)
        }
        .frame(width: 520, height: 244).qwixitPanel(cornerRadius: 17)
        .shadow(color: KColor.ink.opacity(0.12), radius: 16, y: 7)
    }

    private func paletteRow(action: OnboardingAction, title: String, accent: Color) -> some View {
        let selected = viewModel.onboardingMenuSelection == action.rawValue
        return HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 1).fill(accent).frame(width: 3, height: 18)
            Text(title).fontWeight(.bold)
            Spacer()
            Text("[\(action.rawValue + 1)]")
                .foregroundStyle(selected ? accent : KColor.secondary)
        }
        .font(.system(size: 10, design: .monospaced)).padding(.horizontal, 9).frame(height: 34)
        .background(selected ? accent.opacity(0.1) : .clear).clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}
