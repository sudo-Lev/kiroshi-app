import SwiftUI

struct PaletteView: View {
    @ObservedObject var viewModel: PaletteViewModel
    let onClose: () -> Void
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let text = KColor.ink
    private let muted = KColor.secondary

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(KColor.line)
            list
            Divider().overlay(KColor.line)
            footer
        }
        .foregroundStyle(text)
        .qwixitPanel()
        .qwixitTheme()
    }

    private var header: some View {
        HStack(spacing: 12) {
            QwixitMark(size: 27, style: .automatic).frame(width: 28)
            TextField(placeholder, text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(text)
                .focused($searchFocused)
                .layoutPriority(1)
            Text(viewModel.contextLabel)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(muted)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(KColor.canvasRaised)
        .onAppear { searchFocused = true }
        .onChange(of: viewModel.wordCount) { _, _ in searchFocused = true }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let refinement = viewModel.refinement {
                        refineContent(refinement)
                    } else {
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible())],
                            spacing: 4
                        ) {
                            ForEach(viewModel.groups) { group in
                                ForEach(group.actions) { action in
                                    let index = viewModel.index(of: action, in: group)
                                    if action.id == "translate" {
                                        ForEach(Array(viewModel.languages.enumerated()), id: \.element.id) { languageIndex, language in
                                            translationCard(
                                                language,
                                                languageIndex: languageIndex,
                                                index: index + languageIndex
                                            )
                                        }
                                    } else {
                                        actionCard(action, index: index)
                                    }
                                }
                            }
                        }
                        if viewModel.visibleActions.isEmpty {
                            HStack {
                                Text("No action matches “\(viewModel.query)”")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(muted)
                                    .lineLimit(2)
                                Spacer()
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, minHeight: 62)
                            .background(KColor.surfaceHover, in: QwixitControlShape(cut: 8))
                            .overlay(QwixitControlShape(cut: 8).stroke(KColor.line))
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 380)
            .onChange(of: viewModel.selectedIndex) { _, value in proxy.scrollTo(value, anchor: .center) }
            .onChange(of: viewModel.refinement?.focusedQuestion) { _, value in
                if let value { proxy.scrollTo(value, anchor: .center) }
            }
        }
    }

    private func groupHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(0.45)
            .foregroundStyle(KColor.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 7)
            .padding(.bottom, 3)
    }

    private func actionCard(_ action: PaletteAction, index: Int) -> some View {
        Button { viewModel.runAction(action) } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(action.name)
                        .font(.system(size: 13, weight: .bold))
                    Text(action.hint)
                        .font(.system(size: 10.5))
                        .foregroundStyle(muted)
                        .lineLimit(1)
                }
                Spacer()
                if index < 9 { keycap("\(index + 1)") }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
        }
        .buttonStyle(QwixitSemanticCardButtonStyle(
            accent: cardAccent(for: action),
            isSelected: index == viewModel.selectedIndex,
            cut: 5
        ))
        .id(index)
        .accessibilityLabel("\(action.name), \(action.hint), shortcut \(index + 1)")
    }

    private func translationCard(
        _ language: TranslationLanguage,
        languageIndex: Int,
        index: Int
    ) -> some View {
        Button { viewModel.runLanguage(at: languageIndex) } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(language.name)
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)
                    Text("Translate · \(viewModel.detectedLanguage?.code.uppercased() ?? "AUTO") → \(language.code)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(muted)
                        .lineLimit(1)
                }
                Spacer()
                keycap("\(index + 1)")
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
        }
        .buttonStyle(QwixitSemanticCardButtonStyle(
            accent: .language(language.id),
            isSelected: index == viewModel.selectedIndex,
            cut: 5
        ))
        .id(index)
        .help("Translate to \(language.name)")
        .accessibilityLabel("Translate to \(language.name), shortcut \(index + 1)")
    }

    private var placeholder: String {
        if viewModel.isRefining { return "Pick answers below · ↵ runs" }
        return "Search actions…"
    }

    @ViewBuilder
    private func refineContent(_ refinement: PaletteRefinement) -> some View {
        let color = accent(refinement.action)
        groupHeader("\(refinement.action.name) · Quick questions")
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
                            Button { viewModel.chooseAnswer(question: questionIndex, option: optionIndex) } label: {
                                HStack(spacing: 5) {
                                    if focused {
                                        Text("\(optionIndex + 1)").foregroundStyle(chosen ? color : muted)
                                    }
                                    Text(option).lineLimit(1)
                                }
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                            }
                            .buttonStyle(CompactButtonStyle(accent: color, isSelected: chosen))
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(focused ? color.opacity(0.06) : .clear)
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
        .accessibilityLabel("Qwixing. Press Return to skip questions.")
    }

    private var footer: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 2)
                .fill((viewModel.refinement?.action ?? viewModel.selectedAction).map(accent) ?? KColor.line)
                .frame(width: 8, height: 8)
            Text(viewModel.footerText).lineLimit(1).truncationMode(.tail)
            Spacer()
            Text("↑↓ · ↵ · Esc").fixedSize(horizontal: true, vertical: false)
        }
        .font(.system(size: 9, weight: .bold, design: .monospaced))
        .foregroundStyle(muted)
        .padding(.horizontal, 16)
        .frame(height: 34)
        .background(KColor.canvasRaised)
    }

    private func keycap(_ value: String) -> some View {
        Text(value).font(.system(size: 9, weight: .bold, design: .monospaced))
            .frame(width: 20, height: 20)
            .background(KColor.surface, in: QwixitControlShape(cut: 4))
            .overlay(QwixitControlShape(cut: 4).stroke(KColor.line))
    }

    private func accent(_ action: PaletteAction) -> Color {
        if action.id == "translate" { return KColor.cyan }
        if action.refines { return KColor.violet }
        return switch action.mode {
        case .replace: KColor.success
        case .insert: KColor.violet
        case .panel: KColor.magenta
        }
    }

    private func cardAccent(for action: PaletteAction) -> QwixitCardAccent {
        switch action.id {
        case "slack": .slack
        case "formal": .formal
        default: .single(accent(action))
        }
    }
}
