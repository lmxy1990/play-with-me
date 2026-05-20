extends SceneTree


func _initialize() -> void:
	var state = load("res://scripts/core/app_state.gd").new()
	state.persistence_enabled = false
	state.load_or_create()
	state.create_room("狼人杀", 6, "", "basic_village", "标准村庄")
	state.bot_profiles = [
		{
			"id": "remove_filter_alpha",
			"name": "Alpha Bot",
			"description": "已添加机器人",
			"model": "qwen-plus",
			"voice": "系统默认",
			"enabled": true,
		},
		{
			"id": "remove_filter_beta",
			"name": "Beta Bot",
			"description": "仍可添加机器人",
			"model": "deepseek-chat",
			"voice": "系统默认",
			"enabled": true,
		},
	]

	var packed := load("res://scenes/werewolf_room.tscn") as PackedScene
	var room := packed.instantiate() as Control
	room.set_app_state(state)
	root.add_child(room)
	await process_frame

	room._sit_at(0)
	await process_frame
	room._add_bot_at(1, state.bot_profiles[0] as Dictionary)
	await process_frame

	room._open_add_bot_dialog(2)
	await process_frame
	var list := room.find_child("AddBotProfileList", true, false) as GridContainer
	if not _expect(list != null, "bot profile list exists"):
		return
	if not _expect(list.get_child_count() == 1, "already added bot is excluded from new slot chooser"):
		return
	if not _expect(not _contains_label(list, "Alpha Bot"), "current-room bot profile is hidden"):
		return
	if not _expect(_contains_label(list, "Beta Bot"), "available bot profile remains visible"):
		return
	room._clear_modal()
	if not _expect(not room._can_edit_name(1), "bot name cannot be edited"):
		return

	room._open_seat_detail(1)
	await process_frame
	var remove_button := room.find_child("RemoveBotButton", true, false) as Button
	if not _expect(remove_button != null, "unready controller can remove own bot"):
		return
	remove_button.pressed.emit()
	await process_frame
	if not _expect(String(room._players[1].get("owner", "")) == "", "remove button frees bot seat"):
		return
	if not _expect(not room._active_bot_profile_ids().has("remove_filter_alpha"), "removed bot releases active profile id"):
		return

	room._add_bot_at(1, state.bot_profiles[0] as Dictionary)
	await process_frame
	room._toggle_ready()
	await process_frame
	room._open_seat_detail(1)
	await process_frame
	var hidden_remove_button := room.find_child("RemoveBotButton", true, false) as Button
	if not _expect(hidden_remove_button == null, "ready controller cannot see remove button"):
		return
	room._remove_bot_at(1)
	await process_frame
	if not _expect(String(room._players[1].get("owner", "")) == "human", "ready controller cannot remove own bot"):
		return
	if not _expect(String(room._system_message).contains("已准备"), "ready removal rejection is explained"):
		return

	room._players[0]["ready"] = false
	room._werewolf["started"] = true
	room._werewolf["phase"] = "day_discussion"
	room._clear_modal()
	room._open_seat_detail(1)
	await process_frame
	var game_detail := _find_child_name_prefix(room._modal_layer, "SeatDetailOverlay") as Control
	if game_detail == null:
		game_detail = room._modal_layer.find_child("OverlayCard", true, false) as Control
	if not _expect(game_detail != null, "game can open bot detail"):
		return
	var game_remove_button := room._modal_layer.find_child("RemoveBotButton", true, false) as Button
	if not _expect(game_remove_button == null, "game detail does not show bot remove button"):
		return
	room._remove_bot_at(1)
	await process_frame
	if not _expect(String(room._players[1].get("owner", "")) == "human", "game cannot remove bot"):
		return
	if not _expect(String(room._system_message).contains("对局已开始"), "game removal rejection is explained"):
		return

	room.queue_free()
	quit(0)


func _contains_label(root_node: Node, text: String) -> bool:
	if root_node is Label and String((root_node as Label).text) == text:
		return true
	for child in root_node.get_children():
		if _contains_label(child, text):
			return true
	return false


func _find_child_name_prefix(root_node: Node, prefix: String) -> Node:
	if String(root_node.name).begins_with(prefix):
		return root_node
	for child in root_node.get_children():
		var found := _find_child_name_prefix(child, prefix)
		if found != null:
			return found
	return null


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("werewolf_bot_remove_filter_check failed: %s" % message)
	quit(1)
	return false
