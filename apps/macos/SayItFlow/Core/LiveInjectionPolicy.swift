import AppKit
import Foundation

/// Determines the optimal injection strategy for target applications.
/// Electron apps, web browsers, and terminals require Paste (⌘V) because AX selected-text
/// either fails, silently no-ops, or corrupts DOM state.
enum InjectionTargetPolicy {
    static func prefersPaste(bundleID: String?, pid: pid_t? = nil) -> Bool {
        if let pid, isElectronOrCEFApp(pid: pid) {
            return true
        }
        guard let bundle = bundleID?.lowercased() else { return true }
        let pasteBundles: Set<String> = [
            "com.google.antigravity",
            "com.exafunction.windsurf",
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
            "dev.zed.zed",
            "com.anthropic.claudefordesktop",
            "com.openai.chat",
            "com.linear",
            "com.figma.desktop",
            "md.obsidian",
            "notion.id",
            "com.apple.terminal",
            "com.googlecode.iterm2",
            "dev.warp.warp-stable",
            "com.mitchellh.ghostty",
            "org.alacritty",
            "net.kovidgoyal.kitty",
            "com.github.wez.wezterm",
            "com.apple.safari"
        ]
        if pasteBundles.contains(bundle) { return true }
        let pasteSubstrings = [
            "antigravity", "windsurf", "cursor", "vscode",
            "electron", "todesktop", "chromium"
        ]
        if pasteSubstrings.contains(where: { bundle.contains($0) }) {
            return true
        }
        return false
    }

    private static func isElectronOrCEFApp(pid: pid_t) -> Bool {
        guard let bundleURL = NSRunningApplication(processIdentifier: pid)?.bundleURL else {
            return false
        }
        let frameworks = bundleURL.appendingPathComponent("Contents/Frameworks", isDirectory: true)
        let fm = FileManager.default
        return fm.fileExists(atPath: frameworks.appendingPathComponent("Electron Framework.framework").path)
            || fm.fileExists(atPath: frameworks.appendingPathComponent("Chromium Embedded Framework.framework").path)
    }
}
