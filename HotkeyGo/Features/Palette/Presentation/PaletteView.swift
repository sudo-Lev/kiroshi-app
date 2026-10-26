import SwiftUI

struct PaletteView: View {
    @ObservedObject var viewModel: PaletteViewModel

    var body: some View {
        HotkeyGoUI.ActionPalette(
            query: $viewModel.query,
            contextLabel: viewModel.contextLabel,
            footerText: viewModel.footerText,
            rows: viewModel.paletteRows,
            selectedIndex: viewModel.selectedIndex,
            onSelect: { viewModel.runChoice(at: $0) }
        )
    }
}
