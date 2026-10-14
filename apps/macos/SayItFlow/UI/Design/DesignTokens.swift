import AppKit
import SwiftUI

/// Ved Gupta Design System: Monochromatic Precision
/// Extracted from /Users/vedgupta/Desktop/design-system (tokens.json, COLOR_SYSTEM.md, AGENT.md, DESIGN_SYSTEM.md)
enum DesignTokens {
    // MARK: - Monochrome Palette

    static let black = Color(hex: 0x000000)
    static let white = Color(hex: 0xffffff)

    static let neutral50  = Color(hex: 0xfafafa)
    static let neutral100 = Color(hex: 0xf5f5f5)
    static let neutral200 = Color(hex: 0xe5e5e5)
    static let neutral300 = Color(hex: 0xd4d4d4)
    static let neutral400 = Color(hex: 0xa3a3a3)
    static let neutral500 = Color(hex: 0x737373)
    static let neutral600 = Color(hex: 0x525252)
    static let neutral700 = Color(hex: 0x404040)
    static let neutral800 = Color(hex: 0x262626)
    static let neutral900 = Color(hex: 0x171717)
    static let neutral950 = Color(hex: 0x0a0a0a)

    // MARK: - Surfaces & Canvas (Adaptive Light/Dark)

    /// Root page/window canvas. Pure OLED black in dark mode, pure white in light mode.
    static var canvas: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.isDark ? NSColor(hex: 0x000000) : NSColor(hex: 0xffffff)
        })
    }

    /// Primary card/modal surface. #0a0a0a in dark, white in light.
    static var surface: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.isDark ? NSColor(hex: 0x0a0a0a) : NSColor(hex: 0xffffff)
        })
    }

    /// Secondary surface (sub-cards, icon boxes, table headers). #171717 dark, #f5f5f5 light.
    static var surfaceSecondary: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.isDark ? NSColor(hex: 0x171717) : NSColor(hex: 0xf5f5f5)
        })
    }

    /// Subtle fill (row hovers, marketing asides). #171717 dark, #fafafa light.
    static var surfaceSubtle: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.isDark ? NSColor(hex: 0x171717) : NSColor(hex: 0xfafafa)
        })
    }

    /// Primary crisp 1px border. #262626 dark, #e5e5e5 light.
    static var borderPrimary: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.isDark ? NSColor(hex: 0x262626) : NSColor(hex: 0xe5e5e5)
        })
    }

    /// Subtle divider border. #1f1f1f dark, #f0f0f0 light.
    static var borderSubtle: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.isDark ? NSColor(hex: 0x1f1f1f) : NSColor(hex: 0xf0f0f0)
        })
    }

    /// Hover border. #525252 dark, #a1a1a1 light.
    static var borderHover: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.isDark ? NSColor(hex: 0x525252) : NSColor(hex: 0xa1a1a1)
        })
    }

    // MARK: - Typography Contrast Hierarchy

    /// Primary text. Pure white in dark, #0a0a0a in light.
    static var textPrimary: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.isDark ? NSColor(hex: 0xffffff) : NSColor(hex: 0x0a0a0a)
        })
    }

    /// Secondary text (captions, descriptions). #a3a3a3 dark, #525252 light.
    static var textSecondary: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.isDark ? NSColor(hex: 0xa3a3a3) : NSColor(hex: 0x525252)
        })
    }

    /// Muted text (micro-eyebrows, uppercase tags). #737373.
    static var textMuted: Color {
        neutral500
    }

    /// Ved Gupta signature selection blue.
    static let selection = Color(hex: 0x47a3f3)
    static let selectionForeground = Color(hex: 0xfefefe)

    // MARK: - Semantic Soft Tints (Badges & State)

    // Success (Green)
    static var successFg: Color {
        Color(nsColor: NSColor(name: nil) { $0.isDark ? NSColor(hex: 0x4ade80) : NSColor(hex: 0x15803d) })
    }
    static var successBg: Color {
        Color(nsColor: NSColor(name: nil) { $0.isDark ? NSColor(red: 5/255, green: 46/255, blue: 22/255, alpha: 0.3) : NSColor(hex: 0xf0fdf4) })
    }
    static var successBorder: Color {
        Color(nsColor: NSColor(name: nil) { $0.isDark ? NSColor(hex: 0x14532d) : NSColor(hex: 0xbbf7d0) })
    }

    // Warning (Amber)
    static var warningFg: Color {
        Color(nsColor: NSColor(name: nil) { $0.isDark ? NSColor(hex: 0xfbbf24) : NSColor(hex: 0xb45309) })
    }
    static var warningBg: Color {
        Color(nsColor: NSColor(name: nil) { $0.isDark ? NSColor(red: 69/255, green: 26/255, blue: 3/255, alpha: 0.3) : NSColor(hex: 0xfffbeb) })
    }
    static var warningBorder: Color {
        Color(nsColor: NSColor(name: nil) { $0.isDark ? NSColor(hex: 0x78350f) : NSColor(hex: 0xfde68a) })
    }

    // Danger (Red)
    static var dangerFg: Color {
        Color(nsColor: NSColor(name: nil) { $0.isDark ? NSColor(hex: 0xf87171) : NSColor(hex: 0xb91c1c) })
    }
    static var dangerBg: Color {
        Color(nsColor: NSColor(name: nil) { $0.isDark ? NSColor(red: 69/255, green: 10/255, blue: 10/255, alpha: 0.3) : NSColor(hex: 0xfef2f2) })
    }
    static var dangerBorder: Color {
        Color(nsColor: NSColor(name: nil) { $0.isDark ? NSColor(hex: 0x7f1d1d) : NSColor(hex: 0xfecaca) })
    }
    static let dangerSolid = Color(hex: 0xdc2626)

    // Info (Blue)
    static var infoFg: Color {
        Color(nsColor: NSColor(name: nil) { $0.isDark ? NSColor(hex: 0x60a5fa) : NSColor(hex: 0x1d4ed8) })
    }
    static var infoBg: Color {
        Color(nsColor: NSColor(name: nil) { $0.isDark ? NSColor(red: 23/255, green: 37/255, blue: 84/255, alpha: 0.3) : NSColor(hex: 0xeff6ff) })
    }
    static var infoBorder: Color {
        Color(nsColor: NSColor(name: nil) { $0.isDark ? NSColor(hex: 0x1e3a8a) : NSColor(hex: 0xbfdbfe) })
    }

    // MARK: - Radii

    static let radiusSm: CGFloat = 4
    static let radiusMd: CGFloat = 6
    static let radiusLg: CGFloat = 8
    static let radiusXl: CGFloat = 12
    static let radiusFull: CGFloat = 9999


    static let displayFontSize: CGFloat = 24
    static let baseFontSize: CGFloat = 13
    static let sectionLabelSize: CGFloat = 11
    static var statValueFont: Font { .system(size: 20, weight: .semibold, design: .monospaced) }

    // Typography tokens
    static let trackingTighter: CGFloat = -0.6
    static let trackingTight: CGFloat = -0.3
    static let trackingNormal: CGFloat = 0
    static let trackingLoose: CGFloat = 0.8

    static func fontDisplay(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }

    static func fontMono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static let spaceXs: CGFloat = 4
    static let spaceSm: CGFloat = 8
    static let spaceMd: CGFloat = 12
    static let spaceLg: CGFloat = 16
    static let spaceXl: CGFloat = 24

    // MARK: - Motion

    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static var easeOut: Animation {
        reduceMotion ? .linear(duration: 0.01) : .easeOut(duration: 0.15)
    }

    static var pulse: Animation {
        reduceMotion ? .linear(duration: 0.01) : .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
    }
}

// MARK: - Helpers

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: alpha)
    }

    var isDark: Bool {
        guard let rgb = usingColorSpace(.deviceRGB) else { return true }
        let luminance = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        return luminance < 0.5
    }
}

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

// MARK: - Button Styles

/// Inverted monochrome primary button: black on white in dark mode, white on black in light mode.
struct MonochromePrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    var isCompact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let isDark = colorScheme == .dark
        let bg = isDark ? Color.white : Color.black
        let fg = isDark ? Color.black : Color.white
        let pressedOpacity = configuration.isPressed ? 0.8 : 1.0

        configuration.label
            .font(.system(size: isCompact ? 12 : 13, weight: .medium))
            .tracking(-0.02)
            .foregroundStyle(fg)
            .padding(.horizontal, isCompact ? 12 : 16)
            .frame(height: isCompact ? 28 : 34)
            .background(bg.opacity(pressedOpacity), in: RoundedRectangle(cornerRadius: DesignTokens.radiusMd))
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// 1px crisp outline button.
struct MonochromeOutlineButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    var isCompact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: isCompact ? 12 : 13, weight: .medium))
            .tracking(-0.02)
            .foregroundStyle(DesignTokens.textPrimary)
            .padding(.horizontal, isCompact ? 12 : 16)
            .frame(height: isCompact ? 28 : 34)
            .background(
                configuration.isPressed ? DesignTokens.surfaceSubtle : DesignTokens.surface,
                in: RoundedRectangle(cornerRadius: DesignTokens.radiusMd)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.radiusMd)
                    .stroke(DesignTokens.borderPrimary, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Ghost button (no border, hover fill).
struct MonochromeGhostButtonStyle: ButtonStyle {
    var isCompact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: isCompact ? 12 : 13, weight: .medium))
            .tracking(-0.02)
            .foregroundStyle(DesignTokens.textSecondary)
            .padding(.horizontal, isCompact ? 8 : 12)
            .frame(height: isCompact ? 28 : 34)
            .background(
                configuration.isPressed ? DesignTokens.surfaceSecondary : Color.clear,
                in: RoundedRectangle(cornerRadius: DesignTokens.radiusMd)
            )
    }
}

// MARK: - View Modifiers

struct MonochromeCardModifier: ViewModifier {
    var radius: CGFloat = DesignTokens.radiusLg
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(DesignTokens.surface, in: RoundedRectangle(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(DesignTokens.borderPrimary, lineWidth: 1)
            )
    }
}

struct MonochromeSubCardModifier: ViewModifier {
    var radius: CGFloat = DesignTokens.radiusMd
    var padding: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(DesignTokens.surfaceSubtle, in: RoundedRectangle(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(DesignTokens.borderSubtle, lineWidth: 1)
            )
    }
}

extension View {
    func monochromeCard(radius: CGFloat = DesignTokens.radiusLg, padding: CGFloat = 16) -> some View {
        modifier(MonochromeCardModifier(radius: radius, padding: padding))
    }

    func monochromeSubCard(radius: CGFloat = DesignTokens.radiusMd, padding: CGFloat = 12) -> some View {
        modifier(MonochromeSubCardModifier(radius: radius, padding: padding))
    }

    func monochromeCanvas() -> some View {
        background(DesignTokens.canvas)
    }

    // Legacy helpers
    func adminCanvasBackground() -> some View {
        background(DesignTokens.canvas)
    }

    func adminCard() -> some View {
        monochromeCard()
    }

    func adminElevatedCard() -> some View {
        monochromeCard()
    }

    func nativeGroupedForm() -> some View {
        formStyle(.grouped)
    }
}
