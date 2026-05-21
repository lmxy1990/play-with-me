package com.playwithme.godot

import android.content.Context
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
import java.util.Locale

internal class RegisteredLocalTtsClient(
    context: Context,
    private val definition: LocalTtsDefinition,
    private val listener: LocalAndroidTtsEngine.Listener
) {
    private val appContext = context.applicationContext
    private val lock = Any()
    private val activeTexts = mutableMapOf<Int, String>()
    private var tts: TextToSpeech? = null
    private var ready = false
    private var initializing = false
    private var failed = false
    private var progressListenerBound = false

    fun isReady(): Boolean = synchronized(lock) { ready }

    private fun isInitializing(): Boolean = synchronized(lock) { initializing }

    fun warmUp(): Boolean {
        if (!PlayWithMeTtsRegistration.isServiceRegistered(appContext)) {
            AndroidDebugLog.d(TAG, "warmUp skipped: service not registered engine=${definition.id}")
            return false
        }
        val accepted = ensureTts()
        if (accepted && isReady()) {
            notifyReadyIfNeeded()
        }
        val usable = accepted && (isReady() || isInitializing())
        AndroidDebugLog.d(TAG, "warmUp registered engine=${definition.id} accepted=$accepted ready=${isReady()} initializing=${isInitializing()} usable=$usable")
        return usable
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
        if (!PlayWithMeTtsRegistration.isServiceRegistered(appContext)) {
            AndroidDebugLog.d(TAG, "speak skipped: service not registered engine=${definition.id}")
            return false
        }
        if (!ensureTts() || !isReady()) {
            AndroidDebugLog.d(TAG, "speak skipped: registered service not ready engine=${definition.id} initializing=$initializing failed=$failed")
            return false
        }
        val cleanText = text.trim()
        if (cleanText.isEmpty()) {
            listener.onSpeechFailed(utteranceId, "播报文本为空")
            return true
        }
        val ttsRef = synchronized(lock) { tts } ?: return false
        val requestedVoice = PlayWithMeTtsRegistration.voiceName(definition.id, voiceId)
        val voice = ttsRef.voices?.firstOrNull { it.name == requestedVoice }
            ?: PlayWithMeTtsRegistration.voiceFor(definition.id, voiceId)
        val setVoiceResult = ttsRef.setVoice(voice)
        if (setVoiceResult != TextToSpeech.SUCCESS) {
            AndroidDebugLog.d(TAG, "speak fallback: setVoice failed engine=${definition.id} voice=$requestedVoice result=$setVoiceResult")
            return false
        }
        ttsRef.setLanguage(Locale.SIMPLIFIED_CHINESE)
        ttsRef.setSpeechRate(speed.toFloat().coerceIn(0.1f, 2.0f))
        ttsRef.setPitch(pitch.toFloat().coerceIn(0.5f, 2.0f))
        val params = Bundle().apply {
            putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, volume.toFloat().coerceIn(0.0f, 1.0f))
        }
        val queueMode = if (interrupt) TextToSpeech.QUEUE_FLUSH else TextToSpeech.QUEUE_ADD
        synchronized(lock) {
            if (interrupt) {
                activeTexts.clear()
            }
            activeTexts[utteranceId] = cleanText
        }
        val speakResult = ttsRef.speak(cleanText, queueMode, params, utteranceId.toString())
        if (speakResult != TextToSpeech.SUCCESS) {
            synchronized(lock) {
                activeTexts.remove(utteranceId)
            }
            AndroidDebugLog.d(TAG, "speak fallback: service speak failed engine=${definition.id} voice=$requestedVoice result=$speakResult")
            return false
        }
        AndroidDebugLog.d(TAG, "speak registered engine=${definition.id} voice=$requestedVoice utterance=$utteranceId")
        return true
    }

    fun stop() {
        synchronized(lock) {
            activeTexts.clear()
        }
        tts?.stop()
    }

    fun shutdown() {
        synchronized(lock) {
            ready = false
            initializing = false
            failed = false
            progressListenerBound = false
            activeTexts.clear()
        }
        tts?.stop()
        tts?.shutdown()
        tts = null
    }

    private fun ensureTts(): Boolean {
        synchronized(lock) {
            if (ready || initializing) {
                return true
            }
            if (failed) {
                return false
            }
            initializing = true
        }
        return try {
            val created = TextToSpeech(appContext, { status ->
                val ok = status == TextToSpeech.SUCCESS
                synchronized(lock) {
                    initializing = false
                    ready = ok
                    failed = !ok
                }
                AndroidDebugLog.d(TAG, "registered service init callback engine=${definition.id} status=$status ready=$ok")
                if (ok) {
                    notifyReadyIfNeeded()
                } else {
                    clearFailedTextToSpeech()
                }
            }, appContext.packageName)
            var shutdownCreated = false
            var notifyReady = false
            synchronized(lock) {
                if (failed) {
                    shutdownCreated = true
                } else {
                    tts = created
                    notifyReady = ready
                }
            }
            if (shutdownCreated) {
                created.shutdown()
            }
            if (notifyReady) {
                notifyReadyIfNeeded()
            }
            true
        } catch (error: Exception) {
            synchronized(lock) {
                initializing = false
                ready = false
                failed = true
            }
            AndroidDebugLog.d(TAG, "registered service init failed engine=${definition.id} error=${error.message}", error)
            false
        }
    }

    private fun clearFailedTextToSpeech() {
        val existing = synchronized(lock) {
            val current = tts
            tts = null
            progressListenerBound = false
            current
        }
        existing?.shutdown()
    }

    private fun notifyReadyIfNeeded() {
        val current = synchronized(lock) {
            if (!ready || progressListenerBound) {
                return
            }
            progressListenerBound = true
            tts
        } ?: return
        current.setOnUtteranceProgressListener(createProgressListener())
        AndroidDebugLog.d(TAG, "registered service ready engine=${definition.id} voices=${current.voices?.size ?: 0}")
        listener.onReady(definition.id)
        listener.onVoicesUpdated(LocalTtsCatalog.voicesJson(definition))
    }

    private fun createProgressListener(): UtteranceProgressListener {
        return object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {
                val id = utteranceId?.toIntOrNull() ?: 0
                listener.onSpeechStarted(id)
                listener.onSpeechProgress(id, 0.0)
            }

            override fun onDone(utteranceId: String?) {
                val id = utteranceId?.toIntOrNull() ?: 0
                synchronized(lock) {
                    activeTexts.remove(id)
                }
                listener.onSpeechProgress(id, 1.0)
                listener.onSpeechDone(id)
            }

            @Deprecated("Deprecated by Android")
            override fun onError(utteranceId: String?) {
                val id = utteranceId?.toIntOrNull() ?: 0
                synchronized(lock) {
                    activeTexts.remove(id)
                }
                listener.onSpeechFailed(id, "本地 TTS 系统服务播放失败")
            }

            override fun onError(utteranceId: String?, errorCode: Int) {
                val id = utteranceId?.toIntOrNull() ?: 0
                synchronized(lock) {
                    activeTexts.remove(id)
                }
                listener.onSpeechFailed(id, "本地 TTS 系统服务错误：$errorCode")
            }

            override fun onRangeStart(utteranceId: String?, start: Int, end: Int, frame: Int) {
                val id = utteranceId?.toIntOrNull() ?: 0
                val textLength = synchronized(lock) {
                    activeTexts[id]?.length ?: 0
                }
                if (textLength <= 0) {
                    return
                }
                val ratio = end.toDouble().coerceAtLeast(start.toDouble()) / textLength.toDouble()
                listener.onSpeechProgress(id, ratio.coerceIn(0.0, 1.0))
            }
        }
    }

    companion object {
        private const val TAG = "RegisteredLocalTts"
    }
}
