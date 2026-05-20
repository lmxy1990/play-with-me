extends SceneTree


func _initialize() -> void:
	var state = load("res://scripts/core/app_state.gd").new()
	state.persistence_enabled = false
	state.load_or_create()
	state.create_room("狼人杀", 6, "", "basic_village", "标准村庄")
	state.bot_profiles = [
		{
			"id": "observer_owned_bot",
			"name": "Observer Bot",
			"description": "观战位添加机器人",
			"persona": "认真听发言",
			"model": "qwen-plus",
			"voice": "系统默认",
			"enabled": true,
			"memory": {},
		},
	]

	var packed := load("res://scenes/werewolf_room.tscn") as PackedScene
	var room := packed.instantiate() as Control
	room.set_app_state(state)
	root.add_child(room)
	await process_frame
	await process_frame

	if not _expect(String(room._players[0].get("owner", "")) == "self", "entering room auto-sits local player"):
		return
	room._switch_local_to_observer()
	await process_frame
	if not _expect(int(room._local_player_index) == -1, "local player is in observer queue"):
		return
	if not _expect(room._is_observer_participant(room._current_network_participant_id()), "local participant is observer"):
		return

	var observer_slot := room.find_child("ObserverSlotButton1", true, false) as Button
	if not _expect(observer_slot != null and not observer_slot.disabled, "own observer slot opens actions"):
		return
	observer_slot.pressed.emit()
	await process_frame
	if not _expect(room.find_child("ObserverActionsOverlay", true, false) != null, "observer action popup opens"):
		return
	var add_seat := room.find_child("ObserverAddBotSeatButton", true, false) as Button
	if not _expect(add_seat != null and not add_seat.disabled, "observer can choose a player seat for bot"):
		return
	add_seat.pressed.emit()
	await process_frame
	if not _expect(room.find_child("AddBotProfileList", true, false) != null, "bot profile picker opens from observer slot"):
		return
	var hit := room.find_child("AddBotProfileHit", true, false) as Button
	if not _expect(hit != null, "bot profile card is clickable"):
		return
	hit.pressed.emit()
	await process_frame

	var bot_index := _bot_index(room, "observer_owned_bot")
	if not _expect(bot_index >= 0, "observer-owned bot is added to a player seat"):
		return
	if not _expect(String(room._players[bot_index].get("controller_participant_id", "")) == room._current_network_participant_id(), "bot remains controlled by observer"):
		return
	if not _expect(int(room._local_player_index) == -1, "adding a bot does not move observer into game"):
		return
	if not _expect(room._is_observer_participant(room._current_network_participant_id()), "observer remains in observer queue after adding bot"):
		return

	room.queue_free()
	quit(0)


func _bot_index(room: Control, profile_id: String) -> int:
	for i in range(room._players.size()):
		if String(room._players[i].get("owner", "")) == "human" \
				and String(room._players[i].get("participant_id", "")) == "" \
				and String(room._local_private_bot_profile_id_for_seat(i)) == profile_id:
			return i
	return -1


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("werewolf_observer_bot_control_check failed: %s" % message)
	quit(1)
	return false
