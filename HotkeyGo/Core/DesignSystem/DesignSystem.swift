import SwiftUI
import AppKit
import Combine

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

enum HotkeyGoColor {
    static let ink = adaptive(light: rgb(0.086, 0.075, 0.122), dark: rgb(0.945, 0.93, 0.98))
    static let secondary = adaptive(light: rgb(0.43, 0.42, 0.49), dark: rgb(0.69, 0.67, 0.75))
    static let canvas = adaptive(light: rgb(0.975, 0.973, 0.988), dark: rgb(0.047, 0.039, 0.071))
    static let canvasRaised = adaptive(light: rgb(0.992, 0.99, 1), dark: rgb(0.07, 0.059, 0.098))
    static let surface = adaptive(light: .white, dark: rgb(0.09, 0.078, 0.122))
    static let surfaceHover = adaptive(light: rgb(0.965, 0.955, 0.992), dark: rgb(0.145, 0.122, 0.19))
    static let line = adaptive(light: hex(0xDCDBE2), dark: hex(0x34323C))
    static let tile = adaptive(light: hex(0xEEE8FF), dark: hex(0x241C38))
    static let popupBorder = adaptive(light: hex(0xD6D4DE), dark: hex(0x34323C))
    static let popupDivider = adaptive(light: hex(0xECEBF0), dark: hex(0x34323C))
    static let popupMuted = adaptive(light: hex(0x9A97A8), dark: rgb(0.69, 0.67, 0.75))
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
    static let planOrange = adaptive(light: hex(0xD17308), dark: hex(0xFAA629))
    static let planGreen = adaptive(light: hex(0x149E4A), dark: hex(0x47E67D))
    static let planSegmentEmpty = adaptive(light: hex(0xE3E2E8), dark: hex(0x34323C))
    static let planMenuSurface = adaptive(light: hex(0xFDFCFF), dark: hex(0x16131F))
    static let planButtonFill = adaptive(light: hex(0x16131F), dark: hex(0x4B22B8))
    static let planViolet = Color(nsColor: hex(0x6D28FF))
    static let planButtonCyan = Color(nsColor: hex(0x00ABC7))
    static let planCyan = adaptive(light: hex(0x00C2E0), dark: hex(0x26C9E3))
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
    var colorScheme: ColorScheme? {
        switch self {
        case .auto: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

private struct HotkeyGoThemeModifier: ViewModifier {
    @AppStorage(AppPreferenceKey.appearance) private var rawAppearance = AppAppearance.auto.rawValue

    func body(content: Content) -> some View {
        let appearance = AppAppearance(rawValue: rawAppearance) ?? .auto
        content
            .preferredColorScheme(appearance.colorScheme)
            .background(HotkeyGoWindowAppearanceBridge(appearance: appearance))
    }
}

private struct HotkeyGoWindowAppearanceBridge: NSViewRepresentable {
    let appearance: AppAppearance

    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ view: NSView, context: Context) {
        let name: NSAppearance.Name? = switch appearance {
        case .auto: nil
        case .light: .aqua
        case .dark: .darkAqua
        }
        guard view.window?.appearance?.name != name else { return }
        DispatchQueue.main.async {
            view.window?.appearance = name.flatMap { NSAppearance(named: $0) }
        }
    }
}

extension View {
    func hotkeygoTheme() -> some View { modifier(HotkeyGoThemeModifier()) }

    func hotkeygoPanel(cornerRadius: CGFloat = 14, accent: Color? = nil) -> some View {
        modifier(HotkeyGoPanelModifier(cornerRadius: cornerRadius, accent: accent))
    }

    func hotkeygoPopupPanel() -> some View { modifier(HotkeyGoPopupPanelModifier()) }

    /// `onChange` that still runs on macOS 13, where only the single-value form exists.
    @ViewBuilder
    func onValueChange<V: Equatable>(of value: V, perform action: @escaping (V) -> Void) -> some View {
        if #available(macOS 14.0, *) {
            onChange(of: value) { _, newValue in action(newValue) }
        } else {
            onChange(of: value, perform: action)
        }
    }
}

private struct HotkeyGoPopupPanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        let shape = HotkeyGoControlShape(cut: 12)
        content
            .background(HotkeyGoColor.surface)
            .clipShape(shape)
            .overlay {
                HotkeyGoControlShape(cut: 11.5)
                    .stroke(HotkeyGoColor.popupBorder, lineWidth: 1)
                    .padding(0.5)
            }
    }
}

private struct HotkeyGoPanelModifier: ViewModifier {
    let cornerRadius: CGFloat
    let accent: Color?

    func body(content: Content) -> some View {
        content
            .background(HotkeyGoColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(HotkeyGoColor.line, lineWidth: 1)
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

enum HotkeyGoErrorCopy {
    enum Kind {
        case tooLong
        case rejected
        case dailyLimit
        case monthlyLimit
        case rateLimited
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
        if normalized.hasPrefix("too long") { return .tooLong }
        if normalized.contains("didn’t pass") { return .rejected }
        if normalized.hasPrefix("daily limit") { return .dailyLimit }
        if normalized.hasPrefix("monthly limit") { return .monthlyLimit }
        if normalized.hasPrefix("slow down") { return .rateLimited }
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
        case .tooLong:
            return "Selection is too long"
        case .rejected:
            return "Result didn’t pass checks"
        case .dailyLimit:
            return "Today’s limit reached"
        case .monthlyLimit:
            return "This month’s limit reached"
        case .rateLimited:
            return "Slow down a bit"
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
            return "hotkeygo needs access"
        case .service:
            return "The service couldn’t finish that"
        case .unknown:
            return "Couldn’t finish that"
        }
    }

    static func headline(for message: String) -> String {
        switch kind(for: message) {
        case .tooLong: "TOO LONG"
        case .rejected: "NOT REPLACED"
        case .dailyLimit: "DAILY LIMIT"
        case .monthlyLimit: "MONTHLY LIMIT"
        case .rateLimited: "SLOW DOWN"
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

enum HotkeyGoFace: Int, CaseIterable {
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
        case .advanced: "⌐■_■"
        case .lost: "?_?"
        case .retry: ">_<"
        case .idle: "#_#"
        case .scanning: "¬_¬"
        }
    }

    var shut: String {
        switch self {
        case .broke: "-_00_-"
        case .advanced: "⌐■_■"
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

struct HotkeyGoFaceView: View {
    private struct AnimationID: Hashable {
        let face: HotkeyGoFace
        let reduceMotion: Bool
        let shouldBlink: Bool
    }

    let face: HotkeyGoFace
    var size: CGFloat = 15
    var bracketed = true
    var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    var color = HotkeyGoColor.ink
    var stagger = 0
    var chromaticSplit: CGFloat = 0
    var shouldBlink = true

    @Environment(\.colorScheme) private var colorScheme

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
            if size >= 13 || chromaticSplit > 0 {
                glyph.foregroundStyle(HotkeyGoColor.planCyan).offset(x: -split)
                glyph.foregroundStyle(HotkeyGoColor.magenta).offset(x: split)
            }
            glyph.foregroundStyle(color)
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(face == .scanning ? "Scanning" : face.accessibilityLabel(bracketed: bracketed))
        .shadow(
            color: face == .advanced && colorScheme == .dark ? HotkeyGoColor.planGreen.opacity(0.5) : .clear,
            radius: face == .advanced && colorScheme == .dark ? 10 : 0
        )
        .task(id: AnimationID(face: face, reduceMotion: reduceMotion, shouldBlink: shouldBlink)) {
            closed = false
            scanningFrame = 0
            guard shouldBlink, !reduceMotion, face != .advanced else { return }
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

    private var split: CGFloat { chromaticSplit > 0 ? chromaticSplit : 1.5 * size / 18 }
}

struct PlanMeterView: View {
    enum Layout: Equatable {
        case menu
        case settings

        var height: CGFloat { self == .menu ? 9 : 8 }
        var gap: CGFloat { self == .menu ? 2 : 4 }
        var slant: CGFloat { self == .menu ? 3 : 4 }
    }

    let value: PlanMeterValue
    var layout: Layout = .menu

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: layout.gap) {
            ForEach(0..<3, id: \.self) { index in
                ParallelogramShape(slant: layout.slant)
                    .fill(index < value.filled ? toneColor : HotkeyGoColor.planSegmentEmpty)
                    .frame(width: layout == .menu ? 9 : nil, height: layout.height)
                    .frame(maxWidth: layout == .settings ? .infinity : nil)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.2).delay(value.tone == .green ? Double(index) * 0.08 : 0),
                        value: value
                    )
            }
        }
        .frame(maxWidth: layout == .settings ? .infinity : nil)
        .accessibilityHidden(true)
    }

    private var toneColor: Color {
        switch value.tone {
        case .ink: HotkeyGoColor.ink
        case .orange: HotkeyGoColor.planOrange
        case .red: HotkeyGoColor.danger
        case .green: HotkeyGoColor.planGreen
        }
    }
}

struct UsageTicksView: View {
    let used: Int
    let tone: MeterTone

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let gap: CGFloat = 2
            let width = max(0, (geometry.size.width - gap * 29) / 30)
            HStack(spacing: gap) {
                ForEach(0..<30, id: \.self) { index in
                    Rectangle()
                        .fill(index < min(max(used, 0), 30) ? toneColor : HotkeyGoColor.planSegmentEmpty)
                        .frame(width: width, height: 2)
                }
            }
            .animation(reduceMotion ? nil : .easeIn(duration: 0.15), value: used)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: tone)
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }

    private var toneColor: Color {
        switch tone {
        case .ink: HotkeyGoColor.ink
        case .orange: HotkeyGoColor.planOrange
        case .red: HotkeyGoColor.danger
        case .green: HotkeyGoColor.planGreen
        }
    }
}

private struct ParallelogramShape: Shape {
    let slant: CGFloat

    func path(in rect: CGRect) -> Path {
        let cut = min(slant, rect.width / 2)
        return Path { path in
            path.move(to: CGPoint(x: rect.minX + cut, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

struct HotkeyGoPaywallUsageStrip: View {
    let used: Int
    let remaining: Int
    var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    private var clampedUsed: Int { min(max(used, 0), 30) }
    private var clampedRemaining: Int { min(max(remaining, 0), 30) }

    var body: some View {
        HStack(spacing: 10) {
            HotkeyGoFaceView(face: .empty, size: 17, reduceMotion: reduceMotion)

            Text("\(clampedUsed) / 30 used")
                .font(.system(size: 15, weight: .black, design: .monospaced))

            Spacer(minLength: 12)

            Text("\(clampedRemaining) free left")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(HotkeyGoColor.secondary)
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(HotkeyGoColor.canvasRaised)
        .overlay(alignment: .top) { Rectangle().fill(HotkeyGoColor.line).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(HotkeyGoColor.line).frame(height: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(clampedUsed) of 30 free actions used, \(clampedRemaining) free left")
    }
}

struct HotkeyGoWordmark: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(colorScheme == .dark ? "HotkeyGoWordmarkDark" : "HotkeyGoWordmarkLight")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("hotkeygo")
    }
}

struct MonoLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(0.35)
            .foregroundStyle(HotkeyGoColor.secondary)
    }
}

struct Keycap: View {
    let symbol: String
    var active = false

    var body: some View {
        Text(symbol)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(active ? .white : HotkeyGoColor.ink)
            .frame(minWidth: 26, minHeight: 25)
            .padding(.horizontal, 1)
            .background(active ? HotkeyGoColor.violet : HotkeyGoColor.surfaceHover, in: HotkeyGoControlShape(cut: 5))
            .overlay(HotkeyGoControlShape(cut: 5).stroke(active ? HotkeyGoColor.violet : HotkeyGoColor.line))
            .overlay(alignment: .bottom) {
                Rectangle().fill(active ? Color.black.opacity(0.24) : HotkeyGoColor.line).frame(height: 1).padding(.horizontal, 4)
            }
            .clipShape(HotkeyGoControlShape(cut: 5))
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
                .foregroundStyle(HotkeyGoColor.secondary)
            Text(key.uppercased())
                .foregroundStyle(HotkeyGoColor.violet)
        }
        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
        .padding(.horizontal, 7)
        .frame(height: 25)
        .background(HotkeyGoColor.surfaceHover, in: HotkeyGoControlShape(cut: 5))
        .overlay(HotkeyGoControlShape(cut: 5).stroke(HotkeyGoColor.line))
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
    let hint: String

    init(
        modifiers: [String],
        key: String,
        label: String,
        hint: String = "Dismiss this panel",
        action: @escaping () -> Void
    ) {
        self.modifiers = modifiers
        self.key = key
        self.label = label
        self.hint = hint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ShortcutBadge(modifiers: modifiers, key: key)
        }
        .buttonStyle(ShortcutBadgeButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
    }
}

struct ShortcutBadgeButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(HotkeyGoControlShape(cut: 5))
            .overlay {
                HotkeyGoControlShape(cut: 5)
                    .stroke(isHovering ? HotkeyGoColor.violet.opacity(0.72) : .clear, lineWidth: 1)
            }
            .hotkeygoElectricTrace(
                in: HotkeyGoControlShape(cut: 5),
                on: configuration.isPressed,
                when: configuration.isPressed,
                accent: HotkeyGoColor.violet
            )
            .shadow(
                color: HotkeyGoColor.violet.opacity(isHovering ? 0.14 : 0),
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

    private var color: Color { granted ? HotkeyGoColor.success : HotkeyGoColor.warning }

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            HotkeyGoUI.Icon(granted ? .statusSuccess : .statusWarning, size: compact ? 9 : 10)
            if !iconOnly {
                Text(granted ? "Access" : "Access needed")
                    .font(.system(size: compact ? 7.5 : 9, weight: .bold, design: .monospaced))
                    .tracking(compact ? 0 : 0.2)
            }
        }
        .foregroundStyle(color)
        .padding(.horizontal, iconOnly ? 0 : compact ? 6 : 9)
        .frame(width: iconOnly ? (compact ? 24 : 28) : nil, height: compact ? 24 : 28)
        .background(color.opacity(0.09), in: HotkeyGoControlShape(cut: compact ? 4 : 5))
        .overlay(HotkeyGoControlShape(cut: compact ? 4 : 5).stroke(color.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(granted ? "Accessibility access allowed" : "Accessibility access required")
    }
}

struct CutCornerShape: Shape {
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

typealias HotkeyGoControlShape = CutCornerShape

/// A single, self-clearing edge impulse shared by HotkeyGoUI controls. The
/// trimmed strokes collapse to zero at the end, so no timer or looping effect
/// survives an interaction.
private struct HotkeyGoElectricTrace<S: Shape>: View {
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

private struct HotkeyGoElectricTraceModifier<Trigger: Equatable, S: Shape>: ViewModifier {
    let shape: S
    let trigger: Trigger
    let shouldRun: Bool
    let accent: Color
    let prominent: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var impulse = 0

    @ViewBuilder
    func body(content: Content) -> some View {
        // SwiftUI only exposes Dim Flashing Lights on macOS 14+; Reduce Motion still gates the trace on 13.
        if #available(macOS 14.0, *) {
            DimFlashingLightsReader { trace(content, dimFlashingLights: $0) }
        } else {
            trace(content, dimFlashingLights: false)
        }
    }

    private func trace(_ content: Content, dimFlashingLights: Bool) -> some View {
        content
            .overlay {
                if impulse > 0, !reduceMotion, !dimFlashingLights, isEnabled {
                    HotkeyGoElectricTrace(shape: shape, accent: accent, prominent: prominent)
                        .id(impulse)
                }
            }
            .onValueChange(of: trigger) { _ in
                guard shouldRun, isEnabled, !reduceMotion, !dimFlashingLights else { return }
                impulse &+= 1
            }
    }
}

@available(macOS 14.0, *)
private struct DimFlashingLightsReader<Content: View>: View {
    @Environment(\.accessibilityDimFlashingLights) private var dimFlashingLights
    let content: (Bool) -> Content

    var body: some View { content(dimFlashingLights) }
}

private extension View {
    func hotkeygoElectricTrace<Trigger: Equatable, S: Shape>(
        in shape: S,
        on trigger: Trigger,
        when shouldRun: Bool = true,
        accent: Color = HotkeyGoColor.cyan,
        prominent: Bool = false
    ) -> some View {
        modifier(HotkeyGoElectricTraceModifier(
            shape: shape,
            trigger: trigger,
            shouldRun: shouldRun,
            accent: accent,
            prominent: prominent
        ))
    }
}

struct HotkeyGoToggleStyle: ToggleStyle {
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
        let trackShape = HotkeyGoControlShape(cut: compact ? 8 : 9)
        let thumbShape = HotkeyGoControlShape(cut: compact ? 5 : 6)
        let trackWidth: CGFloat = compact ? 66 : 74
        let trackHeight: CGFloat = compact ? 28 : 32
        let thumbWidth: CGFloat = compact ? 23 : 27
        let thumbHeight: CGFloat = compact ? 22 : 26
        let thumbTravel = trackWidth - thumbWidth - 6

        return ZStack {
            trackShape.fill(isOn ? HotkeyGoColor.primaryAction : HotkeyGoColor.surfaceHover)

            ZStack {
                Text("ON")
                    .foregroundStyle(HotkeyGoColor.success)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(isOn ? 1 : 0)

                Text("OFF")
                    .foregroundStyle(HotkeyGoColor.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .opacity(isOn ? 0 : 1)
            }
            .font(.system(size: compact ? 8.5 : 9.5, weight: .black, design: .monospaced))
            .tracking(0.55)
            .padding(.horizontal, compact ? 8 : 9)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: isOn)

            thumbShape
                .fill(HotkeyGoColor.surface)
                .overlay {
                    thumbShape.stroke(
                        isOn ? HotkeyGoColor.success.opacity(0.92) : HotkeyGoColor.line,
                        lineWidth: 1
                    )
                }
                .overlay {
                    ZStack {
                        HotkeyGoUI.Icon(.check, size: compact ? 13 : 14)
                            .foregroundStyle(HotkeyGoColor.success)
                            .opacity(isOn ? 1 : 0)

                        HotkeyGoUI.Icon(.minus, size: compact ? 13 : 14)
                            .foregroundStyle(HotkeyGoColor.secondary)
                            .opacity(isOn ? 0 : 1)
                    }
                    .frame(width: compact ? 13 : 14, height: compact ? 13 : 14)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: isOn)
                }
                .shadow(
                    color: isOn ? HotkeyGoColor.success.opacity(0.34) : HotkeyGoColor.cardShadow,
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
                    ? HotkeyGoColor.success.opacity(isHovering ? 1 : 0.92)
                    : isHovering ? HotkeyGoColor.secondary : HotkeyGoColor.line,
                lineWidth: 1
            )
        }
        .shadow(
            color: isOn ? HotkeyGoColor.success.opacity(0.24) : .clear,
            radius: isHovering ? 6 : 3,
            y: 2
        )
        .hotkeygoElectricTrace(in: trackShape, on: isOn, accent: HotkeyGoColor.success)
        .onHover { isHovering = isEnabled && $0 }
        .accessibilityHidden(true)
    }
}

enum HotkeyGoRadioTileLayout: Equatable {
    case grid(columns: Int)
    case list
}

enum HotkeyGoTileIcon {
    case template(Image)
    case original(Image)
    case initial(String)
}

struct HotkeyGoRadioTileOption<Selection: Hashable>: Identifiable {
    let value: Selection
    let title: String
    let subtitle: String?
    let icon: HotkeyGoTileIcon?
    let preview: AnyView?
    let isDisabled: Bool

    var id: Selection { value }

    init(
        value: Selection,
        title: String,
        subtitle: String? = nil,
        icon: HotkeyGoTileIcon? = nil,
        preview: AnyView? = nil,
        isDisabled: Bool = false
    ) {
        self.value = value
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.preview = preview
        self.isDisabled = isDisabled
    }
}

struct HotkeyGoRadioTileGroup<Selection: Hashable>: View {
    @Binding private var selection: Selection
    let options: [HotkeyGoRadioTileOption<Selection>]
    let layout: HotkeyGoRadioTileLayout
    let label: String
    var glitchEnabled = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedValue: Selection?
    @State private var hoveredValue: Selection?
    @State private var glitchOpacity = 1.0
    @State private var glitchTask: Task<Void, Never>?
    @State private var increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    @AppStorage(AppPreferenceKey.animationsEnabled) private var animationsEnabled = true

    init(
        selection: Binding<Selection>,
        options: [HotkeyGoRadioTileOption<Selection>],
        layout: HotkeyGoRadioTileLayout,
        label: String,
        glitchEnabled: Bool = true
    ) {
        _selection = selection
        self.options = options
        self.layout = layout
        self.label = label
        self.glitchEnabled = glitchEnabled
    }

    private var showsGlitch: Bool {
        glitchEnabled && animationsEnabled && !increaseContrast
    }

    private var shouldReduceMotion: Bool { reduceMotion || !animationsEnabled }

    var body: some View {
        Group {
            switch layout {
            case .grid(let columns):
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: 8),
                        count: max(columns, 1)
                    ),
                    spacing: 8
                ) {
                    ForEach(options) { option in gridOption(option) }
                }
            case .list:
                VStack(spacing: 8) {
                    ForEach(options) { option in listOption(option) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(label))
        .focusSection()
        .onMoveCommand(perform: moveSelection)
        .onValueChange(of: selection) { _ in animateGlitch() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification
        )) { _ in
            increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        }
        .onDisappear { glitchTask?.cancel() }
    }

    private func gridOption(_ option: HotkeyGoRadioTileOption<Selection>) -> some View {
        let valueIsSelected = selection == option.value
        let isSelected = valueIsSelected && !option.isDisabled
        let isHovered = hoveredValue == option.value
        let isFocused = focusedValue == option.value

        return Button {
            select(option.value)
        } label: {
            VStack(spacing: 5) {
                RadioTileSurface(
                    outerCut: 10,
                    innerCut: 9.4,
                    selected: isSelected,
                    hovered: isHovered,
                    disabled: option.isDisabled,
                    focused: isFocused,
                    glitchOpacity: glitchOpacity,
                    showsGlitch: showsGlitch,
                    reduceMotion: shouldReduceMotion,
                    marker: .grid
                ) {
                    (option.preview ?? AnyView(Color.clear))
                }
                .frame(height: 58)

                Text(option.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(titleColor(for: option, selected: isSelected, grid: true))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RadioTileButtonStyle(reduceMotion: shouldReduceMotion))
        .focused($focusedValue, equals: option.value)
        .disabled(option.isDisabled)
        .onHover { updateHover($0, value: option.value) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: option))
        .accessibilityValue(valueIsSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(valueIsSelected ? .isSelected : [])
    }

    private func listOption(_ option: HotkeyGoRadioTileOption<Selection>) -> some View {
        let valueIsSelected = selection == option.value
        let isSelected = valueIsSelected && !option.isDisabled
        let isHovered = hoveredValue == option.value
        let isFocused = focusedValue == option.value

        return Button {
            select(option.value)
        } label: {
            RadioTileSurface(
                outerCut: 9,
                innerCut: 8.4,
                selected: isSelected,
                hovered: isHovered,
                disabled: option.isDisabled,
                focused: isFocused,
                glitchOpacity: glitchOpacity,
                showsGlitch: showsGlitch,
                reduceMotion: shouldReduceMotion,
                marker: .list
            ) {
                HStack(spacing: 12) {
                    if let icon = option.icon {
                        ProviderTileIcon(icon: icon)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(option.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(titleColor(for: option, selected: isSelected, grid: false))
                            .lineLimit(1)
                        if let subtitle = option.subtitle {
                            Text(subtitle)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(HotkeyGoColor.secondary.opacity(option.isDisabled ? 0.6 : 1))
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)
                    Color.clear.frame(width: 18, height: 18)
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(RadioTileButtonStyle(reduceMotion: shouldReduceMotion))
        .focused($focusedValue, equals: option.value)
        .disabled(option.isDisabled)
        .onHover { updateHover($0, value: option.value) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: option))
        .accessibilityValue(valueIsSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(valueIsSelected ? .isSelected : [])
    }

    private func titleColor(
        for option: HotkeyGoRadioTileOption<Selection>,
        selected: Bool,
        grid: Bool
    ) -> Color {
        if option.isDisabled { return HotkeyGoColor.secondary.opacity(0.6) }
        return selected && grid ? HotkeyGoColor.violet : HotkeyGoColor.ink
    }

    private func accessibilityLabel(for option: HotkeyGoRadioTileOption<Selection>) -> String {
        [option.title, option.subtitle].compactMap { $0 }.joined(separator: ", ")
    }

    private func updateHover(_ isHovering: Bool, value: Selection) {
        if isHovering {
            hoveredValue = value
        } else if hoveredValue == value {
            hoveredValue = nil
        }
    }

    private func select(_ value: Selection) {
        guard selection != value else { return }
        if shouldReduceMotion {
            selection = value
        } else {
            withAnimation(.easeOut(duration: 0.15)) { selection = value }
        }
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        let step: Int
        switch (layout, direction) {
        case (.grid, .left), (.list, .up): step = -1
        case (.grid, .right), (.list, .down): step = 1
        default: return
        }

        let enabledOptions = options.filter { !$0.isDisabled }
        guard !enabledOptions.isEmpty else { return }
        let currentValue = focusedValue ?? selection
        let currentIndex = enabledOptions.firstIndex(where: { $0.value == currentValue })
        let startingIndex = currentIndex ?? (step > 0 ? -1 : 0)
        let nextIndex = (startingIndex + step + enabledOptions.count) % enabledOptions.count
        let nextValue = enabledOptions[nextIndex].value
        select(nextValue)
        focusedValue = nextValue
    }

    private func animateGlitch() {
        glitchTask?.cancel()
        guard showsGlitch, !shouldReduceMotion else {
            glitchOpacity = 1
            return
        }

        glitchOpacity = 0
        glitchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(15))
            guard !Task.isCancelled else { return }
            withAnimation(.linear(duration: 0.025)) { glitchOpacity = 1 }
            try? await Task.sleep(for: .milliseconds(30))
            guard !Task.isCancelled else { return }
            withAnimation(.linear(duration: 0.025)) { glitchOpacity = 0.4 }
            try? await Task.sleep(for: .milliseconds(10))
            guard !Task.isCancelled else { return }
            withAnimation(.linear(duration: 0.015)) { glitchOpacity = 1 }
        }
    }
}

private enum RadioTileMarker: Equatable {
    case grid
    case list
}

private struct RadioTileSurface<Content: View>: View {
    let outerCut: CGFloat
    let innerCut: CGFloat
    let selected: Bool
    let hovered: Bool
    let disabled: Bool
    let focused: Bool
    let glitchOpacity: Double
    let showsGlitch: Bool
    let reduceMotion: Bool
    let marker: RadioTileMarker
    let content: Content

    @Environment(\.hotkeyGoRadioTilePressed) private var pressed

    private let borderWidth: CGFloat = 1.5

    init(
        outerCut: CGFloat,
        innerCut: CGFloat,
        selected: Bool,
        hovered: Bool,
        disabled: Bool,
        focused: Bool,
        glitchOpacity: Double,
        showsGlitch: Bool,
        reduceMotion: Bool,
        marker: RadioTileMarker,
        @ViewBuilder content: () -> Content
    ) {
        self.outerCut = outerCut
        self.innerCut = innerCut
        self.selected = selected
        self.hovered = hovered
        self.disabled = disabled
        self.focused = focused
        self.glitchOpacity = glitchOpacity
        self.showsGlitch = showsGlitch
        self.reduceMotion = reduceMotion
        self.marker = marker
        self.content = content()
    }

    var body: some View {
        GeometryReader { geometry in
            let innerSize = CGSize(
                width: max(0, geometry.size.width - borderWidth * 2),
                height: max(0, geometry.size.height - borderWidth * 2)
            )

            ZStack {
                if selected && showsGlitch {
                    CutCornerShape(cut: outerCut)
                        .fill(HotkeyGoColor.cyan.opacity(glitchOpacity))
                        .offset(x: -1)
                    CutCornerShape(cut: outerCut)
                        .fill(HotkeyGoColor.magenta.opacity(glitchOpacity))
                        .offset(x: 1)
                }

                CutCornerShape(cut: outerCut).fill(selected ? HotkeyGoColor.violet : HotkeyGoColor.line)
                if (hovered || pressed) && !selected && !disabled {
                    CutCornerShape(cut: outerCut).fill(HotkeyGoColor.violet.opacity(0.45))
                }
                CutCornerShape(cut: innerCut)
                    .fill(fillColor)
                    .frame(width: innerSize.width, height: innerSize.height)
                content
                    .frame(width: innerSize.width, height: innerSize.height)
                    .clipShape(CutCornerShape(cut: innerCut))

                if selected {
                    CutCornerBevel(corner: marker == .grid ? 15 : 14)
                        .fill(HotkeyGoColor.violet)
                        .frame(width: innerSize.width, height: innerSize.height, alignment: .topLeading)
                        .clipShape(CutCornerShape(cut: innerCut))
                }
                CheckKey()
                    .opacity(selected ? 1 : 0)
                    .scaleEffect(selected ? 1 : 0.4)
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.68),
                        value: selected
                    )
                    .position(checkPosition(in: geometry.size))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: selected)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovered)
        }
        .overlay {
            if focused {
                CutCornerShape(cut: outerCut + 2)
                    .stroke(HotkeyGoColor.violet.opacity(0.35), lineWidth: 2)
                    .padding(-2)
            }
        }
        .accessibilityHidden(true)
    }

    private var fillColor: Color {
        if disabled { return HotkeyGoColor.canvas }
        if selected { return HotkeyGoColor.tile }
        return hovered || pressed ? HotkeyGoColor.surfaceHover : HotkeyGoColor.surface
    }

    private func checkPosition(in size: CGSize) -> CGPoint {
        switch marker {
        case .grid:
            CGPoint(x: size.width - 15, y: size.height - 15)
        case .list:
            CGPoint(x: size.width - 21, y: size.height / 2)
        }
    }
}

private struct CutCornerBevel: Shape {
    let corner: CGFloat

    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: rect.origin)
            path.addLine(to: CGPoint(x: rect.minX + corner, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + corner))
            path.closeSubpath()
        }
    }
}

private struct CheckKey: View {
    var body: some View {
        CutCornerShape(cut: 5)
            .fill(HotkeyGoColor.violet)
            .frame(width: 18, height: 18)
            .overlay {
                CheckKeyMark()
                    .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .frame(width: 9, height: 7)
            }
            .accessibilityHidden(true)
    }
}

private struct CheckKeyMark: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX + rect.width * 0.06, y: rect.minY + rect.height * 0.53))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.37, y: rect.minY + rect.height * 0.84))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.95, y: rect.minY + rect.height * 0.16))
        }
    }
}

private struct ProviderTileIcon: View {
    let icon: HotkeyGoTileIcon

    var body: some View {
        ZStack {
            CutCornerShape(cut: 7).fill(HotkeyGoColor.line)
            CutCornerShape(cut: 6.6).fill(HotkeyGoColor.canvas).padding(1)
            glyph
                .frame(width: 17, height: 17)
        }
        .frame(width: 30, height: 30)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var glyph: some View {
        switch icon {
        case .template(let image):
            image
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(HotkeyGoColor.ink)
        case .original(let image):
            image
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
        case .initial(let value):
            Text(String(value.prefix(1)).uppercased())
                .font(initialFont)
                .foregroundStyle(HotkeyGoColor.secondary)
        }
    }

    private var initialFont: Font {
        if NSFont(name: "JetBrains Mono ExtraBold", size: 11) != nil {
            return .custom("JetBrains Mono ExtraBold", fixedSize: 11)
        }
        return .system(size: 11, weight: .bold, design: .monospaced)
    }
}

private struct RadioTileButtonPressedKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var hotkeyGoRadioTilePressed: Bool {
        get { self[RadioTileButtonPressedKey.self] }
        set { self[RadioTileButtonPressedKey.self] = newValue }
    }
}

private struct RadioTileButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.hotkeyGoRadioTilePressed, configuration.isPressed)
            .offset(y: configuration.isPressed && !reduceMotion ? 1 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

enum HotkeyGoButtonAppearance: Equatable {
    case filled
    case soft
    case ghost
}

struct PrimaryButtonStyle: ButtonStyle {
    var compact = false
    var appearance: HotkeyGoButtonAppearance = .filled

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = HotkeyGoControlShape(cut: compact ? 8 : 6)
        let compactBorder = LinearGradient(
            stops: [
                .init(color: HotkeyGoColor.planButtonCyan, location: 0),
                .init(color: HotkeyGoColor.planViolet, location: 0.3),
                .init(color: HotkeyGoColor.planViolet, location: 0.7),
                .init(color: HotkeyGoColor.magenta, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        let softBorder = LinearGradient(
            colors: [HotkeyGoColor.cyan, HotkeyGoColor.violet, HotkeyGoColor.magenta],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        configuration.label
            .font(.system(size: compact ? 12.5 : 11.5, weight: .bold))
            .foregroundStyle(appearance == .filled ? Color.white : HotkeyGoColor.violet)
            .padding(.horizontal, compact ? 12 : 14)
            .frame(minHeight: compact ? 30 : 32)
            .background {
                if appearance == .filled {
                    if compact {
                        shape.fill(compactBorder)
                            .overlay {
                                HotkeyGoControlShape(cut: 7.4)
                                    .fill(isHovering ? HotkeyGoColor.primaryActionHover : HotkeyGoColor.planButtonFill)
                                    .padding(1.5)
                            }
                    } else {
                        shape.fill(HotkeyGoColor.cyan).offset(x: -1.5, y: 1)
                        shape.fill(HotkeyGoColor.magenta).offset(x: 1.5, y: -1)
                        shape.fill(isHovering ? HotkeyGoColor.primaryActionHover : HotkeyGoColor.primaryAction)
                    }
                } else {
                    shape.fill(appearance == .ghost
                        ? (isHovering ? HotkeyGoColor.violet.opacity(0.08) : Color.clear)
                        : HotkeyGoColor.violet.opacity(isHovering ? 0.12 : 0.055))
                }
            }
            .overlay {
                if appearance == .filled {
                    if !compact { shape.stroke(HotkeyGoColor.violet.opacity(0.9), lineWidth: 1) }
                } else if appearance == .soft {
                    shape.stroke(softBorder, lineWidth: 1)
                } else {
                    shape.stroke(HotkeyGoColor.violet.opacity(isHovering ? 0.55 : 0), lineWidth: 1)
                }
            }
            .overlay(alignment: .topLeading) {
                if compact && appearance == .filled {
                    Rectangle()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 14, height: 1.5)
                        .offset(x: 9, y: 4)
                } else {
                    Rectangle()
                        .fill(appearance == .ghost && !isHovering ? Color.clear : appearance == .filled ? Color.white.opacity(0.72) : HotkeyGoColor.violet.opacity(0.7))
                        .frame(width: compact ? 12 : 15, height: 1)
                        .offset(x: compact ? 7 : 9, y: compact ? 4 : 5)
                }
            }
            .hotkeygoElectricTrace(
                in: shape,
                on: configuration.isPressed,
                when: configuration.isPressed,
                accent: HotkeyGoColor.cyan,
                prominent: appearance == .filled
            )
            .shadow(color: (compact ? HotkeyGoColor.planViolet : HotkeyGoColor.violet).opacity(appearance == .filled
                ? (compact ? 0.25 : isHovering ? (colorScheme == .dark ? 0.24 : 0.16) : 0.12)
                : appearance == .soft ? (isHovering ? 0.10 : 0.04) : 0),
                radius: isHovering ? (compact ? 6 : 8) : (compact ? 6 : 5), y: compact ? 2 : 3)
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
    var appearance: HotkeyGoButtonAppearance = .soft

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var cut: CGFloat { compact ? 4 : 6 }

    func makeBody(configuration: Configuration) -> some View {
        let isFilled = appearance == .filled
        let shape = HotkeyGoControlShape(cut: cut)
        let border = LinearGradient(
            colors: [HotkeyGoColor.quitBorderStart, HotkeyGoColor.quitBorderMiddle, HotkeyGoColor.quitBorderEnd]
                .map { $0.opacity(isFilled ? 1 : 0.8) },
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        configuration.label
            .font(.system(size: compact ? 10 : 11.5, weight: .heavy, design: .rounded))
            .foregroundStyle(isFilled ? Color.white : HotkeyGoColor.danger)
            .padding(.horizontal, compact ? 12 : 14)
            .frame(minHeight: compact ? 28 : 32)
            .background {
                shape.fill(isFilled
                    ? (isHovering ? HotkeyGoColor.quitFillHover : HotkeyGoColor.quitFill)
                    : HotkeyGoColor.danger.opacity(isHovering ? 0.11 : 0.05))
            }
            .overlay { shape.stroke(border, lineWidth: isFilled ? 1.5 : 1) }
            .overlay(alignment: .topLeading) {
                Rectangle()
                    .fill(isFilled ? Color.white : HotkeyGoColor.quitBorderStart)
                    .frame(width: compact ? 12 : 15, height: 1)
                    .offset(x: compact ? 7 : 9, y: compact ? 4 : 5)
            }
            .hotkeygoElectricTrace(
                in: shape,
                on: configuration.isPressed,
                when: configuration.isPressed,
                accent: HotkeyGoColor.quitBorderEnd
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
            .foregroundStyle(isHovering ? HotkeyGoColor.violet : HotkeyGoColor.ink)
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
            .background(configuration.isPressed ? HotkeyGoColor.violet.opacity(0.15) : isHovering ? HotkeyGoColor.violet.opacity(0.08) : HotkeyGoColor.surface, in: HotkeyGoControlShape(cut: 5))
            .overlay {
                HotkeyGoControlShape(cut: 5)
                    .stroke(isHovering ? HotkeyGoColor.violet.opacity(0.7) : HotkeyGoColor.line, lineWidth: 1)
            }
            .hotkeygoElectricTrace(in: HotkeyGoControlShape(cut: 5), on: configuration.isPressed, when: configuration.isPressed, accent: HotkeyGoColor.violet)
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
            .foregroundStyle(prominent ? Color.white : isSelected || isHovering ? HotkeyGoColor.ink : accent)
            .padding(.horizontal, 8)
            .frame(minHeight: 24)
            .background(
                prominent
                    ? accent.opacity(configuration.isPressed ? 0.78 : 1)
                    : accent.opacity(configuration.isPressed ? 0.22 : isSelected ? 0.17 : isHovering ? 0.10 : 0.05),
                in: HotkeyGoControlShape(cut: 4)
            )
            .overlay {
                HotkeyGoControlShape(cut: 4)
                    .stroke(accent.opacity(isSelected || isHovering || prominent ? 0.82 : 0.52), lineWidth: 1)
            }
            .hotkeygoElectricTrace(in: HotkeyGoControlShape(cut: 4), on: configuration.isPressed, when: configuration.isPressed, accent: accent)
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
                in: HotkeyGoControlShape(cut: cut)
            )
            .overlay {
                HotkeyGoControlShape(cut: cut)
                    .stroke(
                        isSelected ? accent.opacity(0.74) : isHovering ? accent.opacity(0.45) : HotkeyGoColor.line.opacity(0.48),
                        lineWidth: 1
                    )
            }
            .hotkeygoElectricTrace(in: HotkeyGoControlShape(cut: cut), on: configuration.isPressed, when: configuration.isPressed, accent: accent)
            .contentShape(HotkeyGoControlShape(cut: cut))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? 0.985 : 1)
            .animation(reduceMotion ? nil : .snappy(duration: 0.13), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovering)
            .onHover { isHovering = isEnabled && $0 }
    }
}

/// The one filled row used by the lighter Actions and Peek pickers.
struct PopupSelectedButtonStyle: ButtonStyle {
    var compact = false

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let cut: CGFloat = compact ? 6 : 8
        let shape = HotkeyGoControlShape(cut: cut)
        let innerShape = HotkeyGoControlShape(cut: cut - 0.6)
        let border = LinearGradient(
            stops: [
                .init(color: HotkeyGoColor.cyan, location: 0),
                .init(color: HotkeyGoColor.violet, location: 0.30),
                .init(color: HotkeyGoColor.violet, location: 0.70),
                .init(color: HotkeyGoColor.magenta, location: 1)
            ],
            startPoint: .bottomLeading,
            endPoint: .topTrailing
        )
        let contentHeight: CGFloat = compact ? 26 : 38

        configuration.label
            .font(.system(size: compact ? 13 : 14, weight: .bold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, compact ? 10 : 0)
            .frame(maxWidth: compact ? nil : .infinity, minHeight: contentHeight, maxHeight: contentHeight)
            .background(HotkeyGoColor.primaryAction, in: innerShape)
            .overlay(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: compact ? 10 : 16, height: 1.5)
                    .offset(x: compact ? 7 : 10, y: compact ? 3 : 4)
            }
            .padding(1.5)
            .background(border, in: shape)
            .clipShape(shape)
            .contentShape(shape)
            .opacity(isEnabled ? (configuration.isPressed ? 0.9 : 1) : 0.45)
            .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? 0.985 : 1)
            .animation(reduceMotion ? nil : .snappy(duration: 0.13), value: configuration.isPressed)
    }
}

/// Plain text rows gain only a quiet hover/press wash; they never acquire a border.
struct PopupPlainRowButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, minHeight: 41, maxHeight: 41)
            .background {
                HotkeyGoControlShape(cut: 6)
                    .fill((configuration.isPressed || isHovering) ? HotkeyGoColor.surfaceHover : .clear)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
            }
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.45)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
            .onHover { isHovering = isEnabled && $0 }
    }
}

enum HotkeyGoCardAccent {
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
            [HotkeyGoColor.line, HotkeyGoColor.violet]
        case .single(let color):
            [color]
        case .language:
            [HotkeyGoColor.cyan]
        }
    }
}

struct HotkeyGoSemanticCardButtonStyle: ButtonStyle {
    let accent: HotkeyGoCardAccent
    let isSelected: Bool
    var cut: CGFloat = 8

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var colors: [Color] { accent.colors }
    private var primary: Color { colors.first ?? HotkeyGoColor.violet }
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
                in: HotkeyGoControlShape(cut: cut)
            )
            .overlay {
                HotkeyGoControlShape(cut: cut)
                    .stroke(
                        border.opacity(isSelected ? 0.82 : isHovering ? 0.58 : 0.34),
                        lineWidth: 1
                    )
            }
            .hotkeygoElectricTrace(in: HotkeyGoControlShape(cut: cut), on: configuration.isPressed, when: configuration.isPressed, accent: primary)
            .contentShape(HotkeyGoControlShape(cut: cut))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? 0.985 : 1)
            .animation(reduceMotion ? nil : .snappy(duration: 0.13), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovering)
            .onHover { isHovering = isEnabled && $0 }
    }
}

struct HotkeyGoSemanticCompactButtonStyle: ButtonStyle {
    let accent: HotkeyGoCardAccent
    var isSelected = false

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var colors: [Color] { accent.colors }
    private var primary: Color { colors.first ?? HotkeyGoColor.violet }
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
            .foregroundStyle(isSelected || isHovering ? HotkeyGoColor.ink : primary)
            .padding(.horizontal, 8)
            .frame(minHeight: 24)
            .background(
                primary.opacity(configuration.isPressed ? 0.20 : isSelected ? 0.14 : isHovering ? 0.08 : 0.035),
                in: HotkeyGoControlShape(cut: 4)
            )
            .overlay {
                HotkeyGoControlShape(cut: 4)
                    .stroke(
                        border.opacity(isSelected ? 0.82 : isHovering ? 0.60 : 0.40),
                        lineWidth: 1
                    )
            }
            .hotkeygoElectricTrace(in: HotkeyGoControlShape(cut: 4), on: configuration.isPressed, when: configuration.isPressed, accent: primary)
            .contentShape(HotkeyGoControlShape(cut: 4))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? 0.96 : 1)
            .offset(y: reduceMotion ? 0 : configuration.isPressed ? 1 : 0)
            .animation(reduceMotion ? nil : .snappy(duration: 0.13), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovering)
            .onHover { isHovering = isEnabled && $0 }
    }
}

struct IconButtonStyle: ButtonStyle {
    var accent = HotkeyGoColor.secondary
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(isHovering ? HotkeyGoColor.ink : accent)
            .frame(width: 24, height: 24)
            .background(configuration.isPressed ? accent.opacity(0.20) : isHovering ? accent.opacity(0.12) : HotkeyGoColor.surfaceHover, in: HotkeyGoControlShape(cut: 5))
            .overlay { HotkeyGoControlShape(cut: 5).stroke(isHovering ? accent.opacity(0.65) : HotkeyGoColor.line) }
            .hotkeygoElectricTrace(in: HotkeyGoControlShape(cut: 5), on: configuration.isPressed, when: configuration.isPressed, accent: accent)
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
            .background(HotkeyGoColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(HotkeyGoColor.line))
            .shadow(color: HotkeyGoColor.cardShadow, radius: 12, y: 5)
    }
}

extension View {
    func kCard() -> some View { modifier(CardModifier()) }
}
