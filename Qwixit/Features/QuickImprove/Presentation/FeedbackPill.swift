import SwiftUI

struct FeedbackPill: View {
    let phase: AppPhase
    let reduceMotion: Bool
    let onClose: () -> Void

    @State private var trace = false
    @State private var successPulse = false
    @State private var borderSweep = false

    var body: some View {
        Group {
            if phase == .limitReached { limitCard }
            else if case .error(let message) = phase { errorCard(message) }
            else if phase == .processing || phase == .success { cyberStatusBox }
            else { basicStatus }
        }
        .foregroundStyle(KColor.ink)
        .environment(\.colorScheme, .light)
        .onAppear {
            if phase == .processing, !reduceMotion { withAnimation(.linear(duration: 0.46).repeatForever(autoreverses: false)) { trace = true } }
            if phase == .success, !reduceMotion { withAnimation(.easeOut(duration: 0.72)) { successPulse = true } }
            if (phase == .processing || phase == .success), !reduceMotion { withAnimation(.linear(duration: 0.64).repeatForever(autoreverses: false)) { borderSweep = true } }
        }
    }

    private var basicStatus: some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                if let detail { Text(detail).font(.system(size: 9, design: .monospaced)).foregroundStyle(KColor.secondary) }
            }
        }
        .padding(.horizontal, 14).frame(height: 46)
        .background(KColor.surface.opacity(0.98)).clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(borderColor)).padding(6)
    }

    private var cyberStatusBox: some View {
        HStack(spacing: 10) {
            statusGlyph

            VStack(alignment: .leading, spacing: 5) {
                if phase == .processing {
                    HStack(spacing: 3) {
                        Text(">").foregroundStyle(KColor.cyan)
                        CyberRewriteLabel(text: "QWIXING", reduceMotion: reduceMotion)
                    }
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                } else {
                    Text("✓ QWIXED!")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1.45)
                        .foregroundStyle(KColor.terminalGreen)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }

                if phase == .processing {
                    progressTrace
                } else {
                    HStack(spacing: 5) {
                        Rectangle().fill(KColor.terminalGreen).frame(width: 14, height: 1)
                        Text("TEXT REPLACED")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .tracking(1.1)
                            .foregroundStyle(.white.opacity(0.52))
                    }
                    .frame(height: 2)
                }
            }

            Spacer(minLength: 2)

            Text(phase == .success ? "OK" : "AI")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(phase == .success ? KColor.terminalGreen : KColor.magenta)
        }
        .padding(.horizontal, 12)
        .frame(width: 224, height: 46)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 11)
                    .fill(Color(red: 0.055, green: 0.047, blue: 0.085).opacity(0.96))
                LinearGradient(
                    colors: [KColor.violet.opacity(0.16), .clear, KColor.cyan.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 11))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .overlay(alignment: .topLeading) {
            LinearGradient(
                colors: [.clear, KColor.magenta, .white, KColor.cyan, .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 68, height: 1)
            .offset(x: borderSweep ? 224 : -68)
            .mask(RoundedRectangle(cornerRadius: 11).stroke(lineWidth: 1))
        }
        .overlay(alignment: .leading) {
            Rectangle().fill(phase == .success ? KColor.terminalGreen : KColor.violet).frame(width: 2, height: 24)
                .shadow(color: (phase == .success ? KColor.terminalGreen : KColor.magenta).opacity(0.8), radius: 5)
        }
        .shadow(color: KColor.violet.opacity(0.2), radius: 16, y: 6)
        .padding(6)
    }

    private var statusGlyph: some View {
        ZStack {
            Circle()
                .stroke(phase == .success ? KColor.terminalGreen.opacity(0.55) : KColor.violet.opacity(0.34), lineWidth: 1)
                .frame(width: 27, height: 27)
                .scaleEffect(successPulse ? 1.18 : 1)
                .opacity(successPulse ? 0 : 1)
            QwixitMark(size: 22, animated: phase == .processing && !reduceMotion, style: .dark)
        }
        .frame(width: 29, height: 29)
    }

    private var progressTrace: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(KColor.line).frame(height: 2)
                LinearGradient(
                    colors: [.clear, KColor.violet, KColor.magenta, KColor.cyan, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 42, height: 2)
                .offset(x: trace ? geometry.size.width : -42)
            }
        }
        .frame(width: 100, height: 2)
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("ERROR").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.5).foregroundStyle(KColor.danger)
            Text("Things are a little unstable.").font(.system(size: 17, weight: .bold))
            Text(message).font(.system(size: 10, design: .monospaced)).foregroundStyle(KColor.secondary).lineLimit(2)
        }
        .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(KColor.surface).overlay(Rectangle().stroke(KColor.line))
        .overlay(Rectangle().fill(KColor.danger).frame(width: 2), alignment: .leading).padding(6)
    }

    @ViewBuilder private var icon: some View {
        switch phase {
        case .success: QwixitMark(size: 19)
        case .permissionDenied: Image(systemName: "exclamationmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white).frame(width: 19, height: 19).background(KColor.magenta).clipShape(Circle())
        case .error, .limitReached: Image(systemName: "exclamationmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white).frame(width: 19, height: 19).background(KColor.danger).clipShape(Circle())
        case .noSelection: Image(systemName: "cursorarrow.rays").foregroundStyle(KColor.secondary)
        default: QwixitMark(size: 19, animated: phase == .processing)
        }
    }

    private var title: String {
        switch phase { case .ready: "Ready"; case .processing: "Qwixing…"; case .success: "Qwixed!"; case .noSelection: "Select some text first"; case .permissionDenied: "Accessibility access needed"; case .lastFreeAction: "30 actions used — go Unlimited"; case .subscriptionActivating: "Activating Unlimited…"; case .limitReached: "Free limit reached"; case .offline: "No internet connection"; default: "Something went wrong" }
    }
    private var detail: String? {
        switch phase { case .permissionDenied: "OPEN SYSTEM SETTINGS"; case .lastFreeAction: "SUBSCRIBE FOR UNLIMITED ACTIONS"; case .subscriptionActivating: "PADDLE IS SYNCING YOUR SUBSCRIPTION"; case .offline: "Your text is unchanged. Try again when you’re back online."; case .limitReached: "SUBSCRIBE FOR UNLIMITED ACTIONS"; case .error(let message): message; default: nil }
    }
    private var borderColor: Color { if case .error = phase { return KColor.danger.opacity(0.7) }; return phase == .permissionDenied ? KColor.magenta.opacity(0.5) : KColor.line }

    private var limitCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Text("YOU’RE OUT OF TOKENS!")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .tracking(2.2)
                    .foregroundStyle(KColor.magenta)
                QwixitFaceView(face: .pay, size: 19, bracketed: true, reduceMotion: reduceMotion)
                Spacer()
                LimitDismissButton(action: onClose)
            }

            Text("Two coffees or unlimited Qwixit?")
                .font(.system(size: 26, weight: .bold))

            VStack(spacing: 10) {
                ledgerRow("flat white × 2", amount: "$10.00", muted: true, struck: true)
                ledgerRow("qwixit unlimited", amount: "$10.00")
                Rectangle().fill(KColor.secondary.opacity(0.35)).frame(height: 1).padding(.vertical, 2)
                HStack(spacing: 8) {
                    Text("your call").foregroundStyle(KColor.magenta)
                    ledgerDots(color: KColor.magenta.opacity(0.5))
                    QwixitFaceView(face: .upsell, size: 16, bracketed: true, reduceMotion: reduceMotion)
                }
                .font(.system(size: 14, weight: .bold, design: .monospaced))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(KColor.canvas)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            HStack {
                Spacer()
                Button {
                    _ = PaddleCheckoutOpener().openStarterCheckout()
                    onClose()
                } label: {
                    HStack(spacing: 12) {
                        Text("Well, I can buy 2 coffees")
                        Text("$10/mo").font(.system(size: 13, weight: .bold, design: .monospaced))
                        QwixitFaceView(face: .pay, size: 16, bracketed: true, reduceMotion: reduceMotion, color: .white)
                        Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .bold))
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(red: 0.28, green: 0.08, blue: 0.78))
                    .padding(.horizontal, 15)
                    .frame(height: 44)
                    .background(Color(red: 0.95, green: 0.92, blue: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(KColor.violet.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(width: 530, alignment: .leading)
        .background(KColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(KColor.magenta.opacity(0.75), lineWidth: 1))
        .padding(6)
    }

    private func ledgerRow(_ title: String, amount: String, muted: Bool = false, struck: Bool = false) -> some View {
        HStack(spacing: 10) {
            Text(title).foregroundStyle(muted ? KColor.secondary : KColor.ink).strikethrough(struck)
            ledgerDots(color: KColor.secondary.opacity(0.48))
            Text(amount).foregroundStyle(muted ? KColor.secondary : KColor.ink).strikethrough(struck)
        }
        .font(.system(size: 14, weight: .bold, design: .monospaced))
    }

    private func ledgerDots(color: Color) -> some View {
        GeometryReader { proxy in
            Path { path in
                path.move(to: .init(x: 0, y: proxy.size.height / 2))
                path.addLine(to: .init(x: proxy.size.width, y: proxy.size.height / 2))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [1, 4]))
        }
        .frame(height: 8)
    }
}

private struct LimitDismissButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(KColor.secondary)
                .frame(width: 24, height: 24)
                .background(KColor.canvasRaised)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help("Close")
        .accessibilityLabel("Close subscription offer")
    }
}

private struct CyberRewriteLabel: View {
    let text: String
    let reduceMotion: Bool

    var body: some View {
        if reduceMotion {
            staticLabel
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                let duration = 0.56
                let raw = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: duration) / duration
                let progress = min(raw / 0.75, 1)
                let eased = progress < 0.5
                    ? 2 * progress * progress
                    : 1 - pow(-2 * progress + 2, 2) / 2
                let characters = Array(text)
                let head = CGFloat(eased) * CGFloat(characters.count + 4) - 2

                HStack(spacing: 0.45) {
                    ForEach(Array(characters.enumerated()), id: \.offset) { index, character in
                        animatedGlyph(String(character), index: index, head: head)
                    }
                }
            }
        }
    }

    private var staticLabel: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .tracking(0.8)
            .foregroundStyle(.white.opacity(0.96))
    }

    private func animatedGlyph(_ glyph: String, index: Int, head: CGFloat) -> some View {
        let distance = CGFloat(index) - head
        let energy = max(0, 1 - abs(distance) / 2.35)
        let isBehind = distance < 0
        let lift = isBehind ? energy * 1.1 : -energy * 2.3

        return ZStack {
            glyphText(glyph, color: KColor.cyan)
                .offset(x: -energy * 1.8, y: lift)
                .opacity(energy * 0.78)
            glyphText(glyph, color: KColor.magenta)
                .offset(x: energy * 1.8, y: lift)
                .opacity(energy * 0.78)
            glyphText(glyph, color: .white.opacity(0.96))
                .offset(y: lift)
                .opacity(isBehind ? 1 : 1 - energy * 0.35)
        }
        .frame(width: 7.05, height: 13)
        .rotation3DEffect(
            .degrees(Double((isBehind ? 1 : -1) * energy * 34)),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.48
        )
    }

    private func glyphText(_ glyph: String, color: Color) -> some View {
        Text(glyph)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
    }
}
