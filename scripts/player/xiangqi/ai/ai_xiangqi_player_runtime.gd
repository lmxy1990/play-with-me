extends RefCounted

const ContextBuilderScript := preload("res://scripts/player/xiangqi/ai/ai_xiangqi_turn_context_builder.gd")
const OutputParserScript := preload("res://scripts/player/xiangqi/ai/ai_xiangqi_output_parser.gd")
const PromptRendererScript := preload("res://scripts/player/xiangqi/ai/ai_xiangqi_prompt_renderer.gd")
const ResponseSchemaBuilderScript := preload("res://scripts/player/xiangqi/ai/ai_xiangqi_response_schema_builder.gd")

var _context_builder = ContextBuilderScript.new()
var _output_parser = OutputParserScript.new()
var _prompt_renderer = PromptRendererScript.new()
var _response_schema_builder = ResponseSchemaBuilderScript.new()


func build_messages(context: Dictionary) -> Array:
	return _prompt_renderer.build_messages(context)


func system_prompt(context: Dictionary = {}) -> String:
	return _prompt_renderer.system_prompt(context)


func user_prompt(context: Dictionary) -> String:
	return _prompt_renderer.user_prompt(context)


func to_model_payload(context: Dictionary) -> Dictionary:
	return _prompt_renderer.to_model_payload(context)


func response_schema_for_context(context: Dictionary) -> Dictionary:
	return _response_schema_builder.response_schema_for_context(context)


func request_options_for_context(context: Dictionary) -> Dictionary:
	return _response_schema_builder.request_options_for_context(context)


func parse_decision(content: String, context: Dictionary) -> Dictionary:
	var raw = JSON.parse_string(_normalize_json_object_text(content))
	if raw == null:
		return {"ok": false, "error": "invalid_json", "message": "模型未返回 JSON 对象"}
	return _output_parser.parse_action(raw, context)


func build_move_context(state: Dictionary, player: Dictionary, seat_index: int, timeline: Array = []) -> Dictionary:
	return _context_builder.build_move_context(state, player, seat_index, timeline)


func build_chat_context(state: Dictionary, player: Dictionary, seat_index: int, timeline: Array = []) -> Dictionary:
	return _context_builder.build_chat_context(state, player, seat_index, timeline)


func next_move_action(state: Dictionary, player: Dictionary, seat_index: int, timeline: Array = []) -> Dictionary:
	var context := _context_builder.build_move_context(state, player, seat_index, timeline)
	var legal_moves: Array = context.get("legal_moves", [])
	if legal_moves.is_empty():
		return {"ok": true, "action": "resign", "reason": "no_legal_moves"}
	var selected := _select_move(legal_moves)
	if selected.is_empty():
		return {"ok": false, "error": "no_move", "message": "AI 没有可提交的合法走法"}
	var raw := {
		"action": "move",
		"move_id": String(selected.get("move_id", "")),
		"from": (selected.get("from", {}) as Dictionary).duplicate(true),
		"to": (selected.get("to", {}) as Dictionary).duplicate(true),
		"reason": String(selected.get("text", "")),
	}
	var parsed := _output_parser.parse_action(raw, context)
	parsed["context"] = context
	return parsed


func fallback_move_action(context: Dictionary) -> Dictionary:
	var legal_moves: Array = context.get("legal_moves", [])
	if legal_moves.is_empty():
		return {"ok": true, "action": "resign", "reason": "no_legal_moves", "context": context}
	var selected := _select_move(legal_moves)
	if selected.is_empty():
		return {"ok": false, "error": "no_move", "message": "AI 没有可提交的合法走法", "context": context}
	var raw := {
		"action": "move",
		"move_id": String(selected.get("move_id", "")),
		"reason": String(selected.get("text", "")),
	}
	var parsed := _output_parser.parse_action(raw, context)
	parsed["context"] = context
	parsed["fallback"] = true
	return parsed


func _select_move(legal_moves: Array) -> Dictionary:
	var candidates: Array = []
	for move_value in legal_moves:
		if not (move_value is Dictionary):
			continue
		candidates.append(move_value)
	candidates.sort_custom(Callable(self, "_compare_move"))
	if not candidates.is_empty():
		return (candidates[0] as Dictionary).duplicate(true)
	return {}


func _compare_move(a_value, b_value) -> bool:
	var a: Dictionary = a_value
	var b: Dictionary = b_value
	var a_score := int(a.get("tactical_score", 0))
	var b_score := int(b.get("tactical_score", 0))
	if a_score != b_score:
		return a_score > b_score
	var a_from: Dictionary = a.get("from", {})
	var b_from: Dictionary = b.get("from", {})
	var a_to: Dictionary = a.get("to", {})
	var b_to: Dictionary = b.get("to", {})
	var a_key := "%02d%02d%02d%02d" % [int(a_from.get("rank", 0)), int(a_from.get("file", 0)), int(a_to.get("rank", 0)), int(a_to.get("file", 0))]
	var b_key := "%02d%02d%02d%02d" % [int(b_from.get("rank", 0)), int(b_from.get("file", 0)), int(b_to.get("rank", 0)), int(b_to.get("file", 0))]
	return a_key < b_key


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
