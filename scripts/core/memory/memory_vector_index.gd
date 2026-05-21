extends RefCounted
class_name MemoryVectorIndex

const EMBEDDING_PROVIDER := "godot_local"
const EMBEDDING_MODEL := "token_hash_v1"
const EMBEDDING_VERSION := "local-token-hash-v1"
const EMBEDDING_DIMENSION := 128
const HNSW_GRAPH_M := 8


func refresh_state_indexes(state: Dictionary, options: Dictionary = {}) -> Dictionary:
	var records := _array_or_empty(state.get("memory_records", []))
	var now := Time.get_unix_time_from_system()
	var had_vector_index := not _dict_or_empty(state.get("vector_index", {})).is_empty()
	var previous_graph := _dict_or_empty(state.get("semantic_hnsw_graph", {}))
	var changed := false
	var ready := 0
	var skipped := 0
	var indexed := 0
	var embedding_jobs: Array = []
	var event_vectors := 0
	var semantic_vectors := 0
	for i in range(records.size()):
		if not (records[i] is Dictionary):
			continue
		var record: Dictionary = (records[i] as Dictionary).duplicate(true)
		if not embedding_required(record):
			record["embedding_status"] = String(record.get("embedding_status", "not_required"))
			records[i] = record
			skipped += 1
			continue
		var content_hash := content_hash_for_record(record)
		var embedding := _dict_or_empty(record.get("embedding", {}))
		var is_ready := (
			String(record.get("embedding_status", "")) == "ready"
			and String(embedding.get("version", "")) == EMBEDDING_VERSION
			and String(embedding.get("content_hash", "")) == content_hash
		)
		if not is_ready or bool(options.get("force_rebuild", false)):
			var vector := embed_text(String(record.get("content", "")))
			record["embedding"] = {
				"provider": EMBEDDING_PROVIDER,
				"model": EMBEDDING_MODEL,
				"version": EMBEDDING_VERSION,
				"dimension": EMBEDDING_DIMENSION,
				"content_hash": content_hash,
				"vector": vector,
				"updated_at": now,
			}
			record["embedding_status"] = "ready"
			record["embedding_updated_at"] = now
			records[i] = record
			changed = true
			indexed += 1
			embedding_jobs.append({
				"memory_id": String(record.get("memory_id", "")),
				"memory_type": String(record.get("memory_type", "")),
				"status": "ready",
			})
		else:
			records[i] = record
			ready += 1
		match String(record.get("memory_type", "")):
			"episodic":
				event_vectors += 1
			"semantic", "reflection":
				semantic_vectors += 1
	state["memory_records"] = records
	var graph_report := build_semantic_graph(records)
	var graph := _dict_or_empty(graph_report.get("graph", {}))
	var graph_changed := JSON.stringify(previous_graph) != JSON.stringify(graph)
	state["semantic_hnsw_graph"] = graph
	var vector_index := {
		"provider": EMBEDDING_PROVIDER,
		"model": EMBEDDING_MODEL,
		"version": EMBEDDING_VERSION,
		"dimension": EMBEDDING_DIMENSION,
		"backend": "godot_local_vector",
		"event_backend": "local_sqlite_vec_slot",
		"semantic_backend": "local_hnsw_graph",
		"updated_at": now,
		"record_count": records.size(),
		"ready_embedding_count": ready + indexed,
		"indexed_embedding_count": indexed,
		"skipped_embedding_count": skipped,
		"event_vector_count": event_vectors,
		"semantic_vector_count": semantic_vectors,
		"graph_node_count": int(graph_report.get("node_count", 0)),
		"graph_edge_count": int(graph_report.get("edge_count", 0)),
	}
	state["vector_index"] = vector_index
	changed = changed or graph_changed or not had_vector_index
	return {
		"state": state,
		"report": {
			"changed": changed,
			"embedding_provider": EMBEDDING_PROVIDER,
			"embedding_model": EMBEDDING_MODEL,
			"embedding_version": EMBEDDING_VERSION,
			"embedding_dimension": EMBEDDING_DIMENSION,
			"indexed_embedding_count": indexed,
			"ready_embedding_count": ready + indexed,
			"event_vector_count": event_vectors,
			"semantic_vector_count": semantic_vectors,
			"hnsw_graph": graph_report,
			"embedding_jobs": embedding_jobs,
			"created_at": now,
		},
	}


func build_semantic_graph(records: Array) -> Dictionary:
	var nodes: Array = []
	for item in records:
		if not (item is Dictionary):
			continue
		var record: Dictionary = item
		var memory_type := String(record.get("memory_type", ""))
		if memory_type != "semantic" and memory_type != "reflection":
			continue
		if String(record.get("embedding_status", "")) != "ready":
			continue
		var vector := record_vector(record)
		if vector.is_empty():
			continue
		nodes.append({
			"memory_id": String(record.get("memory_id", "")),
			"memory_type": memory_type,
			"vector": vector,
		})
	var neighbors := {}
	var edge_count := 0
	for i in range(nodes.size()):
		var node: Dictionary = nodes[i]
		var scored: Array = []
		for j in range(nodes.size()):
			if i == j:
				continue
			var other: Dictionary = nodes[j]
			var score := cosine(node.get("vector", []), other.get("vector", []))
			if score <= 0.0:
				continue
			scored.append({
				"memory_id": String(other.get("memory_id", "")),
				"score": _round_score(score),
			})
		scored.sort_custom(_sort_neighbor_score)
		var kept := scored.slice(0, mini(HNSW_GRAPH_M, scored.size()))
		neighbors[String(node.get("memory_id", ""))] = kept
		edge_count += kept.size()
	return {
		"changed": true,
		"algorithm": "local_hnsw_graph_v1",
		"backend": "godot_local",
		"m": HNSW_GRAPH_M,
		"node_count": nodes.size(),
		"edge_count": edge_count,
		"graph": {
			"algorithm": "local_hnsw_graph_v1",
			"backend": "godot_local",
			"m": HNSW_GRAPH_M,
			"nodes": nodes.size(),
			"edges": edge_count,
			"neighbors": neighbors,
		},
	}


func embedding_required(record: Dictionary) -> bool:
	var memory_type := String(record.get("memory_type", ""))
	var status := String(record.get("status", "active"))
	if status == "archived" or status == "forgotten":
		return false
	return memory_type == "episodic" or memory_type == "semantic" or memory_type == "reflection"


func content_hash_for_record(record: Dictionary) -> String:
	return "%s:%s:%d" % [
		String(record.get("memory_type", "")),
		String(record.get("memory_id", "")),
		String(record.get("content", "")).hash(),
	]


func embed_text(text: String) -> Array:
	var vector: Array = []
	vector.resize(EMBEDDING_DIMENSION)
	for i in range(EMBEDDING_DIMENSION):
		vector[i] = 0.0
	var normalized := text.strip_edges().to_lower()
	if normalized == "":
		return vector
	var tokens := _tokens_for_text(normalized)
	for item in tokens:
		if not (item is Dictionary):
			continue
		var token := String((item as Dictionary).get("token", "")).strip_edges()
		if token == "":
			continue
		var weight := float((item as Dictionary).get("weight", 1.0))
		var slot := absi(token.hash()) % EMBEDDING_DIMENSION
		var sign := -1.0 if absi(("%s:sign" % token).hash()) % 2 == 0 else 1.0
		vector[slot] = float(vector[slot]) + weight * sign
	var norm := _dense_norm(vector)
	if norm <= 0.0:
		return vector
	for i in range(vector.size()):
		vector[i] = _round_score(float(vector[i]) / norm)
	return vector


func record_vector(record: Dictionary) -> Array:
	var embedding := _dict_or_empty(record.get("embedding", {}))
	if String(embedding.get("version", "")) != EMBEDDING_VERSION:
		return []
	return _array_or_empty(embedding.get("vector", []))


func cosine(left_value, right_value) -> float:
	var left := _array_or_empty(left_value)
	var right := _array_or_empty(right_value)
	if left.is_empty() or right.is_empty():
		return 0.0
	var count = mini(left.size(), right.size())
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


func _tokens_for_text(text: String) -> Array:
	var tokens: Array = []
	var ascii_word := ""
	var cjk_run: Array = []
	for i in range(text.length()):
		var ch := text.substr(i, 1)
		var code := ch.unicode_at(0)
		if _is_ascii_alnum(code):
			ascii_word += ch
			_flush_cjk_run(tokens, cjk_run)
			cjk_run = []
			continue
		if ascii_word.length() >= 2:
			_add_token(tokens, ascii_word, 1.5)
		ascii_word = ""
		if _is_cjk(code):
			cjk_run.append(ch)
			_add_token(tokens, ch, 0.55)
		else:
			_flush_cjk_run(tokens, cjk_run)
			cjk_run = []
	if ascii_word.length() >= 2:
		_add_token(tokens, ascii_word, 1.5)
	_flush_cjk_run(tokens, cjk_run)
	return tokens


func _flush_cjk_run(tokens: Array, cjk_run: Array) -> void:
	if cjk_run.size() < 2:
		return
	for i in range(cjk_run.size() - 1):
		_add_token(tokens, String(cjk_run[i]) + String(cjk_run[i + 1]), 1.4)
	if cjk_run.size() >= 3:
		for i in range(cjk_run.size() - 2):
			_add_token(tokens, String(cjk_run[i]) + String(cjk_run[i + 1]) + String(cjk_run[i + 2]), 1.8)


func _add_token(tokens: Array, token: String, weight: float) -> void:
	var trimmed := token.strip_edges()
	if trimmed == "":
		return
	tokens.append({"token": trimmed, "weight": weight})


func _dense_norm(vector: Array) -> float:
	var total := 0.0
	for item in vector:
		var value := float(item)
		total += value * value
	return sqrt(total)


func _sort_neighbor_score(a, b) -> bool:
	var left: Dictionary = a if a is Dictionary else {}
	var right: Dictionary = b if b is Dictionary else {}
	return float(left.get("score", 0.0)) > float(right.get("score", 0.0))


func _round_score(value: float) -> float:
	return round(value * 10000.0) / 10000.0


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
