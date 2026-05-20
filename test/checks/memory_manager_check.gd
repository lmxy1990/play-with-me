extends SceneTree


func _initialize() -> void:
	var manager = load("res://scripts/core/memory/memory_manager.gd").new()
	manager.persistence_enabled = false
	manager.load_or_create()

	var scope: Dictionary = manager.scope("bot_1", "werewolf", "bot_1", "basic_village", "room_1")
	assert(manager.scope_key(scope) == "bot_1|werewolf|basic_village|room_1|bot_1")

	manager.append(scope, {
		"content": "第1天，当前阶段：狼人行动。",
		"visibility": "private",
		"metadata": {"kind": "visible_context"},
	})
	manager.append(scope, {
		"content": "botDecision=1号位执行刀人，目标2号位。",
		"visibility": "private",
		"metadata": {"kind": "bot_decision"},
	})
	manager.append(scope, {
		"content": "预言家查验3号位是狼人，白天需要围绕这个查验发言。",
		"visibility": "private",
		"metadata": {"kind": "seer_check"},
	})
	manager.append(scope, {
		"content": "女巫昨夜救治2号位，暂时保留毒药。",
		"visibility": "private",
		"metadata": {"kind": "witch_action"},
	})
	var prompt: Dictionary = manager.prompt_context(scope, 8, 4)
	assert((prompt["recentMemoryEntries"] as Array).size() == 4)

	var retrieved_recent: Array = manager.retrieve(scope, "查验 狼人 发言", 2, false)
	assert(retrieved_recent.size() >= 1)
	assert(String((retrieved_recent[0] as Dictionary).get("content", "")).contains("查验3号位"))
	assert(String((retrieved_recent[0] as Dictionary).get("source", "")) == "recent")
	var recent_report: Dictionary = manager.get_last_retrieval_report()
	assert(String(recent_report.get("retrieval_mode", "")) == "text_retrieval")
	assert(not bool(recent_report.get("vector_enabled", true)))
	assert(recent_report.has("query_plan"))
	assert(recent_report.has("candidate_pool_report"))
	assert(recent_report.has("rerank_report"))
	assert(recent_report.has("fusion_report"))

	var summary: Dictionary = manager.compact(scope, {
		"day_number": 1,
		"phase": "wolf_action",
		"public_summary": "公开事件。",
		"private_summary": "私密事件。",
		"decision_summary": "行动记录。",
		"suspicion_summary": "暂不形成强怀疑。",
		"strategy_summary": "继续只根据可见信息行动。",
	})
	assert(String(summary["phase"]) == "wolf_action")
	var compacted: Dictionary = manager.prompt_context(scope, 8, 4)
	assert((compacted["recentMemoryEntries"] as Array).is_empty())
	assert((compacted["roundSummaries"] as Array).size() == 1)
	var empty_new_context: Dictionary = manager.get_memory_context({
		"bot_id": "bot_1",
		"scope": scope,
		"query": "行动记录 强怀疑",
	})
	var empty_new_memory_context: Dictionary = (empty_new_context.get("data", {}) as Dictionary).get("memory_context", {}) as Dictionary
	assert((empty_new_memory_context.get("reflection_context", []) as Array).is_empty())
	var retrieved_summary: Array = manager.retrieve(scope, "行动记录 强怀疑", 2, false)
	assert(retrieved_summary.size() >= 1)
	assert(String((retrieved_summary[0] as Dictionary).get("source", "")) == "round_summary")

	var profile_scope: Dictionary = manager.scope("bot_1", "werewolf", "bot_1", "basic_village")
	manager.save_long_term(profile_scope, "这名 AI 下局优先观察票型。", true)
	var profile_prompt: Dictionary = manager.prompt_context(profile_scope)
	assert(String(profile_prompt["longTermMemorySummary"]).contains("票型"))
	var retrieved_long_term: Array = manager.retrieve(profile_scope, "下局 票型", 2, true)
	assert(retrieved_long_term.size() == 1)
	assert(String((retrieved_long_term[0] as Dictionary).get("source", "")) == "long_term")
	var long_term_report: Dictionary = manager.get_last_retrieval_report()
	assert(int((long_term_report.get("candidate_counts", {}) as Dictionary).get("selected", 0)) == 1)
	assert(manager.list_scopes("bot_1", "werewolf", "bot_1").size() == 2)

	var init_result: Dictionary = manager.init_memory({
		"bot_id": "bot_1",
		"scope": scope,
		"persona_template": {"content": "谨慎、重视证据链，不提前使用不可见信息。"},
		"initial_relationship_targets": [
			{"target_id": "player_3", "target_type": "player", "content": "对3号位保持观察。"},
		],
		"reason": "test_seed",
	})
	assert(bool(init_result.get("ok", false)))
	var update_result: Dictionary = manager.update_memory({
		"bot_id": "bot_1",
		"scope": scope,
		"update_reason": "confirmed_event",
		"memory_update": {
			"visibility": "self_private",
			"working_update": {
				"current_goal": "白天验证3号位查验和发言矛盾。",
			},
			"episodic_events": [
				{"content": "3号位发言前后矛盾，需要复核查验和票型。", "importance": 0.72, "confidence": 0.82},
			],
			"relationship_updates": [
				{"target_id": "player_3", "target_type": "player", "content": "对3号位保持高警惕。", "importance": 0.76, "confidence": 0.80},
			],
			"semantic_candidates": [
				{"content": "遇到查验和发言冲突时，优先复核证据链。", "importance": 0.85, "confidence": 0.82, "status": "active"},
			],
			"reflection_candidates": [
				{"content": "过早定性会降低后续判断质量。", "importance": 0.74, "confidence": 0.72, "status": "active"},
			],
			"evidence": [
				{"id": "event_3", "content": "3号发言前后矛盾。"},
			],
		},
	})
	assert(bool(update_result.get("ok", false)))
	var update_report: Dictionary = manager.get_last_update_report()
	assert(("working" in (update_report.get("updated_layers", []) as Array)))
	assert(("episodic" in (update_report.get("updated_layers", []) as Array)))
	assert(("relationship" in (update_report.get("updated_layers", []) as Array)))
	var context_result: Dictionary = manager.get_memory_context({
		"bot_id": "bot_1",
		"scope": scope,
		"query": "3号 查验 发言 证据链",
		"target_entity_ids": ["player_3"],
		"visible_entity_ids": ["player_3"],
		"memory_options": {"final_max_items": 10, "max_token_budget": 2048},
	})
	assert(bool(context_result.get("ok", false)))
	var memory_context: Dictionary = (context_result.get("data", {}) as Dictionary).get("memory_context", {}) as Dictionary
	assert(not _empty_dict(memory_context.get("persona_snapshot", null)))
	assert((memory_context.get("working_memory", []) as Array).size() >= 1)
	assert((memory_context.get("relationship_context", []) as Array).size() >= 1)
	assert((memory_context.get("semantic_context", []) as Array).size() >= 1)
	assert((memory_context.get("episodic_context", []) as Array).size() >= 1)
	var context_report: Dictionary = ((context_result.get("data", {}) as Dictionary).get("retrieval_report", {}) as Dictionary)
	assert(context_report.has("source_fetch_report"))
	assert(String(context_report.get("retrieval_mode", "")) == "hybrid_vector")
	assert(bool(context_report.get("vector_enabled", false)))
	assert(int((context_report.get("budget_report", {}) as Dictionary).get("estimated_used", 0)) > 0)
	var overview_result: Dictionary = manager.get_memory_overview({
		"bot_id": "bot_1",
		"scope": scope,
		"include_recent_samples": true,
	})
	assert(bool(overview_result.get("ok", false)))
	var overview_data: Dictionary = overview_result.get("data", {}) as Dictionary
	var layer_counts: Dictionary = overview_data.get("layer_counts", {}) as Dictionary
	assert(int(layer_counts.get("profile", 0)) == 1)
	assert(int(layer_counts.get("working", 0)) == 1)
	assert(int(layer_counts.get("relationship", 0)) >= 2)
	assert(int(layer_counts.get("semantic", 0)) == 1)
	assert(int(layer_counts.get("episodic", 0)) == 1)
	assert(int(layer_counts.get("reflection", 0)) == 1)
	var overview_index: Dictionary = overview_data.get("index_status", {}) as Dictionary
	assert(String(overview_index.get("retrieval_mode", "")) == "hybrid_vector")
	assert(bool(overview_index.get("vector_enabled", false)))
	assert(int(overview_index.get("pending_embedding_count", -1)) == 0)
	assert(int(overview_index.get("ready_embedding_count", 0)) >= 2)
	var overview_persona: Dictionary = overview_data.get("persona_snapshot", {}) as Dictionary
	assert(String(overview_persona.get("content", "")) == "[private]")
	assert((overview_data.get("recent_samples", []) as Array).size() > 0)

	var episodic_redacted_result: Dictionary = manager.list_memory_records({
		"bot_id": "bot_1",
		"scope": scope,
		"memory_type": "episodic",
		"status": "active",
		"limit": 10,
	})
	assert(bool(episodic_redacted_result.get("ok", false)))
	var episodic_redacted_data: Dictionary = episodic_redacted_result.get("data", {}) as Dictionary
	assert(int(episodic_redacted_data.get("total", 0)) == 1)
	var episodic_redacted_items: Array = episodic_redacted_data.get("items", []) as Array
	assert(String((episodic_redacted_items[0] as Dictionary).get("content", "")) == "[private]")
	var episodic_plain_result: Dictionary = manager.list_memory_records({
		"bot_id": "bot_1",
		"scope": scope,
		"memory_type": "episodic",
		"status": "active",
		"redact_private": false,
	})
	var episodic_plain_items: Array = ((episodic_plain_result.get("data", {}) as Dictionary).get("items", []) as Array)
	assert(String((episodic_plain_items[0] as Dictionary).get("content", "")).contains("3号位发言"))
	var relationship_list_result: Dictionary = manager.list_memory_records({
		"bot_id": "bot_1",
		"scope": scope,
		"memory_type": "relationship",
		"subject_id": "player_3",
	})
	assert(int(((relationship_list_result.get("data", {}) as Dictionary).get("total", 0))) >= 2)
	var active_list_result: Dictionary = manager.list_memory_records({
		"bot_id": "bot_1",
		"scope": scope,
		"status": "active",
	})
	assert(int(((active_list_result.get("data", {}) as Dictionary).get("total", 0))) >= 5)
	var query_list_result: Dictionary = manager.list_memory_records({
		"bot_id": "bot_1",
		"scope": scope,
		"query": "证据链",
		"redact_private": false,
	})
	assert(int(((query_list_result.get("data", {}) as Dictionary).get("total", 0))) >= 1)

	var reports_result: Dictionary = manager.get_memory_reports({
		"bot_id": "bot_1",
		"scope": scope,
		"report_types": ["context_build", "memory_update", "index"],
	})
	assert(bool(reports_result.get("ok", false)))
	var reports_data: Dictionary = reports_result.get("data", {}) as Dictionary
	assert((reports_data.get("reports", []) as Array).size() == 3)
	var latest_reports: Dictionary = reports_data.get("latest", {}) as Dictionary
	var index_report: Dictionary = latest_reports.get("index", {}) as Dictionary
	assert(String(index_report.get("retrieval_mode", "")) == "hybrid_vector")
	assert(bool(index_report.get("vector_enabled", false)))

	manager.append(scope, {
		"content": "direct_entry_4319 should stay outside structured memory APIs.",
		"visibility": "private",
		"metadata": {"kind": "direct_entry"},
	})
	var direct_list_result: Dictionary = manager.list_memory_records({
		"bot_id": "bot_1",
		"scope": scope,
		"query": "direct_entry_4319",
		"redact_private": false,
	})
	assert(int(((direct_list_result.get("data", {}) as Dictionary).get("total", 0))) == 0)
	var direct_context_result: Dictionary = manager.get_memory_context({
		"bot_id": "bot_1",
		"scope": scope,
		"query": "direct_entry_4319",
		"memory_options": {"final_max_items": 10, "max_token_budget": 2048},
	})
	var direct_items: Array = ((direct_context_result.get("data", {}) as Dictionary).get("items", []) as Array)
	for item in direct_items:
		assert(not String((item as Dictionary).get("content", "")).contains("direct_entry_4319"))
	var direct_context_report: Dictionary = (direct_context_result.get("data", {}) as Dictionary).get("retrieval_report", {}) as Dictionary
	assert(int((direct_context_report.get("source_fetch_report", {}) as Dictionary).get("structured_count", 0)) >= 1)

	var maintenance_result: Dictionary = manager.maintain_memory({
		"bot_id": "bot_1",
		"scope": scope,
		"maintenance_type": "manual",
		"options": {
			"enable_distillation": true,
			"enable_merge": true,
			"enable_forgetting": true,
		},
	})
	assert(bool(maintenance_result.get("ok", false)))
	var maintenance_report: Dictionary = (maintenance_result.get("data", {}) as Dictionary).get("maintenance_report", {}) as Dictionary
	assert(int(maintenance_report.get("distilled_count", 0)) >= 1)
	assert(bool((maintenance_report.get("index_status", {}) as Dictionary).get("vector_enabled", false)))

	var clear_result: Dictionary = manager.clear_working_memory({"scope": scope})
	assert(bool(clear_result.get("ok", false)))
	var cleared_context: Dictionary = manager.get_memory_context({
		"bot_id": "bot_1",
		"scope": scope,
		"query": "3号 查验 发言 证据链",
		"target_entity_ids": ["player_3"],
		"visible_entity_ids": ["player_3"],
	})
	var cleared_memory_context: Dictionary = (cleared_context.get("data", {}) as Dictionary).get("memory_context", {}) as Dictionary
	assert((cleared_memory_context.get("working_memory", []) as Array).is_empty())

	manager.delete_scope(scope)
	assert(manager.list_scopes("bot_1", "werewolf", "bot_1").size() == 1)
	quit()


func _empty_dict(value) -> bool:
	return not (value is Dictionary) or (value as Dictionary).is_empty()
