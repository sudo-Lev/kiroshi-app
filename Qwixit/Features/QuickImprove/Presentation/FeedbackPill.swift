import SwiftUI

struct FeedbackPill: View {
    let phase: AppPhase
    let reduceMotion: Bool
    let successDetail: String
    let embedded: Bool
    let onClose: () -> Void
    let onUpgrade: (() -> Void)?

    init(
        phase: AppPhase,
        reduceMotion: Bool,
        successDetail: String = "TEXT REPLACED",
        embedded: Bool = false,
        onClose: @escaping () -> Void,
        onUpgrade: (() -> Void)? = nil
    ) {
        self.phase = phase
        self.reduceMotion = reduceMotion
        self.successDetail = successDetail
        self.embedded = embedded
        self.onClose = onClose
        self.onUpgrade = onUpgrade
    }

    @Environment(\.colorScheme) private var colorScheme
    @State private var trace = false
    @State private var successPulse = false
    @State private var borderSweep = false

    var body: some View {
        Group {
            if phase == .limitReached {
                upgradeCard
            } else if phase == .permissionDenied {
                accessNotice
            } else if usesCyberStatus {
                cyberStatusBox
            } else {
                compactNotice
            }
        }
        .foregroundStyle(KColor.ink)
        .padding(embedded || phase == .limitReached ? 0 : usesCyberStatus ? 5 : 6)
        .qwixitTheme()
        .onAppear {
            if isProcessingLike, !reduceMotion {
                withAnimation(.linear(duration: 0.46).repeatForever(autoreverses: false)) { trace = true }
            }
            if (phase == .success || phase == .pasteSent), !reduceMotion {
                withAnimation(.easeOut(duration: 0.72)) { successPulse = true }
            }
            if (isProcessingLike || phase == .success || phase == .pasteSent), !reduceMotion {
                withAnimation(.linear(duration: 0.64).repeatForever(autoreverses: false)) { borderSweep = true }
            }
        }
    }

    private var accessNotice: some View {
        HStack(spacing: 10) {
            ZStack {
                QwixitControlShape(cut: 5)
                    .fill(KColor.warning.opacity(0.16))
                    .frame(width: 35, height: 35)
                TokiriUI.Icon(.lock, size: 13)
                    .foregroundStyle(KColor.warning)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(detail ?? "")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(1)
            }

            Spacer(minLength: 3)

            Text("AX")
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundStyle(KColor.warning)
                .padding(.horizontal, 6)
                .frame(height: 22)
                .background(
                    QwixitControlShape(cut: 4)
                        .fill(KColor.warning.opacity(0.08))
                )
                .overlay {
                    QwixitControlShape(cut: 4)
                        .stroke(KColor.warning.opacity(0.58), lineWidth: 1)
                }
        }
        .padding(.horizontal, 12)
        .frame(width: 314, height: 68)
        .background {
            ZStack {
                QwixitControlShape(cut: 9)
                    .fill(KColor.cyan)
                    .offset(x: -1.5, y: 1)
                QwixitControlShape(cut: 9)
                    .fill(KColor.magenta)
                    .offset(x: 1.5, y: -1)
                QwixitControlShape(cut: 9)
                    .fill(KColor.primaryAction)
            }
        }
        .overlay {
            QwixitControlShape(cut: 9)
                .stroke(KColor.violet.opacity(0.9), lineWidth: 1)
        }
        .overlay(alignment: .topLeading) {
            Rectangle()
                .fill(.white.opacity(0.72))
                .frame(width: 28, height: 1)
                .offset(x: 10, y: 5)
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(KColor.warning)
                .frame(width: 2, height: 34)
        }
        .shadow(color: KColor.cardShadow, radius: 12, y: 5)
    }

    private var cyberStatusBox: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 8) {
                statusGlyph

                VStack(alignment: .leading, spacing: 4) {
                    if isProcessingLike {
                        HStack(spacing: 3) {
                            Text(">").foregroundStyle(KColor.cyan)
                            CyberRewriteLabel(text: "PROCESSING", reduceMotion: reduceMotion)
                        }
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                    } else {
                        Text(statusHeadline)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(isError ? 0.65 : 1.1)
                            .foregroundStyle(statusTone)
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                    }

                    if phase == .processing {
                        progressTrace
                    } else if isRetrying {
                        HStack(spacing: 5) {
                            Rectangle().fill(KColor.hudTone).frame(width: 11, height: 1)
                            Text(statusDetail)
                                .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                                .tracking(0.6)
                                .foregroundStyle(cyberSecondary)
                                .lineLimit(1)
                        }
                        .frame(height: 2, alignment: .leading)
                    } else {
                        HStack(spacing: 5) {
                            Rectangle().fill(statusTone).frame(width: 11, height: 1)
                            Text(statusDetail)
                                .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                                .tracking(isError ? 0.6 : 0.85)
                                .foregroundStyle(cyberSecondary)
                                .lineLimit(isError ? 2 : 1)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(height: isError ? 20 : 2, alignment: .leading)
                    }
                }

                Spacer(minLength: 2)

                Text(statusBadge)
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .tracking(0.65)
                    .foregroundStyle(statusTone)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                if isDismissible && !embedded {
                    TokiriUI.PopupCloseButton(
                        shortcut: HotkeyCatalog.popupDismiss.presentation,
                        label: phase == .offline ? "Close offline status" : "Close error",
                        action: onClose
                    )
                }
            }
            .padding(.horizontal, 10)
        }
        .frame(width: embedded ? nil : cyberStatusWidth, height: cyberStatusHeight)
        .frame(maxWidth: embedded ? .infinity : nil)
        .background {
            ZStack {
                QwixitControlShape(cut: 7)
                    .fill(KColor.cyan.opacity(colorScheme == .dark ? 0.38 : 0.58))
                    .offset(x: -1.5, y: 1)
                QwixitControlShape(cut: 7)
                    .fill(KColor.magenta.opacity(colorScheme == .dark ? 0.38 : 0.58))
                    .offset(x: 1.5, y: -1)
                QwixitControlShape(cut: 7).fill(cyberSurface)
                LinearGradient(
                    colors: [
                        colorScheme == .dark
                            ? Color(nsColor: KColor.hex(0xA98BFF, alpha: 0.08))
                            : Color(nsColor: KColor.hex(0x8F6BFF, alpha: 0.05)),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(QwixitControlShape(cut: 7))
            }
        }
        .overlay {
            QwixitControlShape(cut: 7)
                .stroke(cyberBorder, lineWidth: 1)
        }
        .overlay(alignment: .topLeading) {
            LinearGradient(
                colors: [.clear, KColor.magenta, cyberSweepHighlight, KColor.cyan, .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 56, height: 1)
            .offset(x: borderSweep ? 206 : -56)
            .mask(QwixitControlShape(cut: 7).stroke(lineWidth: 1))
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(statusTone)
                .frame(width: 2, height: 24)
                .shadow(
                    color: statusTone.opacity(0.8),
                    radius: 5
                )
        }
        .shadow(
            color: colorScheme == .dark ? .black.opacity(0.45) : Color(nsColor: KColor.hex(0x16131F, alpha: 0.10)),
            radius: colorScheme == .dark ? 16 : 14,
            y: 6
        )
    }

    private var statusGlyph: some View {
        ZStack {
            QwixitControlShape(cut: 5)
                .stroke(
                    statusTone.opacity(isError ? 0.5 : 0.55),
                    lineWidth: 1
                )
                .frame(width: 47, height: 23)
                .scaleEffect(successPulse ? 1.16 : 1)
                .opacity(successPulse ? 0 : 1)
            QwixitFaceView(
                face: statusFace,
                size: 11,
                bracketed: true,
                reduceMotion: reduceMotion,
                color: cyberPrimary
            )
        }
        .frame(width: 49, height: 25)
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
                .frame(width: 36, height: 2)
                .offset(x: trace ? geometry.size.width : -36)
            }
        }
        .frame(width: 86, height: 2)
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
                QwixitLockup()
                    .frame(width: 28, height: 12)
            case .success:
                TokiriUI.Icon(.check, size: 13)
                    .foregroundStyle(tone)
            case .pasteSent:
                TokiriUI.Icon(.arrowRight, size: 13)
                    .foregroundStyle(tone)
            case .noSelection:
                TokiriUI.Icon(.textCursor, size: 14)
                    .foregroundStyle(tone)
            case .permissionDenied:
                TokiriUI.Icon(.lock, size: 12)
                    .foregroundStyle(tone)
            case .offline:
                TokiriUI.Icon(.wifiOff, size: 12)
                    .foregroundStyle(tone)
            case .error:
                TokiriUI.Icon(.warning, size: 13)
                    .foregroundStyle(tone)
            default:
                QwixitLockup()
                    .frame(width: 28, height: 12)
            }
        }
        .frame(width: 32, height: 32)
    }

    private var upgradeCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                QwixitLockup()
                    .frame(width: 86, height: 34, alignment: .leading)
                Text("Fix")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer()
                TokiriUI.PopupCloseButton(
                    shortcut: HotkeyCatalog.popupDismiss.presentation,
                    label: "Close Fix limit notice",
                    action: onClose
                )
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(KColor.canvasRaised)
            .overlay(alignment: .bottom) { Rectangle().fill(KColor.line).frame(height: 1) }

            QwixitPaywallUsageStrip(used: 30, remaining: 0, reduceMotion: reduceMotion)

            VStack(alignment: .leading, spacing: 0) {
                Text("30/30. You ran it dry.")
                    .font(.system(size: 20, weight: .black, design: .rounded))

                Text("Free ride’s over. Advanced gives you more room to work. Same quality bar.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(KColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 7)

                Spacer(minLength: 10)

                HStack(spacing: 9) {
                    if let onUpgrade {
                        Button {
                            onUpgrade()
                            onClose()
                        } label: {
                            Text("Get Advanced · $10")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityLabel("Get Tokiri Advanced for ten dollars per month")
                    }

                    Button("Nah", action: onClose)
                        .buttonStyle(SubtleButtonStyle())
                        .frame(width: 58)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 19)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .qwixitPanel(cornerRadius: 14, accent: KColor.violet)
    }

    private var title: String {
        switch phase {
        case .ready: "Ready"
        case .processing: "Sharpening your text…"
        case .success: "Text replaced"
        case .pasteSent: "Success"
        case .noSelection: "Select some text first"
        case .permissionDenied: "Accessibility access needed"
        case .offline: "You’re offline"
        case .retrying: "Retrying connection…"
        case .error(let message): QwixitErrorCopy.title(for: message)
        case .limitReached: ""
        }
    }

    private var detail: String? {
        switch phase {
        case .noSelection: "Highlight text in any app, then try again."
        case .permissionDenied: "Allow Tokiri in System Settings to continue."
        case .offline: "Your text is unchanged. Try again when you’re back online."
        case .retrying(let attempt, let total): "Trying again · \(attempt)/\(total)"
        case .error(let message): QwixitErrorCopy.detail(for: message)
        default: nil
        }
    }

    private var tone: Color {
        switch phase {
        case .success: KColor.success
        case .pasteSent: KColor.success
        case .permissionDenied: KColor.warning
        case .offline: KColor.cyan
        case .retrying: KColor.cyan
        case .error: KColor.danger
        case .processing: KColor.violet
        default: KColor.secondary
        }
    }

    private var cyberSurface: Color {
        colorScheme == .dark
            ? Color(nsColor: KColor.hex(0x121116, alpha: 0.96))
            : Color(nsColor: KColor.hex(0xFAFAFC, alpha: 0.98))
    }

    private var cyberPrimary: Color {
        colorScheme == .dark ? .white.opacity(0.96) : KColor.ink
    }

    private var cyberSecondary: Color {
        colorScheme == .dark ? .white.opacity(0.52) : KColor.secondary
    }

    private var cyberBorder: Color {
        colorScheme == .dark ? .white.opacity(0.07) : KColor.line
    }

    private var cyberSweepHighlight: Color {
        colorScheme == .dark ? .white : KColor.ink.opacity(0.72)
    }

    private var isError: Bool {
        if embedded && phase == .noSelection { return true }
        if case .error = phase { return true }
        return false
    }

    private var statusTone: Color {
        if isError { return KColor.danger }
        if phase == .offline { return KColor.cyan }
        if phase == .success { return KColor.terminalGreen }
        return phase == .pasteSent ? KColor.terminalGreen : KColor.hudTone
    }

    private var statusFace: QwixitFace {
        if embedded && phase == .noSelection { return .empty }
        if isRetrying { return .retry }
        if isError { return .retry }
        if phase == .offline { return .lost }
        return phase == .processing ? .scanning : .ready
    }

    private var statusHeadline: String {
        if embedded && phase == .noSelection { return "NO TEXT CAPTURED" }
        if phase == .pasteSent { return "SUCCESS" }
        if phase == .offline { return "CONNECTION LOST" }
        guard case .error(let message) = phase else { return "READY" }
        return QwixitErrorCopy.headline(for: message)
    }

    private var statusDetail: String {
        if embedded && phase == .noSelection { return "HIGHLIGHT TEXT · TRY PEEK AGAIN" }
        if case .retrying(let attempt, let total) = phase {
            return "RETRY \(attempt) OF \(total)"
        }
        if phase == .offline { return "TEXT UNCHANGED · TRY AGAIN" }
        if phase == .pasteSent { return "RESULT READY" }
        if isError, case .error(let message) = phase {
            return QwixitErrorCopy.detail(for: message)
        }
        return successDetail
    }

    private var statusBadge: String {
        if isError { return "ERR" }
        if phase == .offline { return "NET" }
        if phase == .success { return "OK" }
        return phase == .pasteSent ? "OK" : "AI"
    }

    private var usesCyberStatus: Bool {
        isProcessingLike || phase == .success || phase == .pasteSent || phase == .offline || isError
    }

    private var isDismissible: Bool {
        phase == .offline || isError
    }

    private var cyberStatusWidth: CGFloat {
        if isError { return 390 }
        if phase == .offline { return 350 }
        return 206
    }

    private var cyberStatusHeight: CGFloat {
        if isError { return 62 }
        if phase == .offline { return 46 }
        return 40
    }

    private var isRetrying: Bool {
        if case .retrying = phase { return true }
        return false
    }

    private var isProcessingLike: Bool {
        phase == .processing || isRetrying
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
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(0.65)
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
        .frame(width: 6.4, height: 12)
        .rotation3DEffect(
            .degrees(Double((isBehind ? 1 : -1) * energy * 34)),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.48
        )
    }

    private func glyphText(_ glyph: String, color: Color) -> some View {
        Text(glyph)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
    }

    private var baseColor: Color {
        colorScheme == .dark ? .white.opacity(0.96) : KColor.ink
    }
}
