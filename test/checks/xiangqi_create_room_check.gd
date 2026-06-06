extends SceneTree


func _initialize() -> void:
	var state = load("res://scripts/core/app_state.gd").new()
	state.persistence_enabled = false
	state.load_or_create()
	var packed := load("res://scenes/lobby.tscn") as PackedScene
	var lobby := packed.instantiate() as Control
	lobby.set_app_state(state)
	root.add_child(lobby)
	await process_frame
	lobby._open_create_room()
	await process_frame

	var game_select := lobby.find_child("CreateRoomGameSelect", true, false) as OptionButton
	_expect(game_select != null, "game select missing")
	_expect(game_select.item_count >= 2, "game select should include xiangqi")
	game_select.select(1)
	game_select.item_selected.emit(1)
	await process_frame

	var role_counts := lobby.find_child("MapRoleCounts", true, false)
	_expect(role_counts != null, "map role counts missing after xiangqi switch")
	_expect(_has_label_containing(role_counts, "2人局"), "xiangqi selected count should be two")
	_expect(_has_label_containing(role_counts, "红方 1"), "xiangqi role counts should show red")
	_expect(_has_label_containing(role_counts, "黑方 1"), "xiangqi role counts should show black")

	var compression_model := lobby.find_child("TimelineCompressionModel", true, false) as OptionButton
	var compression_interval := lobby.find_child("TimelineCompressionInterval", true, false) as LineEdit
	var max_output_tokens := lobby.find_child("RoomMaxOutputTokens", true, false) as LineEdit
	_expect(compression_model != null and not compression_model.get_parent().visible, "werewolf model row should hide for xiangqi")
	_expect(compression_interval != null and not compression_interval.get_parent().visible, "werewolf compression interval row should hide for xiangqi")
	_expect(max_output_tokens != null and not max_output_tokens.get_parent().visible, "werewolf output row should hide for xiangqi")

	var clock_check := lobby.find_child("XiangqiClockCheck", true, false) as CheckBox
	var clock_minutes := lobby.find_child("XiangqiClockMinutes", true, false) as OptionButton
	_expect(clock_check != null and clock_check.get_parent().visible, "xiangqi clock row should be visible")
	_expect(clock_minutes != null and clock_minutes.get_parent().visible, "xiangqi clock minutes row should be visible")
	_expect(not clock_check.button_pressed, "xiangqi clock should be off by default")
	_expect(clock_minutes.disabled, "clock minutes should be disabled while clock is off")
	_expect(int(clock_minutes.get_item_metadata(clock_minutes.selected)) == 600000, "clock default duration should be 10 minutes")
	clock_check.button_pressed = true
	clock_check.toggled.emit(true)
	await process_frame
	_expect(not clock_minutes.disabled, "clock minutes should enable after clock toggle")

	var confirm := lobby.find_child("CreateRoomConfirmButton", true, false) as Button
	_expect(confirm != null, "confirm button missing")
	confirm.pressed.emit()
	await process_frame
	_expect(state.rooms.size() == 1, "confirm should create one room")
	var room: Dictionary = state.rooms[0]
	_expect(String(room.get("game_room_id", "")) == "xiangqi", "created room should be xiangqi")
	_expect(String(room.get("map_id", "")) == "xiangqi_standard", "created room map should be xiangqi standard")
	_expect(int(room.get("max_players", 0)) == 2, "created xiangqi room should have two players")
	_expect(bool(room.get("clock_enabled", false)), "created xiangqi room should keep clock enabled")
	_expect(int(room.get("time_limit_ms", 0)) == 600000, "created xiangqi room should use 10 minute clock")
	_expect(not state.xiangqi.is_empty(), "created xiangqi room should initialize xiangqi state")
	_expect(String(state.xiangqi.get("game_id", "")) == "xiangqi", "xiangqi state game id mismatch")

	lobby.queue_free()
	await process_frame
	quit()


func _has_label_containing(node: Node, text: String) -> bool:
	if node is Label and String((node as Label).text).contains(text):
		return true
	for child in node.get_children():
		if _has_label_containing(child, text):
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	assert(false, message)
