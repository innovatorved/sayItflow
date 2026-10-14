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
        case .granted: "Ready"
        case .denied: "Denied"
        case .pending: "Setup"
        case .info: "Active"
        case .warning: "Warning"
        case .neutral: "Default"
        }
    }

    var fill: Color {
        switch self {
        case .granted: DesignTokens.accentTeal
        case .denied: DesignTokens.accentCoral
        case .pending: DesignTokens.accentYellow
        case .info: DesignTokens.accentYellow
        case .warning: DesignTokens.accentYellow
        case .neutral: DesignTokens.paperDeep
        }
    }
}

/// Monitor YT Neo-Brutalist Status Pill with 2pt Ink border and 2.5pt hard offset shadow
struct StatusBadge: View {
    let kind: StatusBadgeKind
    var text: String?
    var showDot: Bool = true

    var body: some View {
        HStack(spacing: 6) {
            if showDot {
                Circle()
                    .fill(DesignTokens.ink)
                    .frame(width: 7, height: 7)
            }
            Text(text ?? kind.label)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(DesignTokens.ink)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(
            ZStack {
                Capsule()
                    .fill(DesignTokens.ink)
                    .offset(x: 2.5, y: 2.5)
                Capsule()
                    .fill(kind.fill)
                Capsule()
                    .strokeBorder(DesignTokens.ink, lineWidth: 2)
            }
        )
        .padding(.trailing, 2.5)
        .padding(.bottom, 2.5)
    }
}
