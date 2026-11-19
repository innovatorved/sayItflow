import SwiftUI
import KeyboardShortcuts

enum MainWindowSection: String, CaseIterable, Identifiable, Hashable {
    case status
    case history
    case dictation
    case text
    case permissions
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .status: "Status"
        case .history: "History"
        case .dictation: "Dictation"
        case .text: "Audio & System"
        case .permissions: "Permissions"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .status: "waveform.circle"
        case .history: "clock.arrow.circlepath"
        case .dictation: "mic"
        case .text: "gearshape"
        case .permissions: "lock.shield"
        case .about: "info.circle"
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var engineSettings = EngineSettings.shared
    @ObservedObject private var vozEngine = VozEngine.shared
    @ObservedObject private var s1Mini = S1MiniEngine.shared

    @State private var selection: MainWindowSection = .status
    @State private var demoText = ""
    @State private var hint = ""
    @State private var fixingKind: PermissionKind?

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
            } else if !Permissions.allGranted() {
                selection = .permissions
            }
            if selection == .status {
                configureTestInjection()
            }
            vozEngine.refreshStatus()
            s1Mini.refreshStatus()
        }
        .onChange(of: selection) { _, section in
            if section == .status {
                configureTestInjection()
            } else {
                appState.clearOnboardingHandlers()
            }
        }
        .onDisappear { appState.clearOnboardingHandlers() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appState.refreshPermissionStatuses()
            vozEngine.refreshStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sayItFlowSelectSection)) { notification in
            if let target = notification.object as? MainWindowSection {
                selection = target
            }
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
        case .history: "Every dictation automatically saved locally with exact timestamps."
        case .dictation: "Hotkey trigger and language settings for Voz speech recognition."
        case .text: "Output formatting, custom vocabulary, and system preferences."
        case .permissions: "System accessibility and audio input access control."
        case .about: "SayItFlow version information and open-source models."
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
        case .status:
            statusDetail
        case .history:
            TranscriptHistoryView()
        case .dictation:
            dictationSettings
        case .text:
            textSettings
        case .permissions:
            permissionsDetail
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

                // Row 2: Embedded In-Process Normalizer (Emberon-2 or S1-mini)
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(s1Mini.selectedModel.shortName)
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
                        Text(s1Mini.selectedModel.subtitle)
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
                        Button("Download (\(s1Mini.selectedModel.sizeMB) MB)") {
                            Task { try? await s1Mini.downloadModel() }
                        }
                        .buttonStyle(MonochromePrimaryButtonStyle(isCompact: true))
                    }
                }

                Divider().overlay(DesignTokens.borderSubtle)

                Text("Desert Ant Voz · Emberon-2 by Promethic Labs · S1-mini by Superwhisper. Runs 100% in-process — no external apps required.")
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
            // Text Normalization Card (Embedded In-Process llama.cpp)
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("AI Text Cleanup")
                                .font(.system(size: 14, weight: .semibold))
                                .tracking(-0.02)
                                .foregroundStyle(DesignTokens.textPrimary)
                            Text("Built-in Metal")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(DesignTokens.textMuted)
                        }
                        Text("Runs directly inside SayItFlow (no external apps) to clean fillers, stutters, punctuation, and self-corrections.")
                            .font(.system(size: 11))
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                    Spacer()
                    Toggle("", isOn: $s1Mini.isEnabled)
                        .toggleStyle(.switch)
                }

                if s1Mini.isEnabled {
                    Divider().overlay(DesignTokens.borderSubtle)

                    HStack {
                        Text("Model")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DesignTokens.textSecondary)
                            .frame(width: 80, alignment: .leading)
                        Picker("", selection: $s1Mini.selectedModel) {
                            ForEach(NormalizerModel.allCases) { model in
                                Text("\(model.displayName) · \(model.sizeMB) MB").tag(model)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    if s1Mini.selectedModel == .s1Mini {
                        // Control Axes: Styling, Structure, Context (S1-mini only)
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
                    }

                    Divider().overlay(DesignTokens.borderSubtle)

                    // Model Download / Status
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text("\(s1Mini.selectedModel.shortName) Weights (\(s1Mini.selectedModel.sizeMB) MB)")
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
                            Text(s1Mini.isDownloaded ? "Runs natively in-process on Metal GPU — zero external apps." : "When not downloaded, instant built-in Swift rules clean your text.")
                                .font(.system(size: 11))
                                .foregroundStyle(DesignTokens.textMuted)
                        }
                        Spacer()

                        if s1Mini.isDownloading {
                            ProgressView(value: s1Mini.downloadProgress)
                                .frame(width: 100)
                        } else if !s1Mini.isDownloaded {
                            Button("Download \(s1Mini.selectedModel.shortName)") {
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
                        Text("AI cleanup is fine-tuned for English. For the other 24 languages supported by Voz, transcripts are passed directly without modification.")
                            .font(.system(size: 11))
                            .foregroundStyle(DesignTokens.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .monochromeCard()

            // Custom Vocabulary Card
            VStack(alignment: .leading, spacing: 10) {
                Text("Custom Vocabulary")
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(-0.02)
                    .foregroundStyle(DesignTokens.textPrimary)

                Text("Comma-separated names, acronyms, or technical terms to preserve exact spelling and casing.")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.textSecondary)

                TextField("e.g. SayItFlow, SwiftUI, Xcode, PostgreSQL", text: $settings.vocabularyText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(DesignTokens.surfaceSubtle, in: RoundedRectangle(cornerRadius: DesignTokens.radiusMd))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.radiusMd)
                            .stroke(DesignTokens.borderSubtle, lineWidth: 1)
                    )
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
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.7.0")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(DesignTokens.textPrimary)
                    }
                    GridRow {
                        Text("Speech Engine").font(.system(size: 12)).foregroundStyle(DesignTokens.textSecondary)
                        Text("Desert Ant Voz (Apple Neural Engine)").font(.system(size: 12)).foregroundStyle(DesignTokens.textPrimary)
                    }
                    GridRow {
                        Text("Text Normalizers").font(.system(size: 12)).foregroundStyle(DesignTokens.textSecondary)
                        Text("Emberon-2 (Promethic Labs / LFM2.5-350M) & \"S1-mini\" by \"Superwhisper\"").font(.system(size: 12)).foregroundStyle(DesignTokens.textPrimary)
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

    private func fix(_ kind: PermissionKind) async {
        fixingKind = kind
        defer { fixingKind = nil }
        _ = await Permissions.request(kind)
        appState.refreshPermissionsAndHotkey(allowDuringOnboarding: true)
    }

    private func configureTestInjection() {
        appState.refreshPermissionsAndHotkey(allowDuringOnboarding: true)
        appState.setOnboardingLiveHandlers(
            prefix: { demoText.trimmingCharacters(in: .whitespaces) },
            update: { demoText = $0 },
            onComplete: { text in
                let trimmed = demoText.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    demoText = text
                } else {
                    demoText = trimmed + " " + text
                }
                hint = "Inserted!"
            }
        )
    }
}
