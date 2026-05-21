extends RefCounted
class_name RoomSessionStore

const SAVE_PATH := "user://room_reconnect_session_v1.json"

var persistence_enabled := true
static var _shared_memory_session: Dictionary = {}


func load() -> Dictionary:
	if not persistence_enabled:
		return _shared_memory_session.duplicate(true)
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return {}
	var session: Dictionary = (parsed as Dictionary).duplicate(true)
	return session if is_valid(session) else {}


func save(session: Dictionary) -> void:
	var normalized := _normalize(session)
	if not is_valid(normalized):
		return
	if not persistence_enabled:
		_shared_memory_session = normalized
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(normalized, "\t"))


func clear() -> void:
	_shared_memory_session.clear()
	if persistence_enabled and FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func is_valid(session: Dictionary) -> bool:
	return String(session.get("host", "")).strip_edges() != "" \
		and int(session.get("port", 0)) > 0 \
		and String(session.get("participantId", "")).strip_edges() != "" \
		and String(session.get("reconnectToken", "")).strip_edges() != ""


func _normalize(session: Dictionary) -> Dictionary:
	return {
		"host": String(session.get("host", "")).strip_edges(),
		"port": int(session.get("port", 0)),
		"participantId": String(session.get("participantId", "")).strip_edges(),
		"reconnectToken": String(session.get("reconnectToken", "")).strip_edges(),
		"isObserver": bool(session.get("isObserver", false)),
		"roomId": String(session.get("roomId", "")).strip_edges(),
		"expectedHostDeviceId": String(session.get("expectedHostDeviceId", "")).strip_edges(),
		"expectedHostPublicKey": String(session.get("expectedHostPublicKey", "")).strip_edges(),
		"controlledPlayers": _normalize_controlled_players(session.get("controlledPlayers", session.get("controlled_players", []))),
		"savedAtMs": int(session.get("savedAtMs", Time.get_ticks_msec())),
	}


func _normalize_controlled_players(value) -> Array:
	var result := []
	if not (value is Array):
		return result
	for item in value as Array:
		if not (item is Dictionary):
			continue
		var data: Dictionary = item
		var seat_index := int(data.get("seatIndex", data.get("seat_index", -1)))
		var profile_id := String(data.get("profileId", data.get("profile_id", ""))).strip_edges()
		if seat_index < 0 or profile_id == "":
			continue
		result.append({
			"seatIndex": seat_index,
			"seatNumber": seat_index + 1,
			"playerId": String(data.get("playerId", data.get("player_id", ""))).strip_edges(),
			"profileId": profile_id,
			"displayName": String(data.get("displayName", data.get("display_name", ""))).strip_edges(),
		})
	return result
