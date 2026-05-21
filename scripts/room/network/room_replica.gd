extends RefCounted
class_name RoomReplicaStore

const REPLICA_DOMAIN := "chat_with_me.room_replica.v1"
const SAVE_PATH := "user://room_replicas_v1.json"
const DeviceIdentityScript := preload("res://scripts/core/device_identity.gd")

var _latest: Dictionary = {}
var _frames_by_room: Dictionary = {}
var persistence_enabled := true
var save_path := SAVE_PATH
static var _shared_memory_frames_by_room: Dictionary = {}


func load_or_create() -> void:
	if not persistence_enabled:
		_frames_by_room = _shared_memory_frames_by_room.duplicate(true)
		_latest = {}
		return
	if not FileAccess.file_exists(save_path):
		return
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return
	var frames_value = (parsed as Dictionary).get("framesByRoom", {})
	if not (frames_value is Dictionary):
		return
	_frames_by_room.clear()
	for key in (frames_value as Dictionary).keys():
		var signed_value = (frames_value as Dictionary)[key]
		if signed_value is Dictionary and verify_signed_frame(signed_value as Dictionary):
			_frames_by_room[String(key)] = (signed_value as Dictionary).duplicate(true)
	_latest = {}


func save() -> void:
	if not persistence_enabled:
		_shared_memory_frames_by_room = _frames_by_room.duplicate(true)
		return
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"version": 1,
		"framesByRoom": _frames_by_room,
	}, "\t"))


func latest() -> Dictionary:
	return _latest.duplicate(true)


func clear() -> void:
	_latest = {}


func make_frame(room_id: String, host_device_id: String, host_public_key: String, election_term: int, applied_event_serial: int, snapshot_version: int, roster_hash: String, state_payload: Dictionary) -> Dictionary:
	return {
		"roomId": room_id,
		"hostDeviceId": host_device_id,
		"hostPublicKey": host_public_key,
		"electionTerm": election_term,
		"appliedEventSerial": applied_event_serial,
		"snapshotVersion": snapshot_version,
		"rosterHash": roster_hash,
		"statePayload": state_payload.duplicate(true),
	}


func sign_frame(frame: Dictionary, identity: Dictionary) -> Dictionary:
	var device_id := String(identity.get("deviceId", "")).strip_edges()
	var public_key := String(identity.get("publicKey", "")).strip_edges()
	if device_id == "" or public_key == "":
		return {}
	if device_id != String(frame.get("hostDeviceId", "")).strip_edges() or public_key != String(frame.get("hostPublicKey", "")).strip_edges():
		return {}
	return {
		"frame": normalize_frame(frame),
		"hostAuth": DeviceIdentityScript.auth_payload_from_identity(identity, canonical_content(frame)),
	}


func accept(signed_frame: Dictionary) -> bool:
	if not verify_signed_frame(signed_frame):
		return false
	var frame := normalize_frame(signed_frame.get("frame", {}))
	var room_id := String(frame.get("roomId", "")).strip_edges()
	if room_id == "":
		return false
	var normalized_signed := {
		"frame": frame,
		"hostAuth": (signed_frame.get("hostAuth", {}) as Dictionary).duplicate(true) if signed_frame.get("hostAuth", {}) is Dictionary else {},
	}
	var current_value = _frames_by_room.get(room_id, {})
	if current_value is Dictionary and not (current_value as Dictionary).is_empty():
		var current_frame := normalize_frame((current_value as Dictionary).get("frame", {}))
		if not is_newer_frame(frame, current_frame):
			_latest = (current_value as Dictionary).duplicate(true)
			return true
	_frames_by_room[room_id] = normalized_signed
	_latest = normalized_signed.duplicate(true)
	save()
	return true


func latest_for_room(room_id: String) -> Dictionary:
	var clean := room_id.strip_edges()
	if clean == "":
		return {}
	var current_value = _frames_by_room.get(clean, {})
	if current_value is Dictionary and verify_signed_frame(current_value as Dictionary):
		_latest = (current_value as Dictionary).duplicate(true)
		return _latest.duplicate(true)
	return {}


func list_room_ids() -> Array:
	var ids: Array = []
	for key in _frames_by_room.keys():
		ids.append(String(key))
	ids.sort()
	return ids


func delete_room(room_id: String) -> void:
	var clean := room_id.strip_edges()
	if clean == "":
		return
	_frames_by_room.erase(clean)
	var latest_frame = _latest.get("frame", {})
	if latest_frame is Dictionary and String((latest_frame as Dictionary).get("roomId", "")) == clean:
		_latest = {}
	save()


func status_for_election(device_id: String, public_key: String, can_host: bool, participant_order: int = 1 << 30) -> Dictionary:
	var frame: Dictionary = normalize_frame(_latest.get("frame", {})) if _latest.get("frame", {}) is Dictionary else {}
	return {
		"deviceId": device_id,
		"publicKey": public_key,
		"electionTerm": int(frame.get("electionTerm", 0)),
		"appliedEventSerial": int(frame.get("appliedEventSerial", 0)),
		"snapshotVersion": int(frame.get("snapshotVersion", 0)),
		"canHost": can_host,
		"participantOrder": participant_order,
	}


static func verify_signed_frame(signed_frame: Dictionary) -> bool:
	var frame_value = signed_frame.get("frame", {})
	var auth_value = signed_frame.get("hostAuth", {})
	if not (frame_value is Dictionary) or not (auth_value is Dictionary):
		return false
	var frame := normalize_frame(frame_value as Dictionary)
	var auth: Dictionary = auth_value
	if String(auth.get("deviceId", "")).strip_edges() != String(frame.get("hostDeviceId", "")).strip_edges():
		return false
	if String(auth.get("publicKey", "")).strip_edges() != String(frame.get("hostPublicKey", "")).strip_edges():
		return false
	return DeviceIdentityScript.verify_auth_payload(auth, canonical_content(frame))


static func normalize_frame(frame: Dictionary) -> Dictionary:
	return {
		"roomId": String(frame.get("roomId", "")),
		"hostDeviceId": String(frame.get("hostDeviceId", "")),
		"hostPublicKey": String(frame.get("hostPublicKey", "")),
		"electionTerm": int(frame.get("electionTerm", 0)),
		"appliedEventSerial": int(frame.get("appliedEventSerial", 0)),
		"snapshotVersion": int(frame.get("snapshotVersion", 0)),
		"rosterHash": String(frame.get("rosterHash", "")),
		"statePayload": (frame.get("statePayload", {}) as Dictionary).duplicate(true) if frame.get("statePayload", {}) is Dictionary else {},
	}


static func canonical_content(frame: Dictionary) -> String:
	return "%s\n%s" % [REPLICA_DOMAIN, canonical_json(normalize_frame(frame))]


static func canonical_json(value) -> String:
	return JSON.stringify(_canonical_value(value))


static func is_newer_frame(left: Dictionary, right: Dictionary) -> bool:
	var left_frame := normalize_frame(left)
	var right_frame := normalize_frame(right)
	var serial_compare := int(left_frame.get("appliedEventSerial", 0)) - int(right_frame.get("appliedEventSerial", 0))
	if serial_compare != 0:
		return serial_compare > 0
	var snapshot_compare := int(left_frame.get("snapshotVersion", 0)) - int(right_frame.get("snapshotVersion", 0))
	if snapshot_compare != 0:
		return snapshot_compare > 0
	return int(left_frame.get("electionTerm", 0)) > int(right_frame.get("electionTerm", 0))


static func _canonical_value(value):
	if value is Dictionary:
		var keys: Array = []
		for key in (value as Dictionary).keys():
			keys.append(String(key))
		keys.sort()
		var result := {}
		for key in keys:
			result[key] = _canonical_value((value as Dictionary).get(key))
		return result
	if value is Array:
		var result: Array = []
		for item in value as Array:
			result.append(_canonical_value(item))
		return result
	return value
