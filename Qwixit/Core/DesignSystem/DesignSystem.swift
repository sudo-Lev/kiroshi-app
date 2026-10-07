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
    static let line = adaptive(light: rgb(0.875, 0.855, 0.925), dark: rgb(0.25, 0.215, 0.315))
    static let violet = adaptive(light: rgb(0.427, 0.157, 1), dark: rgb(0.59, 0.38, 1))
    static let magenta = adaptive(light: rgb(1, 0.176, 0.608), dark: rgb(1, 0.31, 0.68))
    static let cyan = adaptive(light: rgb(0, 0.67, 0.78), dark: rgb(0.15, 0.79, 0.89))
    static let success = adaptive(light: rgb(0.08, 0.57, 0.27), dark: rgb(0.27, 0.78, 0.44))
    static let terminalGreen = adaptive(light: rgb(0.08, 0.62, 0.29), dark: rgb(0.28, 0.9, 0.49))
    static let warning = adaptive(light: rgb(0.82, 0.45, 0.03), dark: rgb(0.98, 0.65, 0.16))
    static let danger = adaptive(light: rgb(0.9, 0.16, 0.24), dark: rgb(1, 0.37, 0.43))
    static let receipt = adaptive(light: rgb(0.953, 0.945, 0.969), dark: rgb(0.12, 0.101, 0.151))

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
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
    static func title(for message: String) -> String {
        let normalized = message.lowercased()
        if normalized.contains("replace") || normalized.contains("text change") {
            return "Couldn’t replace the text"
        }
        if normalized.contains("no text") || normalized.contains("empty") {
            return "No text came back"
        }
        if normalized.contains("unreadable") || normalized.contains("decode") {
            return "The reply couldn’t be read"
        }
        if normalized.contains("permission") || normalized.contains("accessibility") {
            return "Qwixit needs access"
        }
        if normalized.contains("service") || normalized.contains("server") || normalized.contains("status") {
            return "The service couldn’t finish that"
        }
        return "Couldn’t finish that"
    }
}

enum QwixitFace: Int, CaseIterable {
    case hello, boot, ready, pay, broke, empty, upsell, lost, retry, idle, scanning

    var open: String {
        switch self {
        case .hello: "^_^"
        case .boot: "o_o"
        case .ready: "^_-"
        case .pay: "^o^"
        case .broke: "$_00_$"
        case .empty: "x_x"
        case .upsell: "¬_¬"
        case .lost: "?_?"
        case .retry: "@_@"
        case .idle: "#_#"
        case .scanning: "¬_¬"
        }
    }

    var shut: String {
        switch self {
        case .broke: "-_00_-"
        default: "-_-"
        }
    }

    var line: String {
        switch self {
        case .hello: "hi. select text, press ⌥⌘X."
        case .boot: "first launch. permissions?"
        case .ready: "ready. go fix something."
        case .pay: "wow — 30 actions already!\nlooks like we clicked."
        case .broke: "out of tokens."
        case .empty: "30 / 30 used."
        case .upsell: "unlimited. $10/mo."
        case .lost: "no signal."
        case .retry: "reconnecting…"
        case .idle: "offline. waiting for wi-fi."
        case .scanning: "scanning…"
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
            if size >= 13 {
                glyph.foregroundStyle(KColor.cyan).offset(x: -split)
                glyph.foregroundStyle(KColor.magenta).offset(x: split)
            }
            glyph.foregroundStyle(color)
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(face == .scanning ? "Scanning" : face.text(closed: false, bracketed: bracketed))
        .task(id: AnimationID(face: face, reduceMotion: reduceMotion)) {
            closed = false
            scanningFrame = 0
            guard !reduceMotion else { return }
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
            .accessibilityLabel("Qwixit")
    }

    private var assetName: String {
        switch style {
        case .automatic: colorScheme == .dark ? "QwixitLockupDark" : "QwixitLockupLight"
        case .light: "QwixitLockupLight"
        case .dark: "QwixitLockupDark"
        }
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

struct ShortcutKeys: View {
    var body: some View {
        ShortcutBadge(modifiers: ["⌥", "⌘"], key: "X")
    }
}

struct ShortcutBadge: View {
    let modifiers: [String]
    let key: String

    var body: some View {
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((modifiers + [key]).joined(separator: " "))
    }
}

struct AccessStatusBadge: View {
    let granted: Bool
    var compact = false

    private var color: Color { granted ? KColor.success : KColor.warning }

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: compact ? 9 : 10, weight: .bold))
            Text(granted ? "Access" : "No access")
                .font(.system(size: compact ? 7.5 : 9, weight: .bold, design: .monospaced))
                .tracking(compact ? 0 : 0.2)
        }
        .foregroundStyle(color)
        .padding(.horizontal, compact ? 6 : 9)
        .frame(height: compact ? 24 : 28)
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

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(minHeight: 32)
            .background {
                QwixitControlShape(cut: 6).fill(KColor.cyan).offset(x: -1.5, y: 1)
                QwixitControlShape(cut: 6).fill(KColor.magenta).offset(x: 1.5, y: -1)
                QwixitControlShape(cut: 6).fill(isHovering ? KColor.violet : KColor.ink)
            }
            .overlay { QwixitControlShape(cut: 6).stroke(KColor.violet.opacity(0.9), lineWidth: 1) }
            .overlay(alignment: .topLeading) {
                Rectangle().fill(.white.opacity(0.72)).frame(width: 15, height: 1).offset(x: 9, y: 5)
            }
            .shadow(color: KColor.violet.opacity(isHovering ? 0.22 : 0.12), radius: isHovering ? 8 : 5, y: 3)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.96 : isHovering ? 1.025 : 1)
            .offset(y: configuration.isPressed ? 2 : 0)
            .animation(.snappy(duration: 0.14), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.16), value: isHovering)
            .onHover { isHovering = isEnabled && $0 }
    }
}

struct SubtleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
            .foregroundStyle(isHovering ? KColor.violet : KColor.ink)
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
            .background(isHovering ? KColor.violet.opacity(0.08) : KColor.surface, in: QwixitControlShape(cut: 5))
            .overlay {
                QwixitControlShape(cut: 5)
                    .stroke(isHovering ? KColor.violet.opacity(0.7) : KColor.line, lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.snappy(duration: 0.14), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.16), value: isHovering)
            .onHover { isHovering = isEnabled && $0 }
    }
}

struct CompactButtonStyle: ButtonStyle {
    let accent: Color
    var isSelected = false
    var prominent = false

    @Environment(\.isEnabled) private var isEnabled
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
                    : accent.opacity(isSelected ? 0.17 : isHovering ? 0.10 : 0.05),
                in: QwixitControlShape(cut: 4)
            )
            .overlay {
                QwixitControlShape(cut: 4)
                    .stroke(accent.opacity(isSelected || isHovering || prominent ? 0.82 : 0.52), lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.snappy(duration: 0.13), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.14), value: isHovering)
            .onHover { isHovering = isEnabled && $0 }
    }
}

struct SelectionButtonStyle: ButtonStyle {
    let accent: Color
    let isSelected: Bool
    var cut: CGFloat = 6

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                accent.opacity(isSelected ? 0.13 : isHovering ? 0.06 : 0),
                in: QwixitControlShape(cut: cut)
            )
            .overlay {
                QwixitControlShape(cut: cut)
                    .stroke(
                        isSelected ? accent.opacity(0.74) : isHovering ? accent.opacity(0.45) : KColor.line.opacity(0.48),
                        lineWidth: 1
                    )
            }
            .contentShape(QwixitControlShape(cut: cut))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.snappy(duration: 0.13), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.14), value: isHovering)
            .onHover { isHovering = isEnabled && $0 }
    }
}

struct IconButtonStyle: ButtonStyle {
    var accent = KColor.secondary
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(isHovering ? KColor.ink : accent)
            .frame(width: 24, height: 24)
            .background(isHovering ? accent.opacity(0.12) : KColor.surfaceHover, in: QwixitControlShape(cut: 5))
            .overlay { QwixitControlShape(cut: 5).stroke(isHovering ? accent.opacity(0.65) : KColor.line) }
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.snappy(duration: 0.13), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.14), value: isHovering)
            .onHover { isHovering = $0 }
    }
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(KColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(KColor.line))
            .shadow(color: KColor.violet.opacity(0.08), radius: 12, y: 5)
    }
}

extension View {
    func kCard() -> some View { modifier(CardModifier()) }
}
