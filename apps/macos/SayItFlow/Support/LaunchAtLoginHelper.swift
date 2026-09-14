import ServiceManagement
import os

enum LaunchAtLoginHelper {
    static func setEnabled(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                AppLogger.dictation.debug("Launch at login registration failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    static func unregisterIfPossible() {
        setEnabled(false)
    }
}
