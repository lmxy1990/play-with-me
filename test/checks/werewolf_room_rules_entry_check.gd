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

	if not _expect(_contains_label(room._hud_layer, "规则"), "rules button is visible beside QR"):
		return

	room._open_room_rules()
	await process_frame

	var overlay := room.find_child("RoomRulesOverlay", true, false) as PanelContainer
	if not _expect(overlay != null, "rules overlay opens"):
		return
	if not _expect(_contains_label(overlay, "房间规则"), "rules overlay title is shown"):
		return
	if not _expect(_contains_label(overlay, "标准村庄"), "map name is shown"):
		return
	var scroll := overlay.find_child("RoomRulesTextScroll", true, false) as ScrollContainer
	if not _expect(scroll != null, "rules text uses a scroll container"):
		return
	if not _expect(scroll.size_flags_vertical == Control.SIZE_EXPAND_FILL, "rules scroll fills remaining height"):
		return
	if not _expect(_contains_label_containing(overlay, "狼人夜间共同选择袭击目标"), "rule text is shown"):
		return
	if not _expect(_contains_label(overlay, "狼人 2"), "role counts are shown"):
		return
	if not _expect(_contains_label(overlay, "标准村庄 6人局"), "count-specific formatted rule title is shown"):
		return
	if not _expect(_contains_label_containing(overlay, "所有好人全部出局"), "6-player win condition is all-good-dead"):
		return
	if not _expect(not _contains_label_containing(overlay, "当前地图补充"), "shared map supplement section is not shown"):
		return

	room.queue_free()
	quit(0)


func _contains_label(root_node: Node, text: String) -> bool:
	if root_node is Label and String((root_node as Label).text) == text:
		return true
	if root_node is Button and String((root_node as Button).text) == text:
		return true
	for child in root_node.get_children():
		if _contains_label(child, text):
			return true
	return false


func _contains_label_containing(root_node: Node, text: String) -> bool:
	if root_node is Label and String((root_node as Label).text).contains(text):
		return true
	if root_node is Button and String((root_node as Button).text).contains(text):
		return true
	for child in root_node.get_children():
		if _contains_label_containing(child, text):
			return true
	return false


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("werewolf_room_rules_entry_check failed: %s" % message)
	quit(1)
	return false
