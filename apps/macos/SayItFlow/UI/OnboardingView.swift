import SwiftUI
import AppKit

struct OnboardingView: View {
    @ObservedObject var appState: AppState
    let onComplete: () -> Void

    @ObservedObject private var vozEngine = VozEngine.shared
    @ObservedObject private var s1Mini = S1MiniEngine.shared
    @State private var step: SetupStep
    @State private var requestingKind: PermissionKind?
    @State private var hotkeyProbePassed = false
    @State private var isBusy = false
    @State private var demoText = ""
    @State private var tryItHint = ""
    @State private var hasCompletedDemoDictation = false
    @State private var launchAtLogin = false
    @State private var vozDownloadError: String?
    @State private var s1DownloadError: String?

    private let settings = AppSettings.shared
    private static let permissionPollAttempts = 12

    init(appState: AppState = .shared, startingAt: SetupStep? = nil, onComplete: @escaping () -> Void) {
        self.appState = appState
        let initial = startingAt ?? SetupStep.firstIncompleteStep()
        _step = State(initialValue: initial)
        self.onComplete = onComplete
    }

    var body: some View {
        VStack(spacing: 0) {
            topNav
            Divider().overlay(DesignTokens.borderPrimary)

            HStack(alignment: .top, spacing: 0) {
                // Left sidebar rail
                sidebarRail
                    .frame(width: 240)
                    .background(DesignTokens.surface)
                
                Divider().overlay(DesignTokens.borderPrimary)

                // Right interactive step content
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            stepHeader
                            stepContent
                        }
                        .padding(28)
                    }
                    
                    Spacer(minLength: 0)
                    
                    Divider().overlay(DesignTokens.borderPrimary)
                    footer
                }
            }
        }
        .frame(minWidth: 800, idealWidth: 860, maxWidth: .infinity, minHeight: 560, idealHeight: 600, maxHeight: .infinity)
        .background(DesignTokens.canvas)
        .task {
            tryItHint = "Hold \(settings.hotkeyMode.label) for half a second, speak, then release."
            launchAtLogin = settings.launchAtLogin
            updateHotkeyProbePassed()
            vozEngine.refreshStatus()
            s1Mini.refreshStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appState.refreshPermissionsAndHotkey(allowDuringOnboarding: true)
            updateHotkeyProbePassed()
            vozEngine.refreshStatus()
            s1Mini.refreshStatus()
            if let kind = requestingKind, Permissions.status(for: kind) == .granted {
                requestingKind = nil
            }
            autoAdvanceIfNeeded()
        }
        .onChange(of: appState.phase) { _, phase in
            guard step == .tryDictation, case .recording = phase else { return }
            if !appState.partialTranscript.isEmpty {
                tryItHint = "Transcribing with Voz…"
            }
        }
        .onChange(of: step) { oldStep, newStep in
            if newStep == .verifyHotkey {
                appState.refreshPermissionsAndHotkey(allowDuringOnboarding: true)
                updateHotkeyProbePassed()
                vozEngine.refreshStatus()
                s1Mini.refreshStatus()
            }
            if newStep == .tryDictation {
                configureTryIt()
            } else {
                appState.clearOnboardingHandlers()
                if oldStep == .tryDictation {
                    appState.stopHotkey()
                }
            }
        }
        .task(id: step) {
            guard step.permissionKind != nil else { return }
            for _ in 0..<Self.permissionPollAttempts {
                guard !Task.isCancelled else { return }
                autoAdvanceIfNeeded()
                if step.permissionKind == nil || isCurrentPermissionGranted { return }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    // MARK: - Top Nav

    private var topNav: some View {
        HStack(spacing: 12) {
            BrandLockup(size: .sm)
            Spacer()
            StatusBadge(
                kind: .neutral,
                text: "STEP \(step.rawValue + 1) OF \(SetupStep.allCases.count)"
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(DesignTokens.surface)
    }

    // MARK: - Sidebar Rail

    private var sidebarRail: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Steps list
            VStack(alignment: .leading, spacing: 6) {
                Text("SETUP STEPS")
                    .font(DesignTokens.fontMono(size: 10, weight: .medium))
                    .tracking(DesignTokens.trackingLoose)
                    .foregroundStyle(DesignTokens.textMuted)
                    .padding(.bottom, 4)

                ForEach(SetupStep.allCases) { item in
                    stepRow(item)
                }
            }

            Spacer()

            // System Specs Badge Card
            VStack(alignment: .leading, spacing: 8) {
                Text("ARCHITECTURE")
                    .font(DesignTokens.fontMono(size: 10, weight: .medium))
                    .tracking(DesignTokens.trackingLoose)
                    .foregroundStyle(DesignTokens.textMuted)

                specItem(label: "MODEL", value: "Desert Ant Voz")
                specItem(label: "COMPUTE", value: "Apple Neural Engine")
                specItem(label: "WEIGHTS", value: "467 MB Core ML")
                specItem(label: "PRIVACY", value: "100% Offline")
            }
            .monochromeSubCard(radius: DesignTokens.radiusMd, padding: 12)
        }
        .padding(18)
    }

    private func stepRow(_ item: SetupStep) -> some View {
        let isCurrent = item == step
        let isPast = item.rawValue < step.rawValue

        return HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(isCurrent ? DesignTokens.textPrimary : (isPast ? DesignTokens.successFg : DesignTokens.borderSubtle), lineWidth: 1)
                    .frame(width: 16, height: 16)

                if isPast {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(DesignTokens.successFg)
                } else if isCurrent {
                    Circle()
                        .fill(DesignTokens.textPrimary)
                        .frame(width: 6, height: 6)
                }
            }

            Text(item.title)
                .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                .tracking(DesignTokens.trackingTight)
                .foregroundStyle(isCurrent ? DesignTokens.textPrimary : (isPast ? DesignTokens.textSecondary : DesignTokens.textMuted))

            Spacer()
        }
        .padding(.vertical, 3)
    }

    private func specItem(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(DesignTokens.fontMono(size: 10))
                .foregroundStyle(DesignTokens.textMuted)
            Spacer()
            Text(value)
                .font(DesignTokens.fontMono(size: 10, weight: .medium))
                .foregroundStyle(DesignTokens.textSecondary)
        }
    }

    // MARK: - Step Header

    private var stepHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(step.title)
                .font(DesignTokens.fontDisplay(size: 20, weight: .semibold))
                .tracking(DesignTokens.trackingTighter)
                .foregroundStyle(DesignTokens.textPrimary)

            Text(step.subtitle)
                .font(.system(size: 13))
                .foregroundStyle(DesignTokens.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        Group {
            switch step {
            case .welcome:
                welcomeStep
            case .microphone, .accessibility, .inputMonitoring:
                if let kind = step.permissionKind {
                    PermissionStepView(
                        kind: kind,
                        status: Permissions.status(for: kind),
                        isRequesting: requestingKind == kind,
                        onPrimaryAction: { Task { await requestPermission(kind) } }
                    )
                }
            case .verifyHotkey:
                verifyStep
            case .tryDictation:
                tryItStep
            }
        }
        .transition(.opacity)
        .id(step)
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Zero-latency dictation on Apple Silicon.")
                    .font(DesignTokens.fontDisplay(size: 15, weight: .semibold))
                    .tracking(DesignTokens.trackingTight)
                    .foregroundStyle(DesignTokens.textPrimary)

                Text("SayItFlow uses Desert Ant's Voz model directly compiled for the Apple Neural Engine (ANE). Press and hold your hotkey anywhere on your Mac to speak, release to inject instant text at your active cursor.")
                    .font(.system(size: 13))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .lineSpacing(3)
            }
            .monochromeCard(radius: DesignTokens.radiusLg, padding: 18)

            VStack(alignment: .leading, spacing: 12) {
                Text("KEY SPECIFICATIONS")
                    .font(DesignTokens.fontMono(size: 10, weight: .medium))
                    .tracking(DesignTokens.trackingLoose)
                    .foregroundStyle(DesignTokens.textMuted)

                HStack(spacing: 12) {
                    specBox(title: "0% CPU / GPU", desc: "Pure Neural Engine")
                    specBox(title: "25 Languages", desc: "Multilingual Core ML")
                    specBox(title: "Local & Private", desc: "Zero Cloud API Calls")
                }
            }
        }
    }

    private func specBox(title: String, desc: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(DesignTokens.fontDisplay(size: 13, weight: .semibold))
                .tracking(DesignTokens.trackingTight)
                .foregroundStyle(DesignTokens.textPrimary)
            Text(desc)
                .font(.system(size: 11))
                .foregroundStyle(DesignTokens.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .monochromeSubCard(radius: DesignTokens.radiusMd, padding: 12)
    }

    private var verifyStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Permissions card
            VStack(alignment: .leading, spacing: 12) {
                Text("PERMISSIONS STATUS")
                    .font(DesignTokens.fontMono(size: 10, weight: .medium))
                    .tracking(DesignTokens.trackingLoose)
                    .foregroundStyle(DesignTokens.textMuted)

                ForEach(PermissionKind.allCases) { kind in
                    verifyRow(title: kind.title, ok: Permissions.status(for: kind) == .granted)
                }
            }
            .monochromeCard(radius: DesignTokens.radiusLg, padding: 16)

            // System & Voz Card
            VStack(alignment: .leading, spacing: 12) {
                Text("SYSTEM & SPEECH ENGINE")
                    .font(DesignTokens.fontMono(size: 10, weight: .medium))
                    .tracking(DesignTokens.trackingLoose)
                    .foregroundStyle(DesignTokens.textMuted)

                verifyRow(
                    title: "Push-to-talk hotkey listener",
                    ok: hotkeyProbePassed,
                    detail: hotkeyProbePassed
                        ? "Global push-to-talk listener is active."
                        : "Enable Accessibility and Input Monitoring, then return here."
                )

                Divider().overlay(DesignTokens.borderSubtle)

                // Voz Engine Status Row
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Desert Ant Voz Model (467 MB)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DesignTokens.textPrimary)

                        if vozEngine.isDownloading {
                            Text("Downloading: \(Int(vozEngine.downloadProgress * 100))%…")
                                .font(.system(size: 11))
                                .foregroundStyle(DesignTokens.textSecondary)
                        } else if vozEngine.isDownloaded {
                            Text("Ready on Apple Neural Engine (ANE)")
                                .font(.system(size: 11))
                                .foregroundStyle(DesignTokens.textSecondary)
                        } else {
                            Text("Model weights not yet cached on disk.")
                                .font(.system(size: 11))
                                .foregroundStyle(DesignTokens.textSecondary)
                        }
                    }

                    Spacer()

                    if vozEngine.isDownloading {
                        ProgressView(value: vozEngine.downloadProgress)
                            .frame(width: 90)
                    } else if vozEngine.isDownloaded {
                        StatusBadge(kind: .granted, text: "Ready")
                    } else {
                        Button("Download Model") {
                            Task {
                                do {
                                    try await vozEngine.downloadModel()
                                } catch {
                                    vozDownloadError = error.localizedDescription
                                }
                            }
                        }
                        .buttonStyle(MonochromeOutlineButtonStyle(isCompact: true))
                    }
                }

                if let err = vozDownloadError {
                    Text("Download failed: \(err)")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.dangerFg)
                }

                Divider().overlay(DesignTokens.borderSubtle)

                // S1-mini Engine Status Row
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("S1-mini by Superwhisper (462 MB)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DesignTokens.textPrimary)

                        if s1Mini.isDownloading {
                            Text("Downloading: \(Int(s1Mini.downloadProgress * 100))%…")
                                .font(.system(size: 11))
                                .foregroundStyle(DesignTokens.textSecondary)
                        } else if s1Mini.isDownloaded {
                            Text("Ready on Apple Silicon (Text Normalizer)")
                                .font(.system(size: 11))
                                .foregroundStyle(DesignTokens.textSecondary)
                        } else {
                            Text("Optional: cleans speech fillers & fixes punctuation.")
                                .font(.system(size: 11))
                                .foregroundStyle(DesignTokens.textSecondary)
                        }
                    }

                    Spacer()

                    if s1Mini.isDownloading {
                        ProgressView(value: max(s1Mini.downloadProgress, 0.05))
                            .frame(width: 90)
                    } else if s1Mini.isDownloaded {
                        StatusBadge(kind: .granted, text: "Ready")
                    } else {
                        Button("Download Model") {
                            Task {
                                do {
                                    try await s1Mini.downloadModel()
                                } catch {
                                    s1DownloadError = error.localizedDescription
                                }
                            }
                        }
                        .buttonStyle(MonochromeOutlineButtonStyle(isCompact: true))
                    }
                }

                if let err = s1DownloadError {
                    Text("Download failed: \(err)")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.dangerFg)
                }

                Divider().overlay(DesignTokens.borderSubtle)

                Toggle("Launch at login", isOn: $launchAtLogin)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DesignTokens.textPrimary)

                if !hotkeyProbePassed {
                    Button("Open Privacy Settings") {
                        Permissions.openSettings(for: .accessibility)
                    }
                    .buttonStyle(MonochromeOutlineButtonStyle(isCompact: true))
                }
            }
            .monochromeCard(radius: DesignTokens.radiusLg, padding: 16)
        }
    }

    private var tryItStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("PUSH-TO-TALK TEST BENCH")
                        .font(DesignTokens.fontMono(size: 10, weight: .medium))
                        .tracking(DesignTokens.trackingLoose)
                        .foregroundStyle(DesignTokens.textMuted)

                    Spacer()

                    HotkeyKeyCap(label: settings.hotkeyMode.label)
                }

                Text(tryItHint.isEmpty ? "Hold \(settings.hotkeyMode.label), speak, then release." : tryItHint)
                    .font(DesignTokens.fontMono(size: 12))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DesignTokens.surfaceSubtle, in: RoundedRectangle(cornerRadius: DesignTokens.radiusMd))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.radiusMd)
                            .stroke(DesignTokens.borderSubtle, lineWidth: 1)
                    )

                TextEditor(text: $demoText)
                    .font(.system(size: 13))
                    .frame(minHeight: 110)
                    .padding(8)
                    .background(DesignTokens.surfaceSubtle, in: RoundedRectangle(cornerRadius: DesignTokens.radiusMd))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.radiusMd)
                            .stroke(DesignTokens.borderPrimary, lineWidth: 1)
                    )
                    .onChange(of: demoText) { _, newText in
                        if !newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            hasCompletedDemoDictation = true
                        }
                    }

                HStack {
                    Text("Try speaking: \"Hello world, this is SayItFlow.\"")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.textMuted)

                    Spacer()

                    if hasCompletedDemoDictation {
                        StatusBadge(kind: .granted, text: "Dictation Verified")
                    }
                }
            }
            .monochromeCard(radius: DesignTokens.radiusLg, padding: 16)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if step != .welcome {
                Button("Back") { goBack() }
                    .buttonStyle(MonochromeOutlineButtonStyle())
            }

            Spacer()

            Button(primaryButtonTitle) {
                Task { await primaryAction() }
            }
            .buttonStyle(MonochromePrimaryButtonStyle())
            .disabled((step.permissionKind != nil ? requestingKind != nil : false) || isBusy || !canAdvance)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .background(DesignTokens.surface)
    }

    // MARK: - Helpers

    private var isCurrentPermissionGranted: Bool {
        guard let kind = step.permissionKind else { return false }
        return Permissions.status(for: kind) == .granted
    }

    private var primaryButtonTitle: String {
        switch step {
        case .welcome: "Get Started"
        case .verifyHotkey: "Continue"
        case .tryDictation: "Finish"
        default: "Continue"
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .welcome: true
        case .microphone, .accessibility, .inputMonitoring:
            isCurrentPermissionGranted
        case .verifyHotkey: hotkeyProbePassed
        case .tryDictation: hasCompletedDemoDictation
        }
    }

    private func verifyRow(title: String, ok: Bool, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DesignTokens.textPrimary)
                Spacer()
                StatusBadge(kind: ok ? .granted : .denied, text: ok ? "Ready" : "Needs attention")
            }
            if let detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.textSecondary)
            }
        }
    }

    @MainActor
    private func updateHotkeyProbePassed() {
        if appState.isHotkeyRunning, appState.isHotkeyHealthy {
            hotkeyProbePassed = true
            return
        }
        hotkeyProbePassed = Permissions.probeHotkeyTap()
    }

    private func requestPermission(_ kind: PermissionKind) async {
        if Permissions.status(for: kind) == .granted {
            autoAdvanceIfNeeded()
            return
        }
        requestingKind = kind
        defer { requestingKind = nil }
        _ = await Permissions.request(kind)
        appState.refreshPermissionsAndHotkey(allowDuringOnboarding: true)
        try? await Task.sleep(for: .milliseconds(400))
        autoAdvanceIfNeeded()
    }

    @MainActor
    private func autoAdvanceIfNeeded() {
        guard step.permissionKind != nil, isCurrentPermissionGranted else { return }
        guard requestingKind == nil else { return }
        guard let next = SetupStep(rawValue: step.rawValue + 1) else { return }
        withAnimation(DesignTokens.easeOut) { step = next }
    }

    private func goBack() {
        guard let prev = SetupStep(rawValue: step.rawValue - 1) else { return }
        withAnimation(DesignTokens.easeOut) { step = prev }
    }

    private func goForward() {
        guard let next = SetupStep(rawValue: step.rawValue + 1) else { return }
        withAnimation(DesignTokens.easeOut) { step = next }
    }

    private func primaryAction() async {
        switch step {
        case .tryDictation:
            isBusy = true
            if launchAtLogin {
                LaunchAtLoginHelper.setEnabled(true)
                AppSettings.shared.launchAtLogin = true
            }
            appState.clearOnboardingHandlers()
            isBusy = false
            onComplete()
        default:
            goForward()
        }
    }

    private func configureTryIt() {
        appState.setOnboardingLiveHandlers(
            prefix: { demoText },
            update: { demoText = $0 },
            onComplete: { text in
                tryItHint = "Transcribed with Voz!"
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    hasCompletedDemoDictation = true
                }
            }
        )
        appState.startHotkeyForOnboardingTry()
    }
}
