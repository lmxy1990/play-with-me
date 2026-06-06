extends SceneTree

class FakeModelChatClient:
	signal completed(request_id: int, ok: bool, content: String, error: String)

	var requests: Array = []
	var _next_id := 1
	var _results := {}

	func complete_request(request: Dictionary) -> int:
		var request_id := _next_id
		_next_id += 1
		requests.append({"id": request_id, "request": request.duplicate(true)})
		return request_id

	func take_completed_result(request_id: int) -> Dictionary:
		if not _results.has(request_id):
			return {}
		var result: Dictionary = _results.get(request_id, {})
		_results.erase(request_id)
		return result

	func complete_with(request_id: int, content: String, ok: bool = true, error: String = "") -> void:
		_results[request_id] = {"ok": ok, "text": content, "error": error}
		completed.emit(request_id, ok, content, error)


func _initialize() -> void:
	var state = load("res://scripts/core/app_state.gd").new()
	state.persistence_enabled = false
	state.load_or_create()
	state.model_configs = [{
		"model": "默认模型",
		"provider": "openai_api",
		"endpoint": "http://127.0.0.1:9/v1",
		"api_key": "test-key",
		"max_context": 262144,
		"context_window_tokens": 183501,
		"max_output": 4096,
		"temperature": 0.2,
		"reasoning": false,
		"formt_adapter": "openai_json_schema",
		"reason_adapter": "native",
	}]
	state.bot_profiles = [{
		"id": "xiangqi_ai_alpha",
		"name": "象棋机器人",
		"model": "默认模型",
		"voice": "系统默认",
		"enabled": true,
	}]
	state.create_room("象棋", 2, "", "xiangqi_standard", "标准象棋", true, 3, {"game_room_id": "xiangqi"})
	var packed := load("res://scenes/xiangqi_room.tscn") as PackedScene
	var room := packed.instantiate() as Control
	room.set_app_state(state)
	var fake_model := FakeModelChatClient.new()
	room._disconnect_model_client()
	room._model_chat_client = fake_model
	room._connect_model_client()
	root.add_child(room)
	await process_frame
	await process_frame

	room._sit_down(0)
	await process_frame
	room._add_bot_at(1, state.bot_profiles[0] as Dictionary)
	await process_frame
	_expect(String((state.players[1] as Dictionary).get("player_module", "")) == "xiangqi_ai", "black seat should be xiangqi ai")
	_expect(String((state.players[1] as Dictionary).get("role_key", "")) == "black", "black ai should bind black side")
	_expect(String((state.players[1] as Dictionary).get("name", "")) == "象棋机器人", "ai name should use bot profile")
	_expect(not bool(state.xiangqi.get("started", false)), "game should wait for human ready")

	room._toggle_ready()
	await process_frame
	_expect(bool(state.xiangqi.get("started", false)), "game should start when human and bot are ready")

	var before_history: int = state.history.size()
	room._on_square_pressed(0, 3)
	await process_frame
	room._on_square_pressed(0, 4)
	await process_frame
	await create_timer(0.6).timeout
	_expect(fake_model.requests.size() == 1, "black ai should request model before fallback")
	var request: Dictionary = (fake_model.requests[0] as Dictionary).get("request", {})
	_expect(String(request.get("purpose", "")) == "xiangqi.player.move", "xiangqi model request purpose mismatch")
	_expect(String(request.get("output_type", "")) == "json", "xiangqi model request should use json output")
	var messages: Array = request.get("messages", [])
	_expect(messages.size() == 2, "xiangqi model request should include system and user messages")
	_expect(String((messages[0] as Dictionary).get("content", "")).contains("timeline：本局当前可见的公开发言累计"), "xiangqi system prompt should explain timeline")
	_expect(String((messages[0] as Dictionary).get("content", "")).contains("recommended_moves"), "xiangqi system prompt should explain recommended moves")
	_expect(String((messages[0] as Dictionary).get("content", "")).contains("tactical_score"), "xiangqi system prompt should explain tactical score")
	var response_schema: Dictionary = request.get("response_schema", {})
	var schema: Dictionary = response_schema.get("schema", {}) if response_schema.get("schema", {}) is Dictionary else {}
	var properties: Dictionary = schema.get("properties", {}) if schema.get("properties", {}) is Dictionary else {}
	var move_id_schema: Dictionary = properties.get("move_id", {}) if properties.get("move_id", {}) is Dictionary else {}
	var move_ids: Array = move_id_schema.get("enum", [])
	_expect(not move_ids.is_empty(), "xiangqi model schema should constrain move_id")
	fake_model.complete_with(int((fake_model.requests[0] as Dictionary).get("id", 0)), JSON.stringify({
		"action": "move",
		"move_id": "not_in_schema",
		"reason": "测试无效走法",
	}))
	await process_frame
	_expect(String(state.xiangqi.get("side_to_move", "")) == "red", "black ai should move and return turn to red")
	_expect((state.xiangqi.get("move_history", []) as Array).size() == 2, "red move plus ai move should be recorded")
	_expect(state.history.size() == before_history, "side chat history should not include chess moves")
	_expect(_toast_text(room).contains("本地兜底走法"), "xiangqi fallback should show toast instead of being silent")
	_expect(_toast_text(room).contains("模型选择了无效走法"), "xiangqi fallback toast should explain invalid move id")
	_check_ai_context_contract(state)

	var factory = load("res://scripts/player/player_factory.gd").new()
	var named_bot: Dictionary = factory.xiangqi_bot_player_from_profile(2, {
		"name": "象棋机器人",
		"model": "默认模型",
		"avatar": "res://custom/bot.png",
		"voice": "系统默认",
	}, "host", [
		{"name": "象棋机器人", "owner": "human"},
	], -1, 0)
	_expect(String(named_bot.get("name", "")) == "象棋机器人 2", "xiangqi bot should use room unique name logic")
	_expect(String(named_bot.get("player_module", "")) == "xiangqi_ai", "factory should create xiangqi ai player")
	_expect(String(named_bot.get("model", "")) == "默认模型", "xiangqi bot should keep profile model")
	_expect(String(named_bot.get("avatar", "")) == "res://custom/bot.png", "xiangqi bot should keep profile avatar")
	_expect(String(named_bot.get("voice", "")) == "系统默认", "xiangqi bot should keep profile voice")

	room.queue_free()
	await process_frame
	quit()


func _check_ai_context_contract(state) -> void:
	state.history.append({
		"speaker": "阿景",
		"speaker_index": 0,
		"type": "chat",
		"text": "先试探一下",
		"visibility": "public",
		"at": 1.0,
	})
	var builder = load("res://scripts/player/xiangqi/ai/ai_xiangqi_turn_context_builder.gd").new()
	var parser = load("res://scripts/player/xiangqi/ai/ai_xiangqi_output_parser.gd").new()
	var runtime = load("res://scripts/player/xiangqi/ai/ai_xiangqi_player_runtime.gd").new()
	var context: Dictionary = builder.build_move_context(state.xiangqi, state.players[0] as Dictionary, 0, state.history)
	_expect(String(context.get("request_type", "")) == "move", "xiangqi move context should mark request type")
	_expect(String(context.get("system_prompt", "")).contains("timeline：本局当前可见的公开发言累计"), "xiangqi context should explain timeline")
	_expect(String(context.get("system_prompt", "")).contains("你必须以 current_question 和 request_type 为准完成本次任务"), "xiangqi context should guard against chat hijacking")
	_expect(String(context.get("system_prompt", "")).contains("strategy"), "xiangqi context should explain strategy")
	_expect(String(context.get("strategy", "")).contains("赢棋"), "xiangqi strategy should prefer winning play")
	var board: Array = context.get("board", [])
	_expect(board.size() == 10, "xiangqi context board should have 10 ranks")
	_expect(board[0] is Array and (board[0] as Array).size() == 9, "xiangqi context board should have 9 files")
	var timeline: Array = context.get("timeline", [])
	_expect(timeline.size() == 1, "xiangqi context should include accumulated public chat")
	_expect(String((timeline[0] as Dictionary).get("text", "")) == "先试探一下", "xiangqi context timeline should keep chat text")
	var legal_moves: Array = context.get("legal_moves", [])
	_expect(not legal_moves.is_empty(), "xiangqi context should include legal moves")
	_expect(String((legal_moves[0] as Dictionary).get("move_id", "")).begins_with("m_"), "xiangqi legal move should expose move_id")
	_expect((legal_moves[0] as Dictionary).has("tactical_score"), "xiangqi legal move should expose tactical score")
	_expect((legal_moves[0] as Dictionary).get("tags", []) is Array, "xiangqi legal move should expose tags")
	var recommended_moves: Array = context.get("recommended_moves", [])
	_expect(not recommended_moves.is_empty(), "xiangqi context should include recommended moves")
	_expect(String((recommended_moves[0] as Dictionary).get("move_id", "")) == String((legal_moves[0] as Dictionary).get("move_id", "")), "xiangqi recommended moves should start from top scored move")
	_expect(int((recommended_moves[0] as Dictionary).get("tactical_score", -999999)) == int((legal_moves[0] as Dictionary).get("tactical_score", -999999)), "xiangqi recommended move should keep tactical score")
	var parsed: Dictionary = parser.parse_action({"action": "move", "move_id": String((legal_moves[0] as Dictionary).get("move_id", ""))}, context)
	_expect(bool(parsed.get("ok", false)), "xiangqi parser should resolve move_id from context")
	_expect(parsed.get("from", {}) is Dictionary and parsed.get("to", {}) is Dictionary, "xiangqi parser should return from/to for move_id")
	var fallback_context := {
		"legal_moves": [
			{"move_id": "low", "from": {"file": 0, "rank": 0}, "to": {"file": 0, "rank": 1}, "tactical_score": 1, "text": "低分"},
			{"move_id": "high", "from": {"file": 8, "rank": 9}, "to": {"file": 8, "rank": 8}, "tactical_score": 50, "text": "高分"},
		],
	}
	var fallback: Dictionary = runtime.fallback_move_action(fallback_context)
	_expect(bool(fallback.get("ok", false)), "xiangqi fallback should parse selected move")
	_expect(String(fallback.get("move_id", "")) == "high", "xiangqi fallback should prefer highest tactical score")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	assert(false, message)


func _toast_text(room: Control) -> String:
	var layer = room._toast_layer
	if layer == null or not is_instance_valid(layer):
		return ""
	var label := (layer as Control).find_child("XiangqiToastLabel", true, false) as Label
	if label == null:
		return ""
	return String(label.text)
