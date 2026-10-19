import SwiftUI

struct PaletteView: View {
    @ObservedObject var viewModel: PaletteViewModel
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let text = KColor.ink
    private let muted = KColor.secondary

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(KColor.popupDivider).frame(height: 1)
            list
            Rectangle().fill(KColor.popupDivider).frame(height: 1)
            footer
        }
        .frame(width: 360)
        .foregroundStyle(text)
        .tokiriPopupPanel()
        .qwixitTheme()
    }

    private var header: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(KColor.violet)
                .frame(width: 1.5, height: 18)

            TextField(
                "",
                text: $viewModel.query,
                prompt: Text(placeholder).foregroundColor(KColor.popupMuted)
            )
            .textFieldStyle(.plain)
            .font(.system(size: 14, weight: .medium, design: .monospaced))
            .foregroundStyle(text)
            .focused($searchFocused)
            .layoutPriority(1)

            Text(viewModel.contextLabel)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(KColor.popupMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .fixedSize(horizontal: false, vertical: false)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .onAppear { searchFocused = true }
        .onChange(of: viewModel.wordCount) { _, _ in searchFocused = true }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if let refinement = viewModel.refinement {
                        refineContent(refinement)
                    } else if viewModel.choices.isEmpty {
                        Text("No matching action")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(muted)
                            .frame(maxWidth: .infinity, minHeight: 41, alignment: .leading)
                    } else {
                        ForEach(Array(viewModel.translationChoices.enumerated()), id: \.element.id) { index, choice in
                            choiceRow(choice, at: index)
                        }

                        if viewModel.showsRewriteDivider {
                            Rectangle()
                                .fill(KColor.popupDivider)
                                .frame(height: 1)
                                .padding(.horizontal, 4)
                        }

                        let offset = viewModel.translationChoices.count
                        ForEach(Array(viewModel.rewriteChoices.enumerated()), id: \.element.id) { index, choice in
                            choiceRow(choice, at: offset + index)
                        }
                    }
                }
                .padding(10)
            }
            .frame(maxHeight: 380)
            .onChange(of: viewModel.selectedIndex) { _, value in proxy.scrollTo(value, anchor: .center) }
            .onChange(of: viewModel.refinement?.focusedQuestion) { _, value in
                if let value { proxy.scrollTo(value, anchor: .center) }
            }
        }
    }

    @ViewBuilder
    private func choiceRow(_ choice: PaletteChoice, at index: Int) -> some View {
        let selected = index == viewModel.selectedIndex
        let row = HStack(spacing: 10) {
            Text(choice.name)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(selected ? Color.white : text)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Text(selected ? "↵" : "\(index + 1)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(selected ? Color.white : KColor.popupMuted)
                .fixedSize()
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, alignment: .leading)

        if selected {
            Button { viewModel.runChoice(at: index) } label: { row }
                .buttonStyle(TokiriUI.PopupSelectedButton())
                .accessibilityLabel("\(choice.name), Return")
                .accessibilityAddTraits(.isSelected)
                .id(index)
        } else {
            Button { viewModel.runChoice(at: index) } label: { row }
                .frame(height: 41)
                .buttonStyle(TokiriUI.PopupPlainRowButton())
                .accessibilityLabel("\(choice.name), shortcut \(index + 1)")
                .id(index)
        }
    }

    private var placeholder: String {
        viewModel.isRefining ? "Answer questions…" : "Search…"
    }

    @ViewBuilder
    private func refineContent(_ refinement: PaletteRefinement) -> some View {
        Text("\(refinement.action.name) · Quick questions")
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(KColor.popupMuted)
            .padding(.horizontal, 4)
            .padding(.bottom, 2)

        if refinement.isLoading {
            refinementStatusChip
        } else {
            ForEach(Array(refinement.questions.enumerated()), id: \.offset) { questionIndex, question in
                let focused = questionIndex == refinement.focusedQuestion
                VStack(alignment: .leading, spacing: 6) {
                    Text(question.question)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(focused ? text : muted)
                    HStack(spacing: 5) {
                        ForEach(Array(question.options.enumerated()), id: \.offset) { optionIndex, option in
                            let chosen = refinement.answers[questionIndex] == optionIndex
                            Button {
                                viewModel.chooseAnswer(question: questionIndex, option: optionIndex)
                            } label: {
                                HStack(spacing: 5) {
                                    if focused {
                                        Text("\(optionIndex + 1)")
                                            .foregroundStyle(chosen ? KColor.violet : muted)
                                    }
                                    Text(option).lineLimit(1)
                                }
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                            }
                            .buttonStyle(CompactButtonStyle(accent: KColor.violet, isSelected: chosen))
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(focused ? KColor.violet.opacity(0.06) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .id(questionIndex)
            }
        }
    }

    private var refinementStatusChip: some View {
        FeedbackPill(
            phase: .processing,
            reduceMotion: reduceMotion,
            onClose: {}
        )
        .id("palette-refinement-processing")
        .allowsHitTesting(false)
        .accessibilityLabel("Sharpening. Press Return to skip questions.")
    }

    private var footer: some View {
        Text(viewModel.footerText)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(KColor.popupMuted)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 32)
    }
}
