extends SceneTree


class FakeNetworkSession:
	var participants := {
		11: {"participant_id": "peer_human", "seat_index": 1, "display_name": "真人"},
	}
	var sent := []
	var stopped := false

	func is_host() -> bool:
		return true

	func is_client() -> bool:
		return false

	func is_active() -> bool:
		return true

	func local_participant_id() -> String:
		return "host"

	func peer_ids() -> Array:
		return participants.keys()

	func peer_participant_id(peer_id: int) -> String:
		return String((participants.get(peer_id, {}) as Dictionary).get("participant_id", ""))

	func peer_seat_index(peer_id: int) -> int:
		return int((participants.get(peer_id, {}) as Dictionary).get("seat_index", -1))

	func set_peer_participant(peer_id: int, participant_id: String, seat_index: int, display_name: String = "") -> void:
		participants[peer_id] = {
			"participant_id": participant_id,
			"seat_index": seat_index,
			"display_name": display_name,
		}

	func set_peer_seat(peer_id: int, seat_index: int) -> void:
		if not participants.has(peer_id):
			participants[peer_id] = {}
		(participants[peer_id] as Dictionary)["seat_index"] = seat_index

	func send_to_peer(peer_id: int, type: String, payload: Dictionary = {}, _message_id: String = "") -> bool:
		sent.append({"peer": peer_id, "type": type, "payload": payload.duplicate(true)})
		return true

	func broadcast(type: String, payload: Dictionary = {}, _message_id: String = "") -> void:
		sent.append({"peer": -1, "type": type, "payload": payload.duplicate(true)})

	func stop() -> void:
		stopped = true


func _initialize() -> void:
	await _check_disconnect_pauses_and_reconnect_resumes()
	await _check_explicit_leave_destroys_when_no_real_players()
	quit(0)


func _room_with_state() -> Control:
	var state = load("res://scripts/core/app_state.gd").new()
	state.persistence_enabled = false
	state.load_or_create()
	state.create_room("狼人杀", 6, "", "basic_village", "标准村庄")
	var packed := load("res://scenes/werewolf_room.tscn") as PackedScene
	var room := packed.instantiate() as Control
	room.set_app_state(state)
	room.set_network_session(FakeNetworkSession.new())
	root.add_child(room)
	return room


func _check_disconnect_pauses_and_reconnect_resumes() -> void:
	var room := _room_with_state()
	await process_frame
	await process_frame
	room._players = [
		{"id": "host_player", "name": "房主", "owner": "self", "participant_id": "host", "alive": true, "ready": true, "state": "已准备"},
		{"id": "peer_human", "name": "真人", "owner": "human", "participant_id": "peer_human", "alive": true, "ready": true, "state": "已准备", "device_id": "", "public_key": ""},
		{"id": "player_1", "name": "机器人1", "owner": "human", "participant_id": "", "controller_participant_id": "host", "alive": true, "ready": true},
		{"id": "player_2", "name": "机器人2", "owner": "human", "participant_id": "", "controller_participant_id": "host", "alive": true, "ready": true},
		{"id": "player_3", "name": "机器人3", "owner": "human", "participant_id": "", "controller_participant_id": "host", "alive": true, "ready": true},
		{"id": "player_4", "name": "机器人4", "owner": "human", "participant_id": "", "controller_participant_id": "host", "alive": true, "ready": true},
	]
	room._werewolf = {
		"started": true,
		"phase": "day_discussion",
		"day": 1,
		"speech_index": 1,
		"current_action": {},
	}
	var item := {
		"speaker": "主持人",
		"text": "等待真人设备确认。",
		"visibility": "public",
		"at": 1.0,
	}
	room._ensure_history_presentation_id(item)
	var presentation_id: String = room._history_presentation_id(item)
	room._register_presentation_ack_gate_for_history_item(item)
	if not _expect(room._presentation_ack_gates.has(presentation_id), "ack gate exists before disconnect"):
		return
	var task: Dictionary = room._create_device_task_for_actor("player_speech", 1, {"question": "请发言"})
	if not _expect(not task.is_empty(), "device task exists before disconnect"):
		return
	if not _expect(room._route_device_task(task), "device task routes before disconnect"):
		return
	room._host_mark_peer_left(11, false)
	await process_frame
	if not _expect(bool(room._werewolf.get("paused", false)), "disconnect pauses game"):
		return
	if not _expect(String(room._players[1].get("state", "")) == "离线", "disconnected player is offline"):
		return
	if not _expect(not room._presentation_ack_gates.has(presentation_id), "disconnect drops ack gate participant"):
		return
	if not _expect(not room._device_task_channel.has_task(String(task.get("id", ""))), "disconnect drops pending device task"):
		return
	var history_before: int = room._history.size()
	room._host_apply_device_task_result(11, {
		"taskId": String(task.get("id", "")),
		"ok": true,
		"text": "这是断线后的过期发言",
	})
	if not _expect(room._history.size() == history_before, "paused game ignores stale device result"):
		return
	if not _expect(not room._app_state.rooms.is_empty(), "disconnect does not destroy room"):
		return
	room._host_accept_network_reconnect(11, "reconnect_test", {
		"participantId": "peer_human",
		"reconnectToken": room._ensure_network_reconnect_token(room._active_room(), "peer_human"),
		"auth": {},
	})
	await process_frame
	if not _expect(not bool(room._werewolf.get("paused", false)), "reconnect resumes when no humans offline"):
		return
	if not _expect(String(room._players[1].get("state", "")) != "离线", "reconnected player leaves offline state"):
		return
	room.queue_free()
	await process_frame


func _check_explicit_leave_destroys_when_no_real_players() -> void:
	var room := _room_with_state()
	await process_frame
	await process_frame
	room._players = [
		{"id": "peer_human", "name": "真人", "owner": "human", "participant_id": "peer_human", "alive": true, "ready": true},
		{"id": "player_1", "name": "机器人1", "owner": "human", "participant_id": "", "controller_participant_id": "peer_human", "alive": true, "ready": true},
		{"id": "player_2", "name": "机器人2", "owner": "human", "participant_id": "", "controller_participant_id": "peer_human", "alive": true, "ready": true},
		{"id": "player_3", "name": "机器人3", "owner": "human", "participant_id": "", "controller_participant_id": "peer_human", "alive": true, "ready": true},
		{"id": "player_4", "name": "机器人4", "owner": "human", "participant_id": "", "controller_participant_id": "peer_human", "alive": true, "ready": true},
		{"id": "player_5", "name": "机器人5", "owner": "human", "participant_id": "", "controller_participant_id": "peer_human", "alive": true, "ready": true},
	]
	(room._room_network_session as FakeNetworkSession).set_peer_participant(11, "peer_human", 0, "真人")
	room._host_mark_peer_left(11, true)
	await process_frame
	if not _expect(room._app_state.rooms.is_empty(), "explicit last real player leave destroys room"):
		return
	if not _expect(String(room._app_state.active_room_id) == "", "destroy clears active room id"):
		return
	room.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("werewolf_human_disconnect_pause_check failed: %s" % message)
	quit(1)
	return false
