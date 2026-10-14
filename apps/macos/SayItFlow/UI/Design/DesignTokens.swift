import AppKit
import SwiftUI
#if canImport(AudioTapCore)
@_exported import AudioTapCore
#endif

/// MonitorYT-Inspired Warm Lo-Fi Editorial Design System
public enum DesignTokens {
    // MARK: - MonitorYT Warm Lo-Fi Palette

    public static let warmCanvas       = Color(hex: 0xFAF9F6) // Warm alabaster (#FAF9F6)
    public static let warmSurface      = Color(hex: 0xF3F1EC) // Soft stone (#F3F1EC)
    public static let warmBorder       = Color(hex: 0xE4E1DA) // Crisp 1px sand border (#E4E1DA)
    public static let warmInkPrimary   = Color(hex: 0x141413) // Deep charcoal ink (#141413)
    public static let warmInkSecondary = Color(hex: 0x5A5044) // Warm muted brown (#5A5044)
    public static let warmInkMuted     = Color(hex: 0x8A7E6E) // Subtle stone (#8A7E6E)
    public static let warmReady        = Color(hex: 0x15803D) // Forest green status (#15803D)
    public static let warmRecording    = Color(hex: 0xD97757) // Terracotta recording accent (#D97757)

    // MARK: - Surfaces & Canvas (Canonical MonitorYT Tokens)

    /// Root page/window canvas. Warm alabaster #FAF9F6.
    public static var canvas: Color { warmCanvas }

    /// Primary card/modal surface. Soft stone #F3F1EC.
    public static var surface: Color { warmSurface }

    /// Secondary surface (sub-cards, icon boxes, table headers).
    public static var surfaceSecondary: Color { warmSurface }

    /// Subtle fill (row hovers, text editor background).
    public static var surfaceSubtle: Color { Color(hex: 0xF8F7F4) }

    /// Crisp sand border #E4E1DA.
    public static var border: Color { warmBorder }

    /// Backward-compatibility alias for border.
    public static var borderPrimary: Color { warmBorder }

    /// Backward-compatibility alias for subtle divider border.
    public static var borderSubtle: Color { warmBorder }

    /// Hover border.
    public static var borderHover: Color { Color(hex: 0xD8D4CB) }

    // MARK: - Typography Contrast Hierarchy (Canonical MonitorYT Tokens)

    /// Primary deep charcoal ink #141413.
    public static var inkPrimary: Color { warmInkPrimary }

    /// Backward-compatibility alias for textPrimary.
    public static var textPrimary: Color { warmInkPrimary }

    /// Warm muted brown ink #5A5044.
    public static var inkSecondary: Color { warmInkSecondary }

    /// Backward-compatibility alias for textSecondary.
    public static var textSecondary: Color { warmInkSecondary }

    /// Subtle stone muted ink #8A7E6E.
    public static var inkMuted: Color { warmInkMuted }

    /// Backward-compatibility alias for textMuted.
    public static var textMuted: Color { warmInkMuted }

    /// Forest green active/ready status #15803D.
    public static var ready: Color { warmReady }

    /// Terracotta recording accent #D97757.
    public static var recording: Color { warmRecording }

    /// Signature selection accent.
    public static var selection: Color { warmRecording }
    public static var selectionForeground: Color { warmCanvas }

    // MARK: - Semantic Soft Tints (Badges & State)

    // Success / Ready (Green)
    public static var successFg: Color { warmReady }
    public static var successBg: Color { Color(hex: 0xEEF7F1) }
    public static var successBorder: Color { Color(hex: 0xC6E7D1) }

    // Warning (Amber / Gold)
    public static var warningFg: Color { Color(hex: 0xB45309) }
    public static var warningBg: Color { Color(hex: 0xFDF6E7) }
    public static var warningBorder: Color { Color(hex: 0xF7E2B0) }

    // Danger (Red)
    public static var dangerFg: Color { Color(hex: 0xB91C1C) }
    public static var dangerBg: Color { Color(hex: 0xFDF1F1) }
    public static var dangerBorder: Color { Color(hex: 0xF7CACA) }
    public static let dangerSolid = Color(hex: 0xDC2626)

    // Info (Terracotta Accent)
    public static var infoFg: Color { warmRecording }
    public static var infoBg: Color { Color(hex: 0xFAF0EC) }
    public static var infoBorder: Color { Color(hex: 0xF2D4C9) }

    // MARK: - Radii

    public static let radiusSm: CGFloat = 4
    public static let radiusMd: CGFloat = 6
    public static let radiusLg: CGFloat = 8
    public static let radiusXl: CGFloat = 12
    public static let radiusFull: CGFloat = 9999

    public static let displayFontSize: CGFloat = 24
    public static let baseFontSize: CGFloat = 13
    public static let sectionLabelSize: CGFloat = 11
    public static var statValueFont: Font { .system(size: 20, weight: .semibold, design: .monospaced) }

    // Typography tokens
    public static let trackingTighter: CGFloat = -0.6
    public static let trackingTight: CGFloat = -0.3
    public static let trackingNormal: CGFloat = 0
    public static let trackingLoose: CGFloat = 0.8

    public static func fontDisplay(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }

    public static func fontMono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
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
        reduceMotion ? .linear(duration: 0.01) : .easeOut(duration: 0.15)
    }

    public static var pulse: Animation {
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

/// Warm lo-fi MonitorYT primary button: deep charcoal #141413 on warm alabaster #FAF9F6.
struct MonochromePrimaryButtonStyle: ButtonStyle {
    var isCompact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let bg = DesignTokens.inkPrimary
        let fg = DesignTokens.canvas
        let pressedOpacity = configuration.isPressed ? 0.85 : 1.0

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

/// 1px crisp outline button with warm surface and sand border.
struct MonochromeOutlineButtonStyle: ButtonStyle {
    var isCompact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: isCompact ? 12 : 13, weight: .medium))
            .tracking(-0.02)
            .foregroundStyle(DesignTokens.inkPrimary)
            .padding(.horizontal, isCompact ? 12 : 16)
            .frame(height: isCompact ? 28 : 34)
            .background(
                configuration.isPressed ? DesignTokens.surfaceSubtle : DesignTokens.surface,
                in: RoundedRectangle(cornerRadius: DesignTokens.radiusMd)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.radiusMd)
                    .stroke(DesignTokens.border, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Ghost button (no border, warm hover fill).
struct MonochromeGhostButtonStyle: ButtonStyle {
    var isCompact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: isCompact ? 12 : 13, weight: .medium))
            .tracking(-0.02)
            .foregroundStyle(DesignTokens.inkSecondary)
            .padding(.horizontal, isCompact ? 8 : 12)
            .frame(height: isCompact ? 28 : 34)
            .background(
                configuration.isPressed ? DesignTokens.surface : Color.clear,
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
/// Persists records locally to UserDefaults with JSON encoding.
@MainActor
public final class DictationHistoryStore: ObservableObject {
    public static let shared = DictationHistoryStore()

    private static let storageKey = "SayItFlow.DictationHistory"
    private static let maxRecords = 500

    @Published public private(set) var records: [DictationRecord] = []

    public init() {
        load()
    }

    /// Records a new dictation transcript and saves to persistent storage.
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

    /// Deletes a specific record by its unique ID.
    public func delete(id: UUID) {
        records.removeAll { $0.id == id }
        save()
    }

    /// Deletes records at specified index offsets.
    public func delete(at offsets: IndexSet) {
        records.remove(atOffsets: offsets)
        save()
    }

    /// Clears all recorded dictations.
    public func clearAll() {
        records.removeAll()
        save()
    }

    /// Searches records matching query in transcript or app name.
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

