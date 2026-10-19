import SwiftUI

struct ShortcutPresentation: Equatable {
    let modifiers: [String]
    let key: String

    var displayString: String { (modifiers + [key]).joined() }
}

/// The app's shared visual vocabulary. Keep feature state and window ownership outside this namespace.
enum TokiriUI {
    typealias Colors = KColor
    typealias Toggle = QwixitToggleStyle
    typealias ThemePicker = QwixitThemePicker
    typealias RadioOption<Selection: Hashable> = QwixitRadioOption<Selection>
    typealias ButtonAppearance = TokiriButtonAppearance
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
            case .themeLight: .asset("TokiriIconSun")
            case .themeDark: .asset("TokiriIconMoon")
            case .fix: .asset("TokiriIconFix")
            case .review: .asset("TokiriIconReview")
            case .actions: .asset("TokiriIconActions")
            case .peek: .asset("TokiriIconPeek")
            case .accessGranted: .asset("TokiriIconAccessGranted")
            case .accessNeeded: .asset("TokiriIconAccessNeeded")
            case .plan: .asset("TokiriIconPlan")
            case .check: .system("checkmark")
            case .minus: .system("minus")
            case .statusSuccess: .system("checkmark.circle.fill")
            case .statusWarning: .system("exclamationmark.triangle.fill")
            case .warning: .system("exclamationmark")
            case .info: .system("info.circle.fill")
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

/// A common close affordance; the owner supplies the current shortcut and the
/// same dismissal action used by its other close paths.
struct PopupCloseBadgeButton: View {
    let shortcut: ShortcutPresentation
    let label: String
    let action: () -> Void

    var body: some View {
        TokiriUI.ShortcutButton(
            modifiers: shortcut.modifiers,
            key: shortcut.key,
            label: label,
            action: action
        )
        .help("Close · \(shortcut.displayString)")
        .accessibilityHint("Press \(shortcut.displayString) to close")
    }
}
