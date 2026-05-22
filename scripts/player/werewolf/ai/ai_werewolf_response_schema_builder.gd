extends RefCounted

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


func response_schema_for_context(context: Dictionary) -> Dictionary:
	var actions := _string_array(context.get("allowed_actions", []))
	if actions.is_empty() or _is_single_speech_action(actions):
		return {}
	var target_seats := _target_seat_numbers_for_actions(context, actions)
	var needs_target := _actions_need_target(actions)
	var schema := {
		"type": "object",
		"additionalProperties": false,
		"properties": {
			"action": {
				"type": "string",
				"enum": actions,
				"description": _action_description(actions),
			},
		},
		"required": ["action"],
	}
	if needs_target:
		var target_schema := {
			"type": "integer",
			"description": _target_description(context, actions),
		}
		var allowed_target_seats := target_seats.duplicate()
		if not allowed_target_seats.is_empty():
			target_schema["enum"] = allowed_target_seats
		(schema["properties"] as Dictionary)["targetSeatNumber"] = target_schema
		(schema["required"] as Array).append("targetSeatNumber")
	if actions.has("sheriff_speech_order"):
		(schema["properties"] as Dictionary)["direction"] = {
			"type": "string",
			"enum": ["clockwise", "counterclockwise"],
			"description": "发言方向。clockwise 表示顺时针，counterclockwise 表示逆时针。",
		}
		(schema["required"] as Array).append("direction")
	return {
		"name": _schema_name(actions),
		"strict": true,
		"schema": schema,
	}


func request_options_for_context(context: Dictionary) -> Dictionary:
	var actions := _string_array(context.get("allowed_actions", []))
	if _is_single_speech_action(actions):
		return {
			"output_type": "text",
			"output_adapter": "none",
		}
	var schema := response_schema_for_context(context)
	if schema.is_empty():
		return {}
	return {
		"output_type": "json",
		"response_schema": schema,
	}


func _schema_name(actions: Array) -> String:
	var parts := []
	for action in actions:
		var clean := String(action).strip_edges().to_lower()
		if clean == "":
			continue
		parts.append(clean.replace("-", "_"))
	if parts.is_empty():
		parts.append("action")
	return "werewolf_%s_v1" % "_".join(parts)


func _action_description(actions: Array) -> String:
	if actions.size() == 1:
		return "本次行动：%s。固定值。" % _action_label(String(actions[0]))
	return "本次行动。只选 enum 值。"


func _action_label(action: String) -> String:
	match action:
		"wolf_kill":
			return "狼队击杀"
		"seer_check":
			return "预言家查验"
		"guard_protect":
			return "守卫守护"
		"witch_act":
			return "女巫用药"
		"sheriff_vote":
			return "警长竞选投票"
		"sheriff_speech_order":
			return "警长指定白天发言起点和方向"
		"sheriff_badge_action":
			return "警长死亡后处理警徽"
		"vote":
			return "白天放逐投票"
		"mvp_vote":
			return "赛后 MVP 投票"
		"hunter_shoot":
			return "猎人开枪或不开枪"
		_:
			return action


func _target_description(context: Dictionary, actions: Array) -> String:
	if actions.has("sheriff_vote"):
		return "警长投票目标座位号。"
	if actions.has("vote"):
		return "放逐投票目标座位号。"
	if actions.has("wolf_kill"):
		return "狼队击杀目标座位号。"
	if actions.has("seer_check"):
		return "查验目标座位号。"
	if actions.has("guard_protect"):
		return "守护目标座位号。"
	if actions.has("witch_act"):
		return _witch_act_target_description(context)
	if actions.has("hunter_shoot"):
		return "目标座位号。-1 表示不开枪。"
	if actions.has("sheriff_speech_order"):
		return "发言起点座位号。"
	if actions.has("sheriff_badge_action"):
		return "目标座位号。-1 表示撕警徽。"
	if actions.has("mvp_vote"):
		return "MVP 投票目标座位号。"
	return "目标座位号。"


func _witch_act_target_description(context: Dictionary) -> String:
	var has_save := false
	var has_poison := false
	for option in _target_options(context):
		var target_actions := _string_array((option as Dictionary).get("targetActions", []))
		has_save = has_save or target_actions.has("witch_save")
		has_poison = has_poison or target_actions.has("witch_poison")
	if has_save and has_poison:
		return "女巫用药选择。-1 表示不用药；今晚被袭击座位表示使用解药；其它合法座位表示使用毒药。"
	if has_save:
		return "女巫用药选择。-1 表示不使用解药；今晚被袭击座位表示使用解药。"
	if has_poison:
		return "女巫用药选择。-1 表示不使用毒药；其它合法座位表示使用毒药。"
	return "女巫用药选择。-1 表示不用药。"


func _is_single_speech_action(actions: Array) -> bool:
	return actions.size() == 1 and SPEECH_ACTIONS.has(String(actions[0]))


func _actions_need_target(actions: Array) -> bool:
	for action_value in actions:
		if TARGET_ACTIONS.has(String(action_value)):
			return true
	return false


func _actions_have_no_target(actions: Array) -> bool:
	for action_value in actions:
		var action := String(action_value)
		if NO_TARGET_ACTIONS.has(action) or SKIPPABLE_TARGET_ACTIONS.has(action):
			return true
	return false


func _target_seat_numbers_for_actions(context: Dictionary, actions: Array) -> Array:
	var result := []
	for action_value in actions:
		var action_seats := _target_seat_numbers_for_action(context, String(action_value))
		for seat in action_seats:
			if not result.has(seat):
				result.append(seat)
	if _actions_have_no_target(actions) and not result.has(-1):
		result.push_front(-1)
	result.sort()
	return result


func _target_seat_numbers_for_action(context: Dictionary, action: String) -> Array:
	var result := []
	for option in _target_options(context):
		var option_dict := option as Dictionary
		var target_actions := _string_array(option_dict.get("targetActions", []))
		if not target_actions.is_empty() and not _target_actions_match(target_actions, action):
			continue
		var seat_number := _int_or_minus_one(option_dict.get("targetSeatNumber", -1))
		if seat_number > 0 and not result.has(seat_number):
			result.append(seat_number)
	result.sort()
	return result


func _target_actions_match(target_actions: Array, action: String) -> bool:
	if target_actions.has(action):
		return true
	match action:
		"witch_act":
			return target_actions.has("witch_save") or target_actions.has("witch_poison")
		"sheriff_speech_order":
			return target_actions.has("sheriff_speech_order_clockwise") or target_actions.has("sheriff_speech_order_counterclockwise")
		"sheriff_badge_action":
			return target_actions.has("sheriff_badge_pass")
		"hunter_shoot":
			return target_actions.has("hunter_shoot")
		_:
			return false


func _target_options(context: Dictionary) -> Array:
	var result := []
	var value = context.get("targetOptions", [])
	if not (value is Array):
		return result
	for item in value:
		if item is Dictionary:
			result.append(item)
	return result


func _string_array(value) -> Array:
	var result := []
	if not (value is Array):
		return result
	for item in value:
		var text := String(item).strip_edges()
		if text != "":
			result.append(text)
	return result


func _int_or_minus_one(value) -> int:
	if value is int:
		return int(value)
	if value is float:
		return int(value) if float(value) == float(int(value)) else -1
	if value is String:
		var text := String(value).strip_edges()
		if text.is_valid_int():
			return int(text.to_int())
	return -1
