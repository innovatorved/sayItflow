import SwiftUI

/// Precision technical keycap as defined in Ved Gupta design system
struct HotkeyKeyCap: View {
    let label: String
    var isEmphasized: Bool = false

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .tracking(0.02)
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

struct HotkeyInstructionRow: View {
    let mode: HotkeyMode
    let hint: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            HotkeyKeyCap(label: keyLabel, isEmphasized: true)
            Text(hint)
                .font(.system(size: 13, weight: .regular))
                .tracking(-0.01)
                .foregroundStyle(DesignTokens.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(keyLabel). \(hint)")
    }

    private var keyLabel: String {
        switch mode {
        case .holdSpace: "Space"
        case .fnKey: "fn"
        case .rightOption: "⌥ Option"
        case .custom: "Custom"
        }
    }
}
