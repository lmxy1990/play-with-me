extends RefCounted

const PromptPolicyScript := preload("res://scripts/player/werewolf/ai/ai_werewolf_prompt_policy.gd")
const RoleCatalogScript := preload("res://scripts/room/werewolf/werewolf_role_catalog.gd")

const SPEECH_ACTIONS := ["speak", "wolf_chat", "last_words", "post_game_summary"]
const TARGET_ACTIONS := [
	"wolf_kill",
	"seer_check",
	"guard_protect",
	"witch_act",
	"sheriff_vote",
	"sheriff_speech_order",
	"sheriff_speech_order_clockwise",
	"sheriff_speech_order_counterclockwise",
	"sheriff_badge_action",
	"sheriff_badge_pass",
	"witch_save",
	"witch_poison",
	"vote",
	"mvp_vote",
	"hunter_shoot",
]
const NO_TARGET_ACTIONS := ["witch_skip", "skip", "sheriff_badge_destroy"]
const SKIPPABLE_TARGET_ACTIONS := ["witch_act", "hunter_shoot", "sheriff_badge_action"]

var _role_catalog = RoleCatalogScript.new()


func build_messages(context: Dictionary) -> Array:
	return [
		{"role": "system", "content": system_prompt(context)},
		{"role": "user", "content": user_prompt(context)},
	]


func system_prompt(context: Dictionary = {}) -> String:
	var visible_state := _as_dict(context.get("visible_state", {}))
	var bot_id := String(context.get("bot_id", ""))
	var lines := []
	lines.append_array(_identity_prompt_lines(visible_state, bot_id))
	lines.append_array(_current_state_prompt_lines(visible_state))
	lines.append_array(_game_rule_prompt_lines(visible_state))
	lines.append_array(_user_input_format_prompt_lines())
	if _is_single_speech_context(context):
		lines.append_array(_speech_output_format_prompt_lines())
	elif _is_action_context(context):
		lines.append_array(_action_output_format_prompt_lines(context))
	return "\n".join(lines)


func _identity_prompt_lines(visible_state: Dictionary, bot_id: String) -> Array:
	var self_player := _player_by_id(visible_state, bot_id)
	var script_summary := _as_dict(visible_state.get("scriptSummary", {}))
	var game_name := String(script_summary.get("gameName", script_summary.get("name", "狼人杀"))).strip_edges()
	if game_name == "":
		game_name = "狼人杀"
	var self_name := String(self_player.get("displayName", "")).strip_edges()
	if self_name == "":
		self_name = "AI玩家"
	var seat_number := _int_or_minus_one(self_player.get("seatNumber", -1))
	var seat_text := "%d号" % seat_number if seat_number > 0 else "未知座位号"
	var role_text := _role_label_from_value(visible_state.get("myRole", ""))
	return [
		"你正在参与%s。你是%s，座位号%s，身份：%s。" % [game_name, self_name, seat_text, role_text],
	]


func _game_rule_prompt_lines(visible_state: Dictionary) -> Array:
	var rule_text := String(visible_state.get("ruleSummary", "")).strip_edges()
	if rule_text == "":
		rule_text = "按当前房间模块下发的地图规则推进。"
	return [
		"游戏规则：%s" % rule_text,
	]


func _current_state_prompt_lines(visible_state: Dictionary) -> Array:
	var phase_label := String(visible_state.get("phaseLabel", "")).strip_edges()
	var parts := [_current_state_text(visible_state)]
	if phase_label != "":
		parts.append("阶段：%s" % phase_label)
	return [
		"当前状态：%s。" % "；".join(parts),
	]


func _user_input_format_prompt_lines() -> Array:
	return [
		"输入：user 是 JSON；current_question 是问题；current_state/players/timeline/memoryHints 是资料；targetOptions 是合法目标座位号数组。只依据输入，未知不编。",
	]


func _speech_output_format_prompt_lines() -> Array:
	return [
		"输出：直接返回发言文本，不要 JSON。建议回复在120字以内。",
	]


func _action_output_format_prompt_lines(context: Dictionary) -> Array:
	var allowed_actions := _string_array(context.get("allowed_actions", []))
	var action_value := String(allowed_actions[0]) if allowed_actions.size() == 1 else ""
	var target_rule := _target_rule_text(allowed_actions)
	var target_suffix := "；%s" % target_rule if target_rule != "" else ""
	if action_value == "sheriff_speech_order":
		return [
			"输出：只返回 {\"action\":\"sheriff_speech_order\",\"targetSeatNumber\":数字,\"direction\":\"clockwise|counterclockwise\"}。action 表示本次行动：%s，固定填 sheriff_speech_order；targetSeatNumber 从 user.targetOptions 选；direction 选 clockwise 顺时针或 counterclockwise 逆时针。" % _action_label(action_value),
		]
	if action_value != "":
		return [
			"输出：只返回 {\"action\":\"%s\",\"targetSeatNumber\":数字}。action 表示本次行动：%s，固定填 %s；targetSeatNumber 从 user.targetOptions 选%s。" % [action_value, _action_label(action_value), action_value, target_suffix],
		]
	var action_texts := []
	for action in allowed_actions:
		action_texts.append("%s=%s" % [String(action), _action_label(String(action))])
	return [
		"输出：只返回 {\"action\":\"...\",\"targetSeatNumber\":数字}。action 表示本次行动，从 [%s] 选；targetSeatNumber 从 user.targetOptions 选%s。" % [", ".join(action_texts), target_suffix],
	]


func _action_label(action: String) -> String:
	match action:
		"wolf_kill":
			return "狼队击杀"
		"seer_check":
			return "预言家查验"
		"guard_protect":
			return "守卫守护"
		"sheriff_vote":
			return "警长竞选投票"
		"sheriff_speech_order":
			return "警长指定白天发言起点和方向"
		"sheriff_speech_order_clockwise":
			return "从目标座位开始顺时针发言"
		"sheriff_speech_order_counterclockwise":
			return "从目标座位开始逆时针发言"
		"sheriff_badge_action":
			return "警长死亡后处理警徽"
		"sheriff_badge_pass":
			return "飞警徽给目标"
		"sheriff_badge_destroy":
			return "撕警徽"
		"witch_save":
			return "救今晚被袭击玩家"
		"witch_poison":
			return "毒目标玩家"
		"witch_skip":
			return "不用药"
		"vote":
			return "白天放逐投票"
		"mvp_vote":
			return "赛后MVP投票"
		"hunter_shoot":
			return "猎人开枪或不开枪"
		"skip":
			return "不行动"
		_:
			return action


func _target_rule_text(allowed_actions: Array) -> String:
	if allowed_actions.has("witch_save"):
		return "今晚被袭击座位表示救人"
	if allowed_actions.has("witch_poison"):
		return "目标表示毒人"
	if allowed_actions.has("witch_act"):
		return "-1 表示不用药；今晚被袭击座位表示救人；其他合法座位表示毒人"
	if allowed_actions.has("sheriff_badge_destroy"):
		return "-1 表示撕警徽"
	if allowed_actions.has("sheriff_badge_action"):
		return "-1 表示撕警徽；其他座位表示飞警徽给该玩家"
	if allowed_actions.has("witch_skip"):
		return "-1 表示不用药"
	if allowed_actions.has("skip"):
		return "-1 表示不行动"
	if allowed_actions.has("hunter_shoot"):
		return "-1 表示不开枪"
	return ""


func _is_single_speech_context(context: Dictionary) -> bool:
	var allowed_actions := _string_array(context.get("allowed_actions", []))
	return allowed_actions.size() == 1 and SPEECH_ACTIONS.has(String(allowed_actions[0]))


func _is_public_speech_context(context: Dictionary) -> bool:
	var allowed_actions := _string_array(context.get("allowed_actions", []))
	return allowed_actions.size() == 1 and String(allowed_actions[0]) == "speak"


func _is_sheriff_campaign_context(context: Dictionary) -> bool:
	var visible_state := _as_dict(context.get("visible_state", {}))
	return _is_public_speech_context(context) and String(visible_state.get("phase", "")) == "sheriff_speech"


func _is_action_context(context: Dictionary) -> bool:
	var allowed_actions := _string_array(context.get("allowed_actions", []))
	return not allowed_actions.is_empty() and not _is_single_speech_context(context)


func _is_sheriff_speech_order_context(context: Dictionary) -> bool:
	var allowed_actions := _string_array(context.get("allowed_actions", []))
	return allowed_actions.has("sheriff_speech_order_clockwise") or allowed_actions.has("sheriff_speech_order_counterclockwise")


func _is_sheriff_badge_context(context: Dictionary) -> bool:
	var allowed_actions := _string_array(context.get("allowed_actions", []))
	return allowed_actions.has("sheriff_badge_pass") or allowed_actions.has("sheriff_badge_destroy")


func user_prompt(context: Dictionary) -> String:
	return JSON.stringify(_context_payload(context, true), "\t")


func to_model_payload(context: Dictionary) -> Dictionary:
	return _context_payload(context, true)


func _context_payload(context: Dictionary, include_question: bool) -> Dictionary:
	var bot_id := String(context.get("bot_id", ""))
	var visible_state := _as_dict(context.get("visible_state", {}))
	var memory_hints := _model_memory_hints(_as_dict(context.get("memory_hints", {})), visible_state)
	var payload := {
		"current_question": String(context.get("current_question", "")),
		"current_state": _current_state_payload_text(visible_state),
		"players": _model_players(visible_state, bot_id),
		"timeline": _model_timeline_texts(visible_state),
	}
	if not memory_hints.is_empty():
		payload["memoryHints"] = memory_hints
	var target_seat_numbers := target_seat_number_options_for_context(context)
	if not target_seat_numbers.is_empty():
		payload["targetOptions"] = target_seat_numbers
	return payload


func target_options_for_context(context: Dictionary) -> Array:
	var bot_id := String(context.get("bot_id", ""))
	var visible_state := _as_dict(context.get("visible_state", {}))
	var allowed_actions := _string_array(context.get("allowed_actions", []))
	return _model_target_options(visible_state, bot_id, allowed_actions)


func target_seat_number_options_for_context(context: Dictionary) -> Array:
	var result := []
	for option in target_options_for_context(context):
		if not (option is Dictionary):
			continue
		var seat_number := _int_or_minus_one((option as Dictionary).get("targetSeatNumber", -1))
		if seat_number > 0 and not result.has(seat_number):
			result.append(seat_number)
	for action in _string_array(context.get("allowed_actions", [])):
		if (NO_TARGET_ACTIONS.has(action) or SKIPPABLE_TARGET_ACTIONS.has(action)) and not result.has(-1):
			result.push_front(-1)
	result.sort()
	return result


func _current_state_text(state: Dictionary) -> String:
	var day := _int_or_minus_one(state.get("dayNumber", 0))
	if day <= 0:
		day = 1
	var phase := String(state.get("phase", ""))
	var label := String(state.get("phaseLabel", ""))
	if phase in ["sheriff_speech", "sheriff_vote"] and day <= 1:
		return "第1天白天（首夜前，无夜间技能结果）"
	if phase in ["wolf_chat", "wolf_action", "guard_action", "seer_action", "witch_action"] or label.contains("夜"):
		return "第%d夜晚上" % day
	if phase in ["game_over", "post_game_summary", "mvp_vote", "completed"]:
		return "第%d天结束" % day
	return "第%d天白天" % day


func _current_state_payload_text(state: Dictionary) -> String:
	var parts := [_current_state_text(state)]
	var phase_label := String(state.get("phaseLabel", "")).strip_edges()
	if phase_label != "":
		parts.append("阶段：%s" % phase_label)
	parts.append_array(_sanitized_state_facts(state))
	parts.append_array(_private_state_lines(state))
	var wolf_summary := _known_wolf_summary(state)
	if wolf_summary != "":
		parts.append(wolf_summary)
	var clean_parts := []
	for part in parts:
		var text := _strip_trailing_period(String(part).strip_edges())
		if text != "" and not clean_parts.has(text):
			clean_parts.append(text)
	return "；".join(clean_parts)


func _sanitized_state_facts(state: Dictionary) -> Array:
	var result := []
	for fact in _sanitized_string_array(state.get("facts", []), state):
		var text := String(fact)
		if text.contains("尚未进入首夜") and _current_state_text(state).contains("首夜前"):
			continue
		result.append(text)
	return result


func _private_state_lines(state: Dictionary) -> Array:
	var private_info := _as_dict(state.get("privateInfo", {}))
	var result := []
	var checks := _as_dict(private_info.get("checks", {}))
	if not checks.is_empty():
		var check_texts := []
		for target_id in checks.keys():
			check_texts.append("%s是%s" % [_model_player_label(state, String(target_id)), String(checks[target_id])])
		check_texts.sort()
		result.append("查验结果：%s" % "，".join(check_texts))
	var last_guarded_id := String(private_info.get("lastGuardedPlayerId", "")).strip_edges()
	if last_guarded_id != "":
		result.append("上次守护：%s" % _model_player_label(state, last_guarded_id))
	var killed_id := String(private_info.get("tonightKilledPlayerId", "")).strip_edges()
	if killed_id != "":
		result.append("今晚被袭击：%s" % _model_player_label(state, killed_id))
	if private_info.has("antidoteAvailable"):
		result.append("解药：%s" % ("可用" if bool(private_info.get("antidoteAvailable", false)) else "已用"))
	if private_info.has("poisonAvailable"):
		result.append("毒药：%s" % ("可用" if bool(private_info.get("poisonAvailable", false)) else "已用"))
	return result


func _known_wolf_summary(state: Dictionary) -> String:
	var labels := []
	for id in _string_array(state.get("knownWolfIds", [])):
		labels.append(_model_player_label(state, id))
	if labels.is_empty():
		return ""
	labels.sort()
	return "已知狼队友：%s" % "，".join(labels)


func _model_players(state: Dictionary, bot_id: String) -> Array:
	var known_wolf_ids := _string_array(state.get("knownWolfIds", []))
	var result := []
	for player in _players(state):
		var player_id := String(player.get("playerId", ""))
		var entry := {
			"alive": bool(player.get("alive", true)),
			"displayName": String(player.get("displayName", "")),
			"role": _visible_role_for_player(player, player_id, bot_id, known_wolf_ids),
			"seatNumber": player.get("seatNumber"),
		}
		if player.has("voteCount"):
			entry["voteCount"] = int(player.get("voteCount", 0))
		if bool(player.get("nightTargeted", false)):
			entry["nightTargeted"] = true
		result.append(entry)
	return result


func _visible_role_for_player(player: Dictionary, player_id: String, bot_id: String, known_wolf_ids: Array) -> String:
	var revealed := String(player.get("revealedRole", "")).strip_edges()
	if revealed != "":
		return _role_label_from_value(revealed)
	if player_id != "" and player_id == bot_id:
		return _role_label_from_value(player.get("revealedRole", ""))
	if player_id != "" and known_wolf_ids.has(player_id):
		return "狼人"
	return "未知"


func _model_timeline_texts(state: Dictionary) -> Array:
	var result := []
	for event in _events(state.get("timeline", [])):
		var description := String(event.get("speechText", event.get("description", ""))).strip_edges()
		if description == "":
			continue
		var speaker := _timeline_speaker(event, state)
		result.append("%s:%s" % [speaker, _sanitize_text_ids(description, state)])
	return result


func _timeline_speaker(event: Dictionary, state: Dictionary) -> String:
	var actor_id := String(event.get("actorId", ""))
	if actor_id != "":
		var player := _player_by_id(state, actor_id)
		var seat := _int_or_minus_one(player.get("seatNumber", -1))
		if seat > 0:
			return "%d号" % seat
	var type := String(event.get("type", ""))
	if type == "wolf_spoke":
		return "狼队"
	return "主持人"


func _model_memory_hints(memory_hints: Dictionary, state: Dictionary) -> Dictionary:
	if not bool(PromptPolicyScript.include_memory_hints):
		return {}
	var result := {}
	var relevant := _sanitized_string_array(memory_hints.get("relevantMemory", []), state)
	if not relevant.is_empty():
		result["relevantMemory"] = relevant
	var summaries := _sanitized_string_array(memory_hints.get("roundSummaries", []), state)
	if not summaries.is_empty():
		result["roundSummaries"] = summaries
	var long_term := String(memory_hints.get("longTermSummary", "")).strip_edges()
	if long_term != "":
		result["longTermSummary"] = _sanitize_text_ids(long_term, state)
	return result


func _model_target_options(state: Dictionary, bot_id: String, allowed_actions: Array) -> Array:
	if allowed_actions.size() == 1 and SPEECH_ACTIONS.has(String(allowed_actions[0])):
		return []
	if not _actions_require_model_target_selection(allowed_actions):
		return []
	var result := []
	for player in _players(state):
		var player_id := String(player.get("playerId", ""))
		if player_id == "":
			continue
		var target_actions := _target_actions_for_option(player, state, bot_id, allowed_actions)
		if target_actions.is_empty():
			continue
		var entry := {
			"targetSeatNumber": player.get("seatNumber"),
			"targetName": player.get("displayName"),
			"targetLabel": _player_label(player),
			"targetActions": target_actions,
		}
		if player.has("revealedRole") and String(player.get("revealedRole", "")).strip_edges() != "":
			entry["targetRole"] = _role_label_from_value(player.get("revealedRole"))
		result.append(entry)
	return result


func _actions_require_model_target_selection(allowed_actions: Array) -> bool:
	for action_value in allowed_actions:
		var action := String(action_value)
		if TARGET_ACTIONS.has(action) or SKIPPABLE_TARGET_ACTIONS.has(action):
			return true
	return false


func _target_actions_for_option(player: Dictionary, state: Dictionary, bot_id: String, allowed_actions: Array) -> Array:
	var player_id := String(player.get("playerId", ""))
	var result := []
	var include_all := allowed_actions.has("mvp_vote")
	if not include_all and not bool(player.get("alive", true)):
		return result
	if allowed_actions.has("guard_protect"):
		if player_id != _last_guarded_player_id(state):
			result.append("guard_protect")
	if allowed_actions.has("wolf_kill"):
		if player_id != bot_id and not _string_array(state.get("knownWolfIds", [])).has(player_id):
			result.append("wolf_kill")
	if allowed_actions.has("witch_save") or allowed_actions.has("witch_poison") or allowed_actions.has("witch_act"):
		var private_info := _as_dict(state.get("privateInfo", {}))
		var killed := String(private_info.get("tonightKilledPlayerId", ""))
		var can_save := bool(private_info.get("antidoteAvailable", false))
		var can_poison := bool(private_info.get("poisonAvailable", false))
		if (allowed_actions.has("witch_save") or allowed_actions.has("witch_act")) and can_save and player_id == killed:
			result.append("witch_save")
		if (allowed_actions.has("witch_poison") or allowed_actions.has("witch_act")) and can_poison and player_id != bot_id and not (can_save and player_id == killed):
			result.append("witch_poison")
	if include_all:
		result.append("mvp_vote")
	for action_value in allowed_actions:
		var action := String(action_value)
		if action in ["guard_protect", "wolf_kill", "witch_save", "witch_poison", "witch_act", "mvp_vote", "witch_skip", "skip"]:
			continue
		var allow_self_target := action in ["sheriff_vote", "sheriff_speech_order", "sheriff_speech_order_clockwise", "sheriff_speech_order_counterclockwise"]
		if TARGET_ACTIONS.has(action) and (allow_self_target or player_id != bot_id):
			result.append(action)
	var unique := []
	for action_value in result:
		var action := String(action_value)
		if action != "" and not unique.has(action):
			unique.append(action)
	return unique


func _last_guarded_player_id(state: Dictionary) -> String:
	return String(_as_dict(state.get("privateInfo", {})).get("lastGuardedPlayerId", ""))


func _model_player_label(state: Dictionary, player_id: String) -> String:
	for player in _players(state):
		if String(player.get("playerId", "")) == player_id:
			return _player_label(player)
	return "未知玩家"


func _player_by_id(state: Dictionary, player_id: String) -> Dictionary:
	for player in _players(state):
		if String(player.get("playerId", "")) == player_id:
			return player
	return {}


func _player_label(player: Dictionary) -> String:
	var seat_number := _int_or_minus_one(player.get("seatNumber", -1))
	var display_name := String(player.get("displayName", "")).strip_edges()
	if seat_number > 0 and display_name != "":
		return "%d号位 %s" % [seat_number, display_name]
	if seat_number > 0:
		return "%d号位" % seat_number
	if display_name != "":
		return display_name
	return "未知玩家"


func _role_label_from_value(value) -> String:
	var role := String(value).strip_edges()
	if role == "" or role == "<null>":
		return "未知身份"
	return _role_catalog.role_label(role)


func _sanitize_text_ids(text: String, state: Dictionary) -> String:
	var result := text
	for player in _players(state):
		var player_id := String(player.get("playerId", ""))
		if player_id != "":
			result = result.replace(player_id, _player_label(player))
	var regex := RegEx.new()
	if regex.compile("\\bplayer_\\d+\\b") == OK:
		result = regex.sub(result, "某玩家", true)
	return result


func _strip_trailing_period(text: String) -> String:
	var result := text
	while result.ends_with("。") or result.ends_with("."):
		result = result.substr(0, result.length() - 1).strip_edges()
	return result


func _sanitized_string_array(value, state: Dictionary) -> Array:
	var result := []
	if not (value is Array):
		return result
	for item in value:
		result.append(_sanitize_text_ids(String(item), state))
	return result


func _string_array(value) -> Array:
	var result := []
	if not (value is Array):
		return result
	for item in value:
		result.append(String(item))
	return result


func _players(state: Dictionary) -> Array:
	var value = state.get("players", [])
	var result := []
	if not (value is Array):
		return result
	for player in value:
		if player is Dictionary:
			result.append(player)
	return result


func _events(value) -> Array:
	var result := []
	if not (value is Array):
		return result
	for event in value:
		if event is Dictionary:
			result.append(event)
	return result


func _as_dict(value) -> Dictionary:
	if value is Dictionary:
		return value
	return {}


func _int_or_minus_one(value) -> int:
	if value is int:
		return int(value)
	if value is float:
		return int(value)
	if value is String:
		var text := String(value).strip_edges()
		if text.is_valid_int():
			return int(text.to_int())
	return -1
