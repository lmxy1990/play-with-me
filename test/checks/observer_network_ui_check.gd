extends SceneTree

const AppStateScript := preload("res://scripts/core/app_state.gd")
const SessionScript := preload("res://scripts/room/network/room_network_session.gd")
const LobbyScene := preload("res://scenes/lobby.tscn")
const RoomScene := preload("res://scenes/werewolf_room.tscn")

var _host_page
var _observer_page
var _player_page
var _host_session
var _observer_session
var _player_session


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
	var player_payload := String(_host_page._build_join_payload(false))
	var observer_payload := String(_host_page._build_join_payload(true))
	if player_payload == "" or observer_payload == "":
		_fail("host did not build join payload")
		return
	_host_page = await _replace_page(_host_page, RoomScene, host_state, _host_session)

	var observer_state = AppStateScript.new()
	observer_state.persistence_enabled = false
	observer_state.load_or_create()
	_observer_session = SessionScript.new()
	root.add_child(_observer_session)
	_observer_page = LobbyScene.instantiate()
	_observer_page.set_app_state(observer_state)
	_observer_page.set_network_session(_observer_session)
	root.add_child(_observer_page)
	await process_frame
	_observer_page._local_nickname = "观察者"
	if not _observer_page._join_room_from_payload(player_payload):
		_fail("observer client did not accept join payload")
		return
	await _wait_until(func() -> bool:
		return String(_observer_session.local_participant_id()).strip_edges() != "" and int(_observer_page._local_player_index) >= 0
	, 180)
	var observer_initial_index := int(_observer_page._local_player_index)
	if observer_initial_index < 0:
		_fail("observer client did not join as a player first")
		return
	if int(_host_page._observer_count(_host_page._active_room())) != 0:
		_fail("join payload registered observer directly")
		return
	_observer_page = await _replace_page(_observer_page, RoomScene, observer_state, _observer_session)

	_observer_page._switch_local_to_observer()
	await _wait_until(func() -> bool:
		return int(_observer_page._local_player_index) == -1 and int(_host_page._observer_count(_host_page._active_room())) == 1
	, 180)
	if int(_observer_page._local_player_index) != -1:
		_fail("player did not switch to observer")
		return
	if String(_host_page._players[observer_initial_index].get("owner", "")) != "":
		_fail("observer switch did not free the player seat")
		return

	_observer_page._sit_at(observer_initial_index)
	await _wait_until(func() -> bool:
		return int(_observer_page._local_player_index) == observer_initial_index and int(_host_page._observer_count(_host_page._active_room())) == 0
	, 180)
	if int(_observer_page._local_player_index) != observer_initial_index:
		_fail("observer did not switch back to player")
		return
	if int(_host_page._observer_count(_host_page._active_room())) != 0:
		_fail("observer list was not cleared after switching to player")
		return

	_observer_page._switch_local_to_observer()
	await _wait_until(func() -> bool:
		return int(_observer_page._local_player_index) == -1 and int(_host_page._observer_count(_host_page._active_room())) == 1
	, 180)
	if int(_host_page._observer_count(_host_page._active_room())) != 1:
		_fail("observer did not switch back to observer")
		return

	var player_state = AppStateScript.new()
	player_state.persistence_enabled = false
	player_state.load_or_create()
	_player_session = SessionScript.new()
	root.add_child(_player_session)
	_player_page = LobbyScene.instantiate()
	_player_page.set_app_state(player_state)
	_player_page.set_network_session(_player_session)
	root.add_child(_player_page)
	await process_frame
	_player_page._local_nickname = "真人玩家"
	if not _player_page._join_room_from_payload(player_payload):
		_fail("player did not accept join payload")
		return
	await _wait_until(func() -> bool: return int(_player_page._local_player_index) >= 0, 180)
	var player_index := int(_player_page._local_player_index)
	if player_index < 0:
		_fail("player did not receive a seat")
		return
	_player_page = await _replace_page(_player_page, RoomScene, player_state, _player_session)

	if not bool(_player_session.request_switch_to_observer()):
		_fail("switch_to_observer request was not sent")
		return
	await _wait_until(func() -> bool:
		return int(_player_page._local_player_index) == -1 and String(_host_page._players[player_index].get("owner", "")) == ""
	, 180)
	if int(_player_page._local_player_index) != -1:
		_fail("player did not become observer")
		return
	if String(_host_page._players[player_index].get("owner", "")) != "":
		_fail("player seat was not freed after switching to observer")
		return
	if int(_host_page._observer_count(_host_page._active_room())) != 2:
		_fail("switch_to_observer did not add observer")
		return

	_observer_session.send_client("leave_room", {})
	await _wait_until(func() -> bool:
		return int(_host_page._observer_count(_host_page._active_room())) == 1
	, 120)
	if int(_host_page._observer_count(_host_page._active_room())) != 1:
		_fail("observer leave did not remove observer")
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
	if _observer_session != null:
		_observer_session.stop()
	if _player_session != null:
		_player_session.stop()
	if _host_page != null:
		_host_page.queue_free()
	if _observer_page != null:
		_observer_page.queue_free()
	if _player_page != null:
		_player_page.queue_free()


func _fail(message: String) -> void:
	push_error(message)
	_cleanup()
	quit(1)
