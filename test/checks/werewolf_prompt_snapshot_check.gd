extends SceneTree

const BuilderScript := preload("res://scripts/player/werewolf/ai/ai_werewolf_turn_context_builder.gd")
const RuntimeScript := preload("res://scripts/player/werewolf/ai/ai_werewolf_player_runtime.gd")


func _initialize() -> void:
	var builder = BuilderScript.new()
	var runtime = RuntimeScript.new()
	var input := _input()

	_assert_contract(runtime, builder.wolf_chat_context(input, 0, {}), "狼人", false, "发表狼队夜聊。")
	_assert_contract(runtime, builder.action_context(input, 0, "wolf_kill", {}), "狼人", true, "选择今晚狼队击杀目标。")
	_assert_contract(runtime, builder.action_context(input, 1, "seer_check", {}), "预言家", true, "选择今晚查验目标。")
	_assert_contract(runtime, builder.action_context(_witch_input(input), 3, "witch_act", {}), "女巫", true, "选择救人、毒人或跳过。")
	_assert_contract(runtime, builder.action_context(input, 4, "guard_protect", {}), "守卫", true, "选择今晚守护目标。")
	_assert_sheriff_campaign_contract(runtime, builder, input)
	_assert_last_words_contract(runtime, builder, input)
	_assert_current_questions_are_simple(builder, input)

	quit()


func _assert_contract(runtime, context: Dictionary, role_label: String, expects_schema: bool, question_fragment: String) -> void:
	var messages: Array = runtime.build_messages(context)
	var system_content := String((messages[0] as Dictionary).get("content", ""))
	var user_content := String((messages[1] as Dictionary).get("content", ""))
	var user_payload: Dictionary = runtime.to_model_payload(context)
	var question := String(user_payload.get("current_question", ""))

	assert(system_content.contains("游戏规则："))
	assert(system_content.contains("当前状态："))
	assert(system_content.contains("current_question：本次需要回答的问题。"))
	assert(system_content.contains("current_state：只表示当前阶段和系统已结算状态。"))
	assert(system_content.contains("players：只表示当前视角可见的玩家列表。"))
	assert(system_content.contains("timeline：只表示本局当前视角可见的记录，包括发言和行动。"))
	assert(system_content.contains("memoryHints：我的历史记忆摘要。"))
	assert(system_content.contains("targetOptions：可选座位列表，-1 表示不选择目标。"))
	assert(system_content.contains("你必须按照输出格式要求，只回答 current_question 对应的问题。"))
	assert(system_content.contains("身份：%s" % role_label))
	assert(system_content.contains("current_state"))
	if expects_schema:
		assert(system_content.contains("targetOptions"))
		assert(system_content.contains("action 表示本次行动："))
		assert(system_content.contains("固定填"))
		assert(system_content.contains("targetSeatNumber 从 user.targetOptions 选"))
		assert(not system_content.contains("建议回复在120字以内"))
	else:
		assert(system_content.contains("直接返回发言文本"))
		assert(system_content.contains("建议回复在120字以内"))
		assert(system_content.contains("发言原则：结合你当前身份、当前阶段和可见信息发言，优先说符合自身身份利益的话；可以伪装、试探、误导，也可以按策略故意暴露。"))
	assert(not system_content.contains("只输出 JSON"))
	assert(not system_content.contains("outputFormat"))
	assert(not system_content.contains("confidence"))
	assert(not system_content.contains("[游戏上下文]"))
	assert(not system_content.contains("[原则]"))
	assert(not system_content.contains("[公开发言边界]"))
	assert(not system_content.contains("[警长竞选边界]"))
	var response_schema: Dictionary = runtime.response_schema_for_context(context)
	if expects_schema:
		assert(not response_schema.is_empty())
		assert(response_schema.has("schema"))
	else:
		assert(response_schema.is_empty())

	assert(user_payload.has("current_question"))
	assert(user_payload.has("current_state"))
	assert(user_payload.has("players"))
	assert(user_payload.has("timeline"))
	assert(not user_payload.has("outputFormat"))
	assert(not user_payload.has("allowedActions"))
	assert(not user_payload.has("actionOptions"))
	assert(not user_payload.has("targetSeatNumberOptions"))
	assert(user_payload.has("targetOptions") == expects_schema)
	if expects_schema:
		assert(user_payload.get("targetOptions", []) is Array)
		assert((user_payload["targetOptions"] as Array).size() > 0)
		assert((user_payload["targetOptions"] as Array).all(func(value): return value is int))
	assert(question.contains(question_fragment))
	assert(user_content.begins_with("{"))
	var parsed = JSON.parse_string(user_content)
	assert(parsed is Dictionary)
	assert(String((parsed as Dictionary).get("current_question", "")) == question)
	assert(not question.contains("返回 action"))
	assert(not question.contains("只返回"))
	assert(not question.contains("只输出"))


func _assert_sheriff_campaign_contract(runtime, builder, input: Dictionary) -> void:
	var campaign_input: Dictionary = input.duplicate(true)
	(campaign_input["werewolf"] as Dictionary)["phase"] = "sheriff_speech"
	(campaign_input["werewolf"] as Dictionary)["day"] = 1
	campaign_input["phase_label"] = "警长竞选发言"
	var context: Dictionary = builder.speech_context(campaign_input, 1, {})
	var messages: Array = runtime.build_messages(context)
	var system_content := String((messages[0] as Dictionary).get("content", ""))
	var user_content := String((messages[1] as Dictionary).get("content", ""))
	var payload: Dictionary = runtime.to_model_payload(context)
	var question := String(payload.get("current_question", ""))
	assert(system_content.contains("当前状态："))
	assert(system_content.contains("第1天白天（首夜前，无夜间技能结果）"))
	assert(system_content.contains("警长竞选发言"))
	assert(not system_content.contains("本局尚未进入首夜"))
	assert(not system_content.contains("你目前没有查验结果"))
	assert(not system_content.contains("私有底牌"))
	assert(not system_content.contains("[游戏上下文]"))
	assert(system_content.contains("发言原则：结合你当前身份、当前阶段和可见信息发言，优先说符合自身身份利益的话；可以伪装、试探、误导，也可以按策略故意暴露。"))
	assert(question == "发表警长竞选发言。")
	assert(user_content.begins_with("{"))
	assert(String(payload.get("current_state", "")).contains("首夜前"))
	assert(String(payload.get("current_state", "")).contains("无夜间技能结果"))
	assert(not payload.has("facts"))


func _assert_last_words_contract(runtime, builder, input: Dictionary) -> void:
	var speech_messages: Array = runtime.build_messages(builder.speech_context(input, 0, {}))
	var speech_system := String((speech_messages[0] as Dictionary).get("content", ""))
	assert(not speech_system.contains("遗言是全局可见的。"))

	var last_words_input: Dictionary = input.duplicate(true)
	(last_words_input["werewolf"] as Dictionary)["phase"] = "last_words"
	var context: Dictionary = builder.speech_context(last_words_input, 0, {})
	var messages: Array = runtime.build_messages(context)
	var system_content := String((messages[0] as Dictionary).get("content", ""))
	assert(String(context.get("current_question", "")) == "发表遗言。")
	assert(system_content.contains("遗言是全局可见的。"))


func _assert_current_questions_are_simple(builder, input: Dictionary) -> void:
	var contexts := [
		builder.wolf_chat_context(input, 0, {}),
		builder.action_context(input, 0, "wolf_kill", {}),
		builder.action_context(input, 1, "seer_check", {}),
		builder.action_context(_witch_input(input), 3, "witch_act", {}),
		builder.action_context(input, 4, "guard_protect", {}),
		builder.action_context(input, 0, "sheriff_vote", {}),
		builder.action_context(input, 0, "sheriff_speech_order", {}),
		builder.action_context(input, 0, "sheriff_badge_action", {}),
		builder.action_context(input, 0, "vote", {}),
		builder.action_context(input, 0, "hunter_shoot", {}),
		builder.action_context(input, 0, "mvp_vote", {}),
		builder.speech_context(input, 0, {}),
	]
	var campaign_input: Dictionary = input.duplicate(true)
	(campaign_input["werewolf"] as Dictionary)["phase"] = "sheriff_speech"
	contexts.append(builder.speech_context(campaign_input, 0, {}))
	var last_words_input: Dictionary = input.duplicate(true)
	(last_words_input["werewolf"] as Dictionary)["phase"] = "last_words"
	contexts.append(builder.speech_context(last_words_input, 0, {}))
	var summary_input: Dictionary = input.duplicate(true)
	(summary_input["werewolf"] as Dictionary)["phase"] = "post_game_summary"
	contexts.append(builder.speech_context(summary_input, 0, {}))

	for context in contexts:
		var question := String((context as Dictionary).get("current_question", "")).strip_edges()
		assert(question != "")
		assert(question.length() <= 20)
		assert(not question.contains("结合"))
		assert(not question.contains("必须"))
		assert(not question.contains("不能"))
		assert(not question.contains("不要"))
		assert(not question.contains("如果"))
		assert(not question.contains("；"))


func _input() -> Dictionary:
	return {
		"room_id": "room_prompt_snapshot",
		"werewolf": {
			"phase": "wolf_action",
			"day": 1,
			"map_name": "标准村庄",
			"has_sheriff": false,
			"votes": {},
			"night": {"wolf_target_index": 2},
			"current_action": {"key": "wolf_kill", "actor_index": 0, "label": "刀人"},
			"last_guarded_index": 5,
			"witch_antidote": true,
			"witch_poison": true,
			"post_game": {"stage": ""},
		},
		"players": [
			_player("wolf_a", "甲", "wolf"),
			_player("seer_b", "乙", "seer"),
			_player("villager_c", "丙", "villager"),
			_player("witch_d", "丁", "witch"),
			_player("guard_e", "戊", "guard"),
			_player("wolf_f", "己", "wolf"),
		],
		"history": [
			{"speaker": "主持人", "text": "第1夜开始。", "at": 1.0},
			{"speaker": "主持人", "text": "黑夜降临，请狼队按座位顺序发言。 当前由 1号 甲 发言。", "at": 2.0},
		],
		"wolf_private_history": [
			{
				"speaker": "1号 甲",
				"text": "我倾向今晚先刀3号位。",
				"actor_index": 0,
				"actor_id": "wolf_a",
				"day": 1,
				"phase": "wolf_action",
				"at": 3.0,
			},
		],
		"wolf_target_votes": {},
		"wolf_speech_count": 1,
		"max_wolf_night_chat_messages": 3,
		"phase_label": "狼人行动",
		"map_rule_text": "【标准村庄 6人局】\n身份配置：狼人2、预言家1、女巫1、守卫1、村民1。\n夜晚流程：狼人夜间共同选择袭击目标；预言家每夜查验一名玩家阵营；女巫可救人或毒人；守卫可守护一名玩家。\n白天流程：按座位顺序发言，发言结束后投票放逐一名玩家。\n胜利条件：狼人全部出局，好人胜利；所有好人全部出局，狼人胜利。",
	}


func _witch_input(input: Dictionary) -> Dictionary:
	var result: Dictionary = input.duplicate(true)
	var werewolf: Dictionary = result["werewolf"] as Dictionary
	werewolf["phase"] = "witch_action"
	werewolf["current_action"] = {"key": "witch_act", "actor_index": 3, "label": "用药"}
	werewolf["night"] = {"wolf_target_index": 2}
	werewolf["witch_antidote"] = true
	werewolf["witch_poison"] = true
	result["phase_label"] = "女巫行动"
	return result


func _player(id: String, name: String, role_key: String) -> Dictionary:
	var role_names := {
		"wolf": "狼人",
		"seer": "预言家",
		"witch": "女巫",
		"guard": "守卫",
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
