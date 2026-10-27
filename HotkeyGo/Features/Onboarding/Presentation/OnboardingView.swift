import SwiftUI

struct OnboardingView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let shortcuts: OnboardingShortcuts
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let steps = OnboardingStep.allCases

    init(
        viewModel: OnboardingViewModel,
        shortcuts: OnboardingShortcuts = .standard,
        onFinish: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.shortcuts = shortcuts
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack { stepContent.id(viewModel.step) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
                .animation(
                    reduceMotion ? .easeOut(duration: 0.16) : .timingCurve(0.2, 0.9, 0.3, 1, duration: 0.26),
                    value: viewModel.step
                )
            footer
        }
        .frame(width: 820, height: 640)
        .background(HotkeyGoColor.canvas)
        .foregroundStyle(HotkeyGoColor.ink)
        .hotkeygoTheme()
        .onAppear { viewModel.refreshAccessibility() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            HotkeyGoWordmark().frame(width: 144, height: 46)
            Spacer()
            HStack(spacing: 0) {
                ForEach(steps) { step in
                    Button {
                        viewModel.goBack(to: step)
                    } label: {
                        Text(step.precedes(viewModel.step) ? "✓ \(step.title)" : step.title)
                    }
                    .buttonStyle(CompactButtonStyle(
                        accent: step.precedes(viewModel.step) ? HotkeyGoColor.success : HotkeyGoColor.violet,
                        isSelected: step == viewModel.step,
                        prominent: step == viewModel.step
                    ))
                    .disabled(viewModel.step.precedes(step))
                    .accessibilityLabel("\(step.title), \(step == viewModel.step ? "current" : step.precedes(viewModel.step) ? "complete; go back" : "upcoming")")
                    if step != .complete { Rectangle().fill(HotkeyGoColor.line).frame(width: 8, height: 1) }
                }
            }
        }
        .padding(.leading, 42)
        .padding(.trailing, 22)
        .frame(height: 52)
        .background(HotkeyGoColor.canvasRaised)
        .overlay(alignment: .bottom) { Rectangle().fill(HotkeyGoColor.line).frame(height: 1) }
    }

    @ViewBuilder private var stepContent: some View {
        switch viewModel.step {
        case .welcome:
            OnboardingWelcomeStepView(shortcuts: shortcuts)
        case .accessibility:
            OnboardingAccessStepView(viewModel: viewModel)
        case .fix, .actions, .peek:
            OnboardingPracticeStepView(viewModel: viewModel, shortcuts: shortcuts)
        case .complete:
            OnboardingCompletionStepView(shortcuts: shortcuts)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(HotkeyGoColor.violet.opacity(0.09))
                HotkeyGoFaceView(face: footerFace, size: 13, reduceMotion: reduceMotion, color: HotkeyGoColor.violet)
            }
            .frame(width: 54, height: 34)
            Text(guide).font(.system(size: 13.5, weight: .medium)).lineLimit(1)
            Spacer()

            if viewModel.step != .welcome {
                Button("Back") { viewModel.goBack() }
                    .buttonStyle(SubtleButtonStyle())
            }
            if viewModel.step.isPractice, !viewModel.canContinue {
                Button("Skip") { viewModel.skipPractice() }
                    .buttonStyle(SubtleButtonStyle())
            }
            if viewModel.canContinue {
                Button(action: continueFlow) {
                    HStack(spacing: 9) {
                        Text(primaryTitle)
                        HotkeyGoUI.Icon(.arrowRight, size: 10)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.return, modifiers: [])
                .accessibilityLabel(primaryTitle)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 60)
        .background(HotkeyGoColor.canvasRaised)
        .overlay(alignment: .top) { Rectangle().fill(HotkeyGoColor.line).frame(height: 1) }
    }

    private var primaryTitle: String {
        switch viewModel.step {
        case .welcome: "Get started"
        case .accessibility where !viewModel.accessibilityGranted: "Do this later"
        case .complete: "Start using hotkeygo"
        case .accessibility, .fix, .actions, .peek: "Continue"
        }
    }

    private var footerFace: HotkeyGoFace {
        if viewModel.step == .complete ||
            (viewModel.step == .accessibility && viewModel.accessibilityGranted) ||
            [.done, .peek, .peekDone, .skipped].contains(viewModel.phase) {
            return .ready
        }
        if viewModel.phase == .processing || viewModel.phase == .peekProcessing {
            return .scanning
        }
        return .hello
    }

    private var guide: String {
        switch (viewModel.step, viewModel.phase) {
        case (.welcome, _): "Hi! Let's set up hotkeygo — it takes about a minute."
        case (.accessibility, _) where viewModel.accessibilityGranted: "ACCESS GRANTED · PRESS ENTER TO CONTINUE"
        case (.accessibility, _) where viewModel.isRequestingAccessibility: "Press Enter to continue later, or finish in System Settings."
        case (.accessibility, _): "Press Enter to continue later, or allow access."
        case (.fix, .skipped), (.actions, .skipped), (.peek, .skipped): "Skipped. Continue whenever you're ready."
        case (.fix, .processing): "Fixing…"
        case (.fix, .typing): "Replacing the text…"
        case (.fix, .done): "Fixed. That's the main move."
        case (.fix, _): "Press \(shortcuts.fix.displayString) once."
        case (.actions, .palette): "Pick an action — 1–4 or ↵."
        case (.actions, .done): "Chosen and replaced."
        case (.actions, _): "Press \(shortcuts.actions.displayString) to open Actions."
        case (.peek, .peekChoice): "Choose a language — 1–4 or ↵."
        case (.peek, .peekProcessing): "Translating the sample…"
        case (.peek, .peek): "Read it. Your original text is untouched."
        case (.peek, .peekDone): "Translation ready. Your original text is untouched."
        case (.peek, _): "Press \(shortcuts.peek.displayString) to preview the text."
        case (.complete, _): "hotkeygo is ready in every app."
        }
    }

    private func continueFlow() {
        if viewModel.step == .complete {
            onFinish()
        } else {
            viewModel.advance()
        }
    }
}

#Preview("Onboarding · Welcome") {
    OnboardingView(viewModel: OnboardingViewModel(accessibility: PreviewAccessibility()), onFinish: {})
}
#Preview("Onboarding · Access") {
    OnboardingView(viewModel: OnboardingViewModel(accessibility: PreviewAccessibility(), initialStep: .accessibility), onFinish: {})
}
#Preview("Onboarding · Access granted") {
    OnboardingView(viewModel: OnboardingViewModel(accessibility: PreviewAccessibility(isTrusted: true), initialStep: .accessibility), onFinish: {})
}
#Preview("Onboarding · Fix idle") {
    OnboardingView(viewModel: OnboardingViewModel(accessibility: PreviewAccessibility(), initialStep: .fix), onFinish: {})
}
#Preview("Onboarding · Fix processing") {
    OnboardingView(viewModel: OnboardingViewModel(accessibility: PreviewAccessibility(), initialStep: .fix, initialPhase: .processing), onFinish: {})
}
#Preview("Onboarding · Choose palette") {
    OnboardingView(viewModel: OnboardingViewModel(accessibility: PreviewAccessibility(), initialStep: .actions, initialPhase: .palette), onFinish: {})
}
#Preview("Onboarding · Peek loading") {
    OnboardingView(viewModel: OnboardingViewModel(accessibility: PreviewAccessibility(), initialStep: .peek, initialPhase: .peekProcessing), onFinish: {})
}
#Preview("Onboarding · Peek") {
    OnboardingView(viewModel: OnboardingViewModel(accessibility: PreviewAccessibility(), initialStep: .peek, initialPhase: .peek), onFinish: {})
}
#Preview("Onboarding · Done") {
    OnboardingView(viewModel: OnboardingViewModel(accessibility: PreviewAccessibility(), initialStep: .complete), onFinish: {})
}

private final class PreviewAccessibility: AccessibilityServicing {
    var isTrusted: Bool
    init(isTrusted: Bool = false) { self.isTrusted = isTrusted }
    func requestPermission() {}
    func selectedText() async -> String? { nil }
    func selectionBounds() -> CGRect? { nil }
    func fallbackPoint() -> CGPoint { .zero }
}
