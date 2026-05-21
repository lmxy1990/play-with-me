package com.playwithme.godot

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.math.ceil

internal class KokoroTtsEngine(
    private val context: Context,
    private val listener: Listener
) {
    interface Listener {
        fun onReady()
        fun onVoicesUpdated(payload: String)
        fun onSpeechStarted(utteranceId: Int)
        fun onSpeechProgress(utteranceId: Int, ratio: Double)
        fun onSpeechDone(utteranceId: Int)
        fun onSpeechFailed(utteranceId: Int, error: String)
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private val assetDir = "tts/kokoro-int8-multi-lang-v1_1"
    private val waveDir = File(context.cacheDir, "tts_waves")
    private val lock = Any()

    private var runtimeHandle: Long = 0L
    private var mediaPlayer: MediaPlayer? = null
    private var playbackGeneration = 0
    private var waveSequence = 0
    private var currentPlaybackLatch: CountDownLatch? = null

    fun isAvailable(): Boolean = KokoroNative.isAvailable

    fun unavailableReason(): String = KokoroNative.unavailableReason

    fun listVoicesJson(): String = kokoroVoicesJson()

    fun warmUp(): Boolean {
        AndroidDebugLog.d(TAG, "warmUp requested nativeAvailable=${KokoroNative.isAvailable} reason=${KokoroNative.unavailableReason}")
        if (!KokoroNative.isAvailable) {
            listener.onSpeechFailed(0, "本地 Kokoro 库不可用：${KokoroNative.unavailableReason}")
            return false
        }
        executor.execute {
            try {
                AndroidDebugLog.d(TAG, "warmUp job start")
                ensureRuntime()
                AndroidDebugLog.d(TAG, "warmUp runtime ready handle=$runtimeHandle")
                listener.onReady()
                listener.onVoicesUpdated(kokoroVoicesJson())
                val warmFile = nextWaveFile("warm")
                val result = KokoroNative.nativeGenerateToFile(
                    runtimeHandle,
                    "好",
                    speakerIdFor(DEFAULT_CHINESE_VOICE_ID),
                    1.0f,
                    0.2f,
                    warmFile.absolutePath
                )
                if (result.size >= 2) {
                    warmFile.delete()
                }
                AndroidDebugLog.d(TAG, "warmUp generate result=${result.joinToString()} fileDeleted=${!warmFile.exists()}")
            } catch (error: Exception) {
                AndroidDebugLog.d(TAG, "warmUp failed: ${error.message}", error)
                listener.onSpeechFailed(0, error.message ?: "本地 Kokoro 预热失败")
            }
        }
        return true
    }

    fun speak(
        text: String,
        voiceId: String,
        speed: Double,
        volume: Double,
        utteranceId: Int,
        interrupt: Boolean
    ): Boolean {
        val cleanText = text.trim()
        AndroidDebugLog.d(TAG, "speak requested utterance=$utteranceId voice=$voiceId textChars=${cleanText.length} speed=$speed volume=$volume interrupt=$interrupt")
        if (cleanText.isEmpty()) {
            listener.onSpeechFailed(utteranceId, "播报文本为空")
            return false
        }
        val nativeText = sanitizeForChineseKokoro(cleanText)
        if (nativeText.isEmpty()) {
            listener.onSpeechFailed(utteranceId, "播报文本不包含可播放内容")
            return false
        }
        if (nativeText != cleanText) {
            AndroidDebugLog.d(TAG, "speak sanitized text utterance=$utteranceId originalChars=${cleanText.length} nativeChars=${nativeText.length}")
        }
        if (!KokoroNative.isAvailable) {
            AndroidDebugLog.d(TAG, "speak failed: native unavailable ${KokoroNative.unavailableReason}")
            listener.onSpeechFailed(utteranceId, "本地 Kokoro 库不可用：${KokoroNative.unavailableReason}")
            return false
        }
        val sid = speakerIdFor(voiceId)
        if (sid < 0) {
            AndroidDebugLog.d(TAG, "speak failed: invalid voice $voiceId")
            listener.onSpeechFailed(utteranceId, "Kokoro 音色不存在：$voiceId")
            return false
        }

        val generation = synchronized(lock) {
            if (interrupt) {
                playbackGeneration += 1
                stopMediaPlayerLocked()
            }
            playbackGeneration
        }

        executor.execute {
            runSpeakJob(
                text = nativeText,
                sid = sid,
                speed = sherpaSpeedFor(speed),
                volume = volume.toFloat().coerceIn(0.0f, 1.0f),
                utteranceId = utteranceId,
                generation = generation
            )
        }
        return true
    }

    fun stop(): Boolean {
        synchronized(lock) {
            playbackGeneration += 1
            stopMediaPlayerLocked()
            currentPlaybackLatch?.countDown()
            currentPlaybackLatch = null
        }
        return true
    }

    fun release() {
        stop()
        executor.execute {
            synchronized(lock) {
                val handle = runtimeHandle
                runtimeHandle = 0L
                if (handle != 0L) {
                    KokoroNative.nativeDestroy(handle)
                }
            }
        }
        executor.shutdown()
    }

    private fun runSpeakJob(
        text: String,
        sid: Int,
        speed: Float,
        volume: Float,
        utteranceId: Int,
        generation: Int
    ) {
        try {
            ensureRuntime()
            val chunks = splitTtsText(text)
            AndroidDebugLog.d(TAG, "runSpeakJob start utterance=$utteranceId sid=$sid chunks=${chunks.size} speed=$speed")
            var totalChars = 0
            for (chunk in chunks) {
                totalChars += chunk.length
            }
            totalChars = totalChars.coerceAtLeast(1)
            var completedChars = 0
            var started = false
            for (chunk in chunks) {
                if (isCanceled(generation)) {
                    AndroidDebugLog.d(TAG, "runSpeakJob canceled before chunk utterance=$utteranceId")
                    return
                }
                val wave = nextWaveFile("tts")
                AndroidDebugLog.d(TAG, "generate chunk utterance=$utteranceId chars=${chunk.length} file=${wave.name}")
                val result = KokoroNative.nativeGenerateToFile(
                    runtimeHandle,
                    chunk,
                    sid,
                    speed,
                    0.2f,
                    wave.absolutePath
                )
                if (result.size < 2 || result[0] <= 0 || result[1] <= 0) {
                    throw IllegalStateException("本地 Kokoro 生成了空音频")
                }
                AndroidDebugLog.d(TAG, "generate done utterance=$utteranceId sampleRate=${result[0]} sampleCount=${result[1]}")
                if (isCanceled(generation)) {
                    wave.delete()
                    AndroidDebugLog.d(TAG, "runSpeakJob canceled after generate utterance=$utteranceId")
                    return
                }
                playWaveBlocking(
                    file = wave,
                    sampleRate = result[0],
                    sampleCount = result[1],
                    volume = volume,
                    utteranceId = utteranceId,
                    generation = generation,
                    emitStart = !started,
                    baseRatio = completedChars.toDouble() / totalChars.toDouble(),
                    ratioSpan = chunk.length.toDouble() / totalChars.toDouble()
                )
                started = true
                completedChars += chunk.length
                if (!isCanceled(generation)) {
                    listener.onSpeechProgress(utteranceId, (completedChars.toDouble() / totalChars.toDouble()).coerceIn(0.0, 1.0))
                }
                wave.delete()
            }
            if (!isCanceled(generation)) {
                AndroidDebugLog.d(TAG, "runSpeakJob done utterance=$utteranceId")
                listener.onSpeechProgress(utteranceId, 1.0)
                listener.onSpeechDone(utteranceId)
            }
        } catch (error: Exception) {
            if (!isCanceled(generation)) {
                AndroidDebugLog.d(TAG, "runSpeakJob failed utterance=$utteranceId error=${error.message}", error)
                listener.onSpeechFailed(utteranceId, error.message ?: "本地 Kokoro 播放失败")
            }
        }
    }

    private fun ensureRuntime() {
        synchronized(lock) {
            if (runtimeHandle != 0L) {
                AndroidDebugLog.d(TAG, "ensureRuntime reuse handle=$runtimeHandle")
                return
            }
        }
        KokoroNative.ensureAvailable()
        val modelDir = File(context.filesDir, assetDir)
        AndroidDebugLog.d(TAG, "ensureRuntime copy/check modelDir=${modelDir.absolutePath}")
        copyBundledModelIfNeeded(modelDir)
        if (!waveDir.exists() && !waveDir.mkdirs()) {
            throw IllegalStateException("无法创建 TTS 缓存目录：${waveDir.absolutePath}")
        }
        val threads = Runtime.getRuntime().availableProcessors().coerceIn(2, 4)
        AndroidDebugLog.d(TAG, "ensureRuntime nativeCreate threads=$threads")
        val handle = KokoroNative.nativeCreate(modelDir.absolutePath, threads)
        if (handle == 0L) {
            throw IllegalStateException("本地 Kokoro 初始化失败")
        }
        synchronized(lock) {
            if (runtimeHandle == 0L) {
                runtimeHandle = handle
                AndroidDebugLog.d(TAG, "ensureRuntime created handle=$handle")
            } else {
                KokoroNative.nativeDestroy(handle)
                AndroidDebugLog.d(TAG, "ensureRuntime destroyed duplicate handle=$handle")
            }
        }
    }

    private fun copyBundledModelIfNeeded(modelDir: File) {
        val marker = File(modelDir, ".copy-complete")
        val model = File(modelDir, "model.int8.onnx")
        val voices = File(modelDir, "voices.bin")
        if (marker.exists() && model.exists() && voices.exists()) {
            AndroidDebugLog.d(TAG, "copyBundledModelIfNeeded skip marker exists modelBytes=${model.length()} voicesBytes=${voices.length()}")
            return
        }
        if (!modelDir.exists() && !modelDir.mkdirs()) {
            throw IllegalStateException("无法创建 Kokoro 模型目录：${modelDir.absolutePath}")
        }
        AndroidDebugLog.d(TAG, "copyBundledModelIfNeeded start assetDir=$assetDir")
        val copied = copyAssetTree(assetDir, modelDir)
        AndroidDebugLog.d(TAG, "copyBundledModelIfNeeded copiedFiles=$copied")
        restoreChunkedAsset(modelDir, "model.int8.onnx")
        restoreChunkedAsset(modelDir, "voices.bin")
        if (!model.exists() || !voices.exists()) {
            throw IllegalStateException("Kokoro 模型文件复制不完整")
        }
        AndroidDebugLog.d(TAG, "copyBundledModelIfNeeded complete modelBytes=${model.length()} voicesBytes=${voices.length()}")
        marker.writeText(System.currentTimeMillis().toString())
    }

    private fun copyAssetTree(assetPath: String, target: File): Int {
        val children = context.assets.list(assetPath) ?: emptyArray()
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
        context.assets.open(assetPath).use { input ->
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
            AndroidDebugLog.d(TAG, "restoreChunkedAsset skip output exists filename=$filename bytes=${output.length()}")
            return
        }
        if (chunks.isEmpty()) {
            AndroidDebugLog.d(TAG, "restoreChunkedAsset no chunks filename=$filename")
            return
        }
        AndroidDebugLog.d(TAG, "restoreChunkedAsset start filename=$filename chunks=${chunks.size}")
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
            throw IllegalStateException("无法恢复 Kokoro 分片文件：$filename")
        }
        chunks.forEach { it.delete() }
        AndroidDebugLog.d(TAG, "restoreChunkedAsset done filename=$filename bytes=${output.length()}")
    }

    private fun nextWaveFile(prefix: String): File {
        val sequence = synchronized(lock) {
            waveSequence += 1
            waveSequence
        }
        return File(waveDir, "${prefix}_${System.currentTimeMillis()}_$sequence.wav")
    }

    private fun playWaveBlocking(
        file: File,
        sampleRate: Int,
        sampleCount: Int,
        volume: Float,
        utteranceId: Int,
        generation: Int,
        emitStart: Boolean,
        baseRatio: Double,
        ratioSpan: Double
    ) {
        val latch = CountDownLatch(1)
        val durationMs = ceil(sampleCount.toDouble() / sampleRate.toDouble() * 1000.0).toLong()
        synchronized(lock) {
            currentPlaybackLatch = latch
        }
        mainHandler.post {
            if (isCanceled(generation)) {
                latch.countDown()
                return@post
            }
            try {
                synchronized(lock) {
                    stopMediaPlayerLocked()
                }
                val player = MediaPlayer().apply {
                    setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_GAME)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                            .build()
                    )
                    setVolume(volume, volume)
                    setDataSource(file.absolutePath)
                    setOnCompletionListener {
                        synchronized(lock) {
                            if (mediaPlayer === it) {
                                mediaPlayer = null
                            }
                        }
                        it.release()
                        latch.countDown()
                    }
                    setOnErrorListener { mp, _, _ ->
                        synchronized(lock) {
                            if (mediaPlayer === mp) {
                                mediaPlayer = null
                            }
                        }
                        mp.release()
                        latch.countDown()
                        true
                    }
                    prepare()
                }
                synchronized(lock) {
                    mediaPlayer = player
                }
                if (emitStart) {
                    listener.onSpeechStarted(utteranceId)
                    listener.onSpeechProgress(utteranceId, 0.0)
                }
                player.start()
                schedulePlaybackProgress(player, utteranceId, generation, baseRatio, ratioSpan)
                AndroidDebugLog.d(TAG, "playWave start utterance=$utteranceId file=${file.name} durationMs=$durationMs")
            } catch (error: Exception) {
                AndroidDebugLog.d(TAG, "playWave failed utterance=$utteranceId error=${error.message}", error)
                listener.onSpeechFailed(utteranceId, error.message ?: "本地 Kokoro 播放失败")
                latch.countDown()
            }
        }
        latch.await(durationMs + 3000L, TimeUnit.MILLISECONDS)
        synchronized(lock) {
            if (currentPlaybackLatch === latch) {
                currentPlaybackLatch = null
            }
        }
    }

    private fun schedulePlaybackProgress(
        player: MediaPlayer,
        utteranceId: Int,
        generation: Int,
        baseRatio: Double,
        ratioSpan: Double
    ) {
        mainHandler.postDelayed(
            object : Runnable {
                override fun run() {
                    if (isCanceled(generation)) {
                        return
                    }
                    val currentPlayer = synchronized(lock) { mediaPlayer }
                    if (currentPlayer !== player) {
                        return
                    }
                    val duration = try {
                        player.duration.coerceAtLeast(1)
                    } catch (_: IllegalStateException) {
                        return
                    }
                    val position = try {
                        player.currentPosition.coerceIn(0, duration)
                    } catch (_: IllegalStateException) {
                        return
                    }
                    val playbackRatio = position.toDouble() / duration.toDouble()
                    listener.onSpeechProgress(
                        utteranceId,
                        (baseRatio + ratioSpan * playbackRatio).coerceIn(0.0, 0.99)
                    )
                    val playing = try {
                        player.isPlaying
                    } catch (_: IllegalStateException) {
                        false
                    }
                    if (playing) {
                        mainHandler.postDelayed(this, 120L)
                    }
                }
            },
            120L
        )
    }

    private fun stopMediaPlayerLocked() {
        val player = mediaPlayer ?: return
        mediaPlayer = null
        try {
            player.stop()
        } catch (_: IllegalStateException) {
        }
        player.release()
    }

    private fun isCanceled(generation: Int): Boolean {
        return synchronized(lock) { playbackGeneration != generation }
    }

    private fun speakerIdFor(voiceId: String): Int = speakerIdForVoiceId(voiceId)

    private fun sherpaSpeedFor(uiSpeed: Double): Float = sherpaSpeedForUiSpeed(uiSpeed)

    private fun sanitizeForChineseKokoro(text: String): String = sanitizeTextForChineseKokoro(text)

    private fun splitTtsText(text: String): List<String> {
        val normalized = text.trim().replace(Regex("\\s+"), " ")
        if (normalized.length <= 18) {
            return listOf(normalized)
        }
        val chunks = mutableListOf<String>()
        val buffer = StringBuilder()
        for (char in normalized) {
            buffer.append(char)
            val canBreak = (isBreakChar(char) && buffer.length >= 8) || buffer.length >= 18
            if (canBreak) {
                chunks.add(buffer.toString().trim())
                buffer.clear()
            }
        }
        val rest = buffer.toString().trim()
        if (rest.isNotEmpty()) {
            if (chunks.isNotEmpty() && rest.length < 6) {
                val last = chunks.removeAt(chunks.lastIndex)
                chunks.add(last + rest)
            } else {
                chunks.add(rest)
            }
        }
        return chunks.filter { it.isNotEmpty() }
    }

    private fun isBreakChar(char: Char): Boolean {
        return char == '。' ||
            char == '！' ||
            char == '？' ||
            char == '；' ||
            char == '，' ||
            char == '、' ||
            char == '.' ||
            char == '!' ||
            char == '?' ||
            char == ';' ||
            char == ','
    }

    companion object {
        private const val TAG = "KokoroTtsEngine"
        const val DEFAULT_CHINESE_VOICE_ID = "zf_001"
        private val CHINESE_DIGITS = charArrayOf('零', '一', '二', '三', '四', '五', '六', '七', '八', '九')

        fun speakerIdForVoiceId(voiceId: String): Int {
            val trimmed = voiceId.trim()
            if (trimmed.isEmpty()) {
                return KOKORO_ALL_SPEAKER_NAMES.indexOf(DEFAULT_CHINESE_VOICE_ID)
            }
            val directIndex = KOKORO_ALL_SPEAKER_NAMES.indexOf(trimmed)
            if (directIndex >= 0 && isChineseVoiceName(trimmed)) {
                return directIndex
            }
            val prefix = "kokoro::"
            if (trimmed.startsWith(prefix)) {
                val index = trimmed.removePrefix(prefix).toIntOrNull() ?: return -1
                if (index in KOKORO_ALL_SPEAKER_NAMES.indices && isChineseVoiceName(KOKORO_ALL_SPEAKER_NAMES[index])) {
                    return index
                }
                if (index in KOKORO_CHINESE_SPEAKER_NAMES.indices) {
                    return KOKORO_ALL_SPEAKER_NAMES.indexOf(KOKORO_CHINESE_SPEAKER_NAMES[index])
                }
            }
            return -1
        }

        fun sherpaSpeedForUiSpeed(uiSpeed: Double): Float {
            return (uiSpeed.coerceIn(0.1, 1.0) * 2.0).coerceIn(0.5, 2.0).toFloat()
        }

        fun sanitizeTextForChineseKokoro(text: String): String {
            val builder = StringBuilder()
            val source = text.trim()
            var index = 0
            var lastSpace = false
            while (index < source.length) {
                val digit = normalizedDigit(source[index])
                if (digit != null) {
                    val integerDigits = StringBuilder()
                    while (index < source.length) {
                        val value = normalizedDigit(source[index]) ?: break
                        integerDigits.append(value)
                        index += 1
                    }

                    val decimalDigits = StringBuilder()
                    if (index < source.length &&
                        isDecimalPoint(source[index]) &&
                        index + 1 < source.length &&
                        normalizedDigit(source[index + 1]) != null
                    ) {
                        index += 1
                        while (index < source.length) {
                            val value = normalizedDigit(source[index]) ?: break
                            decimalDigits.append(value)
                            index += 1
                        }
                    }

                    val nextChar = if (index < source.length) source[index] else null
                    builder.append(chineseNumberText(integerDigits.toString(), nextChar))
                    if (decimalDigits.isNotEmpty()) {
                        builder.append('点')
                        builder.append(chineseDigitText(decimalDigits.toString()))
                    }
                    lastSpace = false
                    continue
                }

                normalizedKokoroChar(source[index])?.let {
                    lastSpace = appendKokoroChar(builder, it, lastSpace)
                }
                index += 1
            }
            return cleanupKokoroText(builder.toString())
        }

        fun kokoroVoicesJson(): String {
            val voices = JSONArray()
            KOKORO_CHINESE_SPEAKER_NAMES.forEach { name ->
                val female = name.length > 1 && name[1] == 'f'
                voices.put(
                    JSONObject()
                        .put("id", name)
                        .put("name", "Kokoro ${if (female) "女声" else "男声"} $name")
                        .put("engine", "local_kokoro")
                        .put("language", "zh-CN")
                        .put("locale", "zh-CN")
                        .put("gender", if (female) "女声" else "男声")
                        .put("networkRequired", false)
                )
            }
            return voices.toString()
        }

        private fun isChineseVoiceName(name: String): Boolean {
            return name.startsWith("zf_") || name.startsWith("zm_")
        }

        private fun normalizedKokoroChar(char: Char): Char? {
            if (char in '\u4E00'..'\u9FFF' || char in '\u3400'..'\u4DBF' || char in '\uF900'..'\uFAFF') {
                return char
            }
            if (char in 'A'..'Z' || char in 'a'..'z') {
                return char
            }
            if (char.isWhitespace()) {
                return ' '
            }
            return when (char) {
                '，', '。', '！', '？', '；', '：', '、' -> char
                ',' -> '，'
                '.' -> '。'
                '!' -> '！'
                '?' -> '？'
                ';' -> '；'
                ':' -> '：'
                '(', '（' -> '（'
                ')', '）' -> '）'
                '[', '【' -> '【'
                ']', '】' -> '】'
                '\'', '-', '_', '/', '+', '#', '&' -> char
                else -> null
            }
        }

        private fun appendKokoroChar(builder: StringBuilder, char: Char, lastSpace: Boolean): Boolean {
            if (char == ' ') {
                if (builder.isNotEmpty() && !lastSpace) {
                    builder.append(char)
                    return true
                }
                return lastSpace
            }
            if (isClosingKokoroPunctuation(char) && builder.isNotEmpty() && builder[builder.length - 1] == ' ') {
                builder.setLength(builder.length - 1)
            }
            builder.append(char)
            return false
        }

        private fun isClosingKokoroPunctuation(char: Char): Boolean {
            return char == '，' ||
                char == '。' ||
                char == '！' ||
                char == '？' ||
                char == '；' ||
                char == '：' ||
                char == '、' ||
                char == '）' ||
                char == '】'
        }

        private fun cleanupKokoroText(text: String): String {
            var result = text.trim().replace(Regex("\\s+"), " ")
            listOf("，", "。", "！", "？", "；", "：", "、", "）", "】").forEach { punctuation ->
                result = result.replace(" $punctuation", punctuation)
            }
            listOf("（", "【").forEach { punctuation ->
                result = result.replace("$punctuation ", punctuation)
            }
            return result.trim()
        }

        private fun normalizedDigit(char: Char): Int? {
            return when (char) {
                in '0'..'9' -> char - '0'
                in '\uFF10'..'\uFF19' -> char - '\uFF10'
                else -> null
            }
        }

        private fun isDecimalPoint(char: Char): Boolean {
            return char == '.' || char == '\uFF0E'
        }

        private fun chineseNumberText(digits: String, nextChar: Char?): String {
            if (digits.isEmpty()) {
                return ""
            }
            if (digits.length == 1) {
                return CHINESE_DIGITS[digits[0] - '0'].toString()
            }
            val value = digits.toIntOrNull()
            if (value == null || digits.length >= 4 || digits.first() == '0' || nextChar == '年') {
                return chineseDigitText(digits)
            }
            return chineseIntegerText(value)
        }

        private fun chineseDigitText(digits: String): String {
            val builder = StringBuilder()
            for (char in digits) {
                val value = char - '0'
                if (value in CHINESE_DIGITS.indices) {
                    builder.append(CHINESE_DIGITS[value])
                }
            }
            return builder.toString()
        }

        private fun chineseIntegerText(value: Int): String {
            val number = value.coerceIn(0, 9999)
            if (number == 0) {
                return CHINESE_DIGITS[0].toString()
            }
            val units = intArrayOf(1000, 100, 10, 1)
            val names = arrayOf("千", "百", "十", "")
            val builder = StringBuilder()
            var pendingZero = false
            for (i in units.indices) {
                val unit = units[i]
                val digit = number / unit % 10
                if (digit == 0) {
                    if (builder.isNotEmpty()) {
                        pendingZero = true
                    }
                    continue
                }
                if (pendingZero) {
                    builder.append(CHINESE_DIGITS[0])
                    pendingZero = false
                }
                if (!(digit == 1 && unit == 10 && builder.isEmpty())) {
                    builder.append(CHINESE_DIGITS[digit])
                }
                builder.append(names[i])
            }
            return builder.toString()
        }

        private val KOKORO_CHINESE_SPEAKER_NAMES: List<String>
            get() = KOKORO_ALL_SPEAKER_NAMES.filter(::isChineseVoiceName)

        private val KOKORO_ALL_SPEAKER_NAMES = listOf(
            "af_maple", "af_sol", "bf_vale", "zf_001", "zf_002", "zf_003", "zf_004", "zf_005", "zf_006", "zf_007",
            "zf_008", "zf_017", "zf_018", "zf_019", "zf_021", "zf_022", "zf_023", "zf_024", "zf_026", "zf_027",
            "zf_028", "zf_032", "zf_036", "zf_038", "zf_039", "zf_040", "zf_042", "zf_043", "zf_044", "zf_046",
            "zf_047", "zf_048", "zf_049", "zf_051", "zf_059", "zf_060", "zf_067", "zf_070", "zf_071", "zf_072",
            "zf_073", "zf_074", "zf_075", "zf_076", "zf_077", "zf_078", "zf_079", "zf_083", "zf_084", "zf_085",
            "zf_086", "zf_087", "zf_088", "zf_090", "zf_092", "zf_093", "zf_094", "zf_099", "zm_009", "zm_010",
            "zm_011", "zm_012", "zm_013", "zm_014", "zm_015", "zm_016", "zm_020", "zm_025", "zm_029", "zm_030",
            "zm_031", "zm_033", "zm_034", "zm_035", "zm_037", "zm_041", "zm_045", "zm_050", "zm_052", "zm_053",
            "zm_054", "zm_055", "zm_056", "zm_057", "zm_058", "zm_061", "zm_062", "zm_063", "zm_064", "zm_065",
            "zm_066", "zm_068", "zm_069", "zm_080", "zm_081", "zm_082", "zm_089", "zm_091", "zm_095", "zm_096",
            "zm_097", "zm_098", "zm_100"
        )
    }
}
