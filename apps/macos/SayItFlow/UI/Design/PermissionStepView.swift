import SwiftUI

struct PermissionStepView: View {
    let kind: PermissionKind
    let status: PermissionStatus
    let isRequesting: Bool
    let onPrimaryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                // 1:1 icon box
                ZStack {
                    RoundedRectangle(cornerRadius: DesignTokens.radiusMd)
                        .fill(DesignTokens.surfaceSubtle)
                    RoundedRectangle(cornerRadius: DesignTokens.radiusMd)
                        .stroke(DesignTokens.borderPrimary, lineWidth: 1)
                    Image(systemName: iconName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DesignTokens.textPrimary)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(DesignTokens.fontDisplay(size: 15, weight: .semibold))
                        .tracking(DesignTokens.trackingTight)
                        .foregroundStyle(DesignTokens.textPrimary)
                    Text(kind.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(DesignTokens.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                StatusBadge(kind: status.badgeKind, text: statusLabel)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(actionHint)
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .lineSpacing(2)

                Button(action: onPrimaryAction) {
                    HStack(spacing: 6) {
                        if isRequesting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(primaryButtonTitle)
                    }
                }
                .buttonStyle(MonochromePrimaryButtonStyle())
                .disabled(isRequesting)
            }
        }
        .monochromeCard(radius: DesignTokens.radiusLg, padding: 18)
    }

    private var iconName: String {
        switch kind {
        case .microphone: "mic.fill"
        case .accessibility: "hand.point.up.left.fill"
        case .inputMonitoring: "keyboard"
        }
    }

    private var statusLabel: String {
        if isRequesting { return "Waiting…" }
        return status.label
    }

    private var needsManualGrant: Bool {
        status == .denied || status == .needsSettings
    }

    private var primaryButtonTitle: String {
        if isRequesting { return "Waiting for system dialog…" }
        switch kind {
        case .microphone:
            return needsManualGrant ? "Open Microphone Settings" : "Allow Microphone"
        case .accessibility: return "Open Accessibility Settings"
        case .inputMonitoring: return "Open Input Monitoring Settings"
        }
    }

    private var actionHint: String {
        switch kind {
        case .microphone:
            if needsManualGrant {
                return "Access was denied earlier. Enable the SayItFlow toggle in macOS System Settings, then return here."
            }
            return "Click the button, then choose Allow in the system security dialog."
        case .accessibility:
            return "Enable the SayItFlow toggle under Privacy → Accessibility to allow global hotkey detection and caret text injection."
        case .inputMonitoring:
            return "Enable the SayItFlow toggle under Privacy → Input Monitoring to detect push-to-talk keydown & keyup events."
        }
    }
}
