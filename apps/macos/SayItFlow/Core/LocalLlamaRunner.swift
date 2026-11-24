import Foundation
import LlamaSwift

enum LocalLlamaError: Error, LocalizedError {
    case modelNotFound(String)
    case modelLoadFailed(String)
    case contextInitFailed
    case tokenizationFailed
    case promptTooLong(Int, Int)
    case decodeFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let path): "Model file not found at \(path)"
        case .modelLoadFailed(let path): "Failed to load GGUF model at \(path)"
        case .contextInitFailed: "Failed to initialize llama.cpp inference context"
        case .tokenizationFailed: "Failed to tokenize prompt"
        case .promptTooLong(let count, let max): "Prompt too long (\(count) tokens, max \(max))"
        case .decodeFailed(let code): "llama_decode failed with code \(code)"
        }
    }
}

struct LocalLlamaCompletion: Sendable, Equatable {
    let text: String
    let hitTokenLimit: Bool
}

/// Self-contained, in-process GGUF inference runner powered by embedded `llama.cpp` (Metal GPU).
///
/// Runs directly inside `SayItFlow.app` with zero external binaries, zero localhost servers,
/// and deterministic unload support to reclaim RAM after idle periods.
actor LocalLlamaRunner {
    static let shared = LocalLlamaRunner()

    private static let backendSetupOnce: Void = {
        llama_log_set({ _, _, _ in }, nil)
        llama_backend_init()
    }()

    private var loadedModelPath: String?
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var sampler: UnsafeMutablePointer<llama_sampler>?

    private let contextSize: UInt32 = 2048
    private let batchSize: UInt32 = 512

    var isLoaded: Bool {
        model != nil && context != nil
    }

    var currentModelPath: String? {
        loadedModelPath
    }

    /// Loads a GGUF model into Metal GPU memory, reusing it if already loaded.
    func load(modelPath: String) throws {
        _ = Self.backendSetupOnce

        if loadedModelPath == modelPath, model != nil, context != nil {
            return
        }

        unload()

        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw LocalLlamaError.modelNotFound(modelPath)
        }

        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = 99

        guard let loadedModel = llama_model_load_from_file(modelPath, modelParams) else {
            throw LocalLlamaError.modelLoadFailed(modelPath)
        }

        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = contextSize
        ctxParams.n_batch = batchSize
        let cpuCount = ProcessInfo.processInfo.activeProcessorCount
        let threads = Int32(min(max(2, cpuCount - 2), 6))
        ctxParams.n_threads = threads
        ctxParams.n_threads_batch = threads

        guard let loadedContext = llama_init_from_model(loadedModel, ctxParams) else {
            llama_model_free(loadedModel)
            throw LocalLlamaError.contextInitFailed
        }

        let greedySampler = llama_sampler_init_greedy()

        self.model = loadedModel
        self.context = loadedContext
        self.sampler = greedySampler
        self.loadedModelPath = modelPath
    }

    /// Releases model weights and KV cache immediately so app RAM drops back to idle baseline.
    func unload() {
        if let sampler {
            llama_sampler_free(sampler)
            self.sampler = nil
        }
        if let context {
            llama_free(context)
            self.context = nil
        }
        if let model {
            llama_model_free(model)
            self.model = nil
        }
        loadedModelPath = nil
    }

    /// Runs greedy completion for `prompt`, stopping at EOG or any string in `stopSequences`.
    func complete(
        modelPath: String,
        prompt: String,
        maxTokens: Int,
        stopSequences: [String] = ["<|im_end|>", "<|endoftext|>"]
    ) throws -> LocalLlamaCompletion {
        try load(modelPath: modelPath)

        guard let model, let ctx = context, let sampler else {
            throw LocalLlamaError.contextInitFailed
        }
        guard let vocab = llama_model_get_vocab(model) else {
            throw LocalLlamaError.contextInitFailed
        }

        // Clear KV cache so every dictation starts from a clean slate
        if let mem = llama_get_memory(ctx) {
            llama_memory_clear(mem, true)
        }

        let tokens = try tokenize(prompt, vocab: vocab)
        let maxPromptTokens = Int(contextSize) - 32
        guard tokens.count <= maxPromptTokens else {
            throw LocalLlamaError.promptTooLong(tokens.count, maxPromptTokens)
        }

        // Evaluate prompt in batch-sized chunks
        var offset = 0
        while offset < tokens.count {
            let end = min(offset + Int(batchSize), tokens.count)
            var chunk = Array(tokens[offset..<end])
            let status = chunk.withUnsafeMutableBufferPointer { buf -> Int32 in
                let batch = llama_batch_get_one(buf.baseAddress, Int32(buf.count))
                return llama_decode(ctx, batch)
            }
            guard status == 0 else {
                throw LocalLlamaError.decodeFailed(status)
            }
            offset = end
        }

        var outputBytes: [UInt8] = []
        outputBytes.reserveCapacity(maxTokens * 4)
        var pieceBuf = [CChar](repeating: 0, count: 64)
        let limit = max(1, min(maxTokens, Int(contextSize) - tokens.count - 4))
        var hitLimit = true

        let maxStopBytes = stopSequences.map(\.utf8.count).max() ?? 0
        for _ in 0..<limit {
            var nextToken = llama_sampler_sample(sampler, ctx, -1)

            if llama_vocab_is_eog(vocab, nextToken) {
                hitLimit = false
                break
            }

            var written = llama_token_to_piece(vocab, nextToken, &pieceBuf, Int32(pieceBuf.count), 0, false)
            if written < 0 {
                pieceBuf = [CChar](repeating: 0, count: Int(-written) + 1)
                written = llama_token_to_piece(vocab, nextToken, &pieceBuf, Int32(pieceBuf.count), 0, false)
            }
            if written > 0 {
                for i in 0..<Int(written) {
                    outputBytes.append(UInt8(bitPattern: pieceBuf[i]))
                }
            }

            if maxStopBytes > 0 {
                let tailCount = min(outputBytes.count, maxStopBytes + 4)
                let tailText = String(decoding: outputBytes.suffix(tailCount), as: UTF8.self)
                if let matchedStop = stopSequences.first(where: { tailText.hasSuffix($0) }) {
                    let fullText = String(decoding: outputBytes, as: UTF8.self)
                    let trimmed = String(fullText.dropLast(matchedStop.count))
                    return LocalLlamaCompletion(text: trimmed, hitTokenLimit: false)
                }
            }

            let stepStatus = withUnsafeMutablePointer(to: &nextToken) { ptr -> Int32 in
                let batch = llama_batch_get_one(ptr, 1)
                return llama_decode(ctx, batch)
            }
            guard stepStatus == 0 else {
                throw LocalLlamaError.decodeFailed(stepStatus)
            }
        }

        let finalText = String(decoding: outputBytes, as: UTF8.self)
        return LocalLlamaCompletion(text: finalText, hitTokenLimit: hitLimit)
    }

    private func tokenize(_ text: String, vocab: OpaquePointer) throws -> [llama_token] {
        let utf8 = Array(text.utf8)
        let textLen = Int32(utf8.count)

        let needed: Int32 = utf8.withUnsafeBytes { rawBuf in
            let ptr = rawBuf.bindMemory(to: CChar.self).baseAddress
            return -llama_tokenize(vocab, ptr, textLen, nil, 0, false, true)
        }
        guard needed > 0 else {
            throw LocalLlamaError.tokenizationFailed
        }

        var tokens = [llama_token](repeating: 0, count: Int(needed))
        let actual: Int32 = utf8.withUnsafeBytes { rawBuf in
            let ptr = rawBuf.bindMemory(to: CChar.self).baseAddress
            return llama_tokenize(vocab, ptr, textLen, &tokens, needed, false, true)
        }
        guard actual >= 0 else {
            throw LocalLlamaError.tokenizationFailed
        }
        if Int(actual) < tokens.count {
            tokens.removeSubrange(Int(actual)..<tokens.count)
        }
        return tokens
    }
}
