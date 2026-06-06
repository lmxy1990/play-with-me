extends RefCounted


func parse_action(value, context: Dictionary = {}) -> Dictionary:
	if not (value is Dictionary):
		return {"ok": false, "error": "invalid_output", "message": "AI 行棋输出不是对象"}
	var data: Dictionary = value
	var action := String(data.get("action", "")).strip_edges()
	if action == "":
		action = "move"
	match action:
		"move":
			var move_id := String(data.get("move_id", "")).strip_edges()
			if move_id != "":
				var matched := _move_by_id(move_id, context)
				if matched.is_empty():
					return {"ok": false, "error": "invalid_move_id", "message": "AI 行棋选择了不存在的 move_id：%s" % move_id}
				return {
					"ok": true,
					"action": "move",
					"move_id": move_id,
					"from": (matched.get("from", {}) as Dictionary).duplicate(true),
					"to": (matched.get("to", {}) as Dictionary).duplicate(true),
					"reason": String(data.get("reason", "")),
				}
			if not context.is_empty():
				return {"ok": false, "error": "missing_move_id", "message": "AI 行棋缺少 move_id"}
			var from_value = data.get("from", {})
			var to_value = data.get("to", {})
			if not (from_value is Dictionary) or not (to_value is Dictionary):
				return {"ok": false, "error": "invalid_move", "message": "AI 行棋缺少起点或终点"}
			var from: Dictionary = from_value
			var to: Dictionary = to_value
			return {
				"ok": true,
				"action": "move",
				"move_id": String(data.get("move_id", "")),
				"from": {"file": int(from.get("file", -1)), "rank": int(from.get("rank", -1))},
				"to": {"file": int(to.get("file", -1)), "rank": int(to.get("rank", -1))},
				"reason": String(data.get("reason", "")),
			}
		"resign", "draw_offer", "undo_offer", "draw_accept", "draw_decline", "undo_accept", "undo_decline":
			return {"ok": true, "action": action, "reason": String(data.get("reason", ""))}
		_:
			return {"ok": false, "error": "unsupported_action", "message": "AI 行棋动作不支持：%s" % action}


func _move_by_id(move_id: String, context: Dictionary) -> Dictionary:
	var legal_moves: Array = context.get("legal_moves", [])
	for move_value in legal_moves:
		if not (move_value is Dictionary):
			continue
		var move: Dictionary = move_value
		if String(move.get("move_id", "")) == move_id:
			return move
	return {}
