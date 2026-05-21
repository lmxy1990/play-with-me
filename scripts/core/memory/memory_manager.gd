extends RefCounted
class_name MemoryManager

const AndroidMemoryStoreScript := preload("res://scripts/android/android_memory_store.gd")
const MemoryQueryRouterScript := preload("res://scripts/core/memory/memory_query_router.gd")
const MemorySourceFetchersScript := preload("res://scripts/core/memory/memory_source_fetchers.gd")
const MemoryCandidatePoolBuilderScript := preload("res://scripts/core/memory/memory_candidate_pool_builder.gd")
const MemoryPolicyRerankerScript := preload("res://scripts/core/memory/memory_policy_reranker.gd")
const MemorySelectionFusionScript := preload("res://scripts/core/memory/memory_selection_fusion.gd")
const MemoryFormationScript := preload("res://scripts/core/memory/memory_formation.gd")
const MemoryVectorIndexScript := preload("res://scripts/core/memory/memory_vector_index.gd")
const MemoryMaintenanceEngineScript := preload("res://scripts/core/memory/memory_maintenance_engine.gd")
const SAVE_PATH := "user://play_with_me_memory.json"
const TOKEN_BUDGET := 4000
const MEMORY_SCHEMA_VERSION := 1
const RECORD_SCHEMA_VERSION := 1
const CONTEXT_SCHEMA_VERSION := 1

var persistence_enabled := true
var prefer_android_sqlite := true
var _states: Dictionary = {}
var _loaded := false
var _android_store = AndroidMemoryStoreScript.new()
var _query_router = MemoryQueryRouterScript.new()
var _source_fetchers = MemorySourceFetchersScript.new()
var _candidate_pool_builder = MemoryCandidatePoolBuilderScript.new()
var _policy_reranker = MemoryPolicyRerankerScript.new()
var _selection_fusion = MemorySelectionFusionScript.new()
var _memory_formation = MemoryFormationScript.new()
var _vector_index = MemoryVectorIndexScript.new()
var _maintenance_engine = MemoryMaintenanceEngineScript.new()
var _last_retrieval_report: Dictionary = {}
var _last_update_report: Dictionary = {}
var _last_maintenance_report: Dictionary = {}
var _last_retrieval_reports_by_scope: Dictionary = {}
var _last_update_reports_by_scope: Dictionary = {}
var _last_maintenance_reports_by_scope: Dictionary = {}


func load_or_create() -> void:
	if _loaded:
		return
	if _use_native_store():
		_loaded = true
		return
	if _should_wait_for_native_store():
		return
	_loaded = true
	if not persistence_enabled:
		_states.clear()
		return
	if not FileAccess.file_exists(SAVE_PATH):
		save()
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_apply_json(parsed as Dictionary)


func save() -> void:
	if not persistence_enabled:
		return
	if _use_native_store():
		return
	if _should_wait_for_native_store():
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(to_json(), "\t"))


func to_json() -> Dictionary:
	return {
		"memory_schema_version": MEMORY_SCHEMA_VERSION,
		"states": _states,
	}


func scope(owner_id: String, game_id: String, memory_namespace: String, map_id: String = "", room_id: String = "") -> Dictionary:
	return {
		"owner_id": owner_id.strip_edges(),
		"game_id": game_id.strip_edges(),
		"namespace": memory_namespace.strip_edges(),
		"map_id": map_id.strip_edges(),
		"room_id": room_id.strip_edges(),
	}


func scope_key(scope_data: Dictionary) -> String:
	return "|".join([
		_non_empty(String(scope_data.get("owner_id", "")), "unknown"),
		_non_empty(String(scope_data.get("game_id", "")), "game"),
		_non_empty(String(scope_data.get("map_id", "")), "-"),
		_non_empty(String(scope_data.get("room_id", "")), "-"),
		_non_empty(String(scope_data.get("namespace", "")), "session"),
	])


func init_memory(request: Dictionary) -> Dictionary:
	load_or_create()
	var scope_data := _request_scope(request)
	var key := scope_key(scope_data)
	var state := _mutable_state(scope_data)
	if _state_read_only(state):
		return _write_blocked_result(state, scope_data)
	var now := Time.get_unix_time_from_system()
	var persona_template = request.get("persona_template", {})
	var persona_content := _persona_content(persona_template)
	if persona_content != "":
		state["persona_snapshot"] = {
			"memory_id": "profile_%s" % _non_empty(String(scope_data.get("owner_id", "")), "unknown"),
			"bot_id": String(request.get("bot_id", scope_data.get("owner_id", ""))),
			"content": _trim_text(persona_content, 600),
			"structured_payload": _dict_or_empty(persona_template),
			"visibility": "self_private",
			"source": String(request.get("reason", "bot_created")),
			"status": "active",
			"importance": 0.82,
			"confidence": 0.80,
			"created_at": now,
			"updated_at": now,
			"evidence": [],
		}
	for target in _array_or_empty(request.get("initial_relationship_targets", [])):
		if not (target is Dictionary):
			continue
		var target_data: Dictionary = target
		var target_id := String(target_data.get("target_id", target_data.get("id", ""))).strip_edges()
		if target_id == "":
			continue
		_upsert_memory_record(state, {
			"memory_id": "relationship_%s_%s" % [String(scope_data.get("owner_id", "")), target_id],
			"bot_id": String(request.get("bot_id", scope_data.get("owner_id", ""))),
			"memory_type": "relationship",
			"scope_key": key,
			"scope": scope_data.duplicate(true),
			"domain_id": String(scope_data.get("game_id", "")),
			"session_id": String(scope_data.get("room_id", "")),
			"instance_id": String(scope_data.get("map_id", "")),
			"subject_id": target_id,
			"subject_type": String(target_data.get("target_type", "entity")),
			"content": String(target_data.get("content", "relationship target=%s initialized" % target_id)),
			"structured_payload": target_data.duplicate(true),
			"visibility": "self_private",
			"source": String(request.get("reason", "bot_created")),
			"importance": 0.55,
			"confidence": 0.60,
			"status": "active",
			"created_at": now,
			"updated_at": now,
			"evidence": [],
			"metadata": {},
			"embedding_status": "not_required",
		})
	_ensure_state_indexes(scope_data, state, {"reason": "init_memory"})
	_store_state(scope_data, state)
	return {
		"ok": true,
		"data": {
			"scope": scope_data.duplicate(true),
			"scope_key": key,
			"memory_counts": _memory_counts(state),
		},
		"warnings": [],
		"error": "",
	}


func load_state(scope_data: Dictionary) -> Dictionary:
	load_or_create()
	if _use_native_store():
		var native_state: Dictionary = _android_store.load_state(scope_data)
		if bool(native_state.get("ok", true)):
			return _normalize_state(native_state)
		push_warning(String(native_state.get("error", "SQLite memory load failed")))
	var key := scope_key(scope_data)
	if not _states.has(key):
		_states[key] = _empty_state(scope_data)
	return (_states[key] as Dictionary).duplicate(true)


func append(scope_data: Dictionary, entry: Dictionary) -> void:
	load_or_create()
	if _use_native_store():
		var result: Dictionary = _android_store.append(scope_data, entry)
		if bool(result.get("ok", false)):
			return
		push_warning(String(result.get("error", "SQLite memory append failed")))
	var key := scope_key(scope_data)
	var state := _state_ref(scope_data)
	if _state_read_only(state):
		push_warning("Memory state is read-only; append skipped")
		return
	var next_entry := {
		"content": String(entry.get("content", "")).strip_edges(),
		"visibility": _visibility(String(entry.get("visibility", "public"))),
		"created_at": float(entry.get("created_at", Time.get_unix_time_from_system())),
		"metadata": _dict_or_empty(entry.get("metadata", {})),
	}
	if String(next_entry["content"]) == "":
		return
	(state["recent_entries"] as Array).append(next_entry)
	_trim_recent_entries(state)
	_states[key] = state
	save()


func compact(scope_data: Dictionary, request: Dictionary) -> Dictionary:
	load_or_create()
	if _use_native_store():
		var result: Dictionary = _android_store.compact(scope_data, request)
		if bool(result.get("ok", false)):
			result.erase("ok")
			return result
		push_warning(String(result.get("error", "SQLite memory compact failed")))
	var key := scope_key(scope_data)
	var state := _state_ref(scope_data)
	if _state_read_only(state):
		return {"ok": false, "error": "memory_read_only", "summary": {}}
	var summary := {
		"day_number": int(request.get("day_number", 0)),
		"phase": String(request.get("phase", "")),
		"public_summary": String(request.get("public_summary", "")).strip_edges(),
		"private_summary": String(request.get("private_summary", "")).strip_edges(),
		"decision_summary": String(request.get("decision_summary", "")).strip_edges(),
		"suspicion_summary": String(request.get("suspicion_summary", "")).strip_edges(),
		"strategy_summary": String(request.get("strategy_summary", "")).strip_edges(),
	}
	(state["round_summaries"] as Array).append(summary)
	state["recent_entries"] = []
	_states[key] = state
	save()
	return summary


func save_long_term(scope_data: Dictionary, summary: String, user_approved: bool = true) -> void:
	if not user_approved:
		return
	load_or_create()
	if _use_native_store():
		var result: Dictionary = _android_store.save_long_term(scope_data, _trim_text(summary, 900), user_approved)
		if bool(result.get("ok", false)):
			return
		push_warning(String(result.get("error", "SQLite long-term memory save failed")))
	var key := scope_key(scope_data)
	var state := _state_ref(scope_data)
	if _state_read_only(state):
		push_warning("Memory state is read-only; long-term save skipped")
		return
	state["long_term_memory_summary"] = _trim_text(summary, 900)
	_states[key] = state
	save()


func update_memory(request: Dictionary) -> Dictionary:
	load_or_create()
	var scope_data := _request_scope(request)
	var key := scope_key(scope_data)
	var state := _mutable_state(scope_data)
	if _state_read_only(state):
		return _write_blocked_result(state, scope_data)
	var formation: Dictionary = _memory_formation.extract_update_candidates(request, key)
	var records := _array_or_empty(formation.get("records", []))
	var written: Array = []
	var merged: Array = []
	var skipped: Array = []
	for item in records:
		if not (item is Dictionary):
			continue
		var result := _upsert_memory_record(state, item as Dictionary)
		match String(result.get("action", "")):
			"written":
				written.append(result)
			"merged":
				merged.append(result)
			"skipped":
				skipped.append(result)
	var report := _dict_or_empty(formation.get("report", {}))
	report["written"] = written
	report["merged"] = merged
	var existing_skipped := _array_or_empty(report.get("skipped", []))
	for item in skipped:
		existing_skipped.append(item)
	report["skipped"] = existing_skipped
	var index_result := _refresh_state_indexes(scope_data, state, {"reason": "update_memory"})
	state = _dict_or_empty(index_result.get("state", state))
	var index_report := _dict_or_empty(index_result.get("report", {}))
	report["index_report"] = index_report
	report["embedding_jobs"] = _array_or_empty(index_report.get("embedding_jobs", report.get("embedding_jobs", [])))
	report["memory_counts"] = _memory_counts(state)
	_store_state(scope_data, state)
	_last_update_report = report.duplicate(true)
	_remember_report(scope_data, "memory_update", _last_update_report)
	if OS.is_debug_build():
		print("[MemoryManager][debug] update scope=%s records=%d written=%d merged=%d skipped=%d layers=%s" % [
			key,
			records.size(),
			written.size(),
			merged.size(),
			existing_skipped.size(),
			",".join(_array_or_empty(report.get("updated_layers", []))),
		])
	return {
		"ok": true,
		"data": {
			"memory_update_report": _last_update_report.duplicate(true),
			"memory_counts": _memory_counts(state),
		},
		"warnings": _array_or_empty(report.get("warnings", [])),
		"error": "",
	}


func clear_working_memory(request: Dictionary) -> Dictionary:
	load_or_create()
	var scope_data := _request_scope(request)
	var state := _mutable_state(scope_data)
	if _state_read_only(state):
		return _write_blocked_result(state, scope_data)
	var records := _array_or_empty(state.get("memory_records", []))
	var kept: Array = []
	var removed := 0
	for item in records:
		if item is Dictionary and String((item as Dictionary).get("memory_type", "")) == "working":
			removed += 1
			continue
		kept.append(item)
	state["memory_records"] = kept
	_store_state(scope_data, state)
	return {
		"ok": true,
		"data": {
			"removed_count": removed,
			"memory_counts": _memory_counts(state),
		},
		"warnings": [],
		"error": "",
	}


func maintain_memory(request: Dictionary) -> Dictionary:
	load_or_create()
	var scope_data := _request_scope(request)
	var state := _mutable_state(scope_data)
	if _state_read_only(state):
		return _write_blocked_result(state, scope_data)
	var maintain_request := request.duplicate(true)
	maintain_request["scope"] = scope_data
	var result: Dictionary = _maintenance_engine.maintain_state(state, maintain_request)
	state = _dict_or_empty(result.get("state", state))
	_store_state(scope_data, state)
	var report := _dict_or_empty(result.get("report", {}))
	report["scope"] = scope_data.duplicate(true)
	report["scope_key"] = scope_key(scope_data)
	report["memory_counts"] = _memory_counts(state)
	report["index_status"] = _index_status_for_state(state)
	_last_maintenance_report = report.duplicate(true)
	_remember_report(scope_data, "maintenance", _last_maintenance_report)
	if OS.is_debug_build():
		print("[MemoryManager][debug] maintain scope=%s type=%s distilled=%d merged=%d archived=%d vector=%s" % [
			scope_key(scope_data),
			String(report.get("maintenance_type", "")),
			int(report.get("distilled_count", 0)),
			int(report.get("merged_count", 0)),
			int(report.get("archived_count", 0)),
			str(bool((_dict_or_empty(report.get("index_status", {}))).get("vector_enabled", false))),
		])
	return {
		"ok": true,
		"data": {
			"maintenance_report": _last_maintenance_report.duplicate(true),
			"memory_counts": _memory_counts(state),
		},
		"warnings": _array_or_empty(report.get("warnings", [])),
		"error": "",
	}


func get_last_update_report(request: Dictionary = {}) -> Dictionary:
	var scope_data := _request_scope(request) if not request.is_empty() else {}
	if not scope_data.is_empty():
		return _report_for_scope(scope_data, "memory_update")
	return _last_update_report.duplicate(true)


func delete_scope(scope_data: Dictionary) -> void:
	load_or_create()
	if _use_native_store():
		var result: Dictionary = _android_store.delete_scope(scope_data)
		if bool(result.get("ok", false)):
			return
		push_warning(String(result.get("error", "SQLite memory delete failed")))
	var key := scope_key(scope_data)
	_states.erase(key)
	_last_retrieval_reports_by_scope.erase(key)
	_last_update_reports_by_scope.erase(key)
	_last_maintenance_reports_by_scope.erase(key)
	save()


func discard_session(scope_data: Dictionary) -> void:
	if String(scope_data.get("room_id", "")).strip_edges() == "":
		return
	if _use_native_store():
		var result: Dictionary = _android_store.discard_session(scope_data)
		if bool(result.get("ok", false)):
			return
		push_warning(String(result.get("error", "SQLite session memory discard failed")))
	delete_scope(scope_data)


func list_scopes(owner_id: String = "", game_id: String = "", memory_namespace: String = "") -> Array:
	load_or_create()
	if _use_native_store():
		return _android_store.list_scopes(owner_id, game_id, memory_namespace)
	var scopes := []
	for key in _states.keys():
		var state: Dictionary = _states[key]
		var scope_data: Dictionary = state.get("scope", {})
		if owner_id != "" and String(scope_data.get("owner_id", "")) != owner_id:
			continue
		if game_id != "" and String(scope_data.get("game_id", "")) != game_id:
			continue
		if memory_namespace != "" and String(scope_data.get("namespace", "")) != memory_namespace:
			continue
		scopes.append(scope_data.duplicate(true))
	return scopes


func prompt_context(scope_data: Dictionary, max_entries: int = 8, max_summaries: int = 4) -> Dictionary:
	var state := load_state(scope_data)
	return {
		"longTermMemorySummary": String(state.get("long_term_memory_summary", "")),
		"recentMemoryEntries": _tail_entries(state.get("recent_entries", []), max_entries),
		"roundSummaries": _tail_entries(state.get("round_summaries", []), max_summaries),
		"tokenBudget": int(state.get("token_budget", TOKEN_BUDGET)),
	}


func retrieve(scope_data: Dictionary, query: String, limit: int = 4, include_long_term: bool = true) -> Array:
	var result := retrieve_with_report(scope_data, query, limit, include_long_term)
	return result.get("items", []) as Array


func retrieve_with_report(scope_data: Dictionary, query: String, limit: int = 4, include_long_term: bool = true) -> Dictionary:
	var normalized_query := query.strip_edges()
	if normalized_query == "" or limit <= 0:
		_last_retrieval_report = _empty_retrieval_report(scope_data, normalized_query, limit, "empty_query_or_limit")
		_remember_report(scope_data, "context_build", _last_retrieval_report)
		return {
			"items": [],
			"agent_memory_context": {},
			"retrieval_report": _last_retrieval_report.duplicate(true),
			"warnings": _array_or_empty(_last_retrieval_report.get("warnings", [])),
		}
	return _retrieve_current_with_report(scope_data, normalized_query, limit, include_long_term)


func _retrieve_current_with_report(scope_data: Dictionary, query: String, limit: int, include_long_term: bool) -> Dictionary:
	var state := load_state(scope_data)
	var query_plan := _query_router.build_plan({
		"scope": scope_data,
		"query": query,
		"limit": limit,
		"include_long_term": include_long_term,
		"max_token_budget": int(state.get("token_budget", TOKEN_BUDGET)),
		"retrieval_hints": [],
	})
	var raw_candidates := _retrieval_candidates(state, include_long_term)
	var source_report := {
		"candidate_count": raw_candidates.size(),
		"source_counts": _source_counts(raw_candidates),
		"structured_count": 0,
		"warnings": [],
	}
	var candidate_pool: Dictionary = _candidate_pool_builder.build_pool(raw_candidates, query_plan)
	var reranked: Dictionary = _policy_reranker.rerank(candidate_pool.get("candidates", []) as Array, query_plan)
	var selected: Dictionary = _selection_fusion.select(reranked.get("candidates", []) as Array, query_plan)
	_last_retrieval_report = _build_retrieval_report(
		query_plan,
		source_report,
		candidate_pool.get("report", {}) as Dictionary,
		reranked.get("report", {}) as Dictionary,
		selected.get("report", {}) as Dictionary,
		selected.get("items", []) as Array
	)
	_remember_report(scope_data, "context_build", _last_retrieval_report)
	if OS.is_debug_build():
		print("[MemoryManager][debug] current retrieve mode=%s scope=%s query_chars=%d raw=%d kept=%d selected=%d warnings=%s" % [
			String(_last_retrieval_report.get("retrieval_mode", "")),
			scope_key(scope_data),
			query.length(),
			raw_candidates.size(),
			int((candidate_pool.get("report", {}) as Dictionary).get("kept_count", 0)),
			int((selected.get("items", []) as Array).size()),
			",".join(_array_or_empty(_last_retrieval_report.get("warnings", []))),
		])
	return {
		"items": (selected.get("items", []) as Array).duplicate(true),
		"agent_memory_context": (selected.get("agent_memory_context", {}) as Dictionary).duplicate(true),
		"retrieval_report": _last_retrieval_report.duplicate(true),
		"warnings": _array_or_empty(_last_retrieval_report.get("warnings", [])),
	}


func _retrieve_with_report_request(request: Dictionary) -> Dictionary:
	var scope_data := _dict_or_empty(request.get("scope", {}))
	var normalized_query := String(request.get("query", "")).strip_edges()
	var limit := int(request.get("limit", 24))
	var include_long_term := bool(request.get("include_long_term", true))
	if normalized_query == "":
		normalized_query = "memory_context"
	request["query"] = normalized_query
	request["limit"] = limit
	request["include_long_term"] = include_long_term
	var state := load_state(scope_data)
	state = _ensure_state_indexes(scope_data, state, {"reason": "retrieve"})
	var options := _dict_or_empty(request.get("memory_options", {}))
	if not options.has("max_token_budget"):
		options["max_token_budget"] = int(request.get("max_token_budget", state.get("token_budget", TOKEN_BUDGET)))
	request["memory_options"] = options
	request["index_status"] = _index_status_for_state(state)
	var query_plan := _query_router.build_plan(request)
	if bool(query_plan.get("vector_enabled", false)):
		query_plan["query_embedding"] = _vector_index.embed_text(normalized_query)
		var query_embedding := _array_or_empty(query_plan.get("query_embedding", []))
		query_plan["native_vector_report"] = _native_vector_search(scope_data, query_embedding, query_plan)
		query_plan["native_vector_results"] = _array_or_empty((query_plan["native_vector_report"] as Dictionary).get("items", []))
	var fetched: Dictionary = _source_fetchers.fetch_sources(state, query_plan)
	var raw_candidates := _array_or_empty(fetched.get("candidates", []))
	var candidate_pool: Dictionary = _candidate_pool_builder.build_pool(raw_candidates, query_plan)
	var reranked: Dictionary = _policy_reranker.rerank(candidate_pool.get("candidates", []) as Array, query_plan)
	var selected: Dictionary = _selection_fusion.select(reranked.get("candidates", []) as Array, query_plan)
	_last_retrieval_report = _build_retrieval_report(
		query_plan,
		fetched.get("report", {}) as Dictionary,
		candidate_pool.get("report", {}) as Dictionary,
		reranked.get("report", {}) as Dictionary,
		selected.get("report", {}) as Dictionary,
		selected.get("items", []) as Array
	)
	_remember_report(scope_data, "context_build", _last_retrieval_report)
	if OS.is_debug_build():
		print("[MemoryManager][debug] retrieve mode=%s scope=%s query_chars=%d raw=%d kept=%d selected=%d warnings=%s" % [
			String(_last_retrieval_report.get("retrieval_mode", "")),
			scope_key(scope_data),
			normalized_query.length(),
			raw_candidates.size(),
			int((candidate_pool.get("report", {}) as Dictionary).get("kept_count", 0)),
			int((selected.get("items", []) as Array).size()),
			",".join(_array_or_empty(_last_retrieval_report.get("warnings", []))),
		])
	return {
		"items": (selected.get("items", []) as Array).duplicate(true),
		"agent_memory_context": (selected.get("agent_memory_context", {}) as Dictionary).duplicate(true),
		"retrieval_report": _last_retrieval_report.duplicate(true),
		"warnings": _array_or_empty(_last_retrieval_report.get("warnings", [])),
	}


func get_memory_context(request: Dictionary) -> Dictionary:
	var scope_data := _dict_or_empty(request.get("scope", {}))
	var query := String(request.get("query", "")).strip_edges()
	if query == "":
		query = _query_from_visible_facts(request.get("visible_context_facts", []))
	if query == "":
		query = "memory_context"
	var options := _dict_or_empty(request.get("memory_options", {}))
	var limit := int(options.get("final_max_items", request.get("limit", 24)))
	var include_long_term := bool(options.get("include_long_term", request.get("include_long_term", true)))
	var retrieval_request := request.duplicate(true)
	retrieval_request["scope"] = scope_data
	retrieval_request["query"] = query
	retrieval_request["limit"] = limit
	retrieval_request["include_long_term"] = include_long_term
	var result := _retrieve_with_report_request(retrieval_request)
	return {
		"ok": true,
		"data": {
			"memory_context": (result.get("agent_memory_context", {}) as Dictionary).duplicate(true),
			"items": (result.get("items", []) as Array).duplicate(true),
			"retrieval_report": (result.get("retrieval_report", {}) as Dictionary).duplicate(true),
		},
		"warnings": _array_or_empty(result.get("warnings", [])),
		"error": "",
	}


func get_last_retrieval_report(request: Dictionary = {}) -> Dictionary:
	var scope_data := _request_scope(request) if not request.is_empty() else {}
	if not scope_data.is_empty():
		return _report_for_scope(scope_data, "context_build")
	return _last_retrieval_report.duplicate(true)


func get_memory_overview(request: Dictionary) -> Dictionary:
	var scope_data := _request_scope(request)
	var state := load_state(scope_data)
	state = _ensure_state_indexes(scope_data, state, {"reason": "overview"})
	var redact_private := bool(request.get("redact_private", true))
	var include_recent_samples := bool(request.get("include_recent_samples", false))
	var counts := _memory_counts(state)
	var index_status := _index_status_for_state(state)
	var latest_reports := _latest_report_summaries(scope_data)
	return {
		"ok": true,
		"data": {
			"scope": scope_data.duplicate(true),
			"memory_health": {
				"status": _memory_health_status(counts, index_status),
				"schema_version": int(state.get("memory_schema_version", MEMORY_SCHEMA_VERSION)),
				"memory_schema_version": int(state.get("memory_schema_version", MEMORY_SCHEMA_VERSION)),
				"record_schema_version": int(state.get("record_schema_version", RECORD_SCHEMA_VERSION)),
				"context_schema_version": int(state.get("context_schema_version", CONTEXT_SCHEMA_VERSION)),
				"read_only": bool(state.get("read_only", false)),
				"warnings": _overview_warnings(index_status),
				"last_updated_at": _last_memory_updated_at(state),
			},
			"layer_counts": counts,
			"index_status": index_status,
			"persona_snapshot": _persona_summary(_dict_or_empty(state.get("persona_snapshot", {})), redact_private),
			"relationship_state": _dict_or_empty(state.get("relationship_state", {})),
			"conflict_records": _array_or_empty(state.get("conflict_records", [])),
			"recent_samples": _recent_memory_samples(state, include_recent_samples, redact_private),
			"latest_reports": latest_reports,
		},
		"warnings": [],
		"error": "",
	}


func list_memory_records(request: Dictionary) -> Dictionary:
	var scope_data := _request_scope(request)
	var state := load_state(scope_data)
	state = _ensure_state_indexes(scope_data, state, {"reason": "list_memory_records"})
	var records := _array_or_empty(state.get("memory_records", []))
	var memory_type := String(request.get("memory_type", "")).strip_edges()
	var status := String(request.get("status", "")).strip_edges()
	var conflict_status := String(request.get("conflict_status", "")).strip_edges()
	var subject_id := String(request.get("subject_id", "")).strip_edges()
	var query := String(request.get("query", "")).strip_edges().to_lower()
	var limit := maxi(1, int(request.get("limit", 50)))
	var offset := maxi(0, int(request.get("offset", 0)))
	var redact_private := bool(request.get("redact_private", true))
	var filtered: Array = []
	for item in records:
		if not (item is Dictionary):
			continue
		var record: Dictionary = item
		if memory_type != "" and String(record.get("memory_type", "")) != memory_type:
			continue
		if status != "" and String(record.get("status", "")) != status:
			continue
		if conflict_status != "" and String(record.get("conflict_status", _dict_or_empty(record.get("metadata", {})).get("conflict_status", ""))) != conflict_status:
			continue
		if subject_id != "" and String(record.get("subject_id", "")) != subject_id:
			continue
		if query != "" and not _record_matches_query(record, query):
			continue
		filtered.append(record)
	filtered.sort_custom(_sort_memory_records)
	var total := filtered.size()
	var page_items: Array = []
	var end := mini(total, offset + limit)
	for i in range(offset, end):
		page_items.append(_record_summary(filtered[i] as Dictionary, redact_private))
	return {
		"ok": true,
		"data": {
			"items": page_items,
			"total": total,
			"page_report": {
				"offset": offset,
				"limit": limit,
				"returned": page_items.size(),
				"filters": {
					"memory_type": memory_type,
					"status": status,
					"conflict_status": conflict_status,
					"subject_id": subject_id,
					"query": query,
				},
				"redact_private": redact_private,
				"source": "memory_records",
			},
		},
		"warnings": [],
		"error": "",
	}


func get_memory_reports(request: Dictionary) -> Dictionary:
	var requested_types := _string_array(request.get("report_types", ["context_build", "memory_update", "maintenance", "index"]))
	if requested_types.is_empty():
		requested_types = ["context_build", "memory_update", "maintenance", "index"]
	var limit := maxi(1, int(request.get("limit", 20)))
	var redact_private := bool(request.get("redact_private", true))
	var latest := _latest_reports_full(request, redact_private)
	var reports: Array = []
	for report_type in requested_types:
		var report := _dict_or_empty(latest.get(report_type, {}))
		if report.is_empty():
			continue
		reports.append({
			"report_type": report_type,
			"payload": report,
			"created_at": float(report.get("created_at", 0.0)),
		})
		if reports.size() >= limit:
			break
	return {
		"ok": true,
		"data": {
			"reports": reports,
			"latest": latest,
			"warnings": [],
		},
		"warnings": [],
		"error": "",
	}


func get_memory_index_status(request: Dictionary) -> Dictionary:
	var scope_data := _request_scope(request)
	var state := load_state(scope_data)
	state = _ensure_state_indexes(scope_data, state, {"reason": "index_status"})
	return {
		"ok": true,
		"data": _index_status_for_state(state),
		"warnings": [],
		"error": "",
	}


func delete_owner_memory(owner_id: String, game_id: String = "") -> void:
	load_or_create()
	if _use_native_store():
		var result: Dictionary = _android_store.delete_owner_memory(owner_id, game_id)
		if bool(result.get("ok", false)):
			return
		push_warning(String(result.get("error", "SQLite owner memory delete failed")))
	var targets := []
	for key in _states.keys():
		var state: Dictionary = _states[key]
		var scope_data: Dictionary = state.get("scope", {})
		if String(scope_data.get("owner_id", "")) != owner_id:
			continue
		if game_id != "" and String(scope_data.get("game_id", "")) != game_id:
			continue
		targets.append(key)
	for key in targets:
		_states.erase(key)
	save()


func native_index_names() -> Array:
	if _use_native_store() and _android_store.has_method("list_index_names"):
		return _android_store.list_index_names()
	return []


func native_index_status() -> Dictionary:
	if _use_native_store() and _android_store.has_method("index_status"):
		return _android_store.index_status()
	return {}


func _build_retrieval_report(query_plan: Dictionary, source_fetch_report: Dictionary, candidate_pool_report: Dictionary, rerank_report: Dictionary, fusion_report: Dictionary, selected_items: Array) -> Dictionary:
	var warnings := _array_or_empty(query_plan.get("warnings", []))
	for item in _array_or_empty(source_fetch_report.get("warnings", [])):
		warnings.append(item)
	var dropped_items := []
	for key in ["dropped"]:
		for item in _array_or_empty(candidate_pool_report.get(key, [])):
			dropped_items.append(item)
		for item in _array_or_empty(rerank_report.get(key, [])):
			dropped_items.append(item)
		for item in _array_or_empty(fusion_report.get(key, [])):
			dropped_items.append(item)
	return {
		"retrieval_mode": String(query_plan.get("retrieval_mode", "text_retrieval")),
		"vector_enabled": bool(query_plan.get("vector_enabled", false)),
		"embedding_enabled": bool(query_plan.get("embedding_enabled", false)),
		"vector_sources": _dict_or_empty(query_plan.get("vector_sources", {})),
		"query_plan": query_plan.duplicate(true),
		"queries": _array_or_empty(query_plan.get("queries", [])),
		"filters": _dict_or_empty(query_plan.get("filters", {})),
		"candidate_counts": {
			"raw": int(source_fetch_report.get("candidate_count", candidate_pool_report.get("input_count", 0))),
			"pooled": int(candidate_pool_report.get("kept_count", 0)),
			"scored": int(rerank_report.get("scored_count", 0)),
			"selected": selected_items.size(),
			"dropped": dropped_items.size(),
		},
		"source_fetch_report": source_fetch_report.duplicate(true),
		"candidate_pool_report": candidate_pool_report.duplicate(true),
		"rerank_report": rerank_report.duplicate(true),
		"fusion_report": fusion_report.duplicate(true),
		"selected_items": _retrieval_report_items(selected_items),
		"dropped_items": dropped_items,
		"budget_report": {
			"final_max_items": int(fusion_report.get("final_max_items", 0)),
			"selected_count": selected_items.size(),
			"dropped_count": int(fusion_report.get("dropped_count", 0)),
			"estimated_used": int(fusion_report.get("estimated_used", 0)),
			"kept_counts": _dict_or_empty(fusion_report.get("kept_counts", {})),
			"dropped_counts": _dict_or_empty(fusion_report.get("dropped_counts", {})),
			"drop_reasons": _dict_or_empty(fusion_report.get("drop_reasons", {})),
		},
		"warnings": warnings,
	}


func _empty_retrieval_report(scope_data: Dictionary, query: String, limit: int, reason: String) -> Dictionary:
	return {
		"retrieval_mode": "none",
		"vector_enabled": false,
		"embedding_enabled": false,
		"vector_sources": {
			"sqlite_vec_event": false,
			"hnsw_semantic": false,
		},
		"query_plan": {
			"queries": [{"type": "task_query", "text": query}],
			"filters": {
				"bot_id": String(scope_data.get("owner_id", "")),
				"namespace": String(scope_data.get("namespace", "")),
			},
			"budget_plan": {"final_max_items": limit},
		},
		"queries": [{"type": "task_query", "text": query}],
		"filters": {
			"bot_id": String(scope_data.get("owner_id", "")),
			"namespace": String(scope_data.get("namespace", "")),
		},
		"candidate_counts": {
			"raw": 0,
			"pooled": 0,
			"scored": 0,
			"selected": 0,
			"dropped": 0,
		},
		"source_fetch_report": {},
		"candidate_pool_report": {},
		"rerank_report": {},
		"fusion_report": {},
		"selected_items": [],
		"dropped_items": [],
		"budget_report": {"final_max_items": limit, "selected_count": 0},
		"warnings": [reason],
	}


func _retrieval_report_items(items: Array) -> Array:
	var result := []
	for item in items:
		if not (item is Dictionary):
			continue
		var entry: Dictionary = item
		result.append({
			"memory_id": String(entry.get("memory_id", "")),
			"memory_type": String(entry.get("memory_type", "")),
			"source": String(entry.get("source", "")),
			"retrieval_source": String(entry.get("retrieval_source", "")),
			"visibility": String(entry.get("visibility", "")),
			"score": entry.get("score", 0.0),
			"lexical_score": entry.get("lexical_score", 0.0),
			"vector_score": entry.get("vector_score", null),
			"importance": entry.get("importance", 0.0),
			"confidence": entry.get("confidence", 0.0),
			"drop_reason": String(entry.get("drop_reason", "")),
		})
	return result


func _query_from_visible_facts(value) -> String:
	var facts := _array_or_empty(value)
	var parts := []
	for item in facts:
		if item is Dictionary:
			var text := String((item as Dictionary).get("text", "")).strip_edges()
			if text == "":
				text = String((item as Dictionary).get("content", "")).strip_edges()
			if text != "":
				parts.append(text)
		else:
			var raw := String(item).strip_edges()
			if raw != "":
				parts.append(raw)
	return "\n".join(parts)


func _apply_json(data: Dictionary) -> void:
	var states = data.get("states", {})
	if not (states is Dictionary):
		return
	_states.clear()
	for key in states.keys():
		var state = states[key]
		if state is Dictionary:
			_states[String(key)] = _normalize_state(state as Dictionary)


func _request_scope(request: Dictionary) -> Dictionary:
	var scope_data := _dict_or_empty(request.get("scope", {}))
	if not scope_data.is_empty():
		return scope_data
	var bot_id := String(request.get("bot_id", request.get("owner_id", ""))).strip_edges()
	return scope(
		bot_id,
		String(request.get("domain_id", request.get("game_id", ""))),
		String(request.get("memory_namespace", bot_id)),
		String(request.get("map_id", "")),
		String(request.get("session_id", request.get("room_id", "")))
	)


func _persona_content(persona_template) -> String:
	if persona_template is Dictionary:
		var data: Dictionary = persona_template
		for key in ["content", "persona", "description", "profile"]:
			var text := String(data.get(key, "")).strip_edges()
			if text != "":
				return text
		return JSON.stringify(data)
	return String(persona_template).strip_edges()


func _upsert_memory_record(state: Dictionary, record: Dictionary) -> Dictionary:
	var records := _array_or_empty(state.get("memory_records", []))
	var memory_id := String(record.get("memory_id", "")).strip_edges()
	var content := String(record.get("content", "")).strip_edges()
	var memory_type := String(record.get("memory_type", "")).strip_edges()
	var subject_id := String(record.get("subject_id", "")).strip_edges()
	if content == "" or memory_type == "":
		return {"action": "skipped", "reason": "schema_invalid", "memory_id": memory_id}
	for i in range(records.size()):
		if not (records[i] is Dictionary):
			continue
		var existing: Dictionary = records[i]
		var existing_id := String(existing.get("memory_id", "")).strip_edges()
		var same_id := memory_id != "" and existing_id == memory_id
		var same_content := (
			String(existing.get("memory_type", "")) == memory_type
			and String(existing.get("subject_id", "")) == subject_id
			and String(existing.get("content", "")).strip_edges() == content
		)
		if same_id or same_content:
			var merged := existing.duplicate(true)
			merged["updated_at"] = Time.get_unix_time_from_system()
			merged["importance"] = maxf(float(existing.get("importance", 0.0)), float(record.get("importance", 0.0)))
			merged["confidence"] = maxf(float(existing.get("confidence", 0.0)), float(record.get("confidence", 0.0)))
			merged["status"] = String(record.get("status", existing.get("status", "active")))
			merged["evidence"] = _merge_evidence(_array_or_empty(existing.get("evidence", [])), _array_or_empty(record.get("evidence", [])))
			records[i] = merged
			state["memory_records"] = records
			return {"action": "merged", "memory_id": String(merged.get("memory_id", memory_id)), "memory_type": memory_type}
	var stored := record.duplicate(true)
	if memory_id == "":
		stored["memory_id"] = "%s_%d_%d" % [memory_type, int(Time.get_unix_time_from_system() * 1000.0), records.size()]
	records.append(stored)
	state["memory_records"] = records
	return {"action": "written", "memory_id": String(stored.get("memory_id", "")), "memory_type": memory_type}


func _merge_evidence(left: Array, right: Array) -> Array:
	var result: Array = []
	var seen := {}
	for source in [left, right]:
		for item in source:
			var key := JSON.stringify(item)
			if seen.has(key):
				continue
			seen[key] = true
			result.append(item)
	return result


func _memory_counts(state: Dictionary) -> Dictionary:
	var counts := {
		"profile": 0,
		"working": 0,
		"relationship": 0,
		"semantic": 0,
		"episodic": 0,
		"reflection": 0,
	}
	if not _dict_or_empty(state.get("persona_snapshot", {})).is_empty():
		counts["profile"] = 1
	for item in _array_or_empty(state.get("memory_records", [])):
		if not (item is Dictionary):
			continue
		var memory_type := String((item as Dictionary).get("memory_type", "")).strip_edges()
		if memory_type == "":
			continue
		counts[memory_type] = int(counts.get(memory_type, 0)) + 1
	return counts


func _ensure_state_indexes(scope_data: Dictionary, state: Dictionary, options: Dictionary = {}) -> Dictionary:
	var result := _refresh_state_indexes(scope_data, state, options)
	return _dict_or_empty(result.get("state", state))


func _refresh_state_indexes(scope_data: Dictionary, state: Dictionary, options: Dictionary = {}) -> Dictionary:
	var result: Dictionary = _vector_index.refresh_state_indexes(state, options)
	var indexed_state := _dict_or_empty(result.get("state", state))
	var native_report := _native_rebuild_indexes(scope_data, indexed_state)
	if not native_report.is_empty():
		var vector_index := _dict_or_empty(indexed_state.get("vector_index", {}))
		vector_index["native_backend_status"] = native_report.duplicate(true)
		if bool(native_report.get("native_sqlite_vec_enabled", false)) or bool(native_report.get("native_hnswlib_enabled", false)):
			vector_index["backend"] = "godot_local_embedding_with_android_native_index"
			if bool(native_report.get("native_sqlite_vec_enabled", false)):
				vector_index["event_backend"] = "sqlite-vec"
			if bool(native_report.get("native_hnswlib_enabled", false)):
				vector_index["semantic_backend"] = "hnswlib"
		indexed_state["vector_index"] = vector_index
		var report := _dict_or_empty(result.get("report", {}))
		report["native_backend_status"] = native_report.duplicate(true)
		result["report"] = report
	if bool((_dict_or_empty(result.get("report", {}))).get("changed", false)):
		_store_state(scope_data, indexed_state)
	result["state"] = indexed_state
	return result


func _native_rebuild_indexes(scope_data: Dictionary, state: Dictionary) -> Dictionary:
	if _use_native_store() and _android_store.has_method("native_rebuild_indexes"):
		var result: Dictionary = _android_store.native_rebuild_indexes(scope_data, state)
		if bool(result.get("ok", false)) or result.has("native_sqlite_vec_enabled") or result.has("native_hnswlib_enabled"):
			return result
		return {
			"ok": false,
			"native_sqlite_vec_enabled": false,
			"native_hnswlib_enabled": false,
			"error": String(result.get("error", "native_vector_rebuild_failed")),
			"warnings": _array_or_empty(result.get("warnings", ["native_vector_rebuild_failed"])),
		}
	return {}


func _native_vector_search(scope_data: Dictionary, query_embedding: Array, query_plan: Dictionary) -> Dictionary:
	if query_embedding.is_empty():
		return {}
	if _use_native_store() and _android_store.has_method("native_vector_search"):
		var sources := _dict_or_empty(query_plan.get("vector_sources", {}))
		if not bool(sources.get("native_sqlite_vec", false)) and not bool(sources.get("native_hnswlib", false)):
			return {}
		var result: Dictionary = _android_store.native_vector_search(scope_data, query_embedding, query_plan)
		if bool(result.get("ok", false)) or result.has("items"):
			return result
		return {
			"ok": false,
			"items": [],
			"error": String(result.get("error", "native_vector_search_failed")),
			"warnings": _array_or_empty(result.get("warnings", ["native_vector_search_failed"])),
		}
	return {}


func _index_status_for_state(state: Dictionary) -> Dictionary:
	var pending := 0
	var failed := 0
	var stale := 0
	var ready := 0
	var required := 0
	for item in _array_or_empty(state.get("memory_records", [])):
		if not (item is Dictionary):
			continue
		var record: Dictionary = item
		if _vector_index.embedding_required(record):
			required += 1
		match String(record.get("embedding_status", "not_required")):
			"pending":
				pending += 1
			"failed":
				failed += 1
			"stale":
				stale += 1
			"ready":
				ready += 1
	var vector_index := _dict_or_empty(state.get("vector_index", {}))
	var graph := _dict_or_empty(state.get("semantic_hnsw_graph", {}))
	var event_vectors := int(vector_index.get("event_vector_count", 0))
	var semantic_vectors := int(vector_index.get("semantic_vector_count", 0))
	var vector_enabled := ready > 0 and pending == 0 and failed == 0 and stale == 0
	var retrieval_mode := "hybrid_vector" if vector_enabled else "text_retrieval"
	var native_status := _dict_or_empty(vector_index.get("native_backend_status", {}))
	if native_status.is_empty():
		native_status = native_index_status()
	var native_names := native_index_names()
	var native_sqlite_enabled := bool(native_status.get("native_sqlite_vec_enabled", native_status.get("sqlite_vec_event_enabled", native_names.has("sqlite_vec_event"))))
	var native_hnsw_enabled := bool(native_status.get("native_hnswlib_enabled", native_status.get("hnsw_semantic_enabled", native_names.has("hnsw_semantic"))))
	var warnings: Array = []
	if not vector_enabled:
		warnings.append("vector_unavailable_text_retrieval")
	if bool(state.get("read_only", false)):
		warnings.append("memory_read_only")
	if pending > 0:
		warnings.append("embedding_pending")
	if stale > 0:
		warnings.append("embedding_stale")
	if failed > 0:
		warnings.append("embedding_failed")
	for item in _array_or_empty(native_status.get("warnings", [])):
		if not warnings.has(item):
			warnings.append(item)
	return {
		"retrieval_mode": retrieval_mode,
		"vector_enabled": vector_enabled,
		"embedding_enabled": vector_enabled,
		"sqlite_vec_event_enabled": event_vectors > 0,
		"hnsw_semantic_enabled": semantic_vectors > 0,
		"native_sqlite_vec_enabled": native_sqlite_enabled,
		"native_hnswlib_enabled": native_hnsw_enabled,
		"embedding_provider": String(vector_index.get("provider", "")),
		"embedding_model": String(vector_index.get("model", "")),
		"embedding_version": String(vector_index.get("version", "")),
		"embedding_dimension": int(vector_index.get("dimension", 0)),
		"vector_backend": String(vector_index.get("backend", "")),
		"event_vector_count": event_vectors,
		"semantic_vector_count": semantic_vectors,
		"hnsw_graph_nodes": int(graph.get("nodes", 0)),
		"hnsw_graph_edges": int(graph.get("edges", 0)),
		"required_embedding_count": required,
		"pending_embedding_count": pending,
		"failed_embedding_count": failed,
		"stale_index_count": stale,
		"ready_embedding_count": ready,
		"native_index_names": native_names,
		"native_backend_status": native_status,
		"memory_schema_version": int(state.get("memory_schema_version", MEMORY_SCHEMA_VERSION)),
		"record_schema_version": int(state.get("record_schema_version", RECORD_SCHEMA_VERSION)),
		"context_schema_version": int(state.get("context_schema_version", CONTEXT_SCHEMA_VERSION)),
		"read_only": bool(state.get("read_only", false)),
		"warnings": warnings,
	}


func _memory_health_status(counts: Dictionary, index_status: Dictionary) -> String:
	if bool(index_status.get("read_only", false)):
		return "read_only"
	var total := 0
	for key in ["profile", "working", "relationship", "semantic", "episodic", "reflection"]:
		total += int(counts.get(key, 0))
	if total <= 0:
		return "empty"
	if int(index_status.get("failed_embedding_count", 0)) > 0:
		return "degraded"
	if not bool(index_status.get("vector_enabled", false)):
		return "text_retrieval"
	return "ok"


func _overview_warnings(index_status: Dictionary) -> Array:
	var warnings: Array = []
	for item in _array_or_empty(index_status.get("warnings", [])):
		warnings.append(item)
	return warnings


func _last_memory_updated_at(state: Dictionary) -> float:
	var latest := 0.0
	var persona := _dict_or_empty(state.get("persona_snapshot", {}))
	latest = maxf(latest, float(persona.get("updated_at", persona.get("created_at", 0.0))))
	for item in _array_or_empty(state.get("memory_records", [])):
		if item is Dictionary:
			var record: Dictionary = item
			latest = maxf(latest, float(record.get("updated_at", record.get("created_at", 0.0))))
	return latest


func _persona_summary(persona: Dictionary, redact_private: bool) -> Dictionary:
	if persona.is_empty():
		return {}
	var content := String(persona.get("content", ""))
	var visibility := String(persona.get("visibility", "self_private"))
	return {
		"memory_id": String(persona.get("memory_id", "")),
		"bot_id": String(persona.get("bot_id", "")),
		"content": _redact_content(content, visibility, redact_private),
		"content_preview": _preview_text(_redact_content(content, visibility, redact_private), 80),
		"visibility": visibility,
		"status": String(persona.get("status", "active")),
		"source": String(persona.get("source", "")),
		"importance": float(persona.get("importance", 0.0)),
		"confidence": float(persona.get("confidence", 0.0)),
		"updated_at": float(persona.get("updated_at", 0.0)),
	}


func _recent_memory_samples(state: Dictionary, include_recent_samples: bool, redact_private: bool) -> Array:
	if not include_recent_samples:
		return []
	var records := _array_or_empty(state.get("memory_records", []))
	records.sort_custom(_sort_memory_records)
	var samples: Array = []
	var limit := mini(5, records.size())
	for i in range(limit):
		if records[i] is Dictionary:
			samples.append(_record_summary(records[i] as Dictionary, redact_private))
	return samples


func _record_summary(record: Dictionary, redact_private: bool) -> Dictionary:
	var content := String(record.get("content", ""))
	var visibility := String(record.get("visibility", "self_private"))
	var visible_content := _redact_content(content, visibility, redact_private)
	return {
		"memory_id": String(record.get("memory_id", "")),
		"bot_id": String(record.get("bot_id", "")),
		"memory_type": String(record.get("memory_type", "")),
		"subject_id": String(record.get("subject_id", "")),
		"subject_type": String(record.get("subject_type", "")),
		"content": visible_content,
		"content_preview": _preview_text(visible_content, 96),
		"visibility": visibility,
		"source": String(record.get("source", "")),
		"importance": float(record.get("importance", 0.0)),
		"confidence": float(record.get("confidence", 0.0)),
		"status": String(record.get("status", "")),
		"conflict_status": String(record.get("conflict_status", _dict_or_empty(record.get("metadata", {})).get("conflict_status", ""))),
		"created_at": float(record.get("created_at", 0.0)),
		"updated_at": float(record.get("updated_at", 0.0)),
		"embedding_status": String(record.get("embedding_status", "")),
		"evidence_count": _array_or_empty(record.get("evidence", [])).size(),
	}


func _record_matches_query(record: Dictionary, query: String) -> bool:
	if String(record.get("content", "")).to_lower().contains(query):
		return true
	if String(record.get("subject_id", "")).to_lower().contains(query):
		return true
	if String(record.get("source", "")).to_lower().contains(query):
		return true
	return false


func _sort_memory_records(a, b) -> bool:
	var left: Dictionary = a if a is Dictionary else {}
	var right: Dictionary = b if b is Dictionary else {}
	var left_time := float(left.get("updated_at", left.get("created_at", 0.0)))
	var right_time := float(right.get("updated_at", right.get("created_at", 0.0)))
	if left_time == right_time:
		return String(left.get("memory_id", "")) < String(right.get("memory_id", ""))
	return left_time > right_time


func _redact_content(content: String, visibility: String, redact_private: bool) -> String:
	if not redact_private:
		return content
	if visibility == "public" or visibility == "observer_safe":
		return content
	return "[private]"


func _preview_text(content: String, max_chars: int) -> String:
	var normalized := content.strip_edges().replace("\n", " ")
	if normalized.length() <= max_chars:
		return normalized
	return normalized.substr(0, maxi(0, max_chars - 3)) + "..."


func _remember_report(scope_data: Dictionary, report_type: String, report: Dictionary) -> void:
	var key := scope_key(scope_data)
	match report_type:
		"context_build":
			_last_retrieval_reports_by_scope[key] = report.duplicate(true)
		"memory_update":
			_last_update_reports_by_scope[key] = report.duplicate(true)
		"maintenance":
			_last_maintenance_reports_by_scope[key] = report.duplicate(true)


func _report_for_scope(scope_data: Dictionary, report_type: String) -> Dictionary:
	var key := scope_key(scope_data)
	match report_type:
		"context_build":
			return _dict_or_empty(_last_retrieval_reports_by_scope.get(key, {}))
		"memory_update":
			return _dict_or_empty(_last_update_reports_by_scope.get(key, {}))
		"maintenance":
			return _dict_or_empty(_last_maintenance_reports_by_scope.get(key, {}))
		_:
			return {}


func _latest_report_summaries(scope_data: Dictionary) -> Dictionary:
	return {
		"context_build": _report_summary(_report_for_scope(scope_data, "context_build")),
		"memory_update": _report_summary(_report_for_scope(scope_data, "memory_update")),
		"maintenance": _report_summary(_report_for_scope(scope_data, "maintenance")),
	}


func _report_summary(report: Dictionary) -> Dictionary:
	if report.is_empty():
		return {}
	return {
		"retrieval_mode": String(report.get("retrieval_mode", "")),
		"vector_enabled": bool(report.get("vector_enabled", false)),
		"updated_layers": _array_or_empty(report.get("updated_layers", [])),
		"candidate_counts": _dict_or_empty(report.get("candidate_counts", {})),
		"memory_counts": _dict_or_empty(report.get("memory_counts", {})),
		"warnings": _array_or_empty(report.get("warnings", [])),
	}


func _latest_reports_full(request: Dictionary, redact_private: bool) -> Dictionary:
	var scope_data := _request_scope(request)
	var state := load_state(scope_data)
	state = _ensure_state_indexes(scope_data, state, {"reason": "reports"})
	return {
		"context_build": _redact_report(_report_for_scope(scope_data, "context_build"), redact_private),
		"memory_update": _redact_report(_report_for_scope(scope_data, "memory_update"), redact_private),
		"maintenance": _redact_report(_report_for_scope(scope_data, "maintenance"), redact_private),
		"index": _index_status_for_state(state),
	}


func _redact_report(report: Dictionary, redact_private: bool) -> Dictionary:
	if report.is_empty():
		return {}
	if not redact_private:
		return report.duplicate(true)
	var copy := report.duplicate(true)
	copy.erase("selected_items")
	copy.erase("dropped_items")
	return copy


func _string_array(value) -> Array:
	var result: Array = []
	for item in _array_or_empty(value):
		var text := String(item).strip_edges()
		if text != "":
			result.append(text)
	return result


func _use_native_store() -> bool:
	return persistence_enabled and prefer_android_sqlite and _android_store != null and _android_store.is_available()


func _should_wait_for_native_store() -> bool:
	return persistence_enabled and prefer_android_sqlite and OS.get_name() == "Android" and _android_store != null


func _state_read_only(state: Dictionary) -> bool:
	return bool(state.get("read_only", false))


func _write_blocked_result(state: Dictionary, scope_data: Dictionary) -> Dictionary:
	return {
		"ok": false,
		"data": {
			"scope": scope_data.duplicate(true),
			"memory_health": {
				"status": "read_only",
			},
		},
		"warnings": ["memory_read_only"],
		"error": "memory_read_only",
		"code": "memory_read_only",
	}


func _state_ref(scope_data: Dictionary) -> Dictionary:
	var key := scope_key(scope_data)
	if not _states.has(key):
		_states[key] = _empty_state(scope_data)
	return _states[key] as Dictionary


func _mutable_state(scope_data: Dictionary) -> Dictionary:
	if _use_native_store():
		var native_state := load_state(scope_data)
		if bool(native_state.get("ok", true)):
			return _normalize_state(native_state)
		push_warning(String(native_state.get("error", "SQLite memory load failed")))
	return _state_ref(scope_data)


func _store_state(scope_data: Dictionary, state: Dictionary) -> void:
	var normalized := _normalize_state(state)
	if _use_native_store() and _android_store.has_method("save_state"):
		var result: Dictionary = _android_store.save_state(scope_data, normalized)
		if bool(result.get("ok", false)):
			return
		push_warning(String(result.get("error", "SQLite memory save state failed")))
	_states[scope_key(scope_data)] = normalized
	save()


func _empty_state(scope_data: Dictionary) -> Dictionary:
	return {
		"scope": scope_data.duplicate(true),
		"memory_schema_version": MEMORY_SCHEMA_VERSION,
		"record_schema_version": RECORD_SCHEMA_VERSION,
		"context_schema_version": CONTEXT_SCHEMA_VERSION,
		"read_only": false,
		"persona_snapshot": {},
		"memory_records": [],
		"relationship_state": {},
		"conflict_records": [],
		"vector_index": {},
		"semantic_hnsw_graph": {},
		"recent_entries": [],
		"round_summaries": [],
		"long_term_memory_summary": "",
		"token_budget": TOKEN_BUDGET,
	}


func _normalize_state(state: Dictionary) -> Dictionary:
	var scope_data := _dict_or_empty(state.get("scope", {}))
	var source_version := int(state.get("memory_schema_version", 0))
	if source_version != MEMORY_SCHEMA_VERSION:
		return _empty_state(scope_data)
	return {
		"scope": scope_data,
		"memory_schema_version": MEMORY_SCHEMA_VERSION,
		"record_schema_version": int(state.get("record_schema_version", RECORD_SCHEMA_VERSION)),
		"context_schema_version": int(state.get("context_schema_version", CONTEXT_SCHEMA_VERSION)),
		"read_only": bool(state.get("read_only", false)),
		"persona_snapshot": _dict_or_empty(state.get("persona_snapshot", {})),
		"memory_records": _normalize_memory_records(_array_or_empty(state.get("memory_records", []))),
		"relationship_state": _dict_or_empty(state.get("relationship_state", {})),
		"conflict_records": _array_or_empty(state.get("conflict_records", [])),
		"vector_index": _dict_or_empty(state.get("vector_index", {})),
		"semantic_hnsw_graph": _dict_or_empty(state.get("semantic_hnsw_graph", {})),
		"recent_entries": _array_or_empty(state.get("recent_entries", [])),
		"round_summaries": _array_or_empty(state.get("round_summaries", [])),
		"long_term_memory_summary": String(state.get("long_term_memory_summary", "")),
		"token_budget": int(state.get("token_budget", TOKEN_BUDGET)),
	}


func _normalize_memory_records(records: Array) -> Array:
	var normalized: Array = []
	for item in records:
		if not (item is Dictionary):
			continue
		var record: Dictionary = (item as Dictionary).duplicate(true)
		record["record_schema_version"] = int(record.get("record_schema_version", RECORD_SCHEMA_VERSION))
		record["memory_id"] = String(record.get("memory_id", ""))
		record["memory_type"] = String(record.get("memory_type", "")).strip_edges()
		record["content"] = String(record.get("content", "")).strip_edges()
		record["visibility"] = String(record.get("visibility", "self_private")).strip_edges()
		record["status"] = String(record.get("status", "active")).strip_edges()
		record["structured_payload"] = _dict_or_empty(record.get("structured_payload", {}))
		record["metadata"] = _dict_or_empty(record.get("metadata", {}))
		record["evidence"] = _array_or_empty(record.get("evidence", []))
		record["importance"] = clampf(float(record.get("importance", 0.55)), 0.0, 1.0)
		record["confidence"] = clampf(float(record.get("confidence", 0.70)), 0.0, 1.0)
		normalized.append(record)
	return normalized


func _trim_recent_entries(state: Dictionary) -> void:
	var entries: Array = state.get("recent_entries", [])
	var max_entries := 48
	if entries.size() > max_entries:
		state["recent_entries"] = entries.slice(entries.size() - max_entries)


func _tail_entries(value, limit: int) -> Array:
	var entries := _array_or_empty(value)
	var start: int = maxi(0, entries.size() - max(0, limit))
	var result := []
	for i in range(start, entries.size()):
		if entries[i] is Dictionary:
			result.append((entries[i] as Dictionary).duplicate(true))
		else:
			result.append(entries[i])
	return result


func _retrieval_candidates(state: Dictionary, include_long_term: bool) -> Array:
	var result := []
	var rank := 0
	for item in _array_or_empty(state.get("recent_entries", [])):
		if not (item is Dictionary):
			continue
		var entry: Dictionary = item
		var content := String(entry.get("content", "")).strip_edges()
		if content == "":
			continue
		result.append({
			"content": content,
			"source": "recent",
			"visibility": String(entry.get("visibility", "public")),
			"created_at": float(entry.get("created_at", 0.0)),
			"metadata": _dict_or_empty(entry.get("metadata", {})),
			"_rank": rank,
		})
		rank += 1
	for item in _array_or_empty(state.get("round_summaries", [])):
		if not (item is Dictionary):
			continue
		var summary: Dictionary = item
		var content := _round_summary_text(summary)
		if content == "":
			continue
		result.append({
			"content": content,
			"source": "round_summary",
			"visibility": "private" if String(summary.get("private_summary", "")).strip_edges() != "" else "public",
			"created_at": 0.0,
			"metadata": {
				"day_number": int(summary.get("day_number", 0)),
				"phase": String(summary.get("phase", "")),
			},
			"_rank": rank,
		})
		rank += 1
	if include_long_term:
		var long_term := String(state.get("long_term_memory_summary", "")).strip_edges()
		if long_term != "":
			result.append({
				"content": long_term,
				"source": "long_term",
				"visibility": "private",
				"created_at": 0.0,
				"metadata": {},
				"_rank": rank,
			})
	return result


func _source_counts(candidates: Array) -> Dictionary:
	var counts := {}
	for item in candidates:
		if not (item is Dictionary):
			continue
		var source := String((item as Dictionary).get("source", "unknown"))
		counts[source] = int(counts.get(source, 0)) + 1
	return counts


func _round_summary_text(summary: Dictionary) -> String:
	var parts := []
	for key in ["public_summary", "private_summary", "decision_summary", "suspicion_summary", "strategy_summary"]:
		var value := String(summary.get(key, "")).strip_edges()
		if value != "":
			parts.append(value)
	return "\n".join(parts)


func _retrieval_score(query: String, query_vector: Dictionary, content: String) -> float:
	var content_vector := _text_vector(content)
	if content_vector.is_empty():
		return 0.0
	var dot := 0.0
	for token_value in query_vector.keys():
		var token := String(token_value)
		if content_vector.has(token):
			dot += float(query_vector[token]) * float(content_vector[token])
	if dot <= 0.0:
		return 0.0
	var query_norm := _vector_norm(query_vector)
	var content_norm := _vector_norm(content_vector)
	if query_norm <= 0.0 or content_norm <= 0.0:
		return 0.0
	var score := dot / (sqrt(query_norm) * sqrt(content_norm))
	if content.to_lower().contains(query.to_lower()):
		score += 0.2
	return score


func _text_vector(text: String) -> Dictionary:
	var weights := {}
	var ascii_word := ""
	var cjk_run := []
	var normalized := text.to_lower()
	for i in range(normalized.length()):
		var ch := normalized.substr(i, 1)
		var code := ch.unicode_at(0)
		if _is_ascii_alnum(code):
			ascii_word += ch
			_flush_cjk_run(weights, cjk_run)
			cjk_run = []
			continue
		if ascii_word.length() >= 2:
			_add_token_weight(weights, ascii_word, 1.5)
		ascii_word = ""
		if _is_cjk(code):
			cjk_run.append(ch)
			_add_token_weight(weights, ch, 0.7)
		else:
			_flush_cjk_run(weights, cjk_run)
			cjk_run = []
	if ascii_word.length() >= 2:
		_add_token_weight(weights, ascii_word, 1.5)
	_flush_cjk_run(weights, cjk_run)
	return weights


func _flush_cjk_run(weights: Dictionary, cjk_run: Array) -> void:
	if cjk_run.size() < 2:
		return
	for i in range(cjk_run.size() - 1):
		_add_token_weight(weights, String(cjk_run[i]) + String(cjk_run[i + 1]), 1.4)
	if cjk_run.size() >= 3:
		for i in range(cjk_run.size() - 2):
			_add_token_weight(weights, String(cjk_run[i]) + String(cjk_run[i + 1]) + String(cjk_run[i + 2]), 1.8)


func _add_token_weight(weights: Dictionary, token: String, weight: float) -> void:
	var trimmed := token.strip_edges()
	if trimmed == "":
		return
	weights[trimmed] = float(weights.get(trimmed, 0.0)) + weight


func _vector_norm(vector: Dictionary) -> float:
	var total := 0.0
	for token in vector.keys():
		var weight := float(vector[token])
		total += weight * weight
	return total


func _sort_retrieval_results(a, b) -> bool:
	var left: Dictionary = a if a is Dictionary else {}
	var right: Dictionary = b if b is Dictionary else {}
	var score_left := float(left.get("score", 0.0))
	var score_right := float(right.get("score", 0.0))
	if score_left == score_right:
		return int(left.get("_rank", 0)) < int(right.get("_rank", 0))
	return score_left > score_right


func _is_ascii_alnum(code: int) -> bool:
	return (code >= 48 and code <= 57) or (code >= 97 and code <= 122)


func _is_cjk(code: int) -> bool:
	return (code >= 0x4e00 and code <= 0x9fff) or (code >= 0x3400 and code <= 0x4dbf)


func _dict_or_empty(value) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}


func _array_or_empty(value) -> Array:
	if value is Array:
		return (value as Array).duplicate(true)
	return []


func _visibility(value: String) -> String:
	return "private" if value.strip_edges().to_lower() == "private" else "public"


func _non_empty(value: String, default_value: String) -> String:
	var trimmed := value.strip_edges()
	return trimmed if trimmed != "" else default_value


func _trim_text(value: String, max_chars: int) -> String:
	var normalized := value.strip_edges()
	if normalized.length() <= max_chars:
		return normalized
	return normalized.substr(0, max(0, max_chars - 3)) + "..."
