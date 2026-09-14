import SwiftUI
import KeyboardShortcuts

enum MainWindowSection: String, CaseIterable, Identifiable, Hashable {
    case status
    case dictation
    case text
    case analytics
    case permissions
    case diagnostics
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .status: "Status"
        case .dictation: "Dictation"
        case .text: "Audio & System"
        case .analytics: "Analytics"
        case .permissions: "Permissions"
        case .diagnostics: "Diagnostics & Logs"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .status: "waveform.circle"
        case .dictation: "mic"
        case .text: "gearshape"
        case .analytics: "chart.bar.xaxis"
        case .permissions: "lock.shield"
        case .diagnostics: "stethoscope"
        case .about: "info.circle"
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var engineSettings = EngineSettings.shared
    @ObservedObject private var analytics = DictationAnalytics.shared
    @ObservedObject private var vozEngine = VozEngine.shared
    @ObservedObject private var s1Mini = S1MiniEngine.shared

    @State private var selection: MainWindowSection = .status
    @State private var demoText = ""
    @State private var hint = ""
    @State private var fixingKind: PermissionKind?
    @State private var testInjectionText: String = "Hello from SayItFlow!"
    @State private var testInjectionResult: String = ""
    @State private var testInjectionCountdown: Int = 0
    @State private var isTestingInjection: Bool = false
    @State private var copiedReport: Bool = false
    @State private var recentLogsList: [String] = []

    var initialSection: MainWindowSection?

    init(initialSection: MainWindowSection? = nil) {
        self.initialSection = initialSection
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach(MainWindowSection.allCases) { section in
                        Label(section.title, systemImage: section.symbol)
                            .tag(section)
                    }
                } header: {
                    Text("MENU")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(DesignTokens.textMuted)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerView
                    detailContent
                }
                .padding(24)
            }
            .frame(minWidth: 560, minHeight: 520)
            .monochromeCanvas()
        }
        .frame(minWidth: 860, minHeight: 620)
        .onAppear {
            if let initialSection {
                selection = initialSection
            }
            if selection == .status {
                configureTestInjection()
            }
            refreshLogs()
            vozEngine.refreshStatus()
            s1Mini.refreshStatus()
        }
        .onChange(of: selection) { _, section in
            if section == .status {
                configureTestInjection()
            } else {
                appState.clearOnboardingHandlers()
            }
            if section == .diagnostics {
                refreshLogs()
            }
        }
        .onDisappear { appState.clearOnboardingHandlers() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appState.refreshPermissionStatuses()
            refreshLogs()
            vozEngine.refreshStatus()
        }
    }

    private var headerView: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(selection.title)
                    .font(.system(size: 24, weight: .semibold))
                    .tracking(-0.04)
                    .foregroundStyle(DesignTokens.textPrimary)

                Text(subtitleForSection(selection))
                    .font(.system(size: 13))
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            Spacer()

            if selection == .status {
                StatusBadge(
                    kind: appState.statusLabel == "Ready" ? .granted : (appState.statusLabel == "Listening…" ? .info : .warning),
                    text: appState.statusLabel,
                    showDot: true
                )
            }
        }
        .padding(.bottom, 8)
    }

    private func subtitleForSection(_ section: MainWindowSection) -> String {
        switch section {
        case .status: "System health, speech recognition engine, and quick test."
        case .dictation: "Hotkey trigger and language settings for Voz speech recognition."
        case .text: "Output formatting, auto-capitalization, and text polish."
        case .analytics: "On-device transcription statistics and historical logs."
        case .permissions: "System accessibility and audio input access control."
        case .diagnostics: "Diagnostics report, event trace logs, and injection testing."
        case .about: "SayItFlow version information and open-source models."
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
        case .status:
            statusDetail
        case .dictation:
            dictationSettings
        case .text:
            textSettings
        case .analytics:
            analyticsDetail
        case .permissions:
            permissionsDetail
        case .diagnostics:
            diagnosticsDetail
        case .about:
            aboutDetail
        }
    }

    // MARK: - Status Detail

    private var statusDetail: some View {
        VStack(spacing: 12) {
            // Models Card (Compact)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("ON-DEVICE AI MODELS")
                        .font(DesignTokens.fontMono(size: 10, weight: .medium))
                        .tracking(DesignTokens.trackingLoose)
                        .foregroundStyle(DesignTokens.textMuted)
                    Spacer()
                    Text("100% Private · Apple Silicon")
                        .font(DesignTokens.fontMono(size: 9))
                        .foregroundStyle(DesignTokens.textMuted)
                }

                // Row 1: Voz STT
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(engineSettings.sttModelName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DesignTokens.textPrimary)
                                .lineLimit(1)
                            Text("STT")
                                .font(DesignTokens.fontMono(size: 9, weight: .medium))
                                .foregroundStyle(DesignTokens.textMuted)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(DesignTokens.borderSubtle.opacity(0.5), in: RoundedRectangle(cornerRadius: 3))
                        }
                        Text("Parakeet 0.6B · 467 MB · Neural Engine · 25 Langs")
                            .font(.system(size: 10))
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                    Spacer()
                    if vozEngine.isDownloading {
                        ProgressView(value: max(vozEngine.downloadProgress, 0.05))
                            .frame(width: 80)
                    } else if vozEngine.isDownloaded {
                        StatusBadge(kind: .granted, text: "Ready")
                    } else {
                        Button("Download (467 MB)") {
                            Task { try? await vozEngine.downloadModel() }
                        }
                        .buttonStyle(MonochromePrimaryButtonStyle(isCompact: true))
                    }
                }

                Divider().overlay(DesignTokens.borderSubtle)

                // Row 2: S1-mini Normalizer
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("S1-mini")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DesignTokens.textPrimary)
                                .lineLimit(1)
                            Text("Normalizer")
                                .font(DesignTokens.fontMono(size: 9, weight: .medium))
                                .foregroundStyle(DesignTokens.textMuted)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(DesignTokens.borderSubtle.opacity(0.5), in: RoundedRectangle(cornerRadius: 3))
                        }
                        Text("Superwhisper · Qwen3 0.6B · 462 MB · Metal GPU")
                            .font(.system(size: 10))
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                    Spacer()
                    if s1Mini.isDownloading {
                        ProgressView(value: max(s1Mini.downloadProgress, 0.05))
                            .frame(width: 80)
                    } else if s1Mini.isDownloaded {
                        StatusBadge(kind: .granted, text: "Ready")
                    } else {
                        Button("Download (462 MB)") {
                            Task { try? await s1Mini.downloadModel() }
                        }
                        .buttonStyle(MonochromePrimaryButtonStyle(isCompact: true))
                    }
                }

                Divider().overlay(DesignTokens.borderSubtle)

                Text("Desert Ant Voz (DAL Source-Available 1.0) · S1-mini by Superwhisper (Apache 2.0). All processing is 100% on-device.")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.textMuted)
            }
            .monochromeCard(radius: DesignTokens.radiusMd, padding: 12)

            // Try Dictation Card
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Interactive Dictation Test")
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(-0.02)
                        .foregroundStyle(DesignTokens.textPrimary)
                    Spacer()
                    HotkeyKeyCap(label: settings.hotkeyMode.label, isEmphasized: true)
                }

                Text("Hold \(settings.hotkeyMode.label), speak naturally, and release to transcribe instantly.")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.textSecondary)

                TextEditor(text: $demoText)
                    .font(.system(size: 13))
                    .frame(minHeight: 80)
                    .padding(8)
                    .background(DesignTokens.surfaceSubtle, in: RoundedRectangle(cornerRadius: DesignTokens.radiusMd))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.radiusMd)
                            .stroke(DesignTokens.borderSubtle, lineWidth: 1)
                    )

                if !demoText.isEmpty {
                    HStack {
                        Spacer()
                        Button("Clear Text") { demoText = "" }
                            .buttonStyle(MonochromeOutlineButtonStyle(isCompact: true))
                    }
                }
            }
            .monochromeCard(radius: DesignTokens.radiusMd, padding: 12)
        }
    }

    // MARK: - Dictation Settings

    private var dictationSettings: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Trigger Shortcut")
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(-0.02)
                    .foregroundStyle(DesignTokens.textPrimary)

                Picker("Hotkey Trigger", selection: $settings.hotkeyMode) {
                    ForEach(HotkeyMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                if settings.hotkeyMode == .custom {
                    HStack {
                        Text("Custom Shortcut:")
                            .font(.system(size: 12))
                            .foregroundStyle(DesignTokens.textSecondary)
                        KeyboardShortcuts.Recorder("", name: .pushToTalk)
                    }
                    .padding(.top, 4)
                }

                Text("Hold for >0.25s to start dictating; quick tap types a normal character.")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.textMuted)
            }
            .monochromeCard()

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Spoken Language")
                            .font(.system(size: 14, weight: .semibold))
                            .tracking(-0.02)
                            .foregroundStyle(DesignTokens.textPrimary)
                        Text("Only the 25 languages supported by Voz are available. Default is English.")
                            .font(.system(size: 11))
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                    Spacer()
                    Picker("", selection: $engineSettings.selectedLanguage) {
                        ForEach(VozEngine.supportedLanguageOptions) { lang in
                            Text(lang.name).tag(lang.code)
                        }
                    }
                    .frame(width: 180)
                }

                Divider().overlay(DesignTokens.borderSubtle)

                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignTokens.textMuted)
                    Text("Voz does not auto-detect spoken language. Specifying your language ensures accurate on-device transcription (7.40% WER) with zero CPU/GPU overhead.")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .monochromeCard()
        }
    }

    // MARK: - Text Settings

    private var textSettings: some View {
        VStack(spacing: 16) {
            // S1-mini Post-Processing Card
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("S1-mini Normalization")
                                .font(.system(size: 14, weight: .semibold))
                                .tracking(-0.02)
                                .foregroundStyle(DesignTokens.textPrimary)
                            Text("by Superwhisper")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(DesignTokens.textMuted)
                        }
                        Text("On-device causal LM that cleans fillers (um, uh, like), corrects punctuation, numbers, and formats text.")
                            .font(.system(size: 11))
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                    Spacer()
                    Toggle("", isOn: $s1Mini.isEnabled)
                        .toggleStyle(.switch)
                }

                if s1Mini.isEnabled {
                    Divider().overlay(DesignTokens.borderSubtle)

                    // Control Axes: Styling, Structure, Context
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Styling")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(DesignTokens.textSecondary)
                                .frame(width: 80, alignment: .leading)
                            Picker("", selection: $s1Mini.styling) {
                                ForEach(S1Styling.allCases) { style in
                                    Text(style.displayName).tag(style)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        HStack {
                            Text("Structure")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(DesignTokens.textSecondary)
                                .frame(width: 80, alignment: .leading)
                            Picker("", selection: $s1Mini.structure) {
                                ForEach(S1Structure.allCases) { structure in
                                    Text(structure.displayName).tag(structure)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        HStack {
                            Text("Context")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(DesignTokens.textSecondary)
                                .frame(width: 80, alignment: .leading)
                            Picker("", selection: $s1Mini.context) {
                                ForEach(S1Context.allCases) { ctx in
                                    Text(ctx.displayName).tag(ctx)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    Divider().overlay(DesignTokens.borderSubtle)

                    // Model Download / Status
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text("Model Weights (462 MB)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(DesignTokens.textPrimary)
                                if s1Mini.isDownloaded {
                                    Text("Ready")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(DesignTokens.surfaceSubtle, in: Capsule())
                                        .foregroundStyle(DesignTokens.textPrimary)
                                } else if s1Mini.isDownloading {
                                    Text("Downloading \(Int(s1Mini.downloadProgress * 100))%")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(DesignTokens.surfaceSubtle, in: Capsule())
                                        .foregroundStyle(DesignTokens.textSecondary)
                                } else {
                                    Text("Optional")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(DesignTokens.surfaceSubtle, in: Capsule())
                                        .foregroundStyle(DesignTokens.textMuted)
                                }
                            }
                            Text(s1Mini.isDownloaded ? "Running on-device with zero cloud calls." : "When not downloaded, high-speed built-in rules normalize your text.")
                                .font(.system(size: 11))
                                .foregroundStyle(DesignTokens.textMuted)
                        }
                        Spacer()

                        if s1Mini.isDownloading {
                            ProgressView(value: s1Mini.downloadProgress)
                                .frame(width: 100)
                        } else if !s1Mini.isDownloaded {
                            Button("Download S1-mini") {
                                Task {
                                    try? await s1Mini.downloadModel()
                                }
                            }
                            .buttonStyle(MonochromeOutlineButtonStyle(isCompact: true))
                        } else {
                            Button("Delete") {
                                try? s1Mini.deleteModel()
                            }
                            .buttonStyle(MonochromeGhostButtonStyle())
                        }
                    }

                    if let error = s1Mini.lastError {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }

                    Divider().overlay(DesignTokens.borderSubtle)

                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(DesignTokens.textMuted)
                        Text("S1-mini is fine-tuned for English. For the other 24 languages supported by Voz, transcripts are passed directly without modification.")
                            .font(.system(size: 11))
                            .foregroundStyle(DesignTokens.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .monochromeCard()

            // Audio & Feedback Card
            VStack(alignment: .leading, spacing: 14) {
                Text("Audio & Feedback")
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(-0.02)
                    .foregroundStyle(DesignTokens.textPrimary)

                Toggle("Sound feedback on start & stop", isOn: $settings.soundFeedbackEnabled)
                    .font(.system(size: 13))
                Toggle("Launch SayItFlow at login", isOn: $settings.launchAtLogin)
                    .font(.system(size: 13))
            }
            .monochromeCard()
        }
    }

    // MARK: - Analytics Detail

    private var analyticsDetail: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                statCard(title: "Sessions", value: "\(analytics.totalSessions)")
                statCard(title: "Words Dictated", value: "\(analytics.totalWords)")
                statCard(title: "Speaking Time", value: Self.formatDuration(analytics.totalDurationSeconds))
                statCard(title: "Avg Words", value: "\(analytics.averageWordsPerSession)")
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Recent Sessions")
                        .font(.system(size: 14, weight: .semibold))
                        .tracking(-0.02)
                        .foregroundStyle(DesignTokens.textPrimary)
                    Spacer()
                    if !analytics.recentSessions.isEmpty {
                        Button("Clear History", role: .destructive) {
                            analytics.reset()
                        }
                        .buttonStyle(MonochromeOutlineButtonStyle(isCompact: true))
                    }
                }

                if analytics.recentSessions.isEmpty {
                    Text("No sessions recorded yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignTokens.textMuted)
                        .padding(.vertical, 12)
                } else {
                    VStack(spacing: 0) {
                        ForEach(analytics.recentSessions) { session in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.startedAt, style: .date)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(DesignTokens.textPrimary)
                                    Text("\(Self.formatDuration(session.durationSeconds)) · \(session.engine)")
                                        .font(.system(size: 11))
                                        .foregroundStyle(DesignTokens.textSecondary)
                                }
                                Spacer()
                                Text("\(session.words)w")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(DesignTokens.textPrimary)
                                StatusBadge(kind: Self.badge(for: session.outcome), text: session.outcome)
                            }
                            .padding(.vertical, 8)
                            Divider().overlay(DesignTokens.borderSubtle)
                        }
                    }
                }
            }
            .monochromeCard()
        }
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(DesignTokens.textMuted)
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundStyle(DesignTokens.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .monochromeCard(padding: 12)
    }

    private static func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total >= 60 {
            return "\(total / 60)m \(total % 60)s"
        }
        return "\(total)s"
    }

    private static func badge(for outcome: String) -> StatusBadgeKind {
        switch outcome {
        case "done": .granted
        case "stalled": .warning
        case "error": .denied
        default: .info
        }
    }

    // MARK: - Permissions Detail

    private var permissionsDetail: some View {
        VStack(spacing: 12) {
            ForEach(PermissionKind.allCases) { kind in
                let status = appState.permissionStatuses[kind] ?? .notDetermined
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(DesignTokens.textPrimary)
                        Text(kind.detail)
                            .font(.system(size: 12))
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                    Spacer()
                    StatusBadge(kind: status.badgeKind, showDot: true)
                    if status != .granted {
                        Button(fixingKind == kind ? "…" : "Grant") {
                            Task { await fix(kind) }
                        }
                        .buttonStyle(MonochromePrimaryButtonStyle(isCompact: true))
                        .disabled(fixingKind != nil)
                    }
                }
                .monochromeCard(padding: 12)
            }
        }
    }

    // MARK: - Diagnostics Detail

    private var diagnosticsDetail: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Button(copiedReport ? "✓ Copied Report" : "Copy Diagnostic Report") {
                    let report = DiagnosticReport.generate()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                    copiedReport = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copiedReport = false
                    }
                }
                .buttonStyle(MonochromePrimaryButtonStyle())

                Button("Open Logs Folder") {
                    NSWorkspace.shared.open(SessionTrace.logsDirectory)
                }
                .buttonStyle(MonochromeOutlineButtonStyle())

                Spacer()

                Button("Refresh") { refreshLogs() }
                    .buttonStyle(MonochromeGhostButtonStyle())
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Event Trace Logs")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignTokens.textPrimary)

                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        if recentLogsList.isEmpty {
                            Text("No trace logs yet.")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(DesignTokens.textMuted)
                        } else {
                            ForEach(Array(recentLogsList.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .foregroundStyle(DesignTokens.textSecondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(minHeight: 220, maxHeight: 350)
                .background(DesignTokens.surfaceSubtle, in: RoundedRectangle(cornerRadius: DesignTokens.radiusMd))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.radiusMd)
                        .stroke(DesignTokens.borderSubtle, lineWidth: 1)
                )
            }
            .monochromeCard()
        }
    }

    // MARK: - About Detail

    private var aboutDetail: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                BrandLockup(
                    size: .lg,
                    title: "SayItFlow",
                    tagline: "Ultra-fast On-Device Voice Dictation"
                )

                Text("SayItFlow provides push-to-talk voice dictation that runs completely on-device on Apple Silicon Neural Engine using Desert Ant's Voz model. Zero cloud calls, zero latency penalty, and 100% data privacy.")
                    .font(.system(size: 13))
                    .foregroundStyle(DesignTokens.textSecondary)

                Divider().overlay(DesignTokens.borderSubtle)

                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                    GridRow {
                        Text("Version").font(.system(size: 12)).foregroundStyle(DesignTokens.textSecondary)
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2.0")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(DesignTokens.textPrimary)
                    }
                    GridRow {
                        Text("Speech Engine").font(.system(size: 12)).foregroundStyle(DesignTokens.textSecondary)
                        Text("Desert Ant Voz (Apple Neural Engine)").font(.system(size: 12)).foregroundStyle(DesignTokens.textPrimary)
                    }
                    GridRow {
                        Text("Text Normalizer").font(.system(size: 12)).foregroundStyle(DesignTokens.textSecondary)
                        Text("\"S1-mini\" by \"Superwhisper\"").font(.system(size: 12)).foregroundStyle(DesignTokens.textPrimary)
                    }
                    GridRow {
                        Text("Design System").font(.system(size: 12)).foregroundStyle(DesignTokens.textSecondary)
                        Text("Ved Gupta Monochromatic Precision").font(.system(size: 12)).foregroundStyle(DesignTokens.textPrimary)
                    }
                    GridRow {
                        Text("App License").font(.system(size: 12)).foregroundStyle(DesignTokens.textSecondary)
                        Text("MIT © innovatorved").font(.system(size: 12)).foregroundStyle(DesignTokens.textPrimary)
                    }
                    GridRow {
                        Text("Voz License").font(.system(size: 12)).foregroundStyle(DesignTokens.textSecondary)
                        Text("Desert Ant Labs Source-Available 1.0").font(.system(size: 12)).foregroundStyle(DesignTokens.textPrimary)
                    }
                    GridRow {
                        Text("S1-mini License").font(.system(size: 12)).foregroundStyle(DesignTokens.textSecondary)
                        Text("Apache 2.0 (superwhisper.com)").font(.system(size: 12)).foregroundStyle(DesignTokens.textPrimary)
                    }
                    GridRow {
                        Text("Attribution").font(.system(size: 12)).foregroundStyle(DesignTokens.textSecondary)
                        Text("Desert Ant Labs B.V. & Superwhisper").font(.system(size: 12)).foregroundStyle(DesignTokens.textPrimary)
                    }
                }
            }
            .monochromeCard()
        }
    }

    private func refreshLogs() {
        recentLogsList = SessionTrace.recentLogs(limit: 80)
    }

    private func fix(_ kind: PermissionKind) async {
        fixingKind = kind
        defer { fixingKind = nil }
        _ = await Permissions.request(kind)
        appState.refreshPermissionsAndHotkey(allowDuringOnboarding: true)
    }

    private func configureTestInjection() {
        appState.refreshPermissionsAndHotkey(allowDuringOnboarding: true)
        appState.setOnboardingLiveHandlers(
            prefix: { demoText },
            update: { demoText = $0 },
            onComplete: { _ in
                hint = "Inserted!"
            }
        )
    }
}
