import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    let onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var demoKeys = 0
    @State private var accessPulse = false
    private let labels = ["Welcome", "Access", "Fix", "Choose", "Done"]

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack { content.id(model.step) }
                .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
                .animation(reduceMotion ? .easeOut(duration: 0.16) : .timingCurve(0.2, 0.9, 0.3, 1, duration: 0.26), value: model.step)
            footer
        }
        .frame(width: 820, height: 640)
        .background(KColor.canvas).foregroundStyle(KColor.ink).qwixitTheme()
        .task(id: model.step) { await runKeyDemo() }
        .onAppear { model.refreshAccessibility() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            QwixitLockup().frame(width: 86, height: 24)
            Spacer()
            HStack(spacing: 0) {
                ForEach(labels.indices, id: \.self) { index in
                    Button {
                        while model.step > index { model.goBack() }
                    } label: {
                        Text(index < model.step ? "✓ \(labels[index])" : labels[index])
                    }
                    .buttonStyle(CompactButtonStyle(
                        accent: index < model.step ? KColor.success : KColor.violet,
                        isSelected: index == model.step,
                        prominent: index == model.step
                    ))
                    .disabled(index > model.step)
                    .accessibilityLabel("\(labels[index]), \(index == model.step ? "current" : index < model.step ? "complete; go back" : "upcoming")")
                    if index < labels.count - 1 { Rectangle().fill(KColor.line).frame(width: 8, height: 1) }
                }
            }
        }
        .padding(.leading, 78).padding(.trailing, 22).frame(height: 52)
        .background(KColor.canvasRaised).overlay(alignment: .bottom) { Rectangle().fill(KColor.line).frame(height: 1) }
    }

    @ViewBuilder private var content: some View {
        switch model.step {
        case 0: welcome
        case 1: access
        case 2...3: practice
        default: done
        }
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            QwixitMark(size: 72)
            Text("Fix selected text. Right where it is.").onboardingTitle(32)
            Text("Qwixit’s main move works in any app: select text, then press Option + Command + X.")
                .onboardingBody().frame(maxWidth: 570).multilineTextAlignment(.center)
            welcomeCard("Qwixit", "⌥⌘X", "Fix typos, grammar, and awkward wording without leaving the app you’re in.", KColor.violet)
                .frame(width: 430)
        }.padding(.top, 20)
    }

    private func welcomeCard(_ title: String, _ shortcut: String, _ body: String, _ accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack { Text(title).font(.system(size: 15, weight: .semibold)); Spacer(); SmallKeycap(shortcut) }
            Text(body).font(.system(size: 12.5)).foregroundStyle(KColor.secondary).lineSpacing(3)
        }
        .padding(.vertical, 16).padding(.horizontal, 20)
        .frame(maxWidth: .infinity, minHeight: 116, maxHeight: 116, alignment: .topLeading)
        .qwixitPanel().overlay(alignment: .topLeading) { Capsule().fill(accent).frame(width: 3, height: 22).padding(.top, 20) }
    }

    private var access: some View {
        ZStack {
            if model.isRequestingAccessibility {
                gettingAccess
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                noAccess
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.16) : .timingCurve(0.2, 0.9, 0.3, 1, duration: 0.28),
            value: model.isRequestingAccessibility
        )
    }

    private var noAccess: some View {
        VStack(spacing: 18) {
            accessIcon(systemName: "lock.fill", active: false)
            Text("Qwixit needs Accessibility access.").onboardingTitle(30)
            Text("This lets Qwixit read and replace selected text only when you use a shortcut.")
                .onboardingBody().multilineTextAlignment(.center).frame(maxWidth: 500)
            Button { model.requestAccessibility() } label: {
                HStack(spacing: 9) {
                    Text("Allow access")
                    Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .black))
                }
            }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityHint("Opens Accessibility settings in System Settings")
        }
        .padding(.top, 54)
    }

    private var gettingAccess: some View {
        VStack(spacing: 18) {
            accessIcon(systemName: "lock.open.fill", active: true)
            Text("Finish in System Settings.").onboardingTitle(30)
            Text("Turn on Qwixit under Accessibility. We’ll continue automatically when access is ready.")
                .onboardingBody().multilineTextAlignment(.center).frame(maxWidth: 520)

            HStack(spacing: 13) {
                accessPathItem("gearshape.fill", "Privacy & Security")
                Image(systemName: "chevron.right")
                accessPathItem("accessibility", "Accessibility")
                Image(systemName: "chevron.right")
                accessPathItem("switch.2", "Qwixit on")
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(KColor.secondary)
            .padding(.horizontal, 18)
            .frame(height: 46)
            .background(KColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(KColor.line) }

            HStack(spacing: 9) {
                ProgressView().controlSize(.small).tint(KColor.violet)
                Text("Waiting for access…")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(KColor.ink)
                Button { model.requestAccessibility() } label: {
                    HStack(spacing: 7) {
                        Text("Open System Settings again")
                        Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .bold))
                    }
                }
                    .buttonStyle(SubtleButtonStyle())
            }
        }
        .padding(.top, 38)
    }

    private func accessIcon(systemName: String, active: Bool) -> some View {
        ZStack {
            if active {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(KColor.violet.opacity(0.28), lineWidth: 2)
                    .frame(width: 72, height: 72)
                    .scaleEffect(accessPulse ? 1.28 : 0.94)
                    .opacity(accessPulse ? 0 : 1)
            }
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(KColor.violet.opacity(active ? 0.14 : 0.09))
            Image(systemName: systemName)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(KColor.violet)
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

    private func accessPathItem(_ systemName: String, _ title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemName).foregroundStyle(KColor.violet)
            Text(title)
        }
        .fixedSize()
    }

    private var practice: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 17) {
                HStack(spacing: 8) {
                    Capsule().fill(stepAccent).frame(width: 3, height: 14)
                    Text("\(practiceName) · \(model.step - 1) of 2").font(.system(size: 12, weight: .medium)).foregroundStyle(KColor.secondary)
                }
                Text(practiceTitle).onboardingTitle(27).multilineTextAlignment(.leading)
                Text(practiceSubtitle).onboardingBody()
                DemoKeyRow(step: model.step, accent: stepAccent, activeCount: demoKeys, optionDown: model.optionDown, commandDown: model.commandDown)
                    .opacity([.idle, .palette].contains(model.phase) ? 1 : 0.4)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(checklist.indices, id: \.self) { checklistRow($0, checklist[$0]) }
                }
                Spacer()
            }
            .padding(.top, 34).padding(.leading, 28).padding(.trailing, 22).frame(width: 282, alignment: .leading)
            practiceStage.padding(14).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var practiceStage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(KColor.line.opacity(0.38))
            MockAppWindow(title: mockWindowTitle) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(displayedPracticeText)
                        .font(.system(size: 21, weight: .semibold, design: .rounded)).lineSpacing(5).padding(7)
                        .background(model.phase == .done ? .clear : KColor.violet.opacity(0.16)).clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .frame(maxWidth: 440, maxHeight: 320)
            .padding(28)

            if (2...3).contains(model.step), let feedbackPhase {
                FeedbackPill(
                    phase: feedbackPhase,
                    reduceMotion: reduceMotion,
                    onClose: {}
                )
                .id(model.phase == .done)
                .allowsHitTesting(false)
                .offset(x: 76, y: 38)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            if model.phase == .palette { OnboardingPaletteSurface(model: model) }
        }
    }

    private func checklistRow(_ index: Int, _ label: String) -> some View {
        let complete = completedChecklistRows > index
        let current = completedChecklistRows == index
        return HStack(spacing: 9) {
            ZStack {
                Circle().fill(complete ? KColor.success : current ? stepAccent : .clear)
                Circle().stroke(current || complete ? .clear : KColor.line)
                Text(complete ? "✓" : "\(index + 1)").font(.system(size: 10, weight: .semibold)).foregroundStyle(complete || current ? .white : KColor.secondary)
            }.frame(width: 22, height: 22)
            Text(label).font(.system(size: 12.5, weight: current ? .semibold : .regular)).foregroundStyle(complete ? KColor.secondary : KColor.ink)
        }
    }

    private var done: some View {
        VStack(spacing: 15) {
            QwixitFaceView(face: .ready, size: 22, reduceMotion: reduceMotion, color: KColor.violet)
            Text("You're all set.").onboardingTitle(32)
            Text("Two ways to use Qwixit in any app.").onboardingBody()
            VStack(spacing: 0) {
                cheatRow("⌥⌘X", "Fix", "Correct selected text in place."); Divider().padding(.leading, 150)
                cheatRow("⌥⌘X ×2", "Choose", "Rewrite, translate, or change tone.")
            }.frame(width: 520).qwixitPanel()
            HStack(spacing: 12) {
                HStack(spacing: 8) { Image(systemName: "wifi"); QwixitMark(size: 16, style: .light); Text("9:41") }.font(.system(size: 11, weight: .medium)).foregroundStyle(.white).padding(.horizontal, 12).frame(height: 30).background(KColor.ink).clipShape(Capsule())
                Text("Qwixit lives in your menu bar — settings and usage are there.").font(.system(size: 12.5)).foregroundStyle(KColor.secondary)
            }
        }.padding(.top, 14)
    }

    private func cheatRow(_ keys: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 0) { HStack { SmallKeycap(keys); Spacer() }.frame(width: 132); VStack(alignment: .leading, spacing: 2) { Text(title).font(.system(size: 14, weight: .semibold)); Text(detail).font(.system(size: 12.5)).foregroundStyle(KColor.secondary) }; Spacer() }.padding(.horizontal, 18).frame(height: 58)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            ZStack { RoundedRectangle(cornerRadius: 10).fill(KColor.violet.opacity(0.09)); QwixitFaceView(face: footerFace, size: 13, reduceMotion: reduceMotion, color: KColor.violet) }.frame(width: 54, height: 34)
            Text(guide).font(.system(size: 13.5, weight: .medium)).lineLimit(1)
            Spacer()
            if model.step > 0 { Button("Back") { model.goBack() }.buttonStyle(SubtleButtonStyle()) }
            if (2...3).contains(model.step), model.phase != .done { Button("Skip") { model.skipPractice() }.buttonStyle(SubtleButtonStyle()) }
            if model.canContinue {
                Button { model.step == 4 ? onFinish() : model.advance() } label: {
                    HStack(spacing: 9) {
                        Text(primaryTitle)
                        Image(systemName: "arrow.right").font(.system(size: 10, weight: .black))
                    }
                }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.return, modifiers: []).accessibilityLabel(primaryTitle)
            }
        }.padding(.horizontal, 20).frame(height: 60).background(KColor.canvasRaised).overlay(alignment: .top) { Rectangle().fill(KColor.line).frame(height: 1) }
    }

    private var primaryTitle: String { model.step == 0 ? "Get started" : model.step == 4 ? "Start using Qwixit" : "Continue" }
    private var footerFace: QwixitFace { model.phase == .done || model.step == 4 ? .ready : model.phase == .processing ? .scanning : .hello }
    private var practiceName: String { [2: "Fix", 3: "Choose"][model.step] ?? "" }
    private var practiceTitle: String { [2: "Fix it in place.", 3: "Choose what happens."][model.step] ?? "" }
    private var practiceSubtitle: String { [2: "One shortcut replaces the selected text.", 3: "Press twice, then pick an action."][model.step] ?? "" }
    private var stepAccent: Color { model.step == 3 ? KColor.magenta : KColor.violet }
    private var mockWindowTitle: String { [2: "Draft — Notes", 3: "Message — Slack"][model.step] ?? "" }
    private var displayedPracticeText: String { model.phase == .typing || model.phase == .done ? model.typed : model.originalText }
    private var checklist: [String] { model.step == 2 ? ["Text is selected", "Press ⌥⌘X", "Fixed text replaces it"] : ["Text is selected", "Press ⌥⌘X twice", "Pick an action — 1–6 or ↵", "Result replaces the text"] }
    private var completedChecklistRows: Int { model.phase == .done ? checklist.count : model.phase == .processing || model.phase == .typing ? max(2, checklist.count - 1) : model.phase == .palette ? 2 : 1 }
    private var feedbackPhase: AppPhase? {
        switch model.phase {
        case .processing, .typing: .processing
        case .done: .success
        case .idle, .palette: nil
        }
    }
    private var guide: String {
        switch (model.step, model.phase) {
        case (0, _): "Hi! Let's set up Qwixit — it takes about a minute."
        case (1, _): model.isRequestingAccessibility
            ? "Waiting for Qwixit to be enabled in System Settings."
            : "Allow access now, or continue and do it later."
        case (2, .processing): "Fixing…"
        case (2, .typing): "Replacing the text…"
        case (2, .done): "Fixed. That's the main move."
        case (2, _): "Press ⌥⌘X once."
        case (3, .palette): "Pick an action — 1–6 or ↵."
        case (3, .done): "Chosen and replaced."
        case (3, _): "Press ⌥⌘X twice."
        default: "Qwixit is ready in every app."
        }
    }

    private func runKeyDemo() async {
        demoKeys = 0
        guard (2...3).contains(model.step), !reduceMotion else { return }
        while !Task.isCancelled, !model.hasRealInput, model.phase == .idle {
            try? await Task.sleep(for: .milliseconds(900)); demoKeys = 1
            try? await Task.sleep(for: .milliseconds(220)); demoKeys = 2
            try? await Task.sleep(for: .milliseconds(220)); demoKeys = 3
            try? await Task.sleep(for: .milliseconds(160)); demoKeys = 0
            if model.step == 3 { try? await Task.sleep(for: .milliseconds(180)); demoKeys = 3; try? await Task.sleep(for: .milliseconds(160)); demoKeys = 0 }
        }
    }
}

private struct SmallKeycap: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
            .padding(.horizontal, 8)
            .frame(minWidth: 28, minHeight: 27)
            .background(KColor.surfaceHover, in: QwixitControlShape(cut: 5))
            .overlay { QwixitControlShape(cut: 5).stroke(KColor.ink.opacity(0.72), lineWidth: 1) }
            .shadow(color: KColor.ink.opacity(0.12), radius: 3, y: 2)
    }
}

private struct DemoKeyRow: View {
    let step: Int; let accent: Color; let activeCount: Int; let optionDown: Bool; let commandDown: Bool
    var body: some View {
        HStack(spacing: 7) {
            key("⌥", "option", optionDown || activeCount >= 1)
            key("⌘", "command", commandDown || activeCount >= 2)
            key("X", "qwixit", activeCount >= 3)
            if step == 3 {
                Text("×2")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .frame(height: 23)
                    .background(KColor.ink, in: QwixitControlShape(cut: 4))
                    .overlay { QwixitControlShape(cut: 4).stroke(accent, lineWidth: 1) }
                    .rotationEffect(.degrees(-3))
            }
        }
    }

    private func key(_ symbol: String, _ name: String, _ active: Bool) -> some View {
        VStack(spacing: 2) {
            Text(symbol).font(.system(size: 18, weight: .heavy))
            Text(name.uppercased())
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(active ? .white.opacity(0.76) : KColor.secondary)
        }
        .foregroundStyle(active ? .white : KColor.ink)
        .frame(width: 50, height: 46)
        .background {
            if active {
                QwixitControlShape(cut: 7).fill(KColor.cyan).offset(x: -2, y: 1)
                QwixitControlShape(cut: 7).fill(KColor.magenta).offset(x: 2, y: -1)
            }
            QwixitControlShape(cut: 7).fill(active ? accent : KColor.surface)
        }
        .overlay { QwixitControlShape(cut: 7).stroke(active ? KColor.ink.opacity(0.38) : KColor.line, lineWidth: 1) }
        .shadow(color: KColor.ink.opacity(active ? 0.20 : 0.09), radius: active ? 5 : 3, y: active ? 3 : 2)
        .offset(y: active ? 2 : 0)
        .animation(.snappy(duration: 0.16), value: active)
    }
}

private struct MockAppWindow<Content: View>: View {
    let title: String; let content: Content
    init(title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View { VStack(spacing: 0) { HStack(spacing: 5) { Circle().fill(.red.opacity(0.8)); Circle().fill(.yellow.opacity(0.8)); Circle().fill(.green.opacity(0.8)); Spacer(); Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(KColor.secondary); Spacer().frame(width: 31) }.padding(.horizontal, 9).frame(height: 26).background(KColor.canvasRaised); content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(22) }.background(KColor.surface).clipShape(RoundedRectangle(cornerRadius: 11)).overlay(RoundedRectangle(cornerRadius: 11).stroke(KColor.line)).shadow(color: .black.opacity(0.11), radius: 18, y: 8) }
}

private struct OnboardingPaletteSurface: View {
    @ObservedObject var model: OnboardingModel
    @StateObject private var viewModel = PaletteViewModel(registry: ActionRegistry(), detector: LanguageDetector())
    @State private var syncedSelection = 0

    var body: some View {
        PaletteView(viewModel: viewModel, onClose: { _ = model.escapeOverlay() })
            .frame(width: 500, height: 260)
            .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
            .onAppear {
                viewModel.open(capture: PaletteCapture(
                    element: nil,
                    text: model.originalText,
                    range: nil,
                    bounds: nil,
                    fallbackPoint: .zero
                ))
                viewModel.onRun = { action in
                    let choice: OnboardingChoice
                    switch action.id {
                    case "slack": choice = .slack
                    case "formal": choice = .formal
                    default:
                        choice = switch action.language {
                        case "pl": .polish
                        case "de": .german
                        case "en": .english
                        default: .ukrainian
                        }
                    }
                    model.chooseAction(choice)
                }
            }
            .onChange(of: model.selectionIndex) { _, newValue in
                viewModel.move(newValue - syncedSelection)
                syncedSelection = newValue
            }
    }
}

private extension View {
    func onboardingTitle(_ size: CGFloat) -> some View { font(.system(size: size, weight: .heavy, design: .rounded)).tracking(size >= 30 ? -0.8 : -0.6).multilineTextAlignment(.center) }
    func onboardingBody() -> some View { font(.system(size: 14)).lineSpacing(7).foregroundStyle(KColor.secondary) }
}

#Preview("Onboarding · Welcome") { OnboardingView(model: OnboardingModel(accessibility: PreviewAccessibility()), onFinish: {}) }
#Preview("Onboarding · Access") { OnboardingView(model: OnboardingModel(accessibility: PreviewAccessibility(), initialStep: 1), onFinish: {}) }
#Preview("Onboarding · Fix idle") { OnboardingView(model: OnboardingModel(accessibility: PreviewAccessibility(), initialStep: 2), onFinish: {}) }
#Preview("Onboarding · Fix processing") { OnboardingView(model: OnboardingModel(accessibility: PreviewAccessibility(), initialStep: 2, initialPhase: .processing), onFinish: {}) }
#Preview("Onboarding · Choose palette") { OnboardingView(model: OnboardingModel(accessibility: PreviewAccessibility(), initialStep: 3, initialPhase: .palette), onFinish: {}) }
#Preview("Onboarding · Done") { OnboardingView(model: OnboardingModel(accessibility: PreviewAccessibility(), initialStep: 4), onFinish: {}) }

private final class PreviewAccessibility: AccessibilityServicing {
    var isTrusted = false
    func requestPermission() {}
    func selectedText() async -> String? { nil }
    func selectionBounds() -> CGRect? { nil }
    func fallbackPoint() -> CGPoint { .zero }
    func replaceSelection(_ originalText: String, with replacement: String) async -> Bool { true }
}
