package com.playwithme.godot

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale

internal data class LocalTtsDefinition(
    val id: String,
    val label: String,
    val backend: String
)

internal object LocalTtsCatalog {
    private const val KOKORO_ASSET_DIR = "tts/kokoro-int8-multi-lang-v1_1"

    val definitions = listOf(
        LocalTtsDefinition("neko_tts", "NekoTTS", "kokoro_sherpa"),
        LocalTtsDefinition("voxsherpa_tts", "VoxSherpa-TTS", "kokoro_sherpa"),
        LocalTtsDefinition("multi_tts", "MultiTTS", "kokoro_sherpa")
    )

    fun definition(engineId: String): LocalTtsDefinition? {
        val normalized = normalizeEngineId(engineId)
        return definitions.firstOrNull { it.id == normalized }
    }

    fun normalizeEngineId(engineId: String): String {
        return when (engineId.trim().lowercase(Locale.ROOT).replace("-", "_").replace(" ", "_")) {
            "neko", "neko_tts", "nekotts", "nekospeak", "neko_speak" -> "neko_tts"
            "voxsherpa", "voxsherpa_tts", "vox_sherpa", "vox_sherpa_tts" -> "voxsherpa_tts"
            "multi", "multi_tts", "multitts", "tts_server", "tts_server_android" -> "multi_tts"
            else -> engineId.trim().lowercase(Locale.ROOT).replace("-", "_").replace(" ", "_")
        }
    }

    fun isAvailable(context: Context?): Boolean {
        return availabilityReason(context).isEmpty()
    }

    fun availabilityReason(context: Context?): String {
        if (!KokoroNative.isAvailable) {
            return "本地 TTS native runtime 不可用：${KokoroNative.unavailableReason}"
        }
        val assetStatus = kokoroAssetStatus(context)
        if (!assetStatus.optBoolean("available", false)) {
            return assetStatus.optString("reason", "本地 TTS 模型资产不可用")
        }
        return ""
    }

    fun voicesJson(definition: LocalTtsDefinition): String {
        val voices = JSONArray(KokoroTtsEngine.kokoroVoicesJson())
        val result = JSONArray()
        for (index in 0 until voices.length()) {
            val voice = voices.optJSONObject(index) ?: continue
            val id = voice.optString("id")
            val gender = voice.optString("gender")
            result.put(
                JSONObject(voice.toString())
                    .put("id", id)
                    .put("name", "${definition.label} ${gender.ifBlank { "音色" }} $id")
                    .put("engine", definition.id)
                    .put("backend", definition.backend)
                    .put("networkRequired", false)
            )
        }
        return result.toString()
    }

    fun debugSnapshot(context: Context?): JSONObject {
        val assetStatus = kokoroAssetStatus(context)
        val registration = PlayWithMeTtsRegistration.serviceDiscovery(context)
        val registered = registration.optBoolean("registered", false)
        val engineArray = JSONArray()
        definitions.forEach { definition ->
            val reason = availabilityReason(context)
            engineArray.put(
                JSONObject()
                    .put("id", definition.id)
                    .put("label", definition.label)
                    .put("backend", definition.backend)
                    .put("available", reason.isEmpty())
                    .put("reason", reason)
                    .put("systemServiceVoicePrefix", "${definition.id}::")
                    .put("voiceCount", JSONArray(voicesJson(definition)).length())
            )
        }
        return JSONObject()
            .put("ok", true)
            .put("mode", if (registered) "system_tts_service_with_in_app_fallback" else "in_app_inference")
            .put("systemTtsServiceDiscovery", registered)
            .put("systemTtsService", registration)
            .put("nativeRuntimeAvailable", KokoroNative.isAvailable)
            .put("nativeRuntimeReason", KokoroNative.unavailableReason)
            .put("modelAssets", assetStatus)
            .put("localEngines", engineArray)
    }

    private fun kokoroAssetStatus(context: Context?): JSONObject {
        if (context == null) {
            return JSONObject()
                .put("available", false)
                .put("reason", "Android Context 不可用")
        }
        return try {
            val rootFiles = context.assets.list(KOKORO_ASSET_DIR).orEmpty().toSet()
            val hasModel = rootFiles.contains("model.int8.onnx") ||
                rootFiles.any { it.startsWith("model.int8.onnx.part") }
            val hasVoices = rootFiles.contains("voices.bin") ||
                rootFiles.any { it.startsWith("voices.bin.part") }
            val missing = mutableListOf<String>()
            if (!hasModel) {
                missing.add("model.int8.onnx")
            }
            if (!hasVoices) {
                missing.add("voices.bin")
            }
            listOf("tokens.txt", "lexicon-zh.txt", "phone-zh.fst", "number-zh.fst").forEach { name ->
                if (!rootFiles.contains(name)) {
                    missing.add(name)
                }
            }
            JSONObject()
                .put("available", missing.isEmpty())
                .put("reason", if (missing.isEmpty()) "" else "缺少模型资产：${missing.joinToString(", ")}")
                .put("assetDir", KOKORO_ASSET_DIR)
                .put("hasModel", hasModel)
                .put("hasVoices", hasVoices)
                .put("missing", JSONArray(missing))
        } catch (error: Exception) {
            JSONObject()
                .put("available", false)
                .put("reason", error.message ?: "无法读取本地 TTS 模型资产")
                .put("assetDir", KOKORO_ASSET_DIR)
        }
    }
}
