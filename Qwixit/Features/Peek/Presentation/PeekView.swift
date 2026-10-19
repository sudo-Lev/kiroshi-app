import SwiftUI

private enum PeekPalette {
    static let text = KColor.ink
    static let muted = KColor.secondary
    static let line = KColor.line
    static let popupDivider = KColor.popupDivider
}

struct PeekView: View {
    @ObservedObject var viewModel: PeekViewModel
    let onClose: () -> Void
    let onTogglePin: () -> Void
    let onUpgrade: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(PeekPalette.popupDivider).frame(height: 1)
            if viewModel.loadState == .limitReached {
                paywallContent
                Rectangle().fill(PeekPalette.popupDivider).frame(height: 1)
                footer
            } else {
                if viewModel.isAwaitingChoice {
                    choiceContent
                } else {
                    bodyContent
                    Rectangle().fill(PeekPalette.popupDivider).frame(height: 1)
                    footer
                }
            }
        }
        .frame(width: 360, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .foregroundStyle(PeekPalette.text)
        .tokiriPopupPanel()
        .qwixitTheme()
    }

    private var accent: Color { KColor.cyan }

    private var header: some View {
        Group {
            if viewModel.loadState == .limitReached {
                HStack {
                    Text("Peek")
                        .font(.system(size: 14, weight: .bold))
                    Spacer(minLength: 0)
                    Text(viewModel.contextLabel)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(KColor.popupMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .padding(.horizontal, 16)
            } else if viewModel.isAwaitingChoice || viewModel.sourceText.isEmpty {
                HStack(spacing: 10) {
                    Rectangle().fill(KColor.violet).frame(width: 1.5, height: 18)
                    TextField(
                        "",
                        text: $viewModel.query,
                        prompt: Text("Search…").foregroundColor(KColor.popupMuted)
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(PeekPalette.text)
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
                .onAppear { searchFocused = true }
                .onChange(of: viewModel.wordCount) { _, _ in searchFocused = true }
            } else {
                HStack(spacing: 10) {
                    Text("\(viewModel.sourceLanguage?.displayName ?? "Unknown language") →")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(KColor.popupMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Button(viewModel.targetLanguageName) { viewModel.cycleLanguage() }
                        .buttonStyle(TokiriUI.PopupSelectedButton(compact: true))
                        .help("Next language")
                        .accessibilityLabel("Target language: \(viewModel.targetLanguageName). Switch to next language.")
                    Spacer(minLength: 0)
                    Button("⇥ next") { viewModel.cycleLanguage() }
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(KColor.popupMuted)
                        .buttonStyle(.plain)
                        .accessibilityLabel("Next language")
                }
                .padding(.leading, 16)
                .padding(.trailing, 10)
            }
        }
        .frame(height: 48)
        .contentShape(Rectangle())
        .contextMenu {
            Button(viewModel.isPinned ? "Unpin Peek" : "Pin Peek", action: onTogglePin)
        }
    }

    private var choiceContent: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 6) {
                        if viewModel.visibleLanguages.isEmpty {
                            Text("No language matches \"\(viewModel.query)\"")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(PeekPalette.muted)
                                .frame(maxWidth: .infinity, minHeight: 41, alignment: .leading)
                        } else {
                            ForEach(Array(viewModel.visibleLanguages.enumerated()), id: \.element.id) { index, language in
                                languageRow(language, index: index)
                            }
                        }
                    }
                    .padding(10)
                }
                .frame(maxHeight: 380)
                .onChange(of: viewModel.selectedChoiceIndex) { _, value in proxy.scrollTo(value, anchor: .center) }
            }
            Rectangle().fill(PeekPalette.popupDivider).frame(height: 1)
            footer
        }
    }

    @ViewBuilder
    private func languageRow(_ language: TranslationLanguage, index: Int) -> some View {
        let selected = viewModel.selectedChoiceIndex == index
        let label = HStack(spacing: 10) {
            Text(language.name)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(selected ? Color.white : PeekPalette.text)
                .lineLimit(1)
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
            Button { viewModel.chooseLanguage(at: index) } label: { label }
                .buttonStyle(TokiriUI.PopupSelectedButton())
                .accessibilityLabel("Translate to \(language.name), Return")
                .accessibilityAddTraits(.isSelected)
                .id(index)
        } else {
            Button { viewModel.chooseLanguage(at: index) } label: { label }
                .frame(height: 41)
                .buttonStyle(TokiriUI.PopupPlainRowButton())
                .accessibilityLabel("Translate to \(language.name), shortcut \(index + 1)")
                .id(index)
        }
    }

    private var bodyContent: some View {
        ScrollView {
            Group {
                switch viewModel.loadState {
                case .idle:
                    EmptyView()
                case .loading:
                    statusChip(.processing)
                case .success, .loaded:
                    resultContent
                case .limitReached:
                    EmptyView()
                case .failed(let message):
                    errorView(message)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 16)
        }
        .frame(maxHeight: viewModel.isPinned ? 500 : 250)
    }

    private var paywallContent: some View {
        VStack(spacing: 0) {
            QwixitPaywallUsageStrip(used: 30, remaining: 0, reduceMotion: reduceMotion)
            limitView
        }
    }

    private var limitView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("30/30. You ran it dry.")
                .font(.system(size: 20, weight: .black, design: .rounded))

            Text("Free ride’s over. Advanced gives you more room to work. Same quality bar.")
                .font(.system(size: 13.5))
                .foregroundStyle(PeekPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 7)

            Spacer(minLength: 10)

            HStack(spacing: 9) {
                Button(action: onUpgrade) {
                    Text("Get Advanced · $10")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityLabel("Get Tokiri Advanced for ten dollars per month")

                Button("Nah", action: onClose)
                    .buttonStyle(SubtleButtonStyle())
                    .frame(width: 58)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 19)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func statusChip(
        _ phase: AppPhase,
        successDetail: String = "RESULT READY"
    ) -> some View {
        FeedbackPill(
            phase: phase,
            reduceMotion: reduceMotion,
            successDetail: successDetail,
            onClose: {}
        )
        .id(phase == .success ? "peek-success" : "peek-processing")
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var resultContent: some View {
        if let result = viewModel.result {
            switch result {
            case .translation:
                PeekMarkdownText(
                    markdown: result.plainText,
                    accent: KColor.cyan,
                    baseSize: 15,
                    baseWeight: .regular
                )
            case .summary(let blocks):
                VStack(alignment: .leading, spacing: 13) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            if viewModel.summaryLength == .points {
                                Rectangle().fill(accent).frame(width: 6, height: 6)
                            }
                            PeekMarkdownText(
                                markdown: block,
                                accent: KColor.magenta,
                                baseSize: viewModel.summaryLength == .tldr ? 14 : 12.5,
                                baseWeight: .regular
                            )
                        }
                    }
                }
            }
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            FeedbackPill(
                phase: message == "Select some text first."
                    ? .noSelection
                    : isOffline(message) ? .offline : .error(message),
                reduceMotion: reduceMotion,
                embedded: true,
                onClose: onClose
            )
            if message != "Select some text first." {
                Button("Retry  ↵") { viewModel.retry() }
                    .buttonStyle(CompactButtonStyle(accent: accent))
            }
        }
    }

    private func isOffline(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("offline")
            || normalized.contains("no signal")
            || normalized.contains("internet connection")
            || normalized.contains("network connection")
            || normalized.contains("could not connect")
    }

    private var footer: some View {
        Group {
            if viewModel.isAwaitingChoice {
                footerLabel("Preview only · nothing is replaced")
            } else if viewModel.result != nil {
                Button { viewModel.copyResult() } label: {
                    footerLabel(viewModel.copied ? "Copied · Esc close" : "↵ copy · Esc close")
                }
                .buttonStyle(.plain)
                .help("Copy translation")
                .accessibilityLabel(viewModel.copied ? "Copied" : "Copy translation. Press Return.")
            } else if case .failed = viewModel.loadState, viewModel.sourceText.isEmpty == false {
                footerLabel("↵ retry · Esc close")
            } else {
                footerLabel("Esc close")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 32)
    }

    private func footerLabel(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(KColor.popupMuted)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

}

private struct PeekMarkdownText: View {
    let markdown: String
    let accent: Color
    let baseSize: CGFloat
    let baseWeight: Font.Weight

    private var blocks: [PeekMarkdownBlock] {
        PeekMarkdownParser.parse(markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks) { block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .tint(accent)
    }

    @ViewBuilder
    private func blockView(_ block: PeekMarkdownBlock) -> some View {
        switch block.kind {
        case .paragraph(let text):
            inline(text, size: baseSize, weight: baseWeight)
                .lineSpacing(baseSize >= 15 ? 4 : 2.5)

        case .heading(let level, let text):
            inline(
                text,
                size: max(baseSize + 1, level == 1 ? 14.5 : level == 2 ? 13.5 : 12.5),
                weight: .bold
            )
            .lineSpacing(2)
            .padding(.top, block.id == blocks.first?.id ? 0 : 2)

        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text("–")
                    .font(.system(size: baseSize, weight: .medium))
                    .foregroundStyle(PeekPalette.muted)
                inline(text, size: baseSize, weight: baseWeight)
                    .lineSpacing(2.5)
            }

        case .numbered(let number, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(number).")
                    .font(.system(size: baseSize - 1, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent)
                    .frame(minWidth: 20, alignment: .trailing)
                inline(text, size: baseSize, weight: baseWeight)
                    .lineSpacing(2.5)
            }

        case .quote(let text):
            HStack(alignment: .top, spacing: 9) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(accent.opacity(0.75))
                    .frame(width: 2)
                inline(text, size: baseSize, weight: .medium)
                    .foregroundStyle(PeekPalette.muted)
                    .lineSpacing(2.5)
            }
            .padding(.vertical, 3)

        case .code(let text):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.system(size: max(baseSize - 1, 10.5), weight: .medium, design: .monospaced))
                    .lineSpacing(3)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
            .background(KColor.receipt)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(PeekPalette.line, lineWidth: 1)
            }

        case .divider:
            Rectangle()
                .fill(PeekPalette.line)
                .frame(height: 1)
                .padding(.vertical, 2)
        }
    }

    private func inline(
        _ source: String,
        size: CGFloat,
        weight: Font.Weight = .regular
    ) -> some View {
        Text(PeekMarkdownParser.inline(source))
            .font(.system(size: size, weight: weight))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PeekMarkdownBlock: Identifiable {
    enum Kind {
        case paragraph(String)
        case heading(level: Int, text: String)
        case bullet(String)
        case numbered(number: Int, text: String)
        case quote(String)
        case code(String)
        case divider
    }

    let id: Int
    let kind: Kind
}

private enum PeekMarkdownParser {
    static func parse(_ markdown: String) -> [PeekMarkdownBlock] {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        var result: [PeekMarkdownBlock] = []
        var paragraph: [String] = []
        var code: [String] = []
        var isCodeBlock = false

        func append(_ kind: PeekMarkdownBlock.Kind) {
            result.append(PeekMarkdownBlock(id: result.count, kind: kind))
        }

        func flushParagraph() {
            let text = paragraph.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            paragraph.removeAll(keepingCapacity: true)
            if !text.isEmpty { append(.paragraph(text)) }
        }

        func flushCode() {
            let text = code.joined(separator: "\n").trimmingCharacters(in: .newlines)
            code.removeAll(keepingCapacity: true)
            if !text.isEmpty { append(.code(text)) }
        }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                if isCodeBlock {
                    flushCode()
                } else {
                    flushParagraph()
                }
                isCodeBlock.toggle()
                continue
            }

            if isCodeBlock {
                code.append(rawLine)
                continue
            }

            if line.isEmpty {
                flushParagraph()
                continue
            }

            if ["---", "***", "___"].contains(line) {
                flushParagraph()
                append(.divider)
                continue
            }

            if let heading = heading(from: line) {
                flushParagraph()
                append(.heading(level: heading.level, text: heading.text))
                continue
            }

            if let bullet = bullet(from: line) {
                flushParagraph()
                append(.bullet(bullet))
                continue
            }

            if let numbered = numbered(from: line) {
                flushParagraph()
                append(.numbered(number: numbered.number, text: numbered.text))
                continue
            }

            if line.hasPrefix("> ") {
                flushParagraph()
                append(.quote(String(line.dropFirst(2))))
                continue
            }

            paragraph.append(line)
        }

        if isCodeBlock { flushCode() } else { flushParagraph() }
        return result.isEmpty ? [PeekMarkdownBlock(id: 0, kind: .paragraph(markdown))] : result
    }

    static func inline(_ markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes), line.dropFirst(hashes).hasPrefix(" ") else { return nil }
        return (hashes, String(line.dropFirst(hashes + 1)))
    }

    private static func bullet(from line: String) -> String? {
        guard line.count > 2 else { return nil }
        let prefix = line.prefix(2)
        guard prefix == "- " || prefix == "* " || prefix == "+ " else { return nil }
        return String(line.dropFirst(2))
    }

    private static func numbered(from line: String) -> (number: Int, text: String)? {
        guard let dot = line.firstIndex(of: ".") else { return nil }
        let numberText = line[..<dot]
        let remainder = line[line.index(after: dot)...]
        guard let number = Int(numberText), remainder.hasPrefix(" ") else { return nil }
        return (number, String(remainder.dropFirst()))
    }
}
