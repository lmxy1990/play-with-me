package com.playwithme.godot

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MemoryNativeDeviceTest {
    @Test
    fun rebuildAndSearchNativeMemoryIndexes() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        context.deleteDatabase("ai_memory.sqlite")
        val database = MemoryDatabase(context)
        val scope = JSONObject()
            .put("owner_id", "device_bot")
            .put("game_id", "bot")
            .put("namespace", "profile")
            .put("ruleset_id", "")
            .put("room_id", "device")
        val eventVector = unitVector(0)
        val semanticVector = unitVector(1)
        val state = JSONObject()
            .put(
                "memory_records",
                JSONArray()
                    .put(memoryRecord("event_device_1", "episodic", eventVector))
                    .put(memoryRecord("semantic_device_1", "semantic", semanticVector))
            )

        val rebuild = database.nativeRebuildIndexes(scope.toString(), state.toString())
        assertTrue(rebuild.toString(), rebuild.getBoolean("ok"))
        assertTrue(rebuild.toString(), rebuild.getBoolean("native_sqlite_vec_enabled"))
        assertTrue(rebuild.toString(), rebuild.getBoolean("native_hnswlib_enabled"))

        val searchRequest = JSONObject()
            .put("raw_episodic_vec_top_k_per_query", 4)
            .put("raw_semantic_hnsw_top_k_per_query", 4)
        val search = database.nativeVectorSearch(scope.toString(), eventVector.toString(), searchRequest.toString())
        assertTrue(search.toString(), search.getBoolean("ok"))
        val ids = mutableSetOf<String>()
        val items = search.getJSONArray("items")
        for (i in 0 until items.length()) {
            ids.add(items.getJSONObject(i).getString("memory_id"))
        }
        assertTrue(search.toString(), ids.contains("event_device_1"))
        assertEquals(1, rebuild.getInt("event_vector_count"))
        assertEquals(1, rebuild.getInt("semantic_vector_count"))
    }

    private fun memoryRecord(memoryId: String, memoryType: String, vector: JSONArray): JSONObject {
        return JSONObject()
            .put("memory_id", memoryId)
            .put("memory_type", memoryType)
            .put("status", "active")
            .put("embedding_status", "ready")
            .put(
                "embedding",
                JSONObject()
                    .put("dimension", 128)
                    .put("vector", vector)
            )
    }

    private fun unitVector(slot: Int): JSONArray {
        val vector = JSONArray()
        for (i in 0 until 128) {
            vector.put(if (i == slot) 1.0 else 0.0)
        }
        return vector
    }
}
