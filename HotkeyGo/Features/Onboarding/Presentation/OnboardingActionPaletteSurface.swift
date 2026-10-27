import SwiftUI

struct OnboardingActionPaletteSurface: View {
    @ObservedObject var viewModel: OnboardingViewModel

    private var rows: [HotkeyGoUI.ActionPaletteRow] {
        let choices = viewModel.actionChoices
        let translationCount = choices.prefix { !$0.isRewrite }.count
        let hasRewriteDivider = translationCount > 0 && choices.contains(where: \.isRewrite)
        return choices.enumerated().map { index, choice in
            HotkeyGoUI.ActionPaletteRow(
                id: String(describing: choice),
                title: choice.title,
                startsNewGroup: hasRewriteDivider && index == translationCount
            )
        }
    }

    private var separatorCount: Int { rows.filter(\.startsNewGroup).count }

    var body: some View {
        HotkeyGoUI.ActionPalette(
            query: $viewModel.actionQuery,
            contextLabel: viewModel.actionContextLabel,
            footerText: "Sample only · no request is sent",
            rows: rows,
            selectedIndex: viewModel.actionSelectionIndex,
            onSelect: { index in
                guard viewModel.actionChoices.indices.contains(index) else { return }
                viewModel.chooseAction(viewModel.actionChoices[index])
            }
        )
            .frame(
                width: 360,
                height: HotkeyGoUI.ActionPalette.preferredHeight(
                    rowCount: rows.count,
                    separatorCount: separatorCount
                )
            )
            .shadow(color: HotkeyGoColor.cardShadow, radius: 18, y: 8)
            .onboardingEscape { _ = viewModel.escapeOverlay() }
    }
}
