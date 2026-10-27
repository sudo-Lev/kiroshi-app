import SwiftUI

private struct OnboardingPracticePresentation {
    let title: String
    let subtitle: String
    let windowTitle: String
    let shortcut: HotkeyBinding
    let accent: Color
    let checklist: [String]
}

struct OnboardingPracticeStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let shortcuts: OnboardingShortcuts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var demoKeys: OnboardingDemoKeys = []

    var body: some View {
        Group {
            if let presentation {
                practiceContent(presentation)
            }
        }
        .task(id: viewModel.step) { await runKeyDemo() }
    }

    @ViewBuilder
    private func practiceContent(_ presentation: OnboardingPracticePresentation) -> some View {
        let completedRows = completedChecklistRows(for: presentation.checklist.count)
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 17) {
                HStack(spacing: 8) {
                    Capsule().fill(presentation.accent).frame(width: 3, height: 14)
                    Text("\(viewModel.step.title) · \(viewModel.step.practiceOrdinal ?? 0) of \(OnboardingStep.practiceCount)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(HotkeyGoColor.secondary)
                }
                Text(presentation.title).onboardingTitle(27).multilineTextAlignment(.leading)
                Text(presentation.subtitle).onboardingBody()
                OnboardingDemoKeyRow(
                    binding: presentation.shortcut,
                    accent: presentation.accent,
                    activeKeys: demoKeys,
                    controlDown: viewModel.controlDown,
                    optionDown: viewModel.optionDown,
                    shiftDown: viewModel.shiftDown,
                    commandDown: viewModel.commandDown,
                    reduceMotion: reduceMotion
                )
                .opacity([.idle, .palette].contains(viewModel.phase) ? 1 : 0.4)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(presentation.checklist.indices, id: \.self) {
                        checklistRow(
                            $0,
                            presentation.checklist[$0],
                            accent: presentation.accent,
                            completedRows: completedRows
                        )
                    }
                }
                Spacer()
            }
            .padding(.top, 34).padding(.leading, 28).padding(.trailing, 22).frame(width: 282, alignment: .leading)
            practiceStage(presentation).padding(14).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func practiceStage(_ presentation: OnboardingPracticePresentation) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(HotkeyGoColor.line.opacity(0.38))
            OnboardingMockAppWindow(title: presentation.windowTitle) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(displayedPracticeText)
                        .font(.system(size: 21, weight: .semibold, design: .rounded)).lineSpacing(5).padding(7)
                        .background(viewModel.phase == .done && !viewModel.typed.isEmpty ? .clear : HotkeyGoColor.violet.opacity(0.16)).clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .frame(maxWidth: 440, maxHeight: 320)
            .padding(28)

            if [.fix, .actions].contains(viewModel.step), let feedbackPhase {
                FeedbackPill(
                    phase: feedbackPhase,
                    reduceMotion: reduceMotion,
                    onClose: {}
                )
                .id(viewModel.phase == .done)
                .allowsHitTesting(false)
                .offset(x: 76, y: 38)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            if viewModel.phase == .palette {
                OnboardingActionPaletteSurface(viewModel: viewModel)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
            }
            if viewModel.step == .peek, [.peekChoice, .peekProcessing, .peek].contains(viewModel.phase) {
                OnboardingPeekSurface(
                    viewModel: viewModel,
                    reduceMotion: reduceMotion,
                    onClose: { _ = viewModel.escapeOverlay() }
                )
                    .offset(x: 48, y: 64)
                    // Scaling this popup can leave its SwiftUI text layers invisible after the transition.
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.16) : .snappy(duration: 0.24), value: viewModel.phase)
    }

    private func checklistRow(_ index: Int, _ label: String, accent: Color, completedRows: Int) -> some View {
        let complete = completedRows > index
        let current = completedRows == index
        return HStack(spacing: 9) {
            ZStack {
                Circle().fill(complete ? HotkeyGoColor.success : current ? accent : .clear)
                Circle().stroke(current || complete ? .clear : HotkeyGoColor.line)
                Text(complete ? "✓" : "\(index + 1)").font(.system(size: 10, weight: .semibold)).foregroundStyle(complete || current ? .white : HotkeyGoColor.secondary)
            }.frame(width: 22, height: 22)
            Text(label).font(.system(size: 12.5, weight: current ? .semibold : .regular)).foregroundStyle(complete ? HotkeyGoColor.secondary : HotkeyGoColor.ink)
        }
    }

    private var presentation: OnboardingPracticePresentation? {
        switch viewModel.step {
        case .fix:
            OnboardingPracticePresentation(
                title: "Fix it in place.",
                subtitle: "One shortcut replaces the selected text.",
                windowTitle: "Draft — Notes",
                shortcut: shortcuts.fix,
                accent: HotkeyGoColor.violet,
                checklist: ["Text is selected", "Press \(shortcuts.fix.displayString)", "Fixed text replaces it"]
            )
        case .actions:
            OnboardingPracticePresentation(
                title: "Choose what happens.",
                subtitle: "Open Actions, then choose what happens.",
                windowTitle: "Message — Slack",
                shortcut: shortcuts.actions,
                accent: HotkeyGoColor.magenta,
                checklist: ["Text is selected", "Press \(shortcuts.actions.displayString)", "Pick an action — 1–4 or ↵", "Result replaces the text"]
            )
        case .peek:
            OnboardingPracticePresentation(
                title: "Read without changing a thing.",
                subtitle: "Peek translates selected text in a read-only panel.",
                windowTitle: "Message — Mail",
                shortcut: shortcuts.peek,
                accent: HotkeyGoColor.cyan,
                checklist: ["Text is selected", "Choose a language", "Read the translation; source stays put"]
            )
        case .welcome, .accessibility, .complete:
            nil
        }
    }

    private var displayedPracticeText: String {
        viewModel.step == .peek || viewModel.typed.isEmpty ? viewModel.originalText : viewModel.typed
    }

    private func completedChecklistRows(for count: Int) -> Int {
        switch viewModel.phase {
        case .done, .peek, .peekDone: count
        case .skipped: 1
        case .processing, .typing, .peekProcessing: max(2, count - 1)
        case .peekChoice, .palette: 2
        case .idle: 1
        }
    }

    private var feedbackPhase: AppPhase? {
        switch viewModel.phase {
        case .processing, .typing: .processing
        case .done: .success
        case .idle, .palette, .peekChoice, .peek, .peekDone, .skipped, .peekProcessing: nil
        }
    }


    private func runKeyDemo() async {
        demoKeys = []
        guard viewModel.step.isPractice, !reduceMotion else { return }
        while !Task.isCancelled, !viewModel.hasRealInput, viewModel.phase == .idle {
            do { try await Task.sleep(for: .milliseconds(900)) } catch { return }
            demoKeys = [.modifiers]
            do { try await Task.sleep(for: .milliseconds(220)) } catch { return }
            demoKeys = [.modifiers, .action]
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            demoKeys = [.modifiers]
            do { try await Task.sleep(for: .milliseconds(140)) } catch { return }
            demoKeys = []
        }
    }
}
