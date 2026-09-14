import KeyboardShortcuts
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.openSettings) private var openSettingsPanel
    @State private var hoveredRow: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(DesignTokens.borderSubtle.opacity(0.5))

            VStack(alignment: .leading, spacing: 4) {
                if appState.permissionsNeedAttention {
                    permissionAlertRow
                    Divider().overlay(DesignTokens.borderSubtle).padding(.vertical, 2)
                }
                if let error = appState.lastError?.localizedDescription, !error.isEmpty {
                    errorBanner(error)
                }

                MenuActionRow(
                    id: "dashboard",
                    title: "Open Studio Dashboard",
                    detail: "Voz engine, speech settings, test",
                    systemImage: "macwindow",
                    isHovered: hoveredRow == "dashboard"
                ) {
                    appState.openDashboard()
                }
                .onHover { hoveredRow = $0 ? "dashboard" : nil }

                MenuActionRow(
                    id: "quit",
                    title: "Quit SayItFlow",
                    detail: "Quit the app completely",
                    systemImage: "power",
                    isDestructive: true,
                    isHovered: hoveredRow == "quit"
                ) {
                    NSApplication.shared.terminate(nil)
                }
                .onHover { hoveredRow = $0 ? "quit" : nil }
                .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)

            Divider().overlay(DesignTokens.borderSubtle.opacity(0.5))
            footer
        }
        .frame(width: 300)
        .background(.ultraThinMaterial)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            LogoMark(size: .sm)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("SayItFlow")
                    .font(DesignTokens.fontDisplay(size: 13, weight: .semibold))
                    .tracking(DesignTokens.trackingTight)
                    .foregroundStyle(DesignTokens.textPrimary)

                HStack(spacing: 5) {
                    StatusOrb(phase: appState.phase)
                    Text(appState.statusLabel.uppercased())
                        .font(DesignTokens.fontMono(size: 9, weight: .medium))
                        .tracking(DesignTokens.trackingLoose)
                        .foregroundStyle(statusCaptionColor)
                }
            }

            Spacer()

            if settings.hotkeyMode != .custom
                || KeyboardShortcuts.getShortcut(for: .pushToTalk) != nil {
                HotkeyKeyCap(label: settings.hotkeyMode.label)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("SayItFlow, \(appState.statusLabel)")
    }

    private var statusCaptionColor: Color {
        switch appState.phase {
        case .recording: DesignTokens.successFg
        case .error: DesignTokens.dangerFg
        default: DesignTokens.textMuted
        }
    }

    // MARK: - Alerts

    private var permissionAlertRow: some View {
        Button {
            appState.openDashboard()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(DesignTokens.warningFg)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Permissions needed")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DesignTokens.textPrimary)
                    Text("Dictation won't start until fixed")
                        .font(DesignTokens.fontMono(size: 10))
                        .foregroundStyle(DesignTokens.textMuted)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignTokens.textMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(DesignTokens.warningBg, in: RoundedRectangle(cornerRadius: DesignTokens.radiusMd))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.radiusMd)
                    .stroke(DesignTokens.warningBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Fix permissions")
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 11))
            .foregroundStyle(DesignTokens.dangerFg)
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(DesignTokens.dangerBg, in: RoundedRectangle(cornerRadius: DesignTokens.radiusSm))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.radiusSm)
                    .stroke(DesignTokens.dangerBorder, lineWidth: 1)
            )
            .padding(.bottom, 4)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Text(footerText)
                .font(DesignTokens.fontMono(size: 10))
                .foregroundStyle(DesignTokens.textMuted)

            Spacer()

            Text("100% On-Device · ⌘Q")
                .font(DesignTokens.fontMono(size: 10))
                .foregroundStyle(DesignTokens.textMuted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
    }

    private var footerText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        return "v\(version) · \(appState.wordCount)w"
    }
}

// MARK: - Status orb

private struct StatusOrb: View {
    let phase: DictationPhase
    @State private var pulsing = false

    private var color: Color {
        switch phase {
        case .recording: DesignTokens.successFg
        case .transcribing, .polishing, .injecting: DesignTokens.selection
        case .error: DesignTokens.dangerFg
        default: DesignTokens.textMuted
        }
    }

    private var isActive: Bool {
        switch phase {
        case .recording, .transcribing, .polishing, .injecting: true
        default: false
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: 14, height: 14)
                .scaleEffect(pulsing ? 1.4 : 0.8)
                .opacity(pulsing ? 0 : 1)
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
        }
        .onAppear { updatePulse() }
        .onChange(of: phase) { _, _ in updatePulse() }
    }

    private func updatePulse() {
        guard isActive, !DesignTokens.reduceMotion else {
            pulsing = false
            return
        }
        withAnimation(DesignTokens.pulse) { pulsing = true }
    }
}

// MARK: - Action row

private struct MenuActionRow: View {
    let id: String
    let title: String
    let detail: String?
    let systemImage: String
    var isDestructive: Bool = false
    let isHovered: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: DesignTokens.radiusSm)
                        .fill(isHovered ? (isDestructive ? DesignTokens.dangerBg : DesignTokens.surface) : DesignTokens.surfaceSubtle)
                    RoundedRectangle(cornerRadius: DesignTokens.radiusSm)
                        .stroke(isHovered ? (isDestructive ? DesignTokens.dangerBorder : DesignTokens.borderPrimary) : DesignTokens.borderSubtle, lineWidth: 1)
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isHovered && isDestructive ? DesignTokens.dangerFg : (isHovered ? DesignTokens.textPrimary : DesignTokens.textSecondary))
                }
                .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .tracking(DesignTokens.trackingTight)
                        .foregroundStyle(isHovered && isDestructive ? DesignTokens.dangerFg : DesignTokens.textPrimary)
                    if let detail {
                        Text(detail)
                            .font(DesignTokens.fontMono(size: 10))
                            .foregroundStyle(DesignTokens.textMuted)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                isHovered ? (isDestructive ? DesignTokens.dangerBg : DesignTokens.surfaceSubtle) : Color.clear,
                in: RoundedRectangle(cornerRadius: DesignTokens.radiusMd)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.radiusMd)
                    .stroke(isHovered ? (isDestructive ? DesignTokens.dangerBorder : DesignTokens.borderSubtle) : Color.clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: DesignTokens.radiusMd))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
