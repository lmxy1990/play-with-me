extends SceneTree


class FakeMemoryPlugin:
	extends Node

	var states := {}
	var deleted_owner := ""
	var native_enabled := false
	var native_rebuild_count := 0
	var native_search_count := 0

	func memory_available() -> bool:
		return true

	func memory_load_state(scope_json: String) -> String:
		var scope: Dictionary = JSON.parse_string(scope_json)
		var key := _scope_key(scope)
		if not states.has(key):
			states[key] = {
				"scope": scope,
				"persona_snapshot": {},
				"memory_records": [],
				"recent_entries": [],
				"round_summaries": [],
				"long_term_memory_summary": "",
				"token_budget": 4000,
			}
		return JSON.stringify(states[key])

	func memory_save_state(scope_json: String, state_json: String) -> String:
		var scope: Dictionary = JSON.parse_string(scope_json)
		var state: Dictionary = JSON.parse_string(state_json)
		state["scope"] = scope
		states[_scope_key(scope)] = state
		return JSON.stringify({"ok": true})

	func memory_append(scope_json: String, entry_json: String) -> String:
		var scope: Dictionary = JSON.parse_string(scope_json)
		var entry: Dictionary = JSON.parse_string(entry_json)
		var state := JSON.parse_string(memory_load_state(scope_json)) as Dictionary
		(state["recent_entries"] as Array).append(entry)
		states[_scope_key(scope)] = state
		return JSON.stringify({"ok": true})

	func memory_compact(scope_json: String, request_json: String) -> String:
		var scope: Dictionary = JSON.parse_string(scope_json)
		var request: Dictionary = JSON.parse_string(request_json)
		var summary := {
			"day_number": int(request.get("day_number", 0)),
			"phase": String(request.get("phase", "")),
			"public_summary": String(request.get("public_summary", "")),
			"private_summary": String(request.get("private_summary", "")),
			"decision_summary": String(request.get("decision_summary", "")),
			"suspicion_summary": String(request.get("suspicion_summary", "")),
			"strategy_summary": String(request.get("strategy_summary", "")),
		}
		var state := JSON.parse_string(memory_load_state(scope_json)) as Dictionary
		state["recent_entries"] = []
		(state["round_summaries"] as Array).append(summary)
		states[_scope_key(scope)] = state
		return JSON.stringify({"ok": true, "summary": summary})

	func memory_save_long_term(scope_json: String, summary: String, user_approved: bool) -> String:
		if not user_approved:
			return JSON.stringify({"ok": true})
		var scope: Dictionary = JSON.parse_string(scope_json)
		var state := JSON.parse_string(memory_load_state(scope_json)) as Dictionary
		state["long_term_memory_summary"] = summary
		states[_scope_key(scope)] = state
		return JSON.stringify({"ok": true})

	func memory_delete_scope(scope_json: String) -> String:
		var scope: Dictionary = JSON.parse_string(scope_json)
		states.erase(_scope_key(scope))
		return JSON.stringify({"ok": true})

	func memory_discard_session(scope_json: String) -> String:
		var scope: Dictionary = JSON.parse_string(scope_json)
		if String(scope.get("namespace", "")) == "session":
			states.erase(_scope_key(scope))
		return JSON.stringify({"ok": true})

	func memory_list_scopes(owner_id: String, game_id: String, memory_namespace: String) -> String:
		var result := []
		for state in states.values():
			var scope: Dictionary = state.get("scope", {})
			if owner_id != "" and String(scope.get("owner_id", "")) != owner_id:
				continue
			if game_id != "" and String(scope.get("game_id", "")) != game_id:
				continue
			if memory_namespace != "" and String(scope.get("namespace", "")) != memory_namespace:
				continue
			result.append(scope)
		return JSON.stringify(result)

	func memory_delete_owner(owner_id: String, game_id: String) -> String:
		deleted_owner = owner_id
		var keys := []
		for key in states.keys():
			var scope: Dictionary = states[key].get("scope", {})
			if String(scope.get("owner_id", "")) != owner_id:
				continue
			if game_id != "" and String(scope.get("game_id", "")) != game_id:
				continue
			keys.append(key)
		for key in keys:
			states.erase(key)
		return JSON.stringify({"ok": true})

	func memory_list_index_names() -> String:
		return JSON.stringify([
			"idx_memory_entries_scope_created",
			"idx_memory_entries_owner_game_namespace",
			"idx_memory_records_scope_type_status",
			"idx_memory_records_owner_type_status",
			"idx_memory_summaries_scope_round",
			"idx_long_term_owner_game_namespace",
		])

	func memory_index_status() -> String:
		var record_count := 0
		var ready_count := 0
		var event_count := 0
		var semantic_count := 0
		for state in states.values():
			for record in state.get("memory_records", []):
				if not (record is Dictionary):
					continue
				record_count += 1
				if String((record as Dictionary).get("embedding_status", "")) == "ready":
					ready_count += 1
					match String((record as Dictionary).get("memory_type", "")):
						"episodic":
							event_count += 1
						"semantic", "reflection":
							semantic_count += 1
		return JSON.stringify({
			"ok": true,
			"sqlite_database_enabled": true,
			"native_sqlite_vec_enabled": native_enabled and event_count > 0,
			"native_hnswlib_enabled": native_enabled and semantic_count > 0,
			"sqlite_vec_event_enabled": native_enabled and event_count > 0,
			"hnsw_semantic_enabled": native_enabled and semantic_count > 0,
			"vector_backend": "android_native_sqlite_vec_hnswlib" if native_enabled else "godot_local_vector_persisted_in_android_sqlite",
			"memory_record_count": record_count,
			"ready_embedding_count": ready_count,
			"event_vector_count": event_count,
			"semantic_vector_count": semantic_count,
			"warnings": [] if native_enabled else ["native_sqlite_vec_unavailable", "native_hnswlib_unavailable"],
		})

	func memory_native_rebuild_indexes(scope_json: String, state_json: String) -> String:
		native_rebuild_count += 1
		var state: Dictionary = JSON.parse_string(state_json)
		var event_count := 0
		var semantic_count := 0
		for record in state.get("memory_records", []):
			if not (record is Dictionary):
				continue
			if String((record as Dictionary).get("embedding_status", "")) != "ready":
				continue
			match String((record as Dictionary).get("memory_type", "")):
				"episodic":
					event_count += 1
				"semantic", "reflection":
					semantic_count += 1
		return JSON.stringify({
			"ok": true,
			"native_sqlite_vec_enabled": native_enabled and event_count > 0,
			"native_hnswlib_enabled": native_enabled and semantic_count > 0,
			"sqlite_vec_event_enabled": native_enabled and event_count > 0,
			"hnsw_semantic_enabled": native_enabled and semantic_count > 0,
			"native_vector_backend": "sqlite-vec+hnswlib" if native_enabled else "none",
			"event_vector_count": event_count,
			"semantic_vector_count": semantic_count,
			"warnings": [],
		})

	func memory_native_vector_search(scope_json: String, query_vector_json: String, request_json: String) -> String:
		native_search_count += 1
		if not native_enabled:
			return JSON.stringify({"ok": true, "items": []})
		return JSON.stringify({
			"ok": true,
			"native_sqlite_vec_enabled": true,
			"native_hnswlib_enabled": true,
			"items": [{
				"memory_id": "working_1",
				"memory_type": "working",
				"retrieval_source": "sqlite_vec_event",
				"backend": "sqlite-vec",
				"distance": 0.05,
				"score": 0.95,
			}],
			"warnings": [],
		})

	func _scope_key(scope: Dictionary) -> String:
		return "|".join([
			_non_empty(String(scope.get("owner_id", "")), "unknown"),
			_non_empty(String(scope.get("game_id", "")), "game"),
			_non_empty(String(scope.get("map_id", "")), "-"),
			_non_empty(String(scope.get("room_id", "")), "-"),
			_non_empty(String(scope.get("namespace", "")), "session"),
		])

	func _non_empty(value: String, default_value: String) -> String:
		var trimmed := value.strip_edges()
		return trimmed if trimmed != "" else default_value


class TestMemoryStore:
	extends AndroidMemoryStore

	var plugin

	func _init(plugin_ref) -> void:
		plugin = plugin_ref

	func _plugin():
		return plugin


func _initialize() -> void:
	var plugin := FakeMemoryPlugin.new()
	root.add_child(plugin)

	var store := TestMemoryStore.new(plugin)
	assert(store.is_available())
	var scope := {
		"owner_id": "bot_1",
		"game_id": "werewolf",
		"namespace": "session",
		"map_id": "basic_village",
		"room_id": "room_1",
	}
	assert(bool(store.append(scope, {
		"content": "怀疑3号位",
		"visibility": "private",
		"created_at": 1760000000.0,
		"metadata": {"phase": "day_discussion"},
	}).get("ok", false)))
	var state: Dictionary = store.load_state(scope)
	assert((state["recent_entries"] as Array).size() == 1)
	assert((state["memory_records"] as Array).is_empty())
	assert(bool(store.save_state(scope, {
		"scope": scope,
		"memory_schema_version": 1,
		"record_schema_version": 1,
		"context_schema_version": 1,
		"read_only": false,
		"persona_snapshot": {
			"memory_id": "profile_bot_1",
			"bot_id": "bot_1",
			"content": "谨慎发言。",
			"visibility": "self_private",
		},
		"memory_records": [
			{
				"memory_id": "working_1",
				"bot_id": "bot_1",
				"memory_type": "working",
				"content": "当前目标：观察3号位。",
				"visibility": "self_private",
				"status": "active",
				"embedding_status": "ready",
				"embedding_version": "local-token-hash-v1",
				"embedding": {
					"provider": "godot_local",
					"model": "token_hash_v1",
					"version": "local-token-hash-v1",
					"dimension": 128,
					"vector": [1.0],
				},
			},
		],
		"relationship_state": {"p3": {"trust": 0.4}},
		"conflict_records": [{"conflict_id": "c1"}],
		"vector_index": {"backend": "godot_local_vector", "event_vector_count": 1},
		"semantic_hnsw_graph": {"nodes": 0, "edges": 0},
		"recent_entries": state["recent_entries"],
		"round_summaries": [],
		"long_term_memory_summary": "",
		"token_budget": 4000,
	}).get("ok", false)))
	var saved_state: Dictionary = store.load_state(scope)
	assert(String((saved_state["persona_snapshot"] as Dictionary).get("content", "")) == "谨慎发言。")
	assert((saved_state["memory_records"] as Array).size() == 1)
	assert(not (saved_state.get("relationship_state", {}) as Dictionary).is_empty())
	assert((saved_state.get("conflict_records", []) as Array).size() == 1)
	assert(String((saved_state.get("vector_index", {}) as Dictionary).get("backend", "")) == "godot_local_vector")
	assert(not ((saved_state["memory_records"] as Array)[0].get("embedding", {}) as Dictionary).is_empty())
	var summary: Dictionary = store.compact(scope, {
		"day_number": 1,
		"phase": "vote",
		"public_summary": "公开事件。",
		"private_summary": "",
		"decision_summary": "投票。",
		"suspicion_summary": "怀疑3号。",
		"strategy_summary": "继续观察。",
	})
	assert(bool(summary.get("ok", false)))
	assert(String(summary.get("phase", "")) == "vote")
	assert(store.list_scopes("bot_1", "werewolf", "session").size() == 1)
	assert(store.list_index_names().has("idx_long_term_owner_game_namespace"))
	var store_index_status: Dictionary = store.index_status()
	assert(bool(store_index_status.get("sqlite_database_enabled", false)))
	assert(not bool(store_index_status.get("native_sqlite_vec_enabled", true)))
	plugin.native_enabled = true
	var native_rebuild: Dictionary = store.native_rebuild_indexes(scope, saved_state)
	assert(bool(native_rebuild.get("ok", false)))
	assert(plugin.native_rebuild_count == 1)
	var native_search: Dictionary = store.native_vector_search(scope, [1.0], {"limit": 4})
	assert(bool(native_search.get("ok", false)))
	assert((native_search.get("items", []) as Array).size() == 1)
	assert(plugin.native_search_count == 1)
	plugin.native_enabled = false

	var manager = load("res://scripts/core/memory/memory_manager.gd").new()
	manager.persistence_enabled = true
	manager.prefer_android_sqlite = true
	manager._android_store = store
	var update_result: Dictionary = manager.update_memory({
		"bot_id": "bot_1",
		"scope": scope,
		"update_reason": "confirmed_event",
		"memory_update": {
			"working_update": {"focus": "继续观察票型"},
			"episodic_events": [{"content": "3号位发言发生变化。", "importance": 0.7}],
		},
	})
	assert(bool(update_result.get("ok", false)))
	var native_context: Dictionary = manager.get_memory_context({
		"bot_id": "bot_1",
		"scope": scope,
		"query": "观察 票型 3号",
	})
	var memory_context: Dictionary = (native_context.get("data", {}) as Dictionary).get("memory_context", {}) as Dictionary
	assert((memory_context.get("working_memory", []) as Array).size() >= 1)
	var native_report: Dictionary = (native_context.get("data", {}) as Dictionary).get("retrieval_report", {}) as Dictionary
	assert(int((native_report.get("source_fetch_report", {}) as Dictionary).get("candidate_count", 0)) >= 0)
	manager.append(scope, {"content": "第二条", "visibility": "public"})
	var prompt: Dictionary = manager.prompt_context(scope)
	assert((prompt["recentMemoryEntries"] as Array).size() == 1)
	manager.delete_owner_memory("bot_1", "werewolf")
	assert(plugin.deleted_owner == "bot_1")
	quit()
