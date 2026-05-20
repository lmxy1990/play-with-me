extends SceneTree


func _initialize() -> void:
	var state = load("res://scripts/core/app_state.gd").new()
	state.persistence_enabled = false
	state.load_or_create()
	var room_data: Dictionary = state.create_room("狼人杀", 6, "", "basic_village", "标准村庄")
	room_data["observers"] = [
		{"id": "host", "displayName": "我在观战"},
		{"id": "observer_peer", "displayName": "其他观战"},
	]

	var packed := load("res://scenes/werewolf_room.tscn") as PackedScene
	var room := packed.instantiate() as Control
	room.set_app_state(state)
	root.add_child(room)
	await process_frame
	await process_frame

	if not _expect(room._observer_bar != null, "observer bar exists"):
		return
	if not _expect(room._observer_bar.visible, "observer slots are always visible"):
		return
	if not _expect(room._observer_bar.global_position.x > room.get_viewport_rect().size.x * 0.78, "observer slots stay on the right edge"):
		return
	if not _expect(_contains_text(room._observer_bar, "观战1"), "first observer slot exists"):
		return
	if not _expect(_contains_text(room._observer_bar, "观战2"), "second observer slot exists"):
		return
	if not _expect(_contains_text(room._observer_bar, "观战3"), "third observer slot exists"):
		return
	if not _expect(_contains_text(room._observer_bar, "我在观战"), "local observer is shown"):
		return
	if not _expect(_contains_text(room._observer_bar, "其他观战"), "other observer occupies a fixed slot"):
		return
	if not _expect(_contains_text(room._observer_bar, "空位"), "empty observer slot remains visible"):
		return
	if not _expect(room.find_child("ObserverEntryButton", true, false) == null, "observer entry button is removed from top-right hud"):
		return
	var summary := room.find_child("RoomSummaryStatusLabel", true, false) as Label
	if not _expect(summary != null and String(summary.text).contains("观战 2/3"), "top-left summary shows observer count"):
		return

	room_data["observers"] = []
	room._refresh_room_controls()
	await process_frame
	if not _expect(room._observer_bar.visible, "observer slots remain visible when empty"):
		return
	if not _expect(summary != null and String(summary.text).contains("观战 0/3"), "top-left summary updates observer count"):
		return
	var first_slot := room.find_child("ObserverSlotButton1", true, false) as Button
	if not _expect(first_slot != null and not first_slot.disabled, "empty observer slot can be selected before game starts"):
		return
	first_slot.pressed.emit()
	await process_frame
	if not _expect(int(room._observer_count(room._active_room())) == 1, "selecting an empty observer slot switches local user to observer"):
		return

	room.queue_free()
	quit(0)


func _contains_text(root_node: Node, text: String) -> bool:
	if root_node is Label and String((root_node as Label).text).contains(text):
		return true
	if root_node is Button and String((root_node as Button).text).contains(text):
		return true
	for child in root_node.get_children():
		if _contains_text(child, text):
			return true
	return false


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("werewolf_observer_slots_check failed: %s" % message)
	quit(1)
	return false
