extends RefCounted


func response_schema_for_context(context: Dictionary) -> Dictionary:
	match String(context.get("request_type", "")).strip_edges():
		"move":
			return _move_schema(context)
		"chat":
			return {}
		_:
			return {}


func request_options_for_context(context: Dictionary) -> Dictionary:
	if String(context.get("request_type", "")).strip_edges() == "chat":
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


func _move_schema(context: Dictionary) -> Dictionary:
	var move_ids := _move_ids(context)
	var move_id_schema := {
		"type": "string",
		"description": "必须从 legal_moves 中选择一个 move_id。",
	}
	if not move_ids.is_empty():
		move_id_schema["enum"] = move_ids
	return {
		"name": "xiangqi_move_v1",
		"strict": true,
		"schema": {
			"type": "object",
			"additionalProperties": false,
			"properties": {
				"action": {
					"type": "string",
					"enum": ["move"],
					"description": "本次行动固定为 move。",
				},
				"move_id": move_id_schema,
				"reason": {
					"type": "string",
					"description": "简短说明选择该走法的原因。",
				},
			},
			"required": ["action", "move_id", "reason"],
		},
	}


func _move_ids(context: Dictionary) -> Array:
	var result: Array = []
	var legal_moves: Array = context.get("legal_moves", [])
	for move_value in legal_moves:
		if not (move_value is Dictionary):
			continue
		var move_id := String((move_value as Dictionary).get("move_id", "")).strip_edges()
		if move_id != "":
			result.append(move_id)
	return result
