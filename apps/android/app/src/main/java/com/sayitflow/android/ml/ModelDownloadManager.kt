package com.sayitflow.android.ml

import android.content.Context
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL

/**
 * Resumable Hugging Face model downloader for `desert-ant-labs/voz` (ONNX FP16)
 * and `suprwhspr/s1-mini` (GGUF Q4_K_M).
 */
class ModelDownloadManager(private val context: Context) {

    data class RemoteAsset(
        val fileName: String,
        val url: String,
        val expectedBytes: Long
    )

    data class ModelStatus(
        val isInstalled: Boolean = false,
        val isDownloading: Boolean = false,
        val downloadedBytes: Long = 0L,
        val totalBytes: Long = 0L,
        val currentFile: String = "",
        val errorMessage: String? = null
    ) {
        val progressFraction: Float
            get() = if (totalBytes > 0L) (downloadedBytes.toFloat() / totalBytes.toFloat()).coerceIn(0f, 1f) else 0f
    }

    companion object {
        private const val VOZ_BASE_URL = "https://huggingface.co/desert-ant-labs/voz/resolve/main/web"
        private const val S1_MINI_URL = "https://huggingface.co/superwhisper/s1-mini-GGUF/resolve/main/s1-mini-q4_k_m.gguf"

        val VOZ_ASSETS = listOf(
            RemoteAsset("meta.json", "$VOZ_BASE_URL/meta.json", 539L),
            RemoteAsset("vocab.json", "$VOZ_BASE_URL/vocab.json", 78_654L),
            RemoteAsset("embedding.f16", "$VOZ_BASE_URL/embedding.f16", 10_487_040L),
            RemoteAsset("encoder.onnx", "$VOZ_BASE_URL/encoder.onnx", 813_108L),
            RemoteAsset("decoder.onnx", "$VOZ_BASE_URL/decoder.onnx", 24_472_430L),
            RemoteAsset("encoder.onnx.data", "$VOZ_BASE_URL/encoder.onnx.data", 348_981_248L)
        )

        val VOZ_TOTAL_BYTES = VOZ_ASSETS.sumOf { it.expectedBytes } // ~384.8 MB
        const val S1_MINI_TOTAL_BYTES = 484_219_808L // ~461.8 MB
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var vozDownloadJob: Job? = null
    private var s1DownloadJob: Job? = null

    private val vozDir: File
        get() = File(context.filesDir, "models/desert-ant-voz")

    private val s1Dir: File
        get() = File(context.filesDir, "models/s1-mini")

    private val _vozStatus = MutableStateFlow(ModelStatus(totalBytes = VOZ_TOTAL_BYTES))
    val vozStatus: StateFlow<ModelStatus> = _vozStatus.asStateFlow()

    private val _s1Status = MutableStateFlow(ModelStatus(totalBytes = S1_MINI_TOTAL_BYTES))
    val s1Status: StateFlow<ModelStatus> = _s1Status.asStateFlow()

    init {
        // Clean up any partial/unneeded 461 MB GGUF file since Android uses the built-in 0 MB instant engine
        if (s1Dir.exists()) {
            try {
                s1Dir.deleteRecursively()
            } catch (_: Exception) {
            }
        }
        refreshStatus()
    }

    fun refreshStatus() {
        val vozInstalled = VOZ_ASSETS.all { asset ->
            val f = File(vozDir, asset.fileName)
            f.exists() && f.length() >= (asset.expectedBytes * 0.95).toLong()
        }
        val vozExistingBytes = VOZ_ASSETS.sumOf { asset ->
            val f = File(vozDir, asset.fileName)
            val part = File(vozDir, "${asset.fileName}.part")
            when {
                f.exists() -> f.length()
                part.exists() -> part.length()
                else -> 0L
            }
        }
        _vozStatus.value = _vozStatus.value.copy(
            isInstalled = vozInstalled,
            downloadedBytes = if (vozInstalled) VOZ_TOTAL_BYTES else vozExistingBytes,
            totalBytes = VOZ_TOTAL_BYTES
        )

        _s1Status.value = ModelStatus(
            isInstalled = true,
            isDownloading = false,
            downloadedBytes = 0L,
            totalBytes = 0L,
            currentFile = "Built-In Instant Core"
        )
    }

    fun startVozDownload() {
        if (_vozStatus.value.isDownloading) return
        vozDownloadJob = scope.launch {
            vozDir.mkdirs()
            _vozStatus.value = _vozStatus.value.copy(
                isDownloading = true,
                errorMessage = null
            )
            try {
                var cumulativeCompleted = 0L
                for (asset in VOZ_ASSETS) {
                    val targetFile = File(vozDir, asset.fileName)
                    if (targetFile.exists() && targetFile.length() == asset.expectedBytes) {
                        cumulativeCompleted += targetFile.length()
                        _vozStatus.value = _vozStatus.value.copy(
                            downloadedBytes = cumulativeCompleted,
                            currentFile = asset.fileName
                        )
                        continue
                    }
                    downloadFileResumable(
                        urlStr = asset.url,
                        targetFile = targetFile,
                        onProgress = { fileBytes ->
                            _vozStatus.value = _vozStatus.value.copy(
                                downloadedBytes = cumulativeCompleted + fileBytes,
                                currentFile = asset.fileName
                            )
                        }
                    )
                    cumulativeCompleted += targetFile.length()
                }
                _vozStatus.value = ModelStatus(
                    isInstalled = true,
                    isDownloading = false,
                    downloadedBytes = VOZ_TOTAL_BYTES,
                    totalBytes = VOZ_TOTAL_BYTES,
                    currentFile = "Ready"
                )
            } catch (e: Exception) {
                _vozStatus.value = _vozStatus.value.copy(
                    isDownloading = false,
                    errorMessage = e.localizedMessage ?: "Download interrupted"
                )
            }
        }
    }

    fun cancelVozDownload() {
        vozDownloadJob?.cancel()
        vozDownloadJob = null
        _vozStatus.value = _vozStatus.value.copy(isDownloading = false)
    }

    fun deleteVozModel() {
        cancelVozDownload()
        vozDir.deleteRecursively()
        refreshStatus()
    }

    fun startS1MiniDownload() {
        if (_s1Status.value.isDownloading) return
        s1DownloadJob = scope.launch {
            s1Dir.mkdirs()
            val targetFile = File(s1Dir, "s1-mini-q4_k_m.gguf")
            _s1Status.value = _s1Status.value.copy(
                isDownloading = true,
                errorMessage = null,
                currentFile = "s1-mini-q4_k_m.gguf"
            )
            try {
                downloadFileResumable(
                    urlStr = S1_MINI_URL,
                    targetFile = targetFile,
                    onProgress = { bytes ->
                        _s1Status.value = _s1Status.value.copy(
                            downloadedBytes = bytes,
                            totalBytes = maxOf(S1_MINI_TOTAL_BYTES, bytes)
                        )
                    }
                )
                _s1Status.value = ModelStatus(
                    isInstalled = true,
                    isDownloading = false,
                    downloadedBytes = targetFile.length(),
                    totalBytes = targetFile.length(),
                    currentFile = "Ready"
                )
            } catch (e: Exception) {
                _s1Status.value = _s1Status.value.copy(
                    isDownloading = false,
                    errorMessage = e.localizedMessage ?: "Download interrupted"
                )
            }
        }
    }

    fun cancelS1MiniDownload() {
        s1DownloadJob?.cancel()
        s1DownloadJob = null
        _s1Status.value = _s1Status.value.copy(isDownloading = false)
    }

    fun deleteS1MiniModel() {
        cancelS1MiniDownload()
        s1Dir.deleteRecursively()
        refreshStatus()
    }

    private suspend fun downloadFileResumable(
        urlStr: String,
        targetFile: File,
        onProgress: (Long) -> Unit
    ) = withContext(Dispatchers.IO) {
        val partFile = File(targetFile.parentFile, "${targetFile.name}.part")
        val existingBytes = if (partFile.exists()) partFile.length() else 0L

        val conn = (URL(urlStr).openConnection() as HttpURLConnection).apply {
            connectTimeout = 20_000
            readTimeout = 30_000
            instanceFollowRedirects = true
            setRequestProperty("User-Agent", "SayItFlow-Android/1.5.0")
            if (existingBytes > 0L) {
                setRequestProperty("Range", "bytes=$existingBytes-")
            }
        }

        conn.connect()
        val code = conn.responseCode
        val append = code == HttpURLConnection.HTTP_PARTIAL && existingBytes > 0L
        if (code !in 200..299) {
            conn.disconnect()
            throw IllegalStateException("HTTP $code while fetching ${targetFile.name}")
        }

        var totalWritten = if (append) existingBytes else 0L
        conn.inputStream.use { input ->
            FileOutputStream(partFile, append).use { output ->
                val buffer = ByteArray(64 * 1024)
                while (isActive) {
                    val read = input.read(buffer)
                    if (read == -1) break
                    output.write(buffer, 0, read)
                    totalWritten += read
                    onProgress(totalWritten)
                }
                output.flush()
            }
        }
        conn.disconnect()

        if (targetFile.exists()) targetFile.delete()
        if (!partFile.renameTo(targetFile)) {
            partFile.copyTo(targetFile, overwrite = true)
            partFile.delete()
        }
    }
}
