extends RefCounted
class_name AndroidMemoryStore

const DEFAULT_SINGLETON := "PlayWithMeAndroid"
const AVAILABLE_METHODS := ["memory_available", "memoryAvailable"]
const LOAD_METHODS := ["memory_load_state", "memoryLoadState"]
const SAVE_STATE_METHODS := ["memory_save_state", "memorySaveState"]
const APPEND_METHODS := ["memory_append", "memoryAppend"]
const COMPACT_METHODS := ["memory_compact", "memoryCompact"]
const SAVE_LONG_TERM_METHODS := ["memory_save_long_term", "memorySaveLongTerm"]
const DELETE_SCOPE_METHODS := ["memory_delete_scope", "memoryDeleteScope"]
const DISCARD_SESSION_METHODS := ["memory_discard_session", "memoryDiscardSession"]
const LIST_SCOPES_METHODS := ["memory_list_scopes", "memoryListScopes"]
const DELETE_OWNER_METHODS := ["memory_delete_owner", "memoryDeleteOwner"]
const LIST_INDEX_METHODS := ["memory_list_index_names", "memoryListIndexNames"]
const INDEX_STATUS_METHODS := ["memory_index_status", "memoryIndexStatus"]
const NATIVE_REBUILD_METHODS := ["memory_native_rebuild_indexes", "memoryNativeRebuildIndexes"]
const NATIVE_VECTOR_SEARCH_METHODS := ["memory_native_vector_search", "memoryNativeVectorSearch"]

var singleton_name := DEFAULT_SINGLETON


func is_available() -> bool:
	var plugin = _plugin()
	if plugin == null:
		return false
	var available_method := _method(plugin, AVAILABLE_METHODS)
	if available_method != "":
		var result = plugin.call(available_method)
		if result is bool:
			return bool(result)
	return _method(plugin, LOAD_METHODS) != "" and _method(plugin, APPEND_METHODS) != ""


func load_state(scope_data: Dictionary) -> Dictionary:
	var payload := _call_json(LOAD_METHODS, [JSON.stringify(scope_data)])
	if not bool(payload.get("ok", true)):
		return {"ok": false, "error": String(payload.get("error", "SQLite 记忆读取失败"))}
	return _normalize_state(payload)


func save_state(scope_data: Dictionary, state: Dictionary) -> Dictionary:
	return _call_ok(SAVE_STATE_METHODS, [JSON.stringify(scope_data), JSON.stringify(state)])


func append(scope_data: Dictionary, entry: Dictionary) -> Dictionary:
	return _call_ok(APPEND_METHODS, [JSON.stringify(scope_data), JSON.stringify(entry)])


func compact(scope_data: Dictionary, request: Dictionary) -> Dictionary:
	var payload := _call_json(COMPACT_METHODS, [JSON.stringify(scope_data), JSON.stringify(request)])
	if not bool(payload.get("ok", false)):
		return {"ok": false, "error": String(payload.get("error", "SQLite 记忆压缩失败"))}
	var summary = payload.get("summary", {})
	if summary is Dictionary:
		var normalized := _normalize_summary(summary as Dictionary)
		normalized["ok"] = true
		return normalized
	return {"ok": false, "error": "SQLite 记忆压缩返回格式错误"}


func save_long_term(scope_data: Dictionary, summary: String, user_approved: bool = true) -> Dictionary:
	return _call_ok(SAVE_LONG_TERM_METHODS, [JSON.stringify(scope_data), summary, user_approved])


func delete_scope(scope_data: Dictionary) -> Dictionary:
	return _call_ok(DELETE_SCOPE_METHODS, [JSON.stringify(scope_data)])


func discard_session(scope_data: Dictionary) -> Dictionary:
	if String(scope_data.get("room_id", "")).strip_edges() == "":
		return {"ok": true}
	return _call_ok(DISCARD_SESSION_METHODS, [JSON.stringify(scope_data)])


func list_scopes(owner_id: String = "", game_id: String = "", memory_namespace: String = "") -> Array:
	var plugin = _plugin()
	if plugin == null:
		return []
	var method := _method(plugin, LIST_SCOPES_METHODS)
	if method == "":
		return []
	var parsed = _parse_json(plugin.call(method, owner_id, game_id, memory_namespace))
	var source: Array = []
	if parsed is Array:
		source = parsed
	elif parsed is Dictionary:
		var data: Dictionary = parsed
		if not bool(data.get("ok", true)):
			return []
		source = _array_or_empty(data.get("scopes", []))
	var scopes: Array = []
	for item in source:
		if item is Dictionary:
			scopes.append(_normalize_scope(item as Dictionary))
	return scopes


func delete_owner_memory(owner_id: String, game_id: String = "") -> Dictionary:
	return _call_ok(DELETE_OWNER_METHODS, [owner_id, game_id])


func list_index_names() -> Array:
	var plugin = _plugin()
	if plugin == null:
		return []
	var method := _method(plugin, LIST_INDEX_METHODS)
	if method == "":
		return []
	var parsed = _parse_json(plugin.call(method))
	var source: Array = parsed if parsed is Array else []
	var names: Array = []
	for item in source:
		names.append(String(item))
	return names


func index_status() -> Dictionary:
	var plugin = _plugin()
	if plugin == null:
		return {}
	var method := _method(plugin, INDEX_STATUS_METHODS)
	if method == "":
		return {}
	var parsed = _parse_json(plugin.call(method))
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}


func native_rebuild_indexes(scope_data: Dictionary, state: Dictionary) -> Dictionary:
	return _call_json(NATIVE_REBUILD_METHODS, [JSON.stringify(scope_data), JSON.stringify(state)])


func native_vector_search(scope_data: Dictionary, query_embedding: Array, request: Dictionary) -> Dictionary:
	return _call_json(NATIVE_VECTOR_SEARCH_METHODS, [JSON.stringify(scope_data), JSON.stringify(query_embedding), JSON.stringify(request)])


func _call_ok(methods: Array, args: Array) -> Dictionary:
	var payload := _call_json(methods, args)
	if not bool(payload.get("ok", false)):
		return {"ok": false, "error": String(payload.get("error", "SQLite 记忆数据库操作失败"))}
	return {"ok": true}


func _call_json(methods: Array, args: Array) -> Dictionary:
	var plugin = _plugin()
	if plugin == null:
		return {"ok": false, "error": "Android 记忆插件未接入：缺少 singleton %s" % singleton_name}
	var method := _method(plugin, methods)
	if method == "":
		return {"ok": false, "error": "Android 记忆插件缺少方法"}
	var parsed = _parse_json(plugin.callv(method, args))
	if parsed is Dictionary:
		return parsed as Dictionary
	return {"ok": false, "error": "Android 记忆插件返回格式错误"}


func _plugin():
	if Engine.has_singleton(singleton_name):
		return Engine.get_singleton(singleton_name)
	return null


func _method(plugin, methods: Array) -> String:
	for method in methods:
		if plugin.has_method(method):
			return method
	if OS.get_name() == "Android" and not methods.is_empty():
		return String(methods[0])
	return ""


func _parse_json(payload):
	if payload is Dictionary or payload is Array:
		return payload
	if payload is String:
		var raw := String(payload).strip_edges()
		if raw == "":
			return {}
		var json := JSON.new()
		if json.parse(raw) != OK:
			return {}
		return json.data
	return {}


func _normalize_state(state: Dictionary) -> Dictionary:
	return {
		"scope": _normalize_scope(_dict_or_empty(state.get("scope", {}))),
		"memory_schema_version": int(state.get("memory_schema_version", state.get("schema_version", 1))),
		"record_schema_version": int(state.get("record_schema_version", 1)),
		"context_schema_version": int(state.get("context_schema_version", 1)),
		"read_only": bool(state.get("read_only", false)),
		"persona_snapshot": _dict_or_empty(state.get("persona_snapshot", {})),
		"memory_records": _normalize_memory_records(_array_or_empty(state.get("memory_records", []))),
		"relationship_state": _dict_or_empty(state.get("relationship_state", {})),
		"conflict_records": _array_or_empty(state.get("conflict_records", [])),
		"vector_index": _dict_or_empty(state.get("vector_index", {})),
		"semantic_hnsw_graph": _dict_or_empty(state.get("semantic_hnsw_graph", {})),
		"recent_entries": _normalize_entries(_array_or_empty(state.get("recent_entries", []))),
		"round_summaries": _normalize_summaries(_array_or_empty(state.get("round_summaries", []))),
		"long_term_memory_summary": String(state.get("long_term_memory_summary", "")),
		"token_budget": int(state.get("token_budget", 4000)),
	}


func _normalize_scope(scope_data: Dictionary) -> Dictionary:
	return {
		"owner_id": String(scope_data.get("owner_id", "")).strip_edges(),
		"game_id": String(scope_data.get("game_id", "")).strip_edges(),
		"namespace": String(scope_data.get("namespace", "")).strip_edges(),
		"map_id": String(scope_data.get("map_id", "")).strip_edges(),
		"room_id": String(scope_data.get("room_id", "")).strip_edges(),
	}


func _normalize_entries(entries: Array) -> Array:
	var normalized: Array = []
	for item in entries:
		if not (item is Dictionary):
			continue
		var entry: Dictionary = item
		normalized.append({
			"content": String(entry.get("content", "")),
			"visibility": "private" if String(entry.get("visibility", "public")) == "private" else "public",
			"created_at": float(entry.get("created_at", 0.0)),
			"metadata": _dict_or_empty(entry.get("metadata", {})),
		})
	return normalized


func _normalize_memory_records(records: Array) -> Array:
	var normalized: Array = []
	for item in records:
		if not (item is Dictionary):
			continue
		var record: Dictionary = item
		var content := String(record.get("content", "")).strip_edges()
		var memory_type := String(record.get("memory_type", "")).strip_edges()
		if content == "" or memory_type == "":
			continue
		var stored := record.duplicate(true)
		stored["content"] = content
		stored["memory_type"] = memory_type
		stored["memory_id"] = String(stored.get("memory_id", ""))
		stored["bot_id"] = String(stored.get("bot_id", ""))
		stored["visibility"] = _normalize_visibility(String(stored.get("visibility", "self_private")))
		stored["status"] = String(stored.get("status", "active"))
		stored["importance"] = clampf(float(stored.get("importance", 0.55)), 0.0, 1.0)
		stored["confidence"] = clampf(float(stored.get("confidence", 0.70)), 0.0, 1.0)
		stored["scope"] = _normalize_scope(_dict_or_empty(stored.get("scope", {})))
		stored["structured_payload"] = _dict_or_empty(stored.get("structured_payload", {}))
		stored["evidence"] = _array_or_empty(stored.get("evidence", []))
		stored["metadata"] = _dict_or_empty(stored.get("metadata", {}))
		normalized.append(stored)
	return normalized


func _normalize_summaries(summaries: Array) -> Array:
	var normalized: Array = []
	for item in summaries:
		if item is Dictionary:
			normalized.append(_normalize_summary(item as Dictionary))
	return normalized


func _normalize_summary(summary: Dictionary) -> Dictionary:
	return {
		"day_number": int(summary.get("day_number", 0)),
		"phase": String(summary.get("phase", "")),
		"public_summary": String(summary.get("public_summary", "")),
		"private_summary": String(summary.get("private_summary", "")),
		"decision_summary": String(summary.get("decision_summary", "")),
		"suspicion_summary": String(summary.get("suspicion_summary", "")),
		"strategy_summary": String(summary.get("strategy_summary", "")),
	}


func _normalize_visibility(value: String) -> String:
	var normalized := value.strip_edges().to_lower()
	match normalized:
		"public", "private", "self_private", "observer_safe", "post_session_reveal":
			return normalized
		_:
			return "self_private"


func _dict_or_empty(value) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}


func _array_or_empty(value) -> Array:
	if value is Array:
		return (value as Array).duplicate(true)
	return []
