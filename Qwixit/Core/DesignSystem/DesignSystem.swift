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
    static let ink = Color(red: 0.086, green: 0.075, blue: 0.122)
    static let secondary = Color(red: 0.43, green: 0.42, blue: 0.49)
    static let canvas = Color(red: 0.975, green: 0.973, blue: 0.988)
    static let canvasRaised = Color(red: 0.992, green: 0.99, blue: 1)
    static let surface = Color.white
    static let surfaceHover = Color(red: 0.965, green: 0.955, blue: 0.992)
    static let line = Color(red: 0.875, green: 0.855, blue: 0.925)
    static let violet = Color(red: 0.427, green: 0.157, blue: 1)
    static let magenta = Color(red: 1, green: 0.176, blue: 0.608)
    static let cyan = Color(red: 0, green: 0.75, blue: 0.86)
    static let success = Color(red: 0.122, green: 0.686, blue: 0.333)
    static let terminalGreen = Color(red: 0.18, green: 0.92, blue: 0.45)
    static let warning = Color(red: 0.92, green: 0.55, blue: 0.08)
    static let danger = Color(red: 1, green: 0.25, blue: 0.32)
}

enum QwixitMarkStyle { case light, dark, mono }

enum QwixitLockupStyle { case light, dark }

struct QwixitMark: View {
    let size: CGFloat
    var animated = false
    var style: QwixitMarkStyle = .light
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
        case .light: return "QwixitMarkLight"
        case .dark: return "QwixitMarkDark"
        case .mono: return "QwixitMarkInk"
        }
    }
}

struct QwixitLockup: View {
    var style: QwixitLockupStyle = .light

    var body: some View {
        Image(style == .light ? "QwixitLockupLight" : "QwixitLockupDark")
            .resizable()
            .scaledToFit()
            .accessibilityLabel("Qwixit")
    }
}

struct MonoLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(1.45)
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
            .background(active ? KColor.violet : KColor.surfaceHover)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(active ? KColor.violet : KColor.line))
            .overlay(alignment: .bottom) {
                Rectangle().fill(active ? Color.black.opacity(0.24) : KColor.line).frame(height: 1).padding(.horizontal, 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct ShortcutKeys: View {
    var body: some View {
        HStack(spacing: 4) {
            Keycap(symbol: "⌥")
            Keycap(symbol: "⌘")
            Keycap(symbol: "X", active: true)
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 15)
            .frame(height: 32)
            .background(
                LinearGradient(
                    colors: [KColor.violet, Color(red: 0.34, green: 0.08, blue: 0.88)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.18)))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct SubtleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(KColor.ink)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(configuration.isPressed ? KColor.surfaceHover : KColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(KColor.line))
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
