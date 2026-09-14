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
}

enum PolishIntensity: String, CaseIterable, Identifiable, Codable {
    case off
    case light
    case standard

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: "Off"
        case .light: "Light (grammar only)"
        case .standard: "Standard"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var hotkeyMode: HotkeyMode {
        didSet { persist() }
    }
    @Published var polishEnabled: Bool {
        didSet { persist() }
    }
    @Published var polishIntensity: PolishIntensity {
        didSet { persist() }
    }
    @Published var localeIdentifier: String {
        didSet { persist() }
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
    @Published var liveInjectionEnabled: Bool {
        didSet { persist() }
    }
    @Published var soundFeedbackEnabled: Bool {
        didSet { persist() }
    }

    var locale: Locale { Locale(identifier: localeIdentifier) }

    private init() {
        let defaults = UserDefaults.standard
        hotkeyMode = HotkeyMode(rawValue: defaults.string(forKey: "hotkeyMode") ?? "") ?? .holdSpace
        let storedPolishEnabled = defaults.object(forKey: "polishEnabled") as? Bool ?? true
        let resolvedIntensity: PolishIntensity
        if let storedIntensity = defaults.string(forKey: "polishIntensity"),
           let intensity = PolishIntensity(rawValue: storedIntensity) {
            resolvedIntensity = intensity
        } else {
            resolvedIntensity = storedPolishEnabled ? .light : .off
        }
        polishEnabled = resolvedIntensity != .off
        polishIntensity = resolvedIntensity
        localeIdentifier = defaults.string(forKey: "localeIdentifier") ?? "en-US"
        if #available(macOS 13.0, *) {
            let serviceEnabled = SMAppService.mainApp.status == .enabled
            launchAtLogin = serviceEnabled || defaults.bool(forKey: "launchAtLogin")
        } else {
            launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        }
        vocabularyText = VocabularyStore.load().terms.joined(separator: ", ")
        liveInjectionEnabled = defaults.object(forKey: "liveInjectionEnabled") as? Bool ?? true
        soundFeedbackEnabled = defaults.object(forKey: "soundFeedbackEnabled") as? Bool ?? true
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(hotkeyMode.rawValue, forKey: "hotkeyMode")
        defaults.set(polishEnabled, forKey: "polishEnabled")
        defaults.set(polishIntensity.rawValue, forKey: "polishIntensity")
        defaults.set(localeIdentifier, forKey: "localeIdentifier")
        defaults.set(launchAtLogin, forKey: "launchAtLogin")
        defaults.set(liveInjectionEnabled, forKey: "liveInjectionEnabled")
        defaults.set(soundFeedbackEnabled, forKey: "soundFeedbackEnabled")
    }
}
