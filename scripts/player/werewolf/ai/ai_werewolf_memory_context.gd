extends RefCounted

const PromptPolicyScript := preload("res://scripts/player/werewolf/ai/ai_werewolf_prompt_policy.gd")
const SESSION_ENTRY_LIMIT := 8
const SESSION_SUMMARY_LIMIT := 4
const PROFILE_ENTRY_LIMIT := 2
const PROFILE_SUMMARY_LIMIT := 2
const SESSION_RETRIEVAL_LIMIT := 4
const PROFILE_RETRIEVAL_LIMIT := 3
const MERGED_RETRIEVAL_LIMIT := 6


func build_prompt(memory_manager, memory_builder, session_scope: Dictionary, profile_scope: Dictionary, config_summary: String, retrieval_query: String, context_budget: int = 8192) -> Dictionary:
	var budget := maxi(1, context_budget)
	var limits := limits_for_context_budget(budget)
	if not bool(PromptPolicyScript.include_memory_hints):
		return {
			"configSummary": config_summary.strip_edges(),
			"contextBudgetTokens": budget,
			"contextLimits": limits,
		}
	var session_context: Dictionary = memory_manager.prompt_context(session_scope, int(limits.get("sessionEntryLimit", SESSION_ENTRY_LIMIT)), int(limits.get("sessionSummaryLimit", SESSION_SUMMARY_LIMIT)))
	var profile_context: Dictionary = memory_manager.prompt_context(profile_scope, int(limits.get("profileEntryLimit", PROFILE_ENTRY_LIMIT)), int(limits.get("profileSummaryLimit", PROFILE_SUMMARY_LIMIT)))
	var merged_context := session_context.duplicate(true)
	var long_term := String(profile_context.get("longTermMemorySummary", "")).strip_edges()
	if long_term != "":
		merged_context["longTermMemorySummary"] = long_term
	var query := retrieval_query.strip_edges()
	if query != "" and memory_manager.has_method("retrieve"):
		var retrieved := merge_retrieved_memory(
			memory_manager.retrieve(session_scope, query, int(limits.get("sessionRetrievalLimit", SESSION_RETRIEVAL_LIMIT)), false),
			memory_manager.retrieve(profile_scope, query, int(limits.get("profileRetrievalLimit", PROFILE_RETRIEVAL_LIMIT)), true),
			int(limits.get("mergedRetrievalLimit", MERGED_RETRIEVAL_LIMIT))
		)
		if not retrieved.is_empty():
			merged_context["retrievedMemoryEntries"] = retrieved
	var payload: Dictionary = memory_builder.prompt_memory(merged_context, config_summary)
	payload["contextBudgetTokens"] = budget
	payload["contextLimits"] = limits
	return payload


func retrieval_query(werewolf_state: Dictionary, player_label: String, role_label: String, phase_label: String, private_info: Dictionary, timeline_events: Array, context_budget: int = 8192) -> String:
	var parts := []
	parts.append("第%d天 %s" % [int(werewolf_state.get("day", 0)), phase_label])
	parts.append("自己 %s 身份 %s" % [player_label, role_label])
	var current_action: Dictionary = werewolf_state.get("current_action", {})
	var action_key := String(current_action.get("key", "")).strip_edges()
	var action_label := String(current_action.get("label", "")).strip_edges()
	if action_key != "" or action_label != "":
		parts.append("当前行动 %s %s" % [action_key, action_label])
	if not private_info.is_empty():
		parts.append(JSON.stringify(private_info))
	for item in timeline_events:
		if not (item is Dictionary):
			continue
		var event: Dictionary = item
		var description := String(event.get("speechText", "")).strip_edges()
		if description == "":
			description = String(event.get("description", "")).strip_edges()
		if description == "":
			continue
		parts.append("%s %s" % [String(event.get("type", "")), description])
	return trim_query_text("\n".join(parts), query_char_limit_for_context_budget(context_budget))


func limits_for_context_budget(context_budget: int) -> Dictionary:
	var budget := maxi(1, context_budget)
	if budget < 4096:
		return {
			"sessionEntryLimit": 3,
			"sessionSummaryLimit": 2,
			"profileEntryLimit": 1,
			"profileSummaryLimit": 1,
			"sessionRetrievalLimit": 2,
			"profileRetrievalLimit": 1,
			"mergedRetrievalLimit": 3,
			"queryCharLimit": 600,
		}
	if budget < 8192:
		return {
			"sessionEntryLimit": 5,
			"sessionSummaryLimit": 3,
			"profileEntryLimit": 1,
			"profileSummaryLimit": 1,
			"sessionRetrievalLimit": 3,
			"profileRetrievalLimit": 2,
			"mergedRetrievalLimit": 4,
			"queryCharLimit": 900,
		}
	if budget < 32768:
		return {
			"sessionEntryLimit": SESSION_ENTRY_LIMIT,
			"sessionSummaryLimit": SESSION_SUMMARY_LIMIT,
			"profileEntryLimit": PROFILE_ENTRY_LIMIT,
			"profileSummaryLimit": PROFILE_SUMMARY_LIMIT,
			"sessionRetrievalLimit": SESSION_RETRIEVAL_LIMIT,
			"profileRetrievalLimit": PROFILE_RETRIEVAL_LIMIT,
			"mergedRetrievalLimit": MERGED_RETRIEVAL_LIMIT,
			"queryCharLimit": 1200,
		}
	if budget < 131072:
		return {
			"sessionEntryLimit": 14,
			"sessionSummaryLimit": 6,
			"profileEntryLimit": 3,
			"profileSummaryLimit": 3,
			"sessionRetrievalLimit": 6,
			"profileRetrievalLimit": 4,
			"mergedRetrievalLimit": 8,
			"queryCharLimit": 1800,
		}
	return {
		"sessionEntryLimit": 24,
		"sessionSummaryLimit": 10,
		"profileEntryLimit": 4,
		"profileSummaryLimit": 4,
		"sessionRetrievalLimit": 10,
		"profileRetrievalLimit": 6,
		"mergedRetrievalLimit": 12,
		"queryCharLimit": 2400,
	}


func query_char_limit_for_context_budget(context_budget: int) -> int:
	return int(limits_for_context_budget(context_budget).get("queryCharLimit", 1200))


func round_summary_texts(memory_payload: Dictionary) -> Array:
	var result := []
	for item in memory_payload.get("roundSummaries", []):
		if item is Dictionary:
			var parts := []
			for key in ["publicSummary", "privateSummary", "decisionSummary", "suspicionSummary", "strategySummary"]:
				var value := String((item as Dictionary).get(key, "")).strip_edges()
				if value != "":
					parts.append(value)
			if not parts.is_empty():
				result.append("\n".join(parts))
		else:
			var text := String(item).strip_edges()
			if text != "":
				result.append(text)
	return result


func recent_entry_texts(memory_payload: Dictionary) -> Array:
	var result := []
	for item in memory_payload.get("recentMemoryEntries", []):
		if item is Dictionary:
			var content := String((item as Dictionary).get("content", "")).strip_edges()
			if content != "":
				result.append(content)
		else:
			var text := String(item).strip_edges()
			if text != "":
				result.append(text)
	return result


func retrieved_entry_texts(memory_payload: Dictionary) -> Array:
	var result := []
	for item in memory_payload.get("retrievedMemoryEntries", []):
		if item is Dictionary:
			var entry: Dictionary = item
			var content := String(entry.get("content", "")).strip_edges()
			if content == "":
				continue
			var source_label := retrieved_source_label(String(entry.get("source", "")))
			result.append("%s：%s" % [source_label, content] if source_label != "" else content)
		else:
			var text := String(item).strip_edges()
			if text != "":
				result.append(text)
	return result


func merge_retrieved_memory(session_results: Array, profile_results: Array, limit: int) -> Array:
	var result := []
	var seen := {}
	for source in [session_results, profile_results]:
		for item in source:
			if not (item is Dictionary):
				continue
			var entry: Dictionary = (item as Dictionary).duplicate(true)
			if _should_skip_retrieved_memory(entry):
				continue
			var content := String(entry.get("content", "")).strip_edges()
			if content == "" or seen.has(content):
				continue
			seen[content] = true
			result.append(entry)
			if result.size() >= limit:
				return result
	return result


func _should_skip_retrieved_memory(entry: Dictionary) -> bool:
	var metadata = entry.get("metadata", {})
	if metadata is Dictionary and String((metadata as Dictionary).get("kind", "")).strip_edges() == "visible_context":
		return true
	return false


func retrieved_source_label(source: String) -> String:
	match source:
		"recent":
			return "近期相关记忆"
		"round_summary":
			return "阶段相关摘要"
		"long_term":
			return "长期相关记忆"
		_:
			return ""


func trim_query_text(value: String, max_chars: int) -> String:
	var text := value.strip_edges()
	if text.length() <= max_chars:
		return text
	return text.substr(0, max_chars)
