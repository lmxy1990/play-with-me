package com.playwithme.godot

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.max

internal class MemoryNative private constructor() {
    companion object {
        private const val TAG = "MemoryNative"
        private const val EMBEDDING_DIMENSION = 128
        private var jniLoadError: String? = null
        private var vecLoadError: String? = null

        val isAvailable: Boolean
            get() = jniLoadError == null

        init {
            jniLoadError = try {
                System.loadLibrary("playwithme_memory_jni")
                AndroidDebugLog.d(TAG, "memory JNI library loaded")
                null
            } catch (error: UnsatisfiedLinkError) {
                val message = error.message ?: "memory JNI library is unavailable"
                AndroidDebugLog.d(TAG, "memory JNI load failed: $message", error)
                message
            } catch (error: SecurityException) {
                val message = error.message ?: "memory JNI library cannot be loaded"
                AndroidDebugLog.d(TAG, "memory JNI load blocked: $message", error)
                message
            }
            vecLoadError = try {
                System.loadLibrary("vec0")
                AndroidDebugLog.d(TAG, "sqlite-vec library loaded")
                null
            } catch (error: UnsatisfiedLinkError) {
                val message = error.message ?: "sqlite-vec library is unavailable"
                AndroidDebugLog.d(TAG, "sqlite-vec library load failed: $message", error)
                message
            } catch (error: SecurityException) {
                val message = error.message ?: "sqlite-vec library cannot be loaded"
                AndroidDebugLog.d(TAG, "sqlite-vec library load blocked: $message", error)
                message
            }
        }

        fun status(context: Context, databasePath: String): JSONObject {
            val loadError = jniLoadError
            if (loadError != null) {
                return unavailable(loadError)
            }
            return nativeResult {
                JSONObject(nativeStatus(databasePath, nativeLibraryDir(context)))
            }
        }

        fun rebuildIndexes(
            context: Context,
            databasePath: String,
            scopeJson: String,
            stateJson: String
        ): JSONObject {
            val loadError = jniLoadError
            if (loadError != null) {
                return unavailable(loadError)
            }
            return nativeResult {
                val scope = normalizeScope(JSONObject(scopeJson.ifBlank { "{}" }))
                val scopeKey = storageKey(scope)
                val state = JSONObject(stateJson.ifBlank { "{}" })
                val records = state.optJSONArray("memory_records") ?: JSONArray()
                val eventIds = mutableListOf<String>()
                val eventVectors = mutableListOf<FloatArray>()
                val semanticIds = mutableListOf<String>()
                val semanticTypes = mutableListOf<String>()
                val semanticVectors = mutableListOf<FloatArray>()

                for (i in 0 until records.length()) {
                    val record = records.optJSONObject(i) ?: continue
                    if (record.optString("embedding_status") != "ready") {
                        continue
                    }
                    val status = record.optString("status", "active")
                    if (status == "archived" || status == "forgotten") {
                        continue
                    }
                    val vector = vectorFromRecord(record) ?: continue
                    val memoryId = record.optString("memory_id").trim()
                    if (memoryId.isEmpty()) {
                        continue
                    }
                    when (record.optString("memory_type").trim()) {
                        "episodic" -> {
                            eventIds += memoryId
                            eventVectors += vector
                        }
                        "semantic", "reflection" -> {
                            semanticIds += memoryId
                            semanticTypes += record.optString("memory_type").trim()
                            semanticVectors += vector
                        }
                    }
                }

                JSONObject(
                    nativeRebuild(
                        databasePath,
                        nativeLibraryDir(context),
                        scopeKey,
                        eventIds.toTypedArray(),
                        eventVectors.toTypedArray(),
                        semanticIds.toTypedArray(),
                        semanticTypes.toTypedArray(),
                        semanticVectors.toTypedArray()
                    )
                ).apply {
                    put("event_vector_count", eventIds.size)
                    put("semantic_vector_count", semanticIds.size)
                }
            }
        }

        fun vectorSearch(
            context: Context,
            databasePath: String,
            scopeJson: String,
            queryVectorJson: String,
            requestJson: String
        ): JSONObject {
            val loadError = jniLoadError
            if (loadError != null) {
                return unavailable(loadError)
            }
            return nativeResult {
                val scope = normalizeScope(JSONObject(scopeJson.ifBlank { "{}" }))
                val queryVector = vectorFromJson(JSONArray(queryVectorJson.ifBlank { "[]" }))
                    ?: return@nativeResult error("query_vector_unavailable")
                val request = JSONObject(requestJson.ifBlank { "{}" })
                val eventTopK = topKFor(request, "raw_episodic_vec_top_k_per_query")
                val semanticTopK = topKFor(request, "raw_semantic_hnsw_top_k_per_query")
                JSONObject(
                    nativeSearch(
                        databasePath,
                        nativeLibraryDir(context),
                        storageKey(scope),
                        queryVector,
                        eventTopK,
                        semanticTopK
                    )
                )
            }
        }

        private fun nativeResult(block: () -> JSONObject): JSONObject {
            val result = try {
                block()
            } catch (error: Exception) {
                error(error.message ?: "native_memory_operation_failed")
            }
            return decorate(result)
        }

        private fun decorate(result: JSONObject): JSONObject {
            result.put("jni_loaded", jniLoadError == null)
            result.put("vec0_library_loaded", vecLoadError == null)
            if (vecLoadError != null) {
                result.put("vec0_library_load_error", vecLoadError)
            }
            return result
        }

        private fun unavailable(message: String): JSONObject {
            return decorate(
                JSONObject()
                    .put("ok", false)
                    .put("sqlite_vec_available", false)
                    .put("hnswlib_available", false)
                    .put("native_sqlite_vec_enabled", false)
                    .put("native_hnswlib_enabled", false)
                    .put("error", message)
                    .put("warnings", JSONArray().put("native_memory_jni_unavailable"))
            )
        }

        private fun error(message: String): JSONObject {
            return JSONObject()
                .put("ok", false)
                .put("error", message)
                .put("warnings", JSONArray().put(message))
        }

        private fun nativeLibraryDir(context: Context): String {
            return context.applicationInfo.nativeLibraryDir ?: ""
        }

        private fun topKFor(request: JSONObject, key: String): Int {
            val options = request.optJSONObject("memory_options") ?: JSONObject()
            val budget = request.optJSONObject("budget_plan") ?: JSONObject()
            val defaultTopK = max(
                1,
                request.optInt(
                    "raw_vector_top_k_per_query",
                    options.optInt("raw_vector_top_k_per_query", budget.optInt("final_max_items", 24))
                )
            )
            return max(1, options.optInt(key, request.optInt(key, defaultTopK)))
        }

        private fun vectorFromRecord(record: JSONObject): FloatArray? {
            val embedding = record.optJSONObject("embedding") ?: return null
            val dimension = embedding.optInt("dimension", EMBEDDING_DIMENSION)
            if (dimension != EMBEDDING_DIMENSION) {
                return null
            }
            return vectorFromJson(embedding.optJSONArray("vector") ?: return null)
        }

        private fun vectorFromJson(values: JSONArray): FloatArray? {
            if (values.length() != EMBEDDING_DIMENSION) {
                return null
            }
            val vector = FloatArray(EMBEDDING_DIMENSION)
            for (i in 0 until EMBEDDING_DIMENSION) {
                vector[i] = values.optDouble(i, 0.0).toFloat()
            }
            return vector
        }

        private fun normalizeScope(scope: JSONObject): JSONObject {
            return JSONObject()
                .put("owner_id", nonEmpty(scope.optString("owner_id"), "unknown"))
                .put("game_id", nonEmpty(scope.optString("game_id"), "game"))
                .put("namespace", nonEmpty(scope.optString("namespace"), "session"))
                .put("ruleset_id", scope.optString("ruleset_id").trim())
                .put("room_id", scope.optString("room_id").trim())
        }

        private fun storageKey(scope: JSONObject): String {
            return listOf(
                nonEmpty(scope.optString("owner_id"), "unknown"),
                nonEmpty(scope.optString("game_id"), "game"),
                nonEmpty(scope.optString("ruleset_id"), "-"),
                nonEmpty(scope.optString("room_id"), "-"),
                nonEmpty(scope.optString("namespace"), "session")
            ).joinToString("|")
        }

        private fun nonEmpty(value: String, fallback: String): String {
            val trimmed = value.trim()
            return trimmed.ifEmpty { fallback }
        }

        @JvmStatic
        external fun nativeStatus(databasePath: String, nativeLibraryDir: String): String

        @JvmStatic
        external fun nativeRebuild(
            databasePath: String,
            nativeLibraryDir: String,
            scopeKey: String,
            eventIds: Array<String>,
            eventVectors: Array<FloatArray>,
            semanticIds: Array<String>,
            semanticTypes: Array<String>,
            semanticVectors: Array<FloatArray>
        ): String

        @JvmStatic
        external fun nativeSearch(
            databasePath: String,
            nativeLibraryDir: String,
            scopeKey: String,
            queryVector: FloatArray,
            eventTopK: Int,
            semanticTopK: Int
        ): String
    }
}
