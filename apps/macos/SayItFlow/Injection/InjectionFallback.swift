import AppKit
import Foundation
import UserNotifications

enum InjectionFallback {
    @MainActor
    static func copyToClipboardWithFeedback(_ text: String, playSound: Bool = true) {
        guard !text.isEmpty else { return }

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        // Mark as concealed so clipboard managers don't persist dictated text
        pb.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))

        if playSound, AppSettings.shared.soundFeedbackEnabled {
            NSSound(named: "Basso")?.play()
        }

        let content = UNMutableNotificationContent()
        content.title = "SayItFlow"
        content.body = "Text copied — paste manually (⌘V)"

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        Task {
            try? await UNUserNotificationCenter.current().add(request)
        }
    }
}
