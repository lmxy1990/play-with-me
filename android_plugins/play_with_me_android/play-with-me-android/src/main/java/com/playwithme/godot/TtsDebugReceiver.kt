package com.playwithme.godot

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class TtsDebugReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_TTS_DEBUG_SNAPSHOT -> handleSnapshot(context)
            ACTION_TTS_DEBUG_SPEAK -> handleSpeak(context, intent)
        }
    }

    private fun handleSnapshot(context: Context) {
        if (!isDebuggable(context)) {
            setDeniedResult()
            return
        }
        val snapshot = LocalTtsCatalog.debugSnapshot(context.applicationContext)
            .put("debuggable", true)
            .put("api", "broadcast")
        setResultCode(Activity.RESULT_OK)
        setResultData(snapshot.toString())
        AndroidDebugLog.d(TAG, snapshot.toString())
    }

    private fun handleSpeak(context: Context, intent: Intent) {
        if (!isDebuggable(context)) {
            setDeniedResult()
            return
        }

        val pendingResult = goAsync()
        Thread {
            val payload = runDebugSpeak(context.applicationContext, intent)
            pendingResult.setResultCode(
                if (payload.optBoolean("ok", false)) Activity.RESULT_OK else Activity.RESULT_CANCELED
            )
            pendingResult.setResultData(payload.toString())
            AndroidDebugLog.d(TAG, payload.toString())
            pendingResult.finish()
        }.apply {
            name = "tts-debug-speak"
            start()
        }
    }

    private fun runDebugSpeak(context: Context, intent: Intent): JSONObject {
        val startedAtMs = System.currentTimeMillis()
        val rawEngine = intent.getStringExtra(EXTRA_ENGINE).orEmpty().ifBlank { "neko_tts" }
        val engineId = LocalTtsCatalog.normalizeEngineId(rawEngine)
        val definition = LocalTtsCatalog.definition(engineId)
            ?: return errorPayload(engineId, "未知本地 TTS 引擎：$rawEngine")
        val availabilityReason = LocalTtsCatalog.availabilityReason(context)
        if (availabilityReason.isNotEmpty()) {
            return errorPayload(engineId, availabilityReason)
        }

        val text = intent.getStringExtra(EXTRA_TEXT).orEmpty().ifBlank { DEFAULT_TEST_TEXT }.trim()
        val voice = intent.getStringExtra(EXTRA_VOICE).orEmpty().ifBlank { DEFAULT_VOICE_ID }.trim()
        val utteranceId = intExtra(intent, EXTRA_UTTERANCE_ID, DEFAULT_UTTERANCE_ID)
        val speed = doubleExtra(intent, EXTRA_SPEED, 0.9).coerceIn(0.1, 1.0)
        val pitch = doubleExtra(intent, EXTRA_PITCH, 1.0).coerceIn(0.5, 2.0)
        val volume = doubleExtra(intent, EXTRA_VOLUME, 1.0).coerceIn(0.0, 1.0)
        val timeoutMs = longExtra(intent, EXTRA_TIMEOUT_MS, DEFAULT_TIMEOUT_MS)
            .coerceIn(1_000L, MAX_TIMEOUT_MS)
        val warmUp = booleanExtra(intent, EXTRA_WARM_UP, false)

        val events = JSONArray()
        val done = CountDownLatch(1)
        val state = DebugSpeakState()
        val listener = object : LocalAndroidTtsEngine.Listener {
            override fun onReady(engineId: String) {
                appendEvent(events, "ready", utteranceId, "engine", engineId)
            }

            override fun onVoicesUpdated(payload: String) {
                appendEvent(events, "voices_updated", utteranceId, "count", JSONArray(payload).length())
            }

            override fun onSpeechStarted(utteranceId: Int) {
                synchronized(state) {
                    state.started = true
                }
                appendEvent(events, "started", utteranceId)
            }

            override fun onSpeechProgress(utteranceId: Int, ratio: Double) {
                synchronized(state) {
                    val normalized = ratio.coerceIn(0.0, 1.0)
                    if (normalized < 1.0 && normalized - state.lastProgress < 0.1) {
                        return
                    }
                    state.lastProgress = normalized
                    appendEvent(events, "progress", utteranceId, "ratio", normalized)
                }
            }

            override fun onSpeechDone(utteranceId: Int) {
                synchronized(state) {
                    state.completed = true
                    state.lastProgress = 1.0
                }
                appendEvent(events, "done", utteranceId)
                done.countDown()
            }

            override fun onSpeechFailed(utteranceId: Int, error: String) {
                synchronized(state) {
                    state.failed = true
                    state.error = error
                }
                appendEvent(events, "failed", utteranceId, "error", error)
                done.countDown()
            }
        }

        val engine = LocalAndroidTtsEngine(context, definition, listener)
        return try {
            var warmUpAccepted = false
            if (warmUp) {
                warmUpAccepted = engine.warmUp()
            }
            val speakAccepted = engine.speak(
                text = text,
                voiceId = voice,
                speed = speed,
                pitch = pitch,
                volume = volume,
                utteranceId = utteranceId,
                interrupt = true
            )
            if (!speakAccepted) {
                done.countDown()
            }
            val completedBeforeTimeout = done.await(timeoutMs, TimeUnit.MILLISECONDS)
            if (!completedBeforeTimeout) {
                synchronized(state) {
                    state.timedOut = true
                    state.error = "TTS debug speak timed out after ${timeoutMs}ms"
                }
                appendEvent(events, "timeout", utteranceId, "timeoutMs", timeoutMs)
                engine.stop()
            }
            val elapsedMs = System.currentTimeMillis() - startedAtMs
            synchronized(state) {
                JSONObject()
                    .put("ok", speakAccepted && state.completed && !state.failed && !state.timedOut)
                    .put("debuggable", true)
                    .put("api", "broadcast_speak")
                    .put("mode", "in_app_inference")
                    .put("engine", definition.id)
                    .put("backend", definition.backend)
                    .put("voice", voice)
                    .put("utteranceId", utteranceId)
                    .put("textChars", text.length)
                    .put("speed", speed)
                    .put("volume", volume)
                    .put("warmUpRequested", warmUp)
                    .put("warmUpAccepted", warmUpAccepted)
                    .put("speakAccepted", speakAccepted)
                    .put("started", state.started)
                    .put("completed", state.completed)
                    .put("timedOut", state.timedOut)
                    .put("error", state.error)
                    .put("elapsedMs", elapsedMs)
                    .put("events", events)
            }
        } catch (error: Exception) {
            errorPayload(definition.id, error.message ?: "TTS debug speak failed")
                .put("events", events)
        } finally {
            engine.shutdown()
        }
    }

    private fun setDeniedResult() {
        val denied = JSONObject()
            .put("ok", false)
            .put("debuggable", false)
            .put("error", "TTS debug API only works in debug builds")
            .toString()
        setResultCode(Activity.RESULT_CANCELED)
        setResultData(denied)
        AndroidDebugLog.d(TAG, denied)
    }

    private fun isDebuggable(context: Context): Boolean {
        return (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
    }

    private fun doubleExtra(intent: Intent, key: String, defaultValue: Double): Double {
        return when (val value = intent.extras?.get(key)) {
            is Number -> value.toDouble()
            is String -> value.toDoubleOrNull() ?: defaultValue
            else -> defaultValue
        }
    }

    private fun intExtra(intent: Intent, key: String, defaultValue: Int): Int {
        return when (val value = intent.extras?.get(key)) {
            is Number -> value.toInt()
            is String -> value.toIntOrNull() ?: defaultValue
            else -> defaultValue
        }
    }

    private fun longExtra(intent: Intent, key: String, defaultValue: Long): Long {
        return when (val value = intent.extras?.get(key)) {
            is Number -> value.toLong()
            is String -> value.toLongOrNull() ?: defaultValue
            else -> defaultValue
        }
    }

    private fun booleanExtra(intent: Intent, key: String, defaultValue: Boolean): Boolean {
        return when (val value = intent.extras?.get(key)) {
            is Boolean -> value
            is String -> value.equals("true", ignoreCase = true) || value == "1"
            else -> defaultValue
        }
    }

    private fun errorPayload(engineId: String, error: String): JSONObject {
        return JSONObject()
            .put("ok", false)
            .put("debuggable", true)
            .put("api", "broadcast_speak")
            .put("mode", "in_app_inference")
            .put("engine", engineId)
            .put("error", error)
    }

    private fun appendEvent(events: JSONArray, type: String, utteranceId: Int, key: String = "", value: Any? = null) {
        synchronized(events) {
            val event = JSONObject()
                .put("type", type)
                .put("utteranceId", utteranceId)
                .put("atMs", System.currentTimeMillis())
            if (key.isNotEmpty()) {
                event.put(key, value)
            }
            events.put(event)
        }
    }

    private class DebugSpeakState {
        var started: Boolean = false
        var completed: Boolean = false
        var failed: Boolean = false
        var timedOut: Boolean = false
        var error: String = ""
        var lastProgress: Double = -1.0
    }

    companion object {
        const val ACTION_TTS_DEBUG_SNAPSHOT = "com.playwithme.godot.TTS_DEBUG_SNAPSHOT"
        const val ACTION_TTS_DEBUG_SPEAK = "com.playwithme.godot.TTS_DEBUG_SPEAK"
        private const val EXTRA_ENGINE = "engine"
        private const val EXTRA_VOICE = "voice"
        private const val EXTRA_TEXT = "text"
        private const val EXTRA_SPEED = "speed"
        private const val EXTRA_PITCH = "pitch"
        private const val EXTRA_VOLUME = "volume"
        private const val EXTRA_UTTERANCE_ID = "utterance_id"
        private const val EXTRA_TIMEOUT_MS = "timeout_ms"
        private const val EXTRA_WARM_UP = "warm_up"
        private const val DEFAULT_VOICE_ID = "zf_001"
        private const val DEFAULT_UTTERANCE_ID = 7001
        private const val DEFAULT_TIMEOUT_MS = 45_000L
        private const val MAX_TIMEOUT_MS = 120_000L
        private const val DEFAULT_TEST_TEXT = "这是调试接口播放测试，用于验证本地语音引擎可以完成中文文本推理和播放。"
        private const val TAG = "TtsDebugReceiver"
    }
}
