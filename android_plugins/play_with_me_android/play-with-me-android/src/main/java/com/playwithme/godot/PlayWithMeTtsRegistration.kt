package com.playwithme.godot

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.speech.tts.TextToSpeech
import android.speech.tts.Voice
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale

internal data class RegisteredLocalVoice(
    val engineId: String,
    val voiceId: String
)

internal object PlayWithMeTtsRegistration {
    const val SERVICE_CLASS_NAME = "com.playwithme.godot.PlayWithMeTtsService"
    private const val SERVICE_ACTION = TextToSpeech.Engine.INTENT_ACTION_TTS_SERVICE
    private val LOCALE = Locale.SIMPLIFIED_CHINESE

    fun voiceName(engineId: String, voiceId: String): String {
        val normalizedEngine = LocalTtsCatalog.normalizeEngineId(engineId)
        val normalizedVoice = voiceId.trim().ifBlank { KokoroTtsEngine.DEFAULT_CHINESE_VOICE_ID }
        return "$normalizedEngine::$normalizedVoice"
    }

    fun parseVoiceName(value: String): RegisteredLocalVoice? {
        val clean = value.trim()
        val marker = clean.indexOf("::")
        if (marker <= 0 || marker + 2 >= clean.length) {
            return null
        }
        val engineId = LocalTtsCatalog.normalizeEngineId(clean.substring(0, marker))
        val voiceId = clean.substring(marker + 2).trim()
        if (LocalTtsCatalog.definition(engineId) == null) {
            return null
        }
        if (KokoroTtsEngine.speakerIdForVoiceId(voiceId) < 0) {
            return null
        }
        return RegisteredLocalVoice(engineId, voiceId)
    }

    fun voiceFor(engineId: String, voiceId: String): Voice {
        return Voice(
            voiceName(engineId, voiceId),
            LOCALE,
            Voice.QUALITY_HIGH,
            Voice.LATENCY_NORMAL,
            false,
            emptySet()
        )
    }

    fun allVoices(): List<Voice> {
        val result = mutableListOf<Voice>()
        LocalTtsCatalog.definitions.forEach { definition ->
            val voices = JSONArray(LocalTtsCatalog.voicesJson(definition))
            for (index in 0 until voices.length()) {
                val voice = voices.optJSONObject(index) ?: continue
                val voiceId = voice.optString("id").trim()
                if (voiceId.isNotEmpty()) {
                    result.add(voiceFor(definition.id, voiceId))
                }
            }
        }
        return result
    }

    fun isServiceRegistered(context: Context?): Boolean {
        return serviceDiscovery(context).optBoolean("registered", false)
    }

    fun serviceDiscovery(context: Context?): JSONObject {
        if (context == null) {
            return JSONObject()
                .put("registered", false)
                .put("reason", "Android Context 不可用")
        }
        return try {
            val packageName = context.packageName
            val intent = Intent(SERVICE_ACTION).setPackage(packageName)
            val services = queryTtsServices(context, intent)
            val matches = JSONArray()
            var registered = false
            for (service in services) {
                val info = service.serviceInfo ?: continue
                val className = info.name.orEmpty()
                val match = className == SERVICE_CLASS_NAME || className.endsWith(".PlayWithMeTtsService")
                if (match) {
                    registered = true
                }
                matches.put(
                    JSONObject()
                        .put("package", info.packageName.orEmpty())
                        .put("name", className)
                        .put("exported", info.exported)
                        .put("permission", info.permission.orEmpty())
                        .put("match", match)
                )
            }
            JSONObject()
                .put("registered", registered)
                .put("action", SERVICE_ACTION)
                .put("package", packageName)
                .put("serviceClass", SERVICE_CLASS_NAME)
                .put("matches", matches)
                .put("serviceCount", services.size)
        } catch (error: Exception) {
            JSONObject()
                .put("registered", false)
                .put("reason", error.message ?: "TTS Service 查询失败")
        }
    }

    @Suppress("DEPRECATION")
    private fun queryTtsServices(context: Context, intent: Intent): List<android.content.pm.ResolveInfo> {
        val manager = context.packageManager
        return if (Build.VERSION.SDK_INT >= 33) {
            manager.queryIntentServices(
                intent,
                PackageManager.ResolveInfoFlags.of(PackageManager.GET_META_DATA.toLong())
            )
        } else {
            manager.queryIntentServices(intent, PackageManager.GET_META_DATA)
        }
    }
}
