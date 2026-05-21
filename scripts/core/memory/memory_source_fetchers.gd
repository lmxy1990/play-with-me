extends RefCounted
class_name MemorySourceFetchers


func fetch_sources(state: Dictionary, query_plan: Dictionary) -> Dictionary:
	var candidates: Array = []
	var report := {
		"source_counts": {},
		"structured_count": 0,
		"vector_candidate_count": 0,
		"warnings": [],
	}
	var rank := 0
	rank = _append_profile_snapshot(candidates, state, query_plan, report, rank)
	rank = _append_memory_records(candidates, state, query_plan, report, rank)
	report["candidate_count"] = candidates.size()
	return {
		"candidates": candidates,
		"report": report,
	}


func _append_profile_snapshot(candidates: Array, state: Dictionary, query_plan: Dictionary, report: Dictionary, rank: int) -> int:
	var snapshot := _dict_or_empty(state.get("persona_snapshot", {}))
	var content := String(snapshot.get("content", "")).strip_edges()
	if content == "":
		return rank
	candidates.append({
		"candidate_id": String(snapshot.get("memory_id", "profile_snapshot")),
		"memory_id": String(snapshot.get("memory_id", "profile_snapshot")),
		"bot_id": String(snapshot.get("bot_id", "")),
		"memory_type": "profile",
		"retrieval_source": "profile_snapshot",
		"source": String(snapshot.get("source", "persona_seed")),
		"content": content,
		"structured_payload": _dict_or_empty(snapshot.get("structured_payload", {})),
		"evidence": _array_or_empty(snapshot.get("evidence", [])),
		"scope": _dict_or_empty(state.get("scope", {})),
		"visibility": String(snapshot.get("visibility", "self_private")),
		"status": String(snapshot.get("status", "active")),
		"importance": float(snapshot.get("importance", 0.82)),
		"confidence": float(snapshot.get("confidence", 0.80)),
		"created_at": float(snapshot.get("created_at", 0.0)),
		"updated_at": float(snapshot.get("updated_at", 0.0)),
		"raw_scores": {"source_rank": rank},
		"_rank": rank,
	})
	_increment_source(report, "profile_snapshot")
	return rank + 1


func _append_memory_records(candidates: Array, state: Dictionary, query_plan: Dictionary, report: Dictionary, rank: int) -> int:
	var filters := _dict_or_empty(query_plan.get("filters", {}))
	var target_ids := _array_to_lookup(_array_or_empty(filters.get("target_entity_ids", [])))
	var visible_ids := _array_to_lookup(_array_or_empty(filters.get("visible_entity_ids", [])))
	var native_hits := _native_hits_by_memory_id(query_plan)
	var native_report := _dict_or_empty(query_plan.get("native_vector_report", {}))
	for item in _array_or_empty(native_report.get("warnings", [])):
		(report["warnings"] as Array).append(item)
	for item in _array_or_empty(state.get("memory_records", [])):
		if not (item is Dictionary):
			continue
		var record: Dictionary = item
		var content := String(record.get("content", "")).strip_edges()
		if content == "":
			continue
		var memory_type := String(record.get("memory_type", "episodic")).strip_edges()
		if memory_type == "relationship" and not _relationship_in_scope(record, target_ids, visible_ids):
			continue
		var native_hit := _dict_or_empty(native_hits.get(String(record.get("memory_id", "")), {}))
		var native_score := float(native_hit.get("score", 0.0)) if not native_hit.is_empty() else 0.0
		var vector_score = maxf(_vector_score(record, query_plan), native_score)
		var retrieval_source := _retrieval_source_for_record(record, query_plan, vector_score, native_hit)
		if vector_score > 0.0:
			report["vector_candidate_count"] = int(report.get("vector_candidate_count", 0)) + 1
		if not native_hit.is_empty():
			report["native_vector_candidate_count"] = int(report.get("native_vector_candidate_count", 0)) + 1
		var raw_scores := {
			"source_rank": rank,
			"vector_score": vector_score,
		}
		if not native_hit.is_empty():
			raw_scores["native_vector_score"] = native_score
			raw_scores["native_distance"] = float(native_hit.get("distance", 0.0))
			raw_scores["native_backend"] = String(native_hit.get("backend", ""))
		candidates.append({
			"candidate_id": String(record.get("memory_id", "%s:%d" % [memory_type, rank])),
			"memory_id": String(record.get("memory_id", "")),
			"bot_id": String(record.get("bot_id", "")),
			"memory_type": memory_type,
			"retrieval_source": retrieval_source,
			"source": String(record.get("source", memory_type)),
			"content": content,
			"structured_payload": _dict_or_empty(record.get("structured_payload", {})),
			"evidence": _array_or_empty(record.get("evidence", [])),
			"scope": _dict_or_empty(record.get("scope", state.get("scope", {}))),
			"subject_id": String(record.get("subject_id", "")),
			"subject_type": String(record.get("subject_type", "")),
			"visibility": String(record.get("visibility", "self_private")),
			"status": String(record.get("status", "active")),
			"importance": float(record.get("importance", 0.55)),
			"confidence": float(record.get("confidence", 0.70)),
			"created_at": float(record.get("created_at", 0.0)),
			"updated_at": float(record.get("updated_at", 0.0)),
			"metadata": _dict_or_empty(record.get("metadata", {})),
			"embedding_status": String(record.get("embedding_status", "")),
			"vector_score": vector_score if vector_score > 0.0 else null,
			"raw_scores": raw_scores,
			"_rank": rank,
		})
		_increment_source(report, retrieval_source)
		report["structured_count"] = int(report.get("structured_count", 0)) + 1
		rank += 1
	return rank


func _retrieval_source_for_record(record: Dictionary, query_plan: Dictionary, vector_score: float, native_hit: Dictionary = {}) -> String:
	var explicit := String(record.get("retrieval_source", "")).strip_edges()
	if explicit != "":
		return explicit
	if not native_hit.is_empty():
		var native_source := String(native_hit.get("retrieval_source", "")).strip_edges()
		if native_source != "":
			return native_source
	var vector_sources := _dict_or_empty(query_plan.get("vector_sources", {}))
	if vector_score > 0.0:
		match String(record.get("memory_type", "")):
			"episodic":
				if bool(vector_sources.get("sqlite_vec_event", false)):
					return "sqlite_vec_event"
			"semantic", "reflection":
				if bool(vector_sources.get("hnsw_semantic", false)):
					return "hnsw_semantic"
	match String(record.get("memory_type", "")):
		"profile":
			return "profile_snapshot"
		"working":
			return "working_memory"
		"relationship":
			return "relationship_memory"
		"semantic":
			return "text_retrieval"
		"reflection":
			return "reflection_memory"
		_:
			return "text_retrieval"


func _vector_score(record: Dictionary, query_plan: Dictionary) -> float:
	if not bool(query_plan.get("vector_enabled", false)):
		return 0.0
	var query_vector := _array_or_empty(query_plan.get("query_embedding", []))
	if query_vector.is_empty():
		return 0.0
	var embedding := _dict_or_empty(record.get("embedding", {}))
	var vector := _array_or_empty(embedding.get("vector", []))
	if vector.is_empty() or String(record.get("embedding_status", "")) != "ready":
		return 0.0
	return _cosine(query_vector, vector)


func _native_hits_by_memory_id(query_plan: Dictionary) -> Dictionary:
	var result := {}
	for item in _array_or_empty(query_plan.get("native_vector_results", [])):
		if not (item is Dictionary):
			continue
		var hit: Dictionary = item
		var memory_id := String(hit.get("memory_id", "")).strip_edges()
		if memory_id == "":
			continue
		var previous := _dict_or_empty(result.get(memory_id, {}))
		if previous.is_empty() or float(hit.get("score", 0.0)) > float(previous.get("score", 0.0)):
			result[memory_id] = hit.duplicate(true)
	return result


func _cosine(left: Array, right: Array) -> float:
	var count = mini(left.size(), right.size())
	if count <= 0:
		return 0.0
	var dot := 0.0
	var left_norm := 0.0
	var right_norm := 0.0
	for i in range(count):
		var l := float(left[i])
		var r := float(right[i])
		dot += l * r
		left_norm += l * l
		right_norm += r * r
	if dot <= 0.0 or left_norm <= 0.0 or right_norm <= 0.0:
		return 0.0
	return clampf(dot / (sqrt(left_norm) * sqrt(right_norm)), 0.0, 1.0)


func _relationship_in_scope(record: Dictionary, target_ids: Dictionary, visible_ids: Dictionary) -> bool:
	if target_ids.is_empty() and visible_ids.is_empty():
		return true
	var subject_id := String(record.get("subject_id", "")).strip_edges()
	if subject_id == "":
		return true
	return target_ids.has(subject_id) or visible_ids.has(subject_id)


func _increment_source(report: Dictionary, source: String) -> void:
	var counts := _dict_or_empty(report.get("source_counts", {}))
	counts[source] = int(counts.get(source, 0)) + 1
	report["source_counts"] = counts


func _array_to_lookup(values: Array) -> Dictionary:
	var result := {}
	for item in values:
		var key := String(item).strip_edges()
		if key != "":
			result[key] = true
	return result


func _dict_or_empty(value) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}


func _array_or_empty(value) -> Array:
	if value is Array:
		return (value as Array).duplicate(true)
	return []
