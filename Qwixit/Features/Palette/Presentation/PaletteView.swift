import SwiftUI

struct PaletteView: View {
    @ObservedObject var viewModel: PaletteViewModel
    let onClose: () -> Void
    @FocusState private var searchFocused: Bool

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
        .background(KColor.surface)
        .foregroundStyle(text)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(KColor.line, lineWidth: 1.25))
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
            Text(viewModel.contextLabel)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(muted)
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(KColor.canvasRaised)
        .onAppear { searchFocused = true }
        .onChange(of: viewModel.wordCount) { _, _ in searchFocused = true }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if let refinement = viewModel.refinement {
                        refineContent(refinement)
                    } else {
                        ForEach(viewModel.groups) { group in
                            groupHeader(group.title)
                            ForEach(group.actions) { action in
                                let index = viewModel.index(of: action, in: group)
                                if action.id == "translate" {
                                    translationRow(startIndex: index)
                                } else {
                                    actionRow(action, index: index)
                                }
                            }
                        }
                        if viewModel.visibleActions.isEmpty {
                            Text("↵  Run as custom instruction")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(KColor.ink)
                                .padding(16)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
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

    private func actionRow(_ action: PaletteAction, index: Int) -> some View {
        Button { viewModel.runAction(action) } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 1).fill(accent(action)).frame(width: 3, height: 16)
                Text(action.name)
                    .font(.system(size: 12, weight: .bold, design: .monospaced)).tracking(0.25)
                Text(action.hint).font(.system(size: 11, design: .monospaced)).foregroundStyle(muted).lineLimit(1)
                Spacer()
                Text(action.mode.rawValue.capitalized)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(index == viewModel.selectedIndex ? accent(action) : muted)
                if index < 9 { keycap("\(index + 1)") }
            }
            .padding(.horizontal, 9)
            .frame(height: 36)
            .background(index == viewModel.selectedIndex ? accent(action).opacity(0.13) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(index == viewModel.selectedIndex ? accent(action).opacity(0.72) : .clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .id(index)
    }

    private func translationRow(startIndex: Int) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 1).fill(KColor.cyan).frame(width: 3, height: 16)
            Text("Translate")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .tracking(0.25)
            Text("\(viewModel.detectedLanguage?.code.uppercased() ?? "Auto") →")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(muted)
            Spacer()
            ForEach(Array(viewModel.languages.enumerated()), id: \.element.id) { languageIndex, language in
                let index = startIndex + languageIndex
                Button { viewModel.runLanguage(at: languageIndex) } label: {
                    HStack(spacing: 5) {
                        Text(language.code)
                        keycap("\(index + 1)")
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(index == viewModel.selectedIndex ? KColor.ink : KColor.cyan)
                    .padding(.leading, 9)
                    .padding(.trailing, 4)
                    .frame(height: 28)
                    .background(index == viewModel.selectedIndex ? KColor.cyan.opacity(0.18) : KColor.surface)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(KColor.cyan.opacity(0.75), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Translate to \(language.name)")
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 42)
        .id(startIndex)
    }

    private var placeholder: String {
        if viewModel.isRefining { return "Anything else? (optional)" }
        return "Action or instruction…"
    }

    @ViewBuilder
    private func refineContent(_ refinement: PaletteRefinement) -> some View {
        let color = accent(refinement.action)
        groupHeader("\(refinement.action.name) · Quick questions")
        if refinement.isLoading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(color)
                Text("Qwixing…  ↵ skips")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(muted)
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
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
                                .foregroundStyle(chosen ? text : muted)
                                .padding(.horizontal, 8)
                                .frame(height: 24)
                                .background(chosen ? color.opacity(0.16) : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(chosen ? color.opacity(0.72) : KColor.line, lineWidth: 1)
                                }
                            }
                            .buttonStyle(.plain)
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

    private var footer: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 2)
                .fill((viewModel.refinement?.action ?? viewModel.selectedAction).map(accent) ?? KColor.line)
                .frame(width: 8, height: 8)
            Text(viewModel.footerText).lineLimit(1)
            Spacer()
            Text("↑↓ · ↵ · Esc")
        }
        .font(.system(size: 9, weight: .bold, design: .monospaced))
        .foregroundStyle(muted)
        .padding(.horizontal, 16)
        .frame(height: 38)
        .background(KColor.canvasRaised)
    }

    private func keycap(_ value: String) -> some View {
        Text(value).font(.system(size: 9, weight: .bold, design: .monospaced))
            .frame(width: 22, height: 20).overlay(RoundedRectangle(cornerRadius: 5).stroke(KColor.line))
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
}
