import SwiftUI

struct OnboardingCompletionStepView: View {
    let shortcuts: OnboardingShortcuts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 15) {
            HotkeyGoFaceView(face: .ready, size: 22, reduceMotion: reduceMotion, color: HotkeyGoColor.violet)
            Text("You're all set.").onboardingTitle(32)
            Text("Three ways to use hotkeygo in any app.").onboardingBody()
            VStack(spacing: 0) {
                cheatRow(shortcuts.fix.displayString, "Fix", "Correct selected text in place."); Divider().padding(.leading, 150)
                cheatRow(shortcuts.actions.displayString, "Actions", "Rewrite, translate, or change tone."); Divider().padding(.leading, 150)
                cheatRow(shortcuts.peek.displayString, "Peek", "Understand text without changing it.")
            }.frame(width: 520).hotkeygoPanel()
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    HotkeyGoUI.Icon(.wifi, size: 11)
                    Text("hotkeygo").font(.system(size: 10, weight: .semibold, design: .rounded))
                    Text("9:41").font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(HotkeyGoColor.surface)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(HotkeyGoColor.ink)
                .clipShape(Capsule())
                Text("hotkeygo lives in your menu bar — settings and usage are there.").font(.system(size: 12.5)).foregroundStyle(HotkeyGoColor.secondary)
            }
        }.padding(.top, 14)
    }

    private func cheatRow(_ keys: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 0) {
            HStack { OnboardingKeycap(keys); Spacer() }
                .frame(width: 132)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail).font(.system(size: 12.5)).foregroundStyle(HotkeyGoColor.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
    }
}
