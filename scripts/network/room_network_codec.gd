extends RefCounted
class_name RoomNetworkCodec

const PROTOCOL_VERSION := 1

const CLIENT_TYPES := [
	"hello",
	"qr_secret_request",
	"join_room",
	"join_room_as_observer",
	"reconnect_room",
	"leave_room",
	"player_ready",
	"player_unready",
	"switch_seat",
	"switch_to_observer",
	"vote_map",
	"start_game",
	"add_controlled_player",
	"remove_controlled_player",
	"add_bot",
	"remove_bot",
	"update_participant",
	"game_action",
	"chat_message",
	"presentation_ack",
	"device_task_result",
	"ping",
]

const SERVER_TYPES := [
	"hello_ack",
	"qr_secret_response",
	"join_accepted",
	"join_rejected",
	"room_snapshot",
	"observer_snapshot",
	"game_snapshot",
	"game_event",
	"room_replica_frame",
	"private_message",
	"device_task",
	"action_rejected",
	"timer_updated",
	"pong",
	"room_closed",
]


func encode_client_message(type: String, message_id: String, payload: Dictionary = {}) -> String:
	return JSON.stringify(_with_envelope({
		"type": _normalize_client_type(type),
		"messageId": message_id.strip_edges(),
		"payload": payload,
	}))


func encode_server_message(type: String, message_id: String, payload: Dictionary = {}) -> String:
	return JSON.stringify(_with_envelope({
		"type": _normalize_server_type(type),
		"messageId": message_id.strip_edges(),
		"payload": payload,
	}))


func decode_client_message(data) -> Dictionary:
	var decoded := _decode_envelope(data)
	if not bool(decoded.get("ok", false)):
		return decoded
	var type := _normalize_client_type(String(decoded.get("type", "")))
	if type == "":
		return _error("Unknown client message type: %s" % String(decoded.get("type", "")))
	var message_id := String(decoded.get("messageId", "")).strip_edges()
	if message_id == "":
		return _error("Client messageId is required")
	return {
		"ok": true,
		"type": type,
		"messageId": message_id,
		"payload": _payload(decoded.get("payload", {})),
	}


func decode_server_message(data) -> Dictionary:
	var decoded := _decode_envelope(data)
	if not bool(decoded.get("ok", false)):
		return decoded
	var type := _normalize_server_type(String(decoded.get("type", "")))
	if type == "":
		return _error("Unknown server message type: %s" % String(decoded.get("type", "")))
	var message_id := String(decoded.get("messageId", "")).strip_edges()
	if message_id == "":
		return _error("Server messageId is required")
	return {
		"ok": true,
		"type": type,
		"messageId": message_id,
		"payload": _payload(decoded.get("payload", {})),
	}


func ping(message_id: String = "ping") -> String:
	return encode_client_message("ping", message_id)


func _with_envelope(body: Dictionary) -> Dictionary:
	var envelope := {
		"protocolVersion": PROTOCOL_VERSION,
		"sentAt": Time.get_unix_time_from_system(),
	}
	envelope.merge(body, true)
	return envelope


func _decode_envelope(data) -> Dictionary:
	var decoded
	if data is String:
		decoded = JSON.parse_string((data as String).strip_edges())
	elif data is PackedByteArray:
		decoded = JSON.parse_string((data as PackedByteArray).get_string_from_utf8())
	else:
		return _error("Unsupported WebSocket frame type")
	if not (decoded is Dictionary):
		return _error("Network message must be a JSON object")
	var json: Dictionary = decoded
	var version = json.get("protocolVersion", PROTOCOL_VERSION)
	if int(version) != PROTOCOL_VERSION:
		return _error("Unsupported protocol version: %s" % str(version))
	json["ok"] = true
	return json


func _normalize_client_type(type: String) -> String:
	return _normalize_type(type, CLIENT_TYPES)


func _normalize_server_type(type: String) -> String:
	return _normalize_type(type, SERVER_TYPES)


func _normalize_type(type: String, allowed: Array) -> String:
	var trimmed := type.strip_edges()
	if allowed.has(trimmed):
		return trimmed
	var snake := _camel_to_snake(trimmed)
	if allowed.has(snake):
		return snake
	return ""


func _camel_to_snake(value: String) -> String:
	var result := ""
	for i in range(value.length()):
		var ch := value.substr(i, 1)
		var lower := ch.to_lower()
		if i > 0 and ch != lower:
			result += "_"
		result += lower
	return result


func _payload(value) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}


func _error(message: String) -> Dictionary:
	return {
		"ok": false,
		"error": message,
	}
