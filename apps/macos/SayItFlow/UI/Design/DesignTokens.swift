import AppKit
import SwiftUI
#if canImport(AudioTapCore)
@_exported import AudioTapCore
#endif

/// Monitor YT (`monitoryt.com`) Lo-Fi Paper & Ink Neo-Brutalist Design System
/// Matches Android `DashboardScreen.kt` 1:1 via the `lofi-paper-ink-ui` skill.
public enum DesignTokens {
    // MARK: - Canonical Monitor YT Paper & Ink Palette

    public static let paperBg       = Color(hex: 0xFBF3E4) // Warm cream paper canvas (#FBF3E4)
    public static let paperDeep     = Color(hex: 0xF3E4C6) // Deeper warm sand/tan (#F3E4C6)
    public static let cardWhite     = Color(hex: 0xFFFFFF) // Crisp white card surface (#FFFFFF)
    public static let cardButter    = Color(hex: 0xFFF7E0) // Warm butter sticky-note (#FFF7E0)
    public static let cardMint      = Color(hex: 0xE6FBF6) // Soft mint card surface (#E6FBF6)
    public static let cardPeach     = Color(hex: 0xFFF0EC) // Soft peach card surface (#FFF0EC)

    public static let ink           = Color(hex: 0x1B1712) // Deep warm charcoal ink (#1B1712)
    public static let inkSoft       = Color(hex: 0x5A5044) // Secondary warm brown-grey (#5A5044)
    public static let inkMuted      = Color(hex: 0x8A7E6E) // Muted warm stone (#8A7E6E)

    public static let accentRed     = Color(hex: 0xFF3B2F) // Punchy signal red (#FF3B2F)
    public static let accentYellow  = Color(hex: 0xFFCE4A) // Warm gold highlight (#FFCE4A)
    public static let accentTeal    = Color(hex: 0x36C2AD) // Mint-teal ready status (#36C2AD)
    public static let accentSky     = Color(hex: 0x74A7FF) // Periwinkle blue badge (#74A7FF)
    public static let accentCoral   = Color(hex: 0xFF9E86) // Warm coral chip (#FF9E86)
    public static let accentLilac   = Color(hex: 0xC8A8FF) // Soft lilac tag (#C8A8FF)

    // MARK: - Backward-Compatible Semantic Aliases

    public static var warmCanvas: Color { paperBg }
    public static var warmSurface: Color { cardWhite }
    public static var warmBorder: Color { ink }
    public static var warmInkPrimary: Color { ink }
    public static var warmInkSecondary: Color { inkSoft }
    public static var warmInkMuted: Color { inkMuted }
    public static var warmReady: Color { accentTeal }
    public static var warmRecording: Color { accentRed }

    /// Root page/window canvas: Warm cream paper #FBF3E4.
    public static var canvas: Color { paperBg }

    /// Primary card surface: Crisp white #FFFFFF.
    public static var surface: Color { cardWhite }

    /// Secondary surface (sidebar, segmented rail, keycaps): #F3E4C6.
    public static var surfaceSecondary: Color { paperDeep }

    /// Subtle fill (nested input boxes, unselected pills): #FBF3E4.
    public static var surfaceSubtle: Color { paperBg }

    /// Thick neo-brutalist ink border #1B1712.
    public static var border: Color { ink }
    public static var borderPrimary: Color { ink }
    public static var borderSubtle: Color { ink.opacity(0.2) }
    public static var borderHover: Color { ink }

    // MARK: - Typography Hierarchy

    public static var inkPrimary: Color { ink }
    public static var textPrimary: Color { ink }
    public static var inkSecondary: Color { inkSoft }
    public static var textSecondary: Color { inkSoft }
    public static var textMuted: Color { inkMuted }

    public static var ready: Color { accentTeal }
    public static var recording: Color { accentRed }
    public static var selection: Color { accentYellow }
    public static var selectionForeground: Color { ink }

    // MARK: - Semantic Neo-Brutalist Tints

    // Success / Ready (Mint Teal)
    public static var successFg: Color { ink }
    public static var successBg: Color { accentTeal }
    public static var successBorder: Color { ink }

    // Warning (Warm Gold Yellow)
    public static var warningFg: Color { ink }
    public static var warningBg: Color { accentYellow }
    public static var warningBorder: Color { ink }

    // Danger (Signal Red / Coral)
    public static var dangerFg: Color { ink }
    public static var dangerBg: Color { accentCoral }
    public static var dangerBorder: Color { ink }
    public static let dangerSolid = Color(hex: 0xFF3B2F)

    // Info (Sky / Yellow)
    public static var infoFg: Color { ink }
    public static var infoBg: Color { accentSky }
    public static var infoBorder: Color { ink }

    // MARK: - Radii & Borders

    public static let radiusSm: CGFloat = 6
    public static let radiusMd: CGFloat = 10
    public static let radiusLg: CGFloat = 14
    public static let radiusXl: CGFloat = 16
    public static let radiusFull: CGFloat = 999

    public static let borderWidth: CGFloat = 2.0
    public static let shadowOffset: CGFloat = 4.0
    public static var shadowColor: Color { ink }

    public static let displayFontSize: CGFloat = 22
    public static let baseFontSize: CGFloat = 13
    public static let sectionLabelSize: CGFloat = 11
    public static var statValueFont: Font { .system(size: 20, weight: .heavy, design: .monospaced) }

    public static let trackingTighter: CGFloat = -0.6
    public static let trackingTight: CGFloat = -0.4
    public static let trackingNormal: CGFloat = 0
    public static let trackingLoose: CGFloat = 0.6

    public static func fontDisplay(size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight)
    }

    public static func fontMono(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    public static let spaceXs: CGFloat = 4
    public static let spaceSm: CGFloat = 8
    public static let spaceMd: CGFloat = 12
    public static let spaceLg: CGFloat = 16
    public static let spaceXl: CGFloat = 24

    // MARK: - Motion

    public static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    public static var easeOut: Animation {
        reduceMotion ? .linear(duration: 0.01) : .easeOut(duration: 0.14)
    }

    public static var pulse: Animation {
        reduceMotion ? .linear(duration: 0.01) : .easeInOut(duration: 0.85).repeatForever(autoreverses: true)
    }
}

// MARK: - Color & NSColor Helpers

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

// MARK: - Neo-Brutalist Paper Dot-Grid Canvas

public struct PaperDotGridBackground: View {
    public init() {}

    public var body: some View {
        ZStack {
            DesignTokens.paperBg
            Canvas { context, size in
                let step: CGFloat = 22.0
                let radius: CGFloat = 1.15
                let dotColor = DesignTokens.ink.opacity(0.09)
                var y: CGFloat = 11.0
                while y < size.height {
                    var x: CGFloat = 11.0
                    while x < size.width {
                        let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                        context.fill(Path(ellipseIn: rect), with: .color(dotColor))
                        x += step
                    }
                    y += step
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Neo-Brutalist Button Styles

/// Primary Neo-Brutalist Pill Button: Signal Red (#FF3B2F) or Gold Yellow (#FFCE4A) with 2pt Ink border + hard offset shadow.
struct MonochromePrimaryButtonStyle: ButtonStyle {
    var isCompact: Bool = false
    var fill: Color = DesignTokens.accentRed
    var foreground: Color = DesignTokens.cardWhite

    func makeBody(configuration: Configuration) -> some View {
        let offset: CGFloat = configuration.isPressed ? 1.0 : (isCompact ? 2.5 : 3.0)
        let pressShift: CGFloat = configuration.isPressed ? 1.5 : 0.0

        configuration.label
            .font(.system(size: isCompact ? 11.5 : 13, weight: .heavy))
            .foregroundStyle(foreground)
            .padding(.horizontal, isCompact ? 12 : 16)
            .frame(height: isCompact ? 28 : 34)
            .background(
                ZStack {
                    Capsule()
                        .fill(DesignTokens.ink)
                        .offset(x: offset, y: offset)
                    Capsule()
                        .fill(fill)
                    Capsule()
                        .strokeBorder(DesignTokens.ink, lineWidth: 2)
                }
            )
            .offset(x: pressShift, y: pressShift)
            .padding(.trailing, 3)
            .padding(.bottom, 3)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

/// Secondary Neo-Brutalist Outline Pill Button: Warm Yellow or White fill with 2pt Ink border + hard offset shadow.
struct MonochromeOutlineButtonStyle: ButtonStyle {
    var isCompact: Bool = false
    var fill: Color = DesignTokens.accentYellow

    func makeBody(configuration: Configuration) -> some View {
        let offset: CGFloat = configuration.isPressed ? 1.0 : 2.5
        let pressShift: CGFloat = configuration.isPressed ? 1.5 : 0.0

        configuration.label
            .font(.system(size: isCompact ? 11.5 : 12.5, weight: .heavy))
            .foregroundStyle(DesignTokens.ink)
            .padding(.horizontal, isCompact ? 12 : 14)
            .frame(height: isCompact ? 28 : 32)
            .background(
                ZStack {
                    Capsule()
                        .fill(DesignTokens.ink)
                        .offset(x: offset, y: offset)
                    Capsule()
                        .fill(configuration.isPressed ? DesignTokens.paperDeep : fill)
                    Capsule()
                        .strokeBorder(DesignTokens.ink, lineWidth: 2)
                }
            )
            .offset(x: pressShift, y: pressShift)
            .padding(.trailing, 3)
            .padding(.bottom, 3)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

/// Ghost button with crisp ink border on hover/press.
struct MonochromeGhostButtonStyle: ButtonStyle {
    var isCompact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: isCompact ? 11.5 : 12.5, weight: .bold))
            .foregroundStyle(DesignTokens.inkSoft)
            .padding(.horizontal, isCompact ? 8 : 12)
            .frame(height: isCompact ? 26 : 30)
            .background(
                configuration.isPressed ? DesignTokens.paperDeep : Color.clear,
                in: RoundedRectangle(cornerRadius: DesignTokens.radiusSm)
            )
    }
}

// MARK: - Neo-Brutalist Card & Pill View Modifiers

struct LofiCardModifier: ViewModifier {
    var fill: Color = DesignTokens.cardWhite
    var radius: CGFloat = DesignTokens.radiusXl
    var borderWidth: CGFloat = 2.0
    var shadowOffset: CGFloat = 4.0
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: radius)
                        .fill(DesignTokens.ink)
                        .offset(x: shadowOffset, y: shadowOffset)
                    RoundedRectangle(cornerRadius: radius)
                        .fill(fill)
                    RoundedRectangle(cornerRadius: radius)
                        .strokeBorder(DesignTokens.ink, lineWidth: borderWidth)
                }
            )
            .padding(.trailing, shadowOffset)
            .padding(.bottom, shadowOffset)
    }
}

struct MonochromeSubCardModifier: ViewModifier {
    var radius: CGFloat = DesignTokens.radiusMd
    var padding: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(DesignTokens.paperBg, in: RoundedRectangle(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(DesignTokens.ink, lineWidth: 1.5)
            )
    }
}

extension View {
    func lofiCard(
        fill: Color = DesignTokens.cardWhite,
        radius: CGFloat = DesignTokens.radiusXl,
        borderWidth: CGFloat = 2.0,
        shadowOffset: CGFloat = 4.0,
        padding: CGFloat = 16
    ) -> some View {
        modifier(LofiCardModifier(
            fill: fill,
            radius: radius,
            borderWidth: borderWidth,
            shadowOffset: shadowOffset,
            padding: padding
        ))
    }

    func monochromeCard(
        radius: CGFloat = DesignTokens.radiusXl,
        padding: CGFloat = 16,
        fill: Color = DesignTokens.cardWhite
    ) -> some View {
        modifier(LofiCardModifier(
            fill: fill,
            radius: radius,
            borderWidth: 2.0,
            shadowOffset: 4.0,
            padding: padding
        ))
    }

    func monochromeSubCard(radius: CGFloat = DesignTokens.radiusMd, padding: CGFloat = 12) -> some View {
        modifier(MonochromeSubCardModifier(radius: radius, padding: padding))
    }

    func monochromeCanvas() -> some View {
        background(PaperDotGridBackground())
    }

    func adminCanvasBackground() -> some View {
        background(PaperDotGridBackground())
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

#if !SWIFT_PACKAGE
import Foundation
import Combine

/// Represents an individual voice dictation event stored in history.
public struct DictationRecord: Identifiable, Codable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let text: String
    public let wordCount: Int
    public let charCount: Int
    public let appName: String
    public let durationSeconds: Double

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        text: String,
        wordCount: Int? = nil,
        charCount: Int? = nil,
        appName: String = "",
        durationSeconds: Double = 0.0
    ) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.wordCount = wordCount ?? text.split { $0.isWhitespace || $0.isNewline }.count
        self.charCount = charCount ?? text.count
        self.appName = appName
        self.durationSeconds = durationSeconds
    }
}

/// On-device storage for past voice dictation sessions.
@MainActor
public final class DictationHistoryStore: ObservableObject {
    public static let shared = DictationHistoryStore()

    private static let storageKey = "SayItFlow.DictationHistory"
    private static let maxRecords = 500

    @Published public private(set) var records: [DictationRecord] = []

    public init() {
        load()
    }

    @discardableResult
    public func record(text: String, appName: String = "", durationSeconds: Double = 0.0) -> DictationRecord? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let item = DictationRecord(
            text: trimmed,
            appName: appName,
            durationSeconds: durationSeconds
        )

        records.insert(item, at: 0)
        if records.count > Self.maxRecords {
            records = Array(records.prefix(Self.maxRecords))
        }

        save()
        return item
    }

    public func delete(id: UUID) {
        records.removeAll { $0.id == id }
        save()
    }

    public func delete(at offsets: IndexSet) {
        records.remove(atOffsets: offsets)
        save()
    }

    public func clearAll() {
        records.removeAll()
        save()
    }

    public func search(query: String) -> [DictationRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return records }

        return records.filter { record in
            record.text.localizedCaseInsensitiveContains(trimmed) ||
            record.appName.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else {
            return
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            records = try decoder.decode([DictationRecord].self, from: data)
        } catch {
            records = []
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(records)
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        } catch {
            // Ignore persistence write failure
        }
    }
}
#endif
