package com.playwithme.godot

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
import android.util.Base64
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.SecureRandom
import java.security.Signature
import java.security.spec.PKCS8EncodedKeySpec
import java.security.spec.X509EncodedKeySpec
import java.util.Locale

class PlayWithMeAndroid(godot: Godot) : GodotPlugin(godot) {
    private var pendingScanAfterPermission = false
    private var systemTts: TextToSpeech? = null
    private var systemTtsReady = false
    private var systemTtsInitializing = false
    private var kokoroTts: KokoroTtsEngine? = null
    private val localTtsEngines = mutableMapOf<String, LocalAndroidTtsEngine>()
    private var memoryDatabase: MemoryDatabase? = null
    private val pendingSystemTtsRequests = mutableListOf<SystemTtsRequest>()
    private val activeSystemTtsTexts = mutableMapOf<Int, String>()

    private data class SystemTtsRequest(
        val text: String,
        val voiceId: String,
        val speed: Double,
        val pitch: Double,
        val volume: Double,
        val utteranceId: Int,
        val interrupt: Boolean
    )

    override fun getPluginName(): String = "PlayWithMeAndroid"

    override fun getPluginMethods(): List<String> = listOf(
        "start_qr_scan",
        "scan_join_qr",
        "startScan",
        "scanQr",
        "tts_warm_up",
        "warmUpTts",
        "tts_list_voices",
        "listSystemTtsVoices",
        "tts_kokoro_available",
        "tts_kokoro_warm_up",
        "kokoro_tts_warm_up",
        "warmUpKokoroTts",
        "tts_list_kokoro_voices",
        "listKokoroTtsVoices",
        "tts_external_available",
        "tts_external_warm_up",
        "tts_list_external_voices",
        "tts_speak_external",
        "tts_debug_available",
        "tts_debug_snapshot",
        "tts_speak",
        "speakTts",
        "tts_speak_kokoro",
        "speakKokoroTts",
        "tts_stop",
        "stopTts",
        "memory_available",
        "memoryAvailable",
        "memory_load_state",
        "memoryLoadState",
        "memory_save_state",
        "memorySaveState",
        "memory_append",
        "memoryAppend",
        "memory_compact",
        "memoryCompact",
        "memory_save_long_term",
        "memorySaveLongTerm",
        "memory_delete_scope",
        "memoryDeleteScope",
        "memory_discard_session",
        "memoryDiscardSession",
        "memory_list_scopes",
        "memoryListScopes",
        "memory_delete_owner",
        "memoryDeleteOwner",
        "memory_list_index_names",
        "memoryListIndexNames",
        "memory_index_status",
        "memoryIndexStatus",
        "memory_native_rebuild_indexes",
        "memoryNativeRebuildIndexes",
        "memory_native_vector_search",
        "memoryNativeVectorSearch",
        "model_config_available",
        "modelConfigAvailable",
        "model_config_list",
        "modelConfigList",
        "model_config_save",
        "modelConfigSave",
        "model_config_delete",
        "modelConfigDelete",
        "voice_config_available",
        "voiceConfigAvailable",
        "voice_config_list",
        "voiceConfigList",
        "voice_config_save",
        "voiceConfigSave",
        "voice_config_delete",
        "voiceConfigDelete",
        "identity_generate",
        "generateDeviceIdentity",
        "identity_sign",
        "signDeviceChallenge",
        "identity_verify",
        "verifyDeviceAuth",
    )

    override fun getPluginSignals(): Set<SignalInfo> = setOf(
        SignalInfo("qr_scan_succeeded", String::class.java),
        SignalInfo("qr_scan_failed", String::class.java),
        SignalInfo("qr_scan_cancelled"),
        SignalInfo("scan_succeeded", String::class.java),
        SignalInfo("scan_failed", String::class.java),
        SignalInfo("scan_cancelled"),
        SignalInfo("tts_ready"),
        SignalInfo("kokoro_tts_ready"),
        SignalInfo("external_tts_ready", String::class.java),
        SignalInfo("tts_voices_updated", String::class.java),
        SignalInfo("tts_speech_started", Int::class.javaObjectType),
        SignalInfo("tts_speech_progress", Int::class.javaObjectType, Double::class.javaObjectType),
        SignalInfo("tts_speech_done", Int::class.javaObjectType),
        SignalInfo("tts_speech_failed", Int::class.javaObjectType, String::class.java),
    )

    @UsedByGodot
    fun start_qr_scan() {
        scanQr()
    }

    @UsedByGodot
    fun scan_join_qr() {
        scanQr()
    }

    @UsedByGodot
    fun startScan() {
        scanQr()
    }

    @UsedByGodot
    fun scanQr() {
        val activity = activity
        AndroidDebugLog.d(TAG, "scanQr requested activity=${activity != null} permissionPending=$pendingScanAfterPermission")
        if (activity == null) {
            fail("Android Activity 不可用")
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            activity.checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED
        ) {
            pendingScanAfterPermission = true
            AndroidDebugLog.d(TAG, "scanQr requesting CAMERA permission request=$CAMERA_PERMISSION_REQUEST")
            activity.requestPermissions(arrayOf(Manifest.permission.CAMERA), CAMERA_PERMISSION_REQUEST)
            return
        }
        activity.runOnUiThread {
            AndroidDebugLog.d(TAG, "scanQr launching QrScannerActivity request=$QR_SCAN_REQUEST")
            val intent = Intent(activity, QrScannerActivity::class.java)
            activity.startActivityForResult(intent, QR_SCAN_REQUEST)
        }
    }

    @UsedByGodot
    fun tts_warm_up(): Boolean {
        val result = ensureSystemTts()
        AndroidDebugLog.d(TAG, "tts_warm_up result=$result ready=$systemTtsReady initializing=$systemTtsInitializing")
        return result
    }

    @UsedByGodot
    fun warmUpTts(): Boolean {
        return tts_warm_up()
    }

    @UsedByGodot
    fun tts_list_voices(): String {
        AndroidDebugLog.d(TAG, "tts_list_voices requested ready=$systemTtsReady initializing=$systemTtsInitializing")
        ensureSystemTts()
        if (!systemTtsReady) {
            AndroidDebugLog.d(TAG, "tts_list_voices returning empty: system TTS not ready")
            return "[]"
        }
        val payload = systemTtsVoicesJson()
        AndroidDebugLog.d(TAG, "tts_list_voices count=${systemTts?.voices?.size ?: 0} payloadChars=${payload.length}")
        return payload
    }

    @UsedByGodot
    fun listSystemTtsVoices(): String {
        return tts_list_voices()
    }

    @UsedByGodot
    fun tts_kokoro_available(): Boolean {
        val engine = ensureKokoroTts()
        val available = engine?.isAvailable() == true
        AndroidDebugLog.d(TAG, "tts_kokoro_available result=$available reason=${engine?.unavailableReason().orEmpty()}")
        return available
    }

    @UsedByGodot
    fun tts_kokoro_warm_up(): Boolean {
        AndroidDebugLog.d(TAG, "tts_kokoro_warm_up requested")
        val engine = ensureKokoroTts()
        if (engine == null) {
            emitTtsSignal("tts_speech_failed", 0, "Android Activity 不可用")
            AndroidDebugLog.d(TAG, "tts_kokoro_warm_up failed: activity unavailable")
            return false
        }
        val result = engine.warmUp()
        AndroidDebugLog.d(TAG, "tts_kokoro_warm_up result=$result")
        return result
    }

    @UsedByGodot
    fun kokoro_tts_warm_up(): Boolean {
        return tts_kokoro_warm_up()
    }

    @UsedByGodot
    fun warmUpKokoroTts(): Boolean {
        return tts_kokoro_warm_up()
    }

    @UsedByGodot
    fun tts_list_kokoro_voices(): String {
        val payload = KokoroTtsEngine.kokoroVoicesJson()
        AndroidDebugLog.d(TAG, "tts_list_kokoro_voices payloadChars=${payload.length}")
        return payload
    }

    @UsedByGodot
    fun listKokoroTtsVoices(): String {
        return tts_list_kokoro_voices()
    }

    @UsedByGodot
    fun tts_debug_available(): Boolean {
        return isDebuggableApp()
    }

    @UsedByGodot
    fun tts_debug_snapshot(): String {
        if (!isDebuggableApp()) {
            return JSONObject()
                .put("ok", false)
                .put("debuggable", false)
                .put("error", "TTS debug API only works in debug builds")
                .toString()
        }
        return LocalTtsCatalog
            .debugSnapshot(activity?.applicationContext)
            .put("debuggable", true)
            .put("api", "plugin")
            .put("systemTtsReady", systemTtsReady)
            .put("systemTtsInitializing", systemTtsInitializing)
            .toString()
    }

    @UsedByGodot
    fun tts_external_available(engineId: String): Boolean {
        val definition = localTtsDefinition(engineId)
        val available = definition != null && LocalTtsCatalog.isAvailable(activity?.applicationContext)
        AndroidDebugLog.d(TAG, "tts_external_available engine=$engineId available=$available mode=in_app_inference")
        return available
    }

    @UsedByGodot
    fun tts_external_warm_up(engineId: String): Boolean {
        val engine = ensureLocalTtsEngine(engineId)
        if (engine == null) {
            emitTtsSignal("tts_speech_failed", 0, "本地 TTS 引擎不可用：$engineId")
            AndroidDebugLog.d(TAG, "tts_external_warm_up failed engine=$engineId")
            return false
        }
        val result = engine.warmUp()
        AndroidDebugLog.d(TAG, "tts_external_warm_up engine=$engineId result=$result")
        return result
    }

    @UsedByGodot
    fun tts_list_external_voices(engineId: String): String {
        val engine = ensureLocalTtsEngine(engineId)
        if (engine == null) {
            AndroidDebugLog.d(TAG, "tts_list_external_voices missing engine=$engineId")
            return "[]"
        }
        val payload = engine.voicesJson()
        AndroidDebugLog.d(TAG, "tts_list_external_voices engine=$engineId payloadChars=${payload.length}")
        return payload
    }

    @UsedByGodot
    fun tts_speak_external(
        engineId: String,
        text: String,
        voiceId: String,
        speed: Double,
        pitch: Double,
        volume: Double,
        utteranceId: Int,
        interrupt: Boolean
    ): Boolean {
        AndroidDebugLog.d(TAG, "tts_speak_external requested engine=$engineId utterance=$utteranceId voice=$voiceId textChars=${text.trim().length}")
        val engine = ensureLocalTtsEngine(engineId)
        if (engine == null) {
            emitTtsSignal("tts_speech_failed", utteranceId, "本地 TTS 引擎不可用：$engineId")
            return false
        }
        return engine.speak(text, voiceId, speed, pitch, volume, utteranceId, interrupt)
    }

    @UsedByGodot
    fun tts_speak(
        text: String,
        voiceId: String,
        speed: Double,
        pitch: Double,
        volume: Double,
        utteranceId: Int,
        interrupt: Boolean
    ): Boolean {
        val cleanText = text.trim()
        val normalizedVoiceId = voiceId.trim()
        AndroidDebugLog.d(TAG, "tts_speak requested utterance=$utteranceId voice=${normalizedVoiceId.ifBlank { "<default>" }} textChars=${cleanText.length} speed=$speed pitch=$pitch volume=$volume interrupt=$interrupt ready=$systemTtsReady initializing=$systemTtsInitializing")
        if (cleanText.isEmpty()) {
            emitTtsSignal("tts_speech_failed", utteranceId, "播报文本为空")
            return false
        }
        if (!ensureSystemTts()) {
            emitTtsSignal("tts_speech_failed", utteranceId, "Android 系统 TTS 未就绪")
            return false
        }
        val request = SystemTtsRequest(
            text = cleanText,
            voiceId = normalizedVoiceId,
            speed = speed,
            pitch = pitch,
            volume = volume,
            utteranceId = utteranceId,
            interrupt = interrupt
        )
        val tts = systemTts
        if (!systemTtsReady || tts == null) {
            if (systemTtsInitializing) {
                synchronized(pendingSystemTtsRequests) {
                    if (interrupt) {
                        pendingSystemTtsRequests.clear()
                    }
                    pendingSystemTtsRequests.add(request)
                }
                AndroidDebugLog.d(TAG, "tts_speak queued until system TTS ready utterance=$utteranceId pending=${pendingSystemTtsRequests.size}")
                return true
            }
            emitTtsSignal("tts_speech_failed", utteranceId, "Android 系统 TTS 不可用")
            return false
        }
        return speakSystemTtsNow(tts, request)
    }

    @UsedByGodot
    fun speakTts(
        text: String,
        voiceId: String,
        speed: Double,
        pitch: Double,
        volume: Double,
        utteranceId: Int,
        interrupt: Boolean
    ): Boolean {
        return tts_speak(text, voiceId, speed, pitch, volume, utteranceId, interrupt)
    }

    @UsedByGodot
    fun tts_speak_kokoro(
        text: String,
        voiceId: String,
        speed: Double,
        pitch: Double,
        volume: Double,
        utteranceId: Int,
        interrupt: Boolean
    ): Boolean {
        AndroidDebugLog.d(TAG, "tts_speak_kokoro requested utterance=$utteranceId voice=$voiceId textChars=${text.trim().length} speed=$speed volume=$volume interrupt=$interrupt")
        val engine = ensureKokoroTts()
        if (engine == null) {
            emitTtsSignal("tts_speech_failed", utteranceId, "Android Activity 不可用")
            AndroidDebugLog.d(TAG, "tts_speak_kokoro failed: activity unavailable")
            return false
        }
        val result = engine.speak(text, voiceId, speed, volume, utteranceId, interrupt)
        AndroidDebugLog.d(TAG, "tts_speak_kokoro result=$result utterance=$utteranceId")
        return result
    }

    @UsedByGodot
    fun speakKokoroTts(
        text: String,
        voiceId: String,
        speed: Double,
        pitch: Double,
        volume: Double,
        utteranceId: Int,
        interrupt: Boolean
    ): Boolean {
        return tts_speak_kokoro(text, voiceId, speed, pitch, volume, utteranceId, interrupt)
    }

    private fun speakSystemTtsNow(tts: TextToSpeech, request: SystemTtsRequest): Boolean {
        val voice = if (request.voiceId.isEmpty()) {
            null
        } else {
            tts.voices?.firstOrNull { voiceIdFor(it) == request.voiceId }
        }
        if (request.voiceId.isNotEmpty() && voice == null) {
            AndroidDebugLog.d(TAG, "tts_speak failed: missing system voice ${request.voiceId} available=${tts.voices?.size ?: 0}")
            emitTtsSignal("tts_speech_failed", request.utteranceId, "系统音色不存在：${request.voiceId}")
            return false
        }
        val speakResult = try {
            if (voice != null) {
                tts.voice = voice
                AndroidDebugLog.d(TAG, "tts_speak apply voice utterance=${request.utteranceId} voice=${request.voiceId}")
            } else {
                val languageResult = tts.setLanguage(Locale.SIMPLIFIED_CHINESE)
                AndroidDebugLog.d(TAG, "tts_speak use default voice utterance=${request.utteranceId} languageResult=$languageResult")
            }
            tts.setSpeechRate(request.speed.toFloat().coerceIn(0.1f, 2.0f))
            tts.setPitch(request.pitch.toFloat().coerceIn(0.5f, 2.0f))
            val params = Bundle().apply {
                putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, request.volume.toFloat().coerceIn(0.0f, 1.0f))
            }
            val queueMode = if (request.interrupt) TextToSpeech.QUEUE_FLUSH else TextToSpeech.QUEUE_ADD
            synchronized(activeSystemTtsTexts) {
                if (request.interrupt) {
                    activeSystemTtsTexts.clear()
                }
                activeSystemTtsTexts[request.utteranceId] = request.text
            }
            tts.speak(request.text, queueMode, params, request.utteranceId.toString())
        } catch (error: Exception) {
            synchronized(activeSystemTtsTexts) {
                activeSystemTtsTexts.remove(request.utteranceId)
            }
            AndroidDebugLog.d(TAG, "tts_speak failed utterance=${request.utteranceId} error=${error.message}", error)
            emitTtsSignal("tts_speech_failed", request.utteranceId, error.message ?: "Android 系统 TTS 播放失败")
            return false
        }
        if (speakResult != TextToSpeech.SUCCESS) {
            synchronized(activeSystemTtsTexts) {
                activeSystemTtsTexts.remove(request.utteranceId)
            }
            AndroidDebugLog.d(TAG, "tts_speak failed: speakResult=$speakResult utterance=${request.utteranceId}")
            emitTtsSignal("tts_speech_failed", request.utteranceId, "Android 系统 TTS 播放失败")
            return false
        }
        AndroidDebugLog.d(TAG, "tts_speak started utterance=${request.utteranceId} voice=${request.voiceId.ifBlank { "<default>" }}")
        return true
    }

    private fun flushPendingSystemTtsRequests(tts: TextToSpeech) {
        val requests = synchronized(pendingSystemTtsRequests) {
            val copy = pendingSystemTtsRequests.toList()
            pendingSystemTtsRequests.clear()
            copy
        }
        if (requests.isEmpty()) {
            return
        }
        AndroidDebugLog.d(TAG, "flushPendingSystemTtsRequests count=${requests.size}")
        for (request in requests) {
            speakSystemTtsNow(tts, request)
        }
    }

    private fun failPendingSystemTtsRequests(message: String) {
        val requests = synchronized(pendingSystemTtsRequests) {
            val copy = pendingSystemTtsRequests.toList()
            pendingSystemTtsRequests.clear()
            copy
        }
        if (requests.isEmpty()) {
            return
        }
        AndroidDebugLog.d(TAG, "failPendingSystemTtsRequests count=${requests.size} message=$message")
        for (request in requests) {
            emitTtsSignal("tts_speech_failed", request.utteranceId, message)
        }
    }

    @UsedByGodot
    fun tts_stop(): Boolean {
        synchronized(pendingSystemTtsRequests) {
            pendingSystemTtsRequests.clear()
        }
        synchronized(activeSystemTtsTexts) {
            activeSystemTtsTexts.clear()
        }
        systemTts?.stop()
        localTtsEngines.values.forEach { it.stop() }
        kokoroTts?.stop()
        return true
    }

    @UsedByGodot
    fun stopTts(): Boolean {
        return tts_stop()
    }

    @UsedByGodot
    fun memory_available(): Boolean {
        return try {
            ensureMemoryDatabase()?.readableDatabase != null
        } catch (_: Exception) {
            false
        }
    }

    @UsedByGodot
    fun memoryAvailable(): Boolean {
        return memory_available()
    }

    @UsedByGodot
    fun memory_load_state(scopeJson: String): String {
        return memoryResult { database ->
            database.loadState(scopeJson)
        }
    }

    @UsedByGodot
    fun memoryLoadState(scopeJson: String): String {
        return memory_load_state(scopeJson)
    }

    @UsedByGodot
    fun memory_save_state(scopeJson: String, stateJson: String): String {
        return memoryResult { database ->
            database.saveState(scopeJson, stateJson)
        }
    }

    @UsedByGodot
    fun memorySaveState(scopeJson: String, stateJson: String): String {
        return memory_save_state(scopeJson, stateJson)
    }

    @UsedByGodot
    fun memory_append(scopeJson: String, entryJson: String): String {
        return memoryResult { database ->
            database.append(scopeJson, entryJson)
        }
    }

    @UsedByGodot
    fun memoryAppend(scopeJson: String, entryJson: String): String {
        return memory_append(scopeJson, entryJson)
    }

    @UsedByGodot
    fun memory_compact(scopeJson: String, requestJson: String): String {
        return memoryResult { database ->
            database.compact(scopeJson, requestJson)
        }
    }

    @UsedByGodot
    fun memoryCompact(scopeJson: String, requestJson: String): String {
        return memory_compact(scopeJson, requestJson)
    }

    @UsedByGodot
    fun memory_save_long_term(scopeJson: String, summary: String, userApproved: Boolean): String {
        return memoryResult { database ->
            database.saveLongTerm(scopeJson, summary, userApproved)
        }
    }

    @UsedByGodot
    fun memorySaveLongTerm(scopeJson: String, summary: String, userApproved: Boolean): String {
        return memory_save_long_term(scopeJson, summary, userApproved)
    }

    @UsedByGodot
    fun memory_delete_scope(scopeJson: String): String {
        return memoryResult { database ->
            database.deleteScope(scopeJson)
        }
    }

    @UsedByGodot
    fun memoryDeleteScope(scopeJson: String): String {
        return memory_delete_scope(scopeJson)
    }

    @UsedByGodot
    fun memory_discard_session(scopeJson: String): String {
        return memoryResult { database ->
            database.discardSession(scopeJson)
        }
    }

    @UsedByGodot
    fun memoryDiscardSession(scopeJson: String): String {
        return memory_discard_session(scopeJson)
    }

    @UsedByGodot
    fun memory_list_scopes(ownerId: String, gameId: String, namespace: String): String {
        return memoryResult { database ->
            database.listScopes(ownerId, gameId, namespace)
        }
    }

    @UsedByGodot
    fun memoryListScopes(ownerId: String, gameId: String, namespace: String): String {
        return memory_list_scopes(ownerId, gameId, namespace)
    }

    @UsedByGodot
    fun memory_delete_owner(ownerId: String, gameId: String): String {
        return memoryResult { database ->
            database.deleteOwnerMemory(ownerId, gameId)
        }
    }

    @UsedByGodot
    fun memoryDeleteOwner(ownerId: String, gameId: String): String {
        return memory_delete_owner(ownerId, gameId)
    }

    @UsedByGodot
    fun memory_list_index_names(): String {
        return memoryResult { database ->
            database.listIndexNames()
        }
    }

    @UsedByGodot
    fun memoryListIndexNames(): String {
        return memory_list_index_names()
    }

    @UsedByGodot
    fun memory_index_status(): String {
        return memoryResult { database ->
            database.indexStatus()
        }
    }

    @UsedByGodot
    fun memoryIndexStatus(): String {
        return memory_index_status()
    }

    @UsedByGodot
    fun memory_native_rebuild_indexes(scopeJson: String, stateJson: String): String {
        return memoryResult { database ->
            database.nativeRebuildIndexes(scopeJson, stateJson)
        }
    }

    @UsedByGodot
    fun memoryNativeRebuildIndexes(scopeJson: String, stateJson: String): String {
        return memory_native_rebuild_indexes(scopeJson, stateJson)
    }

    @UsedByGodot
    fun memory_native_vector_search(scopeJson: String, queryVectorJson: String, requestJson: String): String {
        return memoryResult { database ->
            database.nativeVectorSearch(scopeJson, queryVectorJson, requestJson)
        }
    }

    @UsedByGodot
    fun memoryNativeVectorSearch(scopeJson: String, queryVectorJson: String, requestJson: String): String {
        return memory_native_vector_search(scopeJson, queryVectorJson, requestJson)
    }

    @UsedByGodot
    fun model_config_available(): Boolean {
        val available = memory_available()
        AndroidDebugLog.d(TAG, "model_config_available=$available")
        return available
    }

    @UsedByGodot
    fun modelConfigAvailable(): Boolean {
        return model_config_available()
    }

    @UsedByGodot
    fun model_config_list(): String {
        AndroidDebugLog.d(TAG, "model_config_list requested")
        return memoryResult { database ->
            database.listModelConfigs()
        }
    }

    @UsedByGodot
    fun modelConfigList(): String {
        return model_config_list()
    }

    @UsedByGodot
    fun model_config_save(configJson: String): String {
        AndroidDebugLog.d(TAG, "model_config_save requested chars=${configJson.length}")
        val result = memoryResult { database ->
            database.saveModelConfig(configJson)
        }
        AndroidDebugLog.d(TAG, "model_config_save result chars=${result.length} payload=$result")
        return result
    }

    @UsedByGodot
    fun modelConfigSave(configJson: String): String {
        return model_config_save(configJson)
    }

    @UsedByGodot
    fun model_config_delete(id: Int): String {
        AndroidDebugLog.d(TAG, "model_config_delete requested id=$id")
        return memoryResult { database ->
            database.deleteModelConfig(id)
        }
    }

    @UsedByGodot
    fun modelConfigDelete(id: Int): String {
        return model_config_delete(id)
    }

    @UsedByGodot
    fun voice_config_available(): Boolean {
        val available = memory_available()
        AndroidDebugLog.d(TAG, "voice_config_available=$available")
        return available
    }

    @UsedByGodot
    fun voiceConfigAvailable(): Boolean {
        return voice_config_available()
    }

    @UsedByGodot
    fun voice_config_list(): String {
        AndroidDebugLog.d(TAG, "voice_config_list requested")
        return memoryResult { database ->
            database.listVoiceConfigs()
        }
    }

    @UsedByGodot
    fun voiceConfigList(): String {
        return voice_config_list()
    }

    @UsedByGodot
    fun voice_config_save(configJson: String): String {
        AndroidDebugLog.d(TAG, "voice_config_save requested chars=${configJson.length}")
        return memoryResult { database ->
            database.saveVoiceConfig(configJson)
        }
    }

    @UsedByGodot
    fun voiceConfigSave(configJson: String): String {
        return voice_config_save(configJson)
    }

    @UsedByGodot
    fun voice_config_delete(id: Int): String {
        AndroidDebugLog.d(TAG, "voice_config_delete requested id=$id")
        return memoryResult { database ->
            database.deleteVoiceConfig(id)
        }
    }

    @UsedByGodot
    fun voiceConfigDelete(id: Int): String {
        return voice_config_delete(id)
    }

    @UsedByGodot
    fun identity_generate(deviceId: String): String {
        return try {
            val generator = KeyPairGenerator.getInstance(DEVICE_SIGNATURE_ALGORITHM)
            val keyPair = generator.generateKeyPair()
            JSONObject()
                .put("ok", true)
                .put("deviceId", deviceId.trim().ifBlank { "device_${identityNonce(18)}" })
                .put("publicKey", base64Url(rawEd25519PublicKey(keyPair.public.encoded)))
                .put("privateKey", base64Url(keyPair.private.encoded))
                .put("algorithm", "ed25519")
                .toString()
        } catch (error: Exception) {
            identityError(error.message ?: "Android Ed25519 身份生成失败")
        }
    }

    @UsedByGodot
    fun generateDeviceIdentity(deviceId: String): String {
        return identity_generate(deviceId)
    }

    @UsedByGodot
    fun identity_sign(identityJson: String, challenge: String): String {
        return try {
            val identity = JSONObject(identityJson.ifBlank { "{}" })
            val deviceId = identity.optString("deviceId").trim()
            val publicKey = identity.optString("publicKey").trim()
            val privateKeyText = identity.optString("privateKey").trim()
            if (deviceId.isBlank() || publicKey.isBlank() || privateKeyText.isBlank()) {
                return identityError("设备身份不完整")
            }
            val keyFactory = KeyFactory.getInstance(DEVICE_SIGNATURE_ALGORITHM)
            val privateKey = keyFactory.generatePrivate(
                PKCS8EncodedKeySpec(base64UrlDecode(privateKeyText))
            )
            val signer = Signature.getInstance(DEVICE_SIGNATURE_ALGORITHM)
            signer.initSign(privateKey)
            signer.update(deviceAuthBytes(challenge, deviceId, publicKey))
            JSONObject()
                .put("ok", true)
                .put("deviceId", deviceId)
                .put("publicKey", publicKey)
                .put("signature", base64Url(signer.sign()))
                .put("algorithm", "ed25519")
                .toString()
        } catch (error: Exception) {
            identityError(error.message ?: "Android Ed25519 签名失败")
        }
    }

    @UsedByGodot
    fun signDeviceChallenge(identityJson: String, challenge: String): String {
        return identity_sign(identityJson, challenge)
    }

    @UsedByGodot
    fun identity_verify(authJson: String, challenge: String): Boolean {
        return try {
            val auth = JSONObject(authJson.ifBlank { "{}" })
            val deviceId = auth.optString("deviceId").trim()
            val publicKeyText = auth.optString("publicKey").trim()
            val signatureText = auth.optString("signature").trim()
            if (deviceId.isBlank() || publicKeyText.isBlank() || signatureText.isBlank()) {
                return false
            }
            val keyFactory = KeyFactory.getInstance(DEVICE_SIGNATURE_ALGORITHM)
            val publicKey = keyFactory.generatePublic(
                X509EncodedKeySpec(ed25519PublicKeySpec(base64UrlDecode(publicKeyText)))
            )
            val verifier = Signature.getInstance(DEVICE_SIGNATURE_ALGORITHM)
            verifier.initVerify(publicKey)
            verifier.update(deviceAuthBytes(challenge, deviceId, publicKeyText))
            verifier.verify(base64UrlDecode(signatureText))
        } catch (_: Exception) {
            false
        }
    }

    @UsedByGodot
    fun verifyDeviceAuth(authJson: String, challenge: String): Boolean {
        return identity_verify(authJson, challenge)
    }

    override fun onGodotMainLoopStarted() {
        super.onGodotMainLoopStarted()
        AndroidDebugLog.d(TAG, "onGodotMainLoopStarted pluginMethods=${getPluginMethods().size}")
        try {
            ensureMemoryDatabase()?.writableDatabase
        } catch (_: Exception) {
        }
    }

    override fun onMainDestroy() {
        systemTts?.stop()
        systemTts?.shutdown()
        systemTts = null
        systemTtsReady = false
        systemTtsInitializing = false
        localTtsEngines.values.forEach { it.shutdown() }
        localTtsEngines.clear()
        kokoroTts?.release()
        kokoroTts = null
        memoryDatabase?.close()
        memoryDatabase = null
        super.onMainDestroy()
    }

    override fun onMainRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onMainRequestPermissionsResult(requestCode, permissions, grantResults)
        AndroidDebugLog.d(TAG, "onMainRequestPermissionsResult request=$requestCode pendingScan=$pendingScanAfterPermission grants=${grantResults.joinToString(",")}")
        if (requestCode != CAMERA_PERMISSION_REQUEST || !pendingScanAfterPermission) {
            return
        }
        pendingScanAfterPermission = false
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            scanQr()
        } else {
            fail("相机权限未授权")
        }
    }

    override fun onMainActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onMainActivityResult(requestCode, resultCode, data)
        AndroidDebugLog.d(TAG, "onMainActivityResult request=$requestCode result=$resultCode hasData=${data != null}")
        if (requestCode != QR_SCAN_REQUEST) {
            return
        }
        when (resultCode) {
            Activity.RESULT_OK -> {
                val payload = data?.getStringExtra(QrScannerActivity.EXTRA_QR_PAYLOAD).orEmpty()
                if (payload.isBlank()) {
                    AndroidDebugLog.d(TAG, "qr scan returned blank payload")
                    fail("扫码结果为空")
                } else {
                    AndroidDebugLog.d(TAG, "qr scan succeeded chars=${payload.length} hash=${Integer.toHexString(payload.hashCode())}")
                    emitQrSignal("qr_scan_succeeded", payload)
                    emitQrSignal("scan_succeeded", payload)
                }
            }
            QrScannerActivity.RESULT_SCAN_ERROR -> {
                fail(data?.getStringExtra(QrScannerActivity.EXTRA_QR_ERROR).orEmpty().ifBlank { "扫码失败" })
            }
            else -> {
                AndroidDebugLog.d(TAG, "qr scan cancelled result=$resultCode")
                emitQrSignal("qr_scan_cancelled")
                emitQrSignal("scan_cancelled")
            }
        }
    }

    private fun fail(message: String) {
        AndroidDebugLog.d(TAG, "qr scan failed message=$message")
        emitQrSignal("qr_scan_failed", message)
        emitQrSignal("scan_failed", message)
    }

    private fun emitQrSignal(signalName: String, vararg args: Any?) {
        AndroidDebugLog.d(TAG, "emitQrSignal signal=$signalName args=${args.size}")
        runOnHostThread {
            try {
                emitSignal(signalName, *args)
            } catch (error: Throwable) {
                Log.e(TAG, "emitQrSignal failed signal=$signalName", error)
            }
        }
    }

    private fun ensureSystemTts(): Boolean {
        if (systemTts != null) {
            if (!systemTtsReady && !systemTtsInitializing) {
                AndroidDebugLog.d(TAG, "ensureSystemTts recreate after previous failed init")
                try {
                    systemTts?.shutdown()
                } catch (_: Exception) {
                }
                systemTts = null
            } else {
                AndroidDebugLog.d(TAG, "ensureSystemTts reuse ready=$systemTtsReady initializing=$systemTtsInitializing")
                return true
            }
        }
        if (systemTtsInitializing) {
            AndroidDebugLog.d(TAG, "ensureSystemTts already initializing")
            return true
        }
        val context = activity?.applicationContext
        if (context == null) {
            emitTtsSignal("tts_speech_failed", 0, "Android Activity 不可用")
            AndroidDebugLog.d(TAG, "ensureSystemTts failed: activity unavailable")
            return false
        }
        systemTtsInitializing = true
        AndroidDebugLog.d(TAG, "ensureSystemTts create TextToSpeech")
        systemTts = TextToSpeech(context) { status ->
            systemTtsInitializing = false
            systemTtsReady = status == TextToSpeech.SUCCESS
            val tts = systemTts
            AndroidDebugLog.d(TAG, "ensureSystemTts init callback status=$status ready=$systemTtsReady voices=${tts?.voices?.size ?: 0}")
            if (systemTtsReady && tts != null) {
                tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) {
                        val id = utteranceId?.toIntOrNull() ?: 0
                        emitTtsSignal("tts_speech_started", id)
                        emitTtsSignal("tts_speech_progress", id, 0.0)
                    }

                    override fun onDone(utteranceId: String?) {
                        val id = utteranceId?.toIntOrNull() ?: 0
                        synchronized(activeSystemTtsTexts) {
                            activeSystemTtsTexts.remove(id)
                        }
                        emitTtsSignal("tts_speech_progress", id, 1.0)
                        emitTtsSignal("tts_speech_done", id)
                    }

                    @Deprecated("Deprecated by Android")
                    override fun onError(utteranceId: String?) {
                        val id = utteranceId?.toIntOrNull() ?: 0
                        synchronized(activeSystemTtsTexts) {
                            activeSystemTtsTexts.remove(id)
                        }
                        emitTtsSignal("tts_speech_failed", id, "Android 系统 TTS 播放失败")
                    }

                    override fun onError(utteranceId: String?, errorCode: Int) {
                        val id = utteranceId?.toIntOrNull() ?: 0
                        synchronized(activeSystemTtsTexts) {
                            activeSystemTtsTexts.remove(id)
                        }
                        emitTtsSignal("tts_speech_failed", id, "Android 系统 TTS 错误：$errorCode")
                    }

                    override fun onRangeStart(utteranceId: String?, start: Int, end: Int, frame: Int) {
                        val id = utteranceId?.toIntOrNull() ?: 0
                        val textLength = synchronized(activeSystemTtsTexts) {
                            activeSystemTtsTexts[id]?.length ?: 0
                        }
                        if (textLength <= 0) {
                            return
                        }
                        val ratio = end.toDouble().coerceAtLeast(start.toDouble()) / textLength.toDouble()
                        emitTtsSignal("tts_speech_progress", id, ratio.coerceIn(0.0, 1.0))
                    }
                })
                emitTtsSignal("tts_ready")
                emitTtsSignal("tts_voices_updated", systemTtsVoicesJson())
                flushPendingSystemTtsRequests(tts)
            } else {
                emitTtsSignal("tts_speech_failed", 0, "Android 系统 TTS 初始化失败")
                failPendingSystemTtsRequests("Android 系统 TTS 初始化失败")
            }
        }
        return true
    }

    private fun ensureKokoroTts(): KokoroTtsEngine? {
        val existing = kokoroTts
        if (existing != null) {
            AndroidDebugLog.d(TAG, "ensureKokoroTts reuse available=${existing.isAvailable()} reason=${existing.unavailableReason()}")
            return existing
        }
        val context = activity?.applicationContext
        if (context == null) {
            AndroidDebugLog.d(TAG, "ensureKokoroTts failed: activity unavailable")
            return null
        }
        AndroidDebugLog.d(TAG, "ensureKokoroTts create engine")
        val created = KokoroTtsEngine(
            context,
            object : KokoroTtsEngine.Listener {
                override fun onReady() {
                    emitTtsSignal("kokoro_tts_ready")
                    emitTtsSignal("tts_ready")
                }

                override fun onVoicesUpdated(payload: String) {
                    emitTtsSignal("tts_voices_updated", payload)
                }

                override fun onSpeechStarted(utteranceId: Int) {
                    emitTtsSignal("tts_speech_started", utteranceId)
                }

                override fun onSpeechProgress(utteranceId: Int, ratio: Double) {
                    emitTtsSignal("tts_speech_progress", utteranceId, ratio)
                }

                override fun onSpeechDone(utteranceId: Int) {
                    emitTtsSignal("tts_speech_done", utteranceId)
                }

                override fun onSpeechFailed(utteranceId: Int, error: String) {
                    emitTtsSignal("tts_speech_failed", utteranceId, error)
                }
            }
        )
        kokoroTts = created
        return created
    }

    private fun ensureLocalTtsEngine(engineId: String): LocalAndroidTtsEngine? {
        val normalized = normalizeLocalTtsEngineId(engineId)
        localTtsEngines[normalized]?.let {
            AndroidDebugLog.d(TAG, "ensureLocalTtsEngine reuse engine=$normalized ready=${it.isReady()}")
            return it
        }
        val definition = localTtsDefinition(normalized) ?: return null
        val context = activity?.applicationContext ?: return null
        val reason = LocalTtsCatalog.availabilityReason(context)
        if (reason.isNotEmpty()) {
            AndroidDebugLog.d(TAG, "ensureLocalTtsEngine unavailable engine=$normalized reason=$reason")
            return null
        }
        val created = LocalAndroidTtsEngine(
            context = context,
            definition = definition,
            listener = object : LocalAndroidTtsEngine.Listener {
                override fun onReady(engineId: String) {
                    emitTtsSignal("external_tts_ready", engineId)
                    emitTtsSignal("tts_ready")
                }

                override fun onVoicesUpdated(payload: String) {
                    emitTtsSignal("tts_voices_updated", payload)
                }

                override fun onSpeechStarted(utteranceId: Int) {
                    emitTtsSignal("tts_speech_started", utteranceId)
                }

                override fun onSpeechProgress(utteranceId: Int, ratio: Double) {
                    emitTtsSignal("tts_speech_progress", utteranceId, ratio)
                }

                override fun onSpeechDone(utteranceId: Int) {
                    emitTtsSignal("tts_speech_done", utteranceId)
                }

                override fun onSpeechFailed(utteranceId: Int, error: String) {
                    emitTtsSignal("tts_speech_failed", utteranceId, error)
                }
            }
        )
        localTtsEngines[normalized] = created
        AndroidDebugLog.d(TAG, "ensureLocalTtsEngine create engine=$normalized backend=${definition.backend}")
        return created
    }

    private fun isDebuggableApp(): Boolean {
        val context = activity?.applicationContext ?: return false
        return (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
    }

    private fun localTtsDefinition(engineId: String): LocalTtsDefinition? {
        return LocalTtsCatalog.definition(engineId)
    }

    private fun normalizeLocalTtsEngineId(engineId: String): String {
        return LocalTtsCatalog.normalizeEngineId(engineId)
    }

    private fun ensureMemoryDatabase(): MemoryDatabase? {
        val existing = memoryDatabase
        if (existing != null) {
            return existing
        }
        val context = activity?.applicationContext ?: return null
        val created = MemoryDatabase(context)
        memoryDatabase = created
        return created
    }

    private fun memoryResult(block: (MemoryDatabase) -> Any): String {
        val database = ensureMemoryDatabase()
            ?: return JSONObject()
                .put("ok", false)
                .put("error", "Android Activity 不可用")
                .toString()
        return try {
            val value = block(database)
            when (value) {
                is JSONObject -> value.toString()
                is JSONArray -> value.toString()
                else -> JSONObject().put("ok", true).put("value", value).toString()
            }
        } catch (error: Exception) {
            JSONObject()
                .put("ok", false)
                .put("error", error.message ?: "SQLite 记忆数据库操作失败")
                .toString()
        }
    }

    private fun identityError(message: String): String {
        return JSONObject()
            .put("ok", false)
            .put("error", message)
            .toString()
    }

    private fun identityNonce(byteLength: Int): String {
        val bytes = ByteArray(byteLength)
        SecureRandom().nextBytes(bytes)
        return base64Url(bytes)
    }

    private fun deviceAuthBytes(challenge: String, deviceId: String, publicKey: String): ByteArray {
        return "$DEVICE_AUTH_DOMAIN\n$challenge\n$deviceId\n$publicKey".toByteArray(Charsets.UTF_8)
    }

    private fun base64Url(bytes: ByteArray): String {
        return Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
    }

    private fun base64UrlDecode(value: String): ByteArray {
        return Base64.decode(value, Base64.URL_SAFE or Base64.NO_WRAP)
    }

    private fun rawEd25519PublicKey(encoded: ByteArray): ByteArray {
        if (encoded.size == 32) {
            return encoded
        }
        if (encoded.size >= 32) {
            return encoded.copyOfRange(encoded.size - 32, encoded.size)
        }
        return encoded
    }

    private fun ed25519PublicKeySpec(rawOrEncoded: ByteArray): ByteArray {
        if (rawOrEncoded.size != 32) {
            return rawOrEncoded
        }
        return ED25519_X509_PREFIX + rawOrEncoded
    }

    private fun emitTtsSignal(signalName: String, vararg args: Any?) {
        val normalizedArgs = normalizeTtsSignalArgs(signalName, args)
        AndroidDebugLog.d(TAG, "emitTtsSignal signal=$signalName args=${normalizedArgs.size} raw=[${describeSignalArgs(args)}] normalized=[${describeSignalArgs(normalizedArgs)}]")
        runOnHostThread {
            try {
                emitSignal(signalName, *normalizedArgs)
            } catch (error: Throwable) {
                Log.e(TAG, "emitTtsSignal failed signal=$signalName args=[${describeSignalArgs(normalizedArgs)}]", error)
            }
        }
    }

    private fun normalizeTtsSignalArgs(signalName: String, args: Array<out Any?>): Array<Any> {
        return when (signalName) {
            "tts_ready",
            "kokoro_tts_ready" -> emptyArray()
            "external_tts_ready" -> arrayOf(args.getOrNull(0)?.toString().orEmpty())
            "tts_voices_updated" -> arrayOf(args.getOrNull(0)?.toString().orEmpty())
            "tts_speech_started",
            "tts_speech_done" -> arrayOf(signalArgToInt(args.getOrNull(0)))
            "tts_speech_progress" -> arrayOf(
                signalArgToInt(args.getOrNull(0)),
                signalArgToDouble(args.getOrNull(1)).coerceIn(0.0, 1.0)
            )
            "tts_speech_failed" -> arrayOf(
                signalArgToInt(args.getOrNull(0)),
                args.getOrNull(1)?.toString().orEmpty()
            )
            else -> args.map { it ?: "" }.toTypedArray()
        }
    }

    private fun signalArgToDouble(value: Any?): Double {
        return when (value) {
            is Double -> value
            is Float -> value.toDouble()
            is Number -> value.toDouble()
            is String -> value.toDoubleOrNull() ?: 0.0
            else -> 0.0
        }
    }

    private fun signalArgToInt(value: Any?): Int {
        return when (value) {
            is Int -> value
            is Number -> value.toInt()
            is String -> value.toIntOrNull() ?: 0
            else -> 0
        }
    }

    private fun describeSignalArgs(args: Array<out Any?>): String {
        return args.mapIndexed { index, value ->
            "#$index:${value?.javaClass?.name ?: "null"}=${shortDebugValue(value)}"
        }.joinToString(", ")
    }

    private fun shortDebugValue(value: Any?): String {
        val text = value?.toString() ?: "null"
        return if (text.length > 160) "${text.take(160)}..." else text
    }

    private fun systemTtsVoicesJson(): String {
        val voices = systemTts?.voices.orEmpty()
        val array = JSONArray()
        voices
            .filter { !it.isNetworkConnectionRequired }
            .sortedWith(compareBy<Voice> { it.locale?.toLanguageTag().orEmpty() }.thenBy { it.name })
            .forEach { voice ->
                array.put(
                    JSONObject()
                        .put("id", voiceIdFor(voice))
                        .put("name", voice.name)
                        .put("engine", "system")
                        .put("language", voice.locale?.toLanguageTag().orEmpty())
                        .put("locale", voice.locale?.toLanguageTag().orEmpty())
                        .put("quality", voice.quality)
                        .put("latency", voice.latency)
                        .put("networkRequired", voice.isNetworkConnectionRequired)
                )
            }
        return array.toString()
    }

    private fun voiceIdFor(voice: Voice): String {
        val locale = voice.locale?.toLanguageTag()?.ifBlank { "default" } ?: "default"
        return "$locale::${voice.name}"
    }

    companion object {
        private const val TAG = "PlayWithMeAndroid"
        private const val CAMERA_PERMISSION_REQUEST = 42871
        private const val QR_SCAN_REQUEST = 42872
        private const val DEVICE_SIGNATURE_ALGORITHM = "Ed25519"
        private const val DEVICE_AUTH_DOMAIN = "chat_with_me.device_auth.v1"
        private val ED25519_X509_PREFIX = byteArrayOf(
            0x30.toByte(),
            0x2a.toByte(),
            0x30.toByte(),
            0x05.toByte(),
            0x06.toByte(),
            0x03.toByte(),
            0x2b.toByte(),
            0x65.toByte(),
            0x70.toByte(),
            0x03.toByte(),
            0x21.toByte(),
            0x00.toByte(),
        )
    }
}
