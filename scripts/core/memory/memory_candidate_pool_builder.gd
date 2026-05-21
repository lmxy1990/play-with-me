extends RefCounted
class_name MemoryCandidatePoolBuilder


func build_pool(raw_candidates: Array, query_plan: Dictionary) -> Dictionary:
	var filters: Dictionary = _dict_or_empty(query_plan.get("filters", {}))
	var allowed_status := _array_to_lookup(_array_or_empty(filters.get("status", ["active"])))
	var allowed_visibility := _array_to_lookup(_array_or_empty(filters.get("visibility", ["public", "private", "self_private"])))
	var include_types := _array_to_lookup(_array_or_empty(filters.get("include_types", [])))
	var result: Array = []
	var seen_keys := {}
	var dropped: Array = []
	var duplicate_count := 0
	for i in range(raw_candidates.size()):
		if not (raw_candidates[i] is Dictionary):
			continue
		var raw: Dictionary = raw_candidates[i]
		var content := String(raw.get("content", "")).strip_edges()
		if content == "":
			dropped.append(_drop_report(raw, "empty_content"))
			continue
		var status := String(raw.get("status", "active")).strip_edges()
		if status == "":
			status = "active"
		if not allowed_status.has(status):
			dropped.append(_drop_report(raw, "status_filtered"))
			continue
		var visibility := String(raw.get("visibility", "self_private")).strip_edges()
		if visibility == "":
			visibility = "self_private"
		if not allowed_visibility.has(visibility):
			dropped.append(_drop_report(raw, "visibility_filtered"))
			continue
		var source := String(raw.get("source", "unknown")).strip_edges()
		var memory_type := String(raw.get("memory_type", "")).strip_edges()
		if memory_type == "":
			memory_type = _memory_type_for_source(source)
		if not include_types.is_empty() and memory_type != "profile" and not include_types.has(memory_type):
			dropped.append(_drop_report(raw, "type_filtered"))
			continue
		if not _scope_allowed(raw, filters):
			dropped.append(_drop_report(raw, "scope_filtered"))
			continue
		var dedupe_key := _dedupe_key(raw, content)
		if seen_keys.has(dedupe_key):
			duplicate_count += 1
			dropped.append(_drop_report(raw, "duplicate_content"))
			continue
		seen_keys[dedupe_key] = true
		var candidate := raw.duplicate(true)
		candidate["candidate_id"] = "%s:%d" % [source, int(raw.get("_rank", i))]
		candidate["memory_id"] = String(raw.get("memory_id", candidate["candidate_id"]))
		candidate["memory_type"] = memory_type
		candidate["retrieval_source"] = String(raw.get("retrieval_source", "text_retrieval"))
		candidate["status"] = status
		candidate["visibility"] = visibility
		candidate["content"] = content
		candidate["evidence"] = _array_or_empty(raw.get("evidence", []))
		candidate["raw_scores"] = _dict_or_empty(raw.get("raw_scores", {}))
		candidate["scope"] = _dict_or_empty(raw.get("scope", {}))
		result.append(candidate)
	return {
		"candidates": result,
		"report": {
			"input_count": raw_candidates.size(),
			"kept_count": result.size(),
			"dropped_count": dropped.size(),
			"duplicate_count": duplicate_count,
			"dropped": dropped,
			"hard_filters": {
				"status": allowed_status.keys(),
				"visibility": allowed_visibility.keys(),
				"include_types": include_types.keys(),
				"visibility_checked": true,
				"scope_checked": true,
				"bot_checked": true,
			},
		},
	}


func _memory_type_for_source(source: String) -> String:
	match source:
		"recent":
			return "episodic"
		"round_summary":
			return "reflection"
		"long_term":
			return "semantic"
		"profile":
			return "profile"
		"working":
			return "working"
		"relationship":
			return "relationship"
		_:
			return "episodic"


func _drop_report(raw: Dictionary, reason: String) -> Dictionary:
	return {
		"source": String(raw.get("source", "unknown")),
		"memory_id": String(raw.get("memory_id", "")),
		"memory_type": String(raw.get("memory_type", "")),
		"visibility": String(raw.get("visibility", "")),
		"status": String(raw.get("status", "")),
		"rank": int(raw.get("_rank", -1)),
		"drop_reason": reason,
	}


func _scope_allowed(raw: Dictionary, filters: Dictionary) -> bool:
	var filter_bot := String(filters.get("bot_id", "")).strip_edges()
	var candidate_bot := String(raw.get("bot_id", "")).strip_edges()
	if filter_bot != "" and candidate_bot != "" and candidate_bot != filter_bot:
		return false
	var scope_data := _dict_or_empty(raw.get("scope", {}))
	if scope_data.is_empty():
		return true
	for key in ["game_id", "namespace", "map_id", "room_id"]:
		var expected := String(filters.get(key, "")).strip_edges()
		var actual := String(scope_data.get(key, "")).strip_edges()
		if expected != "" and actual != "" and actual != expected:
			return false
	return true


func _dedupe_key(raw: Dictionary, content: String) -> String:
	var memory_id := String(raw.get("memory_id", "")).strip_edges()
	if memory_id != "":
		return "id:%s" % memory_id
	return "content:%s" % content


func _array_to_lookup(values: Array) -> Dictionary:
	var result := {}
	for item in values:
		result[String(item)] = true
	return result


func _dict_or_empty(value) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}


func _array_or_empty(value) -> Array:
	if value is Array:
		return (value as Array).duplicate(true)
	return []
