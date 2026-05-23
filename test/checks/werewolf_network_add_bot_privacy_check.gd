extends SceneTree

const AppStateScript := preload("res://scripts/core/app_state.gd")
const RoomScene := preload("res://scenes/werewolf_room.tscn")
const SessionScript := preload("res://scripts/room/network/room_network_session.gd")


class CaptureClientSession:
	var payloads := []

	func is_client() -> bool:
		return true

	func is_host() -> bool:
		return false

	func local_participant_id() -> String:
		return "peer_device"

	func request_add_bot(seat_index: int, display_name: String) -> bool:
		return request_add_controlled_player(seat_index, display_name)

	func request_add_controlled_player(seat_index: int, display_name: String, identity_payload: Dictionary = {}) -> bool:
		var payload := identity_payload.duplicate(true)
		payload.merge({
			"seatIndex": seat_index,
			"seatNumber": seat_index + 1,
			"displayName": display_name.strip_edges(),
		}, true)
		return send_client("add_controlled_player", payload)

	func send_client(type: String, payload: Dictionary = {}, _message_id: String = "") -> bool:
		payloads.append({"type": type, "payload": payload.duplicate(true)})
		return true


class FakeHostSession:
	var participant_id := "peer_device"
	var rejections := []

	func peer_participant_id(_peer_id: int) -> String:
		return participant_id

	func send_to_peer(_peer_id: int, type: String, payload: Dictionary = {}, _message_id: String = "") -> bool:
		if type == "action_rejected":
			rejections.append(payload.duplicate(true))
		return true

	func set_peer_seat(_peer_id: int, _seat_index: int) -> void:
		pass


func _initialize() -> void:
	_check_request_payload_is_public()
	await process_frame
	_check_host_stores_public_bot_only()
	await process_frame
	_check_private_profile_survives_snapshot_merge()
	await process_frame
	_check_private_profile_restores_from_reconnect_session()
	await process_frame
	quit(0)


func _check_request_payload_is_public() -> void:
	var session := SessionScript.new()
	root.add_child(session)
	var sent := session.request_add_bot(2, "Kimi Bot")
	if not _expect(not sent, "unconnected request should fail but still build no private payload"):
		return
	session.queue_free()

	var capture := CaptureClientSession.new()
	var state := AppStateScript.new()
	state.persistence_enabled = false
	state.load_or_create()
	state.create_room("狼人杀", 6, "", "basic_village", "标准村庄")
	state.bot_profiles = [_profile()]
	var page := RoomScene.instantiate()
	page.set_app_state(state)
	root.add_child(page)
	await process_frame
	await process_frame
	page._room_network_session = capture
	page._players[1] = page._empty_seat_data(1)
	page._add_bot_at(1, state.bot_profiles[0] as Dictionary)
	if not _expect(capture.payloads.size() == 1, "client sends one add_controlled_player request"):
		return
	var message: Dictionary = capture.payloads[0]
	if not _expect(String(message.get("type", "")) == "add_controlled_player", "client request type is add_controlled_player"):
		return
	var payload: Dictionary = message.get("payload", {})
	for key in ["botProfileId", "bot_profile_id", "model", "api_key", "endpoint"]:
		if not _expect(not payload.has(key), "add_controlled_player request strips %s" % key):
			return
	if not _expect(String(payload.get("displayName", "")) == "Alpha", "add_bot uses public profile name"):
		return
	if not _expect(String(payload.get("voiceName", "")) == "系统默认", "add_bot sends public voice identity"):
		return
	page.queue_free()


func _check_host_stores_public_bot_only() -> void:
	var state := AppStateScript.new()
	state.persistence_enabled = false
	state.load_or_create()
	state.create_room("狼人杀", 6, "", "basic_village", "标准村庄")
	var page := RoomScene.instantiate()
	page.set_app_state(state)
	root.add_child(page)
	page._room_network_session = FakeHostSession.new()
	page._players[2] = page._empty_seat_data(2)
	page._host_add_peer_bot(11, {
		"seatIndex": 2,
		"seatNumber": 3,
		"displayName": "Remote Bot",
		"botProfileId": "must-not-store",
		"model": "private-model",
		"voice": "private-voice",
	})
	var bot: Dictionary = page._players[2]
	if not _expect(String(bot.get("owner", "")) == "human", "host creates generic controlled player seat"):
		return
	if not _expect(String(bot.get("participant_id", "")) == "", "controlled player has no direct participant"):
		return
	if not _expect(String(bot.get("controller_participant_id", "")) == "peer_device", "host stores only controller device"):
		return
	for key in ["bot_profile_id", "model", "api_key", "endpoint"]:
		if not _expect(String(bot.get(key, "")).strip_edges() == "", "host bot has no private field %s" % key):
			return
	if not _expect(String(bot.get("voice", "")) == "private-voice", "host bot keeps public voice identity"):
		return
	if not _expect(String(bot.get("voiceName", "")) == "private-voice", "host bot keeps public voiceName identity"):
		return
	page.queue_free()


func _check_private_profile_survives_snapshot_merge() -> void:
	var state := AppStateScript.new()
	state.persistence_enabled = false
	state.load_or_create()
	state.bot_profiles = [_profile()]
	var page := RoomScene.instantiate()
	page.set_app_state(state)
	root.add_child(page)
	page._players = [
		{"id": "self", "name": "本机", "owner": "self", "participant_id": "host"},
		{"id": "player_1", "name": "Remote Bot", "owner": "human", "participant_id": "", "controller_participant_id": "host"},
	]
	page._cache_local_private_bot_profile_for_seat(1, state.bot_profiles[0] as Dictionary)
	var merged: Array = page._merge_local_private_player_fields([
		{"id": "self", "name": "本机", "owner": "self", "participant_id": "host"},
		{"id": "player_1", "name": "Remote Bot", "owner": "human", "participant_id": "", "controller_participant_id": "host"},
	])
	var bot: Dictionary = merged[1]
	if not _expect(not bot.has("bot_profile_id"), "local snapshot merge keeps public bot free of profile id"):
		return
	if not _expect(not bot.has("model"), "local snapshot merge keeps public bot free of model"):
		return
	if not _expect(String(page._local_private_bot_profile_id_for_seat(1)) == "private_bot_alpha", "local private seat cache keeps profile id"):
		return
	page._players = merged
	var profile: Dictionary = page._local_bot_profile_for_actor(1)
	if not _expect(String(profile.get("model", "")) == "qwen-plus", "local AI resolves profile from private seat cache"):
		return
	page.queue_free()


func _check_private_profile_restores_from_reconnect_session() -> void:
	var state := AppStateScript.new()
	state.persistence_enabled = false
	state.load_or_create()
	state.create_room("狼人杀", 6, "", "basic_village", "标准村庄")
	state.bot_profiles = [_profile()]
	var page := RoomScene.instantiate()
	page.set_app_state(state)
	root.add_child(page)
	page._room_session_store.save({
		"host": "127.0.0.1",
		"port": 42871,
		"participantId": "host",
		"reconnectToken": "token",
		"roomId": String(state.active_room_id),
		"controlledPlayers": [{
			"seatIndex": 1,
			"seatNumber": 2,
			"playerId": "player_1",
			"profileId": "private_bot_alpha",
			"displayName": "Alpha",
		}],
	})
	page._players = [
		{"id": "self", "name": "本机", "owner": "self", "participant_id": "host"},
		{"id": "player_1", "name": "Alpha", "owner": "human", "participant_id": "", "controller_participant_id": "host"},
	]
	page._local_private_bot_profiles_by_seat.clear()
	page._apply_network_snapshot({
		"room": {"id": String(state.active_room_id), "name": "测试房"},
		"players": [
			{"id": "self", "name": "本机", "owner": "self", "participant_id": "host"},
			{"id": "player_1", "name": "Alpha", "owner": "human", "participant_id": "", "controller_participant_id": "host"},
		],
		"werewolf": {"phase": "lobby"},
		"history": [],
	})
	if not _expect(String(page._local_private_bot_profile_id_for_seat(1)) == "private_bot_alpha", "reconnect snapshot restores private controlled profile"):
		return
	var profile: Dictionary = page._local_bot_profile_for_actor(1)
	if not _expect(String(profile.get("model", "")) == "qwen-plus", "restored controlled profile resolves local model name"):
		return
	page.queue_free()


func _profile() -> Dictionary:
	return {
		"id": "private_bot_alpha",
		"name": "Alpha",
		"model": "qwen-plus",
		"voice": "系统默认",
		"enabled": true,
		"memory": {},
	}


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("werewolf_network_add_bot_privacy_check failed: %s" % message)
	quit(1)
	return false
