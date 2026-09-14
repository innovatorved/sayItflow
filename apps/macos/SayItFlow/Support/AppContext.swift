import AppKit
import Foundation

/// Context about the frontmost app, used to tune polish tone.
struct AppContext: Sendable, Equatable {
    var bundleIdentifier: String?
    var appName: String?
    var appTone: String

    static let `default` = AppContext(
        bundleIdentifier: nil,
        appName: nil,
        appTone: "neutral professional"
    )

    @MainActor
    static func fromFrontmostApp() -> AppContext {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return .default
        }
        let bundleID = app.bundleIdentifier
        let name = app.localizedName
        let tone = toneForBundle(bundleID)
        return AppContext(bundleIdentifier: bundleID, appName: name, appTone: tone)
    }

    private static func toneForBundle(_ bundleID: String?) -> String {
        guard let bundleID else { return AppContext.default.appTone }
        let id = bundleID.lowercased()
        switch id {
        case _ where id.contains("mail"):
            return "formal email"
        case _ where id.contains("slack") || id.contains("discord"):
            return "casual chat"
        case _ where id.contains("xcode") || id.contains("vscode") || id.contains("cursor"):
            return "technical concise"
        default:
            return AppContext.default.appTone
        }
    }
}
