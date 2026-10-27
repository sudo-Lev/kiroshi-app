import SwiftUI

struct ShortcutPresentation: Equatable {
    let modifiers: [String]
    let key: String

    var displayString: String { (modifiers + [key]).joined() }
}

/// The app's shared visual vocabulary. Keep feature state and window ownership outside this namespace.
enum HotkeyGoUI {
    typealias Colors = HotkeyGoColor
    typealias Toggle = HotkeyGoToggleStyle
    typealias ThemePicker = HotkeyGoThemePicker
    typealias RadioOption<Selection: Hashable> = HotkeyGoRadioOption<Selection>
    typealias ButtonAppearance = HotkeyGoButtonAppearance
    typealias PrimaryButton = PrimaryButtonStyle
    typealias QuitButton = QuitButtonStyle
    typealias SubtleButton = SubtleButtonStyle
    typealias CompactButton = CompactButtonStyle
    typealias PopupSelectedButton = PopupSelectedButtonStyle
    typealias PopupPlainRowButton = PopupPlainRowButtonStyle
    typealias IconButton = IconButtonStyle
    typealias Shortcut = ShortcutBadge
    typealias ShortcutButton = ShortcutBadgeButton
    typealias PopupCloseButton = PopupCloseBadgeButton
    typealias AccessBadge = AccessStatusBadge
    typealias ActionPalette = HotkeyGoActionPalette
    typealias ActionPaletteRow = HotkeyGoActionPaletteRow

    /// Choose an icon by meaning, never by an asset or SF Symbol string in a feature view.
    enum IconName {
        case themeLight, themeDark
        case fix, review, actions, peek
        case accessGranted, accessNeeded, plan
        case check, minus
        case statusSuccess, statusWarning, warning, info
        case added, removed
        case close, externalLink, chevronRight, chevronDown, arrowRight
        case textCursor, lock, lockOpen, wifi, wifiOff
        case settings, accessibility, switchControl, quit, onboarding

        fileprivate var source: IconSource {
            switch self {
            case .themeLight: .asset("HotkeyGoIconSun")
            case .themeDark: .asset("HotkeyGoIconMoon")
            case .fix: .asset("HotkeyGoIconFix")
            case .review: .asset("HotkeyGoIconReview")
            case .actions: .asset("HotkeyGoIconActions")
            case .peek: .asset("HotkeyGoIconPeek")
            case .accessGranted: .asset("HotkeyGoIconAccessGranted")
            case .accessNeeded: .asset("HotkeyGoIconAccessNeeded")
            case .plan: .asset("HotkeyGoIconPlan")
            case .check: .system("checkmark")
            case .minus: .system("minus")
            case .statusSuccess: .system("checkmark.circle.fill")
            case .statusWarning: .system("exclamationmark.triangle.fill")
            case .warning: .system("exclamationmark")
            case .info: .system("info.circle")
            case .added: .system("underline")
            case .removed: .system("strikethrough")
            case .close: .system("xmark")
            case .externalLink: .system("arrow.up.right")
            case .chevronRight: .system("chevron.right")
            case .chevronDown: .system("chevron.down")
            case .arrowRight: .system("arrow.right")
            case .textCursor: .system("text.cursor")
            case .lock: .system("lock.fill")
            case .lockOpen: .system("lock.open.fill")
            case .wifi: .system("wifi")
            case .wifiOff: .system("wifi.slash")
            case .settings: .system("gearshape.fill")
            case .accessibility: .system("accessibility")
            case .switchControl: .system("switch.2")
            case .quit: .system("power")
            case .onboarding: .system("sparkles")
            }
        }
    }

    fileprivate enum IconSource {
        case asset(String)
        case system(String)
    }

    /// Decorative by default; icon-only buttons must label the parent control.
    struct Icon: View {
        let name: IconName
        var size: CGFloat = 14

        init(_ name: IconName, size: CGFloat = 14) {
            self.name = name
            self.size = size
        }

        @ViewBuilder var body: some View {
            Group {
                switch name.source {
                case .asset(let assetName):
                    Image(assetName)
                        .resizable()
                        .renderingMode(.template)
                        .interpolation(.high)
                        .scaledToFit()
                case .system(let systemName):
                    Image(systemName: systemName)
                        .resizable()
                        .scaledToFit()
                }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        }
    }
}

struct HotkeyGoActionPaletteRow: Identifiable, Equatable {
    let id: String
    let title: String
    let startsNewGroup: Bool
}

/// Shared Actions picker chrome, used by the live palette and its onboarding rehearsal.
struct HotkeyGoActionPalette: View {
    @Binding var query: String
    let contextLabel: String
    let footerText: String
    let rows: [HotkeyGoActionPaletteRow]
    let selectedIndex: Int
    let onSelect: (Int) -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(HotkeyGoColor.popupDivider).frame(height: 1)
            list
            Rectangle().fill(HotkeyGoColor.popupDivider).frame(height: 1)
            footer
        }
        .frame(width: 360)
        .foregroundStyle(HotkeyGoColor.ink)
        .hotkeygoPopupPanel()
        .hotkeygoTheme()
    }

    static func preferredHeight(rowCount: Int, separatorCount: Int) -> CGFloat {
        let visibleRowCount = max(rowCount, 1)
        let visibleSeparatorCount = max(separatorCount, 0)
        let listGaps = max(visibleRowCount - 1, 0) + visibleSeparatorCount
        return CGFloat(
            2 + 48 + 1 + 20 + visibleRowCount * 41 + listGaps * 6
                + visibleSeparatorCount + 1 + 32
        )
    }

    private var header: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(HotkeyGoColor.violet)
                .frame(width: 1.5, height: 18)

            TextField(
                "",
                text: $query,
                prompt: Text("Search…").foregroundColor(HotkeyGoColor.popupMuted)
            )
            .textFieldStyle(.plain)
            .font(.system(size: 14, weight: .medium, design: .monospaced))
            .foregroundStyle(HotkeyGoColor.ink)
            .focused($searchFocused)
            .accessibilityLabel("Search actions")
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(contextLabel)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(HotkeyGoColor.popupMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .onAppear { searchFocused = true }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if rows.isEmpty {
                        Text("No matching action")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(HotkeyGoColor.secondary)
                            .frame(maxWidth: .infinity, minHeight: 41, alignment: .leading)
                    } else {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            if row.startsNewGroup, index > 0 {
                                Rectangle()
                                    .fill(HotkeyGoColor.popupDivider)
                                    .frame(height: 1)
                                    .padding(.horizontal, 4)
                            }
                            choiceRow(row, at: index)
                        }
                    }
                }
                .padding(10)
            }
            .frame(maxHeight: 380)
            .onValueChange(of: selectedIndex) { value in proxy.scrollTo(value, anchor: .center) }
        }
    }

    @ViewBuilder
    private func choiceRow(_ row: HotkeyGoActionPaletteRow, at index: Int) -> some View {
        let selected = index == selectedIndex
        let label = HStack(spacing: 10) {
            Text(row.title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(selected ? Color.white : HotkeyGoColor.ink)
                .lineLimit(1)
                .truncationMode(.tail)
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
            Button { onSelect(index) } label: { label }
                .buttonStyle(HotkeyGoUI.PopupSelectedButton())
                .accessibilityLabel("\(row.title), Return")
                .accessibilityAddTraits(.isSelected)
                .id(index)
        } else {
            Button { onSelect(index) } label: { label }
                .buttonStyle(HotkeyGoUI.PopupPlainRowButton())
                .accessibilityLabel("\(row.title), shortcut \(index + 1)")
                .id(index)
        }
    }

    private var footer: some View {
        Text(footerText)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(HotkeyGoColor.popupMuted)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 32)
    }
}

/// A common close affordance; the owner supplies the current shortcut and the
/// same dismissal action used by its other close paths.
struct PopupCloseBadgeButton: View {
    let shortcut: ShortcutPresentation
    let label: String
    let action: () -> Void

    var body: some View {
        HotkeyGoUI.ShortcutButton(
            modifiers: shortcut.modifiers,
            key: shortcut.key,
            label: label,
            action: action
        )
        .help("Close · \(shortcut.displayString)")
        .accessibilityHint("Press \(shortcut.displayString) to close")
    }
}
