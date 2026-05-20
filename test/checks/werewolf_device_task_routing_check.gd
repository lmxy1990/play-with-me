extends SceneTree


class FakeNetworkSession:
	var sent := []
	var peers := {
		11: "peer_human",
		12: "peer_observer",
	}
	var reject_messages := []

	func is_host() -> bool:
		return true

	func is_client() -> bool:
		return false

	func local_participant_id() -> String:
		return "host"

	func peer_ids() -> Array:
		return peers.keys()

	func peer_participant_id(peer_id: int) -> String:
		return String(peers.get(peer_id, ""))

	func send_to_peer(peer_id: int, type: String, payload: Dictionary = {}, _message_id: String = "") -> bool:
		sent.append({"peer": peer_id, "type": type, "payload": payload.duplicate(true)})
		if type == "action_rejected":
			reject_messages.append(payload.duplicate(true))
		return true


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

	room._players = [
		{"id": "host_player", "name": "房主", "owner": "self", "participant_id": "host", "alive": true},
		{"id": "human_player", "name": "真人", "owner": "human", "participant_id": "peer_human", "alive": true},
		{"id": "player_host_ai", "name": "房主机器人", "owner": "human", "participant_id": "", "controller_participant_id": "host", "alive": true},
		{"id": "player_peer_ai", "name": "远程机器人", "owner": "human", "participant_id": "", "controller_participant_id": "peer_observer", "alive": true},
	]
	room._room_network_session = FakeNetworkSession.new()

	if not _expect(room._device_task_controller_participant_for_actor(0) == "host", "host player routes to host"):
		return
	if not _expect(room._device_task_controller_participant_for_actor(1) == "peer_human", "human player routes to own device"):
		return
	if not _expect(room._device_task_controller_participant_for_actor(2) == "host", "host bot routes to host"):
		return
	if not _expect(room._device_task_controller_participant_for_actor(3) == "peer_observer", "remote bot routes to controller device"):
		return

	var remote_task: Dictionary = room._create_device_task_for_actor("player_action", 3, {
		"turn_key": "manual",
		"modelName": "must-not-send",
		"messages": [{"role": "user", "content": "bad"}],
		"requestOptions": {"output_type": "json"},
		"schema": {"type": "object"},
		"formt_adapter": "openai_json_schema",
		"output_adapter": "openai_json_schema",
		"reason_adapter": "native",
		"max_output_tokens": 4096,
		"temperature": 0.6,
	})
	if not _expect(room._route_device_task(remote_task), "remote task routes"):
		return
	if not _expect(room._device_task_waiting_for_result, "host waits for remote device result"):
		return
	if not _expect(room._device_task_blocks_auto_advance(), "device task channel blocks auto advance"):
		return
	if not _expect(room._room_network_session.sent.size() == 1, "one server message sent"):
		return
	var sent: Dictionary = room._room_network_session.sent[0]
	if not _expect(int(sent.get("peer", -1)) == 12, "remote task sent to observer peer"):
		return
	if not _expect(String(sent.get("type", "")) == "device_task", "server message type is device_task"):
		return
	var sent_payload: Dictionary = sent.get("payload", {})
	if not _expect(String(sent_payload.get("type", "")) == "player_action", "server task type is generic player_action"):
		return
	if not _expect(String(sent_payload.get("actorKind", "")) == "player", "task actor kind is generic player"):
		return
	if not _expect(not sent_payload.has("actorOwner"), "task no longer exposes actorOwner"):
		return
	if not _expect(String(sent_payload.get("controllerParticipantId", "")) == "peer_observer", "task controller is observer device"):
		return
	if not _expect(String(sent_payload.get("hostParticipantId", "")) == "host", "task requester is host"):
		return
	var task_payload: Dictionary = sent_payload.get("payload", {})
	for key in ["model", "modelName", "messages", "requestOptions", "schema", "endpoint", "api_key", "formt_adapter", "output_adapter", "reason_adapter", "max_output_tokens", "temperature"]:
		if not _expect(not _contains_key_recursive(task_payload, key), "task payload strips private key %s" % key):
			return
	var task_frame: Dictionary = task_payload.get("taskFrame", {})
	if not _expect(String(task_frame.get("api", "")) == "werewolf_device_task_frame.v1", "host sends canonical task frame"):
		return
	if not _expect(int(task_frame.get("actorSeatNumber", -1)) == 4, "task frame keeps actor seat"):
		return
	var frame_controller: Dictionary = task_frame.get("controller", {})
	if not _expect(String(frame_controller.get("participantId", "")) == "peer_observer", "task frame keeps controller device"):
		return
	var frame_players: Array = task_frame.get("players", [])
	if not _expect(frame_players.size() == room._players.size(), "task frame includes player view"):
		return
	var actor_row: Dictionary = frame_players[3]
	if not _expect(String(actor_row.get("controllerParticipantId", "")) == "peer_observer", "task frame actor points to controller device"):
		return

	var local_task: Dictionary = room._create_device_task_for_actor("player_action", 0, {})
	if not _expect(room._route_device_task(local_task), "local task routes"):
		return
	if not _expect(String(room._current_device_task_id) == String(local_task.get("id", "")), "local task id is active"):
		return

	var offline_task: Dictionary = room._create_device_task_for_actor("player_action", 3, {"turn_key": "offline"})
	room._room_network_session.peers.erase(12)
	if not _expect(not room._route_device_task(offline_task), "offline task does not route"):
		return
	if not _expect(not room._device_task_channel.has_task(String(offline_task.get("id", ""))), "offline task is removed"):
		return

	room._device_task_channel.clear()
	room._sync_device_task_gate_state()
	room._pending_actor_index = 1
	room._host_apply_peer_action(11, {"targetIndex": 0, "targetSeatNumber": 1})
	if not _expect(room._room_network_session.reject_messages.size() == 1, "legacy action is rejected"):
		return
	if not _expect(String((room._room_network_session.reject_messages[0] as Dictionary).get("message", "")).contains("设备任务"), "legacy rejection explains device task"):
		return

	room.queue_free()
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("werewolf_device_task_routing_check failed: %s" % message)
	quit(1)
	return false


func _contains_key_recursive(value, key: String) -> bool:
	if value is Dictionary:
		for key_value in (value as Dictionary).keys():
			if String(key_value) == key:
				return true
			if _contains_key_recursive((value as Dictionary).get(key_value), key):
				return true
	if value is Array:
		for item in value as Array:
			if _contains_key_recursive(item, key):
				return true
	return false
