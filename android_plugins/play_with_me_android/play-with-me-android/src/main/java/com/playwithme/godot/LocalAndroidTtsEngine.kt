package com.playwithme.godot

import android.content.Context

internal class LocalAndroidTtsEngine(
    context: Context,
    private val definition: LocalTtsDefinition,
    private val listener: Listener
) {
    interface Listener {
        fun onReady(engineId: String)
        fun onVoicesUpdated(payload: String)
        fun onSpeechStarted(utteranceId: Int)
        fun onSpeechProgress(utteranceId: Int, ratio: Double)
        fun onSpeechDone(utteranceId: Int)
        fun onSpeechFailed(utteranceId: Int, error: String)
    }

    private var ready = false
    private val registered = RegisteredLocalTtsClient(context, definition, listener)
    private val kokoro = KokoroTtsEngine(
        context,
        object : KokoroTtsEngine.Listener {
            override fun onReady() {
                ready = true
                listener.onReady(definition.id)
            }

            override fun onVoicesUpdated(payload: String) {
                listener.onVoicesUpdated(LocalTtsCatalog.voicesJson(definition))
            }

            override fun onSpeechStarted(utteranceId: Int) {
                listener.onSpeechStarted(utteranceId)
            }

            override fun onSpeechProgress(utteranceId: Int, ratio: Double) {
                listener.onSpeechProgress(utteranceId, ratio)
            }

            override fun onSpeechDone(utteranceId: Int) {
                listener.onSpeechDone(utteranceId)
            }

            override fun onSpeechFailed(utteranceId: Int, error: String) {
                listener.onSpeechFailed(utteranceId, error)
            }
        }
    )

    fun isReady(): Boolean = ready || registered.isReady()

    fun warmUp(): Boolean {
        if (!kokoro.isAvailable()) {
            listener.onSpeechFailed(0, "${definition.label} 本地推理不可用：${kokoro.unavailableReason()}")
            return false
        }
        if (registered.warmUp()) {
            AndroidDebugLog.d(TAG, "warmUp registered local service engine=${definition.id} backend=${definition.backend}")
            return true
        }
        AndroidDebugLog.d(TAG, "warmUp local engine=${definition.id} backend=${definition.backend}")
        return kokoro.warmUp()
    }

    fun voicesJson(): String {
        return LocalTtsCatalog.voicesJson(definition)
    }

    fun speak(
        text: String,
        voiceId: String,
        speed: Double,
        pitch: Double,
        volume: Double,
        utteranceId: Int,
        interrupt: Boolean
    ): Boolean {
        AndroidDebugLog.d(TAG, "speak local engine=${definition.id} utterance=$utteranceId voice=${voiceId.ifBlank { "<default>" }} pitch=$pitch")
        if (registered.speak(text, voiceId, speed, pitch, volume, utteranceId, interrupt)) {
            return true
        }
        return kokoro.speak(text, voiceId, speed, volume, utteranceId, interrupt)
    }

    fun stop() {
        registered.stop()
        kokoro.stop()
    }

    fun shutdown() {
        ready = false
        registered.shutdown()
        kokoro.release()
    }

    companion object {
        private const val TAG = "LocalAndroidTts"
    }
}
