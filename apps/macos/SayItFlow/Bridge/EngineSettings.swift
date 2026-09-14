import Foundation

@MainActor
final class EngineSettings: ObservableObject {
    static let shared = EngineSettings()

    @Published var selectedLanguage: String {
        didSet { UserDefaults.standard.set(selectedLanguage, forKey: Keys.selectedLanguage) }
    }

    private enum Keys {
        static let selectedLanguage = "sayitflow.voz.language"
    }

    private init() {
        let defaults = UserDefaults.standard
        selectedLanguage = defaults.string(forKey: Keys.selectedLanguage) ?? "en"
    }

    var sttModelName: String { "Desert Ant Voz" }
    var sttModelArchitecture: String { "Parakeet TDT 0.6B v3 (Apple Neural Engine)" }
    var sttModelSpeed: String { "290x real-time (10 min audio in ~2s)" }
}
