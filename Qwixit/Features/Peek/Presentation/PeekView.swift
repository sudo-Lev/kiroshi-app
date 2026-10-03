import SwiftUI

private enum PeekPalette {
    static let top = Color(red: 0.11, green: 0.09, blue: 0.16)
    static let bottom = Color(red: 0.071, green: 0.055, blue: 0.106)
    static let text = Color(red: 0.933, green: 0.918, blue: 0.965)
    static let muted = Color(red: 0.557, green: 0.533, blue: 0.6)
    static let line = Color.white.opacity(0.10)
}

struct PeekView: View {
    @ObservedObject var viewModel: PeekViewModel
    let onClose: () -> Void
    let onTogglePin: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(PeekPalette.line)
            if viewModel.isAwaitingChoice {
                choiceContent
            } else {
                controls
                Divider().overlay(PeekPalette.line)
                bodyContent
                Divider().overlay(PeekPalette.line)
                footer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            LinearGradient(colors: [PeekPalette.top, PeekPalette.bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .foregroundStyle(PeekPalette.text)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(PeekPalette.line))
        .preferredColorScheme(.dark)
    }

    private var accent: Color {
        switch viewModel.mode {
        case .translate: KColor.cyan
        case .summary: KColor.magenta
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            QwixitMark(size: 27, style: .dark)
                .frame(width: 22)
            if viewModel.isAwaitingChoice {
                Text("PEEK")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .tracking(1.2)
                Spacer()
                Text("\(viewModel.wordCount) WORDS · \(viewModel.sourceLanguage?.code.uppercased() ?? "—")")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(PeekPalette.muted)
            } else {
                ForEach(Array(PeekMode.allCases.enumerated()), id: \.element) { index, mode in
                    Button { viewModel.selectMode(mode) } label: {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(color(for: mode))
                                .frame(width: 3, height: 12)
                            Text(title(for: mode))
                            Text("\(index + 1)").foregroundStyle(PeekPalette.muted)
                        }
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 7)
                        .frame(height: 28)
                        .background(viewModel.mode == mode ? Color.white.opacity(0.08) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 2)
            }
            Button("×") { onClose() }
                .buttonStyle(.plain)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(PeekPalette.muted)
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .contentShape(Rectangle())
    }

    private var choiceContent: some View {
        VStack(spacing: 3) {
            translationChoiceRow
            summaryChoiceRow
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var translationChoiceRow: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 1).fill(KColor.cyan).frame(width: 3, height: 16)
            Text("TRANSLATE")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
            Text("\(viewModel.sourceLanguage?.code.uppercased() ?? "AUTO") →")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(PeekPalette.muted)
            Spacer()
            ForEach(Array(viewModel.languages.enumerated()), id: \.element.id) { index, language in
                choiceChip(
                    language.code,
                    number: index + 1,
                    selected: viewModel.selectedChoiceIndex == index,
                    accent: KColor.cyan
                ) { viewModel.runTranslation(at: index) }
                .help("Translate to \(language.name)")
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 42)
    }

    private var summaryChoiceRow: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 1).fill(KColor.magenta).frame(width: 3, height: 16)
            Text("SUMMARY")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
            Spacer()
            ForEach(Array(PeekSummaryLength.allCases.enumerated()), id: \.element) { index, length in
                let choiceIndex = viewModel.languages.count + index
                choiceChip(
                    length == .tldr ? "TL;DR" : length.rawValue.uppercased(),
                    number: choiceIndex + 1,
                    selected: viewModel.selectedChoiceIndex == choiceIndex,
                    accent: KColor.magenta
                ) { viewModel.runSummary(length) }
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 42)
    }

    private func choiceChip(
        _ title: String,
        number: Int,
        selected: Bool,
        accent: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                Text("\(number)")
                    .frame(width: 18, height: 18)
                    .overlay(Capsule().stroke(selected ? Color.black.opacity(0.35) : accent.opacity(0.55)))
            }
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(selected ? Color.black : accent)
            .padding(.leading, 9)
            .padding(.trailing, 4)
            .frame(height: 28)
            .background(selected ? accent : accent.opacity(0.10))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(accent.opacity(0.75), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 8) {
            if viewModel.mode == .translate {
                Text("\(viewModel.sourceLanguage?.code.uppercased() ?? "AUTO") →")
                    .foregroundStyle(PeekPalette.muted)
                languageSelector
            } else {
                Text(hint(for: viewModel.mode)).foregroundStyle(PeekPalette.muted)
            }
            if viewModel.mode == .summary { summaryControl }
            Spacer()
        }
        .font(.system(size: 10, weight: .bold, design: .monospaced))
        .padding(.horizontal, 16)
        .frame(height: 36)
    }

    private var languageSelector: some View {
        HStack(spacing: 0) {
            languageButton("UA", code: "uk")
            languageButton("EN", code: "en")
        }
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(PeekPalette.line))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private func languageButton(_ title: String, code: String) -> some View {
        Button(title) {
            if viewModel.targetLanguage != code { viewModel.cycleLanguage() }
        }
        .buttonStyle(.plain)
        .font(.system(size: 9, weight: .black, design: .monospaced))
        .foregroundStyle(viewModel.targetLanguage == code ? Color.black.opacity(0.8) : PeekPalette.muted)
        .frame(width: 34, height: 24)
        .background(viewModel.targetLanguage == code ? accent : .clear)
    }

    private var summaryControl: some View {
        HStack(spacing: 0) {
            ForEach(PeekSummaryLength.allCases, id: \.self) { length in
                Button(length == .tldr ? "TL;DR" : length.rawValue.uppercased()) {
                    let current = PeekSummaryLength.allCases.firstIndex(of: viewModel.summaryLength) ?? 0
                    let target = PeekSummaryLength.allCases.firstIndex(of: length) ?? 0
                    viewModel.changeLength(step: target - current)
                }
                .buttonStyle(.plain)
                .foregroundStyle(viewModel.summaryLength == length ? PeekPalette.text : PeekPalette.muted)
                .padding(.horizontal, 7)
                .frame(height: 24)
                .background(viewModel.summaryLength == length ? Color.white.opacity(0.1) : .clear)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(PeekPalette.line))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private var bodyContent: some View {
        ScrollView {
            Group {
                switch viewModel.loadState {
                case .idle:
                    EmptyView()
                case .loading:
                    skeleton
                case .loaded:
                    resultContent
                case .limitReached:
                    limitView
                case .failed(let message):
                    errorView(message)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
        }
        .frame(maxHeight: viewModel.isPinned ? 500 : 250)
    }

    private var limitView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("30 / 30 · FREE MONTH COMPLETE")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(KColor.magenta)
            Text("Well, you’re out of tokens xD")
                .font(.system(size: 19, weight: .bold))
            Text("Subscribe for unlimited Qwixit actions.")
                .contentFont()
                .foregroundStyle(PeekPalette.muted)
            Button("GO UNLIMITED · $10/MONTH") {
                _ = PaddleCheckoutOpener().openStarterCheckout()
            }
            .buttonStyle(PeekChipStyle(accent: KColor.magenta))
        }
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("QWIXING…")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(accent)
            ForEach([0.92, 0.78, 0.85], id: \.self) { width in
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(viewModel.receivedFirstToken ? 0.55 : 0.28))
                        .frame(width: proxy.size.width * width, height: 9)
                }
                .frame(height: 9)
            }
        }
    }

    @ViewBuilder
    private var resultContent: some View {
        if let result = viewModel.result {
            switch result {
            case .translation:
                // The source is already on screen, so only the translation is shown, as one passage.
                Text(result.plainText)
                    .contentFont()
                    .textSelection(.enabled)
            case .summary(let blocks):
                VStack(alignment: .leading, spacing: 13) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            if viewModel.summaryLength == .points {
                                Rectangle().fill(accent).frame(width: 6, height: 6)
                            }
                            Text(block)
                                .font(.system(size: viewModel.summaryLength == .tldr ? 17 : 14))
                                .lineSpacing(6)
                        }
                    }
                }
            }
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message == "Select some text first." ? "SELECT TEXT" : "ERROR")
                .font(.system(size: 13, weight: .black, design: .monospaced))
                .foregroundStyle(accent)
            Text(message).contentFont().foregroundStyle(PeekPalette.muted)
            if message != "Select some text first." {
                Button("RETRY  ↵") { viewModel.retry() }
                    .buttonStyle(PeekChipStyle(accent: accent))
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(viewModel.footerText)
            Spacer()
            Text("1 2 · ⇥ · ESC")
            Button(viewModel.isPinned ? "UNPIN" : "PIN") { onTogglePin() }
                .buttonStyle(PeekChipStyle(accent: viewModel.isPinned ? KColor.magenta : PeekPalette.muted))
            Button(viewModel.copied ? "COPIED ✓" : "COPY ⌘C") { viewModel.copyResult() }
                .buttonStyle(PeekCopyStyle())
        }
        .font(.system(size: 9, weight: .bold, design: .monospaced))
        .foregroundStyle(PeekPalette.muted)
        .padding(.horizontal, 16)
        .frame(height: 36)
    }

    private func title(for mode: PeekMode) -> String {
        switch mode {
        case .translate: "TRANSLATE"
        case .summary: "SUMMARY"
        }
    }

    private func hint(for mode: PeekMode) -> String {
        switch mode {
        case .translate: "Translate the selection"
        case .summary: "Condense it to the chosen length"
        }
    }

    private func color(for mode: PeekMode) -> Color {
        switch mode {
        case .translate: KColor.cyan
        case .summary: KColor.magenta
        }
    }
}

private struct PeekChipStyle: ButtonStyle {
    let accent: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(configuration.isPressed ? .white : accent)
            .padding(.horizontal, 8)
            .frame(height: 25)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(accent.opacity(0.7)))
    }
}

private struct PeekCopyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 9, weight: .black, design: .monospaced))
            .foregroundStyle(Color.black)
            .padding(.horizontal, 9)
            .frame(height: 25)
            .background(Color.white.opacity(configuration.isPressed ? 0.75 : 0.96))
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

private extension View {
    func contentFont() -> some View {
        font(.system(size: 14)).lineSpacing(6)
    }
}
