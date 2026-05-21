extends RefCounted
class_name MemoryMaintenanceEngine

const MemoryVectorIndexScript := preload("res://scripts/core/memory/memory_vector_index.gd")

const DEFAULT_MERGE_THRESHOLD := 0.92
const DEFAULT_FORGETTING_THRESHOLD := 0.18
const DISTILL_IMPORTANCE_THRESHOLD := 0.70

var _vector_index = MemoryVectorIndexScript.new()


func maintain_state(state: Dictionary, request: Dictionary) -> Dictionary:
	var maintenance_type := String(request.get("maintenance_type", "manual")).strip_edges()
	if maintenance_type == "":
		maintenance_type = "manual"
	var options := _dict_or_empty(request.get("options", {}))
	var now := Time.get_unix_time_from_system()
	var working_state := state.duplicate(true)
	var distill_report := _distill_semantic_memories(working_state, request, now) if bool(options.get("enable_distillation", maintenance_type == "session_end" or maintenance_type == "manual")) else {"created": []}
	var relationship_report := _evolve_relationship_state(working_state, request, now) if bool(options.get("enable_relationship_evolution", true)) else {"updated": []}
	var conflict_report := _detect_conflicts(working_state, request, now) if bool(options.get("enable_conflict_detection", true)) else {"conflicts": []}
	var merge_report := _merge_similar_memories(working_state, request) if bool(options.get("enable_merge", true)) else {"merged": []}
	var forgetting_report := _apply_forgetting(working_state, request, now) if bool(options.get("enable_forgetting", true)) else {"archived": [], "deleted": []}
	var index_result: Dictionary = _vector_index.refresh_state_indexes(working_state, {
		"force_rebuild": bool(options.get("force_rebuild_indexes", String(request.get("operation", "")) == "rebuild_indexes")),
	})
	working_state = _dict_or_empty(index_result.get("state", working_state))
	var index_report := _dict_or_empty(index_result.get("report", {}))
	var report := {
		"maintenance_type": maintenance_type,
		"operation": String(request.get("operation", "run_light_maintenance")),
		"distilled_memories": _array_or_empty(distill_report.get("created", [])),
		"relationship_updates": _array_or_empty(relationship_report.get("updated", [])),
		"conflict_records": _array_or_empty(conflict_report.get("conflicts", [])),
		"merged_memories": _array_or_empty(merge_report.get("merged", [])),
		"archived_memories": _array_or_empty(forgetting_report.get("archived", [])),
		"deleted_memories": _array_or_empty(forgetting_report.get("deleted", [])),
		"distilled_count": _array_or_empty(distill_report.get("created", [])).size(),
		"relationship_update_count": _array_or_empty(relationship_report.get("updated", [])).size(),
		"conflict_count": _array_or_empty(conflict_report.get("conflicts", [])).size(),
		"merged_count": _array_or_empty(merge_report.get("merged", [])).size(),
		"archived_count": _array_or_empty(forgetting_report.get("archived", [])).size(),
		"deleted_count": _array_or_empty(forgetting_report.get("deleted", [])).size(),
		"index_report": index_report,
		"warnings": [],
		"created_at": now,
	}
	return {
		"state": working_state,
		"report": report,
	}


func _distill_semantic_memories(state: Dictionary, request: Dictionary, now: float) -> Dictionary:
	var records := _array_or_empty(state.get("memory_records", []))
	var created: Array = []
	var max_new := maxi(0, int(_dict_or_empty(request.get("options", {})).get("max_distilled_memories", 4)))
	if max_new <= 0:
		return {"created": created}
	var existing_lookup := {}
	for item in records:
		if not (item is Dictionary):
			continue
		var record: Dictionary = item
		if String(record.get("memory_type", "")) == "semantic":
			existing_lookup[_semantic_key(String(record.get("content", "")))] = true
	var created_count := 0
	for item in records:
		if created_count >= max_new:
			break
		if not (item is Dictionary):
			continue
		var episodic: Dictionary = item
		if String(episodic.get("memory_type", "")) != "episodic":
			continue
		if String(episodic.get("status", "active")) != "active":
			continue
		if float(episodic.get("importance", 0.0)) < DISTILL_IMPORTANCE_THRESHOLD:
			continue
		var content := String(episodic.get("content", "")).strip_edges()
		if content == "":
			continue
		var distilled_content := _distilled_content(content)
		var key := _semantic_key(distilled_content)
		if existing_lookup.has(key):
			continue
		existing_lookup[key] = true
		var semantic_record := {
			"memory_id": "semantic_distilled_%d_%d" % [int(now * 1000.0), created_count],
			"bot_id": String(episodic.get("bot_id", request.get("bot_id", ""))),
			"memory_type": "semantic",
			"scope_key": String(episodic.get("scope_key", "")),
			"scope": _dict_or_empty(episodic.get("scope", request.get("scope", {}))),
			"domain_id": String(episodic.get("domain_id", "")),
			"session_id": String(episodic.get("session_id", "")),
			"instance_id": String(episodic.get("instance_id", "")),
			"subject_id": String(episodic.get("subject_id", "")),
			"subject_type": String(episodic.get("subject_type", "")),
			"content": distilled_content,
			"structured_payload": {
				"distilled_from": String(episodic.get("memory_id", "")),
				"source_content_preview": _preview(content, 120),
			},
			"visibility": String(episodic.get("visibility", "self_private")),
			"source": "memory_distillation",
			"importance": clampf(float(episodic.get("importance", 0.70)) * 0.90, 0.0, 1.0),
			"confidence": clampf(float(episodic.get("confidence", 0.70)) * 0.86, 0.0, 1.0),
			"status": "candidate",
			"created_at": now,
			"updated_at": now,
			"last_accessed_at": 0.0,
			"expires_at": 0.0,
			"evidence": [{"source": "distilled_from", "memory_id": String(episodic.get("memory_id", ""))}],
			"metadata": {"maintenance_type": String(request.get("maintenance_type", "manual"))},
			"embedding_status": "pending",
		}
		records.append(semantic_record)
		created.append({
			"memory_id": String(semantic_record.get("memory_id", "")),
			"source_memory_id": String(episodic.get("memory_id", "")),
			"memory_type": "semantic",
		})
		created_count += 1
	state["memory_records"] = records
	return {"created": created}


func _evolve_relationship_state(state: Dictionary, _request: Dictionary, now: float) -> Dictionary:
	var records := _array_or_empty(state.get("memory_records", []))
	var relationship_state := _dict_or_empty(state.get("relationship_state", {}))
	var updated: Array = []
	for item in records:
		if not (item is Dictionary):
			continue
		var record: Dictionary = item
		if String(record.get("memory_type", "")) != "relationship":
			continue
		var status := String(record.get("status", "active"))
		if status == "archived" or status == "forgotten":
			continue
		var subject_id := String(record.get("subject_id", "")).strip_edges()
		if subject_id == "":
			continue
		var current := _dict_or_empty(relationship_state.get(subject_id, {}))
		var delta := _relationship_delta(record)
		var trust_score := clampf(float(current.get("trust_score", 0.0)) + float(delta.get("trust", 0.0)), -1.0, 1.0)
		var affinity_score := clampf(float(current.get("affinity_score", 0.0)) + float(delta.get("affinity", 0.0)), -1.0, 1.0)
		var risk_score := clampf(float(current.get("risk_score", 0.0)) + float(delta.get("risk", 0.0)), 0.0, 1.0)
		var interaction_count := int(current.get("interaction_count", 0)) + 1
		var confidence := maxf(float(current.get("confidence", 0.0)), float(record.get("confidence", 0.0)))
		var next_state := {
			"subject_id": subject_id,
			"subject_type": String(record.get("subject_type", current.get("subject_type", ""))),
			"trust_score": _round_score(trust_score),
			"affinity_score": _round_score(affinity_score),
			"risk_score": _round_score(risk_score),
			"interaction_count": interaction_count,
			"confidence": _round_score(confidence),
			"last_memory_id": String(record.get("memory_id", "")),
			"updated_at": now,
		}
		relationship_state[subject_id] = next_state
		updated.append(next_state.duplicate(true))
	state["relationship_state"] = relationship_state
	return {"updated": updated}


func _detect_conflicts(state: Dictionary, _request: Dictionary, now: float) -> Dictionary:
	var records := _array_or_empty(state.get("memory_records", []))
	var conflicts: Array = _array_or_empty(state.get("conflict_records", []))
	var seen := {}
	for item in conflicts:
		if item is Dictionary:
			seen[String((item as Dictionary).get("conflict_id", ""))] = true
	for i in range(records.size()):
		if not (records[i] is Dictionary):
			continue
		var left: Dictionary = records[i]
		if not _conflict_candidate(left):
			continue
		for j in range(i + 1, records.size()):
			if not (records[j] is Dictionary):
				continue
			var right: Dictionary = records[j]
			if not _conflict_candidate(right):
				continue
			if String(left.get("memory_type", "")) != String(right.get("memory_type", "")):
				continue
			if String(left.get("subject_id", "")) != String(right.get("subject_id", "")):
				continue
			var reason := _conflict_reason(left, right)
			if reason == "":
				continue
			var conflict_id := _conflict_id(left, right)
			if seen.has(conflict_id):
				continue
			seen[conflict_id] = true
			_mark_conflict(records, i, conflict_id, String(right.get("memory_id", "")), reason, now)
			_mark_conflict(records, j, conflict_id, String(left.get("memory_id", "")), reason, now)
			conflicts.append({
				"conflict_id": conflict_id,
				"status": "unresolved",
				"reason": reason,
				"memory_ids": [String(left.get("memory_id", "")), String(right.get("memory_id", ""))],
				"memory_type": String(left.get("memory_type", "")),
				"subject_id": String(left.get("subject_id", "")),
				"created_at": now,
			})
	state["memory_records"] = records
	state["conflict_records"] = conflicts
	return {"conflicts": conflicts}


func _merge_similar_memories(state: Dictionary, request: Dictionary) -> Dictionary:
	var records := _array_or_empty(state.get("memory_records", []))
	var threshold := clampf(float(_dict_or_empty(request.get("options", {})).get("merge_threshold", DEFAULT_MERGE_THRESHOLD)), 0.50, 0.99)
	var removed := {}
	var merged: Array = []
	for i in range(records.size()):
		if removed.has(i) or not (records[i] is Dictionary):
			continue
		var left: Dictionary = records[i]
		if not _mergeable(left):
			continue
		for j in range(i + 1, records.size()):
			if removed.has(j) or not (records[j] is Dictionary):
				continue
			var right: Dictionary = records[j]
			if not _same_merge_bucket(left, right):
				continue
			var similarity := _similarity(left, right)
			if similarity < threshold:
				continue
			left = _merge_records(left, right, similarity)
			records[i] = left
			removed[j] = true
			merged.append({
				"target_memory_id": String(left.get("memory_id", "")),
				"merged_memory_id": String(right.get("memory_id", "")),
				"memory_type": String(left.get("memory_type", "")),
				"similarity": _round_score(similarity),
			})
	var kept: Array = []
	for i in range(records.size()):
		if removed.has(i):
			continue
		kept.append(records[i])
	state["memory_records"] = kept
	return {"merged": merged}


func _apply_forgetting(state: Dictionary, request: Dictionary, now: float) -> Dictionary:
	var records := _array_or_empty(state.get("memory_records", []))
	var options := _dict_or_empty(request.get("options", {}))
	var threshold := clampf(float(options.get("forgetting_threshold", DEFAULT_FORGETTING_THRESHOLD)), 0.0, 0.95)
	var delete_forgotten := bool(options.get("delete_forgotten", false))
	var archived: Array = []
	var deleted: Array = []
	var kept: Array = []
	for item in records:
		if not (item is Dictionary):
			continue
		var record: Dictionary = (item as Dictionary).duplicate(true)
		var memory_type := String(record.get("memory_type", ""))
		if memory_type == "working":
			kept.append(record)
			continue
		var status := String(record.get("status", "active"))
		if status == "forgotten":
			if delete_forgotten:
				deleted.append({"memory_id": String(record.get("memory_id", "")), "reason": "already_forgotten"})
			else:
				kept.append(record)
			continue
		var expires_at := float(record.get("expires_at", 0.0))
		var retention := _retention_score(record, now)
		var should_archive := (expires_at > 0.0 and now >= expires_at) or retention < threshold
		if should_archive and status != "archived":
			record["status"] = "archived"
			record["updated_at"] = now
			record["forgetting_score"] = _round_score(retention)
			record["embedding_status"] = "not_required"
			archived.append({
				"memory_id": String(record.get("memory_id", "")),
				"memory_type": memory_type,
				"retention_score": _round_score(retention),
				"reason": "expired" if expires_at > 0.0 and now >= expires_at else "low_retention",
			})
		kept.append(record)
	state["memory_records"] = kept
	return {
		"archived": archived,
		"deleted": deleted,
	}


func _merge_records(left: Dictionary, right: Dictionary, similarity: float) -> Dictionary:
	var merged := left.duplicate(true)
	var left_content := String(left.get("content", "")).strip_edges()
	var right_content := String(right.get("content", "")).strip_edges()
	if right_content != "" and not left_content.contains(right_content):
		merged["content"] = left_content if left_content.contains(right_content) else "%s\n%s" % [left_content, right_content]
	merged["importance"] = maxf(float(left.get("importance", 0.0)), float(right.get("importance", 0.0)))
	merged["confidence"] = maxf(float(left.get("confidence", 0.0)), float(right.get("confidence", 0.0)))
	merged["updated_at"] = Time.get_unix_time_from_system()
	merged["evidence"] = _merge_evidence(_array_or_empty(left.get("evidence", [])), _array_or_empty(right.get("evidence", [])))
	var metadata := _dict_or_empty(left.get("metadata", {}))
	var merged_ids := _array_or_empty(metadata.get("merged_memory_ids", []))
	merged_ids.append(String(right.get("memory_id", "")))
	metadata["merged_memory_ids"] = merged_ids
	metadata["last_merge_similarity"] = _round_score(similarity)
	merged["metadata"] = metadata
	merged["embedding_status"] = "stale"
	return merged


func _mergeable(record: Dictionary) -> bool:
	var memory_type := String(record.get("memory_type", ""))
	if memory_type == "profile" or memory_type == "working":
		return false
	var status := String(record.get("status", "active"))
	return status == "active" or status == "candidate"


func _same_merge_bucket(left: Dictionary, right: Dictionary) -> bool:
	if String(left.get("memory_type", "")) != String(right.get("memory_type", "")):
		return false
	if String(left.get("subject_id", "")) != String(right.get("subject_id", "")):
		return false
	return String(left.get("visibility", "self_private")) == String(right.get("visibility", "self_private"))


func _similarity(left: Dictionary, right: Dictionary) -> float:
	var left_vector := _vector_index.record_vector(left)
	var right_vector := _vector_index.record_vector(right)
	var vector_score := _vector_index.cosine(left_vector, right_vector)
	if vector_score > 0.0:
		return vector_score
	return _lexical_similarity(String(left.get("content", "")), String(right.get("content", "")))


func _retention_score(record: Dictionary, now: float) -> float:
	var importance := clampf(float(record.get("importance", 0.0)), 0.0, 1.0)
	var confidence := clampf(float(record.get("confidence", 0.0)), 0.0, 1.0)
	var updated_at := float(record.get("updated_at", record.get("created_at", now)))
	var days := maxf(0.0, (now - updated_at) / 86400.0)
	var recency := 1.0 / (1.0 + days / 30.0)
	var access_score := 0.15 if float(record.get("last_accessed_at", 0.0)) > 0.0 else 0.0
	return clampf(importance * 0.42 + confidence * 0.28 + recency * 0.15 + access_score, 0.0, 1.0)


func _distilled_content(content: String) -> String:
	var normalized := content.strip_edges().replace("\n", " ")
	if normalized.length() <= 120:
		return "从事件沉淀: %s" % normalized
	return "从事件沉淀: %s" % normalized.substr(0, 120)


func _semantic_key(content: String) -> String:
	var normalized := content.strip_edges().to_lower()
	return "%d" % normalized.hash()


func _lexical_similarity(left: String, right: String) -> float:
	var left_tokens := _token_lookup(left)
	var right_tokens := _token_lookup(right)
	if left_tokens.is_empty() or right_tokens.is_empty():
		return 0.0
	var intersection := 0
	for token in left_tokens.keys():
		if right_tokens.has(token):
			intersection += 1
	var union_count := left_tokens.size() + right_tokens.size() - intersection
	if union_count <= 0:
		return 0.0
	return float(intersection) / float(union_count)


func _token_lookup(text: String) -> Dictionary:
	var result := {}
	var normalized := text.strip_edges().to_lower()
	for i in range(normalized.length()):
		var ch := normalized.substr(i, 1)
		var code := ch.unicode_at(0)
		if _is_cjk(code):
			result[ch] = true
			if i + 1 < normalized.length():
				var next := normalized.substr(i + 1, 1)
				if _is_cjk(next.unicode_at(0)):
					result[ch + next] = true
	return result


func _relationship_delta(record: Dictionary) -> Dictionary:
	var payload := _dict_or_empty(record.get("structured_payload", {}))
	var content := String(record.get("content", "")).strip_edges().to_lower()
	var trust := float(payload.get("trust_delta", payload.get("trust", 0.0)))
	var affinity := float(payload.get("affinity_delta", payload.get("affinity", 0.0)))
	var risk := float(payload.get("risk_delta", payload.get("risk", 0.0)))
	var delta_text := String(payload.get("delta", payload.get("relationship_delta", ""))).strip_edges().to_lower()
	var combined := "%s %s" % [delta_text, content]
	if _contains_any(combined, ["trust_up", "positive", "cooperate", "help", "信任", "帮助", "合作"]):
		trust += 0.08
		affinity += 0.06
	if _contains_any(combined, ["trust_down", "negative", "distrust", "conflict", "deceive", "betray", "警惕", "怀疑", "冲突", "欺骗", "背叛"]):
		trust -= 0.08
		risk += 0.08
	if _contains_any(combined, ["risk_up", "danger", "威胁", "风险"]):
		risk += 0.10
	if _contains_any(combined, ["risk_down", "safe", "可靠", "稳定"]):
		risk -= 0.06
	return {
		"trust": clampf(trust, -0.30, 0.30),
		"affinity": clampf(affinity, -0.30, 0.30),
		"risk": clampf(risk, -0.30, 0.30),
	}


func _conflict_candidate(record: Dictionary) -> bool:
	var memory_type := String(record.get("memory_type", ""))
	if memory_type == "profile" or memory_type == "working":
		return false
	var status := String(record.get("status", "active"))
	return status == "active" or status == "candidate"


func _conflict_reason(left: Dictionary, right: Dictionary) -> String:
	var left_payload := _dict_or_empty(left.get("structured_payload", {}))
	var right_payload := _dict_or_empty(right.get("structured_payload", {}))
	var left_id := String(left.get("memory_id", ""))
	var right_id := String(right.get("memory_id", ""))
	if _string_array(left_payload.get("conflicts_with", _dict_or_empty(left.get("metadata", {})).get("conflicts_with", []))).has(right_id):
		return "explicit_conflict"
	if _string_array(right_payload.get("conflicts_with", _dict_or_empty(right.get("metadata", {})).get("conflicts_with", []))).has(left_id):
		return "explicit_conflict"
	var left_key := String(left_payload.get("claim_key", left_payload.get("fact_key", ""))).strip_edges()
	var right_key := String(right_payload.get("claim_key", right_payload.get("fact_key", ""))).strip_edges()
	if left_key != "" and left_key == right_key:
		var left_value := String(left_payload.get("claim_value", left_payload.get("fact_value", ""))).strip_edges()
		var right_value := String(right_payload.get("claim_value", right_payload.get("fact_value", ""))).strip_edges()
		if left_value != "" and right_value != "" and left_value != right_value:
			return "claim_value_conflict"
	var left_polarity := _polarity(left_payload)
	var right_polarity := _polarity(right_payload)
	if left_polarity != "" and right_polarity != "" and left_polarity != right_polarity:
		return "polarity_conflict"
	return ""


func _mark_conflict(records: Array, index: int, conflict_id: String, other_id: String, reason: String, now: float) -> void:
	var record: Dictionary = (records[index] as Dictionary).duplicate(true)
	var metadata := _dict_or_empty(record.get("metadata", {}))
	var conflict_ids := _string_array(metadata.get("conflict_ids", []))
	if not conflict_ids.has(conflict_id):
		conflict_ids.append(conflict_id)
	var conflicting_memory_ids := _string_array(metadata.get("conflicting_memory_ids", []))
	if other_id != "" and not conflicting_memory_ids.has(other_id):
		conflicting_memory_ids.append(other_id)
	metadata["conflict_status"] = "unresolved"
	metadata["conflict_reason"] = reason
	metadata["conflict_ids"] = conflict_ids
	metadata["conflicting_memory_ids"] = conflicting_memory_ids
	record["metadata"] = metadata
	record["conflict_status"] = "unresolved"
	record["updated_at"] = now
	records[index] = record


func _conflict_id(left: Dictionary, right: Dictionary) -> String:
	var ids := [String(left.get("memory_id", "")), String(right.get("memory_id", ""))]
	ids.sort()
	return "conflict_%d" % "|".join(ids).hash()


func _polarity(payload: Dictionary) -> String:
	var polarity := String(payload.get("polarity", payload.get("stance", payload.get("sentiment", "")))).strip_edges().to_lower()
	match polarity:
		"positive", "support", "true", "trust", "agree", "正向", "支持", "可信":
			return "positive"
		"negative", "oppose", "false", "distrust", "deny", "负向", "反对", "不可信":
			return "negative"
		_:
			return ""


func _contains_any(text: String, needles: Array) -> bool:
	for item in needles:
		if text.contains(String(item).to_lower()):
			return true
	return false


func _string_array(value) -> Array:
	var result: Array = []
	if value is String:
		var text := String(value).strip_edges()
		return [text] if text != "" else []
	for item in _array_or_empty(value):
		var text := String(item).strip_edges()
		if text != "":
			result.append(text)
	return result


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


func _preview(content: String, max_chars: int) -> String:
	if content.length() <= max_chars:
		return content
	return content.substr(0, max_chars - 3) + "..."


func _round_score(value: float) -> float:
	return round(value * 10000.0) / 10000.0


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
