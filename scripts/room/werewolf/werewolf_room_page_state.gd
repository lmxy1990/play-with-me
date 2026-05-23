extends "res://scripts/pages/base/page_bot_profile_ui_base.gd"

const WerewolfRoomModuleScript := preload("res://scripts/room/werewolf/werewolf_room_module.gd")
const RoomRuntimeScript := preload("res://scripts/room/room_runtime.gd")
const RoomPlayerFactoryScript := preload("res://scripts/player/player_factory.gd")
const PlayerPresentationAckControllerScript := preload("res://scripts/player/player_presentation_ack_controller.gd")
const PlayerPresentationAckParticipantResolverScript := preload("res://scripts/player/player_presentation_ack_participant_resolver.gd")
const PlayerPresentationAckRuntimeScript := preload("res://scripts/player/player_presentation_ack_runtime.gd")
const PlayerTaskChannelScript := preload("res://scripts/player/player_task_channel.gd")
const TableSurfaceScript := preload("res://scripts/room/werewolf/table_surface.gd")
const SeatCardScript := preload("res://scripts/room/werewolf/seat_card.gd")
const EffectLayerScript := preload("res://scripts/room/werewolf/effect_layer.gd")
const WerewolfRoleCatalogScript := preload("res://scripts/room/werewolf/werewolf_role_catalog.gd")

var _phase_night := false
var _seat_cards: Array = []
var _selected_player_index := 0
var _local_player_index := 0
var _bot_serial := 1
var _pending_action := ""
var _pending_action_icon := ""
var _pending_actor_index := -1
var _speech_prompt_index := -1
var _system_message := "等待主持人"
var _werewolf := {}
var _history := []
var _device_task_waiting_for_result := false
var _engine = WerewolfRoomModuleScript.new()
var _room_runtime = RoomRuntimeScript.new()
var _room_player_factory = RoomPlayerFactoryScript.new()
var _presentation_ack_controller = PlayerPresentationAckControllerScript.new()
var _presentation_ack_participant_resolver = PlayerPresentationAckParticipantResolverScript.new()
var _presentation_ack_runtime = PlayerPresentationAckRuntimeScript.new()
var _device_task_channel = PlayerTaskChannelScript.new()
var _role_catalog = WerewolfRoleCatalogScript.new()
var _current_device_task_id := ""
var _current_device_task_frame := {}

var _players := [
	{"name": "1号位", "role": "待加入", "avatar": "", "state": "可落座", "motion": SeatMotion.IDLE, "alive": true, "ready": false, "owner": ""},
	{"name": "2号位", "role": "待加入", "avatar": "", "state": "可落座", "motion": SeatMotion.IDLE, "alive": true, "ready": false, "owner": ""},
	{"name": "3号位", "role": "待加入", "avatar": "", "state": "可落座", "motion": SeatMotion.IDLE, "alive": true, "ready": false, "owner": ""},
	{"name": "4号位", "role": "待加入", "avatar": "", "state": "可落座", "motion": SeatMotion.IDLE, "alive": true, "ready": false, "owner": ""},
	{"name": "5号位", "role": "待加入", "avatar": "", "state": "可落座", "motion": SeatMotion.IDLE, "alive": true, "ready": false, "owner": ""},
	{"name": "6号位", "role": "待加入", "avatar": "", "state": "可落座", "motion": SeatMotion.IDLE, "alive": true, "ready": false, "owner": ""},
]


func _is_game_started() -> bool:
	return _room_runtime.is_game_started(_werewolf)


func _is_post_game_phase() -> bool:
	return String(_werewolf.get("phase", "")) in ["post_game_summary", "mvp_vote", "completed"]


func _is_werewolf_paused() -> bool:
	return bool(_werewolf.get("paused", false))


func _set_werewolf_paused(paused: bool, reason: String = "", participant_id: String = "") -> void:
	if _werewolf.is_empty():
		_werewolf = _engine.default_state()
	_werewolf["paused"] = paused
	if paused:
		_werewolf["pause_reason"] = reason
		_werewolf["pause_participant_id"] = participant_id
		_werewolf["paused_at"] = Time.get_unix_time_from_system()
	else:
		_werewolf.erase("pause_reason")
		_werewolf.erase("pause_participant_id")
		_werewolf.erase("paused_at")
	if has_method("_on_werewolf_pause_changed"):
		call("_on_werewolf_pause_changed", paused)


func _has_offline_human_players() -> bool:
	for player_value in _players:
		if not (player_value is Dictionary):
			continue
		var player: Dictionary = player_value
		var owner := String(player.get("owner", ""))
		if owner != "self" and owner != "human":
			continue
		if String(player.get("state", "")).strip_edges() == "离线":
			return true
	return false


func _default_werewolf_state() -> Dictionary:
	return _engine.default_state()


func _room_can_change_seat() -> Dictionary:
	return _room_runtime.can_change_seat(_werewolf)


func _room_can_add_bot() -> Dictionary:
	return _room_runtime.can_add_bot(_werewolf)


func _phase_status_text() -> String:
	if _werewolf.is_empty():
		return "等待开局"
	if _is_werewolf_paused():
		return "游戏暂停"
	var day := int(_werewolf.get("day", 0))
	var label := _engine.phase_label(_werewolf)
	if day > 0:
		var day_kind := "夜" if _engine.is_night_phase(_werewolf) else "天"
		return "第%d%s · %s" % [day, day_kind, label]
	return label


func _interaction_status_text() -> String:
	if _is_werewolf_paused():
		var reason := String(_werewolf.get("pause_reason", "")).strip_edges()
		return "游戏暂停：%s" % (reason if reason != "" else "等待真人玩家重连")
	if _pending_action != "":
		return "%s · %s：%s" % [_phase_status_text(), _player_title(_pending_actor_index), _pending_action]
	if _speech_prompt_index >= 0:
		return "%s · %s 发言" % [_phase_status_text(), _player_title(_speech_prompt_index)]
	if _is_game_started():
		return "%s · 等待主持人推进" % _phase_status_text()
	return "真人准备后房主开始"


func _human_count() -> int:
	return _room_runtime.human_count(_players)


func _bot_count() -> int:
	return _room_runtime.bot_count(_players)


func _occupied_indices() -> Array:
	return _room_runtime.occupied_indices(_players)


func _player_title(index: int) -> String:
	if index >= 0 and index < _players.size():
		return "%d号 %s" % [index + 1, String(_players[index].get("name", ""))]
	return "主持人"


func _current_viewer_participant_id() -> String:
	var participant_id := _current_network_participant_id()
	if participant_id != "":
		return participant_id
	if _local_player_index >= 0 and _local_player_index < _players.size() and _players[_local_player_index] is Dictionary:
		var player: Dictionary = _players[_local_player_index]
		var player_participant_id := String(player.get("participant_id", player.get("participantId", ""))).strip_edges()
		if player_participant_id != "":
			return player_participant_id
		if String(player.get("owner", "")) == "self":
			return "host"
	return participant_id


func _visible_history_for_current_participant() -> Array:
	var result := []
	for item in _history:
		if item is Dictionary and _history_item_visible_to_current(item as Dictionary):
			result.append((item as Dictionary).duplicate(true))
	return result


func _history_item_visible_to_current(item: Dictionary) -> bool:
	return _history_item_visible_to_participant(item, _current_viewer_participant_id())


func _seat_state_visible_to_current(index: int) -> bool:
	if index < 0 or index >= _players.size() or not (_players[index] is Dictionary):
		return true
	if not _engine.is_night_phase(_werewolf) or _is_post_game_phase():
		return true
	if _is_observer_participant(_current_viewer_participant_id()):
		return true
	if index == _local_player_index:
		return true
	var phase := String(_werewolf.get("phase", ""))
	if phase == "wolf_chat":
		return _current_viewer_can_see_wolf_private()
	var action: Dictionary = _werewolf.get("current_action", {}) if _werewolf.get("current_action", {}) is Dictionary else {}
	if int(action.get("actor_index", -1)) == index:
		var action_key := String(action.get("key", "")).strip_edges()
		if action_key == "wolf_kill":
			return _current_viewer_can_see_wolf_private()
		if action_key in ["witch_act", "witch_save", "witch_poison", "witch_skip", "seer_check", "guard_protect"]:
			return false
	return true


func _current_viewer_can_see_wolf_private() -> bool:
	if _local_player_index < 0 or _local_player_index >= _players.size() or not (_players[_local_player_index] is Dictionary):
		return false
	return _role_catalog.can_join_wolf_chat(String((_players[_local_player_index] as Dictionary).get("role_key", "")))


func _history_item_visible_to_participant(item: Dictionary, participant_id: String) -> bool:
	var visibility := String(item.get("visibility", "public")).strip_edges()
	if visibility == "" or visibility == "public":
		return true
	if _is_observer_participant(participant_id):
		return true
	var viewer_index := _seat_for_participant_id(participant_id)
	if viewer_index < 0:
		return false
	var visible_indices := _history_visible_to_indices(item)
	if visible_indices.has(viewer_index):
		return true
	var actor_index := _history_item_speaker_index(item)
	match visibility:
		"private":
			return actor_index == viewer_index
		"wolf":
			return _role_catalog.can_join_wolf_chat(_history_player_role_key(viewer_index))
		"observer":
			return false
		_:
			return true


func _history_visible_to_indices(item: Dictionary) -> Array:
	var result := []
	var value = item.get("visible_to_indices", item.get("visibleToIndices", []))
	if value is Array:
		for entry in value as Array:
			var index := int(entry)
			if index >= 0 and not result.has(index):
				result.append(index)
	return result


func _history_item_speaker_index(item: Dictionary) -> int:
	var explicit := int(item.get("speaker_index", item.get("actor_index", -1)))
	if explicit >= 0:
		return explicit
	return _history_speaker_index_from_text(String(item.get("speaker", "")))


func _history_speaker_index_from_text(speaker: String) -> int:
	var marker := speaker.find("号")
	if marker <= 0:
		return -1
	var seat_text := speaker.substr(0, marker).strip_edges()
	if not seat_text.is_valid_int():
		return -1
	var index := int(seat_text.to_int()) - 1
	return index if index >= 0 and index < _players.size() else -1


func _history_player_role_key(index: int) -> String:
	if index < 0 or index >= _players.size() or not (_players[index] is Dictionary):
		return ""
	return String((_players[index] as Dictionary).get("role_key", ""))


func _history_item_display_name(item: Dictionary) -> String:
	var index := _history_item_speaker_index(item)
	if index >= 0 and index < _players.size() and _players[index] is Dictionary:
		var name := String((_players[index] as Dictionary).get("name", "")).strip_edges()
		return name if name != "" else "%d号位" % [index + 1]
	var speaker := String(item.get("speaker", "主持人")).strip_edges()
	if speaker in ["", "系统", "房间"]:
		return "主持人"
	return speaker


func _history_item_seat_text(item: Dictionary) -> String:
	var index := _history_item_speaker_index(item)
	return "%d号" % [index + 1] if index >= 0 else ""


func _history_item_avatar_path(item: Dictionary) -> String:
	var index := _history_item_speaker_index(item)
	if index >= 0 and index < _players.size() and _players[index] is Dictionary:
		return _avatar_for_role_visibility(_players[index] as Dictionary, _role_visible_for_current_view(index))
	var avatar := String(item.get("avatar", "")).strip_edges()
	if avatar != "":
		return avatar
	return _werewolf_action_path("speech")


func _history_item_tts_enabled(item: Dictionary) -> bool:
	var index := _history_item_speaker_index(item)
	if index < 0:
		return true
	return _player_tts_enabled(index)


func _player_tts_enabled(index: int) -> bool:
	return _player_speech_output.speaker_tts_enabled(index, _players, _player_tts_profile_resolver())


func _set_player_tts_enabled(index: int, enabled: bool) -> void:
	_player_speech_output.set_speaker_tts_enabled(index, enabled, _players, _player_tts_profile_resolver())


func _player_tts_key(index: int) -> String:
	return _player_speech_output.speaker_tts_key(index, _players, _player_tts_profile_resolver())


func _player_tts_profile_resolver() -> Callable:
	if has_method("_local_private_bot_profile_id_for_seat"):
		return Callable(self, "_local_private_bot_profile_id_for_seat")
	return Callable()


func _clear_device_task_state() -> void:
	_device_task_channel.clear()
	_current_device_task_id = ""
	_current_device_task_frame.clear()
	_sync_device_task_gate_state()


func _remove_device_task(task_id: String) -> void:
	_device_task_channel.remove_task(task_id)
	_sync_device_task_gate_state()


func _sync_device_task_gate_state() -> bool:
	_device_task_waiting_for_result = _device_task_channel.blocks_auto_advance()
	return _device_task_waiting_for_result


func _device_task_blocks_auto_advance() -> bool:
	return _sync_device_task_gate_state()


func _device_task_controller_participant_for_actor(actor_index: int) -> String:
	if actor_index < 0 or actor_index >= _players.size() or not (_players[actor_index] is Dictionary):
		return ""
	var player: Dictionary = _players[actor_index]
	return _player_controller_participant_id(player)


func _player_controller_participant_id(player: Dictionary) -> String:
	var controller := String(player.get("controller_participant_id", player.get("controllerParticipantId", ""))).strip_edges()
	if controller != "":
		return controller
	var participant_id := String(player.get("participant_id", player.get("participantId", ""))).strip_edges()
	if participant_id != "":
		return participant_id
	return "host" if String(player.get("owner", "")).strip_edges() == "self" else ""


func _device_task_peer_id_for_participant(participant_id: String) -> int:
	var clean := participant_id.strip_edges()
	if clean == "" or clean == "host":
		return 0
	if _room_network_session == null or not _room_network_session.has_method("peer_ids") or not _room_network_session.has_method("peer_participant_id"):
		return -1
	var peer_ids: Array = _room_network_session.call("peer_ids")
	for peer_id_value in peer_ids:
		var peer_id := int(peer_id_value)
		if String(_room_network_session.call("peer_participant_id", peer_id)).strip_edges() == clean:
			return peer_id
	return -1


func _device_task_connected_participants() -> Array:
	var result := [_current_network_participant_id()]
	if _room_network_session != null and _room_network_session.has_method("is_host") and bool(_room_network_session.call("is_host")) and _room_network_session.has_method("peer_ids") and _room_network_session.has_method("peer_participant_id"):
		var peer_ids: Array = _room_network_session.call("peer_ids")
		for peer_id_value in peer_ids:
			var peer_id := int(peer_id_value)
			var participant_id := String(_room_network_session.call("peer_participant_id", peer_id)).strip_edges()
			if participant_id != "" and not result.has(participant_id):
				result.append(participant_id)
	return result


func _device_task_turn_key(task_type: String, actor_index: int) -> String:
	var action: Dictionary = _werewolf.get("current_action", {}) if _werewolf.get("current_action", {}) is Dictionary else {}
	return "%s|day=%d|phase=%s|actor=%d|action=%s|speech=%d|history=%d" % [
		task_type.strip_edges(),
		int(_werewolf.get("day", 0)),
		String(_werewolf.get("phase", "")),
		actor_index,
		String(action.get("key", "")),
		int(_werewolf.get("speech_index", -1)),
		_history.size(),
	]


func _device_task_frame_for_actor(actor_index: int, controller_participant_id: String) -> Dictionary:
	var controller := controller_participant_id.strip_edges()
	var controller_index := -1
	if has_method("_seat_for_participant_id"):
		controller_index = _seat_for_participant_id(controller)
	var controller_is_observer := false
	if has_method("_is_observer_participant"):
		controller_is_observer = _is_observer_participant(controller)
	var viewer_index := controller_index
	if actor_index >= 0:
		viewer_index = actor_index
	var viewer_is_observer := controller_is_observer and actor_index < 0
	var action := {}
	var action_value = _werewolf.get("current_action", {})
	if action_value is Dictionary:
		action = (action_value as Dictionary).duplicate(true)
	var room_id := String(_active_room().get("id", ""))
	if _app_state != null:
		room_id = String(_app_state.active_room_id)
	var actor_seat_number := -1
	if actor_index >= 0:
		actor_seat_number = actor_index + 1
	var viewer_seat_number := -1
	if viewer_index >= 0:
		viewer_seat_number = viewer_index + 1
	var current_action := {}
	if not action.is_empty() and int(action.get("actor_index", -1)) == actor_index:
		current_action = action.duplicate(true)
	var speech_index := int(_werewolf.get("speech_index", -1))
	var speech_seat_number := -1
	if speech_index >= 0:
		speech_seat_number = speech_index + 1
	return {
		"api": "werewolf_device_task_frame.v1",
		"roomId": room_id,
		"day": int(_werewolf.get("day", 0)),
		"phase": String(_werewolf.get("phase", "")),
		"phaseLabel": _engine.phase_label(_werewolf),
		"mapId": String(_werewolf.get("map_id", "")),
		"mapName": String(_werewolf.get("map_name", "")),
		"actorIndex": actor_index,
		"actorSeatNumber": actor_seat_number,
		"actor": _device_task_actor_frame(actor_index, viewer_index, viewer_is_observer),
		"controller": _device_task_controller_frame(controller, controller_index, controller_is_observer),
		"viewerSeatNumber": viewer_seat_number,
		"viewerIsObserver": viewer_is_observer,
		"players": _device_task_players_for_viewer(viewer_index, viewer_is_observer),
		"history": _device_task_history_for_viewer(viewer_index, viewer_is_observer),
		"timeline": _device_task_timeline_for_viewer(viewer_index, viewer_is_observer),
		"currentAction": current_action,
		"speechIndex": speech_index,
		"speechSeatNumber": speech_seat_number,
	}


func _device_task_actor_frame(actor_index: int, viewer_index: int, viewer_is_observer: bool) -> Dictionary:
	if actor_index < 0 or actor_index >= _players.size() or not (_players[actor_index] is Dictionary):
		return {}
	var player: Dictionary = _players[actor_index]
	return _device_task_player_row(actor_index, player, viewer_index, viewer_is_observer)


func _device_task_controller_frame(controller_participant_id: String, controller_index: int, is_observer: bool) -> Dictionary:
	var controller := controller_participant_id.strip_edges()
	var display_name := ""
	if controller_index >= 0 and controller_index < _players.size() and _players[controller_index] is Dictionary:
		display_name = String((_players[controller_index] as Dictionary).get("name", ""))
	elif is_observer:
		var room := _active_room()
		if has_method("_observer_for_participant"):
			var observer_value = call("_observer_for_participant", room, controller)
			if observer_value is Dictionary:
				display_name = String((observer_value as Dictionary).get("displayName", (observer_value as Dictionary).get("name", "")))
	var seat_number := -1
	if controller_index >= 0:
		seat_number = controller_index + 1
	return {
		"participantId": controller,
		"seatIndex": controller_index,
		"seatNumber": seat_number,
		"isObserver": is_observer,
		"displayName": display_name,
	}


func _device_task_players_for_viewer(viewer_index: int, viewer_is_observer: bool) -> Array:
	var result := []
	for i in range(_players.size()):
		if not (_players[i] is Dictionary):
			result.append({})
			continue
		result.append(_device_task_player_row(i, _players[i] as Dictionary, viewer_index, viewer_is_observer))
	return result


func _device_task_player_row(index: int, player: Dictionary, viewer_index: int, viewer_is_observer: bool) -> Dictionary:
	var owner := String(player.get("owner", "")).strip_edges()
	var occupied := owner != ""
	var role_visible := _device_task_role_visible_for_viewer(index, viewer_index, viewer_is_observer)
	var role_text := "未知"
	if not occupied:
		role_text = "空位"
	elif role_visible:
		role_text = String(player.get("role", "未知"))
	var role_key := ""
	var role_title := ""
	var role_avatar := ""
	if role_visible:
		role_key = String(player.get("role_key", ""))
		role_title = _role_title_for_player(player)
		role_avatar = _role_avatar_for_player(player)
	return {
		"seatNumber": index + 1,
		"displayName": String(player.get("name", "%d号位" % [index + 1])),
		"alive": bool(player.get("alive", true)),
		"state": String(player.get("state", "")),
		"owner": owner,
		"avatar": _avatar_for_role_visibility(player, role_visible),
		"baseAvatar": String(player.get("base_avatar", player.get("avatar", ""))),
		"roleVisible": role_visible,
		"role": role_text,
		"roleKey": role_key,
		"roleTitle": role_title,
		"roleAvatar": role_avatar,
		"participantId": String(player.get("participant_id", "")),
		"controllerParticipantId": String(player.get("controller_participant_id", "")),
	}


func _device_task_role_visible_for_viewer(target_index: int, viewer_index: int, viewer_is_observer: bool) -> bool:
	if target_index < 0 or target_index >= _players.size() or not (_players[target_index] is Dictionary):
		return false
	var player: Dictionary = _players[target_index]
	if String(player.get("owner", "")).strip_edges() == "":
		return true
	if not _is_game_started() or _is_post_game_phase():
		return true
	if viewer_is_observer:
		return true
	if target_index == viewer_index:
		return true
	if _role_publicly_revealed_for_player(player):
		return true
	if viewer_index >= 0 and viewer_index < _players.size() and _players[viewer_index] is Dictionary:
		var viewer_role := String((_players[viewer_index] as Dictionary).get("role_key", "")).strip_edges()
		var target_role := String(player.get("role_key", "")).strip_edges()
		if _role_catalog.can_see_wolf_teammates(viewer_role) and _role_catalog.is_wolf_team(target_role) and _role_catalog.visible_to_wolf_teammates(target_role):
			return true
	return false


func _device_task_history_for_viewer(viewer_index: int, viewer_is_observer: bool) -> Array:
	var result := []
	for item_value in _history:
		if item_value is Dictionary and _device_task_history_visible_to_viewer(item_value as Dictionary, viewer_index, viewer_is_observer):
			result.append((item_value as Dictionary).duplicate(true))
	return result


func _device_task_timeline_for_viewer(viewer_index: int, viewer_is_observer: bool) -> Array:
	var result := []
	for item_value in _history:
		if not (item_value is Dictionary):
			continue
		var item: Dictionary = item_value
		if not _device_task_history_visible_to_viewer(item, viewer_index, viewer_is_observer):
			continue
		var line := _device_task_history_line(item)
		if line != "":
			result.append(line)
	return result


func _device_task_history_visible_to_viewer(item: Dictionary, viewer_index: int, viewer_is_observer: bool) -> bool:
	var visibility := String(item.get("visibility", "public")).strip_edges()
	if visibility == "" or visibility == "public":
		return true
	if viewer_is_observer:
		return true
	if viewer_index < 0:
		return false
	var visible_indices := _history_visible_to_indices(item)
	if visible_indices.has(viewer_index):
		return true
	var actor_index := _history_item_speaker_index(item)
	match visibility:
		"private":
			return actor_index == viewer_index
		"wolf":
			return _role_catalog.can_join_wolf_chat(_history_player_role_key(viewer_index))
		"observer":
			return false
		_:
			return true


func _device_task_history_line(item: Dictionary) -> String:
	var text := String(item.get("display_text", item.get("text", ""))).strip_edges()
	if text == "":
		return ""
	var seat := _history_item_seat_text(item)
	var name := _history_item_display_name(item)
	var speaker := String(item.get("speaker", "主持人")).strip_edges()
	var title := seat
	if title == "":
		title = name if name != "" else speaker
	return "%s:%s" % [title, text]


func _device_task_pending_for_turn(task_type: String, actor_index: int) -> bool:
	var turn_key := _device_task_turn_key(task_type, actor_index)
	var snapshot: Dictionary = _device_task_channel.snapshot()
	for task_value in snapshot.get("tasks", []):
		if not (task_value is Dictionary):
			continue
		var task: Dictionary = task_value
		if String(task.get("type", task.get("taskType", ""))) != task_type:
			continue
		if int(task.get("actor_index", task.get("actorIndex", -1))) != actor_index:
			continue
		var payload: Dictionary = task.get("payload", {}) if task.get("payload", {}) is Dictionary else {}
		if String(payload.get("turn_key", payload.get("turnKey", ""))) == turn_key:
			return true
	return false


func _create_device_task_for_actor(task_type: String, actor_index: int, payload: Dictionary = {}) -> Dictionary:
	var controller := _device_task_controller_participant_for_actor(actor_index)
	if controller == "":
		print("[WerewolfDeviceTask][error] create failed type=%s actor=%d reason=no_controller" % [task_type, actor_index])
		return {}
	var task_payload := payload.duplicate(true)
	_sanitize_device_task_payload(task_payload)
	var actor_participant_id := ""
	var actor_name := ""
	var actor_role := ""
	var actor_role_key := ""
	if actor_index >= 0 and actor_index < _players.size() and _players[actor_index] is Dictionary:
		var player: Dictionary = _players[actor_index]
		actor_participant_id = String(player.get("participant_id", "")).strip_edges()
		actor_name = String(player.get("name", ""))
		var viewer_is_observer := false
		var viewer_index := actor_index
		if _device_task_role_visible_for_viewer(actor_index, viewer_index, viewer_is_observer):
			actor_role = String(player.get("role", ""))
			actor_role_key = String(player.get("role_key", ""))
		else:
			actor_role = "未知"
	task_payload["actor"] = {
		"seatNumber": actor_index + 1,
		"displayName": actor_name,
		"role": actor_role,
		"roleKey": actor_role_key,
		"kind": "player",
		"participantId": actor_participant_id,
	}
	task_payload["turn_key"] = _device_task_turn_key(task_type, actor_index)
	task_payload["turnKey"] = task_payload["turn_key"]
	task_payload["roomId"] = String(_app_state.active_room_id) if _app_state != null else String(_active_room().get("id", ""))
	task_payload["day"] = int(_werewolf.get("day", 0))
	task_payload["phase"] = String(_werewolf.get("phase", ""))
	task_payload["phaseLabel"] = _engine.phase_label(_werewolf)
	task_payload["hostParticipantId"] = _current_network_participant_id()
	task_payload["controllerParticipantId"] = controller
	var task_frame := _device_task_frame_for_actor(actor_index, controller)
	task_payload["playerFrame"] = task_frame
	task_payload["taskFrame"] = task_frame
	var frame_players_count := 0
	var frame_players_value = task_frame.get("players", [])
	if frame_players_value is Array:
		frame_players_count = (frame_players_value as Array).size()
	var frame_history_count := 0
	var frame_history_value = task_frame.get("history", [])
	if frame_history_value is Array:
		frame_history_count = (frame_history_value as Array).size()
	var task := _device_task_channel.create_task(task_type, actor_index, controller, task_payload)
	if task.is_empty():
		print("[WerewolfDeviceTask][error] create failed type=%s actor=%d controller=%s" % [task_type, actor_index, controller])
		return {}
	if OS.is_debug_build():
		print("[WerewolfDeviceTask][debug] created id=%s type=%s actor=%s controller=%s turn=%s frame_players=%d frame_history=%d" % [
			String(task.get("id", "")),
			task_type,
			_player_title(actor_index),
			controller,
			String(task_payload.get("turn_key", "")),
			frame_players_count,
			frame_history_count,
		])
	return task


func _sanitize_device_task_payload(payload: Dictionary) -> void:
	_sanitize_device_task_payload_in_place(payload)


func _device_task_private_payload_fields() -> Array:
	return ["api_key", "apiKey", "endpoint", "provider", "model", "modelName", "model_name", "modelProfile", "model_profile", "modelConfig", "model_config", "messages", "requestOptions", "request_options", "response_schema", "responseSchema", "schema", "formt_adapter", "formtAdapter", "format_adapter", "formatAdapter", "output_adapter", "outputAdapter", "reason_adapter", "reasonAdapter", "reasoning_adapter", "reasoningAdapter", "temperature", "max_output", "maxOutput", "max_output_tokens", "maxOutputTokens", "max_context", "maxContext"]


func _device_task_private_payload_key(key: String, lower_key: String = "") -> bool:
	var lower := lower_key if lower_key != "" else key.to_lower()
	return _device_task_private_payload_fields().has(key) or ["api_key", "apikey", "endpoint", "provider", "model", "modelname", "model_name", "modelprofile", "model_profile", "modelconfig", "model_config", "messages", "requestoptions", "request_options", "response_schema", "responseschema", "schema", "formt_adapter", "formtadapter", "format_adapter", "formatadapter", "output_adapter", "outputadapter", "reason_adapter", "reasonadapter", "reasoning_adapter", "reasoningadapter", "temperature", "max_output", "maxoutput", "max_output_tokens", "maxoutputtokens", "max_context", "maxcontext"].has(lower)


func _sanitize_device_task_payload_in_place(value) -> void:
	if value is Dictionary:
		var dict: Dictionary = value
		for key_value in dict.keys():
			var key := String(key_value)
			if _device_task_private_payload_key(key):
				dict.erase(key_value)
			else:
				_sanitize_device_task_payload_in_place(dict.get(key_value))
	elif value is Array:
		for item in value as Array:
			_sanitize_device_task_payload_in_place(item)


func _route_device_task(task: Dictionary) -> bool:
	if task.is_empty():
		return false
	var controller := String(task.get("controller_participant_id", task.get("controllerParticipantId", ""))).strip_edges()
	var task_id := String(task.get("id", task.get("task_id", ""))).strip_edges()
	var actor_index := int(task.get("actor_index", task.get("actorIndex", -1)))
	if controller == "" or task_id == "":
		return false
	if controller == _current_network_participant_id():
		_device_task_channel.mark_dispatched(task_id, 0)
		_sync_device_task_gate_state()
		_current_device_task_id = task_id
		if OS.is_debug_build():
			print("[WerewolfDeviceTask][debug] local route id=%s type=%s actor=%s controller=%s waiting=true" % [
				task_id,
				String(task.get("type", task.get("taskType", ""))),
				_player_title(actor_index) if actor_index >= 0 and actor_index < _players.size() else str(actor_index),
				controller,
			])
		if has_method("_on_device_task_received"):
			call("_on_device_task_received", task)
		return true
	var peer_id := _device_task_peer_id_for_participant(controller)
	if peer_id <= 0:
		_device_task_channel.mark_route_failed(task_id, "device_offline")
		_remove_device_task(task_id)
		print("[WerewolfDeviceTask][error] route failed id=%s controller=%s reason=device_offline" % [task_id, controller])
		return false
	if _room_network_session == null or not _room_network_session.has_method("send_to_peer"):
		_device_task_channel.mark_route_failed(task_id, "no_network_session")
		_remove_device_task(task_id)
		print("[WerewolfDeviceTask][error] route failed id=%s controller=%s reason=no_network_session" % [task_id, controller])
		return false
	var sent := bool(_room_network_session.call("send_to_peer", peer_id, "device_task", task))
	if sent:
		_device_task_channel.mark_dispatched(task_id, peer_id)
	else:
		_device_task_channel.mark_route_failed(task_id, "send_failed")
		_remove_device_task(task_id)
	_sync_device_task_gate_state()
	if OS.is_debug_build():
		print("[WerewolfDeviceTask][debug] routed id=%s type=%s actor=%s controller=%s peer=%d sent=%s waiting=%s" % [
			task_id,
			String(task.get("type", task.get("taskType", ""))),
			_player_title(actor_index) if actor_index >= 0 and actor_index < _players.size() else str(actor_index),
			controller,
			peer_id,
			str(sent),
			str(_device_task_waiting_for_result),
		])
	return sent


func _send_device_task_result(task_id: String, result: Dictionary) -> bool:
	var clean_task_id := task_id.strip_edges()
	if clean_task_id == "":
		return false
	var payload := result.duplicate(true)
	payload["taskId"] = clean_task_id
	payload["task_id"] = clean_task_id
	payload["participantId"] = _current_network_participant_id()
	payload["participant_id"] = _current_network_participant_id()
	payload["roomId"] = String(_app_state.active_room_id) if _app_state != null else String(_active_room().get("id", ""))
	if _is_network_client():
		if _room_network_session == null or not _room_network_session.has_method("send_client"):
			print("[WerewolfDeviceTask][error] result send failed id=%s reason=no_client_session" % clean_task_id)
			return false
		var sent := bool(_room_network_session.call("send_client", "device_task_result", payload))
		if OS.is_debug_build():
			print("[WerewolfDeviceTask][debug] client result id=%s type=%s sent=%s ok=%s" % [
				clean_task_id,
				String(payload.get("taskType", payload.get("type", ""))),
				str(sent),
				str(payload.get("ok", "")),
			])
		return sent
	if has_method("_host_apply_device_task_result"):
		call("_host_apply_device_task_result", 0, payload)
		return true
	return false


func _device_task_snapshot() -> Dictionary:
	var snapshot := _device_task_channel.snapshot()
	snapshot = _sanitize_device_task_snapshot(snapshot)
	snapshot["currentLocalTaskId"] = _current_device_task_id
	snapshot["connectedParticipants"] = _device_task_connected_participants()
	snapshot["waitingForResult"] = _sync_device_task_gate_state()
	return snapshot


func _sanitize_device_task_snapshot(value):
	if value is Dictionary:
		var result := {}
		for key_value in (value as Dictionary).keys():
			var key := String(key_value)
			var lower_key := key.to_lower()
			var nested = (value as Dictionary).get(key_value)
			if _device_task_private_payload_key(key, lower_key):
				continue
			elif lower_key == "api_key" or lower_key == "apikey":
				result[key_value] = "set" if String(nested).strip_edges() != "" else "empty"
			else:
				result[key_value] = _sanitize_device_task_snapshot(nested)
		return result
	if value is Array:
		var result := []
		for item in (value as Array):
			result.append(_sanitize_device_task_snapshot(item))
		return result
	return value


func _ensure_history_presentation_id(item: Dictionary) -> String:
	return _presentation_ack_controller.ensure_history_presentation_id(item, _presentation_ack_room_id())


func _history_presentation_id(item: Dictionary) -> String:
	return _presentation_ack_controller.history_presentation_id(item)


func _presentation_ack_room_id() -> String:
	var room_id := "local_room"
	if _app_state != null:
		room_id = String(_app_state.active_room_id).strip_edges()
	if room_id == "":
		var room := _active_room()
		room_id = String(room.get("id", "local_room")).strip_edges()
	if room_id == "":
		room_id = "local_room"
	return room_id


func _register_presentation_ack_gate_for_history_item(item: Dictionary) -> void:
	if _is_network_client():
		return
	var plan := _presentation_ack_participant_plan_for_history_item(item)
	var expected: Array = plan.get("expected", [])
	var device_debug: Array = plan.get("devices", [])
	var result: Dictionary = _presentation_ack_controller.register_gate_for_history_item(item, _presentation_ack_room_id(), expected, device_debug, OS.is_debug_build())
	if OS.is_debug_build() and bool(result.get("created", false)):
		print("[WerewolfPresentationAck][debug] gate context id=%s session_peers=%s room_humans=%s room_observers=%s" % [
			String(result.get("id", "")),
			JSON.stringify(_presentation_ack_session_peer_debug()),
			JSON.stringify(_presentation_ack_room_human_debug()),
			JSON.stringify(_presentation_ack_room_observer_debug()),
		])


func _presentation_ack_participant_plan_for_history_item(item: Dictionary) -> Dictionary:
	return _presentation_ack_participant_resolver.build_plan(
		_current_network_participant_id(),
		_history_item_visible_to_current(item),
		_presentation_ack_peer_records_for_history_item(item)
	)


func _presentation_ack_expected_participants(item: Dictionary) -> Array:
	return _presentation_ack_participant_plan_for_history_item(item).get("expected", [])


func _presentation_ack_connected_device_debug(item: Dictionary) -> Array:
	return _presentation_ack_participant_plan_for_history_item(item).get("devices", [])


func _presentation_ack_peer_records_for_history_item(item: Dictionary) -> Array:
	var result := []
	if _room_network_session == null or not _room_network_session.has_method("is_host") or not bool(_room_network_session.call("is_host")):
		return result
	if not _room_network_session.has_method("peer_ids") or not _room_network_session.has_method("peer_participant_id"):
		return result
	var peer_ids: Array = _room_network_session.call("peer_ids")
	for peer_id_value in peer_ids:
		var peer_id := int(peer_id_value)
		var participant_id := String(_room_network_session.call("peer_participant_id", peer_id)).strip_edges()
		result.append({
			"peerId": peer_id,
			"participantId": participant_id,
			"visible": _presentation_ack_peer_can_see_item(item, participant_id),
		})
	return result


func _presentation_ack_session_peer_debug() -> Array:
	if _room_network_session == null:
		return []
	if _room_network_session.has_method("peer_debug_snapshot"):
		var snapshot_value = _room_network_session.call("peer_debug_snapshot")
		return snapshot_value if snapshot_value is Array else []
	if not _room_network_session.has_method("peer_ids"):
		return []
	var result := []
	var peer_ids: Array = _room_network_session.call("peer_ids")
	for peer_id_value in peer_ids:
		var peer_id := int(peer_id_value)
		var participant_id := ""
		if _room_network_session.has_method("peer_participant_id"):
			participant_id = String(_room_network_session.call("peer_participant_id", peer_id)).strip_edges()
		result.append({
			"peerId": peer_id,
			"participantId": participant_id,
		})
	return result


func _presentation_ack_room_human_debug() -> Array:
	var result := []
	for i in range(_players.size()):
		if not (_players[i] is Dictionary):
			continue
		var player: Dictionary = _players[i]
		var owner := String(player.get("owner", "")).strip_edges()
		if owner != "self" and owner != "human":
			continue
		result.append({
			"seatNumber": i + 1,
			"name": String(player.get("name", "")),
			"owner": owner,
			"participantId": String(player.get("participant_id", player.get("participantId", ""))),
			"state": String(player.get("state", "")),
			"deviceId": String(player.get("device_id", player.get("deviceId", ""))),
		})
	return result


func _presentation_ack_room_observer_debug() -> Array:
	var room := _active_room()
	var observers_value = room.get("observers", [])
	if observers_value is Array:
		var result := []
		for observer_value in observers_value as Array:
			if observer_value is Dictionary:
				var observer: Dictionary = observer_value
				result.append({
					"id": String(observer.get("id", "")),
					"displayName": String(observer.get("displayName", "")),
					"deviceId": String(observer.get("device_id", observer.get("deviceId", ""))),
				})
		return result
	return []


func _presentation_ack_id_for_peer(peer_id: int, participant_id: String) -> String:
	return _presentation_ack_participant_resolver.ack_id_for_peer(peer_id, participant_id)


func _presentation_ack_peer_can_see_item(item: Dictionary, participant_id: String) -> bool:
	var clean := participant_id.strip_edges()
	if clean != "":
		return _history_item_visible_to_participant(item, clean)
	var visibility := String(item.get("visibility", "public")).strip_edges()
	return visibility == "" or visibility == "public"


func _presentation_ack_gate_blocks_auto_advance() -> bool:
	return _presentation_ack_controller.gate_blocks_auto_advance()


func _presentation_ack_has_pending_id(presentation_id: String) -> bool:
	return _presentation_ack_controller.has_pending_presentation_id(presentation_id)


func _begin_local_presentation_ack(item: Dictionary) -> void:
	_presentation_ack_runtime.begin_local_ack(_presentation_ack_controller, item, _current_network_participant_id(), OS.is_debug_build())


func _local_presentation_ack_pending(presentation_id: String) -> bool:
	return _presentation_ack_controller.local_ack_pending(presentation_id)


func _schedule_local_presentation_ack_after_text_delay(item: Dictionary) -> void:
	_presentation_ack_runtime.schedule_local_text_ack(
		_presentation_ack_controller,
		item,
		_current_network_participant_id(),
		Callable(self, "_schedule_presentation_ack_timer"),
		Callable(self, "_complete_local_presentation_ack"),
		OS.is_debug_build()
	)


func _schedule_presentation_ack_timer(delay_seconds: float, timeout_callback: Callable) -> void:
	get_tree().create_timer(delay_seconds).timeout.connect(func():
		if timeout_callback.is_valid():
			timeout_callback.call()
	)


func _complete_local_presentation_ack(item: Dictionary, source: String = "presentation_done") -> void:
	_presentation_ack_runtime.complete_local_ack(
		_presentation_ack_controller,
		item,
		_current_network_participant_id(),
		_presentation_ack_room_id(),
		source,
		_is_network_client(),
		Callable(self, "_send_presentation_ack_to_host"),
		Callable(self, "_host_apply_presentation_ack"),
		OS.is_debug_build()
	)


func _send_presentation_ack_to_host(payload: Dictionary) -> bool:
	if _room_network_session != null and _room_network_session.has_method("send_client"):
		return bool(_room_network_session.call("send_client", "presentation_ack", payload))
	return false


func _host_apply_presentation_ack(peer_id: int, payload: Dictionary) -> void:
	if _is_network_client():
		return
	var session_participant_id := ""
	if peer_id > 0 and _room_network_session != null and _room_network_session.has_method("peer_participant_id"):
		session_participant_id = String(_room_network_session.call("peer_participant_id", peer_id)).strip_edges()
	_presentation_ack_runtime.apply_host_ack(
		_presentation_ack_controller,
		_presentation_ack_participant_resolver,
		peer_id,
		payload,
		session_participant_id,
		Callable(self, "_on_presentation_ack_gate_open"),
		OS.is_debug_build()
	)


func _host_drop_presentation_ack_participant(participant_id: String) -> void:
	_presentation_ack_runtime.drop_participant(_presentation_ack_controller, participant_id, Callable(self, "_on_presentation_ack_gate_open"), OS.is_debug_build())


func _presentation_ack_gate_is_open(gate: Dictionary) -> bool:
	return _presentation_ack_controller.gate_is_open(gate)


func _presentation_text_delay_seconds_for_item(item: Dictionary) -> float:
	return _presentation_ack_controller.text_delay_seconds_for_item(item)


func _presentation_text_delay_seconds_for_text(text: String) -> float:
	return _presentation_ack_controller.text_delay_seconds_for_text(text)


func _presentation_text_for_item(item: Dictionary) -> String:
	return _presentation_ack_controller.text_for_item(item)


func _clear_presentation_ack_state() -> void:
	_presentation_ack_runtime.clear(_presentation_ack_controller)
	_clear_device_task_state()


func _seat_card_data(index: int) -> Dictionary:
	var seat_data := {}
	if index >= 0 and index < _players.size() and _players[index] is Dictionary:
		seat_data = (_players[index] as Dictionary).duplicate(true)
	if not _seat_state_visible_to_current(index):
		seat_data["motion"] = SeatMotion.IDLE
		seat_data["speech_progress"] = 0.0
		if String(seat_data.get("state", "")) in ["思考中", "发言中", "狼队夜聊", "等待狼队行动"]:
			seat_data["state"] = "等待"
	seat_data["tts_enabled"] = _player_tts_enabled(index)
	var role_visible := _role_visible_for_current_view(index)
	seat_data["role_visible"] = role_visible
	seat_data["avatar"] = _avatar_for_role_visibility(seat_data, role_visible)
	seat_data["role_title"] = _role_title_for_player(seat_data) if role_visible else ""
	var show_vote_count := _should_show_vote_count() and String(seat_data.get("owner", "")).strip_edges() != ""
	seat_data["show_vote_count"] = show_vote_count
	seat_data["vote_count"] = _vote_count_for_seat(index) if show_vote_count else 0
	seat_data["avatar_badges"] = _avatar_badges_for_seat(index)
	return seat_data


func _avatar_for_current_view(index: int) -> String:
	if index < 0 or index >= _players.size() or not (_players[index] is Dictionary):
		return ""
	return _avatar_for_role_visibility(_players[index] as Dictionary, _role_visible_for_current_view(index))


func _avatar_for_role_visibility(player: Dictionary, role_visible: bool) -> String:
	if role_visible:
		var role_avatar := _role_avatar_for_player(player)
		if role_avatar != "":
			return role_avatar
	var base_avatar := String(player.get("base_avatar", "")).strip_edges()
	if base_avatar != "":
		return base_avatar
	return String(player.get("avatar", "")).strip_edges()


func _role_avatar_for_player(player: Dictionary) -> String:
	var avatar := String(player.get("role_avatar", "")).strip_edges()
	if avatar != "":
		return avatar
	var role_key := String(player.get("role_key", "")).strip_edges()
	if role_key != "":
		return _role_catalog.role_avatar(role_key)
	return ""


func _role_title_for_player(player: Dictionary) -> String:
	var title := String(player.get("role_title", "")).strip_edges()
	if title != "":
		return title
	var role_key := String(player.get("role_key", "")).strip_edges()
	if role_key != "":
		return _role_catalog.role_title(role_key)
	return ""


func _avatar_badges_for_seat(index: int) -> Array:
	var badges := []
	if index < 0 or index >= _players.size() or not (_players[index] is Dictionary):
		return badges
	var player: Dictionary = _players[index]
	if String(player.get("owner", "")).strip_edges() == "":
		return badges
	if index == int(_werewolf.get("sheriff_player_index", -1)):
		badges.append({
			"id": "sheriff",
			"icon": _werewolf_action_path("badge_sheriff"),
			"tooltip": "警徽",
		})
	if String(player.get("owner", "")).strip_edges() == "self":
		badges.append({
			"id": "self",
			"icon": _werewolf_action_path("badge_self"),
			"tooltip": "我的头像",
		})
	if index == _guarded_avatar_badge_index() and _can_view_guard_avatar_badge():
		badges.append({
			"id": "guard",
			"icon": _werewolf_action_path("badge_guard"),
			"tooltip": "守护",
		})
	var post_value = _werewolf.get("post_game", {})
	if post_value is Dictionary and index == int((post_value as Dictionary).get("mvp_index", -1)):
		badges.append({
			"id": "mvp",
			"icon": _werewolf_action_path("badge_mvp"),
			"tooltip": "MVP",
		})
	return badges


func _guarded_avatar_badge_index() -> int:
	var night_value = _werewolf.get("night", {})
	if night_value is Dictionary:
		return int((night_value as Dictionary).get("guarded_index", -1))
	return -1


func _can_view_guard_avatar_badge() -> bool:
	if _is_post_game_phase():
		return true
	var participant_id := _current_network_participant_id()
	if _is_observer_participant(participant_id):
		return true
	if not _is_network_client():
		return true
	if _local_player_index < 0 or _local_player_index >= _players.size() or not (_players[_local_player_index] is Dictionary):
		return false
	return String((_players[_local_player_index] as Dictionary).get("role_key", "")).strip_edges() == "guard"


func _should_show_vote_count() -> bool:
	return String(_werewolf.get("phase", "")) in ["sheriff_vote", "vote", "mvp_vote"]


func _vote_count_for_seat(index: int) -> int:
	if index < 0:
		return 0
	var counts := _current_vote_counts_for_display()
	return int(counts.get(str(index), 0))


func _current_vote_counts_for_display() -> Dictionary:
	var phase := String(_werewolf.get("phase", ""))
	var votes_value = _mvp_vote_source() if phase == "mvp_vote" else _werewolf.get("votes", {})
	if not (votes_value is Dictionary):
		return {}
	var use_sheriff_weight := phase == "vote"
	if _engine != null and _engine.has_method("vote_counts"):
		var counts_value = _engine.vote_counts(votes_value as Dictionary, _werewolf, use_sheriff_weight)
		if counts_value is Dictionary:
			return counts_value
	return _fallback_vote_counts_for_display(votes_value as Dictionary, use_sheriff_weight)


func _mvp_vote_source():
	var post_value = _werewolf.get("post_game", {})
	if post_value is Dictionary:
		return (post_value as Dictionary).get("mvp_votes", {})
	return {}


func _fallback_vote_counts_for_display(votes: Dictionary, use_sheriff_weight: bool) -> Dictionary:
	var counts := {}
	var sheriff_index := int(_werewolf.get("sheriff_player_index", -1))
	for voter_key in votes.keys():
		var target_index := int(votes[voter_key])
		var weight := 1
		if use_sheriff_weight and int(String(voter_key).to_int()) == sheriff_index:
			weight = 2
		counts[str(target_index)] = int(counts.get(str(target_index), 0)) + weight
	return counts


func _role_visible_for_current_view(index: int) -> bool:
	if index < 0 or index >= _players.size() or not (_players[index] is Dictionary):
		return false
	var player: Dictionary = _players[index]
	var owner := String(player.get("owner", ""))
	if owner == "":
		return true
	if not _is_game_started() or String(_werewolf.get("phase", "")) == "replay_round":
		return true
	if _is_observer_participant(_current_network_participant_id()):
		return true
	if index == _local_player_index:
		return true
	if _role_publicly_revealed_for_player(player):
		return true
	if _local_player_index >= 0 and _local_player_index < _players.size() and _players[_local_player_index] is Dictionary:
		var viewer_role := String((_players[_local_player_index] as Dictionary).get("role_key", "")).strip_edges()
		var target_role := String(player.get("role_key", "")).strip_edges()
		return _role_catalog.can_see_wolf_teammates(viewer_role) and _role_catalog.is_wolf_team(target_role) and _role_catalog.visible_to_wolf_teammates(target_role)
	return false


func _role_publicly_revealed_for_player(player: Dictionary) -> bool:
	return bool(player.get("idiot_revealed", false)) \
		or bool(player.get("public_role_visible", false))


func _first_auto_open_target_for_current_action() -> int:
	var target := int(_engine.suggested_target_for_current_action(_werewolf, _players))
	if target >= 0 and target < _players.size():
		return target
	var action: Dictionary = _werewolf.get("current_action", {}) if _werewolf.get("current_action", {}) is Dictionary else {}
	var action_key := String(action.get("key", "")).strip_edges()
	if action_key == "sheriff_badge_action":
		return _pending_actor_index
	return -1


func _is_local_private_ai_seat(index: int) -> bool:
	if index < 0 or index >= _players.size() or not (_players[index] is Dictionary):
		return false
	if not has_method("_local_private_bot_profile_id_for_seat"):
		return false
	return String(call("_local_private_bot_profile_id_for_seat", index)).strip_edges() != ""


func _refresh_all_seats() -> void:
	pass


func _refresh_room_controls() -> void:
	pass


func _refresh_center_panel() -> void:
	pass


func _bind_state() -> void:
	pass


func _enter_table() -> void:
	pass


func _commit_state() -> void:
	pass


func _clear_modal() -> void:
	pass


func _flash_effect(_kind: String) -> void:
	pass
