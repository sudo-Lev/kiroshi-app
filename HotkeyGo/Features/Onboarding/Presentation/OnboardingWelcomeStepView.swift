import SwiftUI

struct OnboardingWelcomeStepView: View {
    let shortcuts: OnboardingShortcuts

    var body: some View {
        VStack(spacing: 16) {
            welcomeFace.frame(width: 188, height: 73)
            Text("Your words. Sharper.").onboardingTitle(32)
            Text("Select text in any app. hotkeygo gives you three quick ways to work with it.")
                .onboardingBody().frame(maxWidth: 570).multilineTextAlignment(.center)
            VStack(spacing: 0) {
                welcomeFeatureRow(.fix, "Fix", "Clean up selected text in place.", shortcuts.fix.displayString, HotkeyGoColor.violet)
                Divider().padding(.leading, 49)
                welcomeFeatureRow(.actions, "Actions", "Translate or change the tone.", shortcuts.actions.displayString, HotkeyGoColor.magenta)
                Divider().padding(.leading, 49)
                welcomeFeatureRow(.peek, "Peek", "Understand text without changing it.", shortcuts.peek.displayString, HotkeyGoColor.cyan)
            }
            .frame(width: 520)
            .hotkeygoPanel()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 4)
    }

    private var welcomeFace: some View {
        (Text("[ ^_").foregroundColor(HotkeyGoColor.ink)
            + Text("-").foregroundColor(HotkeyGoColor.magenta)
            + Text(" ]").foregroundColor(HotkeyGoColor.ink))
            .font(.system(size: 42, weight: .heavy, design: .monospaced))
            .accessibilityLabel("hotkeygo winking face")
    }

    private func welcomeFeatureRow(
        _ icon: HotkeyGoUI.IconName,
        _ title: String,
        _ detail: String,
        _ shortcut: String,
        _ accent: Color
    ) -> some View {
        HStack(spacing: 13) {
            HotkeyGoUI.Icon(icon, size: 19).foregroundStyle(accent).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .bold))
                Text(detail).font(.system(size: 11.5)).foregroundStyle(HotkeyGoColor.secondary)
            }
            Spacer(minLength: 8)
            OnboardingKeycap(shortcut)
        }
        .padding(.horizontal, 16)
        .frame(height: 57)
    }
}

struct OnboardingKeycap: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
            .padding(.horizontal, 8)
            .frame(minWidth: 28, minHeight: 27)
            .background(HotkeyGoColor.surfaceHover, in: HotkeyGoControlShape(cut: 5))
            .overlay { HotkeyGoControlShape(cut: 5).stroke(HotkeyGoColor.ink.opacity(0.72), lineWidth: 1) }
            .shadow(color: HotkeyGoColor.ink.opacity(0.12), radius: 3, y: 2)
    }
}
