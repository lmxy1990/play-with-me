extends RefCounted
class_name MemoryFormation

const NORMAL_LIMITS := {
	"working": 4,
	"episodic": 4,
	"relationship": 4,
	"semantic": 2,
	"reflection": 2,
}
const SESSION_END_LIMITS := {
	"working": 8,
	"episodic": 16,
	"relationship": 12,
	"semantic": 5,
	"reflection": 5,
}


func extract_update_candidates(request: Dictionary, scope_key: String) -> Dictionary:
	var scope_data := _dict_or_empty(request.get("scope", {}))
	var memory_update := _dict_or_empty(request.get("memory_update", {}))
	var update_reason := String(request.get("update_reason", memory_update.get("source", ""))).strip_edges()
	if update_reason == "":
		update_reason = "manual"
	var default_visibility := _visibility(String(memory_update.get("visibility", request.get("visibility", "self_private"))))
	var now := Time.get_unix_time_from_system()
	var limits := SESSION_END_LIMITS if update_reason == "session_end" else NORMAL_LIMITS
	var evidence := _normalize_evidence(_array_or_empty(memory_update.get("evidence", request.get("evidence", []))))
	var records: Array = []
	var skipped: Array = []
	var rejected: Array = []
	var layer_counts := {
		"working": 0,
		"episodic": 0,
		"relationship": 0,
		"semantic": 0,
		"reflection": 0,
	}
	var update_rejection := _pollution_rejection(memory_update, request)
	if not update_rejection.is_empty():
		rejected.append(update_rejection)
	else:
		_collect_working(records, skipped, rejected, layer_counts, memory_update.get("working_update", {}), request, scope_data, scope_key, evidence, default_visibility, update_reason, now, int(limits["working"]))
		_collect_records(records, skipped, rejected, layer_counts, _array_or_empty(memory_update.get("episodic_events", request.get("events", []))), "episodic", request, scope_data, scope_key, evidence, default_visibility, update_reason, now, int(limits["episodic"]))
		_collect_records(records, skipped, rejected, layer_counts, _array_or_empty(memory_update.get("relationship_updates", [])), "relationship", request, scope_data, scope_key, evidence, default_visibility, update_reason, now, int(limits["relationship"]))
		_collect_records(records, skipped, rejected, layer_counts, _array_or_empty(memory_update.get("semantic_candidates", [])), "semantic", request, scope_data, scope_key, evidence, default_visibility, update_reason, now, int(limits["semantic"]))
		_collect_records(records, skipped, rejected, layer_counts, _array_or_empty(memory_update.get("reflection_candidates", [])), "reflection", request, scope_data, scope_key, evidence, default_visibility, update_reason, now, int(limits["reflection"]))
	var warnings: Array = []
	if not rejected.is_empty():
		warnings.append("memory_update_rejected_items")
	var report := {
		"bot_id": String(request.get("bot_id", scope_data.get("owner_id", ""))),
		"scope": scope_data.duplicate(true),
		"scope_key": scope_key,
		"update_reason": update_reason,
		"updated_layers": _updated_layers(layer_counts),
		"written": _record_reports(records),
		"skipped": skipped,
		"merged": [],
		"downgraded": [],
		"rejected": rejected,
		"embedding_jobs": _embedding_jobs(records),
		"layer_counts": layer_counts,
		"warnings": warnings,
		"created_at": now,
	}
	return {
		"records": records,
		"report": report,
	}


func _collect_working(records: Array, skipped: Array, rejected: Array, layer_counts: Dictionary, value, request: Dictionary, scope_data: Dictionary, scope_key: String, evidence: Array, default_visibility: String, update_reason: String, now: float, limit: int) -> void:
	var items: Array = []
	if value is Dictionary:
		for key in (value as Dictionary).keys():
			items.append({
				"subject_id": String(key),
				"subject_type": "working_key",
				"content": _working_content(String(key), (value as Dictionary)[key]),
				"structured_payload": {"key": String(key), "value": (value as Dictionary)[key]},
			})
	elif value is Array:
		items = _array_or_empty(value)
	elif String(value).strip_edges() != "":
		items.append({"content": String(value).strip_edges()})
	_collect_records(records, skipped, rejected, layer_counts, items, "working", request, scope_data, scope_key, evidence, default_visibility, update_reason, now, limit)


func _collect_records(records: Array, skipped: Array, rejected: Array, layer_counts: Dictionary, items: Array, memory_type: String, request: Dictionary, scope_data: Dictionary, scope_key: String, evidence: Array, default_visibility: String, update_reason: String, now: float, limit: int) -> void:
	var count := 0
	for raw_item in items:
		if count >= limit:
			skipped.append({"memory_type": memory_type, "reason": "layer_limit", "limit": limit})
			break
		var item := _dict_from_item(raw_item)
		var content := _content_for_item(item, raw_item, memory_type)
		if content == "":
			skipped.append({"memory_type": memory_type, "reason": "empty_content"})
			continue
		var pollution := _pollution_rejection(item, request)
		if not pollution.is_empty():
			pollution["memory_type"] = memory_type
			pollution["content_preview"] = _preview(content)
			rejected.append(pollution)
			continue
		var raw_visibility := String(item.get("visibility", default_visibility))
		if _visibility_rejected(raw_visibility):
			rejected.append({"memory_type": memory_type, "reason": "not_visible_to_bot", "content_preview": _preview(content)})
			continue
		var visibility := _visibility(raw_visibility)
		if not _visibility_allowed(visibility):
			rejected.append({"memory_type": memory_type, "reason": "privacy_risk", "content_preview": _preview(content)})
			continue
		var status := _status_for_item(item, memory_type)
		var record := {
			"memory_id": String(item.get("memory_id", _new_memory_id(memory_type, content, count))),
			"bot_id": String(request.get("bot_id", scope_data.get("owner_id", ""))),
			"memory_type": memory_type,
			"scope_key": scope_key,
			"scope": scope_data.duplicate(true),
			"domain_id": String(scope_data.get("game_id", "")),
			"session_id": String(scope_data.get("room_id", "")),
			"instance_id": String(scope_data.get("map_id", "")),
			"subject_id": String(item.get("subject_id", item.get("target_id", ""))),
			"subject_type": String(item.get("subject_type", item.get("target_type", ""))),
			"content": content,
			"structured_payload": _dict_or_empty(item.get("structured_payload", item)),
			"visibility": visibility,
			"source": String(item.get("source", update_reason)),
			"importance": clampf(float(item.get("importance", _default_importance(memory_type))), 0.0, 1.0),
			"confidence": clampf(float(item.get("confidence", _default_confidence(memory_type))), 0.0, 1.0),
			"status": status,
			"created_at": float(item.get("created_at", now)),
			"updated_at": now,
			"last_accessed_at": 0.0,
			"expires_at": float(item.get("expires_at", 0.0)),
			"evidence": _normalize_evidence(_array_or_empty(item.get("evidence", evidence))),
			"metadata": _dict_or_empty(item.get("metadata", {})),
			"embedding_status": _embedding_status(memory_type),
		}
		records.append(record)
		layer_counts[memory_type] = int(layer_counts.get(memory_type, 0)) + 1
		count += 1


func _dict_from_item(item) -> Dictionary:
	if item is Dictionary:
		return (item as Dictionary).duplicate(true)
	return {}


func _content_for_item(item: Dictionary, raw_item, memory_type: String) -> String:
	var content := String(item.get("content", "")).strip_edges()
	if content != "":
		return content
	if memory_type == "relationship":
		var target := String(item.get("target_id", item.get("subject_id", ""))).strip_edges()
		var delta := String(item.get("delta", "")).strip_edges()
		var reason := String(item.get("reason", "")).strip_edges()
		var parts: Array = []
		if target != "":
			parts.append("target=%s" % target)
		if delta != "":
			parts.append("delta=%s" % delta)
		if reason != "":
			parts.append(reason)
		return "; ".join(parts)
	if raw_item is String:
		return String(raw_item).strip_edges()
	return ""


func _working_content(key: String, value) -> String:
	if value is Dictionary:
		var content := String((value as Dictionary).get("content", "")).strip_edges()
		if content != "":
			return content
	return "%s: %s" % [key, String(value).strip_edges()]


func _status_for_item(item: Dictionary, memory_type: String) -> String:
	var explicit := String(item.get("status", "")).strip_edges()
	if explicit != "":
		return explicit
	if memory_type == "semantic" or memory_type == "reflection":
		return "candidate"
	return "active"


func _embedding_status(memory_type: String) -> String:
	if memory_type == "episodic" or memory_type == "semantic":
		return "pending"
	return "not_required"


func _default_importance(memory_type: String) -> float:
	match memory_type:
		"working":
			return 0.70
		"relationship":
			return 0.68
		"semantic":
			return 0.66
		"reflection":
			return 0.62
		_:
			return 0.55


func _default_confidence(memory_type: String) -> float:
	match memory_type:
		"semantic":
			return 0.62
		"reflection":
			return 0.64
		_:
			return 0.72


func _new_memory_id(memory_type: String, content: String, index: int) -> String:
	return "%s_%d_%d_%d" % [
		memory_type,
		int(Time.get_unix_time_from_system() * 1000.0),
		index,
		absi(content.hash()),
	]


func _normalize_evidence(values: Array) -> Array:
	var result: Array = []
	for item in values:
		if item is Dictionary:
			var entry := (item as Dictionary).duplicate(true)
			if String(entry.get("content", entry.get("id", ""))).strip_edges() != "":
				result.append(entry)
		else:
			var text := String(item).strip_edges()
			if text != "":
				result.append({"content": text})
	return result


func _embedding_jobs(records: Array) -> Array:
	var jobs: Array = []
	for item in records:
		if not (item is Dictionary):
			continue
		var record: Dictionary = item
		var memory_type := String(record.get("memory_type", ""))
		if memory_type == "episodic" or memory_type == "semantic":
			jobs.append({
				"memory_id": String(record.get("memory_id", "")),
				"memory_type": memory_type,
				"status": "pending",
			})
	return jobs


func _record_reports(records: Array) -> Array:
	var result: Array = []
	for item in records:
		if not (item is Dictionary):
			continue
		var record: Dictionary = item
		result.append({
			"memory_id": String(record.get("memory_id", "")),
			"memory_type": String(record.get("memory_type", "")),
			"subject_id": String(record.get("subject_id", "")),
			"status": String(record.get("status", "")),
			"embedding_status": String(record.get("embedding_status", "")),
		})
	return result


func _updated_layers(layer_counts: Dictionary) -> Array:
	var layers: Array = []
	for key in ["working", "relationship", "episodic", "semantic", "reflection"]:
		if int(layer_counts.get(key, 0)) > 0:
			layers.append(key)
	return layers


func _pollution_rejection(item: Dictionary, request: Dictionary) -> Dictionary:
	if item.is_empty():
		return {}
	if item.has("confirmed") and not bool(item.get("confirmed", true)):
		return {"reason": "unconfirmed_output"}
	if item.has("accepted") and not bool(item.get("accepted", true)):
		return {"reason": "unconfirmed_output"}
	if bool(item.get("rejected", false)):
		return {"reason": "rejected_output"}
	if bool(item.get("model_draft", item.get("is_model_draft", false))):
		return {"reason": "model_draft"}
	if bool(item.get("ui_temp", item.get("temporary", false))):
		return {"reason": "ui_temp"}
	var status := String(item.get("status", item.get("state", ""))).strip_edges().to_lower()
	if status in ["draft", "model_draft", "unconfirmed", "rejected", "ui_temp", "temporary"]:
		return {"reason": status}
	var source := String(item.get("source", item.get("source_type", ""))).strip_edges().to_lower()
	if source in ["model_draft", "unconfirmed_output", "rejected_output", "ui_temp", "temporary_input"]:
		return {"reason": source}
	var bot_id := String(request.get("bot_id", _dict_or_empty(request.get("scope", {})).get("owner_id", ""))).strip_edges()
	if bot_id != "" and item.has("visible_to") and not _visible_to_allows(item.get("visible_to"), bot_id):
		return {"reason": "not_visible_to_bot"}
	if bot_id != "" and item.has("owner_id"):
		var owner_id := String(item.get("owner_id", "")).strip_edges()
		if owner_id != "" and owner_id != bot_id:
			return {"reason": "not_visible_to_bot"}
	if _contains_pollution_marker(item):
		return {"reason": "privacy_risk"}
	return {}


func _visible_to_allows(value, bot_id: String) -> bool:
	if value is Array:
		for item in value:
			var target := String(item).strip_edges()
			if target == bot_id or target == "public" or target == "*":
				return true
		return false
	var target := String(value).strip_edges()
	return target == "" or target == bot_id or target == "public" or target == "*"


func _contains_pollution_marker(value) -> bool:
	if value is Dictionary:
		for key_value in (value as Dictionary).keys():
			var key := String(key_value).strip_edges().to_lower()
			if key in ["hidden_payload", "private_payload", "raw_private_payload", "unredacted_private", "hidden_facts"]:
				return true
			if _contains_pollution_marker((value as Dictionary)[key_value]):
				return true
	elif value is Array:
		for item in value:
			if _contains_pollution_marker(item):
				return true
	return false


func _visibility_rejected(value: String) -> bool:
	var normalized := value.strip_edges().to_lower()
	return normalized in ["hidden", "secret", "not_visible", "raw_private", "unredacted_private"]


func _visibility(value: String) -> String:
	var normalized := value.strip_edges().to_lower()
	match normalized:
		"public", "self_private", "private", "observer_safe", "post_session_reveal":
			return normalized
		_:
			return "self_private"


func _visibility_allowed(value: String) -> bool:
	return value in ["public", "self_private", "private", "observer_safe", "post_session_reveal"]


func _preview(content: String) -> String:
	if content.length() <= 40:
		return content
	return content.substr(0, 37) + "..."


func _dict_or_empty(value) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}


func _array_or_empty(value) -> Array:
	if value is Array:
		return (value as Array).duplicate(true)
	return []
