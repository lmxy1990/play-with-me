extends "res://scripts/pages/base/page_model_ui_base.gd"

enum Mode { LOBBY, TABLE, PREFERENCES, MODEL_CONFIG, VOICE_CONFIG, BOT_CONFIG, REPLAY }

const LanRoomDiscoveryScript := preload("res://scripts/network/lan_room_discovery.gd")

var _mode: int = Mode.LOBBY
var _rooms := []
var _room_discovery = LanRoomDiscoveryScript.new()
var _discovery_publish_elapsed := 0.0
var _discovery_poll_elapsed := 0.0


func _setup_room_discovery() -> void:
	_room_discovery.start()


func _tick_room_discovery(delta: float) -> void:
	_discovery_poll_elapsed += delta
	if _discovery_poll_elapsed >= 0.35:
		_discovery_poll_elapsed = 0.0
		var changed := _poll_discovered_rooms()
		if _mode == Mode.LOBBY and _prune_stale_discovered_rooms():
			changed = true
		if changed and _mode == Mode.LOBBY:
			call("_show_lobby")
	_discovery_publish_elapsed += delta
	if _discovery_publish_elapsed >= 2.0:
		_discovery_publish_elapsed = 0.0
		if _mode == Mode.TABLE:
			call("_publish_active_room")


func _poll_discovered_rooms() -> bool:
	var changed := false
	var discovered: Array = _room_discovery.poll()
	for item in discovered:
		if item is Dictionary:
			if _handle_closed_discovered_room(item as Dictionary):
				changed = true
				continue
			var room := _room_discovery.app_room_from_discovery(item as Dictionary)
			if _upsert_discovered_room(room):
				changed = true
	return changed


func _merge_discovered_rooms() -> void:
	for item in _room_discovery.discovered_rooms():
		if item is Dictionary:
			if bool((item as Dictionary).get("closed", false)):
				_handle_closed_discovered_room(item as Dictionary)
				continue
			_upsert_discovered_room(_room_discovery.app_room_from_discovery(item as Dictionary))
	_prune_stale_discovered_rooms()


func _refresh_lobby_rooms() -> void:
	call("_bind_state")
	_poll_discovered_rooms()
	_merge_discovered_rooms()
	set("_system_message", "房间列表已刷新")
	call("_commit_state")
	if _mode == Mode.LOBBY:
		call("_show_lobby")


func _prune_stale_discovered_rooms() -> bool:
	var active_id := String(_app_state.active_room_id) if _app_state != null else ""
	var live_ids := {}
	for item in _room_discovery.discovered_rooms():
		if item is Dictionary:
			var id := String((item as Dictionary).get("roomId", "")).strip_edges()
			if id != "":
				live_ids[id] = true
	var changed := false
	for i in range(_rooms.size() - 1, -1, -1):
		if not (_rooms[i] is Dictionary):
			continue
		var room: Dictionary = _rooms[i]
		var room_id := String(room.get("id", ""))
		if room_id == active_id:
			continue
		if bool(room.get("discovered", false)) and not live_ids.has(room_id):
			_clear_disappeared_room_artifacts(room_id)
			_rooms.remove_at(i)
			changed = true
	if changed:
		call("_commit_state")
	return changed


func _upsert_discovered_room(room: Dictionary) -> bool:
	var room_id := String(room.get("id", ""))
	if room_id == "":
		return false
	if _app_state != null and room_id == String(_app_state.active_room_id):
		call("_handle_active_room_discovery", room)
		return false
	for i in range(_rooms.size()):
		if String(_rooms[i].get("id", "")) == room_id:
			if JSON.stringify(_rooms[i]) == JSON.stringify(room):
				return false
			_rooms[i] = room
			call("_commit_state")
			return true
	_rooms.append(room)
	call("_commit_state")
	return true


func _handle_closed_discovered_room(room: Dictionary) -> bool:
	if not bool(room.get("closed", false)):
		return false
	var room_id := String(room.get("roomId", room.get("id", ""))).strip_edges()
	if room_id == "":
		return false
	var active_id := String(_app_state.active_room_id) if _app_state != null else ""
	var changed := false
	for i in range(_rooms.size() - 1, -1, -1):
		if _rooms[i] is Dictionary and String((_rooms[i] as Dictionary).get("id", "")) == room_id:
			_rooms.remove_at(i)
			changed = true
	var is_client := has_method("_is_network_client") and bool(call("_is_network_client"))
	if active_id == room_id and is_client:
		if has_method("_clear_room_transient_data"):
			call("_clear_room_transient_data", room_id)
		set("_system_message", "房间已关闭")
		changed = true
	else:
		_clear_disappeared_room_artifacts(room_id)
	if changed:
		call("_commit_state")
		if active_id == room_id and is_client and int(get("_mode")) == Mode.TABLE:
			call("_show_lobby")
	return changed


func _clear_disappeared_room_artifacts(room_id: String) -> void:
	var clean_room_id := room_id.strip_edges()
	if clean_room_id == "":
		return
	if has_method("_clear_room_runtime_artifacts"):
		call("_clear_room_runtime_artifacts", clean_room_id)


func _active_room() -> Dictionary:
	if _app_state == null:
		if not _rooms.is_empty() and _rooms[0] is Dictionary:
			return _rooms[0]
		return {}
	var active_id := String(_app_state.active_room_id)
	for room in _rooms:
		if room is Dictionary and String(room.get("id", "")) == active_id:
			return room as Dictionary
	return {}


func _local_host_address() -> String:
	return LanRoomDiscoveryScript.local_ipv4()
