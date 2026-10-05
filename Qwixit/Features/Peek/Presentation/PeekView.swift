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
                controls
                Divider().overlay(PeekPalette.line)
                bodyContent
                Divider().overlay(PeekPalette.line)
                footer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(PeekPalette.canvas)
        .foregroundStyle(PeekPalette.text)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(PeekPalette.line, lineWidth: 1.25))
        .qwixitTheme()
    }

    private var accent: Color {
        switch viewModel.mode {
        case .translate: KColor.cyan
        case .summary: KColor.magenta
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            QwixitMark(size: 27, style: .automatic)
                .frame(width: 22)
            if viewModel.isAwaitingChoice {
                Text("Peek")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .tracking(0.35)
                Spacer()
                Text("\(viewModel.wordCount) words · \(viewModel.sourceLanguage?.code.uppercased() ?? "—")")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.35)
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
                        .background(viewModel.mode == mode ? color(for: mode).opacity(0.10) : .clear)
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
        .background(PeekPalette.raised)
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
            Text("Translate")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
            Text("\(viewModel.sourceLanguage?.code.uppercased() ?? "Auto") →")
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
            Text("Summary")
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
                    .overlay(Capsule().stroke(selected ? accent : accent.opacity(0.55)))
            }
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(selected ? PeekPalette.text : accent)
            .padding(.leading, 9)
            .padding(.trailing, 4)
            .frame(height: 28)
            .background(selected ? accent.opacity(0.18) : PeekPalette.canvas)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(selected ? accent : accent.opacity(0.55), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 8) {
            if viewModel.mode == .translate {
                Text("\(viewModel.sourceLanguage?.code.uppercased() ?? "Auto") →")
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
        .foregroundStyle(viewModel.targetLanguage == code ? PeekPalette.text : PeekPalette.muted)
        .frame(width: 34, height: 24)
        .background(viewModel.targetLanguage == code ? accent.opacity(0.18) : .clear)
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
                .background(viewModel.summaryLength == length ? accent.opacity(0.12) : .clear)
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
                case .subscriptionActivating:
                    HStack(spacing: 9) {
                        QwixitFaceView(face: .retry, size: 14)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Activating Unlimited…")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                            Text("Payment sync in progress. Try again in a moment.")
                                .contentFont()
                                .foregroundStyle(PeekPalette.muted)
                        }
                    }
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
            HStack(spacing: 10) {
                Text("You’re out of tokens!")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .tracking(0.35)
                    .foregroundStyle(KColor.magenta)
                QwixitFaceView(face: .broke, size: 14)
            }
            Text("Two coffees or unlimited Qwixit?")
                .font(.system(size: 19, weight: .bold))
            Text("30 / 30 used. unlimited is $10/mo.")
                .contentFont()
                .foregroundStyle(PeekPalette.muted)
            Button("Well, I can buy 2 coffees  ·  $10/mo  ↗") {
                _ = PaddleCheckoutOpener().openStarterCheckout()
            }
            .buttonStyle(PeekChipStyle(accent: KColor.magenta))
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
            if isOffline(message) {
                HStack(spacing: 8) {
                    QwixitFaceView(face: message == QwixitFace.idle.line ? .idle : .lost, size: 15)
                    Text(message)
                }
                .font(.system(size: 13, weight: .black, design: .monospaced))
                Text("your text is unchanged.").contentFont().foregroundStyle(PeekPalette.muted)
            } else {
                Text(message == "Select some text first." ? "Select text" : "Error")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundStyle(accent)
                Text(message).contentFont().foregroundStyle(PeekPalette.muted)
            }
            if message != "Select some text first." {
                Button("Retry  ↵") { viewModel.retry() }
                    .buttonStyle(PeekChipStyle(accent: accent))
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
            Text(viewModel.footerText)
            Spacer()
            Text("1 2 · ⇥ · Esc")
            Button(viewModel.isPinned ? "Unpin" : "Pin") { onTogglePin() }
                .buttonStyle(PeekChipStyle(accent: viewModel.isPinned ? KColor.magenta : PeekPalette.muted))
            Button(viewModel.copied ? "Copied ✓" : "Copy ⌘C") { viewModel.copyResult() }
                .buttonStyle(PeekCopyStyle())
        }
        .font(.system(size: 9, weight: .bold, design: .monospaced))
        .foregroundStyle(PeekPalette.muted)
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(PeekPalette.raised)
    }

    private func title(for mode: PeekMode) -> String {
        switch mode {
        case .translate: "Translate"
        case .summary: "Summary"
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
            .foregroundStyle(configuration.isPressed ? PeekPalette.text : accent)
            .padding(.horizontal, 8)
            .frame(height: 25)
            .background(configuration.isPressed ? accent.opacity(0.16) : accent.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(accent.opacity(0.7)))
    }
}

private struct PeekCopyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 9, weight: .black, design: .monospaced))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 9)
            .frame(height: 25)
            .background(KColor.violet.opacity(configuration.isPressed ? 0.78 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

private extension View {
    func contentFont() -> some View {
        font(.system(size: 14)).lineSpacing(6)
    }
}
