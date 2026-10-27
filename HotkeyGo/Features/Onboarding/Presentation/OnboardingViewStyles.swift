import SwiftUI

extension View {
    func onboardingTitle(_ size: CGFloat) -> some View {
        font(.system(size: size, weight: .heavy, design: .rounded))
            .tracking(size >= 30 ? -0.8 : -0.6)
            .multilineTextAlignment(.center)
    }

    func onboardingBody() -> some View {
        font(.system(size: 14))
            .lineSpacing(7)
            .foregroundStyle(HotkeyGoColor.secondary)
    }

    @ViewBuilder
    func onboardingEscape(_ action: @escaping () -> Void) -> some View {
        if #available(macOS 14.0, *) {
            onKeyPress(.escape) {
                action()
                return .handled
            }
        } else {
            onExitCommand(perform: action)
        }
    }
}
