extends RefCounted
class_name MemoryPolicyReranker


func rerank(candidates: Array, query_plan: Dictionary) -> Dictionary:
	var query := _query_text(query_plan)
	var query_vector := _text_vector(query)
	var vector_enabled := bool(query_plan.get("vector_enabled", false))
	var weights := _weights(vector_enabled)
	var scored := []
	var dropped := []
	for i in range(candidates.size()):
		if not (candidates[i] is Dictionary):
			continue
		var candidate: Dictionary = (candidates[i] as Dictionary).duplicate(true)
		var content := String(candidate.get("content", "")).strip_edges()
		var lexical_score := _retrieval_score(query, query_vector, content)
		var vector_score := _candidate_vector_score(candidate)
		var structured_priority := _structured_priority(candidate)
		if lexical_score <= 0.0 and vector_score <= 0.0 and structured_priority <= 0.0:
			candidate["drop_reason"] = "zero_retrieval_score"
			dropped.append(_candidate_report(candidate))
			continue
		if lexical_score <= 0.0:
			lexical_score = 0.05
		var importance := clampf(float(candidate.get("importance", _default_importance(candidate))), 0.0, 1.0)
		var confidence := clampf(float(candidate.get("confidence", _default_confidence(candidate))), 0.0, 1.0)
		var recency := _recency_score(float(candidate.get("created_at", 0.0)))
		var relationship_priority := 1.0 if String(candidate.get("memory_type", "")) == "relationship" else 0.0
		var final_score := (
			lexical_score * float(weights.get("lexical_score", 0.45))
			+ vector_score * float(weights.get("vector_score", 0.0))
			+ importance * float(weights.get("importance", 0.20))
			+ confidence * float(weights.get("confidence", 0.15))
			+ recency * float(weights.get("recency_score", 0.10))
			+ relationship_priority * float(weights.get("relationship_priority", 0.10))
			+ structured_priority
		)
		candidate["lexical_score"] = _round_score(lexical_score)
		candidate["vector_score"] = _round_score(vector_score) if vector_score > 0.0 else null
		candidate["importance"] = _round_score(importance)
		candidate["confidence"] = _round_score(confidence)
		candidate["recency_score"] = _round_score(recency)
		candidate["relationship_priority"] = _round_score(relationship_priority)
		candidate["structured_priority"] = _round_score(structured_priority)
		candidate["final_score"] = _round_score(final_score)
		candidate["score"] = candidate["final_score"]
		candidate["_rerank_rank"] = i
		scored.append(candidate)
	scored.sort_custom(_sort_candidates)
	return {
		"candidates": scored,
		"report": {
			"input_count": candidates.size(),
			"scored_count": scored.size(),
			"dropped_count": dropped.size(),
			"mode": "hybrid_vector" if vector_enabled else "text_retrieval",
			"weights": weights,
			"dropped": dropped,
		},
	}


func _query_text(query_plan: Dictionary) -> String:
	var queries := _array_or_empty(query_plan.get("queries", []))
	for item in queries:
		if item is Dictionary:
			var text := String((item as Dictionary).get("text", "")).strip_edges()
			if text != "":
				return text
	return ""


func _default_importance(candidate: Dictionary) -> float:
	match String(candidate.get("memory_type", "")):
		"working":
			return 0.75
		"relationship":
			return 0.70
		"semantic":
			return 0.65
		"reflection":
			return 0.60
		_:
			return 0.55


func _default_confidence(candidate: Dictionary) -> float:
	match String(candidate.get("source", "")):
		"round_summary":
			return 0.78
		"long_term":
			return 0.74
		_:
			return 0.70


func _weights(vector_enabled: bool) -> Dictionary:
	if vector_enabled:
		return {
			"lexical_score": 0.30,
			"vector_score": 0.25,
			"importance": 0.18,
			"confidence": 0.12,
			"recency_score": 0.08,
			"relationship_priority": 0.07,
			"structured_priority": "fixed_bonus",
		}
	return {
		"lexical_score": 0.45,
		"vector_score": 0.0,
		"importance": 0.20,
		"confidence": 0.15,
		"recency_score": 0.10,
		"relationship_priority": 0.10,
		"structured_priority": "fixed_bonus",
	}


func _candidate_vector_score(candidate: Dictionary) -> float:
	var value = candidate.get("vector_score", null)
	if value is float or value is int:
		return clampf(float(value), 0.0, 1.0)
	var raw_scores := _dict_or_empty(candidate.get("raw_scores", {}))
	var raw = raw_scores.get("vector_score", null)
	if raw is float or raw is int:
		return clampf(float(raw), 0.0, 1.0)
	return 0.0


func _structured_priority(candidate: Dictionary) -> float:
	match String(candidate.get("memory_type", "")):
		"profile":
			return 0.35
		"working":
			return 0.30
		"relationship":
			return 0.24
		_:
			return 0.0


func _recency_score(created_at: float) -> float:
	if created_at <= 0.0:
		return 0.35
	var age_seconds := maxf(0.0, Time.get_unix_time_from_system() - created_at)
	if age_seconds <= 3600.0:
		return 1.0
	if age_seconds <= 86400.0:
		return 0.85
	if age_seconds <= 604800.0:
		return 0.65
	return 0.40


func _retrieval_score(query: String, query_vector: Dictionary, content: String) -> float:
	if query_vector.is_empty():
		return 0.0
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


func _candidate_report(candidate: Dictionary) -> Dictionary:
	return {
		"memory_id": String(candidate.get("memory_id", "")),
		"memory_type": String(candidate.get("memory_type", "")),
		"retrieval_source": String(candidate.get("retrieval_source", "")),
		"score": candidate.get("score", 0.0),
		"drop_reason": String(candidate.get("drop_reason", "")),
	}


func _sort_candidates(a, b) -> bool:
	var left: Dictionary = a if a is Dictionary else {}
	var right: Dictionary = b if b is Dictionary else {}
	var score_left := float(left.get("final_score", 0.0))
	var score_right := float(right.get("final_score", 0.0))
	if score_left == score_right:
		return int(left.get("_rank", left.get("_rerank_rank", 0))) < int(right.get("_rank", right.get("_rerank_rank", 0)))
	return score_left > score_right


func _round_score(value: float) -> float:
	return round(value * 10000.0) / 10000.0


func _is_ascii_alnum(code: int) -> bool:
	return (code >= 48 and code <= 57) or (code >= 97 and code <= 122)


func _is_cjk(code: int) -> bool:
	return (code >= 0x4e00 and code <= 0x9fff) or (code >= 0x3400 and code <= 0x4dbf)


func _array_or_empty(value) -> Array:
	if value is Array:
		return (value as Array).duplicate(true)
	return []


func _dict_or_empty(value) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}
