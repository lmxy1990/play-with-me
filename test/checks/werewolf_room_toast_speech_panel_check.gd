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
	room._clear_system_progress_toast()
	room._center_speech_items.clear()
	room._refresh_center_panel()
	await process_frame

	var center := room._center_panel as PanelContainer
	if not _expect(center != null, "center panel exists"):
		return
	if not _expect(center.size.y >= 270.0, "center panel is taller"):
		return
	if not _expect(center.visible, "center speech panel remains visible while idle"):
		return
	if not _expect(room.find_child("CenterSpeechIdleLabel", true, false) != null, "center panel has an idle speech placeholder"):
		return
	if not _expect(not _has_active_toast(room), "top toast does not show just because the room rendered"):
		return
	if not _expect(_seat_cards_are_above_center(room), "seat avatars are above the center panel for clicks"):
		return

	room._show_system_progress_toast("系统发言测试", 0.05)
	await process_frame
	if not _expect(_has_active_toast(room), "system progress appears as a toast"):
		return
	var toast := room._system_progress_toast as PanelContainer
	if not _expect(toast.size.y <= 64.0, "system toast is a compact instant message"):
		return
	if not _expect(not _contains_label(toast, "准备"), "system toast does not include fixed progress steps"):
		return
	var toast_label := toast.find_child("SystemProgressToastLabel", true, false) as Label
	if not _expect(toast_label != null, "system toast has a named text label"):
		return
	if not _expect(String(toast_label.text) == "系统发言测试", "system toast label contains the message"):
		return
	var toast_color: Color = toast_label.get_theme_color("font_color")
	if not _expect(toast_color.r > 0.92 and toast_color.g > 0.92 and toast_color.b > 0.92, "system toast text is white"):
		return
	await create_timer(0.7).timeout
	await process_frame
	if not _expect(not _has_active_toast(room), "system progress toast dismisses"):
		return

	room._center_speech_items.clear()
	room._set_system_message("阿明 加入 2号位")
	await process_frame
	if not _expect(_has_active_toast(room), "room lifecycle message appears as a toast"):
		return
	var lifecycle_toast := room._system_progress_toast as PanelContainer
	var lifecycle_label := lifecycle_toast.find_child("SystemProgressToastLabel", true, false) as Label
	if not _expect(lifecycle_label != null and String(lifecycle_label.text) == "阿明 加入 2号位", "room lifecycle toast keeps the room message"):
		return
	if not _expect(room._center_speech_items.is_empty(), "room lifecycle message does not enter center speech panel"):
		return
	room._clear_system_progress_toast()

	var first_text := _repeat_text("第一段玩家发言，用来填满中间展示面板。", 18)
	var second_text := _repeat_text("第二段玩家发言，播放完上一段后空间不够时应该清空旧内容。", 18)
	var first := {"speaker": "1号 玩家A", "text": first_text, "at": 1.0}
	var second := {"speaker": "2号 玩家B", "text": second_text, "at": 2.0}
	room._show_center_speech_item(first, false)
	await process_frame
	if not _expect(room._center_speech_items.size() == 1, "first speech is shown in center panel"):
		return
	var center_avatar := room.find_child("CenterSpeechAvatar", true, false) as Control
	if not _expect(center_avatar != null, "center speech has a clickable player avatar"):
		return
	center_avatar.emit_signal("gui_input", _mouse_click(center_avatar.size * 0.5))
	await process_frame
	if not _expect(room.find_child("SeatDetailOverlay", true, false) != null, "clicking center speech avatar opens seat detail"):
		return
	room._clear_modal()
	await process_frame
	var first_entry := room.find_child("CenterSpeechEntry", true, false)
	room._update_center_speech_progress(first, 0.25)
	await process_frame
	if not _expect(first_entry != null and first_entry == room.find_child("CenterSpeechEntry", true, false), "center speech progress refresh reuses the existing view"):
		return
	room._finish_center_speech_item(first)
	room._show_center_speech_item(second, true, false, true)
	await process_frame
	if not _expect(room._center_speech_items.size() == 1, "old speech clears when panel capacity is exceeded after playback"):
		return
	if not _expect(String((room._center_speech_items[0] as Dictionary).get("speaker", "")) == "2号 玩家B", "new speech remains after clear"):
		return

	room._center_speech_items.clear()
	room._show_center_speech_item_from_history({"speaker": "主持人", "text": "黑夜降临，请狼队按座位顺序发言。", "at": 3.0})
	await process_frame
	if not _expect(room._center_speech_items.size() == 1, "moderator speech is shown in center panel"):
		return
	if not _expect(String((room._center_speech_items[0] as Dictionary).get("speaker", "")) == "主持人", "moderator speaker remains in center panel"):
		return

	room._clear_system_progress_toast()
	room._clear_center_speech_display()
	room._refresh_center_panel()
	room._present_history_item({"speaker": "主持人", "text": "昨夜平安夜。", "at": 4.0})
	await process_frame
	if not _expect(not _has_active_toast(room), "moderator history does not create a toast"):
		return
	if not _expect(room._center_speech_items.size() == 1, "moderator history is shown in center panel"):
		return
	if not _expect(String((room._center_speech_items[0] as Dictionary).get("text", "")) == "昨夜平安夜。", "moderator history center text is kept"):
		return

	room.queue_free()
	quit(0)


func _has_active_toast(room: Control) -> bool:
	return room._system_progress_toast != null and is_instance_valid(room._system_progress_toast)


func _seat_cards_are_above_center(room: Control) -> bool:
	if room._center_panel == null or room._seat_cards.is_empty():
		return false
	for seat in room._seat_cards:
		if not (seat is Control):
			return false
		if int((seat as Control).z_index) <= int(room._center_panel.z_index):
			return false
	return true


func _repeat_text(text: String, count: int) -> String:
	var result := ""
	for _i in range(count):
		result += text
	return result


func _contains_label(root_node: Node, text: String) -> bool:
	if root_node is Label and String((root_node as Label).text) == text:
		return true
	for child in root_node.get_children():
		if _contains_label(child, text):
			return true
	return false


func _mouse_click(position: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = position
	return event


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("werewolf_room_toast_speech_panel_check failed: %s" % message)
	quit(1)
	return false
