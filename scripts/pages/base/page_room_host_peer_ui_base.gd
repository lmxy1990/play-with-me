extends "res://scripts/pages/base/page_room_join_ui_base.gd"


func _host_set_peer_ready(peer_id: int, ready: bool) -> void:
	var index := int(_room_network_session.call("peer_seat_index", peer_id))
	var players := _state_array("_players")
	if index < 0 or index >= players.size():
		_send_network_rejection(peer_id, "请先落座")
		return
	var player: Dictionary = (players[index] as Dictionary).duplicate(true)
	player["ready"] = ready
	player["state"] = "已准备" if ready else "等待"
	players[index] = player
	set("_players", players)
	_set_system_message("%s · %s" % [_player_title_text(index), "已准备" if ready else "取消准备"])
	_call_if_present("_refresh_seat", [index])
	_call_if_present("_refresh_room_controls")
	_call_if_present("_commit_state")


func _host_switch_peer_seat(peer_id: int, target_index: int) -> void:
	var participant_id := String(_room_network_session.call("peer_participant_id", peer_id)).strip_edges()
	if participant_id == "":
		_send_network_rejection(peer_id, "请先加入房间")
		return
	var players := _state_array("_players")
	var room := _active_room()
	var from_index := _seat_for_participant_id(participant_id)
	var observer := _observer_for_participant(room, participant_id)
	if from_index < 0 and observer.is_empty():
		_send_network_rejection(peer_id, "请先加入房间")
		return
	if target_index < 0 or target_index >= players.size() or not _bool_call("_is_empty_seat", [target_index]):
		_send_network_rejection(peer_id, "目标座位不可用")
		return
	var gate := _room_can_change_seat_gate()
	if not bool(gate.get("ok", false)):
		_send_network_rejection(peer_id, String(gate.get("message", "不能切换座位")))
		return
	var display_name := "玩家"
	if from_index >= 0:
		display_name = String(players[from_index].get("name", "玩家"))
	elif not observer.is_empty():
		display_name = String(observer.get("displayName", "玩家"))
	var player_value = _call_if_present("_human_player_data", [participant_id, display_name])
	var player: Dictionary = player_value if player_value is Dictionary else {}
	if from_index >= 0 and from_index < players.size():
		player = (players[from_index] as Dictionary).duplicate(true)
		var empty_value = _call_if_present("_empty_seat_data", [from_index])
		players[from_index] = empty_value if empty_value is Dictionary else {}
	elif not observer.is_empty():
		player["device_id"] = String(observer.get("device_id", observer.get("deviceId", "")))
		player["public_key"] = String(observer.get("public_key", observer.get("publicKey", "")))
		_remove_observer(room, participant_id)
	player["ready"] = false
	player["state"] = "等待"
	player["owner"] = "human"
	player["participant_id"] = participant_id
	players[target_index] = player
	set("_players", players)
	_room_network_session.call("set_peer_participant", peer_id, participant_id, target_index, String(player.get("name", display_name)))
	_set_system_message("%s 落座 %d号位" % [String(player.get("name", "玩家")), target_index + 1])
	_call_if_present("_refresh_all_seats")
	_call_if_present("_refresh_room_controls")
	_call_if_present("_refresh_center_panel")
	_call_if_present("_commit_state")


func _host_switch_peer_to_observer(peer_id: int) -> void:
	var participant_id := String(_room_network_session.call("peer_participant_id", peer_id)).strip_edges()
	if participant_id == "":
		_send_network_rejection(peer_id, "请先加入房间")
		return
	if _is_observer_participant(participant_id):
		_room_network_session.call("set_peer_seat", peer_id, -1)
		_room_network_session.call("send_to_peer", peer_id, "room_snapshot", _network_snapshot_for_participant(participant_id))
		return
	var gate := _room_can_change_seat_gate()
	if not bool(gate.get("ok", false)):
		_send_network_rejection(peer_id, String(gate.get("message", "游戏开始后不能切换观察身份")))
		return
	var players := _state_array("_players")
	var index := _seat_for_participant_id(participant_id)
	if index < 0 or index >= players.size():
		_send_network_rejection(peer_id, "只有真人玩家可以切换为观察者")
		return
	var player: Dictionary = players[index]
	if String(player.get("owner", "")) != "human":
		_send_network_rejection(peer_id, "只有真人玩家可以切换为观察者")
		return
	var room := _active_room()
	var observer_gate := _can_add_observer_after_seat_release(room, participant_id)
	if not bool(observer_gate.get("ok", false)):
		_send_network_rejection(peer_id, String(observer_gate.get("message", "不能切换为观察者")))
		return
	_register_observer(room, participant_id, String(player.get("name", "观察者")), {
		"deviceId": String(player.get("device_id", "")),
		"publicKey": String(player.get("public_key", "")),
	})
	var empty_value = _call_if_present("_empty_seat_data", [index])
	players[index] = empty_value if empty_value is Dictionary else {}
	set("_players", players)
	_room_network_session.call("set_peer_seat", peer_id, -1)
	_set_system_message("%s 切换为观战" % String(player.get("name", "玩家")))
	_call_if_present("_refresh_all_seats")
	_call_if_present("_refresh_room_controls")
	_call_if_present("_refresh_center_panel")
	_call_if_present("_commit_state")


func _host_add_peer_bot(peer_id: int, payload: Dictionary) -> void:
	var participant_id := String(_room_network_session.call("peer_participant_id", peer_id))
	if participant_id == "":
		if OS.is_debug_build():
			print("[MainUI][debug] host_add_controlled_player rejected peer=%d reason=no_participant payload_seat=%s" % [peer_id, str(payload.get("seatIndex", ""))])
		_send_network_rejection(peer_id, "请先加入房间")
		return
	var players := _state_array("_players")
	var index := _payload_seat_index(payload)
	var gate := _room_can_add_bot_gate()
	if not bool(gate.get("ok", false)) or index < 0 or index >= players.size() or not _bool_call("_is_empty_seat", [index]):
		if OS.is_debug_build():
			print("[MainUI][debug] host_add_controlled_player rejected peer=%d participant=%s seat=%d gate=%s message=%s" % [
				peer_id,
				participant_id,
				index,
				str(bool(gate.get("ok", false))),
				String(gate.get("message", "")),
			])
		_send_network_rejection(peer_id, String(gate.get("message", "不能添加机器人")))
		return
	var name := String(payload.get("displayName", "")).strip_edges()
	var bot_serial := int(get("_bot_serial"))
	if name == "":
		name = "机器人%d" % [bot_serial]
	if OS.is_debug_build():
		print("[MainUI][debug] host_add_controlled_player accepted peer=%d participant=%s seat=%d name=%s serial=%d" % [
			peer_id,
			participant_id,
			index,
			name,
			bot_serial,
		])
	var bot_value = _call_if_present("_bot_player_data", ["", name, "", "", participant_id])
	if not (bot_value is Dictionary):
		_send_network_rejection(peer_id, "机器人数据创建失败")
		return
	players[index] = bot_value
	set("_players", players)
	set("_bot_serial", bot_serial + 1)
	_set_system_message("受控玩家加入 %d号位" % [index + 1])
	_call_if_present("_refresh_seat", [index])
	_call_if_present("_refresh_room_controls")
	_call_if_present("_refresh_active_room_bot_occupancy")
	_call_if_present("_commit_state")


func _host_remove_peer_bot(peer_id: int, payload: Dictionary) -> void:
	var participant_id := String(_room_network_session.call("peer_participant_id", peer_id)).strip_edges()
	if participant_id == "":
		_send_network_rejection(peer_id, "请先加入房间")
		return
	var index := _payload_seat_index(payload)
	var players := _state_array("_players")
	if index < 0 or index >= players.size() or not (players[index] is Dictionary):
		_send_network_rejection(peer_id, "机器人不存在")
		return
	if _bool_call("_is_game_started"):
		_send_network_rejection(peer_id, "对局已开始，不能移除机器人")
		return
	var gate := _room_can_add_bot_gate()
	if not bool(gate.get("ok", false)):
		_send_network_rejection(peer_id, String(gate.get("message", "不能移除机器人")))
		return
	var player: Dictionary = players[index]
	if String(player.get("controller_participant_id", "host")) != participant_id:
		_send_network_rejection(peer_id, "只能移除自己控制的玩家")
		return
	if String(player.get("participant_id", "")).strip_edges() != "":
		_send_network_rejection(peer_id, "不能移除真人玩家")
		return
	if _participant_ready(participant_id):
		_send_network_rejection(peer_id, "已准备后不能移除机器人")
		return
	var bot_name := String(player.get("name", "机器人"))
	var empty_value = _call_if_present("_empty_seat_data", [index])
	players[index] = empty_value if empty_value is Dictionary else {}
	set("_players", players)
	_set_system_message("%s 已移除" % bot_name)
	_call_if_present("_refresh_seat", [index])
	_call_if_present("_refresh_room_controls")
	_call_if_present("_refresh_active_room_bot_occupancy")
	_call_if_present("_commit_state")


func _host_update_peer_participant(peer_id: int, payload: Dictionary) -> void:
	var participant_id := String(_room_network_session.call("peer_participant_id", peer_id))
	var target_index := _payload_seat_index(payload)
	if target_index < 0:
		target_index = _seat_for_participant_id(participant_id)
	var players := _state_array("_players")
	if target_index < 0 or target_index >= players.size():
		_send_network_rejection(peer_id, "玩家不存在")
		return
	var player: Dictionary = (players[target_index] as Dictionary).duplicate(true)
	var owner := String(player.get("owner", ""))
	if String(player.get("participant_id", "")).strip_edges() == "" and String(player.get("controller_participant_id", "")).strip_edges() != "":
		_send_network_rejection(peer_id, "机器人名称不能修改")
		return
	if _bool_call("_is_game_started"):
		_send_network_rejection(peer_id, "对局已开始，不能修改名字")
		return
	var can_edit := String(player.get("participant_id", "")) == participant_id
	if not can_edit:
		_send_network_rejection(peer_id, "不能修改该玩家")
		return
	var next_name := String(payload.get("displayName", "")).strip_edges()
	if next_name == "":
		next_name = "玩家"
	player["name"] = next_name
	players[target_index] = player
	set("_players", players)
	_set_system_message("名字已修改")
	_call_if_present("_refresh_seat", [target_index])
	_call_if_present("_commit_state")


func _host_mark_peer_left(peer_id: int, explicit_leave: bool = false) -> void:
	var participant_id := String(_room_network_session.call("peer_participant_id", peer_id))
	var active_room_id := String(_app_state.active_room_id) if _app_state != null else String(_active_room().get("id", ""))
	var should_destroy_room := false
	var players := _state_array("_players")
	var index := _seat_for_participant_id(participant_id)
	if index >= 0 and index < players.size():
		var player: Dictionary = (players[index] as Dictionary).duplicate(true)
		var display_name := String(player.get("name", "玩家"))
		if explicit_leave:
			var empty_value = _call_if_present("_empty_seat_data", [index])
			players[index] = empty_value if empty_value is Dictionary else {}
			_room_network_session.call("set_peer_participant", peer_id, "", -1, "")
			_set_system_message("%s 已离开房间" % display_name)
		else:
			player["state"] = "离线"
			player["ready"] = false
			players[index] = player
			_set_system_message("%s 离线" % _player_title_text(index))
			if _bool_call("_is_game_started"):
				_call_if_present("_set_werewolf_paused", [true, "%s 设备断线" % _player_title_text(index), participant_id])
				_set_system_message("游戏暂停：%s 设备断线" % _player_title_text(index))
		set("_players", players)
		if participant_id != "":
			_call_if_present("_host_drop_presentation_ack_participant", [participant_id])
			_call_if_present("_host_drop_device_task_participant", [participant_id])
		should_destroy_room = explicit_leave and bool(_call_if_present("_active_room_has_no_people"))
		if should_destroy_room and active_room_id != "":
			_call_if_present("_destroy_active_room", [active_room_id])
			return
		_call_if_present("_refresh_all_seats")
		_call_if_present("_refresh_room_controls")
		_call_if_present("_refresh_center_panel")
		_call_if_present("_commit_state")
		return
	var room := _active_room()
	if _remove_observer(room, participant_id):
		if explicit_leave:
			_room_network_session.call("set_peer_participant", peer_id, "", -1, "")
			_set_system_message("观察者已离开")
		else:
			_set_system_message("观察者离线")
		_call_if_present("_refresh_room_controls")
		_call_if_present("_commit_state")


func _first_empty_seat() -> int:
	var players := _state_array("_players")
	for i in range(players.size()):
		if _bool_call("_is_empty_seat", [i]):
			return i
	return -1


func _seat_for_participant_id(participant_id: String) -> int:
	var clean := participant_id.strip_edges()
	var players := _state_array("_players")
	for i in range(players.size()):
		if not (players[i] is Dictionary):
			continue
		var player: Dictionary = players[i]
		var owner := String(player.get("owner", ""))
		var player_participant := String(player.get("participant_id", ""))
		if clean != "" and player_participant == clean:
			return i
		if clean == "host" and owner == "self":
			return i
	return -1


func _participant_controls_index(participant_id: String, index: int) -> bool:
	var players := _state_array("_players")
	if index < 0 or index >= players.size() or not (players[index] is Dictionary):
		return false
	var player: Dictionary = players[index]
	var owner := String(player.get("owner", ""))
	if owner == "self":
		var player_participant := String(player.get("participant_id", ""))
		return player_participant == participant_id or (participant_id == "host" and player_participant == "")
	if owner == "human":
		var player_participant := String(player.get("participant_id", "")).strip_edges()
		if player_participant != "":
			return player_participant == participant_id
	var controller := String(player.get("controller_participant_id", "")).strip_edges()
	if controller != "":
		return controller == participant_id
	return false


func _can_local_control_index(index: int) -> bool:
	return _participant_controls_index(_current_network_participant_id(), index)


func _participant_ready(participant_id: String) -> bool:
	var index := _seat_for_participant_id(participant_id)
	var players := _state_array("_players")
	if index < 0 or index >= players.size() or not (players[index] is Dictionary):
		return false
	return bool((players[index] as Dictionary).get("ready", false))


func _room_can_change_seat_gate() -> Dictionary:
	var value = _call_if_present("_room_can_change_seat")
	return value if value is Dictionary else {"ok": false, "message": "不能切换座位"}


func _room_can_add_bot_gate() -> Dictionary:
	var value = _call_if_present("_room_can_add_bot")
	return value if value is Dictionary else {"ok": false, "message": "不能添加机器人"}


func _player_title_text(index: int) -> String:
	var value = _call_if_present("_player_title", [index])
	return String(value) if value != null else "%d号" % [index + 1]


func _bool_call(method_name: String, args: Array = []) -> bool:
	var value = _call_if_present(method_name, args)
	return bool(value) if value != null else false
