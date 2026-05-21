extends Node
class_name RoomNetworkSession

signal host_started(port: int)
signal host_failed(error: String)
signal status_changed(message: String)
signal client_message_received(peer_id: int, type: String, message_id: String, payload: Dictionary)
signal server_message_received(type: String, message_id: String, payload: Dictionary)
signal snapshot_received(snapshot: Dictionary)
signal join_accepted(payload: Dictionary)
signal join_rejected(message: String)
signal peer_disconnected(peer_id: int)

const ROLE_NONE := "none"
const ROLE_HOST := "host"
const ROLE_CLIENT := "client"
const DEFAULT_PORT := 42871
const MAX_PORT_ATTEMPTS := 24
const HOST_PARTICIPANT_ID := "host"
const CLIENT_JOIN_TIMEOUT_MS := 12000

const CodecScript := preload("res://scripts/network/room_network_codec.gd")
const DeviceIdentityScript := preload("res://scripts/core/device_identity.gd")
const QrJoinPayloadScript := preload("res://scripts/network/qr_join_payload.gd")

var _codec = CodecScript.new()
var _qr_join_payload = QrJoinPayloadScript.new()
var _role := ROLE_NONE
var _server: TCPServer
var _peers: Dictionary = {}
var _next_peer_id := 1
var _client_peer: WebSocketPeer
var _client_opened := false
var _client_hello_sent := false
var _client_join_sent := false
var _client_host := ""
var _client_room_id := ""
var _client_join_token := ""
var _client_display_name := ""
var _client_as_observer := false
var _client_expected_host_device_id := ""
var _client_expected_host_public_key := ""
var _client_observed_host_device_id := ""
var _client_observed_host_public_key := ""
var _client_reconnect_participant_id := ""
var _client_reconnect_token := ""
var _client_host_identity_checked := false
var _client_challenge := ""
var _client_server_challenge := ""
var _client_secure_qr_payload := {}
var _client_qr_private_key = null
var _client_qr_secret_requested := false
var _client_qr_secret_resolved := false
var _client_started_at_ms := 0
var _client_join_completed := false
var _port := 0
var _message_serial := 1
var _local_participant_id := ""
var _device_identity := {}


func role() -> String:
	return _role


func is_host() -> bool:
	return _role == ROLE_HOST


func is_client() -> bool:
	return _role == ROLE_CLIENT


func is_active() -> bool:
	return _role != ROLE_NONE


func port() -> int:
	return _port


func local_participant_id() -> String:
	if _local_participant_id != "":
		return _local_participant_id
	return HOST_PARTICIPANT_ID if is_host() else ""


func set_device_identity(identity: Dictionary) -> void:
	if _role != ROLE_NONE and String(_device_identity.get("deviceId", "")).strip_edges() != "":
		return
	_device_identity = identity.duplicate(true)


func start_host(preferred_port: int = DEFAULT_PORT, bind_address: String = "*") -> Dictionary:
	stop()
	var first_port: int = preferred_port if preferred_port > 0 else DEFAULT_PORT
	for offset in range(MAX_PORT_ATTEMPTS):
		var candidate: int = first_port + offset
		var server := TCPServer.new()
		var err := server.listen(candidate, bind_address)
		if err != OK:
			continue
		_server = server
		_role = ROLE_HOST
		_port = candidate
		_local_participant_id = HOST_PARTICIPANT_ID
		status_changed.emit("房间网络已开启：%d" % candidate)
		host_started.emit(candidate)
		return {"ok": true, "port": candidate, "error": ""}
	var error := "无法监听房间端口：%d" % first_port
	host_failed.emit(error)
	status_changed.emit(error)
	return {"ok": false, "port": 0, "error": error}


func connect_to_room(host: String, port_value: int, room_id: String, join_token: String, display_name: String, as_observer: bool = false, expected_host_device_id: String = "", expected_host_public_key: String = "", reconnect_participant_id: String = "", reconnect_token: String = "") -> Dictionary:
	stop()
	var clean_host := host.strip_edges()
	if clean_host == "" or port_value <= 0:
		var error := "房间地址无效"
		status_changed.emit(error)
		return {"ok": false, "error": error}
	_client_peer = WebSocketPeer.new()
	_client_peer.set_inbound_buffer_size(1024 * 1024)
	_client_peer.set_outbound_buffer_size(1024 * 1024)
	_client_room_id = room_id.strip_edges()
	_client_host = clean_host
	_client_join_token = join_token.strip_edges()
	_client_display_name = display_name.strip_edges()
	_client_as_observer = as_observer
	_client_expected_host_device_id = expected_host_device_id.strip_edges()
	_client_expected_host_public_key = expected_host_public_key.strip_edges()
	_client_observed_host_device_id = ""
	_client_observed_host_public_key = ""
	_client_reconnect_participant_id = reconnect_participant_id.strip_edges()
	_client_reconnect_token = reconnect_token.strip_edges()
	_client_host_identity_checked = false
	_client_challenge = _nonce(16)
	_client_server_challenge = ""
	_client_secure_qr_payload = {}
	_client_qr_private_key = null
	_client_qr_secret_requested = false
	_client_qr_secret_resolved = true
	_client_started_at_ms = Time.get_ticks_msec()
	_client_join_completed = false
	_client_hello_sent = false
	_client_opened = false
	_client_join_sent = false
	_role = ROLE_CLIENT
	_port = port_value
	var url := "ws://%s:%d" % [clean_host, port_value]
	var err := _client_peer.connect_to_url(url)
	if err != OK:
		var message := "连接房间失败：%s" % error_string(err)
		stop()
		status_changed.emit(message)
		return {"ok": false, "error": message}
	status_changed.emit("正在连接房间：%s" % url)
	return {"ok": true, "error": ""}


func connect_to_secure_qr(host: String, port_value: int, secure_payload: Dictionary, display_name: String) -> Dictionary:
	stop()
	var clean_host := host.strip_edges()
	if clean_host == "" or port_value <= 0:
		var error := "房间地址无效"
		status_changed.emit(error)
		return {"ok": false, "error": error}
	if not bool(secure_payload.get("secure", false)) or String(secure_payload.get("secretId", "")).strip_edges() == "":
		var error := "加密加入码无效"
		status_changed.emit(error)
		return {"ok": false, "error": error}
	var crypto := Crypto.new()
	_client_qr_private_key = crypto.generate_rsa(2048)
	if _client_qr_private_key == null:
		var error := "二维码密钥协商初始化失败"
		status_changed.emit(error)
		return {"ok": false, "error": error}
	_client_peer = WebSocketPeer.new()
	_client_peer.set_inbound_buffer_size(1024 * 1024)
	_client_peer.set_outbound_buffer_size(1024 * 1024)
	_client_host = clean_host
	_client_room_id = ""
	_client_join_token = ""
	_client_display_name = display_name.strip_edges()
	_client_as_observer = false
	_client_expected_host_device_id = ""
	_client_expected_host_public_key = ""
	_client_observed_host_device_id = ""
	_client_observed_host_public_key = ""
	_client_reconnect_participant_id = ""
	_client_reconnect_token = ""
	_client_host_identity_checked = false
	_client_challenge = _nonce(16)
	_client_server_challenge = ""
	_client_secure_qr_payload = secure_payload.duplicate(true)
	_client_qr_secret_requested = false
	_client_qr_secret_resolved = false
	_client_started_at_ms = Time.get_ticks_msec()
	_client_join_completed = false
	_client_hello_sent = false
	_client_opened = false
	_client_join_sent = false
	_role = ROLE_CLIENT
	_port = port_value
	var url := "ws://%s:%d" % [clean_host, port_value]
	var err := _client_peer.connect_to_url(url)
	if err != OK:
		var message := "连接房间失败：%s" % error_string(err)
		stop()
		status_changed.emit(message)
		return {"ok": false, "error": message}
	status_changed.emit("正在连接房间：%s" % url)
	return {"ok": true, "error": ""}


func stop() -> void:
	if _server != null:
		_server.stop()
	_server = null
	for peer_id in _peers.keys():
		var peer_data: Dictionary = _peers[peer_id]
		var peer := peer_data.get("peer") as WebSocketPeer
		if peer != null:
			peer.close()
	_peers.clear()
	if _client_peer != null:
		_client_peer.close()
	_client_peer = null
	_client_opened = false
	_client_hello_sent = false
	_client_join_sent = false
	_client_host = ""
	_client_room_id = ""
	_client_join_token = ""
	_client_display_name = ""
	_client_as_observer = false
	_client_expected_host_device_id = ""
	_client_expected_host_public_key = ""
	_client_observed_host_device_id = ""
	_client_observed_host_public_key = ""
	_client_reconnect_participant_id = ""
	_client_reconnect_token = ""
	_client_host_identity_checked = false
	_client_challenge = ""
	_client_server_challenge = ""
	_client_secure_qr_payload = {}
	_client_qr_private_key = null
	_client_qr_secret_requested = false
	_client_qr_secret_resolved = false
	_client_started_at_ms = 0
	_client_join_completed = false
	_role = ROLE_NONE
	_port = 0
	_local_participant_id = ""


func peer_participant_id(peer_id: int) -> String:
	if not _peers.has(peer_id):
		return ""
	var data: Dictionary = _peers[peer_id]
	return String(data.get("participant_id", ""))


func peer_ids() -> Array:
	var ids := []
	for peer_id in _peers.keys():
		ids.append(int(peer_id))
	return ids


func peer_seat_index(peer_id: int) -> int:
	if not _peers.has(peer_id):
		return -1
	var data: Dictionary = _peers[peer_id]
	return int(data.get("seat_index", -1))


func peer_debug_snapshot() -> Array:
	var result := []
	for peer_id in peer_ids():
		var data: Dictionary = _peers.get(peer_id, {})
		var peer := data.get("peer") as WebSocketPeer
		result.append({
			"peerId": int(peer_id),
			"participantId": String(data.get("participant_id", "")),
			"seatIndex": int(data.get("seat_index", -1)),
			"displayName": String(data.get("display_name", "")),
			"opened": bool(data.get("opened", false)),
			"state": int(peer.get_ready_state()) if peer != null else -1,
			"deviceId": String(data.get("device_id", "")),
			"publicKeySet": String(data.get("public_key", "")).strip_edges() != "",
		})
	return result


func set_peer_participant(peer_id: int, participant_id: String, seat_index: int, display_name: String = "") -> void:
	if not _peers.has(peer_id):
		return
	_close_duplicate_participant(peer_id, participant_id)
	var data: Dictionary = _peers[peer_id]
	data["participant_id"] = participant_id
	data["seat_index"] = seat_index
	if display_name.strip_edges() != "":
		data["display_name"] = display_name.strip_edges()
	_peers[peer_id] = data


func set_peer_seat(peer_id: int, seat_index: int) -> void:
	if not _peers.has(peer_id):
		return
	var data: Dictionary = _peers[peer_id]
	data["seat_index"] = seat_index
	_peers[peer_id] = data


func send_to_peer(peer_id: int, type: String, payload: Dictionary = {}, message_id: String = "") -> bool:
	if not _peers.has(peer_id):
		return false
	var data: Dictionary = _peers[peer_id]
	var peer := data.get("peer") as WebSocketPeer
	if peer == null or peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	var id := message_id.strip_edges()
	if id == "":
		id = _next_message_id(type)
	var text := _codec.encode_server_message(type, id, payload)
	return peer.send_text(text) == OK


func broadcast(type: String, payload: Dictionary = {}, message_id: String = "") -> void:
	for peer_id in _peers.keys():
		send_to_peer(int(peer_id), type, payload, message_id)


func send_client(type: String, payload: Dictionary = {}, message_id: String = "") -> bool:
	if _client_peer == null or _client_peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	var id := message_id.strip_edges()
	if id == "":
		id = _next_message_id(type)
	var text := _codec.encode_client_message(type, id, payload)
	return _client_peer.send_text(text) == OK


func request_player_ready(ready: bool, seat_index: int = -1) -> bool:
	return send_client("player_ready" if ready else "player_unready", {
		"seatIndex": seat_index,
		"seatNumber": seat_index + 1,
		"ready": ready,
	})


func request_switch_seat(seat_index: int) -> bool:
	return send_client("switch_seat", {
		"seatIndex": seat_index,
		"seatNumber": seat_index + 1,
	})


func request_switch_to_observer() -> bool:
	return send_client("switch_to_observer", {})


func request_leave_room() -> bool:
	return send_client("leave_room", {})


func request_update_participant(seat_index: int, display_name: String) -> bool:
	return send_client("update_participant", {
		"seatIndex": seat_index,
		"seatNumber": seat_index + 1,
		"displayName": display_name.strip_edges(),
	})


func request_add_bot(seat_index: int, display_name: String) -> bool:
	if OS.is_debug_build():
		print("[RoomNetworkSession][debug] request_add_controlled_player legacy_alias seat=%d name=%s" % [
			seat_index,
			display_name.strip_edges(),
		])
	return request_add_controlled_player(seat_index, display_name)


func request_add_controlled_player(seat_index: int, display_name: String) -> bool:
	return send_client("add_controlled_player", {
		"seatIndex": seat_index,
		"seatNumber": seat_index + 1,
		"displayName": display_name.strip_edges(),
	})


func request_remove_bot(seat_index: int) -> bool:
	return request_remove_controlled_player(seat_index)


func request_remove_controlled_player(seat_index: int) -> bool:
	return send_client("remove_controlled_player", {
		"seatIndex": seat_index,
		"seatNumber": seat_index + 1,
	})


func request_game_action(target_index: int) -> bool:
	return send_client("game_action", {
		"targetIndex": target_index,
		"targetSeatNumber": target_index + 1,
	})


func request_chat_message(text: String) -> bool:
	return send_client("chat_message", {
		"text": text,
	})


func _process(_delta: float) -> void:
	if _role == ROLE_HOST:
		_poll_host()
	elif _role == ROLE_CLIENT:
		_poll_client()


func _poll_host() -> void:
	if _server == null:
		return
	while _server.is_connection_available():
		var stream := _server.take_connection()
		if stream == null:
			break
		var peer := WebSocketPeer.new()
		peer.set_inbound_buffer_size(1024 * 1024)
		peer.set_outbound_buffer_size(1024 * 1024)
		var err := peer.accept_stream(stream)
		if err != OK:
			peer.close()
			continue
		var peer_id := _next_peer_id
		_next_peer_id += 1
		_peers[peer_id] = {
			"peer": peer,
			"opened": false,
			"participant_id": "",
			"seat_index": -1,
			"display_name": "",
			"server_challenge": "",
			"device_id": "",
			"public_key": "",
		}
	var disconnected := []
	for peer_id in _peers.keys():
		var data: Dictionary = _peers[peer_id]
		var peer := data.get("peer") as WebSocketPeer
		if peer == null:
			disconnected.append(peer_id)
			continue
		peer.poll()
		var state := peer.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			if not bool(data.get("opened", false)):
				data["opened"] = true
				_peers[peer_id] = data
			_read_host_packets(int(peer_id), peer)
		elif state == WebSocketPeer.STATE_CLOSED:
			disconnected.append(peer_id)
	for peer_id in disconnected:
		peer_disconnected.emit(int(peer_id))
		_peers.erase(peer_id)


func _poll_client() -> void:
	if _client_peer == null:
		return
	if not _client_join_completed and _client_started_at_ms > 0 and Time.get_ticks_msec() - _client_started_at_ms > CLIENT_JOIN_TIMEOUT_MS:
		_reject_client_join("连接超时，请确认双方在同一局域网且房主网络可达")
		return
	_client_peer.poll()
	var state := _client_peer.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _client_opened:
			_client_opened = true
			status_changed.emit("房间连接成功")
		if not _client_hello_sent:
			_client_hello_sent = true
			send_client("hello", {
				"client": "godot",
				"device": _public_identity(),
				"clientChallenge": _client_challenge,
			})
		_read_client_packets()
	elif state == WebSocketPeer.STATE_CLOSED:
		if not _client_join_completed:
			var message := "网络连接失败，请确认双方在同一局域网且房主在线"
			if _client_opened:
				message = "房间连接已断开"
			_reject_client_join(message)
		else:
			_client_opened = false
			status_changed.emit("房间连接已断开")


func _read_host_packets(peer_id: int, peer: WebSocketPeer) -> void:
	while peer.get_available_packet_count() > 0:
		var data := peer.get_packet()
		var decoded: Dictionary = _codec.decode_client_message(data)
		if not bool(decoded.get("ok", false)):
			send_to_peer(peer_id, "action_rejected", {"message": String(decoded.get("error", "消息解析失败"))})
			continue
		var type := String(decoded.get("type", ""))
		var message_id := String(decoded.get("messageId", ""))
		var payload: Dictionary = decoded.get("payload", {})
		if type == "hello":
			_handle_client_hello(peer_id, message_id, payload)
		elif ["qr_secret_request", "join_room", "join_room_as_observer", "reconnect_room"].has(type) and not _authenticate_peer_payload(peer_id, message_id, payload):
			continue
		elif type == "ping":
			send_to_peer(peer_id, "pong", {"at": Time.get_unix_time_from_system()}, message_id)
		else:
			client_message_received.emit(peer_id, type, message_id, payload)


func _read_client_packets() -> void:
	while _client_peer.get_available_packet_count() > 0:
		var data := _client_peer.get_packet()
		var decoded: Dictionary = _codec.decode_server_message(data)
		if not bool(decoded.get("ok", false)):
			status_changed.emit(String(decoded.get("error", "服务器消息解析失败")))
			continue
		var type := String(decoded.get("type", ""))
		var message_id := String(decoded.get("messageId", ""))
		var payload: Dictionary = decoded.get("payload", {})
		if type == "join_accepted":
			_client_join_completed = true
			_local_participant_id = String(payload.get("participantId", _local_participant_id))
			join_accepted.emit(payload)
		elif type == "join_rejected":
			_client_join_completed = true
			join_rejected.emit(String(payload.get("message", "加入房间失败")))
		elif type == "qr_secret_response":
			_handle_qr_secret_response(payload)
		elif type == "room_snapshot":
			snapshot_received.emit(payload)
		elif type == "hello_ack":
			if _validate_host_identity(payload):
				_send_pending_join_request()
		server_message_received.emit(type, message_id, payload)


func _next_message_id(prefix: String) -> String:
	var id := "%s_%d_%d" % [prefix, Time.get_ticks_msec(), _message_serial]
	_message_serial += 1
	return id


func _public_identity() -> Dictionary:
	var device_id := String(_device_identity.get("deviceId", "")).strip_edges()
	var public_key := String(_device_identity.get("publicKey", "")).strip_edges()
	if device_id == "":
		device_id = "device_%s" % _nonce(12)
		_device_identity["deviceId"] = device_id
	if public_key == "":
		public_key = _nonce(24)
		_device_identity["publicKey"] = public_key
	return {
		"deviceId": device_id,
		"publicKey": public_key,
	}


func _auth_payload() -> Dictionary:
	return _auth_payload_for_challenge(_client_server_challenge)


func _auth_payload_for_challenge(challenge: String) -> Dictionary:
	var public := _public_identity()
	var identity := _device_identity.duplicate(true)
	identity["deviceId"] = String(public.get("deviceId", ""))
	identity["publicKey"] = String(public.get("publicKey", ""))
	return DeviceIdentityScript.auth_payload_from_identity(identity, challenge)


func _validate_host_identity(payload: Dictionary) -> bool:
	if _client_host_identity_checked:
		return _client_server_challenge != ""
	var host_value = payload.get("host", {})
	if not (host_value is Dictionary):
		_reject_client_identity("Host identity missing")
		return false
	var host: Dictionary = host_value
	var host_device_id := String(host.get("deviceId", "")).strip_edges()
	var host_public_key := String(host.get("publicKey", "")).strip_edges()
	if _client_expected_host_device_id != "" and host_device_id != _client_expected_host_device_id:
		_reject_client_identity("Host device identity mismatch")
		return false
	if _client_expected_host_public_key != "" and host_public_key != _client_expected_host_public_key:
		_reject_client_identity("Host public key mismatch")
		return false
	var host_auth_value = payload.get("hostAuth", {})
	if not (host_auth_value is Dictionary):
		_reject_client_identity("Host auth signature missing")
		return false
	var host_auth: Dictionary = host_auth_value
	if String(host_auth.get("deviceId", "")).strip_edges() != host_device_id or String(host_auth.get("publicKey", "")).strip_edges() != host_public_key:
		_reject_client_identity("Host auth identity mismatch")
		return false
	if not DeviceIdentityScript.verify_auth_payload(host_auth, _client_challenge):
		_reject_client_identity("Host auth signature invalid")
		return false
	var server_challenge := String(payload.get("serverChallenge", "")).strip_edges()
	if server_challenge == "":
		_reject_client_identity("Server auth challenge missing")
		return false
	_client_server_challenge = server_challenge
	_client_host_identity_checked = true
	_client_observed_host_device_id = host_device_id
	_client_observed_host_public_key = host_public_key
	return true


func _send_pending_join_request() -> void:
	if _client_join_sent:
		return
	if _client_server_challenge == "":
		return
	if not _client_secure_qr_payload.is_empty() and not _client_qr_secret_resolved:
		if _client_qr_secret_requested:
			return
		_client_qr_secret_requested = true
		var public_key := ""
		if _client_qr_private_key != null:
			public_key = _client_qr_private_key.save_to_string(true)
		if public_key.strip_edges() == "":
			_reject_client_join("二维码密钥协商初始化失败")
			return
		status_changed.emit("正在协商二维码密钥")
		send_client("qr_secret_request", {
			"secretId": String(_client_secure_qr_payload.get("secretId", "")),
			"publicKey": public_key,
			"auth": _auth_payload(),
		})
		return
	_client_join_sent = true
	if _client_reconnect_participant_id != "" and _client_reconnect_token != "":
		send_client("reconnect_room", {
			"roomId": _client_room_id,
			"participantId": _client_reconnect_participant_id,
			"reconnectToken": _client_reconnect_token,
			"auth": _auth_payload(),
		})
	else:
		send_client("join_room_as_observer" if _client_as_observer else "join_room", {
			"roomId": _client_room_id,
			"displayName": _client_display_name,
			"joinToken": _client_join_token,
			"auth": _auth_payload(),
		})


func _handle_qr_secret_response(payload: Dictionary) -> void:
	if _client_secure_qr_payload.is_empty() or _client_qr_secret_resolved:
		return
	if not bool(payload.get("ok", false)):
		_reject_client_join(String(payload.get("message", "二维码密钥协商失败")))
		return
	if _client_qr_private_key == null:
		_reject_client_join("二维码密钥协商状态丢失")
		return
	var wrapped_key := _base64_url_decode(String(payload.get("wrappedKey", "")))
	if wrapped_key.is_empty():
		_reject_client_join("二维码密钥协商结果为空")
		return
	var key := Crypto.new().decrypt(_client_qr_private_key, wrapped_key)
	if key.size() != 32:
		_reject_client_join("二维码解密失败：密钥协商结果无效")
		return
	var decrypted: Dictionary = _qr_join_payload.decrypt_secure_payload(_client_secure_qr_payload, key)
	if not bool(decrypted.get("ok", false)):
		_reject_client_join(String(decrypted.get("error", "二维码解密失败")))
		return
	if String(decrypted.get("host", "")).strip_edges() != _client_host or int(decrypted.get("port", 0)) != _port:
		_reject_client_join("二维码地址与加密内容不一致")
		return
	var protocol_version := int(decrypted.get("networkProtocolVersion", 0))
	if protocol_version != 0 and protocol_version != int(_codec.PROTOCOL_VERSION):
		_reject_client_join("网络协议版本不一致，请确认双方应用版本一致")
		return
	var decrypted_host_device_id := String(decrypted.get("hostDeviceId", "")).strip_edges()
	var decrypted_host_public_key := String(decrypted.get("hostPublicKey", "")).strip_edges()
	if decrypted_host_device_id != "" and _client_observed_host_device_id != "" and decrypted_host_device_id != _client_observed_host_device_id:
		_reject_client_join("房主设备身份与二维码不一致")
		return
	if decrypted_host_public_key != "" and _client_observed_host_public_key != "" and decrypted_host_public_key != _client_observed_host_public_key:
		_reject_client_join("房主公钥与二维码不一致")
		return
	_client_room_id = String(decrypted.get("roomId", "")).strip_edges()
	if _client_room_id == "":
		_reject_client_join("二维码解密失败：缺少房间ID")
		return
	_client_join_token = String(decrypted.get("joinToken", ""))
	_client_as_observer = false
	_client_expected_host_device_id = decrypted_host_device_id
	_client_expected_host_public_key = decrypted_host_public_key
	_client_qr_secret_resolved = true
	status_changed.emit("二维码解密完成，正在加入房间")
	_send_pending_join_request()


func _handle_client_hello(peer_id: int, message_id: String, payload: Dictionary) -> void:
	if not _peers.has(peer_id):
		return
	var client_challenge := String(payload.get("clientChallenge", "")).strip_edges()
	if client_challenge == "":
		send_to_peer(peer_id, "action_rejected", {
			"code": "invalid_auth_challenge",
			"message": "缺少客户端认证挑战",
		}, message_id)
		return
	var server_challenge := _nonce(24)
	var data: Dictionary = _peers[peer_id]
	data["server_challenge"] = server_challenge
	var device_value = payload.get("device", {})
	if device_value is Dictionary:
		data["device_id"] = String((device_value as Dictionary).get("deviceId", "")).strip_edges()
		data["public_key"] = String((device_value as Dictionary).get("publicKey", "")).strip_edges()
	_peers[peer_id] = data
	send_to_peer(peer_id, "hello_ack", {
		"server": "godot",
		"host": _public_identity(),
		"hostAuth": _auth_payload_for_challenge(client_challenge),
		"serverChallenge": server_challenge,
	}, message_id)


func _authenticate_peer_payload(peer_id: int, message_id: String, payload: Dictionary) -> bool:
	if not _peers.has(peer_id):
		return false
	var data: Dictionary = _peers[peer_id]
	var challenge := String(data.get("server_challenge", "")).strip_edges()
	if challenge == "":
		send_to_peer(peer_id, "join_rejected", {
			"code": "auth_required",
			"message": "请先完成设备认证",
		}, message_id)
		return false
	var auth_value = payload.get("auth", {})
	if not (auth_value is Dictionary):
		send_to_peer(peer_id, "join_rejected", {
			"code": "auth_required",
			"message": "缺少设备认证签名",
		}, message_id)
		return false
	var auth: Dictionary = auth_value
	if not DeviceIdentityScript.verify_auth_payload(auth, challenge):
		send_to_peer(peer_id, "join_rejected", {
			"code": "invalid_auth_signature",
			"message": "设备认证签名无效",
		}, message_id)
		return false
	data["device_id"] = String(auth.get("deviceId", "")).strip_edges()
	data["public_key"] = String(auth.get("publicKey", "")).strip_edges()
	_peers[peer_id] = data
	return true

func _reject_client_identity(message: String) -> void:
	_reject_client_join(message)


func _reject_client_join(message: String) -> void:
	if _client_join_completed:
		return
	_client_join_completed = true
	status_changed.emit(message)
	join_rejected.emit(message)
	if _client_peer != null:
		_client_peer.close()


func _close_duplicate_participant(current_peer_id: int, participant_id: String) -> void:
	var clean := participant_id.strip_edges()
	if clean == "":
		return
	var duplicates := []
	for peer_id in _peers.keys():
		if int(peer_id) == current_peer_id:
			continue
		var data: Dictionary = _peers[peer_id]
		if String(data.get("participant_id", "")) == clean:
			duplicates.append(int(peer_id))
	for peer_id in duplicates:
		var data: Dictionary = _peers.get(peer_id, {})
		var peer := data.get("peer") as WebSocketPeer
		if peer != null:
			peer.close()
		_peers.erase(peer_id)


func _nonce(byte_length: int) -> String:
	var crypto := Crypto.new()
	return Marshalls.raw_to_base64(crypto.generate_random_bytes(byte_length)).replace("+", "-").replace("/", "_").replace("=", "")


func _base64_url_decode(value: String) -> PackedByteArray:
	var text := value.strip_edges().replace("-", "+").replace("_", "/")
	while text.length() % 4 != 0:
		text += "="
	return Marshalls.base64_to_raw(text)
