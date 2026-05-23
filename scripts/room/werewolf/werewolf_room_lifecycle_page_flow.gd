extends "res://scripts/player/werewolf/ai/ai_werewolf_player_page_flow.gd"


func _publish_active_room() -> void:
	if not _is_network_host():
		return
	var room := _active_room()
	if room.is_empty() or bool(room.get("discovered", false)):
		return
	_refresh_active_room_bot_occupancy()
	var host := _local_host_address()
	var publish_room := _room_discovery.room_from_state(room, _players, host, _room_network_port, String(_device_identity.device_id), String(_device_identity.public_key))
	_room_discovery.publish(publish_room)


func _leave_room_to_lobby() -> void:
	_prepare_leave_active_room()
	navigate_requested.emit("lobby", {})


func _prepare_leave_active_room() -> void:
	var room_id := String(_app_state.active_room_id) if _app_state != null else String(_active_room().get("id", ""))
	if room_id == "":
		return
	if _is_network_client():
		if _room_network_session != null and _room_network_session.has_method("request_leave_room"):
			_room_network_session.call("request_leave_room")
		if _room_network_session != null:
			_room_network_session.stop()
		if _app_state != null:
			_app_state.active_room_id = ""
		_commit_state()
		return
	_clear_local_human_presence()
	if _active_room_has_no_people():
		_destroy_active_room(room_id)
		return
	_system_message = "已退出房间"
	_commit_state()


func _clear_local_human_presence() -> void:
	for i in range(_players.size()):
		if not (_players[i] is Dictionary):
			continue
		var player: Dictionary = _players[i]
		if String(player.get("owner", "")) == "self":
			_players[i] = _empty_seat_data(i)
	_remove_observer(_active_room(), _current_network_participant_id())
	_local_player_index = -1


func _active_room_has_no_people() -> bool:
	for player_value in _players:
		if not (player_value is Dictionary):
			continue
		var player: Dictionary = player_value
		var owner := String(player.get("owner", ""))
		if owner == "self":
			return false
		if owner == "human" and String(player.get("participant_id", "")).strip_edges() != "":
			return false
	return true


func _destroy_active_room(room_id: String) -> void:
	var room := _active_room()
	var host := _local_host_address()
	var port := _room_network_port
	var host_device_id := String(_device_identity.device_id)
	var host_public_key := String(_device_identity.public_key)
	if not room.is_empty():
		host = String(room.get("host", host)).strip_edges()
		port = int(room.get("port", port))
		host_device_id = String(room.get("host_device_id", room.get("hostDeviceId", host_device_id)))
		host_public_key = String(room.get("host_public_key", room.get("hostPublicKey", host_public_key)))
	if _room_network_session != null and _room_network_session.has_method("broadcast"):
		_room_network_session.call("broadcast", "room_closed", {"roomId": room_id})
	_publish_room_closed(room_id, host, port, host_device_id, host_public_key)
	for i in range(_rooms.size() - 1, -1, -1):
		if _rooms[i] is Dictionary and String((_rooms[i] as Dictionary).get("id", "")) == room_id:
			_rooms.remove_at(i)
	if _room_network_session != null and _room_network_session.has_method("is_active") and bool(_room_network_session.call("is_active")):
		_room_network_session.stop()
	_clear_room_transient_data(room_id)
	_commit_state()


func _publish_room_closed(room_id: String, host: String, port: int, host_device_id: String = "", host_public_key: String = "") -> void:
	for _i in range(3):
		_room_discovery.publish_closed(room_id, host, port, host_device_id, host_public_key)


func _clear_room_transient_data(room_id: String) -> void:
	if _app_state != null and String(_app_state.active_room_id) == room_id:
		_app_state.active_room_id = ""
	_clear_room_runtime_artifacts(room_id, true)
	_players.clear()
	_local_player_index = -1
	_bot_serial = 1
	_phase_night = false
	_werewolf = _engine.default_state()
	_history.clear()
	if has_method("_clear_werewolf_room_runtime"):
		call("_clear_werewolf_room_runtime")
	_system_message = "等待创建房间"


func _clear_room_runtime_artifacts(room_id: String, clear_unknown_session_room: bool = false) -> void:
	var clean_room_id := room_id.strip_edges()
	if clean_room_id == "":
		return
	if _room_replica_store != null:
		_room_replica_store.delete_room(clean_room_id)
	_host_takeover_attempted_rooms.erase(clean_room_id)
	_clear_reconnect_session_for_room(clean_room_id, clear_unknown_session_room)
	_discard_room_session_memory(clean_room_id)


func _clear_reconnect_session_for_room(room_id: String, clear_unknown_session_room: bool = false) -> void:
	if _room_session_store == null:
		return
	var session: Dictionary = _room_session_store.load()
	if session.is_empty():
		return
	var session_room_id := String(session.get("roomId", "")).strip_edges()
	if session_room_id == room_id or (clear_unknown_session_room and session_room_id == ""):
		_room_session_store.clear()


func _discard_room_session_memory(room_id: String) -> void:
	var clean_room_id := room_id.strip_edges()
	if clean_room_id == "":
		return
	_ensure_memory_loaded()
	for scope_value in _memory_manager.list_scopes("", "werewolf", ""):
		if not (scope_value is Dictionary):
			continue
		var scope_data: Dictionary = scope_value
		if String(scope_data.get("room_id", "")).strip_edges() == clean_room_id:
			_memory_manager.discard_session(scope_data)


func _start_host_room_network() -> bool:
	_ensure_room_network_session()
	_apply_network_identity()
	if _room_network_session == null:
		return false
	if _room_network_session.has_method("is_host") and bool(_room_network_session.call("is_host")):
		if _room_network_session.has_method("port") and int(_room_network_session.call("port")) > 0:
			_room_network_port = int(_room_network_session.call("port"))
		return true
	var result: Dictionary = _room_network_session.call("start_host", _room_network_port)
	if bool(result.get("ok", false)):
		_room_network_port = int(result.get("port", _room_network_port))
		_system_message = "房间网络已开启，端口 %d" % _room_network_port
		return true
	_system_message = String(result.get("error", "房间网络启动失败"))
	_flash_effect("skip")
	return false


func _refresh_active_room_network_fields() -> void:
	var room := _active_room()
	if room.is_empty():
		return
	if _room_network_session != null and _room_network_session.has_method("is_host") and bool(_room_network_session.call("is_host")) and _room_network_session.has_method("port"):
		_room_network_port = int(_room_network_session.call("port"))
	var host := _local_host_address()
	var payload := _build_join_payload(false)
	room["host"] = host
	room["port"] = _room_network_port
	room["address"] = "%s:%d" % [host, _room_network_port]
	room["host_device_id"] = String(_device_identity.device_id)
	room["host_public_key"] = String(_device_identity.public_key)
	room["join_payload"] = payload
	room["requiresJoinToken"] = String(room.get("password", "")).strip_edges() != ""
	room["bg"] = _room_background_path(room)
	room["active_bot_profile_ids"] = _active_bot_profile_ids()
	for i in range(_rooms.size()):
		if String(_rooms[i].get("id", "")) == String(room.get("id", "")):
			_rooms[i] = room
			break


func _upsert_room(room: Dictionary) -> void:
	var room_id := String(room.get("id", ""))
	if room_id == "":
		return
	for i in range(_rooms.size()):
		if String(_rooms[i].get("id", "")) == room_id:
			_rooms[i] = room
			return
	_rooms.push_front(room)


func _refresh_active_room_bot_occupancy() -> void:
	var room := _active_room()
	if room.is_empty():
		return
	room["active_bot_profile_ids"] = _active_bot_profile_ids()


func _active_bot_profile_ids() -> Array:
	var ids := []
	for i in range(_players.size()):
		var player_value = _players[i]
		if not (player_value is Dictionary):
			continue
		var profile_id := _local_private_bot_profile_id_for_seat(i)
		if profile_id != "" and not ids.has(profile_id):
			ids.append(profile_id)
	return ids


func _bot_profile_room_occupancy(profile_id: String, ignored_room_id: String = "") -> Dictionary:
	var clean_profile_id := profile_id.strip_edges()
	if clean_profile_id == "":
		return {}
	var ignored := ignored_room_id.strip_edges()
	for room_value in _rooms:
		if not (room_value is Dictionary):
			continue
		var room: Dictionary = room_value
		var room_id := String(room.get("id", "")).strip_edges()
		if ignored != "" and room_id == ignored:
			continue
		var ids := _room_active_bot_profile_ids(room)
		if ids.has(clean_profile_id):
			return room.duplicate(true)
	return {}


func _bot_profile_available_for_room(profile_id: String, room_id: String = "") -> Dictionary:
	var clean_profile_id := profile_id.strip_edges()
	if clean_profile_id == "":
		return {"ok": true, "message": ""}
	var occupied_room := _bot_profile_room_occupancy(clean_profile_id, room_id)
	if occupied_room.is_empty():
		return {"ok": true, "message": ""}
	return {
		"ok": false,
		"message": "该机器人正在房间「%s」中" % String(occupied_room.get("name", "其他房间")),
		"room": occupied_room,
	}


func _room_active_bot_profile_ids(room: Dictionary) -> Array:
	var ids := []
	var explicit_value = room.get("active_bot_profile_ids", room.get("botProfileIds", []))
	if explicit_value is Array:
		for item in explicit_value as Array:
			var id := String(item).strip_edges()
			if id != "" and not ids.has(id):
				ids.append(id)
	var participants_value = room.get("participants", [])
	if participants_value is Array:
		for item in participants_value as Array:
			if not (item is Dictionary):
				continue
			var data: Dictionary = item
			var id := String(data.get("botProfileId", data.get("bot_profile_id", ""))).strip_edges()
			if id != "" and not ids.has(id):
				ids.append(id)
	return ids


func _host_apply_device_task_result(peer_id: int, payload: Dictionary) -> void:
	if _is_network_client():
		return
	if has_method("_is_werewolf_paused") and bool(call("_is_werewolf_paused")):
		if OS.is_debug_build():
			print("[WerewolfDeviceTask][debug] result ignored reason=game_paused peer=%d payload=%s" % [peer_id, JSON.stringify(payload)])
		return
	var task_id := String(payload.get("taskId", payload.get("task_id", ""))).strip_edges()
	if task_id == "":
		if peer_id > 0:
			_send_network_rejection(peer_id, "任务结果缺少 taskId")
		print("[WerewolfDeviceTask][error] result ignored reason=no_task_id peer=%d payload=%s" % [peer_id, JSON.stringify(payload)])
		return
	var participant_id := "host"
	if peer_id > 0:
		participant_id = String(_room_network_session.call("peer_participant_id", peer_id)).strip_edges()
		if participant_id == "":
			_send_network_rejection(peer_id, "设备身份无效")
			print("[WerewolfDeviceTask][error] result ignored id=%s peer=%d reason=no_participant" % [task_id, peer_id])
			return
	var task := _device_task_channel.task(task_id)
	if task.is_empty():
		if peer_id > 0:
			_send_network_rejection(peer_id, "任务已过期")
		if OS.is_debug_build():
			print("[WerewolfDeviceTask][debug] stale result id=%s participant=%s" % [task_id, participant_id])
		return
	var expected := String(task.get("controller_participant_id", task.get("controllerParticipantId", ""))).strip_edges()
	if expected != participant_id:
		if peer_id > 0:
			_send_network_rejection(peer_id, "任务设备不匹配")
		print("[WerewolfDeviceTask][error] result rejected id=%s expected=%s actual=%s" % [task_id, expected, participant_id])
		return
	var popped := _device_task_channel.pop_task(task_id)
	var task_type := String(popped.get("type", popped.get("taskType", ""))).strip_edges()
	_sync_device_task_gate_state()
	if participant_id == _current_network_participant_id() and _current_device_task_id == task_id:
		_current_device_task_id = ""
	if OS.is_debug_build():
		print("[WerewolfDeviceTask][debug] result accepted id=%s type=%s actor=%s participant=%s ok=%s pending=%d waiting=%s" % [
			task_id,
			task_type,
			_player_title(int(popped.get("actor_index", popped.get("actorIndex", -1)))),
			participant_id,
			str(payload.get("ok", "")),
			_device_task_channel.pending_count(),
			str(_device_task_waiting_for_result),
		])
	match task_type:
		"player_action":
			_host_apply_device_task_action(popped, payload)
		"player_speech":
			_host_apply_device_task_speech(popped, payload)
		_:
			print("[WerewolfDeviceTask][error] result unsupported id=%s type=%s" % [task_id, task_type])
	if not _device_task_blocks_auto_advance() and has_method("_on_device_task_gate_open"):
		call("_on_device_task_gate_open", task_id)


func _host_apply_device_task_action(task: Dictionary, payload: Dictionary) -> void:
	var actor_index := int(task.get("actor_index", task.get("actorIndex", -1)))
	if actor_index != _pending_actor_index:
		if OS.is_debug_build():
			print("[WerewolfDeviceTask][debug] action stale id=%s actor=%d pending=%d" % [
				String(task.get("id", "")),
				actor_index,
				_pending_actor_index,
			])
		_schedule_auto_resolve_bot_turns()
		return
	if not bool(payload.get("ok", true)):
		_send_device_task_failure_to_room(task, payload, "玩家行动失败")
		return
	var action_name := String(payload.get("action", "")).strip_edges()
	if action_name == "skip" or action_name == "witch_skip" or action_name == "sheriff_badge_destroy":
		var skip_result: Dictionary = _engine.skip_current_action(_werewolf, _players, _local_player_index)
		if not bool(skip_result.get("ok", false)):
			_send_device_task_failure_to_room(task, skip_result, "玩家行动失败")
			return
		_apply_engine_result(skip_result)
		return
	if action_name == "witch_save" and has_method("_current_witch_save_target_index"):
		var save_target := int(call("_current_witch_save_target_index"))
		if save_target >= 0:
			payload["targetIndex"] = save_target
			payload["targetSeatNumber"] = save_target + 1
	var target_index := _payload_target_index(payload)
	if target_index < 0:
		_send_device_task_failure_to_room(task, payload, "目标无效")
		return
	var action := _pending_action
	var result: Dictionary = _engine.apply_target(_werewolf, _players, target_index, _local_player_index, action_name)
	if not bool(result.get("ok", false)):
		_send_device_task_failure_to_room(task, result, "玩家行动失败")
		return
	var accepted := _apply_engine_result(result)
	if accepted and target_index >= 0 and target_index < _seat_cards.size():
		_seat_cards[target_index].play_action_effect(_action_effect_kind(action))


func _host_apply_device_task_speech(task: Dictionary, payload: Dictionary) -> void:
	var speaker_index := int(task.get("actor_index", task.get("actorIndex", -1)))
	if speaker_index != _speech_prompt_index:
		if OS.is_debug_build():
			print("[WerewolfDeviceTask][debug] speech stale id=%s speaker=%d pending=%d" % [
				String(task.get("id", "")),
				speaker_index,
				_speech_prompt_index,
			])
		_schedule_auto_resolve_bot_turns()
		return
	if not bool(payload.get("ok", true)):
		_send_device_task_failure_to_room(task, payload, "玩家发言失败")
		return
	var phase_before := String(_werewolf.get("phase", ""))
	var speech_text := String(payload.get("text", payload.get("speechText", "")))
	var result: Dictionary = _engine.submit_speech(_werewolf, _players, speech_text, _local_player_index)
	if not bool(result.get("ok", false)):
		_send_device_task_failure_to_room(task, result, "玩家发言失败")
		return
	if bool(result.get("ok", false)) and phase_before == "wolf_chat" and has_method("_record_wolf_private_chat"):
		call("_record_wolf_private_chat", speaker_index, speech_text, false)
	_apply_engine_result(result)


func _send_device_task_failure_to_room(task: Dictionary, payload: Dictionary, fallback_message: String) -> void:
	var actor_index := int(task.get("actor_index", task.get("actorIndex", -1)))
	var error := String(payload.get("error", payload.get("message", fallback_message))).strip_edges()
	if error == "":
		error = fallback_message
	var fatal := bool(payload.get("fatal", false)) or String(payload.get("failureKind", "")).strip_edges() == "ai_player"
	print("[WerewolfDeviceTask][error] task failed id=%s type=%s actor=%s error=%s payload=%s" % [
		String(task.get("id", "")),
		String(task.get("type", task.get("taskType", ""))),
		_player_title(actor_index) if actor_index >= 0 and actor_index < _players.size() else "",
		error,
		JSON.stringify(payload),
	])
	if fatal and has_method("_halt_werewolf_bot_game"):
		call("_halt_werewolf_bot_game", fallback_message, error, {"actor_index": actor_index})
		return
	_system_message = "%s：%s" % [fallback_message, error]
	if has_method("_show_system_progress_toast"):
		call("_show_system_progress_toast", _system_message, 8.0)
	_refresh_center_panel()
	_flash_effect("skip")


func _host_drop_device_task_participant(participant_id: String) -> void:
	var removed := _device_task_channel.remove_tasks_for_participant(participant_id)
	_sync_device_task_gate_state()
	if removed.is_empty():
		return
	for task_value in removed:
		if not (task_value is Dictionary):
			continue
		var task: Dictionary = task_value
		print("[WerewolfDeviceTask][error] participant dropped id=%s type=%s participant=%s" % [
			String(task.get("id", "")),
			String(task.get("type", task.get("taskType", ""))),
			participant_id,
		])
	if has_method("_set_werewolf_paused") and _is_game_started():
		call("_set_werewolf_paused", true, "执行设备已断开", participant_id)
	_system_message = "游戏暂停：执行设备已断开"
	if has_method("_show_system_progress_toast"):
		call("_show_system_progress_toast", _system_message, 8.0)
	_refresh_center_panel()


func _host_apply_peer_action(peer_id: int, payload: Dictionary) -> void:
	var task_id := String(payload.get("taskId", payload.get("task_id", ""))).strip_edges()
	if task_id != "":
		_host_apply_device_task_result(peer_id, payload)
		return
	_send_network_rejection(peer_id, "当前版本必须通过主机下发的设备任务提交行动")
	print("[WerewolfDeviceTask][error] legacy game_action rejected peer=%d payload=%s" % [peer_id, JSON.stringify(payload)])


func _host_apply_peer_speech(peer_id: int, payload: Dictionary) -> void:
	var task_id := String(payload.get("taskId", payload.get("task_id", ""))).strip_edges()
	if task_id != "":
		_host_apply_device_task_result(peer_id, payload)
		return
	_send_network_rejection(peer_id, "当前版本必须通过主机下发的设备任务提交发言")
	print("[WerewolfDeviceTask][error] legacy chat_message rejected peer=%d payload=%s" % [peer_id, JSON.stringify(payload)])


func _local_player_data(ignore_index: int = -1) -> Dictionary:
	if _local_player_index >= 0 and _local_player_index < _players.size() and String(_players[_local_player_index].get("owner", "")) == "self":
		var current: Dictionary = _players[_local_player_index].duplicate(true)
		var unique_ignore_index := ignore_index if ignore_index >= 0 else _local_player_index
		current["name"] = _room_player_factory.room_unique_name(String(current.get("name", _local_nickname)), _players, unique_ignore_index, "玩家")
		current["owner"] = "self"
		current["participant_id"] = _current_network_participant_id()
		_local_nickname = String(current.get("name", _local_nickname))
		return current
	var player := _room_player_factory.self_player_from_identity(_current_network_participant_id(), _preference_identity_snapshot(), _players, ignore_index, SeatMotion.IDLE)
	_local_nickname = String(player.get("name", _local_nickname))
	return player


func _empty_seat_data(index: int) -> Dictionary:
	return _room_player_factory.empty_seat(index, SeatMotion.IDLE)


func _human_player_data(participant_id: String, display_name: String, identity: Dictionary = {}, ignore_index: int = -1) -> Dictionary:
	var source := identity.duplicate(true)
	if String(source.get("name", source.get("displayName", ""))).strip_edges() == "":
		source["name"] = display_name
	return _room_player_factory.human_player_from_identity(participant_id, source, _players, ignore_index, SeatMotion.IDLE)


func _bot_player_data(_bot_profile_id: String, bot_name: String, _model_name: String = "", _voice_name: String = "", controller_participant_id: String = "", profile: Dictionary = {}, ignore_index: int = -1) -> Dictionary:
	var source := profile.duplicate(true)
	if String(source.get("name", source.get("displayName", ""))).strip_edges() == "":
		source["name"] = bot_name
	if String(source.get("voice", source.get("voiceName", ""))).strip_edges() == "" and _voice_name.strip_edges() != "":
		source["voice"] = _voice_name
	return _room_player_factory.bot_player_from_profile(_bot_serial, source, controller_participant_id, _players, ignore_index, SeatMotion.IDLE)


func _visible_role_for_index(index: int) -> String:
	if index < 0 or index >= _players.size():
		return "未知"
	var player: Dictionary = _players[index] as Dictionary
	if String(player.get("owner", "")) == "":
		return "空位"
	if has_method("_role_visible_for_current_view") and bool(call("_role_visible_for_current_view", index)):
		return String(player.get("role", "未知"))
	return _room_player_factory.visible_role_for_player(player)


func _set_seat_motion(index: int, motion: int, close_modal: bool = true) -> void:
	if index < 0 or index >= _players.size():
		return
	_players[index]["motion"] = motion
	_players[index]["alive"] = motion != SeatMotion.DEAD
	match motion:
		SeatMotion.THINKING:
			_players[index]["state"] = "思考中"
		SeatMotion.SPEAKING:
			_players[index]["state"] = "发言中"
		SeatMotion.DEAD:
			_players[index]["state"] = "死亡"
		_:
			_players[index]["state"] = "等待"
	if _mode == Mode.TABLE and index < _seat_cards.size():
		_seat_cards[index].data = _seat_card_data(index)
		_seat_cards[index].start_motion(motion)
	if close_modal:
		_clear_modal()
