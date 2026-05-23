extends SceneTree

const BuilderScript := preload("res://scripts/player/werewolf/ai/ai_werewolf_turn_context_builder.gd")
const RuntimeScript := preload("res://scripts/player/werewolf/ai/ai_werewolf_player_runtime.gd")
const PromptPolicyScript := preload("res://scripts/player/werewolf/ai/ai_werewolf_prompt_policy.gd")


func _initialize() -> void:
	var builder = BuilderScript.new()
	var runtime = RuntimeScript.new()
	var input := _input()
	var original_include_memory_hints := PromptPolicyScript.include_memory_hints
	PromptPolicyScript.include_memory_hints = true

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
	assert((payload["targetOptions"] as Array).all(func(value): return value is int))
	assert(payload.has("current_question"))
	assert(not payload.has("allowedActions"))
	assert(not payload.has("facts"))
	assert(not payload.has("privateInfo"))
	assert(not payload.has("memoryHints"))
	assert(not payload.has("outputFormat"))
	assert(payload.has("current_state"))
	assert(payload.has("players"))
	assert(payload.has("timeline"))
	assert(String(payload.get("current_state", "")).contains("第1夜晚上"))
	assert((payload["timeline"] as Array).any(func(line): return String(line) == "1号:我倾向今晚先刀3号位。"))
	assert((runtime.target_options_for_context(action_context) as Array).size() == 2)
	_check_role_visibility(builder, runtime)
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
	_check_timeline_compression(builder)

	var sheriff_input: Dictionary = input.duplicate(true)
	(sheriff_input["werewolf"] as Dictionary)["phase"] = "sheriff_speech"
	(sheriff_input["werewolf"] as Dictionary)["day"] = 1
	sheriff_input["phase_label"] = "警长竞选发言"
	((sheriff_input["players"] as Array)[1] as Dictionary)["role"] = "预言家"
	((sheriff_input["players"] as Array)[1] as Dictionary)["role_key"] = "seer"
	var seer_campaign_payload: Dictionary = runtime.to_model_payload(builder.speech_context(sheriff_input, 1, {}))
	var seer_state_text := String(seer_campaign_payload.get("current_state", ""))
	assert(not seer_campaign_payload.has("facts"))
	assert(seer_state_text.contains("首夜前"))
	assert(seer_state_text.contains("没有查验结果"))

	var normalized: Dictionary = builder.normalized_wolf_target_vote(input, 0, {
		"ok": true,
		"action": "wolf_kill",
		"target_index": 3,
	})
	assert(int(normalized.get("target_index", -1)) == 2)
	PromptPolicyScript.include_memory_hints = original_include_memory_hints
	quit()


func _check_role_visibility(builder, runtime) -> void:
	var input := _input()
	((input["players"] as Array)[1] as Dictionary)["alive"] = false
	var villager_payload: Dictionary = runtime.to_model_payload(builder.speech_context(input, 2, {}))
	var players: Array = villager_payload["players"]
	assert(String((players[1] as Dictionary).get("role", "")) == "未知")

	(input["werewolf"] as Dictionary)["phase"] = "post_game_summary"
	var post_game_payload: Dictionary = runtime.to_model_payload(builder.speech_context(input, 2, {}))
	var post_game_players: Array = post_game_payload["players"]
	assert(String((post_game_players[1] as Dictionary).get("role", "")) == "狼人")

	var reveal_input := _input()
	var idiot: Dictionary = (reveal_input["players"] as Array)[3]
	idiot["role"] = "白痴"
	idiot["role_key"] = "idiot"
	idiot["idiot_revealed"] = true
	idiot["idiot_reveal_source"] = "vote_exile"
	(reveal_input["players"] as Array)[3] = idiot
	var reveal_payload: Dictionary = runtime.to_model_payload(builder.speech_context(reveal_input, 2, {}))
	var reveal_players: Array = reveal_payload["players"]
	assert(String((reveal_players[3] as Dictionary).get("role", "")) == "白痴")

	var non_vote_reveal_input := _input()
	var non_vote_idiot: Dictionary = (non_vote_reveal_input["players"] as Array)[3]
	non_vote_idiot["role"] = "白痴"
	non_vote_idiot["role_key"] = "idiot"
	non_vote_idiot["idiot_revealed"] = true
	(non_vote_reveal_input["players"] as Array)[3] = non_vote_idiot
	var non_vote_payload: Dictionary = runtime.to_model_payload(builder.speech_context(non_vote_reveal_input, 2, {}))
	var non_vote_players: Array = non_vote_payload["players"]
	assert(String((non_vote_players[3] as Dictionary).get("role", "")) == "未知")

	non_vote_idiot["idiot_reveal_source"] = "hunter_shoot"
	(non_vote_reveal_input["players"] as Array)[3] = non_vote_idiot
	var wrong_source_payload: Dictionary = runtime.to_model_payload(builder.speech_context(non_vote_reveal_input, 2, {}))
	var wrong_source_players: Array = wrong_source_payload["players"]
	assert(String((wrong_source_players[3] as Dictionary).get("role", "")) == "未知")

	var viewer_visibility_input := _input()
	var visible_to_device_player: Dictionary = (viewer_visibility_input["players"] as Array)[1]
	visible_to_device_player["role_visible"] = true
	visible_to_device_player["roleVisible"] = true
	(viewer_visibility_input["players"] as Array)[1] = visible_to_device_player
	var viewer_visibility_payload: Dictionary = runtime.to_model_payload(builder.speech_context(viewer_visibility_input, 2, {}))
	var viewer_visibility_players: Array = viewer_visibility_payload["players"]
	assert(String((viewer_visibility_players[1] as Dictionary).get("role", "")) == "未知")

	var public_reveal_input := _input()
	var public_player: Dictionary = (public_reveal_input["players"] as Array)[1]
	public_player["public_role_visible"] = true
	(public_reveal_input["players"] as Array)[1] = public_player
	var public_reveal_payload: Dictionary = runtime.to_model_payload(builder.speech_context(public_reveal_input, 2, {}))
	var public_reveal_players: Array = public_reveal_payload["players"]
	assert(String((public_reveal_players[1] as Dictionary).get("role", "")) == "狼人")


func _check_timeline_compression(builder) -> void:
	var input := _input()
	input["timeline_compression"] = {
		"enabled": true,
		"model": "glm-5.1",
		"interval": 2,
		"prompt": "把以下时间线转化为事实，减短内容。",
	}
	var history: Array = input["history"]
	history.clear()
	for i in range(6):
		history.append({"speaker": "%d号 玩家%d" % [i + 1, i + 1], "speaker_index": i % 4, "text": "第%d条发言内容，保留事实。" % [i + 1], "at": float(i + 1)})
	input["wolf_private_history"] = []
	var state: Dictionary = builder.visible_state(input, 0, {"contextBudgetTokens": 4096})
	var timeline: Array = state["timeline"]
	assert(timeline.size() < 6)
	assert(String((timeline[0] as Dictionary).get("type", "")) == "timeline_summary")
	assert(String((timeline[0] as Dictionary).get("description", "")).contains("事实摘要"))
	assert(int(state.get("timelineCompressedCount", 0)) > 0)


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
