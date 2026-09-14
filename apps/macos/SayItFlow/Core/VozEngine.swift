import Foundation
import AVFoundation
#if canImport(CoreML)
import CoreML
#endif
import Voz

/// Coordinates Desert Ant's Voz on-device speech recognition on the Apple Neural Engine.
@MainActor
final class VozEngine: ObservableObject {
    static let shared = VozEngine()

    @Published private(set) var isDownloaded: Bool = false
    @Published private(set) var isDownloading: Bool = false
    @Published private(set) var downloadProgress: Double = 0
    @Published private(set) var isReady: Bool = false
    @Published private(set) var lastRealtimeFactor: Double = 0
    @Published private(set) var lastTranscriptionDuration: TimeInterval = 0
    @Published private(set) var lastError: String?

    private var vozInstance: Voz?
    private var isInitializing = false
    private var idleUnloadTask: Task<Void, Never>?
    private static let idleTimeoutSeconds: TimeInterval = 120

    public struct Language: Identifiable, Hashable, Sendable {
        public let code: String
        public let name: String
        public var id: String { code }
    }

    /// The 25 European languages supported by Desert Ant Voz (NVIDIA Parakeet TDT 0.6B v3).
    /// Note: Voz does NOT auto-detect spoken language; audio must be in a specified supported language.
    public static let supportedLanguageOptions: [Language] = [
        Language(code: "en", name: "English"),
        Language(code: "es", name: "Spanish (Español)"),
        Language(code: "fr", name: "French (Français)"),
        Language(code: "de", name: "German (Deutsch)"),
        Language(code: "it", name: "Italian (Italiano)"),
        Language(code: "pt", name: "Portuguese (Português)"),
        Language(code: "nl", name: "Dutch (Nederlands)"),
        Language(code: "pl", name: "Polish (Polski)"),
        Language(code: "ru", name: "Russian (Русский)"),
        Language(code: "uk", name: "Ukrainian (Українська)"),
        Language(code: "cs", name: "Czech (Čeština)"),
        Language(code: "sk", name: "Slovak (Slovenčina)"),
        Language(code: "bg", name: "Bulgarian (Български)"),
        Language(code: "hr", name: "Croatian (Hrvatski)"),
        Language(code: "sl", name: "Slovenian (Slovenščina)"),
        Language(code: "ro", name: "Romanian (Română)"),
        Language(code: "hu", name: "Hungarian (Magyar)"),
        Language(code: "el", name: "Greek (Ελληνικά)"),
        Language(code: "da", name: "Danish (Dansk)"),
        Language(code: "sv", name: "Swedish (Svenska)"),
        Language(code: "fi", name: "Finnish (Suomi)"),
        Language(code: "et", name: "Estonian (Eesti)"),
        Language(code: "lv", name: "Latvian (Latviešu)"),
        Language(code: "lt", name: "Lithuanian (Lietuvių)"),
        Language(code: "mt", name: "Maltese (Malti)")
    ]

    public static let supportedLanguages: [String] = supportedLanguageOptions.map(\.code)

    private init() {
        refreshStatus()
    }

    /// Refresh downloaded status from disk cache.
    func refreshStatus() {
        #if canImport(CoreML)
        isDownloaded = Voz.isDownloaded()
        #else
        isDownloaded = false
        #endif
        if isDownloaded && vozInstance != nil {
            isReady = true
        }
    }

    /// Pre-download the Voz Core ML model weights (467 MB) into the local cache.
    func downloadModel() async throws {
        guard !isDownloading else { return }
        isDownloading = true
        downloadProgress = 0.05
        lastError = nil

        do {
            #if canImport(CoreML)
            _ = try await Voz.download { [weak self] progress in
                Task { @MainActor in
                    self?.downloadProgress = max(progress.fraction, 0.05)
                }
            }
            #endif
            isDownloaded = true
            isDownloading = false
            downloadProgress = 1.0
            // Warm up immediately after download
            try await warmUp()
        } catch {
            isDownloading = false
            downloadProgress = 0
            lastError = error.localizedDescription
            throw error
        }
    }

    /// Warms up and compiles the Core ML Neural Engine graph for Voz.
    func warmUp() async throws {
        if !isDownloaded {
            refreshStatus()
            if !isDownloaded { return }
        }
        guard vozInstance == nil, !isInitializing else { return }
        isInitializing = true
        defer { isInitializing = false }

        do {
            #if canImport(CoreML)
            let voz = try await Voz()
            self.vozInstance = voz
            self.isReady = true
            AppLogger.dictation.notice("VozEngine: Voz model initialized successfully on Neural Engine.")
            #endif
        } catch {
            lastError = error.localizedDescription
            AppLogger.dictation.error("VozEngine warmUp failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Transcribe raw mono audio PCM samples at the given sample rate.
    func transcribe(samples: [Float], sampleRate: Double) async throws -> Voz.Result {
        guard !samples.isEmpty else {
            throw VozError.invalidAudio("Empty audio buffer")
        }

        #if canImport(CoreML)
        if vozInstance == nil {
            try await warmUp()
        }
        guard let voz = vozInstance else {
            throw VozError.invalidModel("Voz model is not initialized")
        }

        let result = try await voz.transcribe(samples: samples, sampleRate: sampleRate)
        self.lastRealtimeFactor = result.realtimeFactor
        self.lastTranscriptionDuration = result.processingTime
        resetIdleTimer()
        return result
        #else
        throw VozError.unsupportedPlatform
        #endif
    }

    // MARK: - Idle Unload

    private func resetIdleTimer() {
        idleUnloadTask?.cancel()
        idleUnloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.idleTimeoutSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.unloadModel()
        }
    }

    /// Explicitly release Voz model memory and ANE residency after idle timeout.
    func unloadModel() {
        guard vozInstance != nil else { return }
        vozInstance = nil
        isReady = false
        idleUnloadTask?.cancel()
        idleUnloadTask = nil
        AppLogger.dictation.notice("VozEngine: model unloaded after idle timeout")
    }
}
