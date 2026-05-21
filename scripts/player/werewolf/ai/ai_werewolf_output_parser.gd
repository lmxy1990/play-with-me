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


func parse_decision(content: String, context: Dictionary) -> Dictionary:
	var allowed_actions := _string_array(context.get("allowed_actions", []))
	if allowed_actions.is_empty():
		return {"ok": false, "error": "缺少允许的 action"}
	if _is_single_speech_action(allowed_actions):
		return _parse_speech_decision(content, String(allowed_actions[0]))
	return _parse_action_decision(content, context, allowed_actions)


func _parse_speech_decision(content: String, action: String) -> Dictionary:
	if _looks_like_structured_output(content):
		return {"ok": false, "error": "发言类输出必须是纯文本"}
	var speech := _normalize_speech(content)
	if speech == "":
		return {"ok": false, "error": "模型返回空发言"}
	return {
		"ok": true,
		"action": action,
		"target_seat_number": -1,
		"target_index": -1,
		"speech_text": speech,
	}


func _parse_action_decision(content: String, context: Dictionary, allowed_actions: Array) -> Dictionary:
	var decoded := _decode_json_object(content)
	if decoded.is_empty():
		return {"ok": false, "error": "模型未返回 JSON 对象"}
	var action := String(decoded.get("action", "")).strip_edges()
	if action == "":
		return {"ok": false, "error": "模型缺少 action"}
	if not _action_allowed_for_context(action, allowed_actions):
		return {"ok": false, "error": "模型返回了不允许的 action"}
	if _has_invalid_fields(decoded):
		return {"ok": false, "error": "模型返回了禁止字段"}
	var context_requires_target_field := _actions_need_target(allowed_actions)
	var target_value = decoded.get("targetSeatNumber", -1)
	if context_requires_target_field and not decoded.has("targetSeatNumber"):
		return {"ok": false, "error": "模型缺少 targetSeatNumber"}
	if decoded.has("targetSeatNumber") and not _is_integer_value(target_value):
		return {"ok": false, "error": "targetSeatNumber 必须是 JSON number/integer"}
	var target_seat_number := _resolve_target_seat_number(decoded, context, action)
	var normalized_action := _normalize_action_for_context(action, target_seat_number, decoded, context, allowed_actions)
	if normalized_action == "":
		return {"ok": false, "error": _normalize_action_error(action, target_seat_number, decoded, allowed_actions)}
	if NO_TARGET_ACTIONS.has(normalized_action) and decoded.has("targetSeatNumber"):
		var no_target_value = decoded.get("targetSeatNumber", -1)
		if not _is_integer_value(no_target_value):
			return {"ok": false, "error": "targetSeatNumber 必须是 JSON number/integer"}
		if _int_or_minus_one(no_target_value) != -1:
			return {"ok": false, "error": "当前 action 不允许返回目标"}
		if not context_requires_target_field:
			return {"ok": false, "error": "当前 action 不允许返回目标"}
	if _action_needs_target(normalized_action) and not _is_legal_target_seat_number(target_seat_number, context, normalized_action):
		return {
			"ok": false,
			"error": "模型返回了非法目标",
			"action": normalized_action,
			"target_seat_number": target_seat_number,
			"target_index": target_seat_number - 1 if target_seat_number > 0 else -1,
		}

	var target_index := target_seat_number - 1 if target_seat_number > 0 else -1
	return {
		"ok": true,
		"action": normalized_action,
		"raw_action": action,
		"target_seat_number": target_seat_number,
		"target_index": target_index,
		"speech_text": "",
	}


func _is_single_speech_action(actions: Array) -> bool:
	return actions.size() == 1 and SPEECH_ACTIONS.has(String(actions[0]))


func _looks_like_structured_output(content: String) -> bool:
	var text := content.strip_edges()
	return text.begins_with("{") or text.begins_with("```")


func _decode_json_object(content: String) -> Dictionary:
	var text := _normalize_json_object_text(content)
	if not text.begins_with("{") or not text.ends_with("}"):
		return {}
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	if json.data is Dictionary:
		return json.data as Dictionary
	return {}


func _normalize_json_object_text(content: String) -> String:
	var text := content.strip_edges()
	if text.begins_with("{") and text.ends_with("}"):
		return text
	var fenced := _strict_markdown_json_fence_inner(text)
	if fenced.begins_with("{") and fenced.ends_with("}"):
		return fenced
	return text


func _strict_markdown_json_fence_inner(text: String) -> String:
	var clean := text.strip_edges()
	if not clean.begins_with("```"):
		return ""
	var first_line_end := clean.find("\n")
	if first_line_end < 0:
		return ""
	var opening := clean.substr(0, first_line_end).strip_edges().to_lower()
	if opening != "```" and opening != "```json":
		return ""
	var closing_start := clean.rfind("```")
	if closing_start <= first_line_end:
		return ""
	var trailing := clean.substr(closing_start + 3).strip_edges()
	if trailing != "":
		return ""
	return clean.substr(first_line_end + 1, closing_start - first_line_end - 1).strip_edges()


func _resolve_target_seat_number(decoded: Dictionary, context: Dictionary, action: String) -> int:
	var seat_number := _int_or_minus_one(decoded.get("targetSeatNumber", -1))
	return seat_number


func _is_legal_target_seat_number(target_seat_number: int, context: Dictionary, action: String) -> bool:
	if target_seat_number <= 0:
		return false
	for option in _target_options(context):
		if _int_or_minus_one(option.get("targetSeatNumber", -1)) != target_seat_number:
			continue
		var target_actions := _string_array(option.get("targetActions", []))
		if not target_actions.is_empty() and not _target_actions_match(target_actions, action):
			continue
		return true
	return false


func _action_needs_target(action: String) -> bool:
	return TARGET_ACTIONS.has(action)


func _actions_need_target(actions: Array) -> bool:
	for action_value in actions:
		if _action_needs_target(String(action_value)):
			return true
	return false


func _has_invalid_fields(decoded: Dictionary) -> bool:
	for key in decoded.keys():
		var text := String(key)
		if not ["action", "targetSeatNumber", "direction"].has(text):
			return true
	return false


func _action_allowed_for_context(action: String, allowed_actions: Array) -> bool:
	return allowed_actions.has(action)


func _normalize_action_for_context(action: String, target_seat_number: int, decoded: Dictionary, context: Dictionary, allowed_actions: Array) -> String:
	if action == "witch_act":
		if target_seat_number == -1:
			return "witch_skip"
		return _witch_action_for_target(context, target_seat_number)
	if action == "hunter_shoot":
		return "skip" if target_seat_number == -1 else "hunter_shoot"
	if action == "sheriff_badge_action":
		return "sheriff_badge_destroy" if target_seat_number == -1 else "sheriff_badge_pass"
	if action == "sheriff_speech_order":
		return _speech_order_action_from_direction(String(decoded.get("direction", "")))
	return action


func _normalize_action_error(action: String, target_seat_number: int, decoded: Dictionary, allowed_actions: Array) -> String:
	if action == "sheriff_speech_order" and String(decoded.get("direction", "")).strip_edges() == "":
		return "模型缺少 direction"
	if action == "sheriff_speech_order":
		return "direction 必须是 clockwise 或 counterclockwise"
	if action == "witch_act" and target_seat_number > 0:
		return "模型返回了非法目标"
	if action == "witch_act" and target_seat_number != -1:
		return "targetSeatNumber 必须从可选范围选择"
	if allowed_actions.has("sheriff_badge_action"):
		return "targetSeatNumber 必须是飞警徽目标或 -1"
	if allowed_actions.has("hunter_shoot"):
		return "targetSeatNumber 必须是开枪目标或 -1"
	return "模型返回了不允许的 action"


func _speech_order_action_from_direction(direction: String) -> String:
	match direction.strip_edges().to_lower():
		"clockwise", "顺时针":
			return "sheriff_speech_order_clockwise"
		"counterclockwise", "逆时针":
			return "sheriff_speech_order_counterclockwise"
		_:
			return ""


func _witch_action_for_target(context: Dictionary, target_seat_number: int) -> String:
	for option in _target_options(context):
		if _int_or_minus_one(option.get("targetSeatNumber", -1)) != target_seat_number:
			continue
		var target_actions := _string_array(option.get("targetActions", []))
		if target_actions.has("witch_save"):
			return "witch_save"
		if target_actions.has("witch_poison"):
			return "witch_poison"
	return ""


func _target_actions_match(target_actions: Array, action: String) -> bool:
	if target_actions.has(action):
		return true
	match action:
		"sheriff_speech_order_clockwise", "sheriff_speech_order_counterclockwise":
			return target_actions.has("sheriff_speech_order")
		"sheriff_badge_pass":
			return target_actions.has("sheriff_badge_action")
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
		result.append(String(item))
	return result


func _int_or_minus_one(value) -> int:
	if value is int:
		return int(value)
	if value is float:
		return int(value)
	return -1


func _is_integer_value(value) -> bool:
	if value is int:
		return true
	if value is float:
		return float(value) == float(int(value))
	return false


func _normalize_speech(text: String) -> String:
	var result := text.replace("\r", " ").replace("\n", " ").strip_edges()
	while result.contains("  "):
		result = result.replace("  ", " ")
	return result
