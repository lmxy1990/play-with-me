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

	if not _expect(_status_text(room, "RoomSummaryStatusLabel") == "容量 1/9 · 席位 1/6 · 真人 1 / AI 0 · 观战 0/3", "initial room summary is current"):
		return
	if not _expect(_status_text(room, "RoomInteractionStatusLabel") == "真人准备后房主开始", "initial interaction status is current"):
		return

	room._add_bot_at(1, {"id": "status_sync_bot", "name": "StatusBot", "model": "qwen-plus", "voice": "系统默认", "enabled": true})
	await process_frame
	if not _expect(_status_text(room, "RoomSummaryStatusLabel") == "容量 2/9 · 席位 2/6 · 真人 1 / AI 1 · 观战 0/3", "room summary updates after adding bot"):
		return
	room._players[1]["controller_participant_id"] = "peer_other"
	room._players[1]["participant_id"] = "peer_other"
	room._refresh_seat(1)

	room._pending_action = "刀人"
	room._pending_actor_index = 1
	room._refresh_center_panel()
	await process_frame
	if not _expect(_status_text(room, "RoomInteractionStatusLabel") == "等待开局 · 2号 StatusBot：刀人", "interaction status updates after pending action changes"):
		return
	room._clear_modal()
	room._on_seat_pressed(0)
	await process_frame
	var detail_overlay := _find_child_name(room._modal_layer, "SeatDetailOverlay")
	if not _expect(detail_overlay != null, "clicking an occupied seat opens detail while waiting for another actor"):
		return
	if not _expect(_find_child_name(room._modal_layer, "TargetConfirmOverlay") == null, "waiting for another actor does not open target confirm"):
		return

	room._clear_modal()
	room._pending_action = ""
	room._pending_actor_index = -1
	room._speech_prompt_index = 0
	room._on_seat_pressed(1)
	await process_frame
	detail_overlay = _find_child_name_prefix(room._modal_layer, "SeatDetailOverlay")
	if not _expect(detail_overlay != null, "clicking occupied seat opens detail during another actor's speech"):
		return
	if not _expect(_find_child_name_prefix(room._modal_layer, "SpeechEditorOverlay") == null, "another actor's speech prompt does not open editor"):
		return

	room.queue_free()
	quit(0)


func _status_text(room: Control, node_name: String) -> String:
	var label := room.find_child(node_name, true, false) as Label
	if label == null:
		return ""
	return String(label.text)


func _find_child_name(root_node: Node, target_name: String) -> Node:
	if root_node == null:
		return null
	if String(root_node.name) == target_name:
		return root_node
	for child in root_node.get_children():
		var found := _find_child_name(child, target_name)
		if found != null:
			return found
	return null


func _find_child_name_prefix(root_node: Node, target_prefix: String) -> Node:
	if root_node == null:
		return null
	if String(root_node.name).begins_with(target_prefix):
		return root_node
	for child in root_node.get_children():
		var found := _find_child_name_prefix(child, target_prefix)
		if found != null:
			return found
	return null


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("werewolf_room_status_sync_check failed: %s" % message)
	quit(1)
	return false
