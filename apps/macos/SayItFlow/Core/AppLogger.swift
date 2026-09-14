import Foundation
import os

enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.innovatorved.sayitflow"

    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    static let dictation = Logger(subsystem: subsystem, category: "dictation")
    static let permissions = Logger(subsystem: subsystem, category: "permissions")
    static let polish = Logger(subsystem: subsystem, category: "polish")
    static let injection = Logger(subsystem: subsystem, category: "injection")
    static let audio = Logger(subsystem: subsystem, category: "audio")
}
