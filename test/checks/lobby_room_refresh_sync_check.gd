extends SceneTree

const AppStateScript := preload("res://scripts/core/app_state.gd")
const LobbyScene := preload("res://scenes/lobby.tscn")


func _initialize() -> void:
	await _assert_refresh_rebinds_state_rooms()
	await _assert_closed_discovery_removes_room()
	quit()


func _assert_refresh_rebinds_state_rooms() -> void:
	var state = AppStateScript.new()
	state.persistence_enabled = false
	state.load_or_create()
	state.rooms = [
		{"id": "room_live", "name": "实时房间", "state": "等待中", "type": "狼人杀", "players": "1/6", "lock": "公开", "address": "本机", "bg": "res://assets/images/werewolf/backgrounds/lobby.png"},
	]
	var lobby := LobbyScene.instantiate()
	lobby.set_app_state(state)
	root.add_child(lobby)
	await process_frame
	state.rooms = []
	lobby._rooms = [
		{"id": "room_stale", "name": "旧房间", "state": "等待中", "type": "狼人杀", "players": "1/6", "lock": "公开", "address": "本机", "bg": "res://assets/images/werewolf/backgrounds/lobby.png"},
	]
	lobby._refresh_lobby_rooms()
	await process_frame
	if not state.rooms.is_empty():
		_fail("lobby refresh wrote stale page rooms back to app state")
		return
	if not lobby._lobby_room_cards().is_empty():
		_fail("lobby refresh still renders stale page rooms")
		return
	lobby.queue_free()
	await process_frame


func _assert_closed_discovery_removes_room() -> void:
	var state = AppStateScript.new()
	state.persistence_enabled = false
	state.load_or_create()
	state.rooms = [
		{"id": "room_closed", "name": "将关闭", "state": "等待中", "type": "狼人杀", "players": "1/6", "lock": "公开", "address": "127.0.0.1:42871", "bg": "res://assets/images/werewolf/backgrounds/lobby.png"},
	]
	var lobby := LobbyScene.instantiate()
	lobby.set_app_state(state)
	root.add_child(lobby)
	await process_frame
	var changed := bool(lobby._handle_closed_discovered_room({
		"ok": true,
		"closed": true,
		"roomId": "room_closed",
		"host": "127.0.0.1",
		"port": 42871,
	}))
	if not changed:
		_fail("closed discovery did not report a room list change")
		return
	if not state.rooms.is_empty():
		_fail("closed discovery did not remove discovered room")
		return
	lobby.queue_free()
	await process_frame


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
