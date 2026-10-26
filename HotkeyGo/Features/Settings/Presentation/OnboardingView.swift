import SwiftUI

private struct DemoKeys: OptionSet {
    let rawValue: Int

    static let modifiers = DemoKeys(rawValue: 1 << 0)
    static let action = DemoKeys(rawValue: 1 << 1)
}

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    let fixShortcut: HotkeyBinding
    let actionShortcut: HotkeyBinding
    let peekShortcut: HotkeyBinding
    let onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var demoKeys: DemoKeys = []
    @State private var accessPulse = false
    private let labels = ["Welcome", "Access", "Fix", "Actions", "Peek", "Done"]

    init(
        model: OnboardingModel,
        fixShortcut: HotkeyBinding = .defaultMain,
        actionShortcut: HotkeyBinding = .actions,
        peekShortcut: HotkeyBinding = .peek,
        onFinish: @escaping () -> Void
    ) {
        self.model = model
        self.fixShortcut = fixShortcut
        self.actionShortcut = actionShortcut
        self.peekShortcut = peekShortcut
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack { content.id(model.step) }
                .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
                .animation(reduceMotion ? .easeOut(duration: 0.16) : .timingCurve(0.2, 0.9, 0.3, 1, duration: 0.26), value: model.step)
            footer
        }
        .frame(width: 820, height: 640)
        .background(HotkeyGoColor.canvas).foregroundStyle(HotkeyGoColor.ink).hotkeygoTheme()
        .task(id: model.step) { await runKeyDemo() }
        .onAppear { model.refreshAccessibility() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            HotkeyGoWordmark().frame(width: 144, height: 46)
            Spacer()
            HStack(spacing: 0) {
                ForEach(labels.indices, id: \.self) { index in
                    Button {
                        while model.step > index { model.goBack() }
                    } label: {
                        Text(index < model.step ? "✓ \(labels[index])" : labels[index])
                    }
                    .buttonStyle(CompactButtonStyle(
                        accent: index < model.step ? HotkeyGoColor.success : HotkeyGoColor.violet,
                        isSelected: index == model.step,
                        prominent: index == model.step
                    ))
                    .disabled(index > model.step)
                    .accessibilityLabel("\(labels[index]), \(index == model.step ? "current" : index < model.step ? "complete; go back" : "upcoming")")
                    if index < labels.count - 1 { Rectangle().fill(HotkeyGoColor.line).frame(width: 8, height: 1) }
                }
            }
        }
        .padding(.leading, 42).padding(.trailing, 22).frame(height: 52)
        .background(HotkeyGoColor.canvasRaised).overlay(alignment: .bottom) { Rectangle().fill(HotkeyGoColor.line).frame(height: 1) }
    }

    @ViewBuilder private var content: some View {
        switch model.step {
        case 0: welcome
        case 1: access
        case 2...4: practice
        default: done
        }
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            welcomeFace.frame(width: 188, height: 73)
            Text("Your words. Sharper.").onboardingTitle(32)
            Text("Select text in any app. hotkeygo gives you three quick ways to work with it.")
                .onboardingBody().frame(maxWidth: 570).multilineTextAlignment(.center)
            VStack(spacing: 0) {
                welcomeFeatureRow(.fix, "Fix", "Clean up selected text in place.", fixShortcut.displayString, HotkeyGoColor.violet)
                Divider().padding(.leading, 49)
                welcomeFeatureRow(.actions, "Actions", "Translate or change the tone.", actionShortcut.displayString, HotkeyGoColor.magenta)
                Divider().padding(.leading, 49)
                welcomeFeatureRow(.peek, "Peek", "Understand text without changing it.", peekShortcut.displayString, HotkeyGoColor.cyan)
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
            SmallKeycap(shortcut)
        }
        .padding(.horizontal, 16)
        .frame(height: 57)
    }

    private var access: some View {
        ZStack {
            if model.accessibilityGranted {
                grantedAccess
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else if model.isRequestingAccessibility {
                gettingAccess
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                noAccess
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.16) : .timingCurve(0.2, 0.9, 0.3, 1, duration: 0.28),
            value: model.isRequestingAccessibility
        )
        .animation(
            reduceMotion ? .easeOut(duration: 0.16) : .timingCurve(0.2, 0.9, 0.3, 1, duration: 0.28),
            value: model.accessibilityGranted
        )
    }

    private var noAccess: some View {
        VStack(spacing: 18) {
            accessIcon(.accessNeeded, active: false)
            Text("hotkeygo needs Accessibility access.").onboardingTitle(30)
            Text("Allow hotkeygo in Privacy & Security › Accessibility. This lets hotkeygo read and replace selected text only when you use a shortcut.")
                .onboardingBody().multilineTextAlignment(.center).frame(maxWidth: 500)
            if model.permissionCheckTimedOut {
                Text("Access wasn’t detected yet. You can reopen System Settings and try again.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(HotkeyGoColor.warning)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
            Button { model.requestAccessibility() } label: {
                HStack(spacing: 9) {
                    Text(model.permissionCheckTimedOut ? "Try again" : "Allow access")
                    HotkeyGoUI.Icon(.externalLink, size: 10)
                }
            }
                .buttonStyle(HotkeyGoUI.PrimaryButton())
                .accessibilityLabel("Allow hotkeygo in Accessibility settings")
                .accessibilityHint("Opens Accessibility settings in System Settings")
        }
        .padding(.top, 40)
    }

    private var grantedAccess: some View {
        VStack(spacing: 18) {
            accessIcon(.accessGranted, active: false, accent: HotkeyGoColor.success)
            Text("Access granted.").onboardingTitle(30)
            Text("Now try Fix, Actions, and Peek with a sample selection. Your text stays on your Mac during this rehearsal.")
                .onboardingBody().multilineTextAlignment(.center).frame(maxWidth: 500)
            HStack(spacing: 8) {
                HotkeyGoUI.Icon(.statusSuccess, size: 12)
                Text("ACCESS GRANTED · PRESS ENTER TO CONTINUE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(HotkeyGoColor.success)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(HotkeyGoColor.success.opacity(0.09), in: HotkeyGoControlShape(cut: 6))
        }
        .padding(.top, 40)
    }

    private var gettingAccess: some View {
        VStack(spacing: 18) {
            accessIcon(.accessGranted, active: true)
            Text("Finish in System Settings.").onboardingTitle(30)
            Text("Turn on hotkeygo under Accessibility. We’ll keep this screen here and confirm when access is detected.")
                .onboardingBody().multilineTextAlignment(.center).frame(maxWidth: 520)

            HStack(spacing: 13) {
                accessPathItem(.settings, "Privacy & Security")
                HotkeyGoUI.Icon(.chevronRight, size: 10)
                accessPathItem(.accessibility, "Accessibility")
                HotkeyGoUI.Icon(.chevronRight, size: 10)
                accessPathItem(.switchControl, "hotkeygo on")
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(HotkeyGoColor.secondary)
            .padding(.horizontal, 18)
            .frame(height: 46)
            .background(HotkeyGoColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(HotkeyGoColor.line) }

            HStack(spacing: 9) {
                ProgressView().controlSize(.small).tint(HotkeyGoColor.violet)
                Text("Waiting for access…")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(HotkeyGoColor.ink)
                Button { model.requestAccessibility() } label: {
                    HStack(spacing: 7) {
                        Text("Open System Settings again")
                        HotkeyGoUI.Icon(.externalLink, size: 9)
                    }
                }
                    .buttonStyle(SubtleButtonStyle())
            }
        }
        .padding(.top, 38)
    }

    private func accessIcon(_ name: HotkeyGoUI.IconName, active: Bool, accent: Color = HotkeyGoColor.violet) -> some View {
        ZStack {
            if active {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(accent.opacity(0.28), lineWidth: 2)
                    .frame(width: 72, height: 72)
                    .scaleEffect(accessPulse ? 1.28 : 0.94)
                    .opacity(accessPulse ? 0 : 1)
            }
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(accent.opacity(active ? 0.14 : 0.09))
            HotkeyGoUI.Icon(name, size: 28)
                .foregroundStyle(accent)
        }
        .frame(width: 64, height: 64)
        .onAppear {
            accessPulse = false
            guard active, !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.45).repeatForever(autoreverses: false)) {
                accessPulse = true
            }
        }
    }

    private func accessPathItem(_ icon: HotkeyGoUI.IconName, _ title: String) -> some View {
        HStack(spacing: 6) {
            HotkeyGoUI.Icon(icon, size: 12).foregroundStyle(HotkeyGoColor.violet)
            Text(title)
        }
        .fixedSize()
    }

    private var practice: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 17) {
                HStack(spacing: 8) {
                    Capsule().fill(stepAccent).frame(width: 3, height: 14)
                Text("\(practiceName) · \(model.step - 1) of 3").font(.system(size: 12, weight: .medium)).foregroundStyle(HotkeyGoColor.secondary)
                }
                Text(practiceTitle).onboardingTitle(27).multilineTextAlignment(.leading)
                Text(practiceSubtitle).onboardingBody()
                DemoKeyRow(
                    binding: shortcutForPractice,
                    accent: stepAccent,
                    activeKeys: demoKeys,
                    controlDown: model.controlDown,
                    optionDown: model.optionDown,
                    shiftDown: model.shiftDown,
                    commandDown: model.commandDown,
                    reduceMotion: reduceMotion
                )
                .opacity([.idle, .palette].contains(model.phase) ? 1 : 0.4)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(checklist.indices, id: \.self) { checklistRow($0, checklist[$0]) }
                }
                Spacer()
            }
            .padding(.top, 34).padding(.leading, 28).padding(.trailing, 22).frame(width: 282, alignment: .leading)
            practiceStage.padding(14).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var practiceStage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(HotkeyGoColor.line.opacity(0.38))
            MockAppWindow(title: mockWindowTitle) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(displayedPracticeText)
                        .font(.system(size: 21, weight: .semibold, design: .rounded)).lineSpacing(5).padding(7)
                        .background(model.phase == .done && !model.typed.isEmpty ? .clear : HotkeyGoColor.violet.opacity(0.16)).clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .frame(maxWidth: 440, maxHeight: 320)
            .padding(28)

            if (2...3).contains(model.step), let feedbackPhase {
                FeedbackPill(
                    phase: feedbackPhase,
                    reduceMotion: reduceMotion,
                    onClose: {}
                )
                .id(model.phase == .done)
                .allowsHitTesting(false)
                .offset(x: 76, y: 38)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            if model.phase == .palette {
                OnboardingPaletteSurface(model: model)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
            }
            if model.step == 4, [.peekChoice, .peekProcessing, .peek].contains(model.phase) {
                OnboardingPeekSurface(
                    model: model,
                    reduceMotion: reduceMotion,
                    onClose: { _ = model.escapeOverlay() }
                )
                    .offset(x: 48, y: 64)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.16) : .snappy(duration: 0.24), value: model.phase)
    }

    private func checklistRow(_ index: Int, _ label: String) -> some View {
        let complete = completedChecklistRows > index
        let current = completedChecklistRows == index
        return HStack(spacing: 9) {
            ZStack {
                Circle().fill(complete ? HotkeyGoColor.success : current ? stepAccent : .clear)
                Circle().stroke(current || complete ? .clear : HotkeyGoColor.line)
                Text(complete ? "✓" : "\(index + 1)").font(.system(size: 10, weight: .semibold)).foregroundStyle(complete || current ? .white : HotkeyGoColor.secondary)
            }.frame(width: 22, height: 22)
            Text(label).font(.system(size: 12.5, weight: current ? .semibold : .regular)).foregroundStyle(complete ? HotkeyGoColor.secondary : HotkeyGoColor.ink)
        }
    }

    private var done: some View {
        VStack(spacing: 15) {
            HotkeyGoFaceView(face: .ready, size: 22, reduceMotion: reduceMotion, color: HotkeyGoColor.violet)
            Text("You're all set.").onboardingTitle(32)
            Text("Three ways to use hotkeygo in any app.").onboardingBody()
            VStack(spacing: 0) {
                cheatRow(fixShortcut.displayString, "Fix", "Correct selected text in place."); Divider().padding(.leading, 150)
                cheatRow(actionShortcut.displayString, "Actions", "Rewrite, translate, or change tone."); Divider().padding(.leading, 150)
                cheatRow(peekShortcut.displayString, "Peek", "Understand text without changing it.")
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
        HStack(spacing: 0) { HStack { SmallKeycap(keys); Spacer() }.frame(width: 132); VStack(alignment: .leading, spacing: 2) { Text(title).font(.system(size: 14, weight: .semibold)); Text(detail).font(.system(size: 12.5)).foregroundStyle(HotkeyGoColor.secondary) }; Spacer() }.padding(.horizontal, 18).frame(height: 58)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            ZStack { RoundedRectangle(cornerRadius: 10).fill(HotkeyGoColor.violet.opacity(0.09)); HotkeyGoFaceView(face: footerFace, size: 13, reduceMotion: reduceMotion, color: HotkeyGoColor.violet) }.frame(width: 54, height: 34)
            Text(guide).font(.system(size: 13.5, weight: .medium)).lineLimit(1)
            Spacer()
            if model.step > 0 { Button("Back") { model.goBack() }.buttonStyle(SubtleButtonStyle()) }
            if (2...4).contains(model.step), !model.canContinue { Button("Skip") { model.skipPractice() }.buttonStyle(SubtleButtonStyle()) }
            if model.canContinue {
                Button { model.step == 5 ? onFinish() : model.advance() } label: {
                    HStack(spacing: 9) {
                        Text(primaryTitle)
                        HotkeyGoUI.Icon(.arrowRight, size: 10)
                    }
                }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.return, modifiers: []).accessibilityLabel(primaryTitle)
            }
        }.padding(.horizontal, 20).frame(height: 60).background(HotkeyGoColor.canvasRaised).overlay(alignment: .top) { Rectangle().fill(HotkeyGoColor.line).frame(height: 1) }
    }

    private var primaryTitle: String {
        if model.step == 0 { return "Get started" }
        if model.step == 1, !model.accessibilityGranted { return "Do this later" }
        if model.step == 5 { return "Start using hotkeygo" }
        if model.step == 4 { return "Continue" }
        return "Continue"
    }
    private var footerFace: HotkeyGoFace {
        model.phase == .done || model.phase == .peek || model.phase == .peekDone || model.phase == .skipped || model.step == 5 || (model.step == 1 && model.accessibilityGranted)
            ? .ready
            : model.phase == .processing || model.phase == .peekProcessing ? .scanning : .hello
    }
    private var practiceName: String { [2: "Fix", 3: "Actions", 4: "Peek"][model.step] ?? "" }
    private var practiceTitle: String {
        [2: "Fix it in place.", 3: "Choose what happens.", 4: "Read without changing a thing."][model.step] ?? ""
    }
    private var practiceSubtitle: String {
        [
            2: "One shortcut replaces the selected text.",
            3: "Open Actions, then choose what happens.",
            4: "Peek translates selected text in a read-only panel."
        ][model.step] ?? ""
    }
    private var stepAccent: Color { model.step == 3 ? HotkeyGoColor.magenta : model.step == 4 ? HotkeyGoColor.cyan : HotkeyGoColor.violet }
    private var mockWindowTitle: String { [2: "Draft — Notes", 3: "Message — Slack", 4: "Message — Mail"][model.step] ?? "" }
    private var shortcutForPractice: HotkeyBinding {
        switch model.step {
        case 3: actionShortcut
        case 4: peekShortcut
        default: fixShortcut
        }
    }
    private var displayedPracticeText: String {
        model.step == 4 || model.typed.isEmpty ? model.originalText : model.typed
    }
    private var checklist: [String] {
        switch model.step {
        case 2: ["Text is selected", "Press \(fixShortcut.displayString)", "Fixed text replaces it"]
        case 3: ["Text is selected", "Press \(actionShortcut.displayString)", "Pick an action — 1–4 or ↵", "Result replaces the text"]
        default: ["Text is selected", "Choose a language", "Read the translation; source stays put"]
        }
    }
    private var completedChecklistRows: Int {
        switch model.phase {
        case .done, .peek, .peekDone: checklist.count
        case .skipped: 1
        case .processing, .typing, .peekProcessing: max(2, checklist.count - 1)
        case .peekChoice: 2
        case .palette: 2
        case .idle: 1
        }
    }
    private var feedbackPhase: AppPhase? {
        switch model.phase {
        case .processing, .typing: .processing
        case .done: .success
        case .idle, .palette, .peekChoice, .peek, .peekDone, .skipped: nil
        case .peekProcessing: nil
        }
    }
    private var guide: String {
        switch (model.step, model.phase) {
        case (0, _): "Hi! Let's set up hotkeygo — it takes about a minute."
        case (1, _): model.accessibilityGranted
            ? "ACCESS GRANTED · PRESS ENTER TO CONTINUE"
            : model.isRequestingAccessibility
                ? "Press Enter to continue later, or finish in System Settings."
                : "Press Enter to continue later, or allow access."
        case (2, .processing): "Fixing…"
        case (2, .typing): "Replacing the text…"
        case (2, .done): "Fixed. That's the main move."
        case (2, _): "Press \(fixShortcut.displayString) once."
        case (3, .palette): "Pick an action — 1–4 or ↵."
        case (3, .done): "Chosen and replaced."
        case (3, _): "Press \(actionShortcut.displayString) to open Actions."
        case (4, .peekChoice): "Choose a language — 1–4 or ↵."
        case (4, .peekProcessing): "Translating the sample…"
        case (4, .peek): "Read it. Your original text is untouched."
        case (4, .peekDone): "Translation ready. Your original text is untouched."
        case (2...4, .skipped): "Skipped. Continue whenever you're ready."
        case (4, _): "Press \(peekShortcut.displayString) to preview the text."
        default: "hotkeygo is ready in every app."
        }
    }

    private func runKeyDemo() async {
        demoKeys = []
        guard (2...4).contains(model.step), !reduceMotion else { return }
        while !Task.isCancelled, !model.hasRealInput, model.phase == .idle {
            do { try await Task.sleep(for: .milliseconds(900)) } catch { return }
            demoKeys = [.modifiers]
            do { try await Task.sleep(for: .milliseconds(220)) } catch { return }
            demoKeys = [.modifiers, .action]
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            demoKeys = [.modifiers]
            do { try await Task.sleep(for: .milliseconds(140)) } catch { return }
            demoKeys = []
        }
    }
}

private struct SmallKeycap: View {
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

private struct DemoKeyRow: View {
    let binding: HotkeyBinding
    let accent: Color
    let activeKeys: DemoKeys
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

private struct MockAppWindow<Content: View>: View {
    let title: String; let content: Content
    init(title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View { VStack(spacing: 0) { HStack(spacing: 5) { Circle().fill(.red.opacity(0.8)); Circle().fill(.yellow.opacity(0.8)); Circle().fill(.green.opacity(0.8)); Spacer(); Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(HotkeyGoColor.secondary); Spacer().frame(width: 31) }.padding(.horizontal, 9).frame(height: 26).background(HotkeyGoColor.canvasRaised); content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(22) }.background(HotkeyGoColor.surface).clipShape(RoundedRectangle(cornerRadius: 11)).overlay(RoundedRectangle(cornerRadius: 11).stroke(HotkeyGoColor.line)).shadow(color: .black.opacity(0.11), radius: 18, y: 8) }
}

private struct OnboardingPaletteSurface: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        HotkeyGoUI.ActionPalette(
            query: $model.actionQuery,
            contextLabel: model.actionContextLabel,
            footerText: model.actionPaletteFooter,
            rows: model.actionPaletteRows,
            selectedIndex: model.actionSelectionIndex,
            onSelect: { index in
                guard model.actionChoices.indices.contains(index) else { return }
                model.chooseAction(model.actionChoices[index])
            }
        )
            .frame(
                width: 360,
                height: HotkeyGoUI.ActionPalette.preferredHeight(
                    rowCount: model.actionPaletteRows.count,
                    separatorCount: model.actionPaletteSeparatorCount
                )
            )
            .shadow(color: HotkeyGoColor.cardShadow, radius: 18, y: 8)
            .onboardingEscape { _ = model.escapeOverlay() }
    }
}

private struct OnboardingPeekSurface: View {
    @ObservedObject var model: OnboardingModel
    let reduceMotion: Bool
    let onClose: () -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            .frame(height: 48)

            Rectangle().fill(HotkeyGoColor.popupDivider).frame(height: 1)

            Group {
                switch model.phase {
                case .peekChoice:
                    languageChoices
                case .peekProcessing:
                    processingContent
                case .peek:
                    resultContent
                default:
                    EmptyView()
                }
            }

            Rectangle().fill(HotkeyGoColor.popupDivider).frame(height: 1)
            footer
        }
        .frame(width: 360)
        .foregroundStyle(HotkeyGoColor.ink)
        .hotkeygoPopupPanel()
        .accessibilityElement(children: .contain)
        .onboardingEscape { onClose() }
    }

    @ViewBuilder private var header: some View {
        if model.phase == .peekChoice {
            HStack(spacing: 10) {
                Rectangle().fill(HotkeyGoColor.violet).frame(width: 1.5, height: 18)
                TextField(
                    "",
                    text: $model.peekQuery,
                    prompt: Text("Search…").foregroundColor(HotkeyGoColor.popupMuted)
                )
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(HotkeyGoColor.ink)
                .focused($searchFocused)
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(model.peekContextLabel)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(HotkeyGoColor.popupMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 16)
            .onAppear { searchFocused = true }
        } else {
            HStack(spacing: 10) {
                Text("Spanish →")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(HotkeyGoColor.popupMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Button(model.peekLanguage.name) { model.cyclePeekLanguage() }
                    .buttonStyle(HotkeyGoUI.PopupSelectedButton(compact: true))
                    .help("Next language")
                    .accessibilityLabel("Target language: \(model.peekLanguage.name). Switch to next language.")
                Spacer(minLength: 0)
                Button(action: onClose) {
                    HotkeyGoUI.Icon(.close, size: 10)
                }
                .buttonStyle(HotkeyGoUI.IconButton(accent: HotkeyGoColor.popupMuted))
                .help("Close Peek preview")
                .accessibilityLabel("Close Peek preview")
            }
            .padding(.leading, 16)
            .padding(.trailing, 10)
        }
    }

    private var languageChoices: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 6) {
                    if model.peekChoices.isEmpty {
                        Text("No language matches \"\(model.peekQuery)\"")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(HotkeyGoColor.popupMuted)
                            .frame(maxWidth: .infinity, minHeight: 41, alignment: .leading)
                    } else {
                        ForEach(Array(model.peekChoices.enumerated()), id: \.element.id) { index, language in
                            languageRow(language, index: index)
                        }
                    }
                }
                .padding(10)
            }
            .frame(maxHeight: 212)
            .onValueChange(of: model.peekSelectionIndex) { value in
                proxy.scrollTo(value, anchor: .center)
            }
        }
    }

    @ViewBuilder
    private func languageRow(_ language: OnboardingPeekLanguage, index: Int) -> some View {
        let selected = model.peekSelectionIndex == index
        let label = HStack(spacing: 10) {
            Text(language.name)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(selected ? Color.white : HotkeyGoColor.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(selected ? "↵" : "\(index + 1)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(selected ? Color.white : HotkeyGoColor.popupMuted)
                .fixedSize()
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, alignment: .leading)

        if selected {
            Button { model.choosePeekLanguage(at: index) } label: { label }
                .buttonStyle(HotkeyGoUI.PopupSelectedButton())
                .accessibilityLabel("Translate to \(language.name), Return")
                .accessibilityAddTraits(.isSelected)
                .id(index)
        } else {
            Button { model.choosePeekLanguage(at: index) } label: { label }
                .frame(height: 41)
                .buttonStyle(HotkeyGoUI.PopupPlainRowButton())
                .accessibilityLabel("Translate to \(language.name), shortcut \(index + 1)")
                .id(index)
        }
    }

    private var processingContent: some View {
        FeedbackPill(
            phase: .processing,
            reduceMotion: reduceMotion,
            onClose: {}
        )
        .id("peek-processing")
        .allowsHitTesting(false)
        .accessibilityLabel("Translating the selected sample")
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 16)
    }

    private var resultContent: some View {
        Text(verbatim: model.peekLanguage.result)
            .font(.system(size: 15, weight: .regular))
            .lineSpacing(4)
            .foregroundStyle(HotkeyGoColor.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .accessibilityLabel("Peek translation: \(model.peekLanguage.result)")
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 16)
    }

    @ViewBuilder private var footer: some View {
        if model.phase == .peekChoice {
            Text("Preview only · nothing is replaced")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(HotkeyGoColor.popupMuted)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 32)
        } else if model.phase == .peek {
            Button(action: model.copyPeekResult) {
                HStack(spacing: 6) {
                    Text(model.peekCopied ? "Copied" : "↵ copy")
                    Text("· Esc close")
                }
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(HotkeyGoColor.popupMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .frame(height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.peekCopied ? "Translation copied" : "Copy translation; Escape closes Peek")
        } else {
            Text("Esc close")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(HotkeyGoColor.popupMuted)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 32)
        }
    }
}

private extension View {
    func onboardingTitle(_ size: CGFloat) -> some View { font(.system(size: size, weight: .heavy, design: .rounded)).tracking(size >= 30 ? -0.8 : -0.6).multilineTextAlignment(.center) }
    func onboardingBody() -> some View { font(.system(size: 14)).lineSpacing(7).foregroundStyle(HotkeyGoColor.secondary) }

    /// `onKeyPress` is macOS 14+; `onExitCommand` delivers the same Escape on macOS 13.
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

#Preview("Onboarding · Welcome") { OnboardingView(model: OnboardingModel(accessibility: PreviewAccessibility()), onFinish: {}) }
#Preview("Onboarding · Access") { OnboardingView(model: OnboardingModel(accessibility: PreviewAccessibility(), initialStep: 1), onFinish: {}) }
#Preview("Onboarding · Access granted") { OnboardingView(model: OnboardingModel(accessibility: PreviewAccessibility(isTrusted: true), initialStep: 1), onFinish: {}) }
#Preview("Onboarding · Fix idle") { OnboardingView(model: OnboardingModel(accessibility: PreviewAccessibility(), initialStep: 2), onFinish: {}) }
#Preview("Onboarding · Fix processing") { OnboardingView(model: OnboardingModel(accessibility: PreviewAccessibility(), initialStep: 2, initialPhase: .processing), onFinish: {}) }
#Preview("Onboarding · Choose palette") { OnboardingView(model: OnboardingModel(accessibility: PreviewAccessibility(), initialStep: 3, initialPhase: .palette), onFinish: {}) }
#Preview("Onboarding · Peek loading") { OnboardingView(model: OnboardingModel(accessibility: PreviewAccessibility(), initialStep: 4, initialPhase: .processing), onFinish: {}) }
#Preview("Onboarding · Peek") { OnboardingView(model: OnboardingModel(accessibility: PreviewAccessibility(), initialStep: 4, initialPhase: .peek), onFinish: {}) }
#Preview("Onboarding · Done") { OnboardingView(model: OnboardingModel(accessibility: PreviewAccessibility(), initialStep: 5), onFinish: {}) }

private final class PreviewAccessibility: AccessibilityServicing {
    var isTrusted: Bool
    init(isTrusted: Bool = false) { self.isTrusted = isTrusted }
    func requestPermission() {}
    func selectedText() async -> String? { nil }
    func selectionBounds() -> CGRect? { nil }
    func fallbackPoint() -> CGPoint { .zero }
}
