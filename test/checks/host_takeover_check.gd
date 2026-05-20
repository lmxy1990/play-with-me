extends SceneTree

const AppStateScript := preload("res://scripts/core/app_state.gd")
const SessionScript := preload("res://scripts/room/network/room_network_session.gd")
const LobbyScene := preload("res://scenes/lobby.tscn")
const RoomScene := preload("res://scenes/werewolf_room.tscn")

var _host_page
var _client_page
var _host_session
var _client_session


func _initialize() -> void:
	var host_state = AppStateScript.new()
	host_state.persistence_enabled = false
	host_state.load_or_create()
	_host_session = SessionScript.new()
	root.add_child(_host_session)
	_host_page = LobbyScene.instantiate()
	_host_page.set_app_state(host_state)
	_host_page.set_network_session(_host_session)
	root.add_child(_host_page)
	await process_frame
	_host_page._create_room_and_enter("狼人杀", 6, "")
	await process_frame
	var room_id := String(host_state.active_room_id)
	var payload := String(_host_page._build_join_payload(false))
	if payload == "":
		_fail("host did not build join payload")
		return
	_host_page = await _replace_page(_host_page, RoomScene, host_state, _host_session)

	var client_state = AppStateScript.new()
	client_state.persistence_enabled = false
	client_state.load_or_create()
	_client_session = SessionScript.new()
	root.add_child(_client_session)
	_client_page = LobbyScene.instantiate()
	_client_page.set_app_state(client_state)
	_client_page.set_network_session(_client_session)
	root.add_child(_client_page)
	await process_frame
	_client_page._local_nickname = "接管玩家"
	if not _client_page._join_room_from_payload(payload):
		_fail("client did not accept join payload")
		return
	await _wait_until(func() -> bool: return int(_client_page._local_player_index) >= 0, 180)
	if int(_client_page._local_player_index) < 0:
		_fail("client did not receive joined seat")
		return
	_client_page = await _replace_page(_client_page, RoomScene, client_state, _client_session)
	var client_index := int(_client_page._local_player_index)
	_client_page._toggle_ready()
	await _wait_until(func() -> bool:
		return client_index >= 0 and bool(_host_page._players[client_index].get("ready", false))
	, 180)
	if client_index < 0 or not bool(_host_page._players[client_index].get("ready", false)):
		_fail("host did not receive ready request before takeover")
		return
	var signed_replica: Dictionary = _host_page._signed_room_replica_payload()
	if signed_replica.is_empty():
		_fail("host did not create signed room replica")
		return
	_client_page._accept_network_room_replica(signed_replica)
	await _wait_until(func() -> bool:
		return not (_client_page._room_replica_store.latest_for_room(room_id) as Dictionary).is_empty()
	, 180)
	if (_client_page._room_replica_store.latest_for_room(room_id) as Dictionary).is_empty():
		_fail("client did not persist latest room replica")
		return

	_host_session.stop()
	if _host_page != null:
		_host_page.queue_free()
		_host_page = null
	await _wait_until(func() -> bool:
		return bool(_client_page._is_network_host()) and String(_client_page._system_message).contains("自动接管")
	, 240)
	if not bool(_client_page._is_network_host()):
		_fail("client did not promote itself to host")
		return
	if not String(_client_page._system_message).contains("自动接管"):
		_fail("takeover status message was not shown")
		return
	var active_room: Dictionary = _client_page._active_room()
	if String(active_room.get("host_device_id", "")) != String(_client_page._device_identity.device_id):
		_fail("promoted room did not expose client device as host")
		return
	if int(_client_page._local_player_index) < 0:
		_fail("promoted client lost its local seat")
		return
	var local_player: Dictionary = _client_page._players[int(_client_page._local_player_index)]
	if String(local_player.get("owner", "")) != "self":
		_fail("promoted client seat was not restored as self")
		return
	if int(_client_page._room_replica_election_term) <= 0:
		_fail("election term did not advance")
		return
	_cleanup()
	quit()


func _wait_until(predicate: Callable, frames: int) -> void:
	for _i in range(frames):
		if bool(predicate.call()):
			return
		await process_frame


func _replace_page(page, packed: PackedScene, state, session):
	var identity := {}
	if page != null:
		identity = page._device_identity.to_stored_json()
	if page != null:
		page.queue_free()
	await process_frame
	var next_page = packed.instantiate()
	if not identity.is_empty():
		next_page._device_identity.device_id = String(identity.get("deviceId", ""))
		next_page._device_identity.public_key = String(identity.get("publicKey", ""))
		next_page._device_identity.private_key = String(identity.get("privateKey", ""))
		next_page._device_identity.algorithm = String(identity.get("algorithm", "godot_sha256_v1"))
	next_page.set_app_state(state)
	next_page.set_network_session(session)
	root.add_child(next_page)
	await process_frame
	return next_page


func _cleanup() -> void:
	if _host_session != null:
		_host_session.stop()
	if _client_session != null:
		_client_session.stop()
	if _host_page != null:
		_host_page.queue_free()
	if _client_page != null:
		_client_page.queue_free()


func _fail(message: String) -> void:
	push_error(message)
	_cleanup()
	quit(1)
