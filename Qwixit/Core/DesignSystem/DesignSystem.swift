import SwiftUI
import AppKit

enum ContextPanelPlacement {
    static let edgeInset: CGFloat = 12
    static let anchorGap: CGFloat = 14

    static func resolve(
        accessibilityBounds: CGRect?,
        fallbackPoint: CGPoint,
        panelSize: NSSize
    ) -> NSPoint? {
        let converted = accessibilityBounds.flatMap(appKitRect)
        let screen = converted.flatMap(screenContaining)
            ?? NSScreen.screens.first(where: { NSMouseInRect(fallbackPoint, $0.frame, false) })
            ?? NSScreen.main
        guard let screen else { return nil }

        return origin(
            anchorRect: converted,
            fallbackPoint: fallbackPoint,
            visibleFrame: screen.visibleFrame,
            panelSize: panelSize
        )
    }

    static func origin(
        anchorRect: CGRect?,
        fallbackPoint: CGPoint,
        visibleFrame: CGRect,
        panelSize: NSSize
    ) -> NSPoint {
        let anchor = anchorRect ?? CGRect(origin: fallbackPoint, size: .init(width: 1, height: 1))
        let roomOnRight = visibleFrame.maxX - anchor.maxX
        let roomOnLeft = anchor.minX - visibleFrame.minX
        let requiredWidth = panelSize.width + anchorGap

        let x: CGFloat
        if roomOnRight >= requiredWidth {
            x = anchor.maxX + anchorGap
        } else if roomOnLeft >= requiredWidth {
            x = anchor.minX - panelSize.width - anchorGap
        } else if anchor.midX <= visibleFrame.midX {
            // Keep the selected text visible and behave like an edge dock when
            // there is not enough room directly beside it.
            x = visibleFrame.maxX - panelSize.width - edgeInset
        } else {
            x = visibleFrame.minX + edgeInset
        }

        // The selected line meets the upper part of large panels, while compact
        // status pills remain vertically centred on the same anchor.
        let connectionOffset = min(panelSize.height / 2, 42)
        let preferredY = anchor.midY - panelSize.height + connectionOffset
        let y = min(
            max(preferredY, visibleFrame.minY + edgeInset),
            visibleFrame.maxY - panelSize.height - edgeInset
        )

        return NSPoint(
            x: min(max(x, visibleFrame.minX + edgeInset), visibleFrame.maxX - panelSize.width - edgeInset),
            y: y
        )
    }

    private static func appKitRect(_ accessibilityRect: CGRect) -> CGRect? {
        guard accessibilityRect.width.isFinite,
              accessibilityRect.height.isFinite,
              accessibilityRect.minX.isFinite,
              accessibilityRect.minY.isFinite,
              accessibilityRect.width > 0,
              accessibilityRect.height > 0,
              let primaryScreen = NSScreen.screens.first else { return nil }

        let converted = CGRect(
            x: accessibilityRect.minX,
            y: primaryScreen.frame.maxY - accessibilityRect.maxY,
            width: accessibilityRect.width,
            height: accessibilityRect.height
        )
        return screenContaining(converted) == nil ? nil : converted
    }

    private static func screenContaining(_ rect: CGRect) -> NSScreen? {
        let candidates: [(screen: NSScreen, area: CGFloat)] = NSScreen.screens.map { screen in
            let intersection = screen.frame.intersection(rect)
            let area: CGFloat = intersection.isNull ? 0 : intersection.width * intersection.height
            return (screen, area)
        }
        return candidates
            .filter { $0.area > 0 }
            .max { $0.area < $1.area }?
            .screen
    }
}

enum KColor {
    static let ink = adaptive(light: rgb(0.086, 0.075, 0.122), dark: rgb(0.945, 0.93, 0.98))
    static let secondary = adaptive(light: rgb(0.43, 0.42, 0.49), dark: rgb(0.69, 0.67, 0.75))
    static let canvas = adaptive(light: rgb(0.975, 0.973, 0.988), dark: rgb(0.047, 0.039, 0.071))
    static let canvasRaised = adaptive(light: rgb(0.992, 0.99, 1), dark: rgb(0.07, 0.059, 0.098))
    static let surface = adaptive(light: .white, dark: rgb(0.09, 0.078, 0.122))
    static let surfaceHover = adaptive(light: rgb(0.965, 0.955, 0.992), dark: rgb(0.145, 0.122, 0.19))
    static let line = adaptive(light: hex(0xDCDBE2), dark: hex(0x34323C))
    static let violet = adaptive(light: rgb(0.427, 0.157, 1), dark: rgb(0.59, 0.38, 1))
    /// Softer violet reserved for the Processing HUD; `violet` stays for primary buttons and focus.
    static let hudTone = adaptive(light: hex(0x7B5CF0), dark: hex(0xA98BFF))
    static let cardShadow = adaptive(light: hex(0x16131F, alpha: 0.06), dark: hex(0x000000, alpha: 0.30))
    static let primaryAction = adaptive(light: rgb(0.086, 0.075, 0.122), dark: rgb(0.31, 0.14, 0.68))
    static let primaryActionHover = adaptive(light: rgb(0.427, 0.157, 1), dark: rgb(0.43, 0.24, 0.84))
    static let magenta = adaptive(light: rgb(1, 0.176, 0.608), dark: rgb(1, 0.31, 0.68))
    static let cyan = adaptive(light: rgb(0, 0.67, 0.78), dark: rgb(0.15, 0.79, 0.89))
    static let success = adaptive(light: rgb(0.08, 0.57, 0.27), dark: rgb(0.27, 0.78, 0.44))
    static let terminalGreen = adaptive(light: hex(0x0C7332), dark: rgb(0.28, 0.9, 0.49))
    static let warning = adaptive(light: rgb(0.82, 0.45, 0.03), dark: rgb(0.98, 0.65, 0.16))
    static let danger = adaptive(light: rgb(0.9, 0.16, 0.24), dark: rgb(1, 0.37, 0.43))
    static let quitFill = adaptive(light: hex(0xD11538), dark: hex(0xA3142F))
    static let quitFillHover = adaptive(light: hex(0xE2173C), dark: hex(0xB71635))
    static let quitBorderStart = Color(nsColor: hex(0xFF8A5C))
    static let quitBorderMiddle = Color(nsColor: hex(0xF0284A))
    static let quitBorderEnd = Color(nsColor: hex(0xFF2D9B))
    static let receipt = adaptive(light: rgb(0.953, 0.945, 0.969), dark: rgb(0.12, 0.101, 0.151))

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    static func hex(_ value: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension AppAppearance {
    var colorScheme: ColorScheme { self == .dark ? .dark : .light }
}

private struct QwixitThemeModifier: ViewModifier {
    @AppStorage(AppPreferenceKey.appearance) private var rawAppearance = AppAppearance.light.rawValue

    func body(content: Content) -> some View {
        let appearance = AppAppearance(rawValue: rawAppearance) ?? .light
        content
            .preferredColorScheme(appearance.colorScheme)
            .background(QwixitWindowAppearanceBridge(appearance: appearance))
    }
}

private struct QwixitWindowAppearanceBridge: NSViewRepresentable {
    let appearance: AppAppearance

    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ view: NSView, context: Context) {
        let name: NSAppearance.Name = appearance == .dark ? .darkAqua : .aqua
        guard view.window?.appearance?.name != name else { return }
        DispatchQueue.main.async { view.window?.appearance = NSAppearance(named: name) }
    }
}

extension View {
    func qwixitTheme() -> some View { modifier(QwixitThemeModifier()) }

    func qwixitPanel(cornerRadius: CGFloat = 14, accent: Color? = nil) -> some View {
        modifier(QwixitPanelModifier(cornerRadius: cornerRadius, accent: accent))
    }
}

private struct QwixitPanelModifier: ViewModifier {
    let cornerRadius: CGFloat
    let accent: Color?

    func body(content: Content) -> some View {
        content
            .background(KColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(KColor.line, lineWidth: 1)
            }
            .overlay(alignment: .leading) {
                if let accent {
                    Capsule()
                        .fill(accent)
                        .frame(width: 2, height: 24)
                        .padding(.leading, 1)
                }
            }
    }
}

enum QwixitErrorCopy {
    enum Kind {
        case verification
        case replacement
        case emptyReply
        case unreadableReply
        case incompleteReply
        case permission
        case service
        case unknown
    }

    static func kind(for message: String) -> Kind {
        let normalized = message.lowercased()
        if normalized.contains("confirm"),
           (normalized.contains("replacement") || normalized.contains("text change")) {
            return .verification
        }
        if normalized.contains("replace") || normalized.contains("text change") {
            return .replacement
        }
        if normalized.contains("no text") || normalized.contains("empty") {
            return .emptyReply
        }
        if normalized.contains("unreadable") || normalized.contains("decode") {
            return .unreadableReply
        }
        if normalized.contains("incomplete") || normalized.contains("did not finish") || normalized.contains("stopped early") {
            return .incompleteReply
        }
        if normalized.contains("permission") || normalized.contains("accessibility") {
            return .permission
        }
        if normalized.contains("service") || normalized.contains("server") || normalized.contains("status") {
            return .service
        }
        return .unknown
    }

    static func title(for message: String) -> String {
        switch kind(for: message) {
        case .verification:
            return "Couldn’t confirm the change"
        case .replacement:
            return "Couldn’t replace the text"
        case .emptyReply:
            return "No text came back"
        case .unreadableReply:
            return "The reply couldn’t be read"
        case .incompleteReply:
            return "The reply stopped early"
        case .permission:
            return "Tokiri needs access"
        case .service:
            return "The service couldn’t finish that"
        case .unknown:
            return "Couldn’t finish that"
        }
    }

    static func headline(for message: String) -> String {
        switch kind(for: message) {
        case .verification: "CHECK THE TEXT"
        case .replacement: "NOT REPLACED"
        case .emptyReply: "EMPTY REPLY"
        case .unreadableReply: "BAD REPLY"
        case .incompleteReply: "INCOMPLETE REPLY"
        case .permission: "ACCESS NEEDED"
        case .service: "SERVICE ERROR"
        case .unknown: "NOT COMPLETED"
        }
    }

    /// Error detail is transient UI copy. Keep provider context useful without
    /// allowing a multiline or unbounded response to reshape the HUD.
    static func detail(for message: String) -> String {
        let singleLine = message
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        let limit = 180
        guard singleLine.count > limit else { return singleLine }
        return String(singleLine.prefix(limit - 1)) + "…"
    }
}

enum QwixitFace: Int, CaseIterable {
    case hello, boot, ready, pay, broke, empty, upsell, advanced, lost, retry, idle, scanning

    var open: String {
        switch self {
        case .hello: "^_^"
        case .boot: "o_o"
        case .ready: "^_-"
        case .pay: "^o^"
        case .broke: "$_00_$"
        case .empty: "x_x"
        case .upsell: "¬_¬"
        case .advanced: "$ᴗ$"
        case .lost: "?_?"
        case .retry: ">_<"
        case .idle: "#_#"
        case .scanning: "¬_¬"
        }
    }

    var shut: String {
        switch self {
        case .broke: "-_00_-"
        case .advanced: "$ᴗ$"
        default: "-_-"
        }
    }

    var line: String {
        switch self {
        case .hello: "hi. select text, press your shortcut."
        case .boot: "first launch. permissions?"
        case .ready: "ready. go fix something."
        case .pay: "wow — 30 actions already!\nlooks like we clicked."
        case .broke: "out of tokens."
        case .empty: "30 / 30 used."
        case .upsell: "advanced. $10/mo."
        case .advanced: "more room to work."
        case .lost: "no signal."
        case .retry: "reconnecting…"
        case .idle: "offline. waiting for wi-fi."
        case .scanning: "scanning…"
        }
    }

    func accessibilityLabel(bracketed: Bool) -> String {
        switch self {
        case .advanced: "Advanced plan active"
        default: text(closed: false, bracketed: bracketed)
        }
    }

    func text(closed: Bool, bracketed: Bool) -> String {
        let value = closed ? shut : open
        return bracketed ? "[ \(value) ]" : value
    }
}

struct QwixitFaceView: View {
    private struct AnimationID: Hashable {
        let face: QwixitFace
        let reduceMotion: Bool
    }

    let face: QwixitFace
    var size: CGFloat = 15
    var bracketed = true
    var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    var color = KColor.ink
    var stagger = 0

    @State private var closed = false
    @State private var scanningFrame = 0

    private let scanningFrames = [
        "[ ¬_¬ ]", "[ ¬_¬ ]", "[ ¬_¬ ]", "[ •_• ]",
        "[ ¬_¬ ]", "[ ¬_¬ ]", "[ ¬_¬ ]", "[ ¬‿¬ ]"
    ]

    var body: some View {
        ZStack {
            // Reserve the widest face so a blink cannot move adjacent controls.
            Text(face.text(closed: false, bracketed: bracketed))
                .font(faceFont)
                .hidden()
            Text(face.text(closed: true, bracketed: bracketed))
                .font(faceFont)
                .hidden()
            if size >= 13 {
                glyph.foregroundStyle(KColor.cyan).offset(x: -split)
                glyph.foregroundStyle(KColor.magenta).offset(x: split)
            }
            glyph.foregroundStyle(color)
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(face == .scanning ? "Scanning" : face.accessibilityLabel(bracketed: bracketed))
        .task(id: AnimationID(face: face, reduceMotion: reduceMotion)) {
            closed = false
            scanningFrame = 0
            guard !reduceMotion, face != .advanced else { return }
            if face == .scanning {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(320))
                    guard !Task.isCancelled else { return }
                    scanningFrame = (scanningFrame + 1) % scanningFrames.count
                }
                return
            }
            if stagger > 0 {
                try? await Task.sleep(for: .milliseconds(stagger * 1_130))
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(4_030))
                guard !Task.isCancelled else { return }
                closed = true
                try? await Task.sleep(for: .milliseconds(170))
                closed = false
            }
        }
    }

    private var glyph: some View {
        Text(displayText)
            .font(faceFont)
    }

    private var displayText: String {
        guard face == .scanning else {
            return face.text(closed: closed, bracketed: bracketed)
        }
        let frame = scanningFrames[scanningFrame]
        return bracketed ? frame : String(frame.dropFirst().dropLast())
    }

    private var faceFont: Font {
        if NSFont(name: "JetBrains Mono ExtraBold", size: size) != nil {
            return .custom("JetBrains Mono ExtraBold", fixedSize: size)
        }
        return .system(size: size, weight: .heavy, design: .monospaced)
    }

    private var split: CGFloat { 1.5 * size / 18 }
}

struct QwixitPaywallUsageStrip: View {
    let used: Int
    let remaining: Int
    var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    private var clampedUsed: Int { min(max(used, 0), 30) }
    private var clampedRemaining: Int { min(max(remaining, 0), 30) }

    var body: some View {
        HStack(spacing: 10) {
            QwixitFaceView(face: .empty, size: 17, reduceMotion: reduceMotion)

            Text("\(clampedUsed) / 30 used")
                .font(.system(size: 15, weight: .black, design: .monospaced))

            Spacer(minLength: 12)

            Text("\(clampedRemaining) free left")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(KColor.secondary)
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(KColor.canvasRaised)
        .overlay(alignment: .top) { Rectangle().fill(KColor.line).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(KColor.line).frame(height: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(clampedUsed) of 30 free actions used, \(clampedRemaining) free left")
    }
}

enum QwixitMarkStyle { case automatic, light, dark, mono }

enum QwixitLockupStyle { case automatic, light, dark }

struct QwixitMark: View {
    let size: CGFloat
    var animated = false
    var style: QwixitMarkStyle = .automatic
    @Environment(\.colorScheme) private var colorScheme
    @State private var scan = false

    var body: some View {
        ZStack {
            Image(assetName)
                .resizable()
                .renderingMode(style == .mono ? .template : .original)
                .scaledToFit()
                .foregroundStyle(style == .mono ? KColor.ink : .white)

            if animated {
                Rectangle()
                    .fill(LinearGradient(colors: [.clear, KColor.cyan.opacity(0.9), KColor.magenta.opacity(0.8), .clear], startPoint: .leading, endPoint: .trailing))
                    .frame(width: size * 0.68, height: 1)
                    .offset(y: scan ? size * 0.31 : -size * 0.31)
                    .blendMode(.plusLighter)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            guard animated else { return }
            withAnimation(.linear(duration: 0.72).repeatForever(autoreverses: false)) { scan = true }
        }
    }

    // The mark itself is static; only the scan line above animates while processing.
    private var assetName: String {
        switch style {
        case .automatic: return colorScheme == .dark ? "QwixitMarkDark" : "QwixitMarkLight"
        case .light: return "QwixitMarkLight"
        case .dark: return "QwixitMarkDark"
        case .mono: return "QwixitMarkInk"
        }
    }
}

struct QwixitLockup: View {
    var style: QwixitLockupStyle = .automatic
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(assetName)
            .resizable()
            .scaledToFit()
            .accessibilityLabel("Tokiri")
    }

    private var assetName: String {
        switch style {
        case .automatic: colorScheme == .dark ? "QwixitLockupDark" : "QwixitLockupLight"
        case .light: "QwixitLockupLight"
        case .dark: "QwixitLockupDark"
        }
    }
}

/// The supplied menu-bar asset is the complete one-color Tokiri lockup.
/// Keep it as one image so compact surfaces never split the blade from the wordmark.
struct QwixitMenuBarLogo: View {
    var body: some View {
        Image("QwixitMenuBar")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .accessibilityLabel("Tokiri")
    }
}

struct MonoLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(0.35)
            .foregroundStyle(KColor.secondary)
    }
}

struct Keycap: View {
    let symbol: String
    var active = false

    var body: some View {
        Text(symbol)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(active ? .white : KColor.ink)
            .frame(minWidth: 26, minHeight: 25)
            .padding(.horizontal, 1)
            .background(active ? KColor.violet : KColor.surfaceHover, in: QwixitControlShape(cut: 5))
            .overlay(QwixitControlShape(cut: 5).stroke(active ? KColor.violet : KColor.line))
            .overlay(alignment: .bottom) {
                Rectangle().fill(active ? Color.black.opacity(0.24) : KColor.line).frame(height: 1).padding(.horizontal, 4)
            }
            .clipShape(QwixitControlShape(cut: 5))
    }
}

struct ShortcutBadge: View {
    let modifiers: [String]
    let key: String

    var body: some View {
        standardKeycap
            .accessibilityElement(children: .ignore)
            .accessibilityLabel((modifiers + [key]).joined(separator: " "))
    }

    private var standardKeycap: some View {
        HStack(spacing: 4) {
            Text(modifiers.joined())
                .foregroundStyle(KColor.secondary)
            Text(key.uppercased())
                .foregroundStyle(KColor.violet)
        }
        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
        .padding(.horizontal, 7)
        .frame(height: 25)
        .background(KColor.surfaceHover, in: QwixitControlShape(cut: 5))
        .overlay(QwixitControlShape(cut: 5).stroke(KColor.line))
    }
}

/// Keeps the familiar hotkey badge visual while making it an explicit action.
/// Used for compact panel dismissal where the badge already occupies the close
/// affordance's natural position.
struct ShortcutBadgeButton: View {
    let modifiers: [String]
    let key: String
    let action: () -> Void
    let label: String

    init(
        modifiers: [String],
        key: String,
        label: String,
        action: @escaping () -> Void
    ) {
        self.modifiers = modifiers
        self.key = key
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ShortcutBadge(modifiers: modifiers, key: key)
        }
        .buttonStyle(ShortcutBadgeButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityHint("Dismiss this panel")
    }
}

struct ShortcutBadgeButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(QwixitControlShape(cut: 5))
            .overlay {
                QwixitControlShape(cut: 5)
                    .stroke(isHovering ? KColor.violet.opacity(0.72) : .clear, lineWidth: 1)
            }
            .tokiriElectricTrace(
                in: QwixitControlShape(cut: 5),
                on: configuration.isPressed,
                when: configuration.isPressed,
                accent: KColor.violet
            )
            .shadow(
                color: KColor.violet.opacity(isHovering ? 0.14 : 0),
                radius: isHovering ? 5 : 0
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.45)
            .scaleEffect(
                reduceMotion
                    ? 1
                    : configuration.isPressed
                        ? 0.96
                        : isHovering ? 1.015 : 1
            )
            .animation(reduceMotion ? nil : .snappy(duration: 0.13), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovering)
            .onHover { isHovering = isEnabled && $0 }
    }
}

struct AccessStatusBadge: View {
    let granted: Bool
    var compact = false
    var iconOnly = false

    private var color: Color { granted ? KColor.success : KColor.warning }

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            TokiriUI.Icon(granted ? .statusSuccess : .statusWarning, size: compact ? 9 : 10)
            if !iconOnly {
                Text(granted ? "Access" : "Access needed")
                    .font(.system(size: compact ? 7.5 : 9, weight: .bold, design: .monospaced))
                    .tracking(compact ? 0 : 0.2)
            }
        }
        .foregroundStyle(color)
        .padding(.horizontal, iconOnly ? 0 : compact ? 6 : 9)
        .frame(width: iconOnly ? (compact ? 24 : 28) : nil, height: compact ? 24 : 28)
        .background(color.opacity(0.09), in: QwixitControlShape(cut: compact ? 4 : 5))
        .overlay(QwixitControlShape(cut: compact ? 4 : 5).stroke(color.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(granted ? "Accessibility access allowed" : "Accessibility access required")
    }
}

struct QwixitControlShape: Shape {
    let cut: CGFloat

    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX + cut, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cut))
            path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cut))
            path.closeSubpath()
        }
    }
}

/// A single, self-clearing edge impulse shared by TokiriUI controls. The
/// trimmed strokes collapse to zero at the end, so no timer or looping effect
/// survives an interaction.
private struct TokiriElectricTrace<S: Shape>: View {
    let shape: S
    let accent: Color
    let prominent: Bool

    @State private var progress: CGFloat = 0

    private var head: CGFloat { min(1, progress * 1.22) }
    private var tail: CGFloat { max(0, min(1, (progress - 0.18) * 1.22)) }

    var body: some View {
        ZStack {
            shape.trim(from: tail, to: head)
                .stroke(
                    accent.opacity(prominent ? 0.48 : 0.32),
                    style: StrokeStyle(lineWidth: prominent ? 4 : 3, lineCap: .round)
                )
                .blur(radius: prominent ? 2 : 1.5)

            shape.trim(from: tail, to: head)
                .stroke(
                    accent,
                    style: StrokeStyle(lineWidth: prominent ? 1.8 : 1.35, lineCap: .round)
                )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.easeOut(duration: prominent ? 0.20 : 0.16)) {
                progress = 1
            }
        }
    }
}

private struct TokiriElectricTraceModifier<Trigger: Equatable, S: Shape>: ViewModifier {
    let shape: S
    let trigger: Trigger
    let shouldRun: Bool
    let accent: Color
    let prominent: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDimFlashingLights) private var dimFlashingLights
    @Environment(\.isEnabled) private var isEnabled
    @State private var impulse = 0

    func body(content: Content) -> some View {
        content
            .overlay {
                if impulse > 0, !reduceMotion, !dimFlashingLights, isEnabled {
                    TokiriElectricTrace(shape: shape, accent: accent, prominent: prominent)
                        .id(impulse)
                }
            }
            .onChange(of: trigger) { _, _ in
                guard shouldRun, isEnabled, !reduceMotion, !dimFlashingLights else { return }
                impulse &+= 1
            }
    }
}

private extension View {
    func tokiriElectricTrace<Trigger: Equatable, S: Shape>(
        in shape: S,
        on trigger: Trigger,
        when shouldRun: Bool = true,
        accent: Color = KColor.cyan,
        prominent: Bool = false
    ) -> some View {
        modifier(TokiriElectricTraceModifier(
            shape: shape,
            trigger: trigger,
            shouldRun: shouldRun,
            accent: accent,
            prominent: prominent
        ))
    }
}

struct QwixitToggleStyle: ToggleStyle {
    var compact = false
    /// Set to `false` when the surrounding row already provides the visible copy.
    /// Add an explicit `.accessibilityLabel(...)` at the call site in this mode.
    var showsLabel = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        Button {
            guard isEnabled else { return }
            if reduceMotion {
                configuration.isOn.toggle()
            } else {
                withAnimation(.easeOut(duration: 0.24)) {
                    configuration.isOn.toggle()
                }
            }
        } label: {
            Group {
                if showsLabel {
                    HStack(spacing: compact ? 8 : 10) {
                        configuration.label
                        Spacer(minLength: 6)
                        track(isOn: configuration.isOn)
                    }
                } else {
                    track(isOn: configuration.isOn)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
        .accessibilityHint("Toggles this setting")
    }

    private func track(isOn: Bool) -> some View {
        let trackShape = QwixitControlShape(cut: compact ? 8 : 9)
        let thumbShape = QwixitControlShape(cut: compact ? 5 : 6)
        let trackWidth: CGFloat = compact ? 66 : 74
        let trackHeight: CGFloat = compact ? 28 : 32
        let thumbWidth: CGFloat = compact ? 23 : 27
        let thumbHeight: CGFloat = compact ? 22 : 26
        let thumbTravel = trackWidth - thumbWidth - 6

        return ZStack {
            trackShape.fill(isOn ? KColor.primaryAction : KColor.surfaceHover)

            ZStack {
                Text("ON")
                    .foregroundStyle(KColor.success)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(isOn ? 1 : 0)

                Text("OFF")
                    .foregroundStyle(KColor.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .opacity(isOn ? 0 : 1)
            }
            .font(.system(size: compact ? 8.5 : 9.5, weight: .black, design: .monospaced))
            .tracking(0.55)
            .padding(.horizontal, compact ? 8 : 9)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: isOn)

            thumbShape
                .fill(KColor.surface)
                .overlay {
                    thumbShape.stroke(
                        isOn ? KColor.success.opacity(0.92) : KColor.line,
                        lineWidth: 1
                    )
                }
                .overlay {
                    ZStack {
                        TokiriUI.Icon(.check, size: compact ? 13 : 14)
                            .foregroundStyle(KColor.success)
                            .opacity(isOn ? 1 : 0)

                        TokiriUI.Icon(.minus, size: compact ? 13 : 14)
                            .foregroundStyle(KColor.secondary)
                            .opacity(isOn ? 0 : 1)
                    }
                    .frame(width: compact ? 13 : 14, height: compact ? 13 : 14)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: isOn)
                }
                .shadow(
                    color: isOn ? KColor.success.opacity(0.34) : KColor.cardShadow,
                    radius: isHovering ? 5 : 3,
                    y: 1
                )
                .frame(width: thumbWidth, height: thumbHeight)
                .offset(x: isOn ? thumbTravel : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: isOn)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(3)
        }
        .frame(width: trackWidth, height: trackHeight)
        .clipShape(trackShape)
        .overlay {
            trackShape.stroke(
                isOn
                    ? KColor.success.opacity(isHovering ? 1 : 0.92)
                    : isHovering ? KColor.secondary : KColor.line,
                lineWidth: 1
            )
        }
        .shadow(
            color: isOn ? KColor.success.opacity(0.24) : .clear,
            radius: isHovering ? 6 : 3,
            y: 2
        )
        .tokiriElectricTrace(in: trackShape, on: isOn, accent: KColor.success)
        .onHover { isHovering = isEnabled && $0 }
        .accessibilityHidden(true)
    }
}

/// Branded two-way selector for the app's explicit Light/Dark appearance.
///
/// This intentionally keeps segmented-control semantics instead of presenting
/// a boolean switch: the current theme remains visible at a glance.
struct QwixitThemePicker: View {
    @Binding var selection: AppAppearance

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedAppearance: AppAppearance?

    var body: some View {
        HStack(spacing: 3) {
            ForEach(AppAppearance.allCases) { appearance in
                option(appearance)
            }
        }
        .padding(3)
        .frame(width: 164, height: 36)
        .background(QwixitControlShape(cut: 9).fill(KColor.surfaceHover))
        .overlay {
            QwixitControlShape(cut: 9).stroke(KColor.line, lineWidth: 1)
        }
        .clipShape(QwixitControlShape(cut: 9))
        .animation(
            reduceMotion ? nil : .snappy(duration: 0.14),
            value: selection
        )
        .onMoveCommand { direction in
            switch direction {
            case .left:
                choose(.light)
            case .right:
                choose(.dark)
            default:
                break
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func option(_ appearance: AppAppearance) -> some View {
        let isSelected = selection == appearance
        let isFocused = focusedAppearance == appearance

        return Button {
            choose(appearance)
        } label: {
            HStack(spacing: 5) {
                TokiriUI.Icon(appearance == .light ? .themeLight : .themeDark, size: 13)
                Text(appearance.title)
                    .font(.system(size: 10.5, weight: .bold))
            }
            .foregroundStyle(isSelected ? .white : KColor.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if isSelected {
                    QwixitControlShape(cut: 5)
                        .fill(KColor.violet)
                        .shadow(color: KColor.violet.opacity(0.25), radius: 4, y: 2)
                }
            }
            .overlay {
                if isFocused {
                    QwixitControlShape(cut: 5)
                        .stroke(KColor.violet, lineWidth: 1.5)
                }
            }
            .tokiriElectricTrace(
                in: QwixitControlShape(cut: 5),
                on: isSelected,
                when: isSelected,
                accent: KColor.cyan
            )
            .contentShape(QwixitControlShape(cut: 5))
        }
        .buttonStyle(.plain)
        .focused($focusedAppearance, equals: appearance)
        .accessibilityLabel(appearance.title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func choose(_ appearance: AppAppearance) {
        guard selection != appearance else { return }
        if reduceMotion {
            selection = appearance
        } else {
            withAnimation(.snappy(duration: 0.14)) {
                selection = appearance
            }
        }
    }
}

/// A compact radio option for mutually exclusive settings.
///
/// Use a vertical group of options for three or more choices. For two short,
/// equal-weight choices such as Light/Dark, prefer the segmented theme picker.
struct QwixitRadioOption<Selection: Hashable>: View {
    let title: String
    let value: Selection
    @Binding var selection: Selection

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    private var isSelected: Bool { selection == value }

    var body: some View {
        Button {
            guard isEnabled, !isSelected else { return }
            if reduceMotion {
                selection = value
            } else {
                withAnimation(.snappy(duration: 0.12)) {
                    selection = value
                }
            }
        } label: {
            HStack(spacing: 8) {
                indicator
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(KColor.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 30)
            .background(
                isHovering ? KColor.surfaceHover : Color.clear,
                in: QwixitControlShape(cut: 4)
            )
            .overlay {
                if isHovering {
                    QwixitControlShape(cut: 4)
                        .stroke(KColor.line, lineWidth: 1)
                }
            }
            .contentShape(QwixitControlShape(cut: 4))
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { isHovering = isEnabled && $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var indicator: some View {
        Circle()
            .fill(KColor.surface)
            .frame(width: 17, height: 17)
            .overlay {
                Circle()
                    .stroke(isSelected ? KColor.violet : KColor.line, lineWidth: isSelected ? 1.5 : 1)
            }
            .overlay {
                if isSelected {
                    Circle()
                        .fill(KColor.violet)
                        .frame(width: 7, height: 7)
                }
            }
            .shadow(
                color: isSelected ? KColor.violet.opacity(0.2) : .clear,
                radius: isHovering ? 4 : 2,
                y: 1
            )
            .tokiriElectricTrace(in: Circle(), on: isSelected, when: isSelected, accent: KColor.violet)
    }
}

enum TokiriButtonAppearance: Equatable {
    case filled
    case soft
    case ghost
}

struct PrimaryButtonStyle: ButtonStyle {
    var compact = false
    var appearance: TokiriButtonAppearance = .filled

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = QwixitControlShape(cut: compact ? 4 : 6)
        let softBorder = LinearGradient(
            colors: [KColor.cyan, KColor.violet, KColor.magenta],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        configuration.label
            .font(.system(size: compact ? 10 : 11.5, weight: .heavy, design: .rounded))
            .foregroundStyle(appearance == .filled ? Color.white : KColor.violet)
            .padding(.horizontal, compact ? 12 : 14)
            .frame(minHeight: compact ? 28 : 32)
            .background {
                if appearance == .filled {
                    shape.fill(KColor.cyan).offset(x: -1.5, y: 1)
                    shape.fill(KColor.magenta).offset(x: 1.5, y: -1)
                    shape.fill(isHovering ? KColor.primaryActionHover : KColor.primaryAction)
                } else {
                    shape.fill(appearance == .ghost
                        ? (isHovering ? KColor.violet.opacity(0.08) : Color.clear)
                        : KColor.violet.opacity(isHovering ? 0.12 : 0.055))
                }
            }
            .overlay {
                if appearance == .filled {
                    shape.stroke(KColor.violet.opacity(0.9), lineWidth: 1)
                } else if appearance == .soft {
                    shape.stroke(softBorder, lineWidth: 1)
                } else {
                    shape.stroke(KColor.violet.opacity(isHovering ? 0.55 : 0), lineWidth: 1)
                }
            }
            .overlay(alignment: .topLeading) {
                Rectangle()
                    .fill(appearance == .ghost && !isHovering ? Color.clear : appearance == .filled ? Color.white.opacity(0.72) : KColor.violet.opacity(0.7))
                    .frame(width: compact ? 12 : 15, height: 1)
                    .offset(x: compact ? 7 : 9, y: compact ? 4 : 5)
            }
            .tokiriElectricTrace(
                in: shape,
                on: configuration.isPressed,
                when: configuration.isPressed,
                accent: KColor.cyan,
                prominent: appearance == .filled
            )
            .shadow(color: KColor.violet.opacity(appearance == .filled
                ? (isHovering ? (colorScheme == .dark ? 0.24 : 0.16) : 0.12)
                : appearance == .soft ? (isHovering ? 0.10 : 0.04) : 0),
                radius: isHovering ? (compact ? 6 : 8) : (compact ? 4 : 5), y: compact ? 2 : 3)
            .opacity(isEnabled ? (configuration.isPressed ? 0.86 : 1) : 0.45)
            .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? (compact ? 0.97 : 0.96) : isHovering ? (compact ? 1.015 : 1.025) : 1)
            .offset(y: reduceMotion ? 0 : configuration.isPressed ? (compact ? 1 : 2) : 0)
            .animation(reduceMotion ? nil : .snappy(duration: 0.14), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHovering)
            .onHover { isHovering = isEnabled && $0 }
    }
}

struct QuitButtonStyle: ButtonStyle {
    var compact = false
    var appearance: TokiriButtonAppearance = .soft

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var cut: CGFloat { compact ? 4 : 6 }

    func makeBody(configuration: Configuration) -> some View {
        let isFilled = appearance == .filled
        let shape = QwixitControlShape(cut: cut)
        let border = LinearGradient(
            colors: [KColor.quitBorderStart, KColor.quitBorderMiddle, KColor.quitBorderEnd]
                .map { $0.opacity(isFilled ? 1 : 0.8) },
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        configuration.label
            .font(.system(size: compact ? 10 : 11.5, weight: .heavy, design: .rounded))
            .foregroundStyle(isFilled ? Color.white : KColor.danger)
            .padding(.horizontal, compact ? 12 : 14)
            .frame(minHeight: compact ? 28 : 32)
            .background {
                shape.fill(isFilled
                    ? (isHovering ? KColor.quitFillHover : KColor.quitFill)
                    : KColor.danger.opacity(isHovering ? 0.11 : 0.05))
            }
            .overlay { shape.stroke(border, lineWidth: isFilled ? 1.5 : 1) }
            .overlay(alignment: .topLeading) {
                Rectangle()
                    .fill(isFilled ? Color.white : KColor.quitBorderStart)
                    .frame(width: compact ? 12 : 15, height: 1)
                    .offset(x: compact ? 7 : 9, y: compact ? 4 : 5)
            }
            .tokiriElectricTrace(
                in: shape,
                on: configuration.isPressed,
                when: configuration.isPressed,
                accent: KColor.quitBorderEnd
            )
            .contentShape(shape)
            .opacity(isEnabled ? (configuration.isPressed ? 0.86 : 1) : 0.45)
            .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? 0.97 : 1)
            .offset(y: reduceMotion ? 0 : configuration.isPressed ? 1 : 0)
            .animation(reduceMotion ? nil : .snappy(duration: 0.14), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHovering)
            .onHover { isHovering = isEnabled && $0 }
    }
}

struct SubtleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
            .foregroundStyle(isHovering ? KColor.violet : KColor.ink)
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
            .background(configuration.isPressed ? KColor.violet.opacity(0.15) : isHovering ? KColor.violet.opacity(0.08) : KColor.surface, in: QwixitControlShape(cut: 5))
            .overlay {
                QwixitControlShape(cut: 5)
                    .stroke(isHovering ? KColor.violet.opacity(0.7) : KColor.line, lineWidth: 1)
            }
            .tokiriElectricTrace(in: QwixitControlShape(cut: 5), on: configuration.isPressed, when: configuration.isPressed, accent: KColor.violet)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? 0.97 : 1)
            .offset(y: reduceMotion ? 0 : configuration.isPressed ? 1 : 0)
            .animation(reduceMotion ? nil : .snappy(duration: 0.14), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHovering)
            .onHover { isHovering = isEnabled && $0 }
    }
}

struct CompactButtonStyle: ButtonStyle {
    let accent: Color
    var isSelected = false
    var prominent = false

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(prominent ? Color.white : isSelected || isHovering ? KColor.ink : accent)
            .padding(.horizontal, 8)
            .frame(minHeight: 24)
            .background(
                prominent
                    ? accent.opacity(configuration.isPressed ? 0.78 : 1)
                    : accent.opacity(configuration.isPressed ? 0.22 : isSelected ? 0.17 : isHovering ? 0.10 : 0.05),
                in: QwixitControlShape(cut: 4)
            )
            .overlay {
                QwixitControlShape(cut: 4)
                    .stroke(accent.opacity(isSelected || isHovering || prominent ? 0.82 : 0.52), lineWidth: 1)
            }
            .tokiriElectricTrace(in: QwixitControlShape(cut: 4), on: configuration.isPressed, when: configuration.isPressed, accent: accent)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? 0.96 : 1)
            .offset(y: reduceMotion ? 0 : configuration.isPressed ? 1 : 0)
            .animation(reduceMotion ? nil : .snappy(duration: 0.13), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovering)
            .onHover { isHovering = isEnabled && $0 }
    }
}

struct SelectionButtonStyle: ButtonStyle {
    let accent: Color
    let isSelected: Bool
    var cut: CGFloat = 6

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                accent.opacity(configuration.isPressed ? 0.18 : isSelected ? 0.13 : isHovering ? 0.06 : 0),
                in: QwixitControlShape(cut: cut)
            )
            .overlay {
                QwixitControlShape(cut: cut)
                    .stroke(
                        isSelected ? accent.opacity(0.74) : isHovering ? accent.opacity(0.45) : KColor.line.opacity(0.48),
                        lineWidth: 1
                    )
            }
            .tokiriElectricTrace(in: QwixitControlShape(cut: cut), on: configuration.isPressed, when: configuration.isPressed, accent: accent)
            .contentShape(QwixitControlShape(cut: cut))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? 0.985 : 1)
            .animation(reduceMotion ? nil : .snappy(duration: 0.13), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovering)
            .onHover { isHovering = isEnabled && $0 }
    }
}

enum QwixitCardAccent {
    case language(String)
    case slack
    case formal
    case single(Color)

    var colors: [Color] {
        switch self {
        case .language("uk"):
            [
                Color(red: 0.12, green: 0.55, blue: 0.88),
                Color(red: 0.96, green: 0.78, blue: 0.20)
            ]
        case .language("pl"):
            [
                Color(red: 0.79, green: 0.80, blue: 0.85),
                Color(red: 0.86, green: 0.20, blue: 0.32)
            ]
        case .language("fr"):
            [
                Color(red: 0.20, green: 0.39, blue: 0.76),
                Color(red: 0.79, green: 0.80, blue: 0.85),
                Color(red: 0.84, green: 0.20, blue: 0.31)
            ]
        case .language("en"):
            [
                Color(red: 0.20, green: 0.39, blue: 0.76),
                Color(red: 0.84, green: 0.20, blue: 0.31)
            ]
        case .slack:
            [
                Color(red: 0.22, green: 0.77, blue: 0.74),
                Color(red: 0.93, green: 0.69, blue: 0.18),
                Color(red: 0.88, green: 0.25, blue: 0.42),
                Color(red: 0.20, green: 0.68, blue: 0.43)
            ]
        case .formal:
            [KColor.line, KColor.violet]
        case .single(let color):
            [color]
        case .language:
            [KColor.cyan]
        }
    }
}

struct QwixitSemanticCardButtonStyle: ButtonStyle {
    let accent: QwixitCardAccent
    let isSelected: Bool
    var cut: CGFloat = 8

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var colors: [Color] { accent.colors }
    private var primary: Color { colors.first ?? KColor.violet }
    private var border: LinearGradient {
        LinearGradient(
            colors: colors.count > 1 ? colors : [primary, primary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                primary.opacity(configuration.isPressed ? 0.16 : isSelected ? 0.10 : isHovering ? 0.045 : 0),
                in: QwixitControlShape(cut: cut)
            )
            .overlay {
                QwixitControlShape(cut: cut)
                    .stroke(
                        border.opacity(isSelected ? 0.82 : isHovering ? 0.58 : 0.34),
                        lineWidth: 1
                    )
            }
            .tokiriElectricTrace(in: QwixitControlShape(cut: cut), on: configuration.isPressed, when: configuration.isPressed, accent: primary)
            .contentShape(QwixitControlShape(cut: cut))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? 0.985 : 1)
            .animation(reduceMotion ? nil : .snappy(duration: 0.13), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovering)
            .onHover { isHovering = isEnabled && $0 }
    }
}

struct QwixitSemanticCompactButtonStyle: ButtonStyle {
    let accent: QwixitCardAccent
    var isSelected = false

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var colors: [Color] { accent.colors }
    private var primary: Color { colors.first ?? KColor.violet }
    private var border: LinearGradient {
        LinearGradient(
            colors: colors.count > 1 ? colors : [primary, primary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(isSelected || isHovering ? KColor.ink : primary)
            .padding(.horizontal, 8)
            .frame(minHeight: 24)
            .background(
                primary.opacity(configuration.isPressed ? 0.20 : isSelected ? 0.14 : isHovering ? 0.08 : 0.035),
                in: QwixitControlShape(cut: 4)
            )
            .overlay {
                QwixitControlShape(cut: 4)
                    .stroke(
                        border.opacity(isSelected ? 0.82 : isHovering ? 0.60 : 0.40),
                        lineWidth: 1
                    )
            }
            .tokiriElectricTrace(in: QwixitControlShape(cut: 4), on: configuration.isPressed, when: configuration.isPressed, accent: primary)
            .contentShape(QwixitControlShape(cut: 4))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? 0.96 : 1)
            .offset(y: reduceMotion ? 0 : configuration.isPressed ? 1 : 0)
            .animation(reduceMotion ? nil : .snappy(duration: 0.13), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovering)
            .onHover { isHovering = isEnabled && $0 }
    }
}

struct IconButtonStyle: ButtonStyle {
    var accent = KColor.secondary
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(isHovering ? KColor.ink : accent)
            .frame(width: 24, height: 24)
            .background(configuration.isPressed ? accent.opacity(0.20) : isHovering ? accent.opacity(0.12) : KColor.surfaceHover, in: QwixitControlShape(cut: 5))
            .overlay { QwixitControlShape(cut: 5).stroke(isHovering ? accent.opacity(0.65) : KColor.line) }
            .tokiriElectricTrace(in: QwixitControlShape(cut: 5), on: configuration.isPressed, when: configuration.isPressed, accent: accent)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? 0.92 : 1)
            .animation(reduceMotion ? nil : .snappy(duration: 0.13), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovering)
            .onHover { isHovering = isEnabled && $0 }
    }
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(KColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(KColor.line))
            .shadow(color: KColor.cardShadow, radius: 12, y: 5)
    }
}

extension View {
    func kCard() -> some View { modifier(CardModifier()) }
}
