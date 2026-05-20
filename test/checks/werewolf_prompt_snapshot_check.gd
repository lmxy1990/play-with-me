extends SceneTree

const BuilderScript := preload("res://scripts/room/werewolf/player/ai_robot/ai_werewolf_turn_context_builder.gd")
const RuntimeScript := preload("res://scripts/room/werewolf/player/ai_robot/ai_werewolf_player_runtime.gd")


func _initialize() -> void:
	var builder = BuilderScript.new()
	var runtime = RuntimeScript.new()
	var input := _input()

	_assert_contract(runtime, builder.wolf_chat_context(input, 0, {}), "狼人", false, "发表狼队夜聊。")
	_assert_contract(runtime, builder.action_context(input, 0, "wolf_kill", {}), "狼人", true, "选择今晚狼队击杀目标。")
	_assert_contract(runtime, builder.action_context(input, 1, "seer_check", {}), "预言家", true, "选择今晚查验目标。")
	_assert_contract(runtime, builder.action_context(input, 3, "witch_act", {}), "女巫", true, "选择救人、毒人或跳过。")
	_assert_contract(runtime, builder.action_context(input, 4, "guard_protect", {}), "守卫", true, "选择今晚守护目标。")
	_assert_sheriff_campaign_contract(runtime, builder, input)
	_assert_current_questions_are_simple(builder, input)

	quit()


func _assert_contract(runtime, context: Dictionary, role_label: String, expects_schema: bool, question_fragment: String) -> void:
	var messages: Array = runtime.build_messages(context)
	var system_content := String((messages[0] as Dictionary).get("content", ""))
	var user_content := String((messages[1] as Dictionary).get("content", ""))
	var user_payload: Dictionary = runtime.to_model_payload(context)
	var question := String(user_payload.get("current_question", ""))

	assert(system_content.contains("[游戏规则]"))
	assert(system_content.contains("[当前状态]"))
	assert(system_content.contains("[游戏上下文]"))
	assert(system_content.contains("[原则]"))
	assert(system_content.contains("你当前的身份是%s" % role_label))
	assert(system_content.contains("current_state"))
	assert(system_content.contains("allowedActions"))
	if expects_schema:
		assert(system_content.contains("targetOptions"))
		assert(system_content.contains("[行动含义]"))
		assert(system_content.contains("[输出格式]"))
		assert(system_content.contains("只返回一个 JSON 对象"))
		assert(system_content.contains("JSON 只能包含 action 和 targetSeatNumber 两个字段"))
		assert(system_content.contains("targetSeatNumber 必须是 JSON number/integer"))
	else:
		assert(system_content.contains("[输出格式]"))
		assert(system_content.contains("直接输出发言文本"))
	assert(not system_content.contains("只输出 JSON"))
	assert(not system_content.contains("outputFormat"))
	assert(not system_content.contains("confidence"))
	assert(not system_content.contains("[用户输入格式]"))
	assert(not system_content.contains("[要求]"))
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
	assert(user_payload.has("allowedActions"))
	assert(user_payload.has("players"))
	assert(user_payload.has("timeline"))
	assert(not user_payload.has("outputFormat"))
	assert(user_payload.has("targetOptions") == expects_schema)
	if expects_schema:
		assert(user_payload.get("targetOptions", []) is Array)
		assert((user_payload["targetOptions"] as Array).size() > 0)
	assert(question.contains(question_fragment))
	assert(user_content == question)
	assert(not user_content.begins_with("{"))
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
	assert(system_content.contains("[当前状态]"))
	assert(system_content.contains("第1天白天（首夜前）"))
	assert(system_content.contains("警长竞选发言"))
	assert(system_content.contains("[游戏上下文]"))
	assert(not system_content.contains("[公开发言边界]"))
	assert(not system_content.contains("[警长竞选边界]"))
	assert(question == "发表警长竞选发言。")
	assert(user_content == question)
	assert(String(payload.get("current_state", "")).contains("首夜前"))


func _assert_current_questions_are_simple(builder, input: Dictionary) -> void:
	var contexts := [
		builder.wolf_chat_context(input, 0, {}),
		builder.action_context(input, 0, "wolf_kill", {}),
		builder.action_context(input, 1, "seer_check", {}),
		builder.action_context(input, 3, "witch_act", {}),
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
