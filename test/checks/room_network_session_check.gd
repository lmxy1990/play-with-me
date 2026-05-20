extends SceneTree

const SessionScript := preload("res://scripts/room/network/room_network_session.gd")
const IdentityScript := preload("res://scripts/core/device_identity.gd")
const QrJoinPayloadScript := preload("res://scripts/network/qr_join_payload.gd")
const CodecScript := preload("res://scripts/network/room_network_codec.gd")

var _host
var _client
var _bad_client
var _secure_client
var _join_seen := false
var _accepted := false
var _switch_seen := false
var _reconnect_seen := false
var _bad_rejected := false
var _secure_join_seen := false
var _secure_accepted := false
var _secure_secret_id := ""
var _secure_secret_key := ""


func _initialize() -> void:
	var host_identity = IdentityScript.new()
	host_identity.persistence_enabled = false
	host_identity.load_or_create()
	var client_identity = IdentityScript.new()
	client_identity.persistence_enabled = false
	client_identity.load_or_create()
	var secure_identity = IdentityScript.new()
	secure_identity.persistence_enabled = false
	secure_identity.load_or_create()
	_host = SessionScript.new()
	_client = SessionScript.new()
	_bad_client = SessionScript.new()
	_secure_client = SessionScript.new()
	_host.set_device_identity(host_identity.to_stored_json())
	_client.set_device_identity(client_identity.to_stored_json())
	_bad_client.set_device_identity(client_identity.to_stored_json())
	_secure_client.set_device_identity(secure_identity.to_stored_json())
	root.add_child(_host)
	root.add_child(_client)
	root.add_child(_bad_client)
	root.add_child(_secure_client)
	_host.client_message_received.connect(_on_host_client_message)
	_client.join_accepted.connect(func(_payload: Dictionary) -> void:
		_accepted = true
	)
	_bad_client.join_rejected.connect(func(_message: String) -> void:
		_bad_rejected = true
	)
	_secure_client.join_accepted.connect(func(_payload: Dictionary) -> void:
		_secure_accepted = true
	)
	var started: Dictionary = _host.start_host(43971, "127.0.0.1")
	if not bool(started.get("ok", false)):
		_fail(String(started.get("error", "host failed")))
		return
	var host_public: Dictionary = host_identity.to_public_json()
	var connected: Dictionary = _client.connect_to_room(
		"127.0.0.1",
		int(started["port"]),
		"room_net_check",
		"token",
		"联网测试",
		false,
		String(host_public.get("deviceId", "")),
		String(host_public.get("publicKey", ""))
	)
	if not bool(connected.get("ok", false)):
		_fail(String(connected.get("error", "client failed")))
		return
	await _wait_until(func() -> bool: return _accepted, 180)
	if not _accepted or not _join_seen:
		_fail("join was not completed")
		return
	_client.request_switch_seat(2)
	await _wait_until(func() -> bool: return _switch_seen, 90)
	if not _switch_seen:
		_fail("switch seat message was not received")
		return
	_client.stop()
	_accepted = false
	var reconnected: Dictionary = _client.connect_to_room(
		"127.0.0.1",
		int(started["port"]),
		"room_net_check",
		"",
		"联网测试",
		false,
		"",
		"",
		"peer_check",
		"token_reconnect"
	)
	if not bool(reconnected.get("ok", false)):
		_fail(String(reconnected.get("error", "reconnect failed")))
		return
	await _wait_until(func() -> bool: return _accepted and _reconnect_seen, 180)
	if not _accepted or not _reconnect_seen:
		_fail("reconnect was not completed")
		return
	var bad_connected: Dictionary = _bad_client.connect_to_room(
		"127.0.0.1",
		int(started["port"]),
		"room_net_check",
		"token",
		"联网测试",
		false,
		"device_wrong",
		String(host_public.get("publicKey", ""))
	)
	if not bool(bad_connected.get("ok", false)):
		_fail(String(bad_connected.get("error", "bad client connect failed")))
		return
	await _wait_until(func() -> bool: return _bad_rejected, 120)
	if not _bad_rejected:
		_fail("host identity mismatch was not rejected")
		return
	var qr = QrJoinPayloadScript.new()
	_secure_secret_id = qr.generate_secret_id()
	_secure_secret_key = qr.generate_secret_key()
	var secure_encoded: String = qr.build_secure_encoded(
		"127.0.0.1",
		int(started["port"]),
		"room_net_check",
		"Secure Net Check",
		"werewolf",
		false,
		"token",
		String(host_public.get("deviceId", "")),
		String(host_public.get("publicKey", "")),
		"",
		"",
		"",
		_secure_secret_id,
		_secure_secret_key,
		CodecScript.PROTOCOL_VERSION
	)
	var secure_payload: Dictionary = qr.parse(secure_encoded)
	if not bool(secure_payload.get("ok", false)):
		_fail(String(secure_payload.get("error", "secure payload parse failed")))
		return
	var secure_connected: Dictionary = _secure_client.connect_to_secure_qr(
		"127.0.0.1",
		int(started["port"]),
		secure_payload,
		"secure qr client"
	)
	if not bool(secure_connected.get("ok", false)):
		_fail(String(secure_connected.get("error", "secure qr connect failed")))
		return
	await _wait_until(func() -> bool: return _secure_accepted and _secure_join_seen, 180)
	if not _secure_accepted or not _secure_join_seen:
		_fail("secure qr join was not completed")
		return
	_host.stop()
	_client.stop()
	_bad_client.stop()
	_secure_client.stop()
	quit()


func _on_host_client_message(peer_id: int, type: String, message_id: String, payload: Dictionary) -> void:
	if type == "qr_secret_request":
		var public_key := CryptoKey.new()
		if String(payload.get("secretId", "")) != _secure_secret_id or public_key.load_from_string(String(payload.get("publicKey", "")), true) != OK:
			_host.send_to_peer(peer_id, "qr_secret_response", {
				"ok": false,
				"message": "qr secret request failed",
			}, message_id)
			return
		var wrapped := Crypto.new().encrypt(public_key, _base64_url_decode(_secure_secret_key))
		_host.send_to_peer(peer_id, "qr_secret_response", {
			"ok": true,
			"secretId": _secure_secret_id,
			"wrappedKey": _base64_url(wrapped),
		}, message_id)
	elif type == "join_room":
		var display_name := String(payload.get("displayName", ""))
		if display_name == "secure qr client":
			_secure_join_seen = String(payload.get("roomId", "")) == "room_net_check" and String(payload.get("joinToken", "")) == "token"
			_host.set_peer_participant(peer_id, "peer_secure", 1, display_name)
			_host.send_to_peer(peer_id, "join_accepted", {
				"participantId": "peer_secure",
				"participant": {"displayName": display_name, "seatNumber": 2},
				"reconnectToken": "token_secure",
				"room": {
					"participantId": "peer_secure",
					"localPlayerIndex": 1,
					"players": [],
					"werewolf": {},
					"history": [],
					"systemMessage": "secure ok",
				},
			}, message_id)
			return
		_join_seen = true
		_host.set_peer_participant(peer_id, "peer_check", 0, display_name)
		_host.send_to_peer(peer_id, "join_accepted", {
			"participantId": "peer_check",
			"participant": {"displayName": display_name, "seatNumber": 1},
			"reconnectToken": "token_reconnect",
			"room": {
				"participantId": "peer_check",
				"localPlayerIndex": 0,
				"players": [],
				"werewolf": {},
				"history": [],
				"systemMessage": "ok",
			},
		}, message_id)
	elif type == "switch_seat":
		_switch_seen = int(payload.get("seatIndex", -1)) == 2
	elif type == "reconnect_room":
		_reconnect_seen = String(payload.get("participantId", "")) == "peer_check" and String(payload.get("reconnectToken", "")) == "token_reconnect"
		_host.set_peer_participant(peer_id, "peer_check", 0, "联网测试")
		_host.send_to_peer(peer_id, "join_accepted", {
			"participantId": "peer_check",
			"participant": {"displayName": "联网测试", "seatNumber": 1},
			"reconnectToken": "token_reconnect",
			"reconnected": true,
			"room": {
				"participantId": "peer_check",
				"localPlayerIndex": 0,
				"players": [],
				"werewolf": {},
				"history": [],
				"systemMessage": "reconnected",
			},
		}, message_id)


func _wait_until(predicate: Callable, frames: int) -> void:
	for _i in range(frames):
		if bool(predicate.call()):
			return
		await process_frame


func _fail(message: String) -> void:
	push_error(message)
	if _host != null:
		_host.stop()
	if _client != null:
		_client.stop()
	if _bad_client != null:
		_bad_client.stop()
	if _secure_client != null:
		_secure_client.stop()
	quit(1)


func _base64_url(bytes: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_").replace("=", "")


func _base64_url_decode(value: String) -> PackedByteArray:
	var text := value.strip_edges().replace("-", "+").replace("_", "/")
	while text.length() % 4 != 0:
		text += "="
	return Marshalls.base64_to_raw(text)
