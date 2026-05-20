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
	_client_page._local_nickname = "客户端"
	if not _client_page._join_room_from_payload(payload):
		_fail("client did not accept join payload")
		return
	await _wait_until(func() -> bool: return int(_client_page._local_player_index) >= 0, 180)
	if int(_client_page._local_player_index) < 0:
		_fail("client did not receive joined seat")
		return
	_client_page = await _replace_page(_client_page, RoomScene, client_state, _client_session)
	_client_page._toggle_ready()
	await _wait_until(func() -> bool:
		var index := int(_client_page._local_player_index)
		return index >= 0 and bool(_host_page._players[index].get("ready", false))
	, 120)
	var ready_index := int(_client_page._local_player_index)
	if ready_index < 0 or not bool(_host_page._players[ready_index].get("ready", false)):
		_fail("host did not receive ready request")
		return
	var saved_session: Dictionary = _client_page._room_session_store.load()
	if not _client_page._room_session_store.is_valid(saved_session):
		_fail("client did not save reconnect session")
		return
	_client_session.stop()
	await process_frame
	if not _client_page._reconnect_last_room():
		_fail("client did not start reconnect")
		return
	await _wait_until(func() -> bool:
		return int(_client_page._local_player_index) == ready_index and String(_host_page._players[ready_index].get("state", "")) != "离线"
	, 180)
	if int(_client_page._local_player_index) != ready_index:
		_fail("client did not recover previous seat")
		return
	_cleanup()
	quit()


func _wait_until(predicate: Callable, frames: int) -> void:
	for _i in range(frames):
		if bool(predicate.call()):
			return
		await process_frame


func _replace_page(page, packed: PackedScene, state, session):
	if page != null:
		page.queue_free()
	await process_frame
	var next_page = packed.instantiate()
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
