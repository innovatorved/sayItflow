import AppKit
import SwiftUI

/// Official Ved Gupta Geometric V Logo
struct VLogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        // Precision geometric V glyph
        path.move(to: CGPoint(x: w * 0.15, y: h * 0.2))
        path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.8))
        path.addLine(to: CGPoint(x: w * 0.85, y: h * 0.2))
        path.addLine(to: CGPoint(x: w * 0.70, y: h * 0.2))
        path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.58))
        path.addLine(to: CGPoint(x: w * 0.30, y: h * 0.2))
        path.closeSubpath()
        return path
    }
}

/// Standalone icon mark inside a rounded 1px border box as defined in Ved Gupta design system
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

            VLogoShape()
                .fill(tint)
                .frame(width: size.iconSize, height: size.iconSize)
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

    private var barWidths: [CGFloat] { compact ? [3, 3, 3, 3, 3] : [3, 3, 3, 3, 3] }
    private var barHeights: [CGFloat] { compact ? [5, 8, 12, 8, 5] : [6, 10, 14, 10, 6] }
    private var barSpacing: CGFloat { compact ? 1.5 : 2.0 }
    private var cornerRadius: CGFloat { 1.5 }

    var body: some View {
        HStack(alignment: .center, spacing: barSpacing) {
            ForEach(0 ..< barHeights.count, id: \.self) { index in
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(color)
                    .frame(width: barWidths[index], height: barHeights[index])
            }
        }
    }
}

struct VoiceMarkView: View {
    var size: CGFloat = 18
    var tint: Color = DesignTokens.textPrimary

    var body: some View {
        VoiceMarkShape(compact: size <= 18, color: tint)
            .frame(width: size, height: size)
    }
}

/// AppKit template bitmap for MenuBarExtra
enum MenuBarIconRenderer {
    private static let pointSize = NSSize(width: 18, height: 18)
    private static let barWidths: [CGFloat] = [3, 3, 3, 3, 3]
    private static let barHeights: [CGFloat] = [5, 8, 12, 8, 5]
    private static let barSpacing: CGFloat = 1.25
    private static let cornerRadius: CGFloat = 1.5

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
            let totalWidth = barWidths.reduce(0, +) + barSpacing * CGFloat(barWidths.count - 1)
            var x = (rect.width - totalWidth) / 2
            for index in barWidths.indices {
                let height = barHeights[index]
                let y = (rect.height - height) / 2
                let bar = NSRect(x: x, y: y, width: barWidths[index], height: height)
                NSBezierPath(roundedRect: bar, xRadius: cornerRadius, yRadius: cornerRadius).fill()
                x += barWidths[index] + barSpacing
            }
            return true
        }
        image.isTemplate = true
        return image
    }()
}


