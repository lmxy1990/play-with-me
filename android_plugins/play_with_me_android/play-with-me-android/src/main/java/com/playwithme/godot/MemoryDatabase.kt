package com.playwithme.godot

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONArray
import org.json.JSONObject

class MemoryDatabase(private val context: Context) : SQLiteOpenHelper(
    context,
    DATABASE_NAME,
    null,
    SCHEMA_VERSION
) {
    override fun onConfigure(db: SQLiteDatabase) {
        super.onConfigure(db)
        db.setForeignKeyConstraintsEnabled(true)
    }

    override fun onCreate(db: SQLiteDatabase) {
        AndroidDebugLog.d(TAG, "onCreate schemaVersion=$SCHEMA_VERSION")
        createSchema(db)
        migrateMemoryState(db)
        migrateModelConfigs(db)
        migrateVoiceConfigs(db)
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        AndroidDebugLog.d(TAG, "onUpgrade oldVersion=$oldVersion newVersion=$newVersion")
        if (oldVersion < SCHEMA_VERSION) {
            createSchema(db)
            migrateMemoryState(db)
            migrateModelConfigs(db)
            migrateVoiceConfigs(db)
        }
    }

    fun loadState(scopeJson: String, tokenBudget: Int = TOKEN_BUDGET): JSONObject {
        val scope = normalizeScope(JSONObject(scopeJson))
        val key = storageKey(scope)
        val db = readableDatabase
        val entries = JSONArray()
        db.query(
            "memory_entries",
            null,
            "scope_key = ?",
            arrayOf(key),
            null,
            null,
            "created_at_ms ASC, id ASC"
        ).use { cursor ->
            while (cursor.moveToNext()) {
                entries.put(entryFromCursor(cursor))
            }
        }

        val summaries = JSONArray()
        db.query(
            "memory_round_summaries",
            null,
            "scope_key = ?",
            arrayOf(key),
            null,
            null,
            "day_number ASC, id ASC"
        ).use { cursor ->
            while (cursor.moveToNext()) {
                summaries.put(summaryFromCursor(cursor))
            }
        }

        val longTermSummary = db.query(
            "long_term_memories",
            arrayOf("summary"),
            "scope_key = ?",
            arrayOf(key),
            null,
            null,
            null,
            "1"
        ).use { cursor ->
            if (cursor.moveToFirst()) {
                cursor.stringOrEmpty("summary")
            } else {
                ""
            }
        }

        val personaSnapshot = db.query(
            "memory_persona_snapshots",
            null,
            "scope_key = ?",
            arrayOf(key),
            null,
            null,
            null,
            "1"
        ).use { cursor ->
            if (cursor.moveToFirst()) {
                personaSnapshotFromCursor(cursor)
            } else {
                JSONObject()
            }
        }

        val memoryRecords = JSONArray()
        db.query(
            "memory_records",
            null,
            "scope_key = ?",
            arrayOf(key),
            null,
            null,
            "updated_at_ms ASC, id ASC"
        ).use { cursor ->
            while (cursor.moveToNext()) {
                memoryRecords.put(memoryRecordFromCursor(cursor))
            }
        }

        val metadata = stateMetadataForScope(db, scope)
        return JSONObject()
            .put("scope", scope)
            .put("memory_schema_version", metadata.optInt("memory_schema_version", MEMORY_SCHEMA_VERSION))
            .put("record_schema_version", metadata.optInt("record_schema_version", RECORD_SCHEMA_VERSION))
            .put("context_schema_version", metadata.optInt("context_schema_version", CONTEXT_SCHEMA_VERSION))
            .put("read_only", metadata.optBoolean("read_only", false))
            .put("migration_report", metadata.optJSONObject("migration_report") ?: defaultMigrationReport())
            .put("persona_snapshot", personaSnapshot)
            .put("memory_records", memoryRecords)
            .put("relationship_state", metadata.optJSONObject("relationship_state") ?: JSONObject())
            .put("conflict_records", metadata.optJSONArray("conflict_records") ?: JSONArray())
            .put("vector_index", metadata.optJSONObject("vector_index") ?: JSONObject())
            .put("semantic_hnsw_graph", metadata.optJSONObject("semantic_hnsw_graph") ?: JSONObject())
            .put("recent_entries", entries)
            .put("round_summaries", summaries)
            .put("long_term_memory_summary", longTermSummary)
            .put("token_budget", metadata.optInt("token_budget", tokenBudget))
    }

    fun saveState(scopeJson: String, stateJson: String): JSONObject {
        val scope = normalizeScope(JSONObject(scopeJson))
        val state = JSONObject(stateJson)
        val now = System.currentTimeMillis()
        val db = writableDatabase
        db.transaction {
            upsertScope(this, scope, now)
            delete("memory_persona_snapshots", "scope_key = ?", arrayOf(storageKey(scope)))
            val persona = state.optJSONObject("persona_snapshot") ?: JSONObject()
            if (persona.optString("content").trim().isNotEmpty()) {
                insertWithOnConflict(
                    "memory_persona_snapshots",
                    null,
                    personaSnapshotColumns(scope, persona, now),
                    SQLiteDatabase.CONFLICT_REPLACE
                )
            }
            delete("memory_records", "scope_key = ?", arrayOf(storageKey(scope)))
            val records = state.optJSONArray("memory_records") ?: JSONArray()
            val recordColumns = tableColumns(this, "memory_records")
            for (i in 0 until records.length()) {
                val record = records.optJSONObject(i) ?: continue
                if (record.optString("content").trim().isEmpty() || record.optString("memory_type").trim().isEmpty()) {
                    continue
                }
                insertWithOnConflict(
                    "memory_records",
                    null,
                    memoryRecordColumns(scope, record, now, recordColumns),
                    SQLiteDatabase.CONFLICT_REPLACE
                )
            }
            insertWithOnConflict(
                "memory_state_metadata",
                null,
                stateMetadataColumns(scope, state, now),
                SQLiteDatabase.CONFLICT_REPLACE
            )
        }
        return ok()
    }

    fun append(scopeJson: String, entryJson: String): JSONObject {
        val scope = normalizeScope(JSONObject(scopeJson))
        val entry = JSONObject(entryJson)
        val content = entry.optString("content").trim()
        if (content.isEmpty()) {
            return ok()
        }
        val createdAtMs = secondsToMillis(entry.optDouble("created_at", nowSeconds()))
        val db = writableDatabase
        db.transaction {
            upsertScope(this, scope, System.currentTimeMillis())
            insert(
                "memory_entries",
                null,
                scopeColumns(scope).apply {
                    put("visibility", visibility(entry.optString("visibility", "public")))
                    put("content", content)
                    put("metadata_json", entry.optJSONObject("metadata")?.toString() ?: "{}")
                    put("created_at_ms", createdAtMs)
                }
            )
        }
        return ok()
    }

    fun compact(scopeJson: String, requestJson: String): JSONObject {
        val scope = normalizeScope(JSONObject(scopeJson))
        val request = JSONObject(requestJson)
        val summary = JSONObject()
            .put("day_number", request.optInt("day_number"))
            .put("phase", request.optString("phase"))
            .put("public_summary", request.optString("public_summary"))
            .put("private_summary", request.optString("private_summary"))
            .put("decision_summary", request.optString("decision_summary"))
            .put("suspicion_summary", request.optString("suspicion_summary"))
            .put("strategy_summary", request.optString("strategy_summary"))
        val now = System.currentTimeMillis()
        val db = writableDatabase
        db.transaction {
            upsertScope(this, scope, now)
            insert(
                "memory_round_summaries",
                null,
                scopeColumns(scope).apply {
                    put("day_number", summary.optInt("day_number"))
                    put("phase", summary.optString("phase"))
                    put("public_summary", summary.optString("public_summary"))
                    put("private_summary", summary.optString("private_summary"))
                    put("decision_summary", summary.optString("decision_summary"))
                    put("suspicion_summary", summary.optString("suspicion_summary"))
                    put("strategy_summary", summary.optString("strategy_summary"))
                    put("created_at_ms", now)
                }
            )
            delete("memory_entries", "scope_key = ?", arrayOf(storageKey(scope)))
        }
        return JSONObject()
            .put("ok", true)
            .put("summary", summary)
    }

    fun saveLongTerm(scopeJson: String, summary: String, userApproved: Boolean): JSONObject {
        if (!userApproved) {
            return ok()
        }
        val scope = normalizeScope(JSONObject(scopeJson))
        val now = System.currentTimeMillis()
        val db = writableDatabase
        db.transaction {
            upsertScope(this, scope, now)
            insertWithOnConflict(
                "long_term_memories",
                null,
                scopeColumns(scope).apply {
                    put("summary", summary)
                    put("updated_at_ms", now)
                },
                SQLiteDatabase.CONFLICT_REPLACE
            )
        }
        return ok()
    }

    fun deleteScope(scopeJson: String): JSONObject {
        val scope = normalizeScope(JSONObject(scopeJson))
        writableDatabase.transaction {
            deleteWhere(this, "scope_key = ?", arrayOf(storageKey(scope)))
        }
        return ok()
    }

    fun discardSession(scopeJson: String): JSONObject {
        val scope = normalizeScope(JSONObject(scopeJson))
        if (scope.optString("namespace") != "session") {
            return ok()
        }
        writableDatabase.transaction {
            deleteWhere(this, "scope_key = ?", arrayOf(storageKey(scope)))
        }
        return ok()
    }

    fun listScopes(ownerId: String, gameId: String, namespace: String): JSONArray {
        val clauses = mutableListOf<String>()
        val args = mutableListOf<String>()
        if (ownerId.isNotBlank()) {
            clauses += "owner_id = ?"
            args += ownerId.trim()
        }
        if (gameId.isNotBlank()) {
            clauses += "game_id = ?"
            args += gameId.trim()
        }
        if (namespace.isNotBlank()) {
            clauses += "namespace = ?"
            args += namespace.trim()
        }

        val scopes = JSONArray()
        readableDatabase.query(
            "memory_scopes",
            null,
            clauses.takeIf { it.isNotEmpty() }?.joinToString(" AND "),
            args.takeIf { it.isNotEmpty() }?.toTypedArray(),
            null,
            null,
            "updated_at_ms DESC"
        ).use { cursor ->
            while (cursor.moveToNext()) {
                scopes.put(scopeFromCursor(cursor))
            }
        }
        return scopes
    }

    fun deleteOwnerMemory(ownerId: String, gameId: String): JSONObject {
        val clauses = mutableListOf("owner_id = ?")
        val args = mutableListOf(ownerId)
        if (gameId.isNotBlank()) {
            clauses += "game_id = ?"
            args += gameId.trim()
        }
        writableDatabase.transaction {
            deleteWhere(this, clauses.joinToString(" AND "), args.toTypedArray())
        }
        return ok()
    }

    fun listIndexNames(): JSONArray {
        val indexes = JSONArray()
        readableDatabase.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'index' " +
                "AND name NOT LIKE 'sqlite_autoindex%' ORDER BY name",
            null
        ).use { cursor ->
            while (cursor.moveToNext()) {
                indexes.put(cursor.getString(0))
            }
        }
        return indexes
    }

    fun indexStatus(): JSONObject {
        val db = readableDatabase
        val indexNames = listIndexNames()
        val recordCount = countRows(db, "memory_records")
        val readyCount = countRows(db, "memory_records", "embedding_status = ?", arrayOf("ready"))
        val pendingCount = countRows(db, "memory_records", "embedding_status = ?", arrayOf("pending"))
        val failedCount = countRows(db, "memory_records", "embedding_status = ?", arrayOf("failed"))
        val staleCount = countRows(db, "memory_records", "embedding_status = ?", arrayOf("stale"))
        val eventVectorCount = countRows(
            db,
            "memory_records",
            "memory_type = ? AND embedding_status = ?",
            arrayOf("episodic", "ready")
        )
        val semanticVectorCount = countRows(
            db,
            "memory_records",
            "memory_type IN (?, ?) AND embedding_status = ?",
            arrayOf("semantic", "reflection", "ready")
        )
        val nativeStatus = MemoryNative.status(context, databasePathForNative())
        val nativeWarnings = nativeStatus.optJSONArray("warnings") ?: JSONArray()
        val nativeSqliteAvailable = nativeStatus.optBoolean("sqlite_vec_available", false)
        val nativeHnswAvailable = nativeStatus.optBoolean("hnswlib_available", false)
        val nativeSqliteEnabled = nativeSqliteAvailable && eventVectorCount > 0
        val nativeHnswEnabled = nativeHnswAvailable && semanticVectorCount > 0
        val warnings = JSONArray()
        for (i in 0 until nativeWarnings.length()) {
            warnings.put(nativeWarnings.optString(i))
        }
        if (!nativeSqliteAvailable) {
            warnings.put("native_sqlite_vec_unavailable")
        }
        if (!nativeHnswAvailable) {
            warnings.put("native_hnswlib_unavailable")
        }
        return ok()
            .put("sqlite_database_enabled", true)
            .put("sqlite_open_helper_schema_version", SCHEMA_VERSION)
            .put("memory_schema_version", MEMORY_SCHEMA_VERSION)
            .put("record_schema_version", RECORD_SCHEMA_VERSION)
            .put("context_schema_version", CONTEXT_SCHEMA_VERSION)
            .put("native_sqlite_vec_enabled", nativeSqliteEnabled)
            .put("native_hnswlib_enabled", nativeHnswEnabled)
            .put("sqlite_vec_event_enabled", nativeSqliteEnabled)
            .put("hnsw_semantic_enabled", nativeHnswEnabled)
            .put("vector_backend", if (nativeSqliteEnabled || nativeHnswEnabled) "android_native_sqlite_vec_hnswlib" else "godot_local_vector_persisted_in_android_sqlite")
            .put("native_vector_backend", if (nativeSqliteAvailable || nativeHnswAvailable) "sqlite-vec+hnswlib" else "none")
            .put("memory_record_count", recordCount)
            .put("ready_embedding_count", readyCount)
            .put("pending_embedding_count", pendingCount)
            .put("failed_embedding_count", failedCount)
            .put("stale_index_count", staleCount)
            .put("event_vector_count", eventVectorCount)
            .put("semantic_vector_count", semanticVectorCount)
            .put("native_index_names", indexNames)
            .put("native_backend_status", nativeStatus)
            .put("warnings", warnings)
    }

    fun nativeRebuildIndexes(scopeJson: String, stateJson: String): JSONObject {
        writableDatabase
        return MemoryNative.rebuildIndexes(context, databasePathForNative(), scopeJson, stateJson)
    }

    fun nativeVectorSearch(scopeJson: String, queryVectorJson: String, requestJson: String): JSONObject {
        readableDatabase
        return MemoryNative.vectorSearch(context, databasePathForNative(), scopeJson, queryVectorJson, requestJson)
    }

    fun listModelConfigs(): JSONArray {
        val models = JSONArray()
        readableDatabase.query(
            "model_configs",
            null,
            null,
            null,
            null,
            null,
            "id ASC"
        ).use { cursor ->
            while (cursor.moveToNext()) {
                models.put(modelConfigFromCursor(cursor))
            }
        }
        return models
    }

    fun saveModelConfig(configJson: String): JSONObject {
        val config = JSONObject(configJson)
        val modelName = nonEmpty(config.optString("model"), config.optString("name"))
        if (modelName.isBlank()) {
            return error("模型名不能为空")
        }
        val endpoint = config.optString("endpoint").trim()
        if (endpoint.isBlank()) {
            return error("BaseUrl 不能为空")
        }
        val formtAdapter = normalizeFormtAdapter(config.optString("formt_adapter"))
        val reasonAdapter = normalizeReasonAdapter(config.optString("reason_adapter"))
        AndroidDebugLog.d(
            TAG,
            "saveModelConfig request id=${config.optInt("id", 0)} provider=${nonEmpty(config.optString("provider"), "openai_compatible")} endpoint=$endpoint model=$modelName reasoning=${config.optBoolean("reasoning", false)} formt_adapter=$formtAdapter reason_adapter=$reasonAdapter"
        )
        if (!isSavableFormtAdapter(formtAdapter)) {
            return error("模型适配器必须先通过测试后保存")
        }
        if (!isSavableReasonAdapter(config.optBoolean("reasoning", false), reasonAdapter)) {
            return error("思考兼容必须先通过测试后保存")
        }
        val now = System.currentTimeMillis()
        val id = config.optInt("id", 0)
        val db = writableDatabase
        val values = modelConfigColumns(db, config, modelName, endpoint, formtAdapter, reasonAdapter).apply {
            put("updated_at_ms", now)
        }
        db.transaction {
            if (id > 0) {
                val updateCount = update("model_configs", values, "id = ?", arrayOf(id.toString()))
                if (updateCount > 0) {
                    return@transaction
                }
            }
            values.put("created_at_ms", now)
            if (id > 0) {
                values.put("id", id)
            }
            val insertedId = insertWithOnConflict(
                "model_configs",
                null,
                values,
                SQLiteDatabase.CONFLICT_IGNORE
            )
            if (insertedId < 0) {
                val existingId = findModelConfigId(db, values.getAsString("provider"), endpoint, modelName)
                if (existingId > 0) {
                    values.remove("id")
                    values.remove("created_at_ms")
                    update("model_configs", values, "id = ?", arrayOf(existingId.toString()))
                }
            }
        }
        val savedId = if (id > 0) id else findModelConfigId(db, values.getAsString("provider"), endpoint, modelName)
        var model = modelConfigById(db, savedId)
        if (model == null) {
            model = modelConfigById(db, findModelConfigId(db, values.getAsString("provider"), endpoint, modelName))
        }
        return if (model != null) {
            AndroidDebugLog.d(
                TAG,
                "saveModelConfig result id=${model.optInt("id", 0)} provider=${model.optString("provider")} endpoint=${model.optString("endpoint")} model=${model.optString("model")} reasoning=${model.optBoolean("reasoning", false)} formt_adapter=${model.optString("formt_adapter")} reason_adapter=${model.optString("reason_adapter")}"
            )
            ok().put("model", model)
        } else {
            error("模型配置保存失败")
        }
    }

    fun deleteModelConfig(id: Int): JSONObject {
        if (id <= 0) {
            return ok()
        }
        AndroidDebugLog.d(TAG, "deleteModelConfig id=$id")
        writableDatabase.delete("model_configs", "id = ?", arrayOf(id.toString()))
        return ok()
    }

    fun listVoiceConfigs(): JSONArray {
        val voices = JSONArray()
        readableDatabase.query(
            "voice_configs",
            null,
            null,
            null,
            null,
            null,
            "id ASC"
        ).use { cursor ->
            while (cursor.moveToNext()) {
                voices.put(voiceConfigFromCursor(cursor))
            }
        }
        AndroidDebugLog.d(TAG, "listVoiceConfigs count=${voices.length()}")
        return voices
    }

    fun saveVoiceConfig(configJson: String): JSONObject {
        val config = JSONObject(configJson)
        val name = nonEmpty(config.optString("name"), "未命名声音")
        val engine = config.optString("engine", "system").trim()
        if (engine.isBlank()) {
            return error("声音引擎不能为空")
        }
        val now = System.currentTimeMillis()
        val id = config.optInt("id", 0)
        val db = writableDatabase
        val values = voiceConfigColumns(config, name, engine).apply {
            put("updated_at_ms", now)
        }
        var savedId = id
        AndroidDebugLog.d(
            TAG,
            "saveVoiceConfig request id=$id name=$name engine=$engine voice=${config.optString("voice").ifBlank { "<default>" }} enabled=${config.optBoolean("enabled", true)} active=${config.optBoolean("active", false)}"
        )
        db.transaction {
            var updatedExisting = false
            if (id > 0) {
                val updateCount = update("voice_configs", values, "id = ?", arrayOf(id.toString()))
                if (updateCount > 0) {
                    savedId = id
                    updatedExisting = true
                }
            }
            if (!updatedExisting) {
                values.put("created_at_ms", now)
                if (id > 0) {
                    values.put("id", id)
                }
                val insertedId = insert("voice_configs", null, values)
                if (insertedId > 0) {
                    savedId = insertedId.toInt()
                }
            }
            if ((values.getAsInteger("active") ?: 0) != 0 && savedId > 0) {
                activateOnlyVoiceConfig(this, savedId)
            } else {
                enforceUniqueActiveVoiceConfig(this)
            }
        }
        val voice = voiceConfigById(db, savedId)
        return if (voice != null) {
            AndroidDebugLog.d(TAG, "saveVoiceConfig ok id=$savedId")
            ok().put("voice", voice)
        } else {
            AndroidDebugLog.d(TAG, "saveVoiceConfig failed id=$savedId")
            error("声音配置保存失败")
        }
    }

    fun deleteVoiceConfig(id: Int): JSONObject {
        if (id <= 0) {
            return ok()
        }
        val deleted = writableDatabase.delete("voice_configs", "id = ?", arrayOf(id.toString()))
        AndroidDebugLog.d(TAG, "deleteVoiceConfig id=$id deleted=$deleted")
        return ok()
    }

    private fun createSchema(db: SQLiteDatabase) {
        db.execSQL(
            """
CREATE TABLE IF NOT EXISTS memory_scopes (
  scope_key TEXT PRIMARY KEY,
  owner_id TEXT NOT NULL,
  game_id TEXT NOT NULL,
  namespace TEXT NOT NULL,
  ruleset_id TEXT,
  room_id TEXT,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
)
            """.trimIndent()
        )
        db.execSQL(
            """
CREATE TABLE IF NOT EXISTS memory_entries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  scope_key TEXT NOT NULL,
  owner_id TEXT NOT NULL,
  game_id TEXT NOT NULL,
  namespace TEXT NOT NULL,
  ruleset_id TEXT,
  room_id TEXT,
  visibility TEXT NOT NULL,
  content TEXT NOT NULL,
  metadata_json TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  FOREIGN KEY(scope_key) REFERENCES memory_scopes(scope_key) ON DELETE CASCADE
)
            """.trimIndent()
        )
        db.execSQL(
            """
CREATE TABLE IF NOT EXISTS memory_round_summaries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  scope_key TEXT NOT NULL,
  owner_id TEXT NOT NULL,
  game_id TEXT NOT NULL,
  namespace TEXT NOT NULL,
  ruleset_id TEXT,
  room_id TEXT,
  day_number INTEGER NOT NULL,
  phase TEXT NOT NULL,
  public_summary TEXT NOT NULL,
  private_summary TEXT NOT NULL,
  decision_summary TEXT NOT NULL,
  suspicion_summary TEXT NOT NULL,
  strategy_summary TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  FOREIGN KEY(scope_key) REFERENCES memory_scopes(scope_key) ON DELETE CASCADE
)
            """.trimIndent()
        )
        db.execSQL(
            """
CREATE TABLE IF NOT EXISTS long_term_memories (
  scope_key TEXT PRIMARY KEY,
  owner_id TEXT NOT NULL,
  game_id TEXT NOT NULL,
  namespace TEXT NOT NULL,
  ruleset_id TEXT,
  room_id TEXT,
  summary TEXT NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  FOREIGN KEY(scope_key) REFERENCES memory_scopes(scope_key) ON DELETE CASCADE
)
            """.trimIndent()
        )
        db.execSQL(
            """
CREATE TABLE IF NOT EXISTS memory_persona_snapshots (
  scope_key TEXT PRIMARY KEY,
  owner_id TEXT NOT NULL,
  game_id TEXT NOT NULL,
  namespace TEXT NOT NULL,
  ruleset_id TEXT,
  room_id TEXT,
  memory_id TEXT NOT NULL,
  bot_id TEXT NOT NULL,
  content TEXT NOT NULL,
  structured_payload_json TEXT NOT NULL,
  visibility TEXT NOT NULL,
  source TEXT NOT NULL,
  status TEXT NOT NULL,
  importance REAL NOT NULL,
  confidence REAL NOT NULL,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  evidence_json TEXT NOT NULL,
  FOREIGN KEY(scope_key) REFERENCES memory_scopes(scope_key) ON DELETE CASCADE
)
            """.trimIndent()
        )
        db.execSQL(
            """
CREATE TABLE IF NOT EXISTS memory_records (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  record_schema_version INTEGER NOT NULL DEFAULT 1,
  memory_id TEXT NOT NULL,
  scope_key TEXT NOT NULL,
  owner_id TEXT NOT NULL,
  game_id TEXT NOT NULL,
  namespace TEXT NOT NULL,
  ruleset_id TEXT,
  room_id TEXT,
  bot_id TEXT NOT NULL,
  memory_type TEXT NOT NULL,
  domain_id TEXT NOT NULL,
  session_id TEXT NOT NULL,
  instance_id TEXT NOT NULL,
  subject_id TEXT NOT NULL,
  subject_type TEXT NOT NULL,
  content TEXT NOT NULL,
  structured_payload_json TEXT NOT NULL,
  visibility TEXT NOT NULL,
  source TEXT NOT NULL,
  importance REAL NOT NULL,
  confidence REAL NOT NULL,
  status TEXT NOT NULL,
  conflict_status TEXT NOT NULL DEFAULT '',
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  last_accessed_at_ms INTEGER NOT NULL,
  expires_at_ms INTEGER NOT NULL,
  evidence_json TEXT NOT NULL,
  metadata_json TEXT NOT NULL,
  embedding_status TEXT NOT NULL,
  embedding_version TEXT NOT NULL DEFAULT '',
  embedding_json TEXT NOT NULL DEFAULT '{}',
  UNIQUE(scope_key, memory_id),
  FOREIGN KEY(scope_key) REFERENCES memory_scopes(scope_key) ON DELETE CASCADE
)
            """.trimIndent()
        )
        db.execSQL(
            """
CREATE TABLE IF NOT EXISTS memory_state_metadata (
  scope_key TEXT PRIMARY KEY,
  owner_id TEXT NOT NULL,
  game_id TEXT NOT NULL,
  namespace TEXT NOT NULL,
  ruleset_id TEXT,
  room_id TEXT,
  memory_schema_version INTEGER NOT NULL DEFAULT 1,
  record_schema_version INTEGER NOT NULL DEFAULT 1,
  context_schema_version INTEGER NOT NULL DEFAULT 1,
  read_only INTEGER NOT NULL DEFAULT 0,
  migration_report_json TEXT NOT NULL DEFAULT '{}',
  relationship_state_json TEXT NOT NULL DEFAULT '{}',
  conflict_records_json TEXT NOT NULL DEFAULT '[]',
  vector_index_json TEXT NOT NULL DEFAULT '{}',
  semantic_hnsw_graph_json TEXT NOT NULL DEFAULT '{}',
  token_budget INTEGER NOT NULL DEFAULT 4000,
  updated_at_ms INTEGER NOT NULL,
  FOREIGN KEY(scope_key) REFERENCES memory_scopes(scope_key) ON DELETE CASCADE
)
            """.trimIndent()
        )
        db.execSQL(
            """
CREATE TABLE IF NOT EXISTS model_configs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  model TEXT NOT NULL,
  provider TEXT NOT NULL,
  endpoint TEXT NOT NULL,
  api_key TEXT NOT NULL DEFAULT '',
  context_window_tokens INTEGER NOT NULL,
  max_context INTEGER NOT NULL DEFAULT 262144,
  max_output INTEGER NOT NULL DEFAULT 4096,
  temperature REAL NOT NULL DEFAULT 0.6,
  reasoning INTEGER NOT NULL DEFAULT 0,
  formt_adapter TEXT NOT NULL DEFAULT 'auto',
  reason_adapter TEXT NOT NULL DEFAULT 'auto',
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
)
            """.trimIndent()
        )
        db.execSQL(
            """
CREATE TABLE IF NOT EXISTS voice_configs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  engine TEXT NOT NULL,
  gender TEXT NOT NULL DEFAULT '女声',
  voice TEXT NOT NULL DEFAULT '',
  speed TEXT NOT NULL DEFAULT '0.90',
  pitch TEXT NOT NULL DEFAULT '1.00',
  volume TEXT NOT NULL DEFAULT '1.00',
  enabled INTEGER NOT NULL DEFAULT 1,
  active INTEGER NOT NULL DEFAULT 0,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
)
            """.trimIndent()
        )
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS idx_memory_scopes_owner_game_namespace " +
                "ON memory_scopes(owner_id, game_id, namespace)"
        )
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS idx_memory_scopes_owner_namespace " +
                "ON memory_scopes(owner_id, namespace)"
        )
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS idx_memory_entries_scope_created " +
                "ON memory_entries(scope_key, created_at_ms, id)"
        )
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS idx_memory_entries_owner_game_namespace " +
                "ON memory_entries(owner_id, game_id, namespace)"
        )
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS idx_memory_entries_room_game " +
                "ON memory_entries(room_id, game_id)"
        )
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS idx_memory_summaries_scope_round " +
                "ON memory_round_summaries(scope_key, day_number, id)"
        )
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS idx_memory_summaries_owner_game_namespace " +
                "ON memory_round_summaries(owner_id, game_id, namespace)"
        )
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS idx_long_term_owner_game_namespace " +
                "ON long_term_memories(owner_id, game_id, namespace)"
        )
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS idx_memory_records_scope_type_status " +
                "ON memory_records(scope_key, memory_type, status)"
        )
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS idx_memory_records_owner_type_status " +
                "ON memory_records(owner_id, memory_type, status)"
        )
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS idx_memory_records_subject " +
                "ON memory_records(owner_id, subject_id, subject_type)"
        )
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS idx_memory_records_importance_confidence " +
                "ON memory_records(owner_id, importance, confidence)"
        )
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS idx_voice_configs_engine_enabled " +
                "ON voice_configs(engine, enabled)"
        )
        enforceUniqueActiveVoiceConfig(db)
    }

    private fun migrateMemoryState(db: SQLiteDatabase) {
        val recordColumns = tableColumns(db, "memory_records")
        if (recordColumns.isNotEmpty()) {
            val additions = listOf(
                "record_schema_version" to "INTEGER NOT NULL DEFAULT $RECORD_SCHEMA_VERSION",
                "conflict_status" to "TEXT NOT NULL DEFAULT ''",
                "embedding_json" to "TEXT NOT NULL DEFAULT '{}'"
            )
            additions.forEach { (column, definition) ->
                if (!recordColumns.contains(column)) {
                    AndroidDebugLog.d(TAG, "migrateMemoryState add memory_records.$column")
                    db.execSQL("ALTER TABLE memory_records ADD COLUMN $column $definition")
                }
            }
        }
        db.execSQL(
            """
CREATE TABLE IF NOT EXISTS memory_state_metadata (
  scope_key TEXT PRIMARY KEY,
  owner_id TEXT NOT NULL,
  game_id TEXT NOT NULL,
  namespace TEXT NOT NULL,
  ruleset_id TEXT,
  room_id TEXT,
  memory_schema_version INTEGER NOT NULL DEFAULT 1,
  record_schema_version INTEGER NOT NULL DEFAULT 1,
  context_schema_version INTEGER NOT NULL DEFAULT 1,
  read_only INTEGER NOT NULL DEFAULT 0,
  migration_report_json TEXT NOT NULL DEFAULT '{}',
  relationship_state_json TEXT NOT NULL DEFAULT '{}',
  conflict_records_json TEXT NOT NULL DEFAULT '[]',
  vector_index_json TEXT NOT NULL DEFAULT '{}',
  semantic_hnsw_graph_json TEXT NOT NULL DEFAULT '{}',
  token_budget INTEGER NOT NULL DEFAULT 4000,
  updated_at_ms INTEGER NOT NULL,
  FOREIGN KEY(scope_key) REFERENCES memory_scopes(scope_key) ON DELETE CASCADE
)
            """.trimIndent()
        )
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS idx_memory_records_embedding_status " +
                "ON memory_records(owner_id, memory_type, embedding_status)"
        )
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS idx_memory_records_conflict_status " +
                "ON memory_records(owner_id, conflict_status)"
        )
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS idx_memory_state_metadata_owner_game_namespace " +
                "ON memory_state_metadata(owner_id, game_id, namespace)"
        )
    }

    private fun migrateModelConfigs(db: SQLiteDatabase) {
        val columns = tableColumns(db, "model_configs")
        if (columns.isEmpty()) {
            return
        }
        if (!columns.contains("model")) {
            db.execSQL("ALTER TABLE model_configs ADD COLUMN model TEXT NOT NULL DEFAULT ''")
            if (columns.contains("name")) {
                db.execSQL("UPDATE model_configs SET model = name WHERE model = ''")
            }
        }
        if (!columns.contains("max_context")) {
            db.execSQL("ALTER TABLE model_configs ADD COLUMN max_context INTEGER NOT NULL DEFAULT 262144")
            if (columns.contains("max_token")) {
                db.execSQL("UPDATE model_configs SET max_context = max_token WHERE max_token > 0")
            }
        }
        if (!columns.contains("max_output")) {
            db.execSQL("ALTER TABLE model_configs ADD COLUMN max_output INTEGER NOT NULL DEFAULT 4096")
            if (columns.contains("max_output_tokens")) {
                db.execSQL(
                    "UPDATE model_configs SET max_output = max_output_tokens " +
                        "WHERE max_output = 4096 AND max_output_tokens > 0 AND max_output_tokens <= 65536"
                )
            }
        }
        if (columns.contains("max_output") || columns.contains("max_output_tokens")) {
            db.execSQL(
                "UPDATE model_configs SET max_output = 4096 " +
                    "WHERE max_output <= 0 OR max_output > 65536 OR (max_context > 0 AND max_output = max_context)"
            )
        }
        if (!columns.contains("reasoning")) {
            db.execSQL("ALTER TABLE model_configs ADD COLUMN reasoning INTEGER NOT NULL DEFAULT 0")
        }
        if (!columns.contains("formt_adapter")) {
            db.execSQL("ALTER TABLE model_configs ADD COLUMN formt_adapter TEXT NOT NULL DEFAULT 'auto'")
        }
        if (!columns.contains("reason_adapter")) {
            db.execSQL("ALTER TABLE model_configs ADD COLUMN reason_adapter TEXT NOT NULL DEFAULT 'auto'")
        }
        db.execSQL("DROP INDEX IF EXISTS idx_model_configs_provider_endpoint_name")
        db.execSQL(
            "CREATE UNIQUE INDEX IF NOT EXISTS idx_model_configs_provider_endpoint_model " +
                "ON model_configs(provider, endpoint, model)"
        )
    }

    private fun migrateVoiceConfigs(db: SQLiteDatabase) {
        val columns = tableColumns(db, "voice_configs")
        if (columns.isEmpty()) {
            return
        }
        val additions = listOf(
            "name" to "TEXT NOT NULL DEFAULT '未命名声音'",
            "engine" to "TEXT NOT NULL DEFAULT 'system'",
            "gender" to "TEXT NOT NULL DEFAULT '女声'",
            "voice" to "TEXT NOT NULL DEFAULT ''",
            "speed" to "TEXT NOT NULL DEFAULT '0.90'",
            "pitch" to "TEXT NOT NULL DEFAULT '1.00'",
            "volume" to "TEXT NOT NULL DEFAULT '1.00'",
            "enabled" to "INTEGER NOT NULL DEFAULT 1",
            "active" to "INTEGER NOT NULL DEFAULT 0",
            "created_at_ms" to "INTEGER NOT NULL DEFAULT 0",
            "updated_at_ms" to "INTEGER NOT NULL DEFAULT 0"
        )
        additions.forEach { (column, definition) ->
            if (!columns.contains(column)) {
                AndroidDebugLog.d(TAG, "migrateVoiceConfigs add column=$column")
                db.execSQL("ALTER TABLE voice_configs ADD COLUMN $column $definition")
            }
        }
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS idx_voice_configs_engine_enabled " +
                "ON voice_configs(engine, enabled)"
        )
    }

    private fun upsertScope(db: SQLiteDatabase, scope: JSONObject, now: Long) {
        db.insertWithOnConflict(
            "memory_scopes",
            null,
            scopeColumns(scope).apply {
                put("created_at_ms", now)
                put("updated_at_ms", now)
            },
            SQLiteDatabase.CONFLICT_IGNORE
        )
        val values = ContentValues().apply {
            put("updated_at_ms", now)
        }
        db.update("memory_scopes", values, "scope_key = ?", arrayOf(storageKey(scope)))
    }

    private fun deleteWhere(db: SQLiteDatabase, where: String, args: Array<String>) {
        db.delete("memory_entries", where, args)
        db.delete("memory_round_summaries", where, args)
        db.delete("long_term_memories", where, args)
        db.delete("memory_persona_snapshots", where, args)
        db.delete("memory_records", where, args)
        db.delete("memory_state_metadata", where, args)
        db.delete("memory_scopes", where, args)
    }

    private fun scopeColumns(scope: JSONObject): ContentValues {
        return ContentValues().apply {
            put("scope_key", storageKey(scope))
            put("owner_id", scope.optString("owner_id"))
            put("game_id", scope.optString("game_id"))
            put("namespace", scope.optString("namespace"))
            put("ruleset_id", scope.optString("ruleset_id"))
            put("room_id", scope.optString("room_id"))
        }
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

    private fun databasePathForNative(): String {
        return context.getDatabasePath(DATABASE_NAME).absolutePath
    }

    private fun entryFromCursor(cursor: Cursor): JSONObject {
        return JSONObject()
            .put("content", cursor.stringOrEmpty("content"))
            .put("visibility", visibility(cursor.stringOrEmpty("visibility")))
            .put("created_at", cursor.longOrZero("created_at_ms").toDouble() / 1000.0)
            .put("metadata", jsonObjectOrEmpty(cursor.stringOrEmpty("metadata_json")))
    }

    private fun summaryFromCursor(cursor: Cursor): JSONObject {
        return JSONObject()
            .put("day_number", cursor.intOrZero("day_number"))
            .put("phase", cursor.stringOrEmpty("phase"))
            .put("public_summary", cursor.stringOrEmpty("public_summary"))
            .put("private_summary", cursor.stringOrEmpty("private_summary"))
            .put("decision_summary", cursor.stringOrEmpty("decision_summary"))
            .put("suspicion_summary", cursor.stringOrEmpty("suspicion_summary"))
            .put("strategy_summary", cursor.stringOrEmpty("strategy_summary"))
    }

    private fun personaSnapshotColumns(scope: JSONObject, persona: JSONObject, now: Long): ContentValues {
        return scopeColumns(scope).apply {
            put("memory_id", nonEmpty(persona.optString("memory_id"), "profile_${scope.optString("owner_id")}"))
            put("bot_id", nonEmpty(persona.optString("bot_id"), scope.optString("owner_id")))
            put("content", persona.optString("content").trim())
            put("structured_payload_json", (persona.optJSONObject("structured_payload") ?: JSONObject()).toString())
            put("visibility", memoryVisibility(persona.optString("visibility", "self_private")))
            put("source", nonEmpty(persona.optString("source"), "persona_seed"))
            put("status", nonEmpty(persona.optString("status"), "active"))
            put("importance", persona.optDouble("importance", 0.82).coerceIn(0.0, 1.0))
            put("confidence", persona.optDouble("confidence", 0.80).coerceIn(0.0, 1.0))
            put("created_at_ms", secondsToMillis(persona.optDouble("created_at", now.toDouble() / 1000.0)))
            put("updated_at_ms", secondsToMillis(persona.optDouble("updated_at", now.toDouble() / 1000.0)))
            put("evidence_json", (persona.optJSONArray("evidence") ?: JSONArray()).toString())
        }
    }

    private fun stateMetadataColumns(scope: JSONObject, state: JSONObject, now: Long): ContentValues {
        return scopeColumns(scope).apply {
            put("memory_schema_version", state.optInt("memory_schema_version", MEMORY_SCHEMA_VERSION))
            put("record_schema_version", state.optInt("record_schema_version", RECORD_SCHEMA_VERSION))
            put("context_schema_version", state.optInt("context_schema_version", CONTEXT_SCHEMA_VERSION))
            put("read_only", if (state.optBoolean("read_only", false)) 1 else 0)
            put("migration_report_json", (state.optJSONObject("migration_report") ?: defaultMigrationReport()).toString())
            put("relationship_state_json", (state.optJSONObject("relationship_state") ?: JSONObject()).toString())
            put("conflict_records_json", (state.optJSONArray("conflict_records") ?: JSONArray()).toString())
            put("vector_index_json", (state.optJSONObject("vector_index") ?: JSONObject()).toString())
            put("semantic_hnsw_graph_json", (state.optJSONObject("semantic_hnsw_graph") ?: JSONObject()).toString())
            put("token_budget", state.optInt("token_budget", TOKEN_BUDGET))
            put("updated_at_ms", now)
        }
    }

    private fun memoryRecordColumns(
        scope: JSONObject,
        record: JSONObject,
        now: Long,
        columns: Set<String>
    ): ContentValues {
        val memoryType = nonEmpty(record.optString("memory_type"), "episodic")
        val memoryId = nonEmpty(record.optString("memory_id"), "${memoryType}_${now}_${record.optString("content").hashCode()}")
        return scopeColumns(scope).apply {
            if (columns.contains("record_schema_version")) {
                put("record_schema_version", record.optInt("record_schema_version", RECORD_SCHEMA_VERSION))
            }
            put("memory_id", memoryId)
            put("bot_id", nonEmpty(record.optString("bot_id"), scope.optString("owner_id")))
            put("memory_type", memoryType)
            put("domain_id", nonEmpty(record.optString("domain_id"), scope.optString("game_id")))
            put("session_id", nonEmpty(record.optString("session_id"), scope.optString("room_id")))
            put("instance_id", nonEmpty(record.optString("instance_id"), scope.optString("ruleset_id")))
            put("subject_id", record.optString("subject_id").trim())
            put("subject_type", record.optString("subject_type").trim())
            put("content", record.optString("content").trim())
            put("structured_payload_json", (record.optJSONObject("structured_payload") ?: JSONObject()).toString())
            put("visibility", memoryVisibility(record.optString("visibility", "self_private")))
            put("source", nonEmpty(record.optString("source"), memoryType))
            put("importance", record.optDouble("importance", 0.55).coerceIn(0.0, 1.0))
            put("confidence", record.optDouble("confidence", 0.70).coerceIn(0.0, 1.0))
            put("status", nonEmpty(record.optString("status"), "active"))
            if (columns.contains("conflict_status")) {
                put("conflict_status", conflictStatus(record))
            }
            put("created_at_ms", secondsToMillis(record.optDouble("created_at", now.toDouble() / 1000.0)))
            put("updated_at_ms", secondsToMillis(record.optDouble("updated_at", now.toDouble() / 1000.0)))
            put("last_accessed_at_ms", secondsToMillis(record.optDouble("last_accessed_at", 0.0)))
            put("expires_at_ms", secondsToMillis(record.optDouble("expires_at", 0.0)))
            put("evidence_json", (record.optJSONArray("evidence") ?: JSONArray()).toString())
            put("metadata_json", (record.optJSONObject("metadata") ?: JSONObject()).toString())
            put("embedding_status", nonEmpty(record.optString("embedding_status"), "not_required"))
            put("embedding_version", record.optString("embedding_version").trim())
            if (columns.contains("embedding_json")) {
                put("embedding_json", (record.optJSONObject("embedding") ?: JSONObject()).toString())
            }
        }
    }

    private fun stateMetadataForScope(db: SQLiteDatabase, scope: JSONObject): JSONObject {
        return db.query(
            "memory_state_metadata",
            null,
            "scope_key = ?",
            arrayOf(storageKey(scope)),
            null,
            null,
            null,
            "1"
        ).use { cursor ->
            if (cursor.moveToFirst()) stateMetadataFromCursor(cursor) else defaultStateMetadata()
        }
    }

    private fun stateMetadataFromCursor(cursor: Cursor): JSONObject {
        return JSONObject()
            .put("memory_schema_version", maxOf(1, cursor.intOrZero("memory_schema_version")))
            .put("record_schema_version", maxOf(1, cursor.intOrZero("record_schema_version")))
            .put("context_schema_version", maxOf(1, cursor.intOrZero("context_schema_version")))
            .put("read_only", cursor.intOrZero("read_only") != 0)
            .put("migration_report", jsonObjectOrEmpty(cursor.stringOrEmpty("migration_report_json")))
            .put("relationship_state", jsonObjectOrEmpty(cursor.stringOrEmpty("relationship_state_json")))
            .put("conflict_records", jsonArrayOrEmpty(cursor.stringOrEmpty("conflict_records_json")))
            .put("vector_index", jsonObjectOrEmpty(cursor.stringOrEmpty("vector_index_json")))
            .put("semantic_hnsw_graph", jsonObjectOrEmpty(cursor.stringOrEmpty("semantic_hnsw_graph_json")))
            .put("token_budget", maxOf(1, cursor.intOrZero("token_budget").takeIf { it > 0 } ?: TOKEN_BUDGET))
    }

    private fun defaultStateMetadata(): JSONObject {
        return JSONObject()
            .put("memory_schema_version", MEMORY_SCHEMA_VERSION)
            .put("record_schema_version", RECORD_SCHEMA_VERSION)
            .put("context_schema_version", CONTEXT_SCHEMA_VERSION)
            .put("read_only", false)
            .put("migration_report", defaultMigrationReport())
            .put("relationship_state", JSONObject())
            .put("conflict_records", JSONArray())
            .put("vector_index", JSONObject())
            .put("semantic_hnsw_graph", JSONObject())
            .put("token_budget", TOKEN_BUDGET)
    }

    private fun defaultMigrationReport(): JSONObject {
        return JSONObject()
            .put("status", "current")
            .put("from_version", MEMORY_SCHEMA_VERSION)
            .put("to_version", MEMORY_SCHEMA_VERSION)
            .put("warnings", JSONArray())
    }

    private fun personaSnapshotFromCursor(cursor: Cursor): JSONObject {
        return JSONObject()
            .put("memory_id", cursor.stringOrEmpty("memory_id"))
            .put("bot_id", cursor.stringOrEmpty("bot_id"))
            .put("content", cursor.stringOrEmpty("content"))
            .put("structured_payload", jsonObjectOrEmpty(cursor.stringOrEmpty("structured_payload_json")))
            .put("visibility", memoryVisibility(cursor.stringOrEmpty("visibility")))
            .put("source", cursor.stringOrEmpty("source"))
            .put("status", cursor.stringOrEmpty("status"))
            .put("importance", cursor.doubleOrDefault("importance", 0.82))
            .put("confidence", cursor.doubleOrDefault("confidence", 0.80))
            .put("created_at", cursor.longOrZero("created_at_ms").toDouble() / 1000.0)
            .put("updated_at", cursor.longOrZero("updated_at_ms").toDouble() / 1000.0)
            .put("evidence", jsonArrayOrEmpty(cursor.stringOrEmpty("evidence_json")))
    }

    private fun memoryRecordFromCursor(cursor: Cursor): JSONObject {
        return JSONObject()
            .put("record_schema_version", maxOf(1, cursor.intOrZero("record_schema_version").takeIf { it > 0 } ?: RECORD_SCHEMA_VERSION))
            .put("memory_id", cursor.stringOrEmpty("memory_id"))
            .put("bot_id", cursor.stringOrEmpty("bot_id"))
            .put("memory_type", cursor.stringOrEmpty("memory_type"))
            .put("scope", scopeFromCursor(cursor))
            .put("domain_id", cursor.stringOrEmpty("domain_id"))
            .put("session_id", cursor.stringOrEmpty("session_id"))
            .put("instance_id", cursor.stringOrEmpty("instance_id"))
            .put("subject_id", cursor.stringOrEmpty("subject_id"))
            .put("subject_type", cursor.stringOrEmpty("subject_type"))
            .put("content", cursor.stringOrEmpty("content"))
            .put("structured_payload", jsonObjectOrEmpty(cursor.stringOrEmpty("structured_payload_json")))
            .put("visibility", memoryVisibility(cursor.stringOrEmpty("visibility")))
            .put("source", cursor.stringOrEmpty("source"))
            .put("importance", cursor.doubleOrDefault("importance", 0.55))
            .put("confidence", cursor.doubleOrDefault("confidence", 0.70))
            .put("status", cursor.stringOrEmpty("status"))
            .put("conflict_status", cursor.stringOrEmpty("conflict_status"))
            .put("created_at", cursor.longOrZero("created_at_ms").toDouble() / 1000.0)
            .put("updated_at", cursor.longOrZero("updated_at_ms").toDouble() / 1000.0)
            .put("last_accessed_at", cursor.longOrZero("last_accessed_at_ms").toDouble() / 1000.0)
            .put("expires_at", cursor.longOrZero("expires_at_ms").toDouble() / 1000.0)
            .put("evidence", jsonArrayOrEmpty(cursor.stringOrEmpty("evidence_json")))
            .put("metadata", jsonObjectOrEmpty(cursor.stringOrEmpty("metadata_json")))
            .put("embedding_status", cursor.stringOrEmpty("embedding_status"))
            .put("embedding_version", cursor.stringOrEmpty("embedding_version"))
            .put("embedding", jsonObjectOrEmpty(cursor.stringOrEmpty("embedding_json")))
    }

    private fun modelConfigColumns(db: SQLiteDatabase, config: JSONObject, modelName: String, endpoint: String, formtAdapter: String, reasonAdapter: String): ContentValues {
        val columns = tableColumns(db, "model_configs")
        val maxContext = maxOf(1, config.optInt("max_context", config.optInt("max_token", 262144)))
        val maxOutput = maxOutputFromConfig(config, maxContext)
        return ContentValues().apply {
            if (columns.contains("model")) {
                put("model", modelName)
            }
            if (columns.contains("name")) {
                put("name", modelName)
            }
            put("provider", nonEmpty(config.optString("provider"), "openai_compatible"))
            put("endpoint", endpoint)
            put("api_key", config.optString("api_key").trim())
            put("context_window_tokens", maxOf(1, config.optInt("context_window_tokens", (maxContext * 0.7).toInt())))
            if (columns.contains("max_context")) {
                put("max_context", maxContext)
            }
            if (columns.contains("max_token")) {
                put("max_token", maxContext)
            }
            if (columns.contains("max_output")) {
                put("max_output", maxOutput)
            }
            if (columns.contains("max_output_tokens")) {
                put("max_output_tokens", maxOutput)
            }
            put("temperature", config.optDouble("temperature", 0.6).coerceIn(0.0, 2.0))
            if (columns.contains("reasoning")) {
                put("reasoning", if (config.optBoolean("reasoning", false)) 1 else 0)
            }
            if (columns.contains("formt_adapter")) {
                put("formt_adapter", formtAdapter)
            }
            if (columns.contains("reason_adapter")) {
                put("reason_adapter", reasonAdapter)
            }
        }
    }

    private fun modelConfigById(db: SQLiteDatabase, id: Int): JSONObject? {
        if (id <= 0) {
            return null
        }
        return db.query(
            "model_configs",
            null,
            "id = ?",
            arrayOf(id.toString()),
            null,
            null,
            null,
            "1"
        ).use { cursor ->
            if (cursor.moveToFirst()) modelConfigFromCursor(cursor) else null
        }
    }

    private fun findModelConfigId(db: SQLiteDatabase, provider: String, endpoint: String, modelName: String): Int {
        val modelColumn = if (tableColumns(db, "model_configs").contains("model")) "model" else "name"
        return db.query(
            "model_configs",
            arrayOf("id"),
            "provider = ? AND endpoint = ? AND $modelColumn = ?",
            arrayOf(provider, endpoint, modelName),
            null,
            null,
            null,
            "1"
        ).use { cursor ->
            if (cursor.moveToFirst()) cursor.intOrZero("id") else 0
        }
    }

    private fun modelConfigFromCursor(cursor: Cursor): JSONObject {
        val modelName = nonEmpty(cursor.stringOrEmpty("model"), cursor.stringOrEmpty("name"))
        val maxContext = maxOf(1, cursor.intOrZero("max_context").takeIf { it > 0 } ?: cursor.intOrZero("max_token").takeIf { it > 0 } ?: 262144)
        val storedMaxOutput = cursor.intOrZero("max_output")
        val maxOutput = if (storedMaxOutput > 0) storedMaxOutput else sanitizedLegacyMaxOutput(cursor.intOrZero("max_output_tokens"), maxContext)
        return JSONObject()
            .put("id", cursor.intOrZero("id"))
            .put("model", modelName)
            .put("provider", cursor.stringOrEmpty("provider"))
            .put("endpoint", cursor.stringOrEmpty("endpoint"))
            .put("api_key", cursor.stringOrEmpty("api_key"))
            .put("context_window_tokens", cursor.intOrZero("context_window_tokens"))
            .put("max_context", maxContext)
            .put("max_output", maxOutput)
            .put("temperature", cursor.doubleOrDefault("temperature", 0.6))
            .put("reasoning", cursor.intOrZero("reasoning") != 0)
            .put("formt_adapter", nonEmpty(cursor.stringOrEmpty("formt_adapter"), "auto"))
            .put("reason_adapter", nonEmpty(cursor.stringOrEmpty("reason_adapter"), "auto"))
    }

    private fun maxOutputFromConfig(config: JSONObject, maxContext: Int): Int {
        if (config.has("max_output")) {
            return maxOf(1, config.optInt("max_output", 4096))
        }
        return sanitizedLegacyMaxOutput(config.optInt("max_output_tokens", 4096), maxContext)
    }

    private fun normalizeFormtAdapter(value: String): String {
        return value.trim().lowercase()
    }

    private fun isSavableFormtAdapter(value: String): Boolean {
        return SAVABLE_FORMT_ADAPTERS.contains(normalizeFormtAdapter(value))
    }

    private fun normalizeReasonAdapter(value: String): String {
        return value.trim().lowercase()
    }

    private fun isSavableReasonAdapter(reasoning: Boolean, value: String): Boolean {
        val normalized = normalizeReasonAdapter(value)
        if (normalized == "auto") {
            return false
        }
        if (reasoning) {
            return normalized != "none" && SAVABLE_REASON_ADAPTERS.contains(normalized)
        }
        return SAVABLE_REASON_ADAPTERS.contains(normalized)
    }

    private fun sanitizedLegacyMaxOutput(value: Int, maxContext: Int): Int {
        if (value <= 0) {
            return 4096
        }
        if (value > 65536 || (maxContext > 0 && value == maxContext)) {
            return 4096
        }
        return value
    }

    private fun voiceConfigColumns(config: JSONObject, name: String, engine: String): ContentValues {
        val active = config.optBoolean("active", false)
        val enabled = config.optBoolean("enabled", true) || active
        return ContentValues().apply {
            put("name", name)
            put("engine", engine)
            put("gender", nonEmpty(config.optString("gender"), "女声"))
            put("voice", config.optString("voice").trim())
            put("speed", nonEmpty(config.optString("speed"), "0.90"))
            put("pitch", nonEmpty(config.optString("pitch"), "1.00"))
            put("volume", nonEmpty(config.optString("volume"), "1.00"))
            put("enabled", if (enabled) 1 else 0)
            put("active", if (active) 1 else 0)
        }
    }

    private fun enforceUniqueActiveVoiceConfig(db: SQLiteDatabase) {
        val targetId = firstVoiceConfigId(db, "active != 0 AND enabled != 0")
            .takeIf { it > 0 }
            ?: firstVoiceConfigId(db, "enabled != 0")
        if (targetId > 0) {
            db.execSQL(
                "UPDATE voice_configs SET active = CASE WHEN id = ? THEN 1 ELSE 0 END",
                arrayOf<Any>(targetId)
            )
        } else {
            db.execSQL("UPDATE voice_configs SET active = 0")
        }
    }

    private fun activateOnlyVoiceConfig(db: SQLiteDatabase, id: Int) {
        db.execSQL(
            "UPDATE voice_configs SET active = CASE WHEN id = ? THEN 1 ELSE 0 END, " +
                "enabled = CASE WHEN id = ? THEN 1 ELSE enabled END",
            arrayOf<Any>(id, id)
        )
    }

    private fun firstVoiceConfigId(db: SQLiteDatabase, where: String): Int {
        return db.query(
            "voice_configs",
            arrayOf("id"),
            where,
            null,
            null,
            null,
            "id ASC",
            "1"
        ).use { cursor ->
            if (cursor.moveToFirst()) cursor.intOrZero("id") else 0
        }
    }

    private fun voiceConfigById(db: SQLiteDatabase, id: Int): JSONObject? {
        if (id <= 0) {
            return null
        }
        return db.query(
            "voice_configs",
            null,
            "id = ?",
            arrayOf(id.toString()),
            null,
            null,
            null,
            "1"
        ).use { cursor ->
            if (cursor.moveToFirst()) voiceConfigFromCursor(cursor) else null
        }
    }

    private fun voiceConfigFromCursor(cursor: Cursor): JSONObject {
        return JSONObject()
            .put("id", cursor.intOrZero("id"))
            .put("name", cursor.stringOrEmpty("name"))
            .put("engine", cursor.stringOrEmpty("engine"))
            .put("gender", cursor.stringOrEmpty("gender"))
            .put("voice", cursor.stringOrEmpty("voice"))
            .put("speed", nonEmpty(cursor.stringOrEmpty("speed"), "0.90"))
            .put("pitch", nonEmpty(cursor.stringOrEmpty("pitch"), "1.00"))
            .put("volume", nonEmpty(cursor.stringOrEmpty("volume"), "1.00"))
            .put("enabled", cursor.intOrZero("enabled") != 0)
            .put("active", cursor.intOrZero("active") != 0)
    }

    private fun scopeFromCursor(cursor: Cursor): JSONObject {
        return JSONObject()
            .put("owner_id", cursor.stringOrEmpty("owner_id"))
            .put("game_id", cursor.stringOrEmpty("game_id"))
            .put("namespace", cursor.stringOrEmpty("namespace"))
            .put("ruleset_id", cursor.stringOrEmpty("ruleset_id"))
            .put("room_id", cursor.stringOrEmpty("room_id"))
    }

    private fun visibility(value: String): String {
        return if (value.trim().lowercase() == "private") "private" else "public"
    }

    private fun memoryVisibility(value: String): String {
        return when (value.trim().lowercase()) {
            "public", "private", "self_private", "observer_safe", "post_session_reveal" -> value.trim().lowercase()
            else -> "self_private"
        }
    }

    private fun conflictStatus(record: JSONObject): String {
        val direct = record.optString("conflict_status").trim()
        if (direct.isNotEmpty()) {
            return direct
        }
        val metadata = record.optJSONObject("metadata") ?: return ""
        return metadata.optString("conflict_status").trim()
    }

    private fun countRows(
        db: SQLiteDatabase,
        table: String,
        where: String? = null,
        args: Array<String>? = null
    ): Int {
        return db.query(
            table,
            arrayOf("COUNT(*) AS c"),
            where,
            args,
            null,
            null,
            null
        ).use { cursor ->
            if (cursor.moveToFirst()) cursor.getInt(0) else 0
        }
    }

    private fun nonEmpty(value: String, fallback: String): String {
        val trimmed = value.trim()
        return trimmed.ifEmpty { fallback }
    }

    private fun nowSeconds(): Double {
        return System.currentTimeMillis().toDouble() / 1000.0
    }

    private fun secondsToMillis(value: Double): Long {
        return (value * 1000.0).toLong()
    }

    private fun jsonObjectOrEmpty(value: String): JSONObject {
        return try {
            if (value.isBlank()) JSONObject() else JSONObject(value)
        } catch (_: Exception) {
            JSONObject()
        }
    }

    private fun jsonArrayOrEmpty(value: String): JSONArray {
        return try {
            if (value.isBlank()) JSONArray() else JSONArray(value)
        } catch (_: Exception) {
            JSONArray()
        }
    }

    private fun ok(): JSONObject = JSONObject().put("ok", true)

    private fun error(message: String): JSONObject = JSONObject()
        .put("ok", false)
        .put("error", message)

    private inline fun SQLiteDatabase.transaction(block: SQLiteDatabase.() -> Unit) {
        beginTransaction()
        try {
            block()
            setTransactionSuccessful()
        } finally {
            endTransaction()
        }
    }

    private fun Cursor.stringOrEmpty(column: String): String {
        val index = getColumnIndex(column)
        if (index < 0 || isNull(index)) {
            return ""
        }
        return getString(index) ?: ""
    }

    private fun Cursor.intOrZero(column: String): Int {
        val index = getColumnIndex(column)
        if (index < 0 || isNull(index)) {
            return 0
        }
        return getInt(index)
    }

    private fun Cursor.longOrZero(column: String): Long {
        val index = getColumnIndex(column)
        if (index < 0 || isNull(index)) {
            return 0L
        }
        return getLong(index)
    }

    private fun Cursor.doubleOrDefault(column: String, fallback: Double): Double {
        val index = getColumnIndex(column)
        if (index < 0 || isNull(index)) {
            return fallback
        }
        return getDouble(index)
    }

    private fun tableColumns(db: SQLiteDatabase, table: String): Set<String> {
        val columns = mutableSetOf<String>()
        db.rawQuery("PRAGMA table_info($table)", null).use { cursor ->
            val nameIndex = cursor.getColumnIndex("name")
            while (cursor.moveToNext()) {
                if (nameIndex >= 0) {
                    columns.add(cursor.getString(nameIndex))
                }
            }
        }
        return columns
    }

    companion object {
        private const val TAG = "MemoryDatabase"
        private const val DATABASE_NAME = "ai_memory.sqlite"
        private const val SCHEMA_VERSION = 11
        private const val MEMORY_SCHEMA_VERSION = 1
        private const val RECORD_SCHEMA_VERSION = 1
        private const val CONTEXT_SCHEMA_VERSION = 1
        private const val TOKEN_BUDGET = 4000
        private val SAVABLE_FORMT_ADAPTERS = setOf(
            "openai_json_schema",
            "openai_json_object",
            "openai_tool_forced",
            "openai_tool_optional",
            "openai_mimo_tool",
            "gemini_json_schema",
            "anthropic_tool",
            "ollama_format_schema"
        )
        private val SAVABLE_REASON_ADAPTERS = setOf(
            "native",
            "none",
            "deepseek_thinking",
            "glm_thinking",
            "ark_thinking",
            "minimax_reasoning_split",
            "openai_reasoning_effort",
            "mimo_chat_template",
            "kimi_thinking_control"
        )
    }
}
