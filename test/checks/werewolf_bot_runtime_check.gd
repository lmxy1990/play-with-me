extends SceneTree


func _initialize() -> void:
	var state = load("res://scripts/core/app_state.gd").new()
	state.persistence_enabled = false
	state.load_or_create()
	var page = load("res://scenes/werewolf_room.tscn").instantiate()
	page.set_app_state(state)
	root.add_child(page)
	await process_frame

	_seed_players(page)
	_check_device_task_frame_does_not_clear_hidden_roles(page)
	_check_payload_is_sanitized(page)
	_check_long_speech_outputs_are_accepted(page)
	_check_guard_target_options(page)
	_check_sheriff_vote_self_target(page)
	_check_sheriff_speech_order_context(page)
	_check_sheriff_badge_context(page)
	_check_mvp_roles_and_decision(page)
	_check_witch_skip_and_save(page)
	_check_witch_poison_targets_exclude_save_target(page)
	_check_hunter_shoot_schema_and_parser(page)
	_check_wolf_action_records_private_vote(page)
	_check_reasoning_output_warning_continues_game(page)
	_check_illegal_target_repair_continues_game(page)
	_check_action_parse_failure_halts_game(page)

	page.queue_free()
	await process_frame
	quit()


func _seed_players(page) -> void:
	page._players = [
		_player("player_1", "张安", "guard", true),
		_player("player_2", "李宁", "wolf", true),
		_player("player_3", "周舟", "villager", false),
	]
	page._history = [
		{"speaker": "主持人", "text": "系统询问女巫：昨夜有人倒牌。", "at": 1},
		{"speaker": "1号 张安", "text": "遗言：我先听2号位。", "at": 2},
	]
	page._werewolf = {
		"phase": "vote",
		"day": 2,
		"map_name": "警长守卫广场",
		"has_sheriff": true,
		"votes": {},
		"night": {},
		"current_action": {"key": "vote", "actor_index": 0, "label": "投票"},
		"last_guarded_index": -1,
		"post_game": {"stage": ""},
	}


func _check_payload_is_sanitized(page) -> void:
	var original_include_memory_hints := AiWerewolfPromptPolicy.include_memory_hints
	AiWerewolfPromptPolicy.include_memory_hints = true
	var context: Dictionary = page._bot_action_context(0, "vote", {
		"retrievedMemoryEntries": [
			{"content": "player_2 上局悍跳后被票型抓住。", "source": "long_term", "score": 0.8},
		],
	})
	var payload: Dictionary = page._bot_runtime.to_model_payload(context)
	var encoded := JSON.stringify(payload)
	assert(not encoded.contains("player_1"))
	assert(not encoded.contains("player_2"))
	assert(encoded.contains("2号位"))
	assert(payload.has("current_question"))
	assert(payload.has("allowedActions"))
	assert(payload.has("memoryHints"))
	assert(not payload.has("outputFormat"))
	assert(payload.has("current_state"))
	assert(payload.has("players"))
	assert(payload.has("timeline"))
	assert(not payload.has("visibleState"))
	assert(payload.has("targetOptions"))
	assert(String(payload.get("current_state", "")) == "第2天白天")
	var timeline: Array = payload["timeline"]
	assert(String(timeline[0]).begins_with("主持人:"))
	assert(String(timeline[1]) == "1号:我先听2号位。")
	assert(payload["memoryHints"] is Dictionary)
	var memory_hints: Dictionary = payload["memoryHints"]
	assert((memory_hints["relevantMemory"] as Array).size() == 1)
	assert(String((memory_hints["relevantMemory"] as Array)[0]).contains("2号位 李宁"))
	var players: Array = payload["players"]
	assert(String((players[0] as Dictionary).get("role", "")) == "守卫")
	assert(String((players[1] as Dictionary).get("role", "")) == "未知")
	assert(String((players[2] as Dictionary).get("role", "")) == "村民")
	var targets: Array = page._bot_runtime.target_options_for_context(context)
	assert(targets.size() == 1)
	assert(int((targets[0] as Dictionary).get("targetSeatNumber", -1)) == 2)
	assert((payload["targetOptions"] as Array).size() == targets.size())
	var messages: Array = page._bot_runtime.build_messages(context)
	var system_content := String((messages[0] as Dictionary).get("content", ""))
	assert(system_content.contains("[游戏规则]"))
	assert(system_content.contains("[当前状态]"))
	assert(system_content.contains("[游戏上下文]"))
	assert(system_content.contains("[原则]"))
	assert(system_content.contains("targetOptions"))
	assert(system_content.contains("players"))
	assert(system_content.contains("[输出格式]"))
	assert(system_content.contains("只返回一个 JSON 对象"))
	assert(system_content.contains("JSON 只能包含 action 和 targetSeatNumber 两个字段"))
	assert(not system_content.contains("建议发言控制在120字以内"))
	assert(not system_content.contains("只输出 JSON"))
	assert(not system_content.contains("confidence"))
	assert(not system_content.contains("只包含 current_question"))
	assert(not system_content.contains("你觉得prompt"))
	var user_content := String((messages[1] as Dictionary).get("content", ""))
	assert(user_content == String(payload.get("current_question", "")))
	assert(not user_content.begins_with("{"))
	assert(not user_content.contains("player_2"))
	var response_schema: Dictionary = page._bot_runtime.response_schema_for_context(context)
	assert(not response_schema.is_empty())
	assert(String(response_schema.get("name", "")) == "werewolf_vote_v1")
	assert(bool(response_schema.get("strict", false)))
	var schema_body: Dictionary = response_schema["schema"] as Dictionary
	assert(not JSON.stringify(schema_body).contains("confidence"))
	assert((schema_body["required"] as Array).has("targetSeatNumber"))
	var properties: Dictionary = schema_body["properties"] as Dictionary
	var target_schema: Dictionary = properties["targetSeatNumber"] as Dictionary
	assert((target_schema["enum"] as Array).size() == 1)
	assert(int((target_schema["enum"] as Array)[0]) == 2)
	var speech_schema: Dictionary = page._bot_runtime.response_schema_for_context({"allowed_actions": ["speak"]})
	assert(speech_schema.is_empty())
	var speech_request_options: Dictionary = page._bot_runtime.request_options_for_context({"allowed_actions": ["speak"]})
	assert(String(speech_request_options.get("output_type", "")) == "text")
	assert(String(speech_request_options.get("output_adapter", "")) == "none")
	assert(not speech_request_options.has("response_schema"))
	var wolf_chat_request_options: Dictionary = page._bot_runtime.request_options_for_context({"allowed_actions": ["wolf_chat"]})
	assert(String(wolf_chat_request_options.get("output_type", "")) == "text")
	assert(String(wolf_chat_request_options.get("output_adapter", "")) == "none")
	assert(not wolf_chat_request_options.has("response_schema"))
	_check_kimi_robot_model_request_payload(page, context, messages, response_schema)
	_check_glm_robot_model_request_payload(page, context, messages, response_schema)
	AiWerewolfPromptPolicy.include_memory_hints = original_include_memory_hints


func _check_device_task_frame_does_not_clear_hidden_roles(page) -> void:
	page._merge_device_task_frame_players([
		{
			"displayName": "张安",
			"alive": true,
			"state": "等待",
			"owner": "bot",
			"roleVisible": true,
			"role": "守卫",
			"roleKey": "guard",
		},
		{
			"displayName": "李宁",
			"alive": true,
			"state": "等待",
			"owner": "bot",
			"roleVisible": false,
			"role": "未知",
			"roleKey": "",
		},
		{
			"displayName": "周舟",
			"alive": false,
			"state": "死亡",
			"owner": "bot",
			"roleVisible": false,
			"role": "未知",
			"roleKey": "",
		},
	])
	assert(String(page._players[0].get("role_key", "")) == "guard")
	assert(String(page._players[1].get("role_key", "")) == "wolf")
	assert(String(page._players[1].get("role", "")) == "狼人")
	assert(String(page._players[1].get("device_task_role", "")) == "未知")
	assert(not bool(page._players[1].get("device_task_role_visible", true)))
	assert(String(page._players[2].get("role_key", "")) == "villager")


func _check_kimi_robot_model_request_payload(page, context: Dictionary, action_messages: Array, response_schema: Dictionary) -> void:
	var client = load("res://scripts/core/model/model_chat_client.gd").new()
	var request_options: Dictionary = page._bot_runtime.request_options_for_context(context)
	assert(not request_options.is_empty())
	var profile := {
		"provider": "openai_api",
		"endpoint": "https://ark.cn-beijing.volces.com/api/plan/v3",
		"model": "kimi-k2.6",
		"api_key": "sk-test",
		"formt_adapter": "openai_json_object",
		"reasoning": true,
		"max_output": 4096,
	}
	var action_request: Dictionary = page._model_completion_request(profile, action_messages, 0.45, 0, 30.0, request_options, "werewolf.action.vote")
	var action_debug: Dictionary = client.build_request_debug_payload(action_request)
	var action_payload: Dictionary = action_debug["payload"] as Dictionary
	assert(String(action_debug.get("output_type", "")) == "json")
	assert(String(action_debug.get("payload_schema", "")) == "response_format")
	assert(int(action_debug.get("output_tokens", -1)) == 0)
	assert(String((action_payload["response_format"] as Dictionary).get("type", "")) == "json_object")
	assert(not (action_payload["response_format"] as Dictionary).has("json_schema"))
	assert(not action_payload.has("max_tokens"))
	assert(not action_payload.has("reasoning_effort"))
	assert(String(((action_payload["messages"] as Array)[0] as Dictionary).get("content", "")).contains("[Kimi JSON Mode]"))
	assert(String(((action_payload["messages"] as Array)[0] as Dictionary).get("content", "")).contains("targetSeatNumber"))
	assert(JSON.stringify(action_debug.get("response_schema", {})) == JSON.stringify(response_schema))

	var speech_context: Dictionary = page._bot_speech_context(0, {})
	var speech_messages: Array = page._bot_runtime.build_messages(speech_context)
	var speech_system := String((speech_messages[0] as Dictionary).get("content", ""))
	assert(speech_system.contains("直接输出发言文本"))
	var speech_request_options: Dictionary = page._bot_runtime.request_options_for_context(speech_context)
	assert(String(speech_request_options.get("output_type", "")) == "text")
	assert(String(speech_request_options.get("output_adapter", "")) == "none")
	var speech_profile: Dictionary = profile.duplicate(true)
	speech_profile["formt_adapter"] = "none"
	speech_profile["reasoning"] = false
	var speech_request: Dictionary = page._model_completion_request(speech_profile, speech_messages, 0.72, 0, 30.0, speech_request_options, "werewolf.speech")
	var speech_debug: Dictionary = client.build_request_debug_payload(speech_request)
	var speech_payload: Dictionary = speech_debug["payload"] as Dictionary
	assert(String(speech_debug.get("output_type", "")) == "text")
	assert(String(speech_debug.get("output_adapter", "")) == "none")
	assert(String(speech_debug.get("payload_schema", "")) == "empty")
	assert(int(speech_debug.get("output_tokens", 0)) == 4096)
	assert(int(speech_payload.get("max_tokens", 0)) == 4096)
	assert(not speech_payload.has("response_format"))
	assert(not speech_payload.has("reasoning_effort"))
	assert(String((speech_payload.get("thinking", {}) as Dictionary).get("type", "")) == "disabled")
	assert(not String(((speech_payload["messages"] as Array)[0] as Dictionary).get("content", "")).contains("[Kimi JSON Mode]"))


func _check_glm_robot_model_request_payload(page, context: Dictionary, action_messages: Array, response_schema: Dictionary) -> void:
	var client = load("res://scripts/core/model/model_chat_client.gd").new()
	var request_options: Dictionary = page._bot_runtime.request_options_for_context(context)
	var profile := {
		"provider": "openai_api",
		"endpoint": "https://ark.cn-beijing.volces.com/api/plan/v3",
		"model": "glm-5.1",
		"api_key": "sk-test",
		"formt_adapter": "openai_tool_forced",
		"reasoning": true,
		"max_output": 4096,
	}
	var action_request: Dictionary = page._model_completion_request(profile, action_messages, 0.45, 0, 30.0, request_options, "werewolf.action.vote")
	var action_debug: Dictionary = client.build_request_debug_payload(action_request)
	var action_payload: Dictionary = action_debug["payload"] as Dictionary
	assert(String(action_debug.get("output_type", "")) == "json")
	assert(String(action_debug.get("payload_schema", "")) == "tools.tool_choice")
	assert(int(action_debug.get("output_tokens", -1)) == 0)
	assert(not action_payload.has("max_tokens"))
	assert(not action_payload.has("response_format"))
	assert((action_payload["tools"] as Array).size() == 1)
	assert(String((action_payload["tool_choice"] as Dictionary).get("type", "")) == "function")
	assert(bool(action_payload.get("parallel_tool_calls", true)) == false)
	assert(not action_payload.has("reasoning_effort"))
	assert(not String(((action_payload["messages"] as Array)[0] as Dictionary).get("content", "")).contains("[GLM JSON Mode]"))
	assert(JSON.stringify(action_debug.get("response_schema", {})) == JSON.stringify(response_schema))


func _check_long_speech_outputs_are_accepted(page) -> void:
	var long_speech := _repeat_text("我认为现在不能只看单点站边，要结合夜间结果、警徽流和每个人前后发言的一致性来判断。", 4)
	var speech_decision: Dictionary = page._bot_runtime.parse_decision(long_speech, {
		"allowed_actions": ["speak"],
	})
	assert(bool(speech_decision.get("ok", false)))
	assert(String(speech_decision.get("speech_text", "")) == long_speech)

	var long_wolf_chat := _repeat_text("我建议先统一目标，优先处理能带队盘逻辑的位置，同时保留一名低信息位白天抗推。", 4)
	var wolf_decision: Dictionary = page._bot_runtime.parse_decision(long_wolf_chat, {
		"allowed_actions": ["wolf_chat"],
	})
	assert(bool(wolf_decision.get("ok", false)))
	assert(String(wolf_decision.get("speech_text", "")) == long_wolf_chat)


func _check_guard_target_options(page) -> void:
	page._werewolf["phase"] = "guard_action"
	page._werewolf["last_guarded_index"] = 1
	page._werewolf["current_action"] = {"key": "guard_protect", "actor_index": 0, "label": "守护"}
	var context: Dictionary = page._bot_action_context(0, "guard_protect", {})
	var payload: Dictionary = page._bot_runtime.to_model_payload(context)
	assert(payload.has("targetOptions"))
	assert(String(payload.get("current_question", "")) == "选择今晚守护目标。")
	assert(String(JSON.stringify(payload.get("privateInfo", {}))).contains("lastGuardedPlayer"))
	var targets: Array = page._bot_runtime.target_options_for_context(context)
	assert(targets.size() == 1)
	assert(int((targets[0] as Dictionary).get("targetSeatNumber", -1)) == 1)
	assert((payload["targetOptions"] as Array).size() == targets.size())
	var decision: Dictionary = page._bot_runtime.parse_decision("{\"action\":\"guard_protect\",\"targetSeatNumber\":1}", context)
	assert(bool(decision.get("ok", false)))
	assert(String(decision.get("action", "")) == "guard_protect")
	assert(int(decision.get("target_index", -1)) == 0)
	var fenced_decision: Dictionary = page._bot_runtime.parse_decision("```json\n{\"action\":\"guard_protect\",\"targetSeatNumber\":1}\n```", context)
	assert(bool(fenced_decision.get("ok", false)))
	assert(int(fenced_decision.get("target_index", -1)) == 0)
	var stale_target: Dictionary = page._bot_runtime.parse_decision("{\"action\":\"guard_protect\",\"targetSeatNumber\":2}", context)
	assert(not bool(stale_target.get("ok", false)))
	var old_field: Dictionary = page._bot_runtime.parse_decision("{\"action\":\"guard_protect\",\"target_index\":0,\"targetSeatNumber\":1}", context)
	assert(not bool(old_field.get("ok", false)))
	var debug_reason: Dictionary = page._bot_runtime.parse_decision("{\"action\":\"guard_protect\",\"targetSeatNumber\":1,\"reason\":\"因为安全\"}", context)
	assert(not bool(debug_reason.get("ok", false)))
	var fenced_debug_reason: Dictionary = page._bot_runtime.parse_decision("```json\n{\"action\":\"guard_protect\",\"targetSeatNumber\":1,\"reason\":\"因为安全\"}\n```", context)
	assert(not bool(fenced_debug_reason.get("ok", false)))
	var string_target: Dictionary = page._bot_runtime.parse_decision("{\"action\":\"guard_protect\",\"targetSeatNumber\":\"1\"}", context)
	assert(not bool(string_target.get("ok", false)))
	var extra_field: Dictionary = page._bot_runtime.parse_decision("{\"action\":\"guard_protect\",\"targetSeatNumber\":1,\"debugReason\":\"test\"}", context)
	assert(not bool(extra_field.get("ok", false)))


func _check_sheriff_vote_self_target(page) -> void:
	page._werewolf["phase"] = "sheriff_vote"
	page._werewolf["current_action"] = {"key": "sheriff_vote", "actor_index": 0, "label": "警长"}
	var context: Dictionary = page._bot_action_context(0, "sheriff_vote", {})
	var payload: Dictionary = page._bot_runtime.to_model_payload(context)
	assert(payload.has("targetOptions"))
	assert(String(payload.get("current_question", "")) == "选择警长投票目标。")
	var targets: Array = page._bot_runtime.target_options_for_context(context)
	assert(targets.size() == 2)
	assert(int((targets[0] as Dictionary).get("targetSeatNumber", -1)) == 1)
	assert(int((targets[1] as Dictionary).get("targetSeatNumber", -1)) == 2)
	assert((payload["targetOptions"] as Array).size() == targets.size())
	var response_schema: Dictionary = page._bot_runtime.response_schema_for_context(context)
	assert(not response_schema.is_empty())
	assert(bool(response_schema.get("strict", false)))
	var schema_body: Dictionary = response_schema["schema"] as Dictionary
	assert((schema_body["required"] as Array).has("action"))
	assert((schema_body["required"] as Array).has("targetSeatNumber"))
	var properties: Dictionary = schema_body["properties"] as Dictionary
	var target_schema: Dictionary = properties["targetSeatNumber"] as Dictionary
	assert((target_schema.get("enum", []) as Array).has(1))
	assert((target_schema.get("enum", []) as Array).has(2))
	var parsed_self: Dictionary = page._bot_runtime.parse_decision("{\"action\":\"sheriff_vote\",\"targetSeatNumber\":1}", context)
	assert(bool(parsed_self.get("ok", false)))
	assert(int(parsed_self.get("target_index", -1)) == 0)


func _check_sheriff_speech_order_context(page) -> void:
	page._werewolf["phase"] = "sheriff_speech_order"
	page._werewolf["sheriff_player_index"] = 0
	page._werewolf["current_action"] = {"key": "sheriff_speech_order", "actor_index": 0, "label": "发言顺序"}
	var context: Dictionary = page._bot_action_context(0, "sheriff_speech_order", {})
	assert((context["allowed_actions"] as Array).has("sheriff_speech_order_clockwise"))
	assert((context["allowed_actions"] as Array).has("sheriff_speech_order_counterclockwise"))
	var payload: Dictionary = page._bot_runtime.to_model_payload(context)
	assert(payload.has("targetOptions"))
	assert(String(payload.get("current_question", "")) == "指定白天发言起点和方向。")
	var messages: Array = page._bot_runtime.build_messages(context)
	var system_content := String((messages[0] as Dictionary).get("content", ""))
	assert(system_content.contains("[行动含义]"))
	assert(system_content.contains("sheriff_speech_order_clockwise"))
	assert(system_content.contains("sheriff_speech_order_counterclockwise"))
	var targets: Array = page._bot_runtime.target_options_for_context(context)
	assert(targets.size() == 2)
	assert(int((targets[0] as Dictionary).get("targetSeatNumber", -1)) == 1)
	assert(int((targets[1] as Dictionary).get("targetSeatNumber", -1)) == 2)
	assert(((targets[0] as Dictionary).get("targetActions", []) as Array).has("sheriff_speech_order_clockwise"))
	assert(((targets[0] as Dictionary).get("targetActions", []) as Array).has("sheriff_speech_order_counterclockwise"))
	var response_schema: Dictionary = page._bot_runtime.response_schema_for_context(context)
	assert(not response_schema.is_empty())
	var schema_body: Dictionary = response_schema["schema"] as Dictionary
	var properties: Dictionary = schema_body["properties"] as Dictionary
	assert(((properties["action"] as Dictionary).get("enum", []) as Array).has("sheriff_speech_order_clockwise"))
	assert(((properties["action"] as Dictionary).get("enum", []) as Array).has("sheriff_speech_order_counterclockwise"))
	assert(((properties["targetSeatNumber"] as Dictionary).get("enum", []) as Array).has(1))
	assert(((properties["targetSeatNumber"] as Dictionary).get("enum", []) as Array).has(2))
	var parsed: Dictionary = page._bot_runtime.parse_decision("{\"action\":\"sheriff_speech_order_counterclockwise\",\"targetSeatNumber\":2}", context)
	assert(bool(parsed.get("ok", false)))
	assert(String(parsed.get("action", "")) == "sheriff_speech_order_counterclockwise")
	assert(int(parsed.get("target_index", -1)) == 1)
	var wrong_action: Dictionary = page._bot_runtime.parse_decision("{\"action\":\"sheriff_speech_order\",\"targetSeatNumber\":2}", context)
	assert(not bool(wrong_action.get("ok", false)))


func _check_sheriff_badge_context(page) -> void:
	page._players[0]["alive"] = false
	page._players[1]["alive"] = true
	page._players[2]["alive"] = false
	page._werewolf["phase"] = "sheriff_badge_action"
	page._werewolf["has_sheriff"] = true
	page._werewolf["sheriff_player_index"] = 0
	page._werewolf["sheriff_badge_dead_index"] = 0
	page._werewolf["current_action"] = {"key": "sheriff_badge_action", "actor_index": 0, "label": "警徽"}
	var context: Dictionary = page._bot_action_context(0, "sheriff_badge_action", {})
	assert((context["allowed_actions"] as Array).has("sheriff_badge_pass"))
	assert((context["allowed_actions"] as Array).has("sheriff_badge_destroy"))
	var payload: Dictionary = page._bot_runtime.to_model_payload(context)
	assert(String(payload.get("current_question", "")).contains("飞警徽"))
	assert(String(payload.get("current_question", "")).contains("撕警徽"))
	assert(payload.has("targetOptions"))
	var messages: Array = page._bot_runtime.build_messages(context)
	var system_content := String((messages[0] as Dictionary).get("content", ""))
	assert(system_content.contains("[行动含义]"))
	assert(system_content.contains("sheriff_badge_pass"))
	assert(system_content.contains("sheriff_badge_destroy"))
	var targets: Array = page._bot_runtime.target_options_for_context(context)
	assert(targets.size() == 1)
	assert(int((targets[0] as Dictionary).get("targetSeatNumber", -1)) == 2)
	assert(((targets[0] as Dictionary).get("targetActions", []) as Array).has("sheriff_badge_pass"))
	var response_schema: Dictionary = page._bot_runtime.response_schema_for_context(context)
	assert(not response_schema.is_empty())
	var schema_body: Dictionary = response_schema["schema"] as Dictionary
	var properties: Dictionary = schema_body["properties"] as Dictionary
	assert(((properties["action"] as Dictionary).get("enum", []) as Array).has("sheriff_badge_pass"))
	assert(((properties["action"] as Dictionary).get("enum", []) as Array).has("sheriff_badge_destroy"))
	var target_enum: Array = (properties["targetSeatNumber"] as Dictionary).get("enum", []) as Array
	assert(target_enum.has(-1))
	assert(target_enum.has(2))
	var variants: Array = schema_body.get("anyOf", []) as Array
	assert(_schema_variant_has_action_target(variants, "sheriff_badge_pass", 2))
	assert(_schema_variant_has_action_target(variants, "sheriff_badge_destroy", -1))
	var pass_decision: Dictionary = page._bot_runtime.parse_decision("{\"action\":\"sheriff_badge_pass\",\"targetSeatNumber\":2}", context)
	assert(bool(pass_decision.get("ok", false)))
	assert(int(pass_decision.get("target_index", -1)) == 1)
	var destroy_decision: Dictionary = page._bot_runtime.parse_decision("{\"action\":\"sheriff_badge_destroy\",\"targetSeatNumber\":-1}", context)
	assert(bool(destroy_decision.get("ok", false)))
	assert(int(destroy_decision.get("target_index", -1)) == -1)
	var destroy_with_target: Dictionary = page._bot_runtime.parse_decision("{\"action\":\"sheriff_badge_destroy\",\"targetSeatNumber\":2}", context)
	assert(not bool(destroy_with_target.get("ok", false)))
	var pass_no_target: Dictionary = page._bot_runtime.parse_decision("{\"action\":\"sheriff_badge_pass\",\"targetSeatNumber\":-1}", context)
	assert(not bool(pass_no_target.get("ok", false)))
	page._players[0]["alive"] = true


func _check_mvp_roles_and_decision(page) -> void:
	page._werewolf["phase"] = "mvp_vote"
	page._werewolf["winner"] = "wolf"
	page._werewolf["post_game"] = {"stage": "mvp_vote"}
	page._werewolf["current_action"] = {"key": "mvp_vote", "actor_index": 0, "label": "MVP"}
	page._history = [
		{"speaker": "主持人", "text": "游戏结束，狼人胜利。", "at": 3},
		{"speaker": "MVP投票", "text": "1号 张安 投给 2号 李宁 为本场 MVP。", "at": 4},
	]
	var context: Dictionary = page._bot_action_context(0, "mvp_vote", {})
	var payload: Dictionary = page._bot_runtime.to_model_payload(context)
	assert(payload.has("targetOptions"))
	var targets: Array = page._bot_runtime.target_options_for_context(context)
	assert((payload["targetOptions"] as Array).size() == targets.size())
	assert(String((targets[0] as Dictionary).get("targetRole", "")) == "守卫")
	assert(String((targets[1] as Dictionary).get("targetRole", "")) == "狼人")
	var parsed: Dictionary = page._bot_runtime.parse_decision("{\"action\":\"mvp_vote\",\"targetSeatNumber\":2}", context)
	assert(bool(parsed.get("ok", false)))
	assert(int(parsed.get("target_index", -1)) == 1)

	page._werewolf["phase"] = "day_discussion"
	var speech_context: Dictionary = page._bot_speech_context(0, {})
	var speech_parsed: Dictionary = page._bot_runtime.parse_decision("我先听2号发言，重点看票型和站边。", speech_context)
	assert(bool(speech_parsed.get("ok", false)))
	assert(String(speech_parsed.get("speech_text", "")).contains("2号"))


func _check_witch_skip_and_save(page) -> void:
	page._players[0]["role_key"] = "witch"
	page._players[0]["role"] = "女巫"
	page._werewolf["phase"] = "witch_action"
	page._werewolf["witch_antidote"] = true
	page._werewolf["witch_poison"] = false
	page._werewolf["night"] = {"wolf_target_index": 1}
	page._werewolf["current_action"] = {"key": "witch_act", "actor_index": 0, "label": "用药"}
	var context: Dictionary = page._bot_action_context(0, "witch_act", {})
	assert((context["allowed_actions"] as Array).has("witch_save"))
	assert((context["allowed_actions"] as Array).has("witch_skip"))
	var payload: Dictionary = page._bot_runtime.to_model_payload(context)
	assert(String(payload.get("current_question", "")) == "选择救人、毒人或跳过。")
	assert(String(JSON.stringify(payload.get("privateInfo", {}))).contains("tonightKilledPlayer"))
	assert(payload.has("targetOptions"))
	var targets: Array = page._bot_runtime.target_options_for_context(context)
	assert(targets.size() == 1)
	assert(int((targets[0] as Dictionary).get("targetSeatNumber", -1)) == 2)
	assert(((targets[0] as Dictionary).get("targetActions", []) as Array).has("witch_save"))
	assert((payload["targetOptions"] as Array).size() == targets.size())
	var response_schema: Dictionary = page._bot_runtime.response_schema_for_context(context)
	assert(not response_schema.is_empty())
	assert(bool(response_schema.get("strict", false)))
	var schema_body: Dictionary = response_schema["schema"] as Dictionary
	assert((schema_body["required"] as Array).has("action"))
	assert((schema_body["required"] as Array).has("targetSeatNumber"))
	assert(not (schema_body["properties"] as Dictionary).has("confidence"))
	assert((schema_body["properties"] as Dictionary).has("targetSeatNumber"))
	var properties: Dictionary = schema_body["properties"] as Dictionary
	var target_schema: Dictionary = properties["targetSeatNumber"] as Dictionary
	assert((target_schema.get("enum", []) as Array).has(-1))
	assert((target_schema.get("enum", []) as Array).has(2))
	var variants: Array = schema_body.get("anyOf", []) as Array
	assert(_schema_variant_has_action_target(variants, "witch_save", 2))
	assert(_schema_variant_has_action_target(variants, "witch_skip", -1))
	var save_decision: Dictionary = page._bot_runtime.parse_decision("{\"action\":\"witch_save\",\"targetSeatNumber\":2}", context)
	assert(bool(save_decision.get("ok", false)))
	assert(int(save_decision.get("target_index", -1)) == 1)
	var save_missing_target: Dictionary = page._bot_runtime.parse_decision("{\"action\":\"witch_save\"}", context)
	assert(not bool(save_missing_target.get("ok", false)))
	var save_with_no_target_marker: Dictionary = page._bot_runtime.parse_decision("{\"action\":\"witch_save\",\"targetSeatNumber\":-1}", context)
	assert(not bool(save_with_no_target_marker.get("ok", false)))
	var skip_decision: Dictionary = page._bot_runtime.parse_decision("{\"action\":\"witch_skip\",\"targetSeatNumber\":-1}", context)
	assert(bool(skip_decision.get("ok", false)))
	assert(int(skip_decision.get("target_index", -1)) == -1)
	var skip_missing_target: Dictionary = page._bot_runtime.parse_decision("{\"action\":\"witch_skip\"}", context)
	assert(not bool(skip_missing_target.get("ok", false)))
	var skip_with_target: Dictionary = page._bot_runtime.parse_decision("{\"action\":\"witch_skip\",\"targetSeatNumber\":2}", context)
	assert(not bool(skip_with_target.get("ok", false)))


func _check_witch_poison_targets_exclude_save_target(page) -> void:
	page._players[0]["role_key"] = "witch"
	page._players[0]["role"] = "女巫"
	page._players[1]["alive"] = true
	page._players[2]["alive"] = true
	page._werewolf["phase"] = "witch_action"
	page._werewolf["witch_antidote"] = true
	page._werewolf["witch_poison"] = true
	page._werewolf["night"] = {"wolf_target_index": 1}
	page._werewolf["current_action"] = {"key": "witch_act", "actor_index": 0, "label": "用药"}
	var context: Dictionary = page._bot_action_context(0, "witch_act", {})
	var payload: Dictionary = page._bot_runtime.to_model_payload(context)
	assert(payload.has("targetOptions"))
	var targets: Array = page._bot_runtime.target_options_for_context(context)
	assert(targets.size() == 2)
	assert(int((targets[0] as Dictionary).get("targetSeatNumber", -1)) == 2)
	assert(((targets[0] as Dictionary).get("targetActions", []) as Array).has("witch_save"))
	assert(int((targets[1] as Dictionary).get("targetSeatNumber", -1)) == 3)
	assert(((targets[1] as Dictionary).get("targetActions", []) as Array).has("witch_poison"))
	assert((payload["targetOptions"] as Array).size() == targets.size())
	var response_schema: Dictionary = page._bot_runtime.response_schema_for_context(context)
	assert(not response_schema.is_empty())
	assert(bool(response_schema.get("strict", false)))
	var schema_body: Dictionary = response_schema["schema"] as Dictionary
	assert((schema_body["required"] as Array).has("action"))
	assert((schema_body["required"] as Array).has("targetSeatNumber"))
	var properties: Dictionary = schema_body["properties"] as Dictionary
	assert((properties["targetSeatNumber"] as Dictionary).has("enum"))
	assert(((properties["targetSeatNumber"] as Dictionary).get("enum", []) as Array).has(-1))
	assert(((properties["targetSeatNumber"] as Dictionary).get("enum", []) as Array).has(2))
	var variants: Array = schema_body.get("anyOf", []) as Array
	assert(variants.size() >= 3)
	assert(_schema_variant_has_action_target(variants, "witch_save", 2))
	assert(_schema_variant_has_action_target(variants, "witch_skip", -1))
	assert(_schema_variant_has_action_target(variants, "witch_poison", 3))
	var poison_save_target: Dictionary = page._bot_runtime.parse_decision("{\"action\":\"witch_poison\",\"targetSeatNumber\":2}", context)
	assert(not bool(poison_save_target.get("ok", false)))
	var poison_decision: Dictionary = page._bot_runtime.parse_decision("{\"action\":\"witch_poison\",\"targetSeatNumber\":3}", context)
	assert(bool(poison_decision.get("ok", false)))
	assert(int(poison_decision.get("target_index", -1)) == 2)
	var save_no_target: Dictionary = page._bot_runtime.parse_decision("{\"action\":\"witch_save\",\"targetSeatNumber\":-1}", context)
	assert(not bool(save_no_target.get("ok", false)))
	var skip_no_target: Dictionary = page._bot_runtime.parse_decision("{\"action\":\"witch_skip\",\"targetSeatNumber\":-1}", context)
	assert(bool(skip_no_target.get("ok", false)))
	var save_real_target: Dictionary = page._bot_runtime.parse_decision("{\"action\":\"witch_save\",\"targetSeatNumber\":2}", context)
	assert(bool(save_real_target.get("ok", false)))
	assert(int(save_real_target.get("target_index", -1)) == 1)
	var save_poison_target: Dictionary = page._bot_runtime.parse_decision("{\"action\":\"witch_save\",\"targetSeatNumber\":3}", context)
	assert(not bool(save_poison_target.get("ok", false)))


func _check_hunter_shoot_schema_and_parser(page) -> void:
	page._players = [
		_player("player_1", "张安", "hunter", true),
		_player("player_2", "李宁", "wolf", true),
		_player("player_3", "周舟", "villager", true),
	]
	page._werewolf = {
		"phase": "hunter_shoot",
		"day": 2,
		"map_name": "标准村庄",
		"has_sheriff": false,
		"votes": {},
		"night": {},
		"current_action": {"key": "hunter_shoot", "actor_index": 0, "label": "开枪"},
		"last_guarded_index": -1,
		"post_game": {"stage": ""},
	}
	var context: Dictionary = page._bot_action_context(0, "hunter_shoot", {})
	assert((context["allowed_actions"] as Array) == ["hunter_shoot", "skip"])
	var targets: Array = page._bot_runtime.target_options_for_context(context)
	assert(targets.size() == 2)
	var response_schema: Dictionary = page._bot_runtime.response_schema_for_context(context)
	assert(not response_schema.is_empty())
	assert(bool(response_schema.get("strict", false)))
	var schema_body: Dictionary = response_schema["schema"] as Dictionary
	assert((schema_body["required"] as Array).has("action"))
	assert((schema_body["required"] as Array).has("targetSeatNumber"))
	var target_schema: Dictionary = (schema_body["properties"] as Dictionary)["targetSeatNumber"] as Dictionary
	var enum_values: Array = target_schema.get("enum", []) as Array
	assert(enum_values.has(-1))
	assert(enum_values.has(2))
	assert(enum_values.has(3))

	var shoot_decision: Dictionary = page._bot_runtime.parse_decision("{\"action\":\"hunter_shoot\",\"targetSeatNumber\":2}", context)
	assert(bool(shoot_decision.get("ok", false)))
	assert(int(shoot_decision.get("target_index", -1)) == 1)
	var skip_decision: Dictionary = page._bot_runtime.parse_decision("{\"action\":\"skip\",\"targetSeatNumber\":-1}", context)
	assert(bool(skip_decision.get("ok", false)))
	assert(int(skip_decision.get("target_index", -1)) == -1)
	var missing_skip_target: Dictionary = page._bot_runtime.parse_decision("{\"action\":\"skip\"}", context)
	assert(not bool(missing_skip_target.get("ok", false)))
	var skip_with_real_target: Dictionary = page._bot_runtime.parse_decision("{\"action\":\"skip\",\"targetSeatNumber\":2}", context)
	assert(not bool(skip_with_real_target.get("ok", false)))
	var missing_shoot_target: Dictionary = page._bot_runtime.parse_decision("{\"action\":\"hunter_shoot\"}", context)
	assert(not bool(missing_shoot_target.get("ok", false)))
	var fractional_shoot_target: Dictionary = page._bot_runtime.parse_decision("{\"action\":\"hunter_shoot\",\"targetSeatNumber\":2.5}", context)
	assert(not bool(fractional_shoot_target.get("ok", false)))


func _check_wolf_action_records_private_vote(page) -> void:
	page._mode = page.Mode.TABLE
	page._players = [
		_player("player_1", "张安", "villager", true),
		_player("player_2", "李宁", "wolf", true),
		_player("player_3", "周舟", "villager", true),
	]
	page._history = []
	page._werewolf = {
		"phase": "wolf_action",
		"day": 1,
		"map_id": "basic_village",
		"map_name": "标准村庄",
		"wolf_win_condition": "all_good_dead",
		"votes": {},
		"night": {"day": 1, "wolf_target_index": -1},
		"current_action": {"key": "wolf_kill", "actor_index": 1, "label": "投刀"},
		"last_guarded_index": -1,
		"witch_antidote": true,
		"witch_poison": true,
		"sheriff_player_index": -1,
		"post_game": {"stage": ""},
	}
	page._pending_action = "投刀"
	page._pending_actor_index = 1
	page._bot_wolf_target_vote_keys.clear()
	page._bot_wolf_target_votes.clear()
	page._bot_request_tracker.register_action(9101, {
		"actor_index": 1,
		"action_key": "wolf_kill",
		"label": "投刀",
		"context": page._bot_action_context(1, "wolf_kill", {}),
		"state": page._werewolf.duplicate(true),
	})
	page._waiting_bot_action = true
	page._on_model_action_completed(9101, true, "{\"action\":\"wolf_kill\",\"targetSeatNumber\":1}", "")
	assert(not page._waiting_bot_action)
	var saw_vote := false
	for vote_value in page._bot_wolf_target_votes.values():
		var vote: Dictionary = vote_value
		if int(vote.get("target_index", -1)) == 0:
			saw_vote = true
	assert(saw_vote)
	assert((page._history as Array).any(func(item): return item is Dictionary and String((item as Dictionary).get("text", "")).contains("投票袭击 1号 张安")))
	page._mode = page.Mode.LOBBY


func _check_action_parse_failure_halts_game(page) -> void:
	_seed_players(page)
	page._mode = page.Mode.TABLE
	page._pending_action = "投票"
	page._pending_actor_index = 0
	page._werewolf["phase"] = "vote"
	page._werewolf["votes"] = {}
	page._werewolf["current_action"] = {"key": "vote", "actor_index": 0, "label": "投票"}
	page._bot_request_tracker.register_action(9001, {
		"actor_index": 0,
		"action_key": "vote",
		"label": "投票",
		"context": page._bot_action_context(0, "vote", {}),
		"state": page._werewolf.duplicate(true),
	})
	page._waiting_bot_action = true
	page._on_model_action_completed(9001, true, "不是 JSON", "")
	assert(not page._waiting_bot_action)
	assert(page._bot_flow_halted)
	assert(bool(page._werewolf.get("bot_error_halted", false)))
	assert((page._werewolf.get("votes", {}) as Dictionary).is_empty())
	assert(int((page._werewolf.get("current_action", {}) as Dictionary).get("actor_index", -1)) == 0)
	assert(not (page._history as Array).any(func(item): return item is Dictionary and String((item as Dictionary).get("text", "")).contains("投票给 2号 李宁")))
	assert(String(page._system_message).contains("游戏已中止"))
	assert(page.find_child("ModelErrorOverlay", true, false) != null)
	page._schedule_auto_resolve_bot_turns()
	assert(not page._auto_resolve_deferred_pending)
	var blocked_result: Dictionary = page._engine.apply_target(page._werewolf, page._players, 1, page._local_player_index)
	assert(bool(blocked_result.get("ok", false)))
	assert(not page._apply_engine_result(blocked_result))
	assert((page._werewolf.get("votes", {}) as Dictionary).is_empty())
	page._mode = page.Mode.LOBBY


func _check_illegal_target_repair_continues_game(page) -> void:
	_seed_players(page)
	page._mode = page.Mode.TABLE
	page._pending_action = "投票"
	page._pending_actor_index = 0
	page._bot_flow_halted = false
	page._bot_flow_halt_error.clear()
	page._werewolf.erase("bot_error_halted")
	page._werewolf.erase("bot_error")
	page._werewolf["phase"] = "vote"
	page._werewolf["votes"] = {}
	page._werewolf["current_action"] = {"key": "vote", "actor_index": 0, "label": "投票"}
	var context: Dictionary = page._bot_action_context(0, "vote", {})
	var targets: Array = page._bot_runtime.target_options_for_context(context)
	assert(targets.size() == 1)
	assert(int((targets[0] as Dictionary).get("targetSeatNumber", -1)) == 2)
	page._bot_request_tracker.register_action(9301, {
		"actor_index": 0,
		"action_key": "vote",
		"label": "投票",
		"context": context,
		"state": page._werewolf.duplicate(true),
	})
	page._waiting_bot_action = true
	page._on_model_action_completed(9301, true, "{\"action\":\"vote\",\"targetSeatNumber\":1}", "")
	assert(not page._waiting_bot_action)
	assert(not page._bot_flow_halted)
	assert(not bool(page._werewolf.get("bot_error_halted", false)))
	assert(int((page._werewolf.get("votes", {}) as Dictionary).get("0", -1)) == 1)
	page._mode = page.Mode.LOBBY


func _check_reasoning_output_warning_continues_game(page) -> void:
	_seed_players(page)
	page._mode = page.Mode.TABLE
	page._pending_action = "投票"
	page._pending_actor_index = 0
	page._werewolf["phase"] = "vote"
	page._werewolf["votes"] = {}
	page._werewolf["current_action"] = {"key": "vote", "actor_index": 0, "label": "投票"}
	page._bot_request_tracker.register_action(9201, {
		"actor_index": 0,
		"action_key": "vote",
		"label": "投票",
		"context": page._bot_action_context(0, "vote", {}),
		"state": page._werewolf.duplicate(true),
		"expected_reasoning": false,
		"model_profile": {"model": "test-model", "provider": "openai_api", "reason_adapter": "native", "reasoning": false},
	})
	page._waiting_bot_action = true
	page._on_model_action_completed(9201, true, "{\"action\":\"vote\",\"targetSeatNumber\":2}", "", {
		"ok": true,
		"text": "{\"action\":\"vote\",\"targetSeatNumber\":2}",
		"error": "",
		"reasoning_mode": "off",
		"has_reasoning_output": true,
		"reasoning_text": "这里是模型思考",
		"diagnostic": {
			"parse_ok": true,
			"response_code": 200,
			"reasoning_enabled": false,
			"has_reasoning_output": true,
			"reasoning_output": "这里是模型思考",
		},
	})
	assert(not page._waiting_bot_action)
	assert(not page._bot_flow_halted)
	assert(String(page._last_bot_reasoning_warning_signature).contains("test-model模型,适配方式native,仍旧返回了思考,fuck"))
	assert(String(page._last_bot_reasoning_warning_signature).contains("低能儿"))
	assert(int((page._werewolf.get("votes", {}) as Dictionary).get("0", -1)) == 1)

	_seed_players(page)
	page._mode = page.Mode.TABLE
	page._pending_action = "投票"
	page._pending_actor_index = 0
	page._bot_flow_halted = false
	page._bot_flow_halt_error.clear()
	page._werewolf.erase("bot_error_halted")
	page._werewolf.erase("bot_error")
	page._werewolf["phase"] = "vote"
	page._werewolf["votes"] = {}
	page._werewolf["current_action"] = {"key": "vote", "actor_index": 0, "label": "投票"}
	page._bot_request_tracker.register_action(9202, {
		"actor_index": 0,
		"action_key": "vote",
		"label": "投票",
		"context": page._bot_action_context(0, "vote", {}),
		"state": page._werewolf.duplicate(true),
		"expected_reasoning": true,
		"model_profile": {"model": "test-model", "provider": "openai_api", "reason_adapter": "openai_reasoning_effort", "reasoning": true},
	})
	page._waiting_bot_action = true
	page._on_model_action_completed(9202, true, "{\"action\":\"vote\",\"targetSeatNumber\":2}", "", {
		"ok": true,
		"text": "{\"action\":\"vote\",\"targetSeatNumber\":2}",
		"error": "",
		"reasoning_mode": "on",
		"has_reasoning_output": false,
		"reasoning_text": "",
		"diagnostic": {
			"parse_ok": true,
			"response_code": 200,
			"reasoning_enabled": true,
			"has_reasoning_output": false,
			"reasoning_output": "",
		},
	})
	assert(not page._waiting_bot_action)
	assert(not page._bot_flow_halted)
	assert(int((page._werewolf.get("votes", {}) as Dictionary).get("0", -1)) == 1)

	_seed_players(page)
	page._mode = page.Mode.TABLE
	page._pending_action = "投票"
	page._pending_actor_index = 0
	page._bot_flow_halted = false
	page._bot_flow_halt_error.clear()
	page._werewolf.erase("bot_error_halted")
	page._werewolf.erase("bot_error")
	page._werewolf["phase"] = "vote"
	page._werewolf["votes"] = {}
	page._werewolf["current_action"] = {"key": "vote", "actor_index": 0, "label": "投票"}
	page._bot_request_tracker.register_action(9203, {
		"actor_index": 0,
		"action_key": "vote",
		"label": "投票",
		"context": page._bot_action_context(0, "vote", {}),
		"state": page._werewolf.duplicate(true),
		"expected_reasoning": false,
		"model_profile": {"model": "minimax-m2.7", "provider": "openai_api", "reason_adapter": "minimax_reasoning_split", "reasoning": false},
	})
	page._waiting_bot_action = true
	page._on_model_action_completed(9203, true, "{\"action\":\"vote\",\"targetSeatNumber\":2}", "", {
		"ok": true,
		"text": "{\"action\":\"vote\",\"targetSeatNumber\":2}",
		"error": "",
		"reasoning_mode": "off",
		"has_reasoning_output": true,
		"reasoning_text": "拆分出来的 MiniMax 思考",
		"diagnostic": {
			"parse_ok": true,
			"response_code": 200,
			"reasoning_enabled": false,
			"has_reasoning_output": true,
			"reasoning_output": "拆分出来的 MiniMax 思考",
		},
	})
	assert(not page._waiting_bot_action)
	assert(not page._bot_flow_halted)
	assert(String(page._last_bot_reasoning_warning_signature).contains("minimax-m2.7模型,适配方式minimax_reasoning_split,仍旧返回了思考,fuck"))
	assert(int((page._werewolf.get("votes", {}) as Dictionary).get("0", -1)) == 1)
	page._mode = page.Mode.LOBBY


func _schema_variant_has_action_target(variants: Array, action: String, target_seat_number: int) -> bool:
	for variant in variants:
		if not (variant is Dictionary):
			continue
		var properties: Dictionary = (variant as Dictionary).get("properties", {}) as Dictionary
		var action_schema: Dictionary = properties.get("action", {}) as Dictionary
		var target_schema: Dictionary = properties.get("targetSeatNumber", {}) as Dictionary
		var actions: Array = action_schema.get("enum", []) as Array
		var targets: Array = target_schema.get("enum", []) as Array
		if actions.has(action) and targets.has(target_seat_number):
			return true
	return false


func _player(id: String, name: String, role_key: String, alive: bool) -> Dictionary:
	var role_names := {
		"wolf": "狼人",
		"villager": "村民",
		"seer": "预言家",
		"witch": "女巫",
		"hunter": "猎人",
		"guard": "守卫",
	}
	return {
		"id": id,
		"name": name,
		"role": String(role_names.get(role_key, role_key)),
		"role_key": role_key,
		"avatar": "",
		"state": "等待",
		"motion": 0,
		"alive": alive,
		"ready": true,
		"owner": "bot",
	}


func _repeat_text(text: String, count: int) -> String:
	var result := ""
	for _i in range(count):
		result += text
	return result
