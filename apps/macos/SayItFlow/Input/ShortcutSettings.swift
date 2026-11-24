import Foundation
import Combine
import KeyboardShortcuts
import ServiceManagement

extension KeyboardShortcuts.Name {
    static let pushToTalk = Self("pushToTalk")
}

enum HotkeyMode: String, CaseIterable, Identifiable, Codable {
    case holdSpace
    case fnKey
    case rightOption
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .holdSpace: "Hold Space"
        case .fnKey: "Hold Fn"
        case .rightOption: "Hold Right ⌥"
        case .custom: "Custom Combo"
        }
    }

    var holdInstruction: String {
        switch self {
        case .holdSpace: "Hold Space"
        case .fnKey: "Hold Fn"
        case .rightOption: "Hold Right ⌥"
        case .custom: "Hold your custom shortcut"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var hotkeyMode: HotkeyMode {
        didSet {
            persist()
            if oldValue != hotkeyMode {
                AppState.shared.refreshHotkeyMode()
            }
        }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            persist()
            LaunchAtLoginHelper.setEnabled(launchAtLogin)
        }
    }
    @Published var vocabularyText: String {
        didSet {
            let terms = vocabularyText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            VocabularyStore.save(Vocabulary(terms: terms))
        }
    }
    @Published var soundFeedbackEnabled: Bool {
        didSet { persist() }
    }

    private init() {
        let defaults = UserDefaults.standard
        hotkeyMode = HotkeyMode(rawValue: defaults.string(forKey: "hotkeyMode") ?? "") ?? .holdSpace
        if #available(macOS 13.0, *) {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } else {
            launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        }
        vocabularyText = VocabularyStore.load().terms.joined(separator: ", ")
        soundFeedbackEnabled = defaults.object(forKey: "soundFeedbackEnabled") as? Bool ?? true
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(hotkeyMode.rawValue, forKey: "hotkeyMode")
        defaults.set(launchAtLogin, forKey: "launchAtLogin")
        defaults.set(soundFeedbackEnabled, forKey: "soundFeedbackEnabled")
    }
}
