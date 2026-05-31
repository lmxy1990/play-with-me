extends "res://scripts/pages/base/page_room_replica_ui_base.gd"

const RoomNetworkCodecScript := preload("res://scripts/network/room_network_codec.gd")


func _network_debug(message: String) -> void:
	if OS.is_debug_build():
		print("[RoomNetwork][debug] %s" % message)


func _build_join_payload(_as_observer: bool = false) -> String:
	var room := _active_room()
	if room.is_empty():
		return ""
	var password := String(room.get("password", "")).strip_edges()
	var secret := _ensure_join_qr_secret(room, false)
	return _qr_join_payload.build_secure_encoded(
		_local_host_address(),
		_room_network_port,
		String(room.get("id", "")),
		String(room.get("name", "狼人杀房间")),
		_game_id_for_room(room),
		false,
		password,
		String(_device_identity.device_id),
		String(_device_identity.public_key),
		String(room.get("map_id", room.get("mapId", ""))),
		String(room.get("map_name", room.get("mapName", ""))),
		_room_background_path(room),
		String(secret.get("id", "")),
		String(secret.get("key", "")),
		RoomNetworkCodecScript.PROTOCOL_VERSION
	)


func _ensure_join_qr_secret(room: Dictionary, as_observer: bool) -> Dictionary:
	var secrets_value = room.get("qr_secrets", {})
	var secrets: Dictionary = (secrets_value as Dictionary) if secrets_value is Dictionary else {}
	var scope := "observer" if as_observer else "player"
	var secret_value = secrets.get(scope, {})
	var secret: Dictionary = (secret_value as Dictionary) if secret_value is Dictionary else {}
	if String(secret.get("id", "")).strip_edges() == "" or String(secret.get("key", "")).strip_edges() == "":
		secret = {
			"id": _qr_join_payload.generate_secret_id(),
			"key": _qr_join_payload.generate_secret_key(),
		}
		secrets[scope] = secret
		room["qr_secrets"] = secrets
		_call_if_present("_commit_state")
	return secret


func _qr_secret_key_for_id(secret_id: String) -> String:
	var clean := secret_id.strip_edges()
	if clean == "":
		return ""
	var room := _active_room()
	var secrets_value = room.get("qr_secrets", {})
	if not (secrets_value is Dictionary):
		return ""
	for value in (secrets_value as Dictionary).values():
		if not (value is Dictionary):
			continue
		var secret: Dictionary = value
		if String(secret.get("id", "")).strip_edges() == clean:
			return String(secret.get("key", "")).strip_edges()
	return ""


func _join_discovered_room(room: Dictionary) -> void:
	var payload := String(room.get("join_payload", ""))
	if payload != "":
		_join_room_from_payload(payload)
		return
	if String(room.get("host", "")) != "" and int(room.get("port", 0)) > 0:
		var built := _qr_join_payload.build_encoded(
			String(room.get("host", "")),
			int(room.get("port", 0)),
			String(room.get("id", "")),
			String(room.get("name", "狼人杀房间")),
			_game_id_for_room(room),
			false,
			String(room.get("password", "")),
			String(room.get("host_device_id", room.get("hostDeviceId", ""))),
			String(room.get("host_public_key", room.get("hostPublicKey", ""))),
			String(room.get("map_id", room.get("mapId", ""))),
			String(room.get("map_name", room.get("mapName", ""))),
			_room_background_path(room)
		)
		_join_room_from_payload(built)


func _join_room_from_payload(payload: String, interactive: bool = false) -> bool:
	var parsed := _qr_join_payload.parse(payload)
	if not bool(parsed.get("ok", false)):
		_set_system_message(String(parsed.get("error", "加入码无效")))
		_scan_debug("join parse failed code=%s error=%s" % [String(parsed.get("code", "")), _state_string("_system_message")])
		_call_if_present("_refresh_center_panel")
		_call_if_present("_flash_effect", ["skip"])
		return false
	_scan_debug("join parse ok secure=%s address=%s interactive=%s" % [
		str(bool(parsed.get("secure", false))),
		_scan_payload_address(parsed),
		str(interactive),
	])
	if bool(parsed.get("secure", false)):
		return _join_secure_room_from_payload(parsed, payload, interactive)
	var room_id := String(parsed.get("roomId", ""))
	var max_players := 6
	var known_room := {}
	for room in _state_array("_rooms"):
		if room is Dictionary and String(room.get("id", "")) == room_id:
			known_room = room as Dictionary
			max_players = int(room.get("max_players", room.get("maxPlayers", 6)))
			break
	var known_map_id := String(known_room.get("map_id", known_room.get("mapId", ""))).strip_edges()
	var parsed_map_id := String(parsed.get("mapId", "")).strip_edges()
	var game_id := String(parsed.get("gameId", "werewolf")).strip_edges()
	var joined_map_id := known_map_id if known_map_id != "" else parsed_map_id
	if joined_map_id == "":
		joined_map_id = "xiangqi_standard" if game_id == "xiangqi" else "basic_village"
	var known_map_name := String(known_room.get("map_name", known_room.get("mapName", ""))).strip_edges()
	var parsed_map_name := String(parsed.get("mapName", "")).strip_edges()
	var joined_map_name := known_map_name if known_map_name != "" else parsed_map_name
	if joined_map_name == "":
		joined_map_name = "标准象棋" if game_id == "xiangqi" else "标准村庄"
	var bg_source: Dictionary = known_room.duplicate(true) if not known_room.is_empty() else {}
	bg_source["map_id"] = joined_map_id
	if String(parsed.get("bg", "")).strip_edges() != "":
		bg_source["bg"] = String(parsed.get("bg", "")).strip_edges()
	var joined_room := {
		"id": room_id,
		"name": String(parsed.get("roomName", "狼人杀房间")),
		"state": "等待同步",
		"type": _type_for_game_id(game_id),
		"game_room_id": game_id,
		"gameId": game_id,
		"players": "0/%d" % max_players,
		"lock": "密码" if String(parsed.get("joinToken", "")).strip_edges() != "" else "公开",
		"address": "%s:%d" % [String(parsed.get("host", "")), int(parsed.get("port", 0))],
		"bg": _room_background_path(bg_source),
		"max_players": max_players,
		"map_id": joined_map_id,
		"map_name": joined_map_name,
		"host": String(parsed.get("host", "")),
		"port": int(parsed.get("port", 0)),
		"join_token": String(parsed.get("joinToken", "")),
		"host_device_id": String(parsed.get("hostDeviceId", "")),
		"host_public_key": String(parsed.get("hostPublicKey", "")),
		"join_payload": payload.strip_edges(),
		"connection_mode": "client",
		"discovered": true,
	}
	_call_if_present("_upsert_room", [joined_room])
	if _app_state != null:
		_app_state.active_room_id = room_id
	var players := _state_array("_players")
	players.clear()
	for i in range(max_players):
		var empty_value = _call_if_present("_empty_seat_data", [i])
		players.append(empty_value if empty_value is Dictionary else {})
	set("_players", players)
	set("_local_player_index", -1)
	var default_werewolf = _call_if_present("_default_werewolf_state")
	set("_werewolf", default_werewolf if default_werewolf is Dictionary else {})
	var history := _state_array("_history")
	history.clear()
	set("_history", history)
	set("_network_history_initialized", false)
	_call_if_present("_reset_wolf_private_flow")
	_set_system_message("已读取加入码，等待房间同步")
	_ensure_room_network_session()
	if _room_network_session != null:
		_room_network_port = int(parsed.get("port", _room_network_port))
		var identity := _preference_identity_snapshot()
		var display_name := String(identity.get("displayName", identity.get("nickname", _state_string("_local_nickname")))).strip_edges()
		var connect_result: Dictionary = _room_network_session.call(
			"connect_to_room",
			String(parsed.get("host", "")),
			int(parsed.get("port", 0)),
			room_id,
			String(parsed.get("joinToken", "")),
			display_name,
			false,
			String(parsed.get("hostDeviceId", "")),
			String(parsed.get("hostPublicKey", "")),
			"",
			"",
			identity
		)
		_scan_debug("network connect result ok=%s error=%s" % [str(bool(connect_result.get("ok", false))), String(connect_result.get("error", ""))])
		if not bool(connect_result.get("ok", false)):
			_set_system_message(String(connect_result.get("error", "连接房间失败")))
			_call_if_present("_flash_effect", ["skip"])
			return false
	_call_if_present("_commit_state")
	if interactive:
		_set_scan_join_waiting("正在加入")
	else:
		_call_if_present("_clear_modal")
		_call_if_present("_enter_table")
	return true


func _join_secure_room_from_payload(parsed: Dictionary, payload: String, interactive: bool = false) -> bool:
	var host := String(parsed.get("host", "")).strip_edges()
	var port := int(parsed.get("port", 0))
	_scan_debug("secure join start address=%s:%d interactive=%s" % [host, port, str(interactive)])
	if host == "" or port <= 0:
		_set_system_message("加密加入码地址无效")
		_call_if_present("_refresh_center_panel")
		_call_if_present("_flash_effect", ["skip"])
		return false
	_ensure_room_network_session()
	if _room_network_session == null:
		_set_system_message("房间网络未初始化")
		_call_if_present("_refresh_center_panel")
		_call_if_present("_flash_effect", ["skip"])
		return false
	_room_network_port = port
	_set_system_message("已读取加密加入码，正在连接房主")
	if interactive:
		_set_scan_join_waiting("正在加入")
	var identity := _preference_identity_snapshot()
	var display_name := String(identity.get("displayName", identity.get("nickname", _state_string("_local_nickname")))).strip_edges()
	var result: Dictionary = _room_network_session.call(
		"connect_to_secure_qr",
		host,
		port,
		parsed,
		display_name,
		identity
	)
	_scan_debug("secure connect result ok=%s error=%s" % [str(bool(result.get("ok", false))), String(result.get("error", ""))])
	if not bool(result.get("ok", false)):
		_set_system_message(String(result.get("error", "连接房间失败")))
		_call_if_present("_refresh_center_panel")
		_call_if_present("_flash_effect", ["skip"])
		return false
	_call_if_present("_commit_state")
	return true


func _reconnect_last_room() -> bool:
	_ensure_device_identity_loaded()
	var session: Dictionary = _room_session_store.load()
	if not _room_session_store.is_valid(session):
		_set_system_message("没有可用的重连信息")
		return false
	_ensure_room_network_session()
	if _room_network_session == null:
		_set_system_message("房间网络未初始化")
		return false
	var room_id := String(session.get("roomId", "")).strip_edges()
	if room_id == "":
		room_id = "reconnect_room"
	_room_replica_store.latest_for_room(room_id)
	var host := String(session.get("host", "")).strip_edges()
	var port := int(session.get("port", 0))
	var joined_room := {
		"id": room_id,
		"name": "重连房间",
		"state": "重连中",
		"type": "狼人杀",
		"players": "0/6",
		"lock": "公开",
		"address": "%s:%d" % [host, port],
		"bg": _lobby_background_path(),
		"max_players": max(6, _state_array("_players").size()),
		"host": host,
		"port": port,
		"host_device_id": String(session.get("expectedHostDeviceId", "")),
		"host_public_key": String(session.get("expectedHostPublicKey", "")),
		"connection_mode": "client",
		"discovered": true,
	}
	_call_if_present("_upsert_room", [joined_room])
	if _app_state != null:
		_app_state.active_room_id = room_id
	var result: Dictionary = _room_network_session.call(
		"connect_to_room",
		host,
		port,
		room_id,
		"",
		_state_string("_local_nickname"),
		bool(session.get("isObserver", false)),
		String(session.get("expectedHostDeviceId", "")),
		String(session.get("expectedHostPublicKey", "")),
		String(session.get("participantId", "")),
		String(session.get("reconnectToken", ""))
	)
	_network_debug("client reconnect_last_room host=%s port=%d room=%s participant=%s observer=%s ok=%s error=%s" % [
		host,
		port,
		room_id,
		String(session.get("participantId", "")),
		str(bool(session.get("isObserver", false))),
		str(bool(result.get("ok", false))),
		String(result.get("error", "")),
	])
	if not bool(result.get("ok", false)):
		_set_system_message(String(result.get("error", "重连失败")))
		_call_if_present("_flash_effect", ["skip"])
		return false
	_set_system_message("正在重连房间")
	_call_if_present("_commit_state")
	_call_if_present("_enter_table")
	return true


func _broadcast_network_snapshot() -> void:
	if not _is_network_host() or int(get("_mode")) != Mode.TABLE:
		return
	var peer_ids: Array = _room_network_session.call("peer_ids")
	if peer_ids.is_empty():
		return
	var replica_payload := _signed_room_replica_payload()
	for peer_id_value in peer_ids:
		var peer_id := int(peer_id_value)
		var participant_id := String(_room_network_session.call("peer_participant_id", peer_id))
		var snapshot := _network_snapshot_for_participant(participant_id)
		_room_network_session.call("send_to_peer", peer_id, "room_snapshot", snapshot)
		if not replica_payload.is_empty():
			_room_network_session.call("send_to_peer", peer_id, "room_replica_frame", replica_payload)


func _on_network_join_accepted(payload: Dictionary) -> void:
	_sync_scan_join_ui_state()
	_scan_debug("network join accepted scan_active=%s keys=%s" % [str(_scan_join_active), JSON.stringify(payload.keys())])
	_network_debug("client join accepted participant=%s reconnected=%s seat=%s observer=%s" % [
		String(payload.get("participantId", "")),
		str(bool(payload.get("reconnected", false))),
		str((payload.get("participant", {}) as Dictionary).get("seatNumber", "")) if payload.get("participant", {}) is Dictionary else "",
		str((payload.get("participant", {}) as Dictionary).get("observer", "")) if payload.get("participant", {}) is Dictionary else "",
	])
	var snapshot_value = payload.get("room", {})
	if snapshot_value is Dictionary:
		_apply_network_snapshot(snapshot_value as Dictionary)
	_save_reconnect_session(payload)
	var replica_value = payload.get("roomReplicaFrame", {})
	if replica_value is Dictionary:
		_accept_network_room_replica(replica_value as Dictionary)
	_set_system_message("已加入房间")
	if _scan_join_active:
		_clear_scan_overlay_refs()
		_call_if_present("_clear_modal")
		_call_if_present("_enter_table")
	_call_if_present("_refresh_center_panel")
	_call_if_present("_flash_effect", ["action"])


func _on_network_join_rejected(message: String) -> void:
	_sync_scan_join_ui_state()
	_set_system_message("加入失败：%s" % message)
	_scan_debug("network join rejected scan_active=%s message=%s" % [str(_scan_join_active), _state_string("_system_message")])
	_network_debug("client join rejected message=%s" % message)
	if _scan_join_active:
		_stop_scan_join_waiting()
		_set_scan_status(_state_string("_system_message"), RED)
	_call_if_present("_refresh_center_panel")
	_call_if_present("_flash_effect", ["skip"])


func _on_network_snapshot_received(snapshot: Dictionary) -> void:
	_apply_network_snapshot(snapshot)


func _save_reconnect_session(payload: Dictionary) -> void:
	var reconnect_token := String(payload.get("reconnectToken", "")).strip_edges()
	var participant_id := String(payload.get("participantId", "")).strip_edges()
	if reconnect_token == "" or participant_id == "":
		return
	var room := _active_room()
	var host := String(room.get("host", "")).strip_edges()
	var port := int(room.get("port", _room_network_port))
	if host == "":
		var address := String(room.get("address", ""))
		var colon := address.rfind(":")
		if colon > 0:
			host = address.substr(0, colon)
			port = int(address.substr(colon + 1).to_int())
	if host == "" or port <= 0:
		return
	_room_session_store.save({
		"host": host,
		"port": port,
		"participantId": participant_id,
		"reconnectToken": reconnect_token,
		"isObserver": bool((payload.get("participant", {}) as Dictionary).get("observer", false)) if payload.get("participant", {}) is Dictionary else false,
		"roomId": String(room.get("id", "")),
		"expectedHostDeviceId": String(room.get("host_device_id", "")),
		"expectedHostPublicKey": String(room.get("host_public_key", "")),
		"controlledPlayers": _private_controlled_players_for_session(),
		"savedAtMs": Time.get_ticks_msec(),
	})


func _on_network_server_message_received(type: String, _message_id: String, payload: Dictionary) -> void:
	if OS.is_debug_build() and ["action_rejected", "device_task", "room_closed", "room_replica_frame"].has(type):
		_network_debug("client server_message type=%s payload_keys=%s" % [type, str(payload.keys())])
	if type == "action_rejected":
		_set_system_message(String(payload.get("message", "操作被房主拒绝")))
		_call_if_present("_refresh_center_panel")
		_call_if_present("_flash_effect", ["skip"])
	elif type == "device_task":
		_call_if_present("_on_device_task_received", [payload])
	elif type == "room_closed":
		_handle_server_room_closed(payload)
	elif type == "room_replica_frame":
		_accept_network_room_replica(payload)


func _handle_server_room_closed(payload: Dictionary) -> void:
	var room_id := String(payload.get("roomId", "")).strip_edges()
	var active_id := String(_app_state.active_room_id) if _app_state != null else String(_active_room().get("id", ""))
	if room_id != "" and active_id != "" and room_id != active_id:
		return
	if _room_network_session != null:
		_room_network_session.stop()
	if active_id != "":
		for i in range(_rooms.size() - 1, -1, -1):
			if _rooms[i] is Dictionary and String((_rooms[i] as Dictionary).get("id", "")) == active_id:
				_rooms.remove_at(i)
	_call_if_present("_clear_room_transient_data", [active_id])
	_set_system_message("房间已关闭")
	_call_if_present("_commit_state")
	if int(get("_mode")) == Mode.TABLE:
		_call_if_present("_show_lobby")


func _on_network_status_changed(message: String) -> void:
	if message.strip_edges() == "":
		return
	_network_debug("status_changed role_client=%s mode=%s message=%s" % [
		str(_is_network_client()),
		str(int(get("_mode"))),
		message,
	])
	_sync_scan_join_ui_state()
	if _scan_join_active and _scan_join_waiting_network:
		_set_scan_join_waiting(message)
	if _is_network_client() or int(get("_mode")) == Mode.TABLE:
		_set_system_message(message)
		_call_if_present("_refresh_center_panel")
	if message == "房间连接已断开":
		_on_host_connection_lost()


func _on_network_peer_disconnected(peer_id: int) -> void:
	if not _is_network_host():
		return
	var participant_id := ""
	if _room_network_session != null and _room_network_session.has_method("peer_participant_id"):
		participant_id = String(_room_network_session.call("peer_participant_id", peer_id)).strip_edges()
	var seat_index := -1
	if _room_network_session != null and _room_network_session.has_method("peer_seat_index"):
		seat_index = int(_room_network_session.call("peer_seat_index", peer_id))
	_network_debug("host peer_disconnected peer=%d participant=%s seat=%d" % [peer_id, participant_id, seat_index])
	_call_if_present("_host_mark_peer_left", [peer_id])
	if participant_id != "":
		_call_if_present("_host_drop_presentation_ack_participant", [participant_id])
		_call_if_present("_host_drop_device_task_participant", [participant_id])


func _on_network_client_message_received(peer_id: int, type: String, message_id: String, payload: Dictionary) -> void:
	if not _is_network_host():
		return
	if OS.is_debug_build() and ["join_room", "join_room_as_observer", "reconnect_room", "switch_seat", "switch_to_observer", "player_ready", "player_unready", "add_controlled_player", "remove_controlled_player", "leave_room"].has(type):
		_network_debug("host client_message peer=%d type=%s message=%s payload_keys=%s seat=%d participant=%s" % [
			peer_id,
			type,
			message_id,
			str(payload.keys()),
			int(_room_network_session.call("peer_seat_index", peer_id)) if _room_network_session != null else -1,
			String(_room_network_session.call("peer_participant_id", peer_id)) if _room_network_session != null else "",
		])
	if type == "presentation_ack":
		_call_if_present("_host_apply_presentation_ack", [peer_id, payload])
		return
	if type == "device_task_result":
		_call_if_present("_host_apply_device_task_result", [peer_id, payload])
		return
	if _observer_message_is_read_only(peer_id, type):
		_send_observer_read_only(peer_id)
		return
	match type:
		"hello":
			pass
		"qr_secret_request":
			_host_resolve_qr_secret(peer_id, message_id, payload)
		"join_room", "join_room_as_observer":
			_host_accept_network_join(peer_id, message_id, payload, false, false)
		"reconnect_room":
			_host_accept_network_join(peer_id, message_id, payload, bool(payload.get("isObserver", false)), true)
		"player_ready":
			_call_if_present("_host_set_peer_ready", [peer_id, true])
		"player_unready":
			_call_if_present("_host_set_peer_ready", [peer_id, false])
		"switch_seat":
			_call_if_present("_host_switch_peer_seat", [peer_id, _payload_seat_index(payload)])
		"switch_to_observer":
			_call_if_present("_host_switch_peer_to_observer", [peer_id])
		"add_controlled_player", "add_bot":
			_call_if_present("_host_add_peer_bot", [peer_id, payload])
		"remove_controlled_player", "remove_bot":
			_call_if_present("_host_remove_peer_bot", [peer_id, payload])
		"update_participant":
			_call_if_present("_host_update_peer_participant", [peer_id, payload])
		"game_action":
			_call_if_present("_host_apply_peer_action", [peer_id, payload])
		"chat_message":
			_call_if_present("_host_apply_peer_speech", [peer_id, payload])
		"leave_room":
			_call_if_present("_host_mark_peer_left", [peer_id, true])
		_:
			_send_network_rejection(peer_id, "暂未支持的消息：%s" % type)


func _host_resolve_qr_secret(peer_id: int, message_id: String, payload: Dictionary) -> void:
	var secret_id := String(payload.get("secretId", "")).strip_edges()
	var secret_key := _qr_secret_key_for_id(secret_id)
	if secret_key == "":
		_room_network_session.call("send_to_peer", peer_id, "qr_secret_response", {
			"ok": false,
			"code": "unknown_qr_secret",
			"message": "二维码已失效，请重新打开房间二维码",
		}, message_id)
		return
	var public_key_text := String(payload.get("publicKey", "")).strip_edges()
	var public_key := CryptoKey.new()
	if public_key_text == "" or public_key.load_from_string(public_key_text, true) != OK:
		_room_network_session.call("send_to_peer", peer_id, "qr_secret_response", {
			"ok": false,
			"code": "invalid_qr_exchange_key",
			"message": "二维码密钥协商失败：客户端公钥无效",
		}, message_id)
		return
	var key_bytes := _qr_secret_key_bytes(secret_key)
	if key_bytes.size() != 32:
		_room_network_session.call("send_to_peer", peer_id, "qr_secret_response", {
			"ok": false,
			"code": "invalid_qr_secret",
			"message": "二维码密钥已损坏，请重新打开房间二维码",
		}, message_id)
		return
	var wrapped := Crypto.new().encrypt(public_key, key_bytes)
	if wrapped.is_empty():
		_room_network_session.call("send_to_peer", peer_id, "qr_secret_response", {
			"ok": false,
			"code": "qr_exchange_failed",
			"message": "二维码密钥协商失败",
		}, message_id)
		return
	_room_network_session.call("send_to_peer", peer_id, "qr_secret_response", {
		"ok": true,
		"secretId": secret_id,
		"wrappedKey": _network_base64_url(wrapped),
		"wrapAlg": "RSA-2048-WRAP",
	}, message_id)


func _qr_secret_key_bytes(secret_key: String) -> PackedByteArray:
	var text := secret_key.strip_edges().replace("-", "+").replace("_", "/")
	while text.length() % 4 != 0:
		text += "="
	return Marshalls.base64_to_raw(text)


func _host_accept_network_join(peer_id: int, message_id: String, payload: Dictionary, as_observer: bool, is_reconnect: bool) -> void:
	var room := _active_room()
	var requested_room_id := String(payload.get("roomId", "")).strip_edges()
	var active_room_id := String(room.get("id", "")).strip_edges()
	_network_debug("host accept_join start peer=%d reconnect=%s observer=%s requested_room=%s active_room=%s display=%s participant=%s" % [
		peer_id,
		str(is_reconnect),
		str(as_observer),
		requested_room_id,
		active_room_id,
		String(payload.get("displayName", "")).strip_edges(),
		String(payload.get("participantId", "")).strip_edges(),
	])
	if not is_reconnect and (requested_room_id == "" or active_room_id == "" or requested_room_id != active_room_id):
		_network_debug("host accept_join rejected peer=%d code=room_mismatch requested_room=%s active_room=%s" % [peer_id, requested_room_id, active_room_id])
		_room_network_session.call("send_to_peer", peer_id, "join_rejected", {
			"code": "room_mismatch",
			"message": "房间ID不匹配，二维码可能已失效",
		}, message_id)
		return
	var password := String(room.get("password", "")).strip_edges()
	var token := String(payload.get("joinToken", "")).strip_edges()
	if not is_reconnect and bool(_call_if_present("_is_game_started")):
		_network_debug("host accept_join rejected peer=%d code=game_already_started" % peer_id)
		_room_network_session.call("send_to_peer", peer_id, "join_rejected", {
			"code": "game_already_started",
			"message": "游戏开始后不能加入房间",
		}, message_id)
		return
	if not is_reconnect and password != "" and token != password:
		_network_debug("host accept_join rejected peer=%d code=wrong_password token_present=%s" % [peer_id, str(token != "")])
		_room_network_session.call("send_to_peer", peer_id, "join_rejected", {"code": "wrong_password", "message": "密码错误"}, message_id)
		return
	if is_reconnect:
		_host_accept_network_reconnect(peer_id, message_id, payload)
		return
	var display_name := String(payload.get("displayName", "")).strip_edges()
	if display_name == "":
		display_name = "玩家%d" % peer_id
	var participant_id := String(payload.get("participantId", "")).strip_edges()
	if participant_id == "":
		participant_id = "peer_%d_%d" % [peer_id, Time.get_ticks_msec()]
	var auth := _network_auth_payload(payload)
	var identity := _network_player_identity_payload(payload, display_name)
	var seat_index := -1
	var players := _state_array("_players")
	if not as_observer:
		var seat_value = _call_if_present("_first_empty_seat")
		seat_index = int(seat_value) if seat_value != null else -1
		if seat_index < 0:
			var observer_gate := _can_add_observer(room)
			if not bool(observer_gate.get("ok", false)):
				_network_debug("host accept_join rejected peer=%d code=%s observer_gate" % [peer_id, String(observer_gate.get("code", ""))])
				_room_network_session.call("send_to_peer", peer_id, "join_rejected", observer_gate, message_id)
				return
			_register_observer(room, participant_id, display_name, auth, identity)
			as_observer = true
			_room_network_session.call("set_peer_participant", peer_id, participant_id, -1, display_name)
			_set_system_message("%s 进入观战位" % display_name)
		else:
			var player_value = _call_if_present("_human_player_data", [participant_id, display_name, identity, seat_index])
			if not (player_value is Dictionary):
				_network_debug("host accept_join rejected peer=%d code=player_create_failed participant=%s seat=%d" % [peer_id, participant_id, seat_index])
				_room_network_session.call("send_to_peer", peer_id, "join_rejected", {"code": "player_create_failed", "message": "玩家数据创建失败"}, message_id)
				return
			var player: Dictionary = player_value
			display_name = String(player.get("name", display_name))
			player["device_id"] = String(auth.get("deviceId", ""))
			player["public_key"] = String(auth.get("publicKey", ""))
			players[seat_index] = player
			set("_players", players)
			_room_network_session.call("set_peer_participant", peer_id, participant_id, seat_index, display_name)
			_set_system_message("%s 加入 %d号位" % [display_name, seat_index + 1])
	else:
		var observer_gate := _can_add_observer(room)
		if not bool(observer_gate.get("ok", false)):
			_network_debug("host accept_join rejected peer=%d code=%s observer_gate" % [peer_id, String(observer_gate.get("code", ""))])
			_room_network_session.call("send_to_peer", peer_id, "join_rejected", observer_gate, message_id)
			return
		_register_observer(room, participant_id, display_name, auth, identity)
		_room_network_session.call("set_peer_participant", peer_id, participant_id, -1, display_name)
		_set_system_message("%s 旁观加入" % display_name)
	var reconnect_token := _ensure_network_reconnect_token(room, participant_id)
	var snapshot := _network_snapshot_for_participant(participant_id)
	_room_network_session.call("send_to_peer", peer_id, "join_accepted", {
		"participantId": participant_id,
		"participant": {"displayName": display_name, "seatNumber": seat_index + 1, "observer": as_observer},
		"reconnectToken": reconnect_token,
		"reconnected": false,
		"controlledBots": [],
		"room": snapshot,
		"roomReplicaFrame": _signed_room_replica_payload(),
	}, message_id)
	_network_debug("host accept_join ok peer=%d participant=%s seat=%d observer=%s display=%s peers=%s" % [
		peer_id,
		participant_id,
		seat_index,
		str(as_observer),
		display_name,
		str(_room_network_session.call("peer_debug_snapshot")) if _room_network_session != null and _room_network_session.has_method("peer_debug_snapshot") else "",
	])
	_call_if_present("_refresh_all_seats")
	_call_if_present("_refresh_room_controls")
	_call_if_present("_refresh_center_panel")
	_call_if_present("_commit_state")


func _host_accept_network_reconnect(peer_id: int, message_id: String, payload: Dictionary) -> void:
	var room := _active_room()
	var participant_id := String(payload.get("participantId", "")).strip_edges()
	var reconnect_token := String(payload.get("reconnectToken", "")).strip_edges()
	_network_debug("host reconnect start peer=%d participant=%s token_present=%s" % [peer_id, participant_id, str(reconnect_token != "")])
	if participant_id == "" or reconnect_token == "":
		_network_debug("host reconnect rejected peer=%d reason=incomplete participant=%s token_present=%s" % [peer_id, participant_id, str(reconnect_token != "")])
		_room_network_session.call("send_to_peer", peer_id, "join_rejected", {"message": "重连信息不完整"}, message_id)
		return
	var stored_token := _network_reconnect_token(room, participant_id)
	if stored_token != "" and stored_token != reconnect_token:
		_network_debug("host reconnect rejected peer=%d participant=%s reason=token_mismatch stored=%s incoming=%s" % [
			peer_id,
			participant_id,
			str(stored_token != ""),
			str(reconnect_token != ""),
		])
		_room_network_session.call("send_to_peer", peer_id, "join_rejected", {"message": "重连凭证无效"}, message_id)
		return
	var auth := _network_auth_payload(payload)
	var seat_value = _call_if_present("_seat_for_participant_id", [participant_id])
	var seat_index := int(seat_value) if seat_value != null else -1
	var observer := _observer_for_participant(room, participant_id)
	var players := _state_array("_players")
	if seat_index < 0 and observer.is_empty():
		_network_debug("host reconnect rejected peer=%d participant=%s reason=not_in_room" % [peer_id, participant_id])
		_room_network_session.call("send_to_peer", peer_id, "join_rejected", {"message": "参与者不在房间内"}, message_id)
		return
	if seat_index >= 0 and not _network_identity_matches(players[seat_index] as Dictionary, auth):
		_network_debug("host reconnect rejected peer=%d participant=%s reason=seat_identity_mismatch seat=%d" % [peer_id, participant_id, seat_index])
		_room_network_session.call("send_to_peer", peer_id, "join_rejected", {"message": "设备身份不匹配"}, message_id)
		return
	if not observer.is_empty() and not _network_identity_matches(observer, auth):
		_network_debug("host reconnect rejected peer=%d participant=%s reason=observer_identity_mismatch" % [peer_id, participant_id])
		_room_network_session.call("send_to_peer", peer_id, "join_rejected", {"message": "设备身份不匹配"}, message_id)
		return
	var display_name := String(observer.get("displayName", "观察者")) if seat_index < 0 else String((players[seat_index] as Dictionary).get("name", "玩家"))
	if seat_index >= 0:
		var player: Dictionary = (players[seat_index] as Dictionary).duplicate(true)
		player["state"] = "等待" if not bool(player.get("ready", false)) else "已准备"
		players[seat_index] = player
		set("_players", players)
		_room_network_session.call("set_peer_participant", peer_id, participant_id, seat_index, display_name)
	else:
		_room_network_session.call("set_peer_participant", peer_id, participant_id, -1, display_name)
	var next_token := _ensure_network_reconnect_token(room, participant_id)
	var snapshot := _network_snapshot_for_participant(participant_id)
	_room_network_session.call("send_to_peer", peer_id, "join_accepted", {
		"participantId": participant_id,
		"participant": {"displayName": display_name, "seatNumber": seat_index + 1, "observer": seat_index < 0},
		"reconnectToken": next_token,
		"reconnected": true,
		"controlledBots": [],
		"room": snapshot,
		"roomReplicaFrame": _signed_room_replica_payload(),
	}, message_id)
	_network_debug("host reconnect ok peer=%d participant=%s seat=%d observer=%s display=%s peers=%s" % [
		peer_id,
		participant_id,
		seat_index,
		str(seat_index < 0),
		display_name,
		str(_room_network_session.call("peer_debug_snapshot")) if _room_network_session != null and _room_network_session.has_method("peer_debug_snapshot") else "",
	])
	_set_system_message("%s 已重连" % display_name)
	if seat_index >= 0 and bool(_call_if_present("_is_werewolf_paused")) and not bool(_call_if_present("_has_offline_human_players")):
		_call_if_present("_set_werewolf_paused", [false, "", ""])
		_set_system_message("%s 已重连，游戏继续" % display_name)
	_call_if_present("_refresh_all_seats")
	_call_if_present("_refresh_room_controls")
	_call_if_present("_refresh_center_panel")
	_call_if_present("_commit_state")
	_call_if_present("_schedule_auto_resolve_bot_turns")


func _network_player_identity_payload(payload: Dictionary, display_name: String) -> Dictionary:
	var voice_config_id := String(payload.get("voiceConfigId", payload.get("playbackVoiceConfigId", ""))).strip_edges()
	return {
		"name": display_name,
		"displayName": display_name,
		"avatar_id": String(payload.get("avatarId", payload.get("avatar_id", ""))).strip_edges(),
		"avatarId": String(payload.get("avatarId", payload.get("avatar_id", ""))).strip_edges(),
		"avatar": String(payload.get("avatar", "")).strip_edges(),
		"voice_config_id": voice_config_id,
		"voiceConfigId": voice_config_id,
		"playback_voice_config_id": voice_config_id,
		"playbackVoiceConfigId": voice_config_id,
		"voice": String(payload.get("voiceName", payload.get("voice", ""))).strip_edges(),
		"voiceName": String(payload.get("voiceName", payload.get("voice", ""))).strip_edges(),
	}


func _game_id_for_room_type(game_type: String) -> String:
	if game_type == "狼人杀":
		return "werewolf"
	if game_type == "象棋":
		return "xiangqi"
	return game_type.to_lower()


func _game_id_for_room(room: Dictionary) -> String:
	var explicit := String(room.get("game_room_id", room.get("gameId", ""))).strip_edges()
	if explicit != "":
		return "xiangqi" if explicit == "象棋" else explicit
	return _game_id_for_room_type(String(room.get("type", "狼人杀")))


func _type_for_game_id(game_id: String) -> String:
	if game_id == "werewolf":
		return "狼人杀"
	if game_id == "xiangqi":
		return "象棋"
	return game_id
