import SwiftUI

struct OnboardingPeekSurface: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let reduceMotion: Bool
    let onClose: () -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            .frame(height: 48)

            Rectangle().fill(HotkeyGoColor.popupDivider).frame(height: 1)

            Group {
                switch viewModel.phase {
                case .peekChoice:
                    languageChoices
                case .peekProcessing:
                    processingContent
                case .peek:
                    resultContent
                default:
                    EmptyView()
                }
            }

            Rectangle().fill(HotkeyGoColor.popupDivider).frame(height: 1)
            footer
        }
        .frame(width: 360)
        .foregroundStyle(HotkeyGoColor.ink)
        .hotkeygoPopupPanel()
        .accessibilityElement(children: .contain)
        .onboardingEscape { onClose() }
    }

    @ViewBuilder private var header: some View {
        if viewModel.phase == .peekChoice {
            HStack(spacing: 10) {
                Rectangle().fill(HotkeyGoColor.violet).frame(width: 1.5, height: 18)
                TextField(
                    "",
                    text: $viewModel.peekQuery,
                    prompt: Text("Search…").foregroundColor(HotkeyGoColor.popupMuted)
                )
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(HotkeyGoColor.ink)
                .focused($searchFocused)
                .frame(minWidth: 72, maxWidth: .infinity, alignment: .leading)
                .layoutPriority(0)
                .onSubmit { viewModel.confirmSelection() }
                Text(viewModel.peekContextLabel)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(HotkeyGoColor.popupMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            }
            .padding(.horizontal, 16)
            .onAppear { searchFocused = true }
        } else {
            HStack(spacing: 10) {
                Text("\(viewModel.peekDetectedLanguageName) →")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(HotkeyGoColor.popupMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Button(viewModel.peekLanguage.name) { viewModel.cyclePeekLanguage() }
                    .buttonStyle(HotkeyGoUI.PopupSelectedButton(compact: true))
                    .help("Next language")
                    .accessibilityLabel("Target language: \(viewModel.peekLanguage.name). Switch to next language.")
                Text("\(viewModel.peekWordCount) words")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(HotkeyGoColor.popupMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Spacer(minLength: 0)
                Button(action: onClose) {
                    HotkeyGoUI.Icon(.close, size: 10)
                }
                .buttonStyle(HotkeyGoUI.IconButton(accent: HotkeyGoColor.popupMuted))
                .help("Close Peek preview")
                .accessibilityLabel("Close Peek preview")
            }
            .padding(.leading, 16)
            .padding(.trailing, 10)
        }
    }

    private var languageChoices: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 6) {
                    if viewModel.peekChoices.isEmpty {
                        Text("No language matches \"\(viewModel.peekQuery)\"")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(HotkeyGoColor.popupMuted)
                            .frame(maxWidth: .infinity, minHeight: 41, alignment: .leading)
                    } else {
                        ForEach(Array(viewModel.peekChoices.enumerated()), id: \.element.id) { index, language in
                            languageRow(language, index: index)
                        }
                    }
                }
                .padding(10)
            }
            .frame(maxHeight: 212)
            .onValueChange(of: viewModel.peekSelectionIndex) { value in
                proxy.scrollTo(value, anchor: .center)
            }
        }
    }

    @ViewBuilder
    private func languageRow(_ language: OnboardingPeekLanguage, index: Int) -> some View {
        let selected = viewModel.peekSelectionIndex == index
        let label = HStack(spacing: 10) {
            Text(language.name)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(selected ? Color.white : HotkeyGoColor.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(selected ? "↵" : "\(index + 1)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(selected ? Color.white : HotkeyGoColor.popupMuted)
                .fixedSize()
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, alignment: .leading)

        if selected {
            Button { viewModel.choosePeekLanguage(at: index) } label: { label }
                .buttonStyle(HotkeyGoUI.PopupSelectedButton())
                .accessibilityLabel("Translate to \(language.name), Return")
                .accessibilityAddTraits(.isSelected)
                .id(index)
        } else {
            Button { viewModel.choosePeekLanguage(at: index) } label: { label }
                .buttonStyle(HotkeyGoUI.PopupPlainRowButton())
                .accessibilityLabel("Translate to \(language.name), shortcut \(index + 1)")
                .id(index)
        }
    }

    private var processingContent: some View {
        FeedbackPill(
            phase: .processing,
            reduceMotion: reduceMotion,
            planStatus: .shared,
            onClose: {}
        )
        .id("peek-processing")
        .allowsHitTesting(false)
        .accessibilityLabel("Translating the selected sample")
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 16)
    }

    private var resultContent: some View {
        Text(verbatim: viewModel.peekLanguage.result)
            .font(.system(size: 15, weight: .regular))
            .lineSpacing(4)
            .foregroundStyle(HotkeyGoColor.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .accessibilityLabel("Peek translation: \(viewModel.peekLanguage.result)")
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 16)
    }

    @ViewBuilder private var footer: some View {
        if viewModel.phase == .peekChoice {
            footerLabel("Preview only · nothing is replaced")
        } else if viewModel.phase == .peekProcessing {
            footerLabel("Auto · \(viewModel.peekDetectedLanguageName) · \(viewModel.peekWordCount) words")
        } else if viewModel.phase == .peek {
            Button(action: viewModel.copyPeekResult) {
                footerLabel(viewModel.peekCopied ? "Copied · Esc close" : "Copy · ⌘C · Esc close")
            }
            .buttonStyle(.plain)
            .help("Copy translation (⌘C)")
            .accessibilityLabel(viewModel.peekCopied ? "Translation copied" : "Copy translation; Escape closes Peek")
        } else {
            footerLabel("Esc close")
        }
    }

    private func footerLabel(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(HotkeyGoColor.popupMuted)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 32)
            .accessibilityHidden(true)
    }
}
