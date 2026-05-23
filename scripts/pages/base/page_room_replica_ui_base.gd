extends "res://scripts/pages/base/page_room_participant_ui_base.gd"

const RoomNetworkSnapshotBuilderScript := preload("res://scripts/room/network/room_network_snapshot_builder.gd")
const RoomReplicaStoreScript := preload("res://scripts/room/network/room_replica.gd")
const HostElectionScript := preload("res://scripts/room/network/host_election.gd")

var _room_snapshot_builder = RoomNetworkSnapshotBuilderScript.new()
var _room_replica_store = RoomReplicaStoreScript.new()
var _host_election = HostElectionScript.new()
var _room_replica_event_serial := 0
var _room_replica_snapshot_version := 0
var _room_replica_election_term := 0
var _applying_network_snapshot := false
var _network_history_initialized := false
var _host_takeover_attempted_rooms := {}
var _host_takeover_reconnect_last_ms := 0
var _local_private_bot_profiles_by_seat := {}


func _network_snapshot_for_participant(participant_id: String) -> Dictionary:
	var room := _active_room().duplicate(true)
	return _room_snapshot_builder.snapshot_for_participant(
		room,
		_state_array("_players"),
		_state_dictionary("_werewolf"),
		_state_array("_history"),
		_state_array("_wolf_private_history"),
		participant_id,
		_snapshot_seat_for_participant(participant_id),
		_participant_can_view_wolf_private_history(participant_id),
		_state_string("_system_message"),
		bool(get("_phase_night")),
		int(get("_bot_serial"))
	)


func _signed_room_replica_payload() -> Dictionary:
	var room := _active_room()
	if room.is_empty():
		return {}
	_ensure_device_identity_loaded()
	_room_replica_event_serial += 1
	_room_replica_snapshot_version += 1
	var state_payload := _room_snapshot_builder.replica_state_payload(
		room,
		_state_array("_players"),
		_state_dictionary("_werewolf"),
		_state_array("_history"),
		_state_string("_system_message"),
		bool(get("_phase_night")),
		int(get("_bot_serial"))
	)
	var frame := _room_replica_store.make_frame(
		String(room.get("id", "")),
		String(_device_identity.device_id),
		String(_device_identity.public_key),
		_room_replica_election_term,
		_room_replica_event_serial,
		_room_replica_snapshot_version,
		_network_roster_hash(room),
		state_payload
	)
	return _room_replica_store.sign_frame(frame, _device_identity.to_stored_json())


func _network_roster_hash(room: Dictionary) -> String:
	var roster: Array = _room_snapshot_builder.roster_payload(room, _state_array("_players"))
	return _network_base64_url(_room_replica_store.canonical_json(roster).to_utf8_buffer())


func _players_for_participant(participant_id: String) -> Array:
	return _room_snapshot_builder.players_for_participant(_state_array("_players"), participant_id, _active_room(), _state_dictionary("_werewolf"))


func _participant_can_view_wolf_private_history(participant_id: String) -> bool:
	if _is_observer_participant(participant_id):
		return true
	if has_method("_can_view_wolf_private_history"):
		return bool(call("_can_view_wolf_private_history", _snapshot_seat_for_participant(participant_id)))
	return false


func _participant_matches(participant_id: String, owner: String, player_participant: String) -> bool:
	return _room_snapshot_builder.participant_matches(participant_id, owner, player_participant)


func _accept_network_room_replica(payload: Dictionary) -> void:
	if not _room_replica_store.verify_signed_frame(payload):
		return
	var frame_value = payload.get("frame", {})
	if not (frame_value is Dictionary):
		return
	var frame: Dictionary = frame_value
	var room := _active_room()
	var expected_device_id := String(room.get("host_device_id", "")).strip_edges()
	var expected_public_key := String(room.get("host_public_key", "")).strip_edges()
	if expected_device_id != "" and String(frame.get("hostDeviceId", "")).strip_edges() != expected_device_id:
		return
	if expected_public_key != "" and String(frame.get("hostPublicKey", "")).strip_edges() != expected_public_key:
		return
	_room_replica_store.accept(payload)


func _apply_network_snapshot(snapshot: Dictionary) -> void:
	_applying_network_snapshot = true
	var room_value = snapshot.get("room", {})
	if room_value is Dictionary:
		var room: Dictionary = (room_value as Dictionary).duplicate(true)
		if has_method("_upsert_room"):
			call("_upsert_room", room)
		if _app_state != null:
			_app_state.active_room_id = String(room.get("id", _app_state.active_room_id))
	var players_value = snapshot.get("players", [])
	if players_value is Array:
		set("_players", _merge_local_private_player_fields((players_value as Array).duplicate(true)))
		_restore_private_controlled_profiles_from_session("network_snapshot")
	var werewolf_value = snapshot.get("werewolf", {})
	if werewolf_value is Dictionary:
		set("_werewolf", (werewolf_value as Dictionary).duplicate(true))
	var previous_history := _state_array("_history").duplicate(true)
	var history_value = snapshot.get("history", [])
	if history_value is Array:
		var next_history := (history_value as Array).duplicate(true)
		set("_history", next_history)
		if _network_history_initialized and has_method("_present_history_delta"):
			call("_present_history_delta", previous_history, next_history)
		_network_history_initialized = true
	var wolf_private_value = snapshot.get("wolfPrivateHistory", [])
	if wolf_private_value is Array:
		set("_wolf_private_history", (wolf_private_value as Array).duplicate(true))
	_set_system_message(String(snapshot.get("systemMessage", _state_string("_system_message"))))
	set("_phase_night", bool(snapshot.get("phaseNight", bool(get("_phase_night")))))
	set("_bot_serial", int(snapshot.get("botSerial", int(get("_bot_serial")))))
	var local_index := int(snapshot.get("localPlayerIndex", _snapshot_seat_for_participant(_current_network_participant_id())))
	set("_local_player_index", local_index)
	var players := _state_array("_players")
	if local_index >= 0 and local_index < players.size() and players[local_index] is Dictionary:
		set("_local_nickname", String((players[local_index] as Dictionary).get("name", _state_string("_local_nickname"))))
	_call_if_present("_initialize_controlled_bot_model_profiles", ["network_snapshot", true])
	_call_if_present("_sync_werewolf_view_state_without_auto")
	_call_if_present("_commit_state")
	_applying_network_snapshot = false
	if int(get("_mode")) == Mode.TABLE:
		_call_if_present("_refresh_all_seats")
		_call_if_present("_refresh_room_controls")
		_call_if_present("_refresh_center_panel")


func _merge_local_private_player_fields(incoming_players: Array) -> Array:
	var current_players := _state_array("_players")
	var local_participant := _current_network_participant_id()
	for i in range(incoming_players.size()):
		if not (incoming_players[i] is Dictionary):
			_clear_local_private_bot_profile_for_seat(i)
			continue
		if i >= current_players.size() or not (current_players[i] is Dictionary):
			_prune_local_private_bot_profile_for_public_player(i, incoming_players[i] as Dictionary)
			continue
		var incoming: Dictionary = incoming_players[i]
		var current: Dictionary = current_players[i]
		_prune_local_private_bot_profile_for_public_player(i, incoming)
		var controller := String(incoming.get("controller_participant_id", incoming.get("controllerParticipantId", ""))).strip_edges()
		if controller == "":
			controller = String(current.get("controller_participant_id", current.get("controllerParticipantId", ""))).strip_edges()
		if controller != local_participant and not (controller == "" and local_participant == "host"):
			continue
		incoming_players[i] = incoming
	return incoming_players


func _cache_local_private_bot_profile_for_seat(seat_index: int, profile: Dictionary) -> void:
	if seat_index < 0 or profile.is_empty():
		return
	_local_private_bot_profiles_by_seat[seat_index] = profile.duplicate(true)
	_persist_private_controlled_profiles("cache_seat_%d" % seat_index)


func _clear_local_private_bot_profile_for_seat(seat_index: int) -> void:
	if seat_index < 0:
		return
	_local_private_bot_profiles_by_seat.erase(seat_index)
	_persist_private_controlled_profiles("clear_seat_%d" % seat_index)


func _prune_local_private_bot_profile_for_public_player(seat_index: int, player: Dictionary) -> void:
	if not _local_private_bot_profiles_by_seat.has(seat_index):
		return
	var owner := String(player.get("owner", "")).strip_edges()
	if owner == "":
		_clear_local_private_bot_profile_for_seat(seat_index)
		return
	var controller := String(player.get("controller_participant_id", player.get("controllerParticipantId", ""))).strip_edges()
	var local_participant := _current_network_participant_id()
	if controller == "":
		controller = String(player.get("participant_id", player.get("participantId", ""))).strip_edges()
	if controller != local_participant and not (controller == "" and local_participant == "host"):
		_clear_local_private_bot_profile_for_seat(seat_index)


func _local_private_bot_profile_for_seat(seat_index: int) -> Dictionary:
	var value = _local_private_bot_profiles_by_seat.get(seat_index, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _local_private_bot_profile_id_for_seat(seat_index: int) -> String:
	var profile := _local_private_bot_profile_for_seat(seat_index)
	return String(profile.get("id", "")).strip_edges()


func _restore_private_controlled_profiles_from_session(reason: String = "") -> void:
	if _room_session_store == null:
		return
	var session: Dictionary = _room_session_store.load()
	if not _room_session_store.is_valid(session):
		return
	var room_id := String(session.get("roomId", "")).strip_edges()
	var active_room_id := String(_app_state.active_room_id) if _app_state != null else String(_active_room().get("id", ""))
	if room_id != "" and active_room_id != "" and room_id != active_room_id:
		return
	var controlled_value = session.get("controlledPlayers", [])
	if not (controlled_value is Array):
		return
	var restored := 0
	for item in controlled_value as Array:
		if not (item is Dictionary):
			continue
		var data: Dictionary = item
		var seat_index := int(data.get("seatIndex", data.get("seat_index", -1)))
		if seat_index < 0:
			continue
		if _local_private_bot_profiles_by_seat.has(seat_index):
			continue
		if not _public_player_is_controlled_by_local(seat_index):
			continue
		var profile_id := String(data.get("profileId", data.get("profile_id", ""))).strip_edges()
		var profile := _local_private_controlled_profile_by_key(profile_id)
		if profile.is_empty():
			print("[WerewolfControlledPlayer][error] private restore failed reason=%s seat=%d profile_id=%s" % [
				reason.strip_edges(),
				seat_index,
				profile_id,
			])
			continue
		_local_private_bot_profiles_by_seat[seat_index] = profile.duplicate(true)
		restored += 1
	if restored > 0:
		if OS.is_debug_build():
			print("[WerewolfControlledPlayer][debug] restored private profiles reason=%s count=%d" % [reason.strip_edges(), restored])


func _local_private_controlled_profile_by_key(profile_id: String) -> Dictionary:
	var clean := profile_id.strip_edges()
	if clean == "":
		return {}
	if has_method("_bot_profile_by_key_for_controlled_player"):
		var value = call("_bot_profile_by_key_for_controlled_player", clean)
		if value is Dictionary:
			return (value as Dictionary).duplicate(true)
	return {}


func _persist_private_controlled_profiles(reason: String = "") -> void:
	if _room_session_store == null:
		return
	var active_room_id := String(_app_state.active_room_id) if _app_state != null else String(_active_room().get("id", ""))
	if active_room_id == "":
		return
	var session: Dictionary = _room_session_store.load()
	if not _room_session_store.is_valid(session):
		return
	var session_room_id := String(session.get("roomId", "")).strip_edges()
	if session_room_id != "" and session_room_id != active_room_id:
		return
	var controlled := _private_controlled_players_for_session()
	session["roomId"] = active_room_id
	session["controlledPlayers"] = controlled
	_room_session_store.save(session)
	if OS.is_debug_build():
		print("[WerewolfControlledPlayer][debug] persist private controls reason=%s count=%d" % [
			reason.strip_edges(),
			controlled.size(),
		])


func _private_controlled_players_for_session() -> Array:
	var result := []
	for seat_key in _local_private_bot_profiles_by_seat.keys():
		var seat_index := int(seat_key)
		if not _public_player_is_controlled_by_local(seat_index):
			continue
		var profile := _local_private_bot_profile_for_seat(seat_index)
		var profile_id := String(profile.get("id", "")).strip_edges()
		if profile_id == "":
			continue
		var player := {}
		var players := _state_array("_players")
		if seat_index >= 0 and seat_index < players.size() and players[seat_index] is Dictionary:
			player = players[seat_index] as Dictionary
		result.append({
			"seatIndex": seat_index,
			"seatNumber": seat_index + 1,
			"playerId": String(player.get("id", "")),
			"profileId": profile_id,
			"displayName": String(player.get("name", profile.get("name", ""))),
		})
	return result


func _public_player_is_controlled_by_local(seat_index: int) -> bool:
	var players := _state_array("_players")
	if seat_index < 0 or seat_index >= players.size() or not (players[seat_index] is Dictionary):
		return false
	var player: Dictionary = players[seat_index]
	if String(player.get("owner", "")).strip_edges() == "":
		return false
	if String(player.get("participant_id", player.get("participantId", ""))).strip_edges() != "":
		return false
	var controller := String(player.get("controller_participant_id", player.get("controllerParticipantId", ""))).strip_edges()
	var local_participant := _current_network_participant_id()
	return controller == local_participant or (controller == "" and local_participant == "host")


func _on_host_connection_lost() -> void:
	if not _is_network_client():
		return
	if _attempt_host_takeover_from_latest_replica():
		return
	_set_system_message("房主断线，等待新房主广播")
	_call_if_present("_refresh_center_panel")


func _attempt_host_takeover_from_latest_replica() -> bool:
	var room := _active_room()
	var room_id := String(room.get("id", "")).strip_edges()
	if room_id == "":
		return false
	var signed_frame: Dictionary = _room_replica_store.latest_for_room(room_id)
	if signed_frame.is_empty() or not _room_replica_store.verify_signed_frame(signed_frame):
		return false
	if bool(_host_takeover_attempted_rooms.get(room_id, false)):
		return false
	var frame_value = signed_frame.get("frame", {})
	if not (frame_value is Dictionary):
		return false
	var frame: Dictionary = frame_value
	var candidates := _replica_election_candidates(frame)
	var result: Dictionary = _host_election.elect(candidates)
	if not bool(result.get("ok", false)):
		_host_takeover_attempted_rooms[room_id] = true
		return false
	var elected_value = result.get("host", {})
	if not (elected_value is Dictionary):
		_host_takeover_attempted_rooms[room_id] = true
		return false
	var elected: Dictionary = elected_value
	_ensure_device_identity_loaded()
	if String(elected.get("deviceId", "")).strip_edges() != String(_device_identity.device_id).strip_edges() \
			or String(elected.get("publicKey", "")).strip_edges() != String(_device_identity.public_key).strip_edges():
		_host_takeover_attempted_rooms[room_id] = true
		_set_system_message("房主断线，等待新房主广播")
		_call_if_present("_refresh_center_panel")
		return false
	_host_takeover_attempted_rooms[room_id] = true
	return _promote_self_from_room_replica(signed_frame, int(result.get("nextElectionTerm", 0)))


func _replica_election_candidates(frame: Dictionary) -> Array:
	var result: Array = []
	var seen := {}
	var state_value = frame.get("statePayload", {})
	if not (state_value is Dictionary):
		return result
	var state_payload: Dictionary = state_value
	var players_value = state_payload.get("players", [])
	if players_value is Array:
		for i in range((players_value as Array).size()):
			var player_value = (players_value as Array)[i]
			if player_value is Dictionary:
				_append_election_candidate(result, seen, player_value as Dictionary, i, frame)
	var room_value = state_payload.get("room", {})
	if room_value is Dictionary:
		var observers_value = (room_value as Dictionary).get("observers", [])
		if observers_value is Array:
			var base_order: int = (players_value as Array).size() if players_value is Array else 0
			for i in range((observers_value as Array).size()):
				var observer_value = (observers_value as Array)[i]
				if observer_value is Dictionary:
					_append_election_candidate(result, seen, observer_value as Dictionary, base_order + i, frame)
	return result


func _append_election_candidate(result: Array, seen: Dictionary, participant: Dictionary, participant_order: int, frame: Dictionary) -> void:
	var owner := String(participant.get("owner", participant.get("type", ""))).strip_edges()
	if owner == "" or owner == "bot" or owner == "botPlayer":
		return
	var device_id := String(participant.get("device_id", participant.get("deviceId", ""))).strip_edges()
	var public_key := String(participant.get("public_key", participant.get("publicKey", ""))).strip_edges()
	if device_id == "" or public_key == "":
		return
	if device_id == String(frame.get("hostDeviceId", "")).strip_edges() and public_key == String(frame.get("hostPublicKey", "")).strip_edges():
		return
	var key := "%s|%s" % [device_id, public_key]
	if seen.has(key):
		return
	seen[key] = true
	var status: Dictionary = _room_replica_store.status_for_election(device_id, public_key, true, participant_order)
	status["participantId"] = String(participant.get("participant_id", participant.get("id", "")))
	status["seatIndex"] = participant_order
	result.append(status)


func _promote_self_from_room_replica(signed_frame: Dictionary, next_election_term: int) -> bool:
	if not _room_replica_store.verify_signed_frame(signed_frame):
		return false
	var frame_value = signed_frame.get("frame", {})
	if not (frame_value is Dictionary):
		return false
	var frame: Dictionary = frame_value
	var state_value = frame.get("statePayload", {})
	if not (state_value is Dictionary):
		return false
	_apply_replica_state_payload(state_value as Dictionary)
	_restore_takeover_ownership()
	_room_replica_election_term = max(max(next_election_term, int(frame.get("electionTerm", 0)) + 1), _room_replica_election_term)
	_room_replica_event_serial = max(_room_replica_event_serial, int(frame.get("appliedEventSerial", 0)))
	_room_replica_snapshot_version = max(_room_replica_snapshot_version, int(frame.get("snapshotVersion", 0)))
	if not bool(call("_start_host_room_network")):
		_set_system_message("房主断线，接管网络启动失败")
		_call_if_present("_refresh_center_panel")
		return false
	_call_if_present("_refresh_active_room_network_fields")
	var room := _active_room()
	if not room.is_empty():
		room["connection_mode"] = "host"
		room["discovered"] = false
		room["host_device_id"] = String(_device_identity.device_id)
		room["host_public_key"] = String(_device_identity.public_key)
		if has_method("_upsert_room"):
			call("_upsert_room", room)
	_room_session_store.clear()
	_set_system_message("房主断线，已自动接管房间")
	_call_if_present("_sync_werewolf_view_state_without_auto")
	_call_if_present("_refresh_all_seats")
	_call_if_present("_refresh_room_controls")
	_call_if_present("_refresh_center_panel")
	_call_if_present("_commit_state")
	_call_if_present("_publish_active_room")
	_call_if_present("_flash_effect", ["action"])
	return true


func _apply_replica_state_payload(payload: Dictionary) -> void:
	_applying_network_snapshot = true
	var room_value = payload.get("room", {})
	if room_value is Dictionary:
		var room: Dictionary = (room_value as Dictionary).duplicate(true)
		if has_method("_upsert_room"):
			call("_upsert_room", room)
		if _app_state != null:
			_app_state.active_room_id = String(room.get("id", _app_state.active_room_id))
	var players_value = payload.get("players", [])
	if players_value is Array:
		set("_players", _merge_local_private_player_fields((players_value as Array).duplicate(true)))
		_restore_private_controlled_profiles_from_session("replica_state_payload")
	var werewolf_value = payload.get("werewolf", {})
	if werewolf_value is Dictionary:
		set("_werewolf", (werewolf_value as Dictionary).duplicate(true))
	var previous_history := _state_array("_history").duplicate(true)
	var history_value = payload.get("history", [])
	if history_value is Array:
		var next_history := (history_value as Array).duplicate(true)
		set("_history", next_history)
		if _network_history_initialized and has_method("_present_history_delta"):
			call("_present_history_delta", previous_history, next_history)
		_network_history_initialized = true
	_set_system_message(String(payload.get("systemMessage", _state_string("_system_message"))))
	set("_phase_night", bool(payload.get("phaseNight", bool(get("_phase_night")))))
	set("_bot_serial", int(payload.get("botSerial", int(get("_bot_serial")))))
	_call_if_present("_initialize_controlled_bot_model_profiles", ["replica_state_payload", true])
	_applying_network_snapshot = false


func _restore_takeover_ownership() -> void:
	_ensure_device_identity_loaded()
	var local_device_id := String(_device_identity.device_id).strip_edges()
	var local_public_key := String(_device_identity.public_key).strip_edges()
	var previous_participant_id := _current_network_participant_id()
	var self_index := -1
	var players := _state_array("_players")
	for i in range(players.size()):
		if not (players[i] is Dictionary):
			continue
		var player: Dictionary = (players[i] as Dictionary).duplicate(true)
		var owner := String(player.get("owner", "")).strip_edges()
		if owner == "":
			players[i] = player
			continue
		if _participant_identity_matches_self(player):
			player["owner"] = "self"
			player["participant_id"] = "host"
			player["device_id"] = local_device_id
			player["public_key"] = local_public_key
			self_index = i
		else:
			player["owner"] = "human"
		players[i] = player
	set("_players", players)
	set("_local_player_index", self_index)
	if self_index >= 0 and self_index < players.size() and players[self_index] is Dictionary:
		set("_local_nickname", String((players[self_index] as Dictionary).get("name", _state_string("_local_nickname"))))
	_call_if_present("_initialize_controlled_bot_model_profiles", ["restore_takeover_ownership", true])


func _participant_identity_matches_self(participant: Dictionary) -> bool:
	_ensure_device_identity_loaded()
	var device_id := String(participant.get("device_id", participant.get("deviceId", ""))).strip_edges()
	var public_key := String(participant.get("public_key", participant.get("publicKey", ""))).strip_edges()
	return device_id != "" and public_key != "" \
		and device_id == String(_device_identity.device_id).strip_edges() \
		and public_key == String(_device_identity.public_key).strip_edges()


func _handle_active_room_discovery(room: Dictionary) -> void:
	if not _is_network_client():
		return
	var active := _active_room()
	if active.is_empty():
		return
	var discovered_device_id := String(room.get("host_device_id", "")).strip_edges()
	var discovered_public_key := String(room.get("host_public_key", "")).strip_edges()
	if discovered_device_id == "" or discovered_public_key == "":
		return
	var active_device_id := String(active.get("host_device_id", "")).strip_edges()
	var active_public_key := String(active.get("host_public_key", "")).strip_edges()
	if discovered_device_id == active_device_id and discovered_public_key == active_public_key:
		return
	var now := Time.get_ticks_msec()
	if now - _host_takeover_reconnect_last_ms < 3000:
		return
	_host_takeover_reconnect_last_ms = now
	_attempt_reconnect_to_promoted_host(room)


func _attempt_reconnect_to_promoted_host(room: Dictionary) -> bool:
	var room_id := String(room.get("id", "")).strip_edges()
	if room_id == "":
		return false
	var session: Dictionary = _room_session_store.load()
	if not _room_session_store.is_valid(session):
		return false
	if String(session.get("roomId", "")).strip_edges() != room_id:
		return false
	var host := String(room.get("host", "")).strip_edges()
	var port := int(room.get("port", 0))
	var host_device_id := String(room.get("host_device_id", "")).strip_edges()
	var host_public_key := String(room.get("host_public_key", "")).strip_edges()
	if host == "" or port <= 0 or host_device_id == "" or host_public_key == "":
		return false
	var next_room := _active_room().duplicate(true)
	if next_room.is_empty():
		next_room = room.duplicate(true)
	next_room["host"] = host
	next_room["port"] = port
	next_room["address"] = "%s:%d" % [host, port]
	next_room["host_device_id"] = host_device_id
	next_room["host_public_key"] = host_public_key
	next_room["join_payload"] = String(room.get("join_payload", next_room.get("join_payload", "")))
	next_room["connection_mode"] = "client"
	next_room["discovered"] = true
	if has_method("_upsert_room"):
		call("_upsert_room", next_room)
	if _app_state != null:
		_app_state.active_room_id = room_id
	_ensure_room_network_session()
	if _room_network_session == null:
		return false
	var result: Dictionary = _room_network_session.call(
		"connect_to_room",
		host,
		port,
		room_id,
		"",
		_state_string("_local_nickname"),
		bool(session.get("isObserver", false)),
		host_device_id,
		host_public_key,
		String(session.get("participantId", "")),
		String(session.get("reconnectToken", ""))
	)
	if not bool(result.get("ok", false)):
		_set_system_message(String(result.get("error", "重连新房主失败")))
		_call_if_present("_refresh_center_panel")
		return false
	_set_system_message("检测到新房主，正在重连")
	_call_if_present("_commit_state")
	_call_if_present("_refresh_center_panel")
	return true


func _snapshot_seat_for_participant(participant_id: String) -> int:
	if has_method("_seat_for_participant_id"):
		return int(call("_seat_for_participant_id", participant_id))
	return -1


func _state_array(property_name: String) -> Array:
	var value = get(property_name)
	return value if value is Array else []


func _state_dictionary(property_name: String) -> Dictionary:
	var value = get(property_name)
	return value if value is Dictionary else {}


func _state_string(property_name: String) -> String:
	var value = get(property_name)
	return String(value) if value != null else ""


func _set_system_message(message: String) -> void:
	set("_system_message", message)
	if has_method("_show_system_progress_toast"):
		call("_show_system_progress_toast", message)


func _call_if_present(method_name: String, args: Array = []) -> Variant:
	if not has_method(method_name):
		return null
	return callv(method_name, args)
