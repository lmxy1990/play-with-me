extends SceneTree

const BuilderScript := preload("res://scripts/room/werewolf/player/ai_robot/ai_werewolf_turn_context_builder.gd")
const RuntimeScript := preload("res://scripts/room/werewolf/player/ai_robot/ai_werewolf_player_runtime.gd")


func _initialize() -> void:
	var builder = BuilderScript.new()
	var runtime = RuntimeScript.new()
	var input := _input()
	var original_include_memory_hints := AiWerewolfPromptPolicy.include_memory_hints
	AiWerewolfPromptPolicy.include_memory_hints = true

	var wolf_state: Dictionary = builder.visible_state(input, 0, {})
	var wolf_timeline: Array = wolf_state["timeline"]
	assert(String((wolf_timeline.back() as Dictionary).get("type", "")) == "wolf_spoke")

	var villager_state: Dictionary = builder.visible_state(input, 2, {})
	for event in villager_state["timeline"]:
		assert(String((event as Dictionary).get("type", "")) != "wolf_spoke")

	var action_context: Dictionary = builder.action_context(input, 0, "wolf_kill", {})
	var payload: Dictionary = runtime.to_model_payload(action_context)
	var payload_text := JSON.stringify(payload)
	assert(not payload_text.contains("sourceText"))
	assert(not payload_text.contains("visiblePriorEvents"))
	assert(not payload_text.contains("recentMemoryEntries"))
	assert(payload.has("targetOptions"))
	assert((payload["targetOptions"] as Array).size() == 2)
	assert(payload.has("current_question"))
	assert(payload.has("memoryHints"))
	assert(not payload.has("outputFormat"))
	assert(payload.has("current_state"))
	assert(payload.has("players"))
	assert(payload.has("timeline"))
	assert(String(payload.get("current_state", "")) == "第1夜晚上")
	assert((payload["timeline"] as Array).any(func(line): return String(line) == "1号:我倾向今晚先刀3号位。"))
	assert((runtime.target_options_for_context(action_context) as Array).size() == 2)
	var capped_hints: Dictionary = builder.memory_hints({
		"memoryContextBudgetTokens": 64,
		"retrievedMemoryEntries": [
			{"content": _long_text("相关记忆", 20), "source": "recent"},
		],
		"roundSummaries": [
			{"publicSummary": _long_text("阶段摘要", 20)},
		],
		"longTermMemorySummary": _long_text("长期记忆", 20),
	})
	var relevant_memory: Array = capped_hints.get("relevantMemory", [])
	assert(relevant_memory.size() == 1)
	assert(String(relevant_memory[0]).length() <= 64)
	assert(not capped_hints.has("roundSummaries"))
	assert(not capped_hints.has("longTermSummary"))
	var script_context: Dictionary = builder.script_prompt_context(input)
	assert(String(script_context.get("winCondition", "")).contains("所有好人全部出局"))
	assert(builder.target_from_decision(runtime, "{\"action\":\"wolf_kill\",\"targetSeatNumber\":3}", input, 0, "wolf_kill") == 2)
	assert(builder.target_from_decision(runtime, "{\"action\":\"wolf_kill\",\"targetSeatNumber\":2}", input, 0, "wolf_kill") == -1)

	var normalized: Dictionary = builder.normalized_wolf_target_vote(input, 0, {
		"ok": true,
		"action": "wolf_kill",
		"target_index": 3,
	})
	assert(int(normalized.get("target_index", -1)) == 2)
	AiWerewolfPromptPolicy.include_memory_hints = original_include_memory_hints
	quit()


func _input() -> Dictionary:
	return {
		"room_id": "room_check",
		"werewolf": {
			"phase": "wolf_action",
			"day": 1,
			"map_name": "标准村庄",
			"has_sheriff": false,
			"votes": {},
			"night": {},
			"current_action": {"key": "wolf_kill", "actor_index": 0, "label": "刀人"},
			"last_guarded_index": -1,
			"post_game": {"stage": ""},
		},
		"players": [
			_player("wolf_a", "甲", "wolf"),
			_player("wolf_b", "乙", "wolf"),
			_player("villager_c", "丙", "villager"),
			_player("villager_d", "丁", "villager"),
		],
		"history": [
			{"speaker": "主持人", "text": "第1夜开始。", "at": 1.0},
		],
		"wolf_private_history": [
			{
				"speaker": "1号 甲",
				"text": "我倾向今晚先刀3号位。",
				"actor_index": 0,
				"actor_id": "wolf_a",
				"day": 1,
				"phase": "wolf_action",
				"at": 2.0,
			},
		],
		"wolf_target_votes": {},
		"wolf_speech_count": 1,
		"max_wolf_night_chat_messages": 3,
		"phase_label": "狼人行动",
		"map_rule_text": "4人检查局规则。",
	}


func _long_text(text: String, count: int) -> String:
	var parts := []
	for i in range(count):
		parts.append(text)
	return "".join(parts)


func _player(id: String, name: String, role_key: String) -> Dictionary:
	var role_names := {
		"wolf": "狼人",
		"villager": "村民",
	}
	return {
		"id": id,
		"name": name,
		"role": String(role_names.get(role_key, role_key)),
		"role_key": role_key,
		"avatar": "",
		"state": "等待",
		"motion": 0,
		"alive": true,
		"ready": true,
		"owner": "bot",
	}
