import SwiftUI

/// Neo-Brutalist technical keycap with 1.5pt Ink border and hard offset shadow
struct HotkeyKeyCap: View {
    let label: String
    var isEmphasized: Bool = false

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .heavy, design: .monospaced))
            .foregroundStyle(DesignTokens.ink)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(DesignTokens.ink)
                        .offset(x: 2, y: 2)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isEmphasized ? DesignTokens.accentYellow : DesignTokens.paperDeep)
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(DesignTokens.ink, lineWidth: 1.5)
                }
            )
            .padding(.trailing, 2)
            .padding(.bottom, 2)
    }
}

struct HotkeyInstructionRow: View {
    let mode: HotkeyMode
    let hint: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            HotkeyKeyCap(label: keyLabel, isEmphasized: true)
            Text(hint)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DesignTokens.inkSoft)
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
