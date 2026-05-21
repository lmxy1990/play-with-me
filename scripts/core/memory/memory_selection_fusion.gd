extends RefCounted
class_name MemorySelectionFusion


func select(scored_candidates: Array, query_plan: Dictionary) -> Dictionary:
	var budget_plan: Dictionary = _dict_or_empty(query_plan.get("budget_plan", {}))
	var limit := maxi(0, int(budget_plan.get("final_max_items", scored_candidates.size())))
	var max_token_budget := maxi(1, int(budget_plan.get("max_token_budget", 2048)))
	var hard_token_limit := maxi(max_token_budget, int(budget_plan.get("hard_token_limit", 4096)))
	var layer_limits := _dict_or_empty(budget_plan.get("layer_limits", {}))
	var selected: Array = []
	var dropped: Array = []
	var kept_counts := {}
	var dropped_counts := {}
	var drop_reasons := {}
	var estimated_used := 0
	for i in range(scored_candidates.size()):
		if not (scored_candidates[i] is Dictionary):
			continue
		var candidate: Dictionary = (scored_candidates[i] as Dictionary).duplicate(true)
		var memory_type := String(candidate.get("memory_type", "episodic"))
		var estimated_tokens := _estimate_tokens(String(candidate.get("content", "")))
		var drop_reason := ""
		if selected.size() >= limit:
			drop_reason = "final_max_items"
		elif int(kept_counts.get(memory_type, 0)) >= int(layer_limits.get(memory_type, limit)):
			drop_reason = "layer_limit"
		elif estimated_used + estimated_tokens > max_token_budget:
			if _is_protected_type(memory_type) and estimated_used + estimated_tokens <= hard_token_limit:
				candidate["budget_warning"] = "over_soft_budget"
			else:
				drop_reason = "token_budget"
		if drop_reason == "":
			candidate["kept"] = true
			candidate["estimated_tokens"] = estimated_tokens
			candidate.erase("_rerank_rank")
			candidate.erase("_rank")
			selected.append(candidate)
			kept_counts[memory_type] = int(kept_counts.get(memory_type, 0)) + 1
			estimated_used += estimated_tokens
		else:
			candidate["kept"] = false
			candidate["drop_reason"] = drop_reason
			dropped.append(_candidate_report(candidate))
			dropped_counts[memory_type] = int(dropped_counts.get(memory_type, 0)) + 1
			drop_reasons[drop_reason] = int(drop_reasons.get(drop_reason, 0)) + 1
	return {
		"items": selected,
		"agent_memory_context": _agent_memory_context(selected, query_plan),
		"report": {
			"input_count": scored_candidates.size(),
			"selected_count": selected.size(),
			"dropped_count": dropped.size(),
			"fused_count": 0,
			"final_max_items": limit,
			"max_token_budget": max_token_budget,
			"hard_token_limit": hard_token_limit,
			"estimated_used": estimated_used,
			"kept_counts": kept_counts,
			"dropped_counts": dropped_counts,
			"drop_reasons": drop_reasons,
			"dropped": dropped,
		},
	}


func _agent_memory_context(items: Array, query_plan: Dictionary) -> Dictionary:
	var context := {
		"persona_snapshot": null,
		"working_memory": [],
		"relationship_context": [],
		"semantic_context": [],
		"episodic_context": [],
		"reflection_context": [],
		"warnings": _array_or_empty(query_plan.get("warnings", [])),
	}
	for item in items:
		if not (item is Dictionary):
			continue
		var entry: Dictionary = (item as Dictionary).duplicate(true)
		match String(entry.get("memory_type", "")):
			"profile":
				context["persona_snapshot"] = entry
			"working":
				(context["working_memory"] as Array).append(entry)
			"relationship":
				(context["relationship_context"] as Array).append(entry)
			"semantic":
				(context["semantic_context"] as Array).append(entry)
			"reflection":
				(context["reflection_context"] as Array).append(entry)
			_:
				(context["episodic_context"] as Array).append(entry)
	return context


func _candidate_report(candidate: Dictionary) -> Dictionary:
	return {
		"memory_id": String(candidate.get("memory_id", "")),
		"memory_type": String(candidate.get("memory_type", "")),
		"retrieval_source": String(candidate.get("retrieval_source", "")),
		"score": candidate.get("score", 0.0),
		"estimated_tokens": candidate.get("estimated_tokens", 0),
		"drop_reason": String(candidate.get("drop_reason", "")),
	}


func _estimate_tokens(content: String) -> int:
	var normalized := content.strip_edges()
	if normalized == "":
		return 0
	return maxi(1, int(ceil(float(normalized.length()) / 2.0)))


func _is_protected_type(memory_type: String) -> bool:
	return memory_type == "profile" or memory_type == "working" or memory_type == "relationship"


func _dict_or_empty(value) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}


func _array_or_empty(value) -> Array:
	if value is Array:
		return (value as Array).duplicate(true)
	return []
