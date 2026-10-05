import SwiftUI

struct FeedbackPill: View {
    let phase: AppPhase
    let reduceMotion: Bool
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var trace = false
    @State private var successPulse = false
    @State private var borderSweep = false

    var body: some View {
        Group {
            if phase == .limitReached {
                upgradeCard(limitReached: true)
            } else if phase == .lastFreeAction {
                upgradeCard(limitReached: false)
            } else if phase == .processing || phase == .success {
                cyberStatusBox
            } else {
                compactNotice
            }
        }
        .foregroundStyle(KColor.ink)
        .padding(6)
        .qwixitTheme()
        .onAppear {
            if phase == .processing, !reduceMotion {
                withAnimation(.linear(duration: 0.46).repeatForever(autoreverses: false)) { trace = true }
            }
            if phase == .success, !reduceMotion {
                withAnimation(.easeOut(duration: 0.72)) { successPulse = true }
            }
            if (phase == .processing || phase == .success), !reduceMotion {
                withAnimation(.linear(duration: 0.64).repeatForever(autoreverses: false)) { borderSweep = true }
            }
        }
    }

    private var cyberStatusBox: some View {
        HStack(spacing: 10) {
            statusGlyph

            VStack(alignment: .leading, spacing: 5) {
                if phase == .processing {
                    HStack(spacing: 3) {
                        Text(">").foregroundStyle(KColor.cyan)
                        CyberRewriteLabel(text: "PROCESSING", reduceMotion: reduceMotion)
                    }
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                } else {
                    Text("READY")
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
                            .foregroundStyle(cyberSecondary)
                    }
                    .frame(height: 2)
                }
            }

            Spacer(minLength: 2)

            Text(phase == .success ? "OK" : "AI")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(phase == .success ? KColor.terminalGreen : KColor.magenta)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 12)
        .frame(width: 224, height: 46)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 11)
                    .fill(cyberSurface)
                LinearGradient(
                    colors: [
                        KColor.violet.opacity(colorScheme == .dark ? 0.16 : 0.08),
                        .clear,
                        KColor.cyan.opacity(colorScheme == .dark ? 0.08 : 0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 11))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(cyberBorder, lineWidth: 1)
        }
        .overlay(alignment: .topLeading) {
            LinearGradient(
                colors: [.clear, KColor.magenta, cyberSweepHighlight, KColor.cyan, .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 68, height: 1)
            .offset(x: borderSweep ? 224 : -68)
            .mask(RoundedRectangle(cornerRadius: 11).stroke(lineWidth: 1))
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(phase == .success ? KColor.terminalGreen : KColor.violet)
                .frame(width: 2, height: 24)
                .shadow(
                    color: (phase == .success ? KColor.terminalGreen : KColor.magenta).opacity(0.8),
                    radius: 5
                )
        }
        .shadow(color: KColor.violet.opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 16, y: 6)
    }

    private var statusGlyph: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    phase == .success ? KColor.terminalGreen.opacity(0.55) : KColor.violet.opacity(0.34),
                    lineWidth: 1
                )
                .frame(width: 57, height: 27)
                .scaleEffect(successPulse ? 1.18 : 1)
                .opacity(successPulse ? 0 : 1)
            QwixitFaceView(
                face: phase == .processing ? .upsell : .ready,
                size: 13,
                bracketed: true,
                reduceMotion: reduceMotion,
                color: cyberPrimary
            )
        }
        .frame(width: 59, height: 29)
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

    private var compactNotice: some View {
        HStack(spacing: 11) {
            noticeIcon

            VStack(alignment: .leading, spacing: detail == nil ? 0 : 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                if let detail {
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(KColor.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .qwixitPanel(cornerRadius: 13, accent: tone)
    }

    private var noticeIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(tone.opacity(0.10))
                .frame(width: 32, height: 32)

            switch phase {
            case .processing:
                QwixitMark(size: 21, animated: !reduceMotion)
            case .success:
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tone)
            case .noSelection:
                Image(systemName: "text.cursor")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tone)
            case .permissionDenied:
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tone)
            case .subscriptionActivating:
                ProgressView()
                    .controlSize(.small)
                    .tint(tone)
            case .offline:
                Image(systemName: "wifi.slash")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tone)
            case .error:
                Image(systemName: "exclamationmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tone)
            default:
                QwixitMark(size: 20)
            }
        }
        .frame(width: 32, height: 32)
    }

    private func upgradeCard(limitReached: Bool) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 11) {
                QwixitFaceView(
                    face: limitReached ? .pay : .hello,
                    size: 16,
                    bracketed: true,
                    reduceMotion: reduceMotion,
                    color: KColor.violet
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(limitReached ? "Ready for more?" : "Looks like you like the process!")
                        .font(.system(size: 16, weight: .bold))
                    Text(limitReached
                         ? "You’ve used 30 free Qwixes this month."
                         : "That was your last free Qwix.")
                        .font(.system(size: 11))
                        .foregroundStyle(KColor.secondary)
                }

                Spacer(minLength: 4)
                dismissButton
            }

            Button {
                _ = PaddleCheckoutOpener().openStarterCheckout()
                onClose()
            } label: {
                HStack(spacing: 7) {
                    Text("Get Unlimited")
                    Text("$10/mo")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .opacity(0.82)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .qwixitPanel(cornerRadius: 14, accent: KColor.violet)
    }

    private var dismissButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(KColor.secondary)
                .frame(width: 25, height: 25)
                .background(KColor.surfaceHover)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Close")
        .accessibilityLabel("Close")
    }

    private var title: String {
        switch phase {
        case .ready: "Ready"
        case .processing: "Qwixing your text…"
        case .success: "Text replaced"
        case .noSelection: "Select some text first"
        case .permissionDenied: "Accessibility access needed"
        case .subscriptionActivating: "Activating Unlimited…"
        case .offline: "You’re offline"
        case .error(let message): QwixitErrorCopy.title(for: message)
        case .lastFreeAction, .limitReached: ""
        }
    }

    private var detail: String? {
        switch phase {
        case .noSelection: "Highlight text in any app, then try again."
        case .permissionDenied: "Allow Qwixit in System Settings to continue."
        case .subscriptionActivating: "Your subscription is still syncing."
        case .offline: "Your text is unchanged. Try again when you’re back online."
        case .error(let message): message
        default: nil
        }
    }

    private var tone: Color {
        switch phase {
        case .success: KColor.success
        case .permissionDenied: KColor.warning
        case .offline: KColor.cyan
        case .error: KColor.danger
        case .processing: KColor.violet
        default: KColor.secondary
        }
    }

    private var cyberSurface: Color {
        colorScheme == .dark
            ? Color(red: 0.055, green: 0.047, blue: 0.085).opacity(0.96)
            : KColor.surface.opacity(0.98)
    }

    private var cyberPrimary: Color {
        colorScheme == .dark ? .white.opacity(0.96) : KColor.ink
    }

    private var cyberSecondary: Color {
        colorScheme == .dark ? .white.opacity(0.52) : KColor.secondary
    }

    private var cyberBorder: Color {
        colorScheme == .dark ? .white.opacity(0.12) : KColor.line
    }

    private var cyberSweepHighlight: Color {
        colorScheme == .dark ? .white : KColor.ink.opacity(0.72)
    }
}

private struct CyberRewriteLabel: View {
    let text: String
    let reduceMotion: Bool

    @Environment(\.colorScheme) private var colorScheme

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
            .foregroundStyle(baseColor)
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
            glyphText(glyph, color: baseColor)
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

    private var baseColor: Color {
        colorScheme == .dark ? .white.opacity(0.96) : KColor.ink
    }
}
