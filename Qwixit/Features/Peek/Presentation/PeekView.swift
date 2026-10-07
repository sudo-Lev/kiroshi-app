import SwiftUI

private enum PeekPalette {
    static let canvas = KColor.surface
    static let raised = KColor.canvasRaised
    static let text = KColor.ink
    static let muted = KColor.secondary
    static let line = KColor.line
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
                bodyContent
                Divider().overlay(PeekPalette.line)
                footer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(PeekPalette.text)
        .qwixitPanel()
        .qwixitTheme()
    }

    private var accent: Color { KColor.cyan }

    private var header: some View {
        HStack(spacing: 8) {
            QwixitMark(size: 20, style: .automatic)
                .frame(width: 20)
            if viewModel.isAwaitingChoice {
                Text("Translate to…")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
            } else {
                Text(viewModel.sourceLanguage?.code.uppercased() ?? "AUTO")
                    .foregroundStyle(PeekPalette.muted)
                Text("→")
                    .foregroundStyle(PeekPalette.muted)
                ForEach(Array(viewModel.languages.enumerated()), id: \.element.id) { index, language in
                    Button(language.code) { viewModel.runTranslation(at: index) }
                        .buttonStyle(CompactButtonStyle(
                            accent: KColor.cyan,
                            isSelected: viewModel.targetLanguage == language.id
                        ))
                }
                Spacer()
            }
            Button(action: onClose) { Image(systemName: "xmark") }
                .buttonStyle(IconButtonStyle())
                .accessibilityLabel("Close")
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .contentShape(Rectangle())
        .background(PeekPalette.raised)
    }

    private var choiceContent: some View {
        VStack(spacing: 0) {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())],
                spacing: 8
            ) {
                ForEach(Array(viewModel.languages.enumerated()), id: \.element.id) { index, language in
                    languageCard(language, index: index)
                }
            }
            .padding(12)

            Divider().overlay(PeekPalette.line)

            HStack {
                Text("\(viewModel.wordCount) words")
                Spacer()
                Text("1–4 or ↵ to translate")
                Text("Esc")
            }
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(PeekPalette.muted)
            .padding(.horizontal, 14)
            .frame(height: 40)
        }
    }

    private func languageCard(_ language: TranslationLanguage, index: Int) -> some View {
        let selected = viewModel.selectedChoiceIndex == index
        return Button { viewModel.runTranslation(at: index) } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(language.name)
                        .font(.system(size: 13, weight: .bold))
                    Text(languageDetail(language))
                        .font(.system(size: 10))
                        .foregroundStyle(PeekPalette.muted)
                }
                Spacer()
                Text("\(index + 1)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .frame(width: 24, height: 24)
                    .background(KColor.surface, in: QwixitControlShape(cut: 5))
                    .overlay(QwixitControlShape(cut: 5).stroke(PeekPalette.line))
            }
            .padding(.horizontal, 12)
            .frame(height: 62)
        }
        .buttonStyle(SelectionButtonStyle(accent: KColor.violet, isSelected: selected, cut: 8))
        .help("Translate to \(language.name)")
    }

    private func languageDetail(_ language: TranslationLanguage) -> String {
        let englishName = switch language.id {
        case "uk": "Ukrainian"
        case "pl": "Polish"
        case "de": "German"
        case "en": sourceBaseLanguage == "en" ? "Clean up English" : "English"
        default: language.code
        }
        return viewModel.targetLanguage == language.id ? "\(englishName) · last used" : englishName
    }

    private var sourceBaseLanguage: String {
        viewModel.sourceLanguage?.code.split(separator: "-").first.map(String.init)?.lowercased() ?? ""
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
                    VStack(alignment: .leading, spacing: 12) {
                        if QwixitUsage.remaining == 0 {
                            HStack(spacing: 7) {
                                QwixitFaceView(face: .pay, size: 12)
                                Text(QwixitFace.pay.line)
                            }
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(KColor.violet)
                        }
                        resultContent
                    }
                case .limitReached:
                    limitView
                case .failed(let message):
                    errorView(message)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .frame(maxHeight: viewModel.isPinned ? 500 : 250)
    }

    private var limitView: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                QwixitFaceView(face: .pay, size: 14, color: KColor.violet)
                Text("Ready for more?")
                    .font(.system(size: 16, weight: .bold))
            }
            Text("You’ve used 30 free Qwixes this month.")
                .contentFont()
                .foregroundStyle(PeekPalette.muted)
            Button {
                _ = PaddleCheckoutOpener().openStarterCheckout()
            } label: {
                HStack(spacing: 7) {
                    Text("Get Unlimited")
                    Text("$10/mo")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .opacity(0.82)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .bold))
                }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 13) {
            if viewModel.isRetrying {
                HStack(spacing: 8) {
                    QwixitFaceView(face: .retry, size: 13)
                    Text(QwixitFace.retry.line)
                }
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(accent)
            } else {
                Text("Qwixing…")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.35)
                    .foregroundStyle(accent)
            }
            ForEach([0.92, 0.78, 0.85], id: \.self) { width in
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(viewModel.receivedFirstToken ? PeekPalette.muted.opacity(0.38) : PeekPalette.line.opacity(0.8))
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
                PeekMarkdownText(
                    markdown: result.plainText,
                    accent: KColor.cyan,
                    baseSize: 11.5,
                    baseWeight: .medium
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
            if isOffline(message) {
                HStack(spacing: 8) {
                    QwixitFaceView(face: message == QwixitFace.idle.line ? .idle : .lost, size: 15)
                    Text(message)
                }
                .font(.system(size: 13, weight: .black, design: .monospaced))
                Text("Your text is unchanged. Try again when you’re back online.")
                    .contentFont()
                    .foregroundStyle(PeekPalette.muted)
            } else {
                HStack(spacing: 9) {
                    Image(systemName: message == "Select some text first." ? "text.cursor" : "exclamationmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(message == "Select some text first." ? KColor.secondary : KColor.danger)
                        .frame(width: 30, height: 30)
                        .background((message == "Select some text first." ? KColor.secondary : KColor.danger).opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(message == "Select some text first."
                             ? "Nothing selected yet"
                             : QwixitErrorCopy.title(for: message))
                            .font(.system(size: 13, weight: .semibold))
                        Text(message == "Select some text first."
                             ? "Highlight text in any app, then press the shortcut again."
                             : message)
                            .font(.system(size: 11))
                            .foregroundStyle(PeekPalette.muted)
                    }
                }
            }
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
        HStack(spacing: 12) {
            Text("\(viewModel.wordCount) words · Esc")
            Spacer()
            Button(viewModel.isPinned ? "Unpin" : "Pin") { onTogglePin() }
                .buttonStyle(CompactButtonStyle(
                    accent: viewModel.isPinned ? KColor.magenta : PeekPalette.muted,
                    isSelected: viewModel.isPinned
                ))
            Button { viewModel.copyResult() } label: {
                HStack(spacing: 4) {
                    Text(viewModel.copied ? "Copied" : "Copy ⌘C")
                    if viewModel.copied { Image(systemName: "checkmark") }
                }
            }
            .buttonStyle(CompactButtonStyle(accent: KColor.violet, prominent: true))
        }
        .font(.system(size: 9, weight: .bold, design: .monospaced))
        .foregroundStyle(PeekPalette.muted)
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(PeekPalette.raised)
    }

}

private extension View {
    func contentFont() -> some View {
        font(.system(size: 14)).lineSpacing(6)
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
                .lineSpacing(2.5)

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
