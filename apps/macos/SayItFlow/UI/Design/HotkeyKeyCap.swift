import SwiftUI

/// Precision technical keycap as defined in Ved Gupta design system
struct HotkeyKeyCap: View {
    let label: String
    var isEmphasized: Bool = false

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .tracking(0.02)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(isEmphasized ? DesignTokens.textPrimary : DesignTokens.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(DesignTokens.surfaceSecondary, in: RoundedRectangle(cornerRadius: DesignTokens.radiusSm))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.radiusSm)
                    .stroke(DesignTokens.borderPrimary, lineWidth: 1)
            )
    }
}
