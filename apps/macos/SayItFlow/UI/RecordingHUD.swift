import AppKit
import SwiftUI

/// NSPanel subclass that can never steal keyboard focus from the user's active app.
private final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

enum HUDDisplayMode: Equatable {
    case full
    case minimal
}

enum HUDState: Equatable {
    case listening
    case transcribing
    case polishing
    case injecting
    case done
    case error(String)
    case hidden
}

@MainActor
final class RecordingHUDController: NSObject {
    static let shared = RecordingHUDController()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<RecordingHUDView>?
    private var targetAppIcon: NSImage?
    private var partialText = ""
    private var currentState: HUDState = .hidden
    private var hotkeyLabel = "hotkey"
    private var displayMode: HUDDisplayMode = .full
    private var audioLevel: Float = 0
    private var placementScreen: NSScreen?
    private var globalEscapeMonitor: Any?
    private var localEscapeMonitor: Any?
    private var lastAudioViewUpdate: CFAbsoluteTime = 0
    /// Live-typing release — text is already in the field, so post-release states
    /// (transcribing/polishing/done) must not resurrect the widget.
    private var releaseDismissed = false

    private override init() {
        super.init()
    }

    func show(
        state: HUDState,
        hotkeyLabel: String? = nil,
        displayMode: HUDDisplayMode = .full,
        targetAppIcon: NSImage? = nil
    ) {
        if state == .done {
            let text = AppState.shared.partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "SayItFlow"
                DictationHistoryStore.shared.record(text: text, appName: appName)
            }
        }
        if releaseDismissed {
            guard state == .listening else { return }
            releaseDismissed = false
        }
        if let hotkeyLabel {
            self.hotkeyLabel = hotkeyLabel
        }
        if let targetAppIcon {
            self.targetAppIcon = targetAppIcon
        } else if self.targetAppIcon == nil {
            self.targetAppIcon = NSWorkspace.shared.frontmostApplication?.icon ?? NSApp.applicationIconImage
        }
        self.displayMode = displayMode
        currentState = state
        if state == .listening {
            placementScreen = NSScreen.main ?? NSScreen.screens.first
        }
        ensurePanel()
        if let panel {
            applyMouseHandling(to: panel)
        }
        resizePanel()
        updateView()
        positionBottomCenter()
        panel?.orderFront(nil)
        installEscapeMonitors()
    }

    /// Hide at key release and ignore non-listening shows until the next session.
    func dismissForRelease() {
        releaseDismissed = true
        currentState = .hidden
        audioLevel = 0
        partialText = ""
        targetAppIcon = nil
        placementScreen = nil
        panel?.orderOut(nil)
        removeEscapeMonitors()
    }

    func updatePartial(_ text: String, keepListeningLabel: Bool = false) {
        partialText = text
        if displayMode == .full,
           !keepListeningLabel,
           currentState == .listening || currentState == .transcribing {
            currentState = .transcribing
        }
        updateView()
    }

    func updateAudioLevel(_ level: Float) {
        let clamped = min(max(level, 0), 1)
        // Low-pass exponential smoothing to prevent vibration from mic noise
        audioLevel = audioLevel * 0.6 + clamped * 0.4
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastAudioViewUpdate >= 0.04 else { return }
        lastAudioViewUpdate = now
        updateView()
    }

    func hide() {
        releaseDismissed = false
        currentState = .hidden
        audioLevel = 0
        partialText = ""
        targetAppIcon = nil
        placementScreen = nil
        panel?.orderOut(nil)
        removeEscapeMonitors()
    }

    private var panelSize: CGSize {
        switch displayMode {
        case .minimal:
            return CGSize(width: 140, height: 56)
        case .full:
            return CGSize(width: 364, height: 108)
        }
    }

    private func resizePanel() {
        guard let panel else { return }
        let size = panelSize
        guard let visible = placementScreen?.visibleFrame ?? NSScreen.main?.visibleFrame else { return }
        let originX = round(visible.midX - size.width / 2)
        let originY = visible.minY + 12
        panel.setFrame(NSRect(x: originX, y: originY, width: size.width, height: size.height), display: true)
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        updateHostingView()
        guard let hosting = hostingView else { return }

        let size = panelSize
        let panel = HUDPanel(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.contentView = hosting
        self.panel = panel
        applyMouseHandling(to: panel)
    }

    /// Full HUD accepts clicks (non-activating panel); minimal pill is click-through.
    private func applyMouseHandling(to panel: NSPanel) {
        panel.ignoresMouseEvents = displayMode != .full
    }

    private func updateView() {
        if hostingView == nil {
            ensurePanel()
        } else {
            resizePanel()
            updateHostingView()
        }
    }

    private func updateHostingView() {
        let view = RecordingHUDView(
            state: currentState,
            partialText: partialText,
            hotkeyLabel: hotkeyLabel,
            displayMode: displayMode,
            audioLevel: audioLevel,
            targetAppIcon: targetAppIcon,
            onDismiss: {
                AppState.shared.cancelDictation()
            }
        )
        if let hostingView {
            hostingView.rootView = view
        } else {
            hostingView = NSHostingView(rootView: view)
        }
    }

    private func positionBottomCenter() {
        resizePanel()
    }

    private func installEscapeMonitors() {
        removeEscapeMonitors()
        let handler: (NSEvent) -> Void = { event in
            guard event.keyCode == 53 else { return }
            guard !KeystrokeEmitter.isSimulated(event) else { return }
            Task { @MainActor in
                AppState.shared.cancelDictation()
            }
        }
        globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handler)
        if globalEscapeMonitor == nil {
            AppLogger.permissions.notice(
                "Global Escape monitor unavailable — Input Monitoring likely denied; Escape cancels only when SayItFlow is focused"
            )
        }
        localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                handler(event)
                return nil
            }
            return event
        }
    }

    private func removeEscapeMonitors() {
        if let globalEscapeMonitor {
            NSEvent.removeMonitor(globalEscapeMonitor)
            self.globalEscapeMonitor = nil
        }
        if let localEscapeMonitor {
            NSEvent.removeMonitor(localEscapeMonitor)
            self.localEscapeMonitor = nil
        }
    }
}


private struct PulsingDot: View {
    let color: Color
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .scaleEffect(isPulsing ? 1.25 : 0.85)
            .opacity(isPulsing ? 1.0 : 0.45)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.8)
                        .repeatForever(autoreverses: true)
                ) {
                    isPulsing = true
                }
            }
    }
}

struct RecordingHUDView: View {
    let state: HUDState
    let partialText: String
    let hotkeyLabel: String
    let displayMode: HUDDisplayMode
    let audioLevel: Float
    let targetAppIcon: NSImage?
    let onDismiss: () -> Void

    var body: some View {
        Group {
            if displayMode == .minimal {
                minimalBody
            } else {
                fullBody
            }
        }
        .animation(DesignTokens.easeOut, value: state)
    }

    private var minimalBody: some View {
        HStack(spacing: 8) {
            if state == .done {
                Circle()
                    .fill(DesignTokens.ready)
                    .frame(width: 8, height: 8)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DesignTokens.ready)
            } else if case .error = state {
                Circle()
                    .fill(DesignTokens.dangerFg)
                    .frame(width: 8, height: 8)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignTokens.dangerFg)
            } else {
                PulsingDot(color: DesignTokens.recording)
                WaveformGauge(level: audioLevel, color: DesignTokens.inkPrimary)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .frame(minWidth: 108)
        .background(
            Capsule()
                .fill(DesignTokens.canvas)
        )
        .overlay(
            Capsule()
                .stroke(DesignTokens.border, lineWidth: 1)
        )
        .clipShape(Capsule())
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 2)
        .padding(10)
    }

    private var fullBody: some View {
        HStack(spacing: 14) {
            brandMark
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: DesignTokens.baseFontSize, weight: .semibold))
                    .tracking(-0.03)
                    .foregroundStyle(DesignTokens.inkPrimary)
                if !partialText.isEmpty && (state == .transcribing || state == .listening) {
                    Text(partialText)
                        .font(.system(size: DesignTokens.baseFontSize))
                        .tracking(-0.01)
                        .foregroundStyle(DesignTokens.inkPrimary)
                        .lineLimit(2)
                } else {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .tracking(-0.01)
                        .foregroundStyle(subtitleColor)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if state != .hidden && state != .done {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DesignTokens.inkSecondary)
                        .frame(width: 22, height: 22)
                        .background(
                            DesignTokens.surface,
                            in: RoundedRectangle(cornerRadius: DesignTokens.radiusSm)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.radiusSm)
                                .stroke(DesignTokens.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help("Cancel (Esc)")
            }
        }
        .padding(.horizontal, DesignTokens.spaceLg)
        .padding(.vertical, DesignTokens.spaceMd)
        .frame(width: 340)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.radiusXl)
                .fill(DesignTokens.canvas)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.radiusXl)
                .stroke(DesignTokens.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.radiusXl))
        .shadow(color: Color.black.opacity(0.12), radius: 12, y: 4)
        .padding(10)
    }

    /// Target app icon or brand geometric mark
    private var brandMark: some View {
        ZStack {
            if let targetAppIcon {
                Image(nsImage: targetAppIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(DesignTokens.border, lineWidth: 1)
                    )
            } else {
                LogoMark(size: .md, tint: markColor)
            }
        }
        .scaleEffect(state == .listening ? 1.05 : 1.0)
        .animation(DesignTokens.easeOut, value: state)
    }

    private var markColor: Color {
        switch state {
        case .listening, .transcribing: DesignTokens.recording
        case .polishing, .injecting: DesignTokens.warningFg
        case .done: DesignTokens.ready
        case .error: DesignTokens.dangerFg
        default: DesignTokens.inkPrimary
        }
    }

    private var title: String {
        switch state {
        case .listening: "Listening"
        case .transcribing: "Voz Dictating"
        case .polishing: "Finishing"
        case .injecting: "Inserting"
        case .done: "Done"
        case .error: "Error"
        case .hidden: ""
        }
    }

    private var subtitle: String {
        switch state {
        case .listening:
            "Hold \(hotkeyLabel) · Esc to cancel"
        case .transcribing:
            if partialText.isEmpty { "Neural Engine transcribing…" } else { partialText }
        case .polishing: "Preparing text…"
        case .injecting: "Inserting at cursor…"
        case .done: "Inserted"
        case .error(let message): message
        case .hidden: ""
        }
    }

    private var subtitleColor: Color {
        if case .error = state { DesignTokens.dangerFg }
        else { DesignTokens.inkSecondary }
    }
}

/// Live waveform gauge — symmetric bar wave that swells with mic level.
struct WaveformGauge: View {
    let level: Float
    let color: Color

    private let barCount = 9

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(color)
                    .frame(width: 3, height: barHeight(index))
            }
        }
        .padding(.horizontal, 10)
        .animation(DesignTokens.reduceMotion ? nil : .linear(duration: 0.08), value: level)
    }

    private func barHeight(_ index: Int) -> CGFloat {
        // Noise gate: treat ambient mic hiss as silence
        let gated = level < 0.05 ? 0.0 : Double(level)
        let centerDistance = abs(Double(index) - Double(barCount - 1) / 2)
            / (Double(barCount - 1) / 2)   // 0 center … 1 edge
        let silhouette = 1.0 - centerDistance * 0.55
        let shaped = gated * 0.75 + 0.25
        return max(4, 24 * silhouette * shaped)
    }
}


