import SwiftUI

struct PaletteView: View {
    @ObservedObject var viewModel: PaletteViewModel
    @FocusState private var searchFocused: Bool

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
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(viewModel.contextLabel)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(KColor.popupMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .onAppear { searchFocused = true }
        .onValueChange(of: viewModel.wordCount) { _ in searchFocused = true }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if viewModel.choices.isEmpty {
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
            .onValueChange(of: viewModel.selectedIndex) { value in proxy.scrollTo(value, anchor: .center) }
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

    private var placeholder: String { "Search…" }

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
