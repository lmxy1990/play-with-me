extends SceneTree

const AppStateScript := preload("res://scripts/core/app_state.gd")
const IdentityScript := preload("res://scripts/core/device_identity.gd")
const SessionScript := preload("res://scripts/room/network/room_network_session.gd")
const LobbyScene := preload("res://scenes/lobby.tscn")
const RoomScene := preload("res://scenes/werewolf_room.tscn")

var _session


func _initialize() -> void:
	_session = SessionScript.new()
	root.add_child(_session)
	await _assert_empty_room_destroyed(false)
	await _assert_empty_room_destroyed(true)
	await _assert_observer_only_room_destroyed()
	await _assert_room_transient_data_cleared()
	await _assert_disappeared_room_artifacts_cleared()
	_session.stop()
	quit()


func _assert_empty_room_destroyed(sit_before_exit: bool) -> void:
	var state = AppStateScript.new()
	state.persistence_enabled = false
	state.load_or_create()
	var lobby := LobbyScene.instantiate()
	lobby.set_app_state(state)
	lobby.set_network_session(_session)
	root.add_child(lobby)
	await process_frame
	lobby._create_room_and_enter("狼人杀", 6, "")
	await process_frame
	if state.rooms.size() != 1:
		_fail("room was not created")
		return
	lobby.queue_free()
	await process_frame

	var room := RoomScene.instantiate()
	room.set_app_state(state)
	room.set_network_session(_session)
	root.add_child(room)
	await process_frame
	if sit_before_exit:
		room._sit_at(0)
		await process_frame
	room._prepare_leave_active_room()
	await process_frame
	if not state.rooms.is_empty():
		_fail("empty room was not destroyed after exit")
		return
	if String(state.active_room_id) != "":
		_fail("active room id was not cleared")
		return
	room.queue_free()
	await process_frame


func _assert_observer_only_room_destroyed() -> void:
	var state = AppStateScript.new()
	state.persistence_enabled = false
	state.load_or_create()
	var lobby := LobbyScene.instantiate()
	lobby.set_app_state(state)
	lobby.set_network_session(_session)
	root.add_child(lobby)
	await process_frame
	lobby._create_room_and_enter("狼人杀", 6, "")
	await process_frame
	if state.rooms.size() != 1:
		_fail("observer-only case room was not created")
		return
	lobby.queue_free()
	await process_frame

	var room := RoomScene.instantiate()
	room.set_app_state(state)
	room.set_network_session(_session)
	root.add_child(room)
	await process_frame
	room._sit_at(0)
	await process_frame
	var active_room: Dictionary = room._active_room()
	active_room["observers"] = [
		{"id": "observer_peer", "displayName": "旁观者"},
	]
	room._players[1] = room._bot_player_data("bot_profile", "bot", "model", "voice", "host")
	room._prepare_leave_active_room()
	await process_frame
	if not state.rooms.is_empty():
		_fail("observer-only room was not destroyed after last real player exit")
		return
	if String(state.active_room_id) != "":
		_fail("observer-only active room id was not cleared")
		return
	room.queue_free()
	await process_frame


func _assert_room_transient_data_cleared() -> void:
	var state = AppStateScript.new()
	state.persistence_enabled = false
	state.load_or_create()
	state.create_room("狼人杀", 6, "", "basic_village", "标准村庄")
	var room_id := String(state.active_room_id)
	var room := RoomScene.instantiate()
	room.set_app_state(state)
	room.set_network_session(_session)
	root.add_child(room)
	await process_frame
	room._room_session_store.save({
		"host": "127.0.0.1",
		"port": 42871,
		"participantId": "p1",
		"reconnectToken": "token",
		"roomId": room_id,
	})
	room._memory_manager.persistence_enabled = false
	room._memory_manager.load_or_create()
	var session_scope: Dictionary = room._memory_manager.scope("bot_profile", "werewolf", "bot_profile", "basic_village", room_id)
	var profile_scope: Dictionary = room._memory_manager.scope("bot_profile", "werewolf", "bot_profile", "basic_village", "")
	room._memory_manager.append(session_scope, {"content": "临时对局记忆", "visibility": "private"})
	room._memory_manager.save_long_term(profile_scope, "长期记忆保留", true)
	assert(room._memory_manager.list_scopes("bot_profile", "werewolf", "bot_profile").size() == 2)
	room._clear_room_transient_data(room_id)
	await process_frame
	if room._room_session_store.is_valid(room._room_session_store.load()):
		_fail("room transient cleanup did not clear reconnect session")
		return
	if not room._memory_manager.list_scopes("bot_profile", "werewolf", "bot_profile").size() == 1:
		_fail("room transient cleanup did not remove only session memory")
		return
	var profile_prompt: Dictionary = room._memory_manager.prompt_context(profile_scope)
	if not String(profile_prompt.get("longTermMemorySummary", "")).contains("长期记忆保留"):
		_fail("room transient cleanup removed long-term memory")
		return
	if String(state.active_room_id) != "":
		_fail("room transient cleanup did not clear active room id")
		return
	room.queue_free()
	await process_frame


func _assert_disappeared_room_artifacts_cleared() -> void:
	var state = AppStateScript.new()
	state.persistence_enabled = false
	state.load_or_create()
	state.rooms = [
		{
			"id": "room_stale_cleanup",
			"name": "将消失的房间",
			"state": "等待中",
			"type": "狼人杀",
			"players": "1/6",
			"lock": "公开",
			"address": "127.0.0.1:42871",
			"bg": "res://assets/images/werewolf/backgrounds/lobby.png",
			"discovered": true,
		},
	]
	var room := RoomScene.instantiate()
	room.set_app_state(state)
	room.set_network_session(_session)
	root.add_child(room)
	await process_frame
	room._room_session_store.save({
		"host": "127.0.0.1",
		"port": 42871,
		"participantId": "p1",
		"reconnectToken": "token",
		"roomId": "room_stale_cleanup",
	})
	var identity = IdentityScript.new()
	identity.persistence_enabled = false
	identity.load_or_create()
	var frame: Dictionary = room._room_replica_store.make_frame(
		"room_stale_cleanup",
		identity.device_id,
		identity.public_key,
		0,
		1,
		1,
		"roster",
		{"room": {"id": "room_stale_cleanup"}}
	)
	var signed: Dictionary = room._room_replica_store.sign_frame(frame, identity.to_stored_json())
	assert(room._room_replica_store.accept(signed))
	room._memory_manager.persistence_enabled = false
	room._memory_manager.load_or_create()
	var stale_scope: Dictionary = room._memory_manager.scope("bot_profile", "werewolf", "bot_profile", "basic_village", "room_stale_cleanup")
	var other_scope: Dictionary = room._memory_manager.scope("bot_profile", "werewolf", "bot_profile", "basic_village", "room_other")
	room._memory_manager.append(stale_scope, {"content": "应删除的房间记忆", "visibility": "private"})
	room._memory_manager.append(other_scope, {"content": "其他房间记忆", "visibility": "private"})
	var changed := bool(room._prune_stale_discovered_rooms())
	await process_frame
	if not changed:
		_fail("stale discovered room cleanup did not report a room list change")
		return
	if not state.rooms.is_empty():
		_fail("stale discovered room cleanup did not remove room")
		return
	if room._room_session_store.is_valid(room._room_session_store.load()):
		_fail("stale discovered room cleanup did not clear reconnect session")
		return
	if not room._room_replica_store.latest_for_room("room_stale_cleanup").is_empty():
		_fail("stale discovered room cleanup did not delete replica")
		return
	if room._memory_manager.list_scopes("bot_profile", "werewolf", "bot_profile").size() != 1:
		_fail("stale discovered room cleanup did not remove only matching session memory")
		return
	if String((room._memory_manager.list_scopes("bot_profile", "werewolf", "bot_profile")[0] as Dictionary).get("room_id", "")) != "room_other":
		_fail("stale discovered room cleanup removed unrelated session memory")
		return
	room.queue_free()
	await process_frame


func _fail(message: String) -> void:
	push_error(message)
	if _session != null:
		_session.stop()
	quit(1)
