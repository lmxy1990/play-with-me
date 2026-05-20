extends SceneTree

const AppStateScript := preload("res://scripts/core/app_state.gd")
const LobbyScene := preload("res://scenes/lobby.tscn")

var _page


func _initialize() -> void:
	var state = AppStateScript.new()
	state.persistence_enabled = false
	state.load_or_create()
	_page = LobbyScene.instantiate()
	_page.set_app_state(state)
	root.add_child(_page)
	await process_frame
	_page._create_room_and_enter("狼人杀", 6, "")
	var room: Dictionary = _page._active_room()
	room["allow_observers"] = false
	var disabled: Dictionary = _page._can_add_observer(room)
	assert(not bool(disabled.get("ok", false)))
	assert(String(disabled.get("code", "")) == "observer_disabled")
	room["allow_observers"] = true
	room["max_observers"] = 1
	room["observers"] = [{"id": "observer_1", "displayName": "观者"}]
	var full: Dictionary = _page._can_add_observer(room)
	assert(not bool(full.get("ok", false)))
	assert(String(full.get("code", "")) == "observer_full")
	room["max_observers"] = 2
	var open: Dictionary = _page._can_add_observer(room)
	assert(bool(open.get("ok", false)))
	_page.queue_free()
	quit()
