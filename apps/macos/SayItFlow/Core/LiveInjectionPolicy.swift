import Foundation

/// Apps where live AX/keystroke injection corrupts text (Monaco, Electron, terminals).
/// These use the minimal waveform HUD and batch paste on release.
enum LiveInjectionPolicy {
    static func supportsLiveTyping(bundleID: String?) -> Bool {
        guard let bundleID else { return true }
        let blockedBundleIDs: Set<String> = [
            "com.microsoft.VSCode",
            "com.todesktop.230313mzl4w4u92",
            "com.apple.Terminal",
            "com.googlecode.iterm2",
        ]
        return !blockedBundleIDs.contains(bundleID)
    }
}

/// Determines the optimal injection strategy for target applications.
/// Electron apps, web browsers, and terminals require Paste (⌘V) because AX selected-text
/// either fails, silently no-ops, or corrupts DOM state.
enum InjectionTargetPolicy {
    static func prefersPaste(bundleID: String?) -> Bool {
        guard let bundle = bundleID?.lowercased() else { return true }
        let pasteBundles: Set<String> = [
            "com.google.chrome",
            "com.google.chrome.canary",
            "com.brave.browser",
            "com.microsoft.edgemac",
            "company.thebrowser.browser",
            "com.operasoftware.opera",
            "org.mozilla.firefox",
            "net.whatsapp.whatsapp",
            "com.tinyspeck.slackmacgap",
            "com.hnc.discord",
            "com.microsoft.vscode",
            "md.obsidian",
            "notion.id",
            "com.apple.terminal",
            "com.googlecode.iterm2",
            "dev.warp.warp-stable",
            "com.apple.safari"
        ]
        if pasteBundles.contains(bundle) { return true }
        if bundle.contains("electron") || bundle.contains("todesktop") || bundle.contains("chromium") {
            return true
        }
        return false
    }
}
