extends RefCounted
class_name MemoryQueryRouter

const DEFAULT_MEMORY_BUDGET := 2048


func build_plan(request: Dictionary) -> Dictionary:
	var query := String(request.get("query", "")).strip_edges()
	var scope_data := _dict_or_empty(request.get("scope", {}))
	var limit := maxi(0, int(request.get("limit", 0)))
	var include_long_term := bool(request.get("include_long_term", true))
	var options := _dict_or_empty(request.get("memory_options", {}))
	var include_types := _string_array(request.get("include_types", options.get("include_types", [
		"working",
		"relationship",
		"semantic",
		"episodic",
		"reflection",
	])))
	var visible_entity_ids := _string_array(request.get("visible_entity_ids", []))
	var target_entity_ids := _string_array(request.get("target_entity_ids", []))
	var memory_namespace := String(scope_data.get("namespace", "")).strip_edges()
	var intent := _intent_for_request(request, memory_namespace)
	var index_status := _dict_or_empty(request.get("index_status", {}))
	var vector_enabled := bool(index_status.get("vector_enabled", false))
	var retrieval_mode := "hybrid_vector" if vector_enabled else "text_retrieval"
	var required_sources: Array = ["profile_snapshot", "working_memory"]
	if include_types.has("relationship") and (not target_entity_ids.is_empty() or not visible_entity_ids.is_empty()):
		required_sources.append("relationship_memory")
	var optional_sources: Array = []
	if include_types.has("semantic") and include_long_term:
		optional_sources.append("semantic_memory")
	if include_types.has("episodic"):
		optional_sources.append("episodic_memory")
	if include_types.has("reflection"):
		optional_sources.append("reflection_memory")
	optional_sources.append("text_retrieval")
	var warnings: Array = []
	for item in _array_or_empty(index_status.get("warnings", [])):
		warnings.append(item)
	var status_filter: Array = ["active"]
	if intent == "maintenance" or intent == "debug_preview":
		status_filter.append("candidate")
	var queries := _queries_for_request(query, request)
	return {
		"intent": intent,
		"retrieval_mode": retrieval_mode,
		"hybrid_retrieval": vector_enabled,
		"vector_enabled": vector_enabled,
		"embedding_enabled": bool(index_status.get("embedding_enabled", vector_enabled)),
		"vector_sources": {
			"sqlite_vec_event": bool(index_status.get("sqlite_vec_event_enabled", false)),
			"hnsw_semantic": bool(index_status.get("hnsw_semantic_enabled", false)),
			"native_sqlite_vec": bool(index_status.get("native_sqlite_vec_enabled", false)),
			"native_hnswlib": bool(index_status.get("native_hnswlib_enabled", false)),
		},
		"index_status": index_status.duplicate(true),
		"required_sources": required_sources,
		"optional_sources": optional_sources,
		"queries": queries,
		"filters": {
			"bot_id": String(request.get("bot_id", scope_data.get("owner_id", ""))),
			"game_id": String(scope_data.get("game_id", "")),
			"namespace": memory_namespace,
			"map_id": String(scope_data.get("map_id", "")),
			"room_id": String(scope_data.get("room_id", "")),
			"visibility": ["public", "private", "self_private", "observer_safe", "post_session_reveal"],
			"status": status_filter,
			"include_types": include_types,
			"visible_entity_ids": visible_entity_ids,
			"target_entity_ids": target_entity_ids,
		},
		"budget_plan": {
			"max_token_budget": int(options.get("max_token_budget", request.get("max_token_budget", DEFAULT_MEMORY_BUDGET))),
			"hard_token_limit": int(options.get("hard_token_limit", request.get("hard_token_limit", 4096))),
			"final_max_items": limit,
			"include_long_term": include_long_term,
			"layer_limits": _dict_or_empty(options.get("layer_limits", {
				"profile": 1,
				"working": 6,
				"relationship": 6,
				"semantic": 6,
				"episodic": 6,
				"reflection": 4,
			})),
		},
		"text_retrieval_plan": {
			"text_retrieval": true,
			"reason": "hybrid_text_support" if vector_enabled else "vector_index_not_available",
		},
		"debug_flags": {
			"include_query_plan": true,
			"include_candidate_pool": true,
			"include_rerank": true,
			"include_fusion": true,
		},
		"warnings": warnings,
	}


func _intent_for_request(request: Dictionary, memory_namespace: String) -> String:
	var task_type := String(request.get("task_type", "")).strip_edges()
	if task_type != "":
		return task_type
	if memory_namespace == "profile":
		return "profile_retrieval"
	return "text_retrieval"


func _queries_for_request(query: String, request: Dictionary) -> Array:
	var queries: Array = []
	if query != "":
		queries.append({"type": "task_query", "text": query})
	var visible_query := _query_from_visible_facts(request.get("visible_context_facts", []))
	if visible_query != "" and visible_query != query:
		queries.append({"type": "visible_context_query", "text": visible_query})
	var hints := _array_or_empty(request.get("retrieval_hints", []))
	for item in hints:
		if item is Dictionary:
			var text := String((item as Dictionary).get("text", (item as Dictionary).get("content", ""))).strip_edges()
			if text != "":
				queries.append({
					"type": String((item as Dictionary).get("type", "hint_query")),
					"text": text,
				})
		else:
			var raw := String(item).strip_edges()
			if raw != "":
				queries.append({"type": "hint_query", "text": raw})
	if queries.is_empty():
		queries.append({"type": "task_query", "text": "memory_context"})
	return queries


func _query_from_visible_facts(value) -> String:
	var facts := _array_or_empty(value)
	var parts: Array = []
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


func _string_array(value) -> Array:
	var result: Array = []
	for item in _array_or_empty(value):
		var text := String(item).strip_edges()
		if text != "":
			result.append(text)
	return result


func _dict_or_empty(value) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}


func _array_or_empty(value) -> Array:
	if value is Array:
		return (value as Array).duplicate(true)
	return []
