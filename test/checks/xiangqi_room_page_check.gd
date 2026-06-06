extends SceneTree


func _initialize() -> void:
	var state = load("res://scripts/core/app_state.gd").new()
	state.persistence_enabled = false
	state.load_or_create()
	state.bot_profiles = [{
		"id": "xiangqi_room_bot",
		"name": "象棋机器人",
		"model": "默认模型",
		"voice": "系统默认",
		"enabled": true,
	}]
	state.create_room("象棋", 2, "", "xiangqi_standard", "标准象棋", true, 3, {
		"game_room_id": "xiangqi",
		"clock_enabled": false,
		"time_limit_ms": 600000,
	})
	var packed := load("res://scenes/xiangqi_room.tscn") as PackedScene
	var room := packed.instantiate() as Control
	room.set_app_state(state)
	root.add_child(room)
	await process_frame
	await process_frame

	_expect(room.find_child("XiangqiBoardPanel", true, false) != null, "xiangqi board panel missing")
	_expect(room.find_child("XiangqiPiecesLayer", true, false) != null, "xiangqi pieces layer missing")
	_expect(room.find_child("XiangqiPieceButton_0_3", true, false) != null, "red soldier button missing")
	_expect(room.find_child("XiangqiPieceButton_4_0", true, false) != null, "red king button missing")
	var red_king := room.find_child("XiangqiPieceButton_4_0", true, false) as Button
	var black_king := room.find_child("XiangqiPieceButton_4_9", true, false) as Button
	_expect(red_king != null and black_king != null and red_king.position.y > black_king.position.y, "red side should render at bottom of board")
	var clock := room.find_child("XiangqiClockLabel", true, false) as Label
	_expect(clock != null and String(clock.text) == "不计时", "clock label should show no clock")
	_expect(room.find_child("XiangqiActionExitButton", true, false) != null, "exit button missing")
	_expect(room.find_child("XiangqiActionReadyButton", true, false) != null, "ready button missing")
	_expect(room.find_child("ObserverSlotButton1", true, false) != null, "first observer slot missing")
	_expect(room.find_child("ObserverSlotButton2", true, false) != null, "second observer slot missing")
	_expect(room.find_child("ObserverSlotButton3", true, false) != null, "third observer slot missing")

	room._on_seat_card_pressed(0)
	await process_frame
	var sit := _find_button(room._modal_layer, "落座")
	var bot := _find_button(room._modal_layer, "AI机器人")
	_expect(sit != null, "seat action sit button missing")
	_expect(bot != null, "seat action bot button missing")
	sit.pressed.emit()
	await process_frame
	_expect(int(state.local_player_index) == 0, "sit button should occupy first seat")
	_expect(String((state.players[0] as Dictionary).get("role_key", "")) == "red", "first seat should bind red side")
	_expect(bool((state.players[0] as Dictionary).get("ready", false)), "human should be marked seated before start")
	_expect(not bool(state.xiangqi.get("started", false)), "sitting should not auto start xiangqi")
	_expect(room._modal_layer.get_child_count() == 0, "seat action overlay should close after sit")
	_expect(room.find_child("XiangqiChatInput1", true, false) != null, "local seated side should show chat input")

	var chat_input := room.find_child("XiangqiChatInput1", true, false) as LineEdit
	chat_input.text = "你好"
	room._send_chat_from_input(0, chat_input)
	await process_frame
	_expect(state.history.size() == 1, "chat send should append one chat record")
	_expect(String((state.history[0] as Dictionary).get("type", "")) == "chat", "chat history item should be typed")

	room._on_seat_card_pressed(1)
	await process_frame
	var add_bot_bubble := _find_button(room._modal_layer, "AI机器人")
	_expect(add_bot_bubble != null, "seat action bot button missing before bot picker")
	add_bot_bubble.pressed.emit()
	await process_frame
	_expect(room.find_child("AddBotDialogOverlay", true, false) != null, "bot picker overlay missing")
	_expect(room.find_child("AddBotProfileList", true, false) != null, "bot picker list missing")
	var choose_bot := room.find_child("AddBotProfileHit", true, false) as Button
	_expect(choose_bot != null, "bot picker choose button missing")
	choose_bot.pressed.emit()
	await process_frame
	_expect(String((state.players[1] as Dictionary).get("player_module", "")) == "xiangqi_ai", "choosing profile should add xiangqi bot")
	_expect(not bool(state.xiangqi.get("started", false)), "adding ready bot should not start before human ready")

	var ready := room.find_child("XiangqiActionReadyButton", true, false) as Button
	_expect(ready != null, "ready button missing after seating")
	ready.pressed.emit()
	await process_frame
	_expect(bool(state.xiangqi.get("started", false)), "game should start when both seats are ready")

	room._local_player_index = -1
	room._offer_draw()
	await process_frame
	_expect((state.xiangqi.get("pending_draw_offer", {}) as Dictionary).is_empty(), "observer should not be able to offer draw")
	room._on_square_pressed(0, 3)
	await process_frame
	_expect(room._selected_square.is_empty(), "observer should not be able to select a piece")
	room._local_player_index = 0

	var black_player: Dictionary = state.players[1] as Dictionary
	black_player["player_type"] = "human"
	black_player.erase("player_module")
	state.players[1] = black_player
	room._players[1] = black_player

	room._local_player_index = 0
	room._offer_draw()
	await process_frame
	_expect(not (state.xiangqi.get("pending_draw_offer", {}) as Dictionary).is_empty(), "draw offer should wait for opponent")
	_expect(String(state.xiangqi.get("game_result", "")) == "playing", "draw offer should not end game before accepted")
	room._local_player_index = 1
	room._refresh_all()
	await process_frame
	_expect(room.find_child("XiangqiPendingOfferOverlay", true, false) != null, "opponent should see draw confirmation")
	var decline_draw := _find_button(room._modal_layer, "拒绝")
	_expect(decline_draw != null, "draw decline button missing")
	decline_draw.pressed.emit()
	await process_frame
	_expect((state.xiangqi.get("pending_draw_offer", {}) as Dictionary).is_empty(), "declined draw should clear pending offer")
	_expect(String(state.xiangqi.get("game_result", "")) == "playing", "declined draw should keep game playing")
	room._local_player_index = 0

	var pause := room.find_child("XiangqiActionPauseButton", true, false) as Button
	_expect(pause != null, "pause button missing")
	pause.pressed.emit()
	await process_frame
	_expect(bool(state.xiangqi.get("paused", false)), "pause button should pause game")
	pause.pressed.emit()
	await process_frame
	_expect(not bool(state.xiangqi.get("paused", false)), "pause button should resume game")

	var red_soldier := room.find_child("XiangqiPieceButton_0_3", true, false) as Button
	_expect(red_soldier != null, "red soldier button missing before move")
	red_soldier.pressed.emit()
	await process_frame
	_expect(room.find_child("XiangqiPieceButton_0_4", true, false) == null, "piece should not move before target click")
	_expect(room.find_child("XiangqiLegalDot_0_4", true, false) != null, "legal move dot missing")
	room._on_board_input_gui(_make_mouse_event(room._board_layer.get_global_transform_with_canvas() * room._square_position(0, 4)), room._board_input_layer)
	await process_frame
	_expect(room.find_child("XiangqiPieceButton_0_4", true, false) != null, "red soldier should move to target")
	_expect((state.xiangqi.get("move_history", []) as Array).size() >= 1, "move should be recorded by engine")
	_expect(state.history.size() == 1, "chess moves should not append side chat history")

	room._local_player_index = 0
	room._offer_undo()
	await process_frame
	_expect(not (state.xiangqi.get("pending_undo_offer", {}) as Dictionary).is_empty(), "undo offer should wait for opponent")
	room._local_player_index = 1
	room._refresh_all()
	await process_frame
	_expect(room.find_child("XiangqiPendingOfferOverlay", true, false) != null, "opponent should see undo confirmation")
	var accept_undo := _find_button(room._modal_layer, "同意")
	_expect(accept_undo != null, "undo accept button missing")
	accept_undo.pressed.emit()
	await process_frame
	_expect((state.xiangqi.get("pending_undo_offer", {}) as Dictionary).is_empty(), "accepted undo should clear pending offer")
	_expect((state.xiangqi.get("move_history", []) as Array).is_empty(), "accepted undo should revert last move")
	room._local_player_index = 0

	var keep_alive_player: Dictionary = state.players[1] as Dictionary
	keep_alive_player["owner"] = "human"
	keep_alive_player["participant_id"] = "peer_black"
	state.players[1] = keep_alive_player
	room._players[1] = keep_alive_player
	room._stand_up(0)
	await process_frame
	_expect(not state.rooms.is_empty(), "room should stay when another human remains")
	var observer_slot := room.find_child("ObserverSlotButton1", true, false) as Button
	_expect(observer_slot != null and observer_slot.disabled, "standing up should occupy first observer slot")
	_expect(String(observer_slot.text).contains("自己"), "standing up observer slot should be marked as self")
	_expect(room._room_observers().size() == 1, "standing up should register local observer")
	_expect(int(state.local_player_index) == -1, "observer should not occupy player seat")

	room.queue_free()
	await process_frame

	var destroy_state = load("res://scripts/core/app_state.gd").new()
	destroy_state.persistence_enabled = false
	destroy_state.load_or_create()
	destroy_state.create_room("象棋", 2, "", "xiangqi_standard", "标准象棋", true, 3, {"game_room_id": "xiangqi"})
	var destroy_room := packed.instantiate() as Control
	destroy_room.set_app_state(destroy_state)
	root.add_child(destroy_room)
	await process_frame
	await process_frame
	destroy_room._sit_down(0)
	await process_frame
	destroy_room._stand_up(0)
	await process_frame
	_expect(not destroy_state.rooms.is_empty(), "standing up into observer should keep xiangqi room")
	_expect(destroy_room._room_observers().size() == 1, "standing up should move local player into observer slot")
	destroy_room._leave_room_to_lobby()
	await process_frame
	_expect(destroy_state.rooms.is_empty(), "last human exit should destroy xiangqi room")
	_expect(String(destroy_state.active_room_id) == "", "last human exit should clear active id")
	destroy_room.queue_free()
	await process_frame
	quit()

func _find_button(root_node: Node, text: String) -> Button:
	if root_node is Button and String((root_node as Button).text) == text:
		return root_node as Button
	for child in root_node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _make_mouse_event(local_position: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = local_position
	return event


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	assert(false, message)
