extends SceneTree

const PromptPolicyScript := preload("res://scripts/player/werewolf/ai/ai_werewolf_prompt_policy.gd")


func _initialize() -> void:
	var original_include_memory_hints := PromptPolicyScript.include_memory_hints
	PromptPolicyScript.include_memory_hints = true
	var memory_context = load("res://scripts/player/werewolf/ai/ai_werewolf_memory_context.gd").new()
	var manager = load("res://scripts/core/memory/memory_manager.gd").new()
	var builder = load("res://scripts/player/werewolf/ai/ai_werewolf_memory.gd").new()
	manager.persistence_enabled = false
	manager.load_or_create()

	var session_scope: Dictionary = manager.scope("bot_2", "werewolf", "bot_2", "basic_village", "room_context_check")
	var profile_scope: Dictionary = manager.scope("bot_2", "werewolf", "bot_2", "basic_village")
	manager.append(session_scope, {
		"content": "预言家查验3号位是狼人，白天需要围绕这个查验发言。",
		"visibility": "private",
		"metadata": {"kind": "seer_check"},
	})
	manager.append(session_scope, {
		"content": "女巫昨夜救治2号位，暂时保留毒药。",
		"visibility": "private",
		"metadata": {"kind": "witch_action"},
	})
	manager.save_long_term(profile_scope, "下局遇到强跳预言家时，优先关注查验、发言矛盾和票型。", true)

	var query: String = memory_context.retrieval_query(
		{"day": 1, "current_action": {"key": "vote", "label": "投票"}},
		"2号 阿辰",
		"预言家",
		"白天讨论",
		{"checks": {"3号": "wolf"}},
		[
			{"type": "player_spoke", "description": "3号发言前后矛盾。"},
			{"type": "vote_cast", "description": "有人准备投3号。"},
		]
	)
	assert(query.contains("2号 阿辰"))
	assert(query.contains("vote"))
	assert(query.contains("3号发言"))

	var payload: Dictionary = memory_context.build_prompt(manager, builder, session_scope, profile_scope, "记录推理风格。", query)
	assert(String(payload.get("configSummary", "")).contains("推理风格"))
	assert(String(payload.get("longTermMemorySummary", "")).contains("票型"))
	assert(memory_context.recent_entry_texts(payload).size() == 2)
	var retrieved: Array = payload.get("retrievedMemoryEntries", [])
	assert(retrieved.size() >= 1)
	assert(String((retrieved[0] as Dictionary).get("content", "")).contains("查验3号位"))
	var retrieved_texts: Array = memory_context.retrieved_entry_texts(payload)
	assert(retrieved_texts.size() >= 1)
	assert(String(retrieved_texts[0]).contains("相关记忆"))

	var low_budget_payload: Dictionary = memory_context.build_prompt(manager, builder, session_scope, profile_scope, "记录推理风格。", query, 1024)
	var limits: Dictionary = low_budget_payload.get("contextLimits", {})
	assert(int(low_budget_payload.get("contextBudgetTokens", 0)) == 1024)
	assert(int(limits.get("sessionEntryLimit", 0)) == 3)
	assert(int(limits.get("mergedRetrievalLimit", 0)) == 3)
	assert(int(limits.get("queryCharLimit", 0)) == 600)
	PromptPolicyScript.include_memory_hints = original_include_memory_hints
	quit()
