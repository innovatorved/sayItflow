import AppKit
import Foundation

enum DiagnosticReport {
    @MainActor
    static func generate() -> String {
        var sections: [String] = []

        // Header
        sections.append("""
        # SayItFlow Diagnostic Report
        Generated: \(ISO8601DateFormatter().string(from: Date()))
        """)

        // App & System
        let osVer = ProcessInfo.processInfo.operatingSystemVersionString
        let appVer = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let buildNum = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        sections.append("""
        ## System & Build
        - OS: macOS \(osVer)
        - Architecture: arm64
        - App Version: \(appVer) (\(buildNum))
        - Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")
        """)

        // Permissions
        let mic = Permissions.status(for: .microphone).label
        let ax = Permissions.status(for: .accessibility).label
        let inputMon = Permissions.status(for: .inputMonitoring).label
        let hotkeyTap = Permissions.probeHotkeyTap()
        sections.append("""
        ## Permissions & Input
        - Microphone: \(mic)
        - Accessibility: \(ax)
        - Input Monitoring: \(inputMon)
        - Event Tap Live: \(hotkeyTap)
        - Hotkey Mode: \(AppSettings.shared.hotkeyMode.label)
        - Live Injection Enabled: \(AppSettings.shared.liveInjectionEnabled)
        - Polish Intensity: \(AppSettings.shared.polishIntensity.label)
        - Polish Enabled: \(AppSettings.shared.polishEnabled)
        """)

        // Engine & Models
        let appState = AppState.shared
        let engineSettings = EngineSettings.shared
        let modelsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("SayItFlow/models").path ?? "unknown"
        sections.append("""
        ## Engine & Models
        - Engine Ready: \(appState.engineReady)
        - Speech STT Model: \(engineSettings.sttModelName) (\(engineSettings.sttModelArchitecture))
        - Voz Downloaded: \(VozEngine.shared.isDownloaded)
        - Voz Ready on Neural Engine: \(VozEngine.shared.isReady)
        - Spoken Language: \(engineSettings.selectedLanguage)
        """)

        // Active Focus Target
        let frontApp = NSWorkspace.shared.frontmostApplication
        let frontBundle = frontApp?.bundleIdentifier ?? "none"
        let frontPID = frontApp?.processIdentifier ?? -1
        var focusedRole = "none"
        if let focused = AXFocusResolver.focusedTextElement() {
            focusedRole = AXHelpers.role(of: focused) ?? "unknown"
        }
        sections.append("""
        ## Target Focus
        - Front App: \(frontBundle) (PID \(frontPID))
        - Focused AX Role: \(focusedRole)
        """)

        // Recent Logs
        let logs = SessionTrace.recentLogs(limit: 60)
        sections.append("""
        ## Recent Trace Logs
        ```
        \(logs.joined(separator: "\n"))
        ```
        """)

        return sections.joined(separator: "\n\n")
    }
}
