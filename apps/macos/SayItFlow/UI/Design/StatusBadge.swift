import SwiftUI

enum StatusBadgeKind {
    case granted
    case denied
    case pending
    case info
    case warning
    case neutral

    var label: String {
        switch self {
        case .granted: "Granted"
        case .denied: "Denied"
        case .pending: "Not Set"
        case .info: "Active"
        case .warning: "Warning"
        case .neutral: "Default"
        }
    }

    var foreground: Color {
        switch self {
        case .granted: DesignTokens.successFg
        case .denied: DesignTokens.dangerFg
        case .pending: DesignTokens.infoFg
        case .info: DesignTokens.infoFg
        case .warning: DesignTokens.warningFg
        case .neutral: DesignTokens.textSecondary
        }
    }

    var background: Color {
        switch self {
        case .granted: DesignTokens.successBg
        case .denied: DesignTokens.dangerBg
        case .pending: DesignTokens.infoBg
        case .info: DesignTokens.infoBg
        case .warning: DesignTokens.warningBg
        case .neutral: DesignTokens.surfaceSubtle
        }
    }

    var border: Color {
        switch self {
        case .granted: DesignTokens.successBorder
        case .denied: DesignTokens.dangerBorder
        case .pending: DesignTokens.infoBorder
        case .info: DesignTokens.infoBorder
        case .warning: DesignTokens.warningBorder
        case .neutral: DesignTokens.borderPrimary
        }
    }
}

/// Soft-tint semantic badge with 1px border as defined in Ved Gupta design system
struct StatusBadge: View {
    let kind: StatusBadgeKind
    var text: String?
    var showDot: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            if showDot {
                Circle()
                    .fill(kind.foreground)
                    .frame(width: 5, height: 5)
            }
            Text(text ?? kind.label)
                .font(.system(size: 11, weight: .medium))
                .tracking(-0.01)
                .foregroundStyle(kind.foreground)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(kind.background, in: RoundedRectangle(cornerRadius: DesignTokens.radiusSm))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.radiusSm)
                .stroke(kind.border, lineWidth: 1)
        )
    }
}
