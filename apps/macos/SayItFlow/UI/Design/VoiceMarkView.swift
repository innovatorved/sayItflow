import AppKit
import SwiftUI

/// Unified minimal monochrome waveform brand mark: 4 rounded vertical bars + terracotta accent dot
public struct WaveformBrandMark: View {
    public var size: CGFloat = 20
    public var tint: Color = Color(red: 20/255, green: 20/255, blue: 19/255) // #141413 deep charcoal
    public var accentColor: Color = Color(red: 217/255, green: 119/255, blue: 87/255) // #D97757 terracotta
    public var showAccentDot: Bool = true

    // Relative bar heights: [0.45, 1.0, 0.70, 0.35]
    private let relHeights: [CGFloat] = [0.45, 1.0, 0.70, 0.35]

    public init(
        size: CGFloat = 20,
        tint: Color = Color(red: 20/255, green: 20/255, blue: 19/255),
        accentColor: Color = Color(red: 217/255, green: 119/255, blue: 87/255),
        showAccentDot: Bool = true
    ) {
        self.size = size
        self.tint = tint
        self.accentColor = accentColor
        self.showAccentDot = showAccentDot
    }

    public var body: some View {
        let barWidth = max(1.5, size * 0.125)
        let barSpacing = max(1.2, size * 0.11)
        let dotDiameter = max(2.0, size * 0.16)
        let dotGap = max(1.5, size * 0.13)
        let maxBarHeight = size * 0.85

        HStack(alignment: .center, spacing: barSpacing) {
            ForEach(0..<relHeights.count, id: \.self) { i in
                RoundedRectangle(cornerRadius: barWidth / 2.0)
                    .fill(tint)
                    .frame(width: barWidth, height: max(2, maxBarHeight * relHeights[i]))
            }

            if showAccentDot {
                Circle()
                    .fill(accentColor)
                    .frame(width: dotDiameter, height: dotDiameter)
                    .padding(.leading, dotGap - barSpacing)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Backward-compatible waveform shape representing the 4-bar mark
struct VLogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let relHeights: [CGFloat] = [0.45, 1.0, 0.70, 0.35]
        let barWidth = rect.height * 0.125
        let barSpacing = rect.height * 0.11
        let dotGap = rect.height * 0.13
        let dotDiameter = rect.height * 0.16
        let totalWidth = (4 * barWidth) + (3 * barSpacing) + dotGap + dotDiameter
        var curX = rect.midX - totalWidth / 2.0

        for rh in relHeights {
            let bh = rect.height * rh * 0.85
            let barRect = CGRect(x: curX, y: rect.midY - bh / 2.0, width: barWidth, height: bh)
            path.addRoundedRect(in: barRect, cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2))
            curX += barWidth + barSpacing
        }

        curX += dotGap - barSpacing
        let dotRect = CGRect(x: curX, y: rect.midY - dotDiameter / 2.0, width: dotDiameter, height: dotDiameter)
        path.addEllipse(in: dotRect)
        return path
    }
}

/// Standalone icon mark inside a rounded 1px border box as defined in design system
struct LogoMark: View {
    enum Size {
        case sm, md, lg

        var boxSize: CGFloat {
            switch self {
            case .sm: 28 // 7rem (28px)
            case .md: 32 // 8rem (32px)
            case .lg: 40 // 10rem (40px)
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .sm: 14
            case .md: 16
            case .lg: 20
            }
        }

        var cornerRadius: CGFloat {
            DesignTokens.radiusMd
        }
    }

    var size: Size = .md
    var tint: Color = DesignTokens.textPrimary

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .fill(DesignTokens.surfaceSubtle)
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .stroke(DesignTokens.borderPrimary, lineWidth: 1)

            WaveformBrandMark(
                size: size.iconSize,
                tint: tint,
                accentColor: Color(red: 217/255, green: 119/255, blue: 87/255)
            )
        }
        .frame(width: size.boxSize, height: size.boxSize)
    }
}

/// App header lockup with companion icon, title & tagline
struct BrandLockup: View {
    var size: LogoMark.Size = .md
    var title: String = "SayItFlow"
    var tagline: String = "On-Device Neural Dictation"

    var body: some View {
        HStack(spacing: 12) {
            LogoMark(size: size)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: size == .lg ? 16 : 14, weight: .semibold))
                    .tracking(-0.03)
                    .foregroundStyle(DesignTokens.textPrimary)

                if !tagline.isEmpty {
                    Text(tagline)
                        .font(.system(size: size == .lg ? 12 : 11, weight: .regular))
                        .foregroundStyle(DesignTokens.textSecondary)
                }
            }
        }
    }
}

/// Brand voice waveform — drawn in SwiftUI for in-app surfaces.
struct VoiceMarkShape: View {
    var compact: Bool = false
    var color: Color = DesignTokens.textPrimary
    var accentColor: Color = Color(red: 217/255, green: 119/255, blue: 87/255)

    private var relHeights: [CGFloat] { [0.45, 1.0, 0.70, 0.35] }
    private var maxBarHeight: CGFloat { compact ? 12 : 14 }
    private var barWidth: CGFloat { compact ? 2.5 : 3.0 }
    private var barSpacing: CGFloat { compact ? 1.5 : 2.0 }
    private var dotDiameter: CGFloat { compact ? 2.5 : 3.0 }
    private var dotGap: CGFloat { compact ? 2.0 : 2.5 }
    private var cornerRadius: CGFloat { 1.5 }

    var body: some View {
        HStack(alignment: .center, spacing: barSpacing) {
            ForEach(0 ..< relHeights.count, id: \.self) { index in
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(color)
                    .frame(width: barWidth, height: maxBarHeight * relHeights[index])
            }

            Circle()
                .fill(accentColor)
                .frame(width: dotDiameter, height: dotDiameter)
                .padding(.leading, dotGap - barSpacing)
        }
    }
}

struct VoiceMarkView: View {
    var size: CGFloat = 18
    var tint: Color = DesignTokens.textPrimary

    var body: some View {
        WaveformBrandMark(size: size, tint: tint)
    }
}

/// AppKit template bitmap for MenuBarExtra
enum MenuBarIconRenderer {
    private static let pointSize = NSSize(width: 18, height: 18)
    private static let relHeights: [CGFloat] = [0.45, 1.0, 0.70, 0.35]
    private static let maxHeight: CGFloat = 11.0
    private static let barWidth: CGFloat = 2.0
    private static let barSpacing: CGFloat = 1.4
    private static let dotDiameter: CGFloat = 2.2
    private static let dotGap: CGFloat = 1.8
    private static let cornerRadius: CGFloat = 1.0

    @MainActor
    static func icon(for appState: AppState) -> NSImage {
        _ = appState
        return templateIcon
    }

    /// Single monochrome template — AppKit tints black/white for light/dark menu bar chrome.
    private static let templateIcon: NSImage = {
        let image = NSImage(size: pointSize, flipped: true) { rect in
            NSColor.clear.setFill()
            rect.fill()
            NSColor.black.setFill()

            let totalWidth = (4.0 * barWidth) + (3.0 * barSpacing) + dotGap + dotDiameter
            var x = (rect.width - totalWidth) / 2.0

            for rh in relHeights {
                let height = maxHeight * rh
                let y = (rect.height - height) / 2.0
                let bar = NSRect(x: x, y: y, width: barWidth, height: height)
                NSBezierPath(roundedRect: bar, xRadius: cornerRadius, yRadius: cornerRadius).fill()
                x += barWidth + barSpacing
            }

            x += dotGap - barSpacing
            let dotY = (rect.height - dotDiameter) / 2.0
            let dotRect = NSRect(x: x, y: dotY, width: dotDiameter, height: dotDiameter)
            NSBezierPath(ovalIn: dotRect).fill()

            return true
        }
        image.isTemplate = true
        return image
    }()
}


