import Foundation

/// Maps a target app's bundle ID to an S1-mini normalization context.
enum AppContext {
    static func s1Context(forBundleID bundleID: String?) -> S1Context? {
        guard let bundleID else { return nil }
        let id = bundleID.lowercased()
        if id.contains("mail") || id.contains("outlook") || id.contains("spark") || id.contains("superhuman") {
            return .email
        }
        return nil
    }
}
