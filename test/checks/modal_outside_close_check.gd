extends SceneTree


func _initialize() -> void:
	var state = load("res://scripts/core/app_state.gd").new()
	state.persistence_enabled = false
	state.load_or_create()
	state.create_room("狼人杀", 6, "", "basic_village", "标准村庄")

	var packed := load("res://scenes/werewolf_room.tscn") as PackedScene
	var room := packed.instantiate() as Control
	room.set_app_state(state)
	root.add_child(room)
	await process_frame
	await process_frame

	room._open_add_bot_dialog(1)
	await process_frame
	if not _expect(_modal_has_outside_close(room), "overlay dialog has outside close area"):
		return
	await create_timer(0.35).timeout
	_click_backdrop(room)
	await process_frame
	if not _expect(room._modal_layer.get_child_count() == 0, "overlay dialog closes on outside click"):
		return

	room._open_empty_seat_actions(1)
	await process_frame
	if not _expect(_modal_has_outside_close(room), "seat bubble has outside close area"):
		return
	var seat_backdrop := room._modal_layer.find_child("ModalOutsideCloseArea", false, false) as Control
	if not _expect(seat_backdrop.mouse_filter == Control.MOUSE_FILTER_IGNORE, "seat bubble outside close area does not block seats"):
		return
	var seat_bubble := room._modal_layer.find_child("SeatBubbleAction", true, false) as Control
	if not _expect(seat_bubble != null, "seat bubble action is shown"):
		return
	if not _expect(_seat_bubbles_are_above_seat(room, 1), "seat bubble actions are above the selected seat"):
		return
	room.call("_input", _mouse_click(seat_bubble.global_position + seat_bubble.size * 0.5))
	await process_frame
	if not _expect(room._modal_layer.get_child_count() > 0, "clicking inside seat bubble keeps it open"):
		return
	room.call("_input", _mouse_click(Vector2(1, 1)))
	await process_frame
	if not _expect(room._modal_layer.get_child_count() == 0, "seat bubble closes on outside click"):
		return

	var occupied_seat := room._seat_cards[0] as Control
	room.call("_input", _mouse_click(occupied_seat.global_position + occupied_seat.size * 0.5))
	occupied_seat.call("_on_gui_input", _mouse_click(occupied_seat.size * 0.5))
	await process_frame
	if not _expect(room._modal_layer.find_child("SeatDetailOverlay", true, false) != null, "clicking a player avatar opens seat detail"):
		return
	_click_backdrop(room)
	await process_frame
	if not _expect(room._modal_layer.find_child("SeatDetailOverlay", true, false) != null, "newly opened seat detail ignores the opening tap tail"):
		return
	await create_timer(0.35).timeout
	_click_backdrop(room)
	await process_frame
	if not _expect(room._modal_layer.get_child_count() == 0, "seat detail closes on outside click after open guard"):
		return
	room._clear_modal()
	await process_frame

	room._open_empty_seat_actions(1)
	await process_frame
	var next_seat := room._seat_cards[2] as Control
	room.call("_input", _mouse_click(next_seat.global_position + next_seat.size * 0.5))
	next_seat.call("_on_gui_input", _mouse_click(next_seat.size * 0.5))
	await process_frame
	if not _expect(int(room._selected_player_index) == 2, "seat click still reaches the next slot while bubble closes"):
		return

	room._open_create_room()
	await process_frame
	await create_timer(1.0).timeout
	var popup := room._modal_layer.find_child("BookPopup", false, false) as Control
	if not _expect(popup != null, "book popup opens"):
		return
	popup.call("_gui_input", _mouse_click(Vector2(1, 1)))
	await create_timer(1.1).timeout
	await process_frame
	if not _expect(room._modal_layer.get_child_count() == 0, "book popup closes on outside click"):
		return

	var standalone_packed := load("res://scenes/common/book_popup.tscn") as PackedScene
	var standalone := standalone_packed.instantiate() as Control
	root.add_child(standalone)
	standalone.call("setup", "测试弹窗", Callable(), Vector2(520, 320))
	await process_frame
	await create_timer(1.0).timeout
	standalone.call("_gui_input", _mouse_click(Vector2(1, 1)))
	await create_timer(1.1).timeout
	await process_frame
	if not _expect(not is_instance_valid(standalone) or standalone.get_parent() == null, "standalone book popup frees itself on outside click"):
		return

	room.queue_free()
	quit(0)


func _modal_has_outside_close(room: Control) -> bool:
	return room._modal_layer.find_child("ModalOutsideCloseArea", false, false) != null


func _click_backdrop(room: Control) -> void:
	var backdrop := room._modal_layer.find_child("ModalOutsideCloseArea", false, false) as Control
	if backdrop == null:
		return
	backdrop.emit_signal("gui_input", _mouse_click(Vector2(1, 1)))


func _seat_bubbles_are_above_seat(room: Control, seat_index: int) -> bool:
	if seat_index < 0 or seat_index >= room._seat_cards.size():
		return false
	var seat := room._seat_cards[seat_index] as Control
	if seat == null:
		return false
	var bubbles: Array = _seat_bubble_actions(room)
	if bubbles.size() < 2:
		return false
	for value in bubbles:
		if not (value is Control):
			return false
		var bubble := value as Control
		if bubble.global_position.y + bubble.size.y > seat.global_position.y:
			return false
	return true


func _seat_bubble_actions(room: Control) -> Array:
	var result := []
	for child in room._modal_layer.get_children():
		if child is Control and bool((child as Control).get_meta("seat_bubble", false)):
			result.append(child)
	return result


func _mouse_click(position: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = position
	return event


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("modal_outside_close_check failed: %s" % message)
	quit(1)
	return false
