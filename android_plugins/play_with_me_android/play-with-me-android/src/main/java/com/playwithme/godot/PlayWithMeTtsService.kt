package com.playwithme.godot

import android.media.AudioFormat
import android.speech.tts.SynthesisCallback
import android.speech.tts.SynthesisRequest
import android.speech.tts.TextToSpeech
import android.speech.tts.TextToSpeechService
import android.speech.tts.Voice
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.nio.charset.StandardCharsets
import java.util.Locale

class PlayWithMeTtsService : TextToSpeechService() {
    private val lock = Any()
    private var runtimeHandle: Long = 0L
    private var generation = 0
    private var waveSequence = 0

    override fun onCreate() {
        super.onCreate()
        AndroidDebugLog.d(TAG, "service created registered=${PlayWithMeTtsRegistration.isServiceRegistered(this)}")
    }

    override fun onDestroy() {
        val handle = synchronized(lock) {
            generation += 1
            val current = runtimeHandle
            runtimeHandle = 0L
            current
        }
        if (handle != 0L) {
            KokoroNative.nativeDestroy(handle)
        }
        super.onDestroy()
    }

    override fun onIsLanguageAvailable(lang: String?, country: String?, variant: String?): Int {
        if (!isChineseLanguage(lang.orEmpty())) {
            return TextToSpeech.LANG_NOT_SUPPORTED
        }
        return if (country.isNullOrBlank()) {
            TextToSpeech.LANG_AVAILABLE
        } else {
            TextToSpeech.LANG_COUNTRY_AVAILABLE
        }
    }

    override fun onGetLanguage(): Array<String> {
        return arrayOf(Locale.SIMPLIFIED_CHINESE.language, Locale.SIMPLIFIED_CHINESE.country, "")
    }

    override fun onLoadLanguage(lang: String?, country: String?, variant: String?): Int {
        return onIsLanguageAvailable(lang, country, variant)
    }

    override fun onStop() {
        synchronized(lock) {
            generation += 1
        }
        AndroidDebugLog.d(TAG, "onStop generation=$generation")
    }

    override fun onGetVoices(): MutableList<Voice> {
        val reason = LocalTtsCatalog.availabilityReason(applicationContext)
        if (reason.isNotEmpty()) {
            AndroidDebugLog.d(TAG, "onGetVoices unavailable reason=$reason")
            return mutableListOf()
        }
        return PlayWithMeTtsRegistration.allVoices().toMutableList()
    }

    override fun onGetDefaultVoiceNameFor(lang: String?, country: String?, variant: String?): String {
        if (!isChineseLanguage(lang.orEmpty())) {
            return ""
        }
        return PlayWithMeTtsRegistration.voiceName(
            LocalTtsCatalog.definitions.first().id,
            KokoroTtsEngine.DEFAULT_CHINESE_VOICE_ID
        )
    }

    override fun onLoadVoice(voiceName: String?): Int {
        return onIsValidVoiceName(voiceName)
    }

    override fun onIsValidVoiceName(voiceName: String?): Int {
        return if (PlayWithMeTtsRegistration.parseVoiceName(voiceName.orEmpty()) != null) {
            TextToSpeech.SUCCESS
        } else {
            TextToSpeech.ERROR
        }
    }

    override fun onSynthesizeText(request: SynthesisRequest, callback: SynthesisCallback) {
        val startedGeneration = synchronized(lock) { generation }
        val rawVoiceName = request.voiceName.orEmpty()
        val voice = PlayWithMeTtsRegistration.parseVoiceName(rawVoiceName)
            ?: RegisteredLocalVoice(LocalTtsCatalog.definitions.first().id, KokoroTtsEngine.DEFAULT_CHINESE_VOICE_ID)
        val definition = LocalTtsCatalog.definition(voice.engineId)
        if (definition == null) {
            callback.error(TextToSpeech.ERROR_INVALID_REQUEST)
            return
        }
        val availabilityReason = LocalTtsCatalog.availabilityReason(applicationContext)
        if (availabilityReason.isNotEmpty()) {
            AndroidDebugLog.d(TAG, "synthesize unavailable engine=${definition.id} reason=$availabilityReason")
            callback.error(TextToSpeech.ERROR_NOT_INSTALLED_YET)
            return
        }
        val cleanText = (request.charSequenceText?.toString() ?: request.text.orEmpty()).trim()
        if (cleanText.isEmpty()) {
            callback.error(TextToSpeech.ERROR_INVALID_REQUEST)
            return
        }
        val nativeText = KokoroTtsEngine.sanitizeTextForChineseKokoro(cleanText)
        if (nativeText.isEmpty()) {
            callback.error(TextToSpeech.ERROR_INVALID_REQUEST)
            return
        }
        val speakerId = KokoroTtsEngine.speakerIdForVoiceId(voice.voiceId)
        if (speakerId < 0) {
            callback.error(TextToSpeech.ERROR_INVALID_REQUEST)
            return
        }
        val wave = nextWaveFile()
        try {
            val handle = ensureRuntime()
            val speed = KokoroTtsEngine.sherpaSpeedForUiSpeed(request.speechRate.toDouble() / 100.0)
            AndroidDebugLog.d(TAG, "synthesize start engine=${definition.id} voice=${voice.voiceId} chars=${nativeText.length} rate=${request.speechRate}")
            val result = KokoroNative.nativeGenerateToFile(
                handle,
                nativeText,
                speakerId,
                speed,
                0.2f,
                wave.absolutePath
            )
            if (result.size < 2 || result[0] <= 0 || result[1] <= 0) {
                throw IllegalStateException("本地 TTS 生成了空音频")
            }
            if (isStopped(startedGeneration)) {
                callback.error(TextToSpeech.ERROR_SERVICE)
                return
            }
            streamWave(wave, callback)
            AndroidDebugLog.d(TAG, "synthesize done engine=${definition.id} voice=${voice.voiceId} sampleRate=${result[0]} samples=${result[1]}")
        } catch (error: Exception) {
            AndroidDebugLog.d(TAG, "synthesize failed engine=${definition.id} voice=${voice.voiceId} error=${error.message}", error)
            callback.error(TextToSpeech.ERROR_SYNTHESIS)
        } finally {
            wave.delete()
        }
    }

    private fun ensureRuntime(): Long {
        synchronized(lock) {
            if (runtimeHandle != 0L) {
                return runtimeHandle
            }
        }
        KokoroNative.ensureAvailable()
        val modelDir = File(filesDir, ASSET_DIR)
        copyBundledModelIfNeeded(modelDir)
        val threads = Runtime.getRuntime().availableProcessors().coerceIn(2, 4)
        val handle = KokoroNative.nativeCreate(modelDir.absolutePath, threads)
        if (handle == 0L) {
            throw IllegalStateException("本地 TTS 服务初始化失败")
        }
        synchronized(lock) {
            if (runtimeHandle == 0L) {
                runtimeHandle = handle
            } else {
                KokoroNative.nativeDestroy(handle)
            }
            return runtimeHandle
        }
    }

    private fun copyBundledModelIfNeeded(modelDir: File) {
        val marker = File(modelDir, ".copy-complete")
        val model = File(modelDir, "model.int8.onnx")
        val voices = File(modelDir, "voices.bin")
        if (marker.exists() && model.exists() && voices.exists()) {
            return
        }
        if (!modelDir.exists() && !modelDir.mkdirs()) {
            throw IllegalStateException("无法创建 TTS 模型目录：${modelDir.absolutePath}")
        }
        copyAssetTree(ASSET_DIR, modelDir)
        restoreChunkedAsset(modelDir, "model.int8.onnx")
        restoreChunkedAsset(modelDir, "voices.bin")
        if (!model.exists() || !voices.exists()) {
            throw IllegalStateException("TTS 模型文件复制不完整")
        }
        marker.writeText(System.currentTimeMillis().toString())
    }

    private fun copyAssetTree(assetPath: String, target: File): Int {
        val children = assets.list(assetPath) ?: emptyArray()
        if (children.isEmpty()) {
            copyAssetFile(assetPath, target)
            return 1
        }
        if (!target.exists() && !target.mkdirs()) {
            throw IllegalStateException("无法创建目录：${target.absolutePath}")
        }
        var copied = 0
        for (child in children) {
            copied += copyAssetTree("$assetPath/$child", File(target, child))
        }
        return copied
    }

    private fun copyAssetFile(assetPath: String, target: File) {
        target.parentFile?.let { parent ->
            if (!parent.exists() && !parent.mkdirs()) {
                throw IllegalStateException("无法创建目录：${parent.absolutePath}")
            }
        }
        assets.open(assetPath).use { input ->
            FileOutputStream(target).use { output ->
                input.copyTo(output, bufferSize = 1024 * 1024)
            }
        }
    }

    private fun restoreChunkedAsset(modelDir: File, filename: String) {
        val output = File(modelDir, filename)
        val chunks = modelDir
            .listFiles { file -> file.isFile && file.name.startsWith("$filename.part") }
            .orEmpty()
            .sortedBy { it.name }
        if (output.exists()) {
            chunks.forEach { it.delete() }
            return
        }
        if (chunks.isEmpty()) {
            return
        }
        val temp = File(modelDir, "$filename.tmp")
        if (temp.exists()) {
            temp.delete()
        }
        FileOutputStream(temp).use { outputStream ->
            for (chunk in chunks) {
                FileInputStream(chunk).use { input ->
                    input.copyTo(outputStream, bufferSize = 1024 * 1024)
                }
            }
        }
        if (!temp.renameTo(output)) {
            throw IllegalStateException("无法恢复 TTS 分片文件：$filename")
        }
        chunks.forEach { it.delete() }
    }

    private fun nextWaveFile(): File {
        val dir = File(cacheDir, "tts_service_waves")
        if (!dir.exists() && !dir.mkdirs()) {
            throw IllegalStateException("无法创建 TTS 服务缓存目录：${dir.absolutePath}")
        }
        val sequence = synchronized(lock) {
            waveSequence += 1
            waveSequence
        }
        return File(dir, "tts_service_${System.currentTimeMillis()}_$sequence.wav")
    }

    private fun streamWave(file: File, callback: SynthesisCallback) {
        val header = readWaveHeader(file)
        val encoding = when (header.bitsPerSample) {
            16 -> AudioFormat.ENCODING_PCM_16BIT
            8 -> AudioFormat.ENCODING_PCM_8BIT
            else -> throw IllegalStateException("不支持的 WAV 位深：${header.bitsPerSample}")
        }
        if (callback.start(header.sampleRate, encoding, header.channels) != TextToSpeech.SUCCESS) {
            throw IllegalStateException("TTS 输出启动失败")
        }
        RandomAccessFile(file, "r").use { input ->
            input.seek(header.dataOffset)
            val maxBuffer = callback.maxBufferSize
            val bufferSize = if (maxBuffer > 0) minOf(maxBuffer, 16 * 1024).coerceAtLeast(1) else 8192
            val buffer = ByteArray(bufferSize)
            var remaining = header.dataSize
            while (remaining > 0 && !callback.hasFinished()) {
                val count = input.read(buffer, 0, minOf(buffer.size, remaining))
                if (count <= 0) {
                    break
                }
                if (callback.audioAvailable(buffer, 0, count) != TextToSpeech.SUCCESS) {
                    throw IllegalStateException("TTS 输出写入失败")
                }
                remaining -= count
            }
        }
        if (!callback.hasFinished()) {
            callback.done()
        }
    }

    private fun readWaveHeader(file: File): WaveHeader {
        RandomAccessFile(file, "r").use { input ->
            val header = ByteArray(12)
            input.readFully(header)
            if (ascii(header, 0, 4) != "RIFF" || ascii(header, 8, 4) != "WAVE") {
                throw IllegalStateException("TTS 输出不是 WAV 文件")
            }
            var sampleRate = 0
            var channels = 0
            var bitsPerSample = 0
            var dataOffset = 0L
            var dataSize = 0
            while (input.filePointer + 8 <= input.length()) {
                val chunk = ByteArray(8)
                input.readFully(chunk)
                val id = ascii(chunk, 0, 4)
                val size = littleInt(chunk, 4)
                val chunkStart = input.filePointer
                when (id) {
                    "fmt " -> {
                        val fmt = ByteArray(minOf(size, 16))
                        input.readFully(fmt)
                        if (fmt.size >= 16) {
                            channels = littleShort(fmt, 2)
                            sampleRate = littleInt(fmt, 4)
                            bitsPerSample = littleShort(fmt, 14)
                        }
                    }
                    "data" -> {
                        dataOffset = chunkStart
                        dataSize = size
                    }
                }
                val next = chunkStart + size + (size % 2)
                input.seek(next)
                if (dataOffset > 0L && sampleRate > 0) {
                    break
                }
            }
            if (sampleRate <= 0 || channels <= 0 || bitsPerSample <= 0 || dataOffset <= 0L || dataSize <= 0) {
                throw IllegalStateException("TTS WAV 头无效")
            }
            return WaveHeader(sampleRate, channels, bitsPerSample, dataOffset, dataSize)
        }
    }

    private fun isStopped(startedGeneration: Int): Boolean {
        return synchronized(lock) { generation != startedGeneration }
    }

    private fun isChineseLanguage(language: String): Boolean {
        val normalized = language.trim().lowercase(Locale.ROOT)
        return normalized == "zh" || normalized == "zho" || normalized == "chi" || normalized == "cmn"
    }

    private fun ascii(bytes: ByteArray, offset: Int, length: Int): String {
        return String(bytes, offset, length, StandardCharsets.US_ASCII)
    }

    private fun littleShort(bytes: ByteArray, offset: Int): Int {
        return (bytes[offset].toInt() and 0xff) or
            ((bytes[offset + 1].toInt() and 0xff) shl 8)
    }

    private fun littleInt(bytes: ByteArray, offset: Int): Int {
        return (bytes[offset].toInt() and 0xff) or
            ((bytes[offset + 1].toInt() and 0xff) shl 8) or
            ((bytes[offset + 2].toInt() and 0xff) shl 16) or
            ((bytes[offset + 3].toInt() and 0xff) shl 24)
    }

    private data class WaveHeader(
        val sampleRate: Int,
        val channels: Int,
        val bitsPerSample: Int,
        val dataOffset: Long,
        val dataSize: Int
    )

    companion object {
        private const val TAG = "PlayWithMeTtsService"
        private const val ASSET_DIR = "tts/kokoro-int8-multi-lang-v1_1"
    }
}
