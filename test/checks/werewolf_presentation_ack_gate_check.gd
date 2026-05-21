extends SceneTree


class FakeNetworkSession:
	var peers := {
		11: "peer_human",
		12: "peer_observer",
	}

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

	func send_to_peer(_peer_id: int, _type: String, _payload: Dictionary = {}, _message_id: String = "") -> bool:
		return true

	func broadcast(_type: String, _payload: Dictionary = {}, _message_id: String = "") -> void:
		pass


class FakeNetworkSessionWithPendingPeer:
	var peers := {
		21: "",
	}

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

	func send_to_peer(_peer_id: int, _type: String, _payload: Dictionary = {}, _message_id: String = "") -> bool:
		return true

	func broadcast(_type: String, _payload: Dictionary = {}, _message_id: String = "") -> void:
		pass


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

	var active: Dictionary = room._active_room()
	active["observers"] = [{"id": "peer_observer", "displayName": "观战"}]
	room._players = [
		{"id": "host_player", "name": "房主", "owner": "self", "participant_id": "host", "role_key": "villager", "alive": true},
		{"id": "peer_player", "name": "真人", "owner": "human", "participant_id": "peer_human", "role_key": "seer", "alive": true},
		{"id": "bot_player", "name": "机器人", "owner": "bot", "controller_participant_id": "host", "role_key": "wolf", "alive": true},
	]
	room._room_network_session = FakeNetworkSession.new()

	var item := {
		"speaker": "主持人",
		"text": "需要所有真实设备确认后再推进。",
		"visibility": "public",
		"at": 1.0,
	}
	room._ensure_history_presentation_id(item)
	var presentation_id: String = room._history_presentation_id(item)
	room._register_presentation_ack_gate_for_history_item(item)
	if not _expect(room._presentation_ack_controller.has_gate(presentation_id), "gate is created for public item"):
		return
	var gate: Dictionary = room._presentation_ack_controller.gate(presentation_id)
	var expected: Array = gate.get("expected", [])
	if not _expect(expected.size() == 3, "host + human peer + observer are expected"):
		return
	if not _expect(expected.has("host"), "host device must ack"):
		return
	if not _expect(expected.has("peer_human"), "human peer device must ack"):
		return
	if not _expect(expected.has("peer_observer"), "observer device must ack"):
		return
	if not _expect(not expected.has("bot_player"), "bot player does not ack"):
		return

	room._schedule_auto_resolve_bot_turns()
	if not _expect(room._auto_resolve_waiting_for_tts, "auto resolve waits on gate"):
		return
	room._host_apply_presentation_ack(0, {"presentationId": presentation_id, "participantId": "host", "source": "test"})
	if not _expect(room._presentation_ack_controller.has_gate(presentation_id), "gate still waits after host ack"):
		return
	room._host_apply_presentation_ack(11, {"presentationId": presentation_id, "source": "test"})
	if not _expect(room._presentation_ack_controller.has_gate(presentation_id), "gate still waits after human ack"):
		return
	room._host_apply_presentation_ack(12, {"presentationId": presentation_id, "source": "test"})
	if not _expect(not room._presentation_ack_controller.has_gate(presentation_id), "gate opens after all device acks"):
		return
	if not _expect(room._auto_resolve_deferred_pending, "auto resolve is scheduled when gate opens"):
		return

	room._presentation_ack_controller.clear_gates()
	room._room_network_session = FakeNetworkSessionWithPendingPeer.new()
	var pending_peer_item := {
		"speaker": "主持人",
		"text": "公开广播必须等待已连接设备确认，即使设备尚未绑定参与者。",
		"visibility": "public",
		"at": 2.0,
	}
	room._ensure_history_presentation_id(pending_peer_item)
	var pending_peer_presentation_id: String = room._history_presentation_id(pending_peer_item)
	room._register_presentation_ack_gate_for_history_item(pending_peer_item)
	if not _expect(room._presentation_ack_controller.has_gate(pending_peer_presentation_id), "gate is created for pending peer public item"):
		return
	var pending_peer_gate: Dictionary = room._presentation_ack_controller.gate(pending_peer_presentation_id)
	var pending_peer_expected: Array = pending_peer_gate.get("expected", [])
	if not _expect(pending_peer_expected.has("host"), "pending peer gate still waits for host"):
		return
	if not _expect(pending_peer_expected.has("peer:21"), "pending peer device must ack public item"):
		return
	room._host_apply_presentation_ack(0, {"presentationId": pending_peer_presentation_id, "participantId": "host", "source": "test"})
	if not _expect(room._presentation_ack_controller.has_gate(pending_peer_presentation_id), "pending peer gate still waits after host ack"):
		return
	room._host_apply_presentation_ack(21, {"presentationId": pending_peer_presentation_id, "source": "test"})
	if not _expect(not room._presentation_ack_controller.has_gate(pending_peer_presentation_id), "pending peer ack opens public gate"):
		return

	room.queue_free()
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("werewolf_presentation_ack_gate_check failed: %s" % message)
	quit(1)
	return false
