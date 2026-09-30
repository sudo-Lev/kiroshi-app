import SwiftUI

struct PaletteView: View {
    @ObservedObject var viewModel: PaletteViewModel
    let onClose: () -> Void
    @FocusState private var searchFocused: Bool

    private let top = Color(red: 0.11, green: 0.09, blue: 0.16)
    private let bottom = Color(red: 0.071, green: 0.055, blue: 0.106)
    private let text = Color(red: 0.933, green: 0.918, blue: 0.965)
    private let muted = Color(red: 0.557, green: 0.533, blue: 0.6)

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.1))
            list
            Divider().overlay(Color.white.opacity(0.1))
            footer
        }
        .background(LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing))
        .foregroundStyle(text)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.1)))
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 12) {
            QwixitMark(size: 27, style: .dark).frame(width: 28)
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
                            Text("↵  RUN AS CUSTOM INSTRUCTION")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
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
            .tracking(1.8)
            .foregroundStyle(Color(red: 0.447, green: 0.427, blue: 0.502))
            .padding(.horizontal, 10)
            .padding(.top, 7)
            .padding(.bottom, 3)
    }

    private func actionRow(_ action: PaletteAction, index: Int) -> some View {
        Button { viewModel.runAction(action) } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 1).fill(accent(action)).frame(width: 3, height: 16)
                Text(action.name.uppercased())
                    .font(.system(size: 12, weight: .bold, design: .monospaced)).tracking(0.8)
                Text(action.hint).font(.system(size: 11, design: .monospaced)).foregroundStyle(muted).lineLimit(1)
                Spacer()
                Text(action.mode.rawValue)
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
            Text("TRANSLATE")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .tracking(0.8)
            Text("\(viewModel.detectedLanguage?.code.uppercased() ?? "AUTO") →")
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
                    .foregroundStyle(index == viewModel.selectedIndex ? Color.black : KColor.cyan)
                    .padding(.leading, 9)
                    .padding(.trailing, 4)
                    .frame(height: 28)
                    .background(index == viewModel.selectedIndex ? KColor.cyan : KColor.cyan.opacity(0.10))
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
        groupHeader("\(refinement.action.name.uppercased()) · QUICK QUESTIONS")
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
                                        .stroke(chosen ? color.opacity(0.72) : Color.white.opacity(0.12), lineWidth: 1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(focused ? Color.white.opacity(0.04) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .id(questionIndex)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 2)
                .fill((viewModel.refinement?.action ?? viewModel.selectedAction).map(accent) ?? .white)
                .frame(width: 8, height: 8)
            Text(viewModel.footerText).lineLimit(1)
            Spacer()
            Text("↑↓ · ↵ · ESC")
        }
        .font(.system(size: 9, weight: .bold, design: .monospaced))
        .foregroundStyle(muted)
        .padding(.horizontal, 16)
        .frame(height: 38)
    }

    private func keycap(_ value: String) -> some View {
        Text(value).font(.system(size: 9, weight: .bold, design: .monospaced))
            .frame(width: 22, height: 20).overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.18)))
    }

    private func accent(_ action: PaletteAction) -> Color {
        if action.id == "translate" { return KColor.cyan }
        if action.refines { return Color(red: 0.655, green: 0.482, blue: 1) }
        return switch action.mode {
        case .replace: Color(red: 0.239, green: 0.961, blue: 0.541)
        case .insert: Color(red: 0.655, green: 0.482, blue: 1)
        case .panel: KColor.magenta
        }
    }
}
