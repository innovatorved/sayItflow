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
