extends "res://scripts/pages/base/page_room_network_ui_base.gd"

const RoomParticipantRegistryScript := preload("res://scripts/room/network/room_participant_registry.gd")

var _room_participant_registry = RoomParticipantRegistryScript.new()


func _network_auth_payload(payload: Dictionary) -> Dictionary:
	return _room_participant_registry.auth_payload(payload)


func _network_identity_matches(participant: Dictionary, auth: Dictionary) -> bool:
	return _room_participant_registry.identity_matches(participant, auth)


func _network_reconnect_token(room: Dictionary, participant_id: String) -> String:
	return _room_participant_registry.reconnect_token(room, participant_id)


func _ensure_network_reconnect_token(room: Dictionary, participant_id: String) -> String:
	return _room_participant_registry.ensure_reconnect_token(room, participant_id)


func _register_observer(room: Dictionary, participant_id: String, display_name: String, auth: Dictionary, identity: Dictionary = {}) -> void:
	_room_participant_registry.register_observer(room, participant_id, display_name, auth, identity)


func _observer_for_participant(room: Dictionary, participant_id: String) -> Dictionary:
	return _room_participant_registry.observer_for_participant(room, participant_id)


func _remove_observer(room: Dictionary, participant_id: String) -> bool:
	return _room_participant_registry.remove_observer(room, participant_id)


func _is_observer_participant(participant_id: String) -> bool:
	return _room_participant_registry.is_observer_participant(_active_room(), participant_id)


func _observer_count(room: Dictionary) -> int:
	return _room_participant_registry.observer_count(room)


func _can_add_observer(room: Dictionary) -> Dictionary:
	return _room_participant_registry.can_add_observer(room, _room_occupied_player_count())


func _can_add_observer_after_seat_release(room: Dictionary, participant_id: String) -> Dictionary:
	var occupied := _room_occupied_player_count()
	if has_method("_seat_for_participant_id") and int(call("_seat_for_participant_id", participant_id)) >= 0:
		occupied = maxi(0, occupied - 1)
	return _room_participant_registry.can_add_observer(room, occupied)


func _room_capacity(room: Dictionary) -> int:
	return _room_participant_registry.room_capacity(room)


func _room_occupied_player_count() -> int:
	var players_value = get("_players")
	var players: Array = players_value if players_value is Array else []
	var count := 0
	for player_value in players:
		if player_value is Dictionary and String((player_value as Dictionary).get("owner", "")).strip_edges() != "":
			count += 1
	return count


func _room_total_participant_count(room: Dictionary) -> int:
	return _room_occupied_player_count() + _observer_count(room)


func _observer_message_is_read_only(peer_id: int, type: String) -> bool:
	var participant_id := String(_room_network_session.call("peer_participant_id", peer_id)).strip_edges()
	return _room_participant_registry.observer_message_is_read_only(_active_room(), participant_id, type)


func _send_observer_read_only(peer_id: int) -> void:
	if _room_network_session != null:
		_room_network_session.call("send_to_peer", peer_id, "action_rejected", {
			"code": "observer_read_only",
			"message": "观察者不能发送聊天或游戏动作",
		})


func _network_nonce(byte_length: int) -> String:
	return _room_participant_registry.nonce(byte_length)


func _network_base64_url(bytes: PackedByteArray) -> String:
	return _room_participant_registry.base64_url(bytes)


func _payload_seat_index(payload: Dictionary) -> int:
	if payload.has("seatIndex"):
		return int(payload.get("seatIndex", -1))
	if payload.has("seatNumber"):
		return int(payload.get("seatNumber", 0)) - 1
	return -1


func _payload_target_index(payload: Dictionary) -> int:
	if payload.has("targetIndex"):
		return int(payload.get("targetIndex", -1))
	if payload.has("targetSeatNumber"):
		return int(payload.get("targetSeatNumber", 0)) - 1
	return -1
