# HotkeyGoUI

**Status:** app-local design system, introduced 2026-10-12. The design blueprint remains the visual specification; this is the implementation catalog and gap register.

## Boundary

HotkeyGoUI lives in `HotkeyGo/Core/DesignSystem/` and is compiled into the macOS app. It is not a CDN asset or a separate package. SwiftUI/AppKit controls need native accessibility, keyboard, focus, appearance, and non-activating-panel behavior; a web delivery layer would not provide those. Extract a Swift package only when another native target genuinely needs the same components.

Use `HotkeyGoUI` for shared appearance and interaction primitives. Feature-specific rows, panel composition, state, copy, and view models stay with their feature. The existing `HotkeyGo*`, `HotkeyGoColor`, and button-style types remain as implementation types while call sites migrate; `HotkeyGoUI` provides the stable entry point, without a broad cosmetic rename.

## Current catalog

| Need | HotkeyGoUI entry point | Notes |
|---|---|---|
| Semantic light/dark colors | `HotkeyGoUI.Colors` | Backed by `HotkeyGoColor`; roles defined in the blueprint. |
| On/off, including no visible label | `HotkeyGoUI.Toggle` | Supply `.accessibilityLabel` when `showsLabel: false`. |
| Explicit Light/Dark choice | `HotkeyGoUI.ThemePicker` | Segmented, not a boolean toggle. |
| One of several choices | `HotkeyGoUI.RadioOption` | Compact radio option. |
| Primary, subtle, compact, and Quit buttons | `HotkeyGoUI.PrimaryButton`, `.SubtleButton`, `.CompactButton`, `.QuitButton` | Primary has filled, soft, and transparent idle appearances; use filled for menu actions and prominent calls to action, and soft for intentionally quieter actions. Compact primary and Quit buttons use 12 pt horizontal padding and a 28 pt minimum height. Quit defaults to soft, matching the menu action row's button size while keeping its warm-to-pink outline; filled is available when a destructive action needs more emphasis. They share their cut corners, highlight, and press trace across appearances. |
| Lighter popup list selection | `HotkeyGoUI.PopupSelectedButton`, `.PopupPlainRowButton`, and `View.hotkeygoPopupPanel()` | Shared by Actions and Peek. One selected row uses the dark gradient-edge button; unselected rows stay plain text with a quiet inset, cut-corner hover wash. The popup surface uses 12 pt cut corners and adaptive border/divider tokens. |
| Actions palette shell | `HotkeyGoUI.ActionPalette` and `.ActionPaletteRow` | Shared by the live Actions picker and its onboarding rehearsal. Keeps the search header, grouped rows, keyboard selection, context label, footer, 360 pt width, and measured content height aligned. Each feature supplies its own rows and selection behavior. |
| Hotkey badge, dismissible hotkey badge, popup close badge, access badge | `HotkeyGoUI.Shortcut`, `.ShortcutButton`, `.PopupCloseButton`, `.AccessBadge` | The shortcut button accepts an action-specific accessibility hint. Settings reuses it to start shortcut recording; the popup close button receives its visible binding from `HotkeyCatalog.popupDismiss`, and panel controllers own the actual dismissal. The access badge supports an icon-only layout with its status in the accessibility label. |
| Small icon-only utility action | `HotkeyGoUI.IconButton` + `HotkeyGoUI.Icon` | Compact control for catalogued utility icons such as close. Always add a clear accessibility label. |
| Paywall usage strip | `HotkeyGoPaywallUsageStrip` | Shared 30-action usage state for limit surfaces. |
| Meaningful icon | `HotkeyGoUI.Icon(.name, size:)` | Decorative by default; label an icon-only parent control. |

Other established primitives in `DesignSystem.swift` (panel modifier, card, outlined SVG wordmark, face, keycap) are part of HotkeyGoUI's app-local implementation. Product surfaces use the supplied lowercase `hotkeygo` wordmark SVG. The menu bar uses the solid `go` key with knocked-out letters from `MenuBarIcon.imageset` as a 22 × 16 pt template image; macOS tints it for the current menu-bar appearance. Keep the status icon monochrome and free of custom accent colors.

The Actions and Peek pickers use a 360 pt one-column list shell. Light surfaces use the compact popup border and divider colors; dark surfaces resolve to the existing dark line, surface, ink, secondary, and primary-action tokens.

The onboarding Actions step uses the same `HotkeyGoUI.ActionPalette` shell as the live picker, with local sample choices and a local replacement rehearsal. It sends no request and does not import the Palette feature's presentation layer.

`HotkeyCatalog` in `Infrastructure/Hotkeys/GlobalHotKey.swift` holds the default Fix, Actions, Peek, and popup dismissal bindings. Users can record unique combinations for all three actions in Settings; `⌥⌘X` remains reserved for popup dismissal. Most interactive transient panels show that binding in the shared close button; the lighter Actions and Peek pick/result shells keep the same global dismissal binding without a visible badge. The app routes the key to the frontmost visible popup before Fix. Click-through processing and success notices have no close control.

The Fix completion notice uses the shared compact status HUD without an additional shortcut badge. `HotkeyGoUI.Shortcut` remains available for controls and settings.

## Control motion

HotkeyGoUI controls share a one-shot electric edge trace. It travels once on an interaction and collapses to an invisible stroke; it never runs at rest or on hover. The toggle moves its thumb along a fixed track over 240 ms and traces the track on a value change; the radio traces only the newly selected indicator, and the theme picker traces the newly selected segment. Custom button styles trace on press (mouse or keyboard), with a slightly stronger 200 ms impulse for the primary button and a quiet 160 ms impulse elsewhere. The action and value update are not delayed for the effect.

The trace is decorative and ignored by accessibility. Disabled controls do not trigger it. With macOS Reduce Motion enabled, there is no trace, scale, or offset movement; Dim Flashing Lights also suppresses the trace. Selection and pressed states remain readable through their static colors and outlines. New custom controls should reuse this interaction grammar rather than start a loop or add a separate lightning treatment. Native fallback controls remain native and are recorded as gaps below.

## Icon rules

Use the curated 24-point Iconoir vector assets for product concepts: `themeLight`, `themeDark`, `fix`, `review`, `actions`, `peek`, `accessGranted`, `accessNeeded`, and `plan`. The SVGs are bundled locally in `Assets.xcassets`, rendered as templates, and tinted by semantic context; no runtime network request or third-party Swift package is required. Source paths and the MIT license are recorded in `docs/third-party/ICONOIR.md`. `check` and `minus` are simple catalogued system-control symbols.

The catalogued SF Symbol fallbacks are utility/platform concepts only: status, info, close, external navigation, direction arrows, text cursor, lock, Wi-Fi, System Settings, Accessibility, switch control, quit, and debug onboarding. They are intentionally centralised in `HotkeyGoUI.IconName`, rather than selected as arbitrary strings in feature views. An icon-only action still needs an explicit accessibility label and a usable hit target.

Never substitute a stock symbol for a missing primary product icon without recording a gap. The former ibis-and-blade mark is intentionally absent. The new standalone `go` key is reserved for the menu bar; use the lowercase text wordmark where the product name is needed.

## Adding a component or icon

1. Check this catalog and the blueprint for an existing semantic match.
2. Extract only a repeated behavior or a clearly shared product concept; keep unique feature composition local.
3. Provide light/dark, hover, pressed, disabled, keyboard focus, VoiceOver, and Reduce Motion behavior as applicable. Preserve native focus and non-activating panel behavior.
4. Add an example/use note here and migrate matching call sites. If native fallback is needed, add a gap below and mention it in the handoff.
5. Verify both themes and keyboard/mouse parity. Do not persist selected text in previews, logs, or fixtures.

## Open gaps

| Gap | Current fallback | Needed before closing |
|---|---|---|
| Search/input field styling | Native SwiftUI `TextField` in feature views | Keep native focus, selection, and text-entry behavior; define shared styling after repeated use establishes a stable pattern. |
| Compact utility-bar icon action | Native SwiftUI `Button` with a plain style and a 28×26 pt hit target | The cut-key `IconButton` reads as a separate tile in the 26 pt toolbar; add an unboxed shared treatment if this pattern repeats. |
| Developer-only usage scenario selector | Native segmented `Picker` | Decide whether it merits a shared multi-option control; keep native for now. |
| Feature-local plain/native buttons (for example the menu-bar access badge) | SwiftUI `.plain` or native button behavior | Migrate only when a shared interaction or matching surface is defined; these do not yet use the HotkeyGoUI edge trace. The menu actions use the shared Primary and Quit button styles. |
| Distinctive utility icons beyond primary product icons | Catalogued SF Symbols for close, arrows, lock, network, status, and platform cues | Curate vector replacements only where repeated use or brand value outweighs the clarity of a familiar macOS symbol. No feature view selects an SF Symbol directly. |
| Visual component gallery | None | Add app-local previews for light/dark, enabled/disabled, and reduced-motion states once the catalog grows. |
| Web dashboard token package | Static dashboard CSS mirrors the semantic colors and typography; the shared system remains native SwiftUI/AppKit | Keep the one-off Cloudflare Pages dashboard aligned with the blueprint. Extract reusable web tokens only if hotkeygo gains another web surface. |
