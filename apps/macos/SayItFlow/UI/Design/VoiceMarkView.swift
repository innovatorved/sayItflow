import AppKit
import SwiftUI

/// Signature SayItFlow 3-Bar Waveform Mark inside the Yellow Neo-Brutalist Badge
/// Matches Android `LofiHeaderBar` in `DashboardScreen.kt` (3 vertical #1B1712 bars: short left, tall center, medium right).
public struct WaveformBrandMark: View {
    public var size: CGFloat = 18
    public var tint: Color = DesignTokens.ink
    public var accentColor: Color = DesignTokens.accentYellow
    public var showAccentDot: Bool = false

    // Exact relative bar heights from Android LofiHeaderBar: [9/16, 16/16, 11/16]
    private let relHeights: [CGFloat] = [0.5625, 1.0, 0.6875]

    public init(
        size: CGFloat = 18,
        tint: Color = DesignTokens.ink,
        accentColor: Color = DesignTokens.accentYellow,
        showAccentDot: Bool = false
    ) {
        self.size = size
        self.tint = tint
        self.accentColor = accentColor
        self.showAccentDot = showAccentDot
    }

    public var body: some View {
        let barWidth = max(2.5, size * 0.175)
        let barSpacing = max(2.0, size * 0.145)
        let maxBarHeight = size * 0.92

        HStack(alignment: .center, spacing: barSpacing) {
            ForEach(0..<relHeights.count, id: \.self) { i in
                RoundedRectangle(cornerRadius: barWidth / 2.0)
                    .fill(tint)
                    .frame(width: barWidth, height: max(3, maxBarHeight * relHeights[i]))
            }
        }
        .frame(width: size, height: size)
    }
}

/// 3-bar waveform shape
struct VLogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let relHeights: [CGFloat] = [0.5625, 1.0, 0.6875]
        let barWidth = rect.height * 0.175
        let barSpacing = rect.height * 0.145
        let totalWidth = (3 * barWidth) + (2 * barSpacing)
        var curX = rect.midX - totalWidth / 2.0

        for rh in relHeights {
            let bh = rect.height * rh * 0.92
            let barRect = CGRect(x: curX, y: rect.midY - bh / 2.0, width: barWidth, height: bh)
            path.addRoundedRect(in: barRect, cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2))
            curX += barWidth + barSpacing
        }
        return path
    }
}

/// Monitor YT Playful Yellow Boxed Brand Badge (`#FFCE4A` fill, `2pt` `#1B1712` border, hard `#1B1712` offset shadow, 3 `#1B1712` bars)
/// Exact 1:1 match with `LofiHeaderBar` in Android `DashboardScreen.kt`.
struct LogoMark: View {
    enum Size {
        case sm, md, lg

        var boxSize: CGFloat {
            switch self {
            case .sm: 30
            case .md: 34
            case .lg: 42
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .sm: 15
            case .md: 17
            case .lg: 21
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .sm: 8
            case .md: 10
            case .lg: 12
            }
        }

        var shadowOffset: CGFloat {
            switch self {
            case .sm: 2.0
            case .md: 2.5
            case .lg: 3.0
            }
        }
    }

    var size: Size = .md
    var tint: Color = DesignTokens.ink
    var fill: Color = DesignTokens.accentYellow

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .fill(DesignTokens.ink)
                .offset(x: size.shadowOffset, y: size.shadowOffset)
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .fill(fill)
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .strokeBorder(DesignTokens.ink, lineWidth: 2)

            WaveformBrandMark(
                size: size.iconSize,
                tint: tint
            )
        }
        .frame(width: size.boxSize, height: size.boxSize)
        .padding(.trailing, size.shadowOffset)
        .padding(.bottom, size.shadowOffset)
    }
}

/// App header lockup with Monitor YT Yellow 3-Bar Boxed Icon, bold grotesque title & `LO-FI VOICE` badge
struct BrandLockup: View {
    var size: LogoMark.Size = .md
    var title: String = "SayItFlow"
    var tagline: String = "LO-FI VOICE"

    var body: some View {
        HStack(spacing: 10) {
            LogoMark(size: size)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: size == .lg ? 20 : 17, weight: .heavy))
                        .tracking(-0.5)
                        .foregroundStyle(DesignTokens.ink)

                    Text("LO-FI VOICE")
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundStyle(DesignTokens.ink)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DesignTokens.paperDeep, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(DesignTokens.ink, lineWidth: 1.5)
                        )
                }

                if !tagline.isEmpty && tagline != "LO-FI VOICE" {
                    Text(tagline)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(DesignTokens.inkSoft)
                }
            }
        }
    }
}

/// Brand voice waveform — 3 vertical bars drawn in SwiftUI for in-app surfaces.
struct VoiceMarkShape: View {
    var compact: Bool = false
    var color: Color = DesignTokens.ink
    var accentColor: Color = DesignTokens.accentYellow

    private var relHeights: [CGFloat] { [0.5625, 1.0, 0.6875] }
    private var maxBarHeight: CGFloat { compact ? 13 : 16 }
    private var barWidth: CGFloat { compact ? 2.5 : 3.0 }
    private var barSpacing: CGFloat { compact ? 2.0 : 2.5 }
    private var cornerRadius: CGFloat { 1.5 }

    var body: some View {
        HStack(alignment: .center, spacing: barSpacing) {
            ForEach(0 ..< relHeights.count, id: \.self) { index in
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(color)
                    .frame(width: barWidth, height: maxBarHeight * relHeights[index])
            }
        }
    }
}

struct VoiceMarkView: View {
    var size: CGFloat = 18
    var tint: Color = DesignTokens.ink

    var body: some View {
        WaveformBrandMark(size: size, tint: tint)
    }
}

/// AppKit MenuBarExtra icon — 3 vertical rounded bars matching the SayItFlow brand icon
enum MenuBarIconRenderer {
    private static let pointSize = NSSize(width: 18, height: 18)
    private static let relHeights: [CGFloat] = [0.5625, 1.0, 0.6875]
    private static let maxHeight: CGFloat = 12.5
    private static let barWidth: CGFloat = 2.6
    private static let barSpacing: CGFloat = 2.2
    private static let cornerRadius: CGFloat = 1.3

    @MainActor
    static func icon(for appState: AppState) -> NSImage {
        let isRecording: Bool = {
            if case .recording = appState.phase { return true }
            return false
        }()

        let img = NSImage(size: pointSize, flipped: false) { rect in
            let totalWidth = (CGFloat(relHeights.count) * barWidth)
                + (CGFloat(relHeights.count - 1) * barSpacing)
            var curX = (rect.width - totalWidth) / 2.0
            let midY = rect.height / 2.0

            NSColor.black.setFill()
            for rh in relHeights {
                let bh = maxHeight * rh * (isRecording ? 1.08 : 1.0)
                let barRect = NSRect(x: curX, y: midY - bh / 2.0, width: barWidth, height: bh)
                let path = NSBezierPath(roundedRect: barRect, xRadius: cornerRadius, yRadius: cornerRadius)
                path.fill()
                curX += barWidth + barSpacing
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}
