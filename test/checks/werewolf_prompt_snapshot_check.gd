extends SceneTree

const BuilderScript := preload("res://scripts/room/werewolf/player/ai_robot/ai_werewolf_turn_context_builder.gd")
const RuntimeScript := preload("res://scripts/room/werewolf/player/ai_robot/ai_werewolf_player_runtime.gd")


func _initialize() -> void:
	var builder = BuilderScript.new()
	var runtime = RuntimeScript.new()
	var input := _input()

	_assert_contract(runtime, builder.wolf_chat_context(input, 0, {}), "狼人", false, "当前是狼人夜晚沟通阶段。")
	_assert_contract(runtime, builder.action_context(input, 0, "wolf_kill", {}), "狼人", true, "选择今晚击杀目标")
	_assert_contract(runtime, builder.action_context(input, 1, "seer_check", {}), "预言家", true, "当前是预言家查验。")
	_assert_contract(runtime, builder.action_context(input, 3, "witch_act", {}), "女巫", true, "当前是女巫行动。")
	_assert_contract(runtime, builder.action_context(input, 4, "guard_protect", {}), "守卫", true, "当前是守卫行动。")

	quit()


func _assert_contract(runtime, context: Dictionary, role_label: String, expects_schema: bool, question_fragment: String) -> void:
	var messages: Array = runtime.build_messages(context)
	var system_content := String((messages[0] as Dictionary).get("content", ""))
	var user_content := String((messages[1] as Dictionary).get("content", ""))
	var payload = JSON.parse_string(user_content)
	assert(payload is Dictionary)
	var user_payload: Dictionary = payload
	var question := String(user_payload.get("current_question", ""))

	assert(system_content.contains("[游戏规则]"))
	assert(system_content.contains("[用户输入格式]"))
	assert(system_content.contains("[要求]"))
	assert(system_content.contains("你当前的身份是%s" % role_label))
	if expects_schema:
		assert(not system_content.contains("[输出格式]"))
		assert(not system_content.contains("建议发言控制在120字以内"))
	else:
		assert(system_content.contains("[输出格式]"))
		assert(system_content.contains("纯文本。不要 JSON"))
		assert(system_content.contains("不要返回 {\"content\":...}"))
		assert(system_content.contains("建议发言控制在120字以内"))
	assert(not system_content.contains("只输出 JSON"))
	assert(not system_content.contains("outputFormat"))
	assert(not system_content.contains("confidence"))
	assert(not system_content.contains("只包含 current_question"))
	assert(system_content.contains("targetOptions 当前动作可选的合法目标列表"))
	var response_schema: Dictionary = runtime.response_schema_for_context(context)
	if expects_schema:
		assert(not response_schema.is_empty())
		assert(response_schema.has("schema"))
	else:
		assert(response_schema.is_empty())

	assert(user_payload.size() == (6 if expects_schema else 5))
	assert(user_payload.has("current_question"))
	assert(user_payload.has("memoryHints"))
	assert(user_payload.has("current_state"))
	assert(user_payload.has("players"))
	assert(user_payload.has("timeline"))
	assert(not user_payload.has("outputFormat"))
	assert(user_payload.has("targetOptions") == expects_schema)
	if expects_schema:
		assert(user_payload.get("targetOptions", []) is Array)
		assert((user_payload["targetOptions"] as Array).size() > 0)
	assert(question.contains(question_fragment))
	assert(not question.contains("返回 action"))
	assert(not question.contains("只返回"))
	assert(not question.contains("只输出"))


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
