import SwiftUI

struct OnboardingDemoKeys: OptionSet {
    let rawValue: Int

    static let modifiers = OnboardingDemoKeys(rawValue: 1 << 0)
    static let action = OnboardingDemoKeys(rawValue: 1 << 1)
}

struct OnboardingDemoKeyRow: View {
    let binding: HotkeyBinding
    let accent: Color
    let activeKeys: OnboardingDemoKeys
    let controlDown: Bool
    let optionDown: Bool
    let shiftDown: Bool
    let commandDown: Bool
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: 7) {
            ForEach(binding.modifierSymbols, id: \.self) { symbol in
                key(symbol, modifierName(symbol), modifierIsDown(symbol) || activeKeys.contains(.modifiers))
            }
            key(binding.keySymbol, "shortcut", activeKeys.contains(.action))
        }
    }

    private func modifierName(_ symbol: String) -> String {
        switch symbol {
        case "⌃": "control"
        case "⌥": "option"
        case "⇧": "shift"
        default: "command"
        }
    }

    private func modifierIsDown(_ symbol: String) -> Bool {
        switch symbol {
        case "⌃": controlDown
        case "⌥": optionDown
        case "⇧": shiftDown
        default: commandDown
        }
    }

    private func key(_ symbol: String, _ name: String, _ active: Bool) -> some View {
        VStack(spacing: 2) {
            Text(symbol).font(.system(size: 18, weight: .heavy))
            Text(name.uppercased())
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(active ? .white.opacity(0.76) : HotkeyGoColor.secondary)
        }
        .foregroundStyle(active ? .white : HotkeyGoColor.ink)
        .frame(width: 50, height: 46)
        .background {
            if active {
                HotkeyGoControlShape(cut: 7).fill(HotkeyGoColor.cyan).offset(x: -2, y: 1)
                HotkeyGoControlShape(cut: 7).fill(HotkeyGoColor.magenta).offset(x: 2, y: -1)
            }
            HotkeyGoControlShape(cut: 7).fill(active ? accent : HotkeyGoColor.surface)
        }
        .overlay { HotkeyGoControlShape(cut: 7).stroke(active ? HotkeyGoColor.ink.opacity(0.38) : HotkeyGoColor.line, lineWidth: 1) }
        .shadow(color: HotkeyGoColor.ink.opacity(active ? 0.20 : 0.09), radius: active ? 5 : 3, y: active ? 3 : 2)
        .offset(y: active ? 2 : 0)
        .animation(reduceMotion ? nil : .snappy(duration: 0.16), value: active)
    }
}

struct OnboardingMockAppWindow<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                Circle().fill(.red.opacity(0.8))
                Circle().fill(.yellow.opacity(0.8))
                Circle().fill(.green.opacity(0.8))
                Spacer()
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(HotkeyGoColor.secondary)
                Spacer().frame(width: 31)
            }
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(HotkeyGoColor.canvasRaised)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(22)
        }
        .background(HotkeyGoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .overlay { RoundedRectangle(cornerRadius: 11).stroke(HotkeyGoColor.line) }
        .shadow(color: .black.opacity(0.11), radius: 18, y: 8)
    }
}
