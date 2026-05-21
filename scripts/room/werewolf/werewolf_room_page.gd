extends "res://scripts/room/werewolf/werewolf_room_interaction_page_flow.gd"

const WEREWOLF_DEBUG_SNAPSHOT_PATH := "user://werewolf_room_debug_snapshot.json"
const WEREWOLF_DEBUG_SNAPSHOT_INTERVAL := 1.0

var _werewolf_debug_snapshot_elapsed := 0.0
var _werewolf_debug_last_error := ""
var _werewolf_final_perspective_text_debug_signature := ""


func _init() -> void:
	initial_route = "table"


func _process(delta: float) -> void:
	super._process(delta)
	_tick_werewolf_debug_snapshot(delta)


func _show_table() -> void:
	_mode = Mode.TABLE
	_bind_state()
	_ensure_local_room_slot()
	_sync_werewolf_view_state()
	_initialize_controlled_bot_model_profiles("show_table", true)
	_clear_scene()
	_set_backdrop(_table_background_path(), Color(0.020, 0.030, 0.060, 0.12) if _phase_night else Color(0.35, 0.24, 0.08, 0.045))

	var table := TableSurfaceScript.new()
	table.set_anchors_preset(Control.PRESET_FULL_RECT)
	table.mood = "night" if _phase_night else "day"
	table.clip_contents = false
	_scene_root.add_child(table)

	for i in range(_players.size()):
		var seat := SeatCardScript.new()
		seat.index = i
		seat.data = _seat_card_data(i)
		seat.texture_provider = _texture
		seat.dead_avatar_path = _werewolf_action_path("dead_avatar")
		seat.edit_icon_path = _werewolf_action_path("pencil")
		seat.voice_icon_path = _werewolf_action_path("speaker")
		seat.seat_pressed.connect(_on_seat_pressed)
		seat.name_edit_pressed.connect(_on_seat_name_edit_pressed)
		seat.voice_toggle_pressed.connect(_on_seat_voice_toggle_pressed)
		table.add_child(seat)
		_seat_cards.append(seat)

	var center := _center_table_panel()
	table.add_child(center)
	table.set_meta("center", center)
	table.set_meta("seats", _seat_cards)
	table.resized.connect(_layout_table.bind(table))
	call_deferred("_layout_table", table)

	_build_table_hud()
	_write_werewolf_debug_snapshot()


func _table_background_path() -> String:
	if _is_game_started() and _phase_night:
		return _night_background_path()
	var room := _active_room()
	if not room.is_empty():
		return _room_background_path(room)
	return _day_background_path()


func _tick_werewolf_debug_snapshot(delta: float) -> void:
	_werewolf_debug_snapshot_elapsed += delta
	if _werewolf_debug_snapshot_elapsed < WEREWOLF_DEBUG_SNAPSHOT_INTERVAL:
		return
	_werewolf_debug_snapshot_elapsed = 0.0
	if _app_state == null:
		return
	_write_werewolf_debug_snapshot()


func _write_werewolf_debug_snapshot() -> void:
	var snapshot := _debug_werewolf_room_snapshot()
	var file := FileAccess.open(WEREWOLF_DEBUG_SNAPSHOT_PATH, FileAccess.WRITE)
	if file == null:
		_werewolf_debug_last_error = "open_failed:%s" % FileAccess.get_open_error()
		return
	file.store_string(JSON.stringify(snapshot, "\t"))
	_werewolf_debug_last_error = ""


func _reset_werewolf_final_perspective_text_debug() -> void:
	_werewolf_final_perspective_text_debug_signature = ""


func _debug_werewolf_room_snapshot() -> Dictionary:
	var room := _active_room().duplicate(true)
	var room_id := String(room.get("id", _app_state.active_room_id if _app_state != null else "")).strip_edges()
	var observers := _room_observers()
	var views := _debug_room_views(room, observers)
	return {
		"ok": true,
		"api": "werewolf_room_debug_snapshot.v1",
		"snapshotPath": WEREWOLF_DEBUG_SNAPSHOT_PATH,
		"generatedAtUnix": Time.get_unix_time_from_system(),
		"activeRoomId": room_id,
		"debugLastError": _werewolf_debug_last_error,
		"local": {
			"participantId": _current_network_participant_id(),
			"localPlayerIndex": _local_player_index,
			"nickname": _local_nickname,
			"isNetworkClient": _is_network_client(),
			"isObserver": _is_observer_participant(_current_network_participant_id()),
			"mode": int(_mode),
		},
		"room": room,
		"counts": {
			"players": _players.size(),
			"occupiedPlayers": _occupied_indices().size(),
			"humans": _human_count(),
			"bots": _bot_count(),
			"observers": observers.size(),
			"history": _history.size(),
			"wolfPrivateHistory": _wolf_private_history.size(),
			"centerSpeechItems": _center_speech_items.size(),
		},
		"players": _debug_players_snapshot(),
		"observers": _debug_array_snapshot(observers),
		"werewolf": _werewolf.duplicate(true),
		"history": _debug_array_snapshot(_history),
		"wolfPrivateHistory": _debug_array_snapshot(_wolf_private_history),
		"views": views,
		"botDebug": _debug_bot_snapshot(),
		"ttsDebug": _debug_tts_snapshot(),
		"memoryDebug": _debug_memory_snapshot(room_id),
		"centerSpeech": {
			"items": _debug_array_snapshot(_center_speech_items),
			"pendingItems": _debug_array_snapshot(_center_speech_pending_items),
			"deferredHistoryItems": _debug_array_snapshot(_center_speech_deferred_history_items),
			"playbackFinished": _center_speech_playback_finished,
			"lastSignature": _center_speech_last_signature,
			"holdUntilMsec": _center_speech_hold_until_msec,
			"autoWaitUntilMsec": _center_speech_auto_wait_until_msec,
			"capacityChars": _center_speech_capacity_chars(),
		},
		"presentationAck": _debug_presentation_ack_snapshot(),
		"deviceTasks": _device_task_snapshot(),
		"runtime": {
			"pendingAction": _pending_action,
			"pendingActionIcon": _pending_action_icon,
			"pendingActorIndex": _pending_actor_index,
			"speechPromptIndex": _speech_prompt_index,
			"systemMessage": _system_message,
			"phaseNight": _phase_night,
			"botSerial": _bot_serial,
			"mutedTtsSpeakerKeys": _player_speech_output.muted_speaker_keys_snapshot(),
		},
	}


func _debug_presentation_ack_snapshot() -> Dictionary:
	return _presentation_ack_controller.debug_snapshot()


func _maybe_print_werewolf_final_perspective_text_debug() -> void:
	if String(_werewolf.get("phase", "")) != "completed":
		return
	var payload := _debug_werewolf_final_perspective_text_payload()
	var signature := String(payload.get("signature", ""))
	if signature != "" and signature == _werewolf_final_perspective_text_debug_signature:
		return
	_werewolf_final_perspective_text_debug_signature = signature
	var room_payload := payload.duplicate(true)
	var views: Array = room_payload.get("views", [])
	room_payload.erase("views")
	_print_werewolf_perspective_text_debug_chunks(
		"[WerewolfPerspectiveTextDebug][room] signature=%s views=%d" % [signature, views.size()],
		JSON.stringify(room_payload, "\t")
	)
	for view_value in views:
		if not (view_value is Dictionary):
			continue
		var view: Dictionary = view_value
		_print_werewolf_perspective_text_debug_chunks(
			"[WerewolfPerspectiveTextDebug][view] role=%s seat=%s name=%s" % [
				String(view.get("role", "")),
				str(view.get("seatNumber", "")),
				String(view.get("displayName", "")),
			],
			JSON.stringify(view, "\t")
		)


func _debug_werewolf_final_perspective_text_payload() -> Dictionary:
	var room := _active_room().duplicate(true)
	var room_id := String(room.get("id", _werewolf.get("room_id", _app_state.active_room_id if _app_state != null else ""))).strip_edges()
	var observers := _room_observers()
	var views := []
	views.append(_debug_final_host_text_view(room))
	for i in range(_players.size()):
		if not _debug_player_slot_occupied(i):
			continue
		views.append(_debug_final_player_text_view(i))
	for i in range(observers.size()):
		if observers[i] is Dictionary:
			views.append(_debug_final_observer_text_view(i, observers[i] as Dictionary))
	return {
		"ok": true,
		"api": "werewolf_final_perspective_text_debug.v1",
		"signature": _debug_final_perspective_text_signature(room_id),
		"generatedAtUnix": Time.get_unix_time_from_system(),
		"roomId": room_id,
		"phase": String(_werewolf.get("phase", "")),
		"phaseLabel": _engine.phase_label(_werewolf),
		"day": int(_werewolf.get("day", 0)),
		"winner": String(_werewolf.get("winner", "")),
		"mapId": String(_werewolf.get("map_id", "")),
		"mapName": String(_werewolf.get("map_name", "")),
		"counts": {
			"players": _players.size(),
			"occupiedPlayers": _occupied_indices().size(),
			"observers": observers.size(),
			"history": _history.size(),
			"wolfPrivateHistory": _wolf_private_history.size(),
			"centerSpeechItems": _center_speech_items.size(),
			"centerSpeechPendingItems": _center_speech_pending_items.size(),
			"centerSpeechDeferredHistoryItems": _center_speech_deferred_history_items.size(),
		},
		"currentPageRenderArrays": _debug_center_speech_render_arrays(),
		"views": views,
	}


func _debug_final_perspective_text_signature(room_id: String) -> String:
	var post := _debug_dict(_werewolf.get("post_game", {}))
	var last_text := ""
	if not _history.is_empty() and _history.back() is Dictionary:
		last_text = String((_history.back() as Dictionary).get("text", ""))
	return "%s|%s|%d|%d|%s|%s|%d|%s" % [
		room_id,
		String(_werewolf.get("phase", "")),
		_history.size(),
		_wolf_private_history.size(),
		String(_werewolf.get("winner", "")),
		String(post.get("stage", "")),
		int(post.get("mvp_index", -1)),
		last_text,
	]


func _debug_final_host_text_view(room: Dictionary) -> Dictionary:
	var can_view_wolf_private := true
	return {
		"key": "host",
		"kind": "host",
		"seatIndex": -1,
		"seatNumber": -1,
		"displayName": String(room.get("host_name", "host")),
		"roleKey": "host",
		"role": "主持人",
		"alive": true,
		"canViewWolfPrivate": can_view_wolf_private,
		"renderArrays": _debug_final_text_render_arrays(_history, can_view_wolf_private, -1),
		"modelPayload": {},
	}


func _debug_final_player_text_view(seat_index: int) -> Dictionary:
	var player: Dictionary = _players[seat_index]
	var visible_history := _debug_visible_history_for_seat(seat_index)
	var can_view_wolf_private := _debug_can_view_wolf_private_for_view("player", seat_index)
	var model_payload := _debug_final_model_payload_for_seat(seat_index)
	var render_arrays := _debug_final_text_render_arrays(visible_history, can_view_wolf_private, seat_index)
	render_arrays["modelTimelineText"] = _debug_string_array(model_payload.get("timeline", []))
	render_arrays["modelMemoryHintText"] = _debug_model_memory_hint_texts(_debug_dict(model_payload.get("memoryHints", {})))
	render_arrays["modelPlayerText"] = _debug_model_player_texts(model_payload.get("players", []))
	return {
		"key": "player_%d" % [seat_index + 1],
		"kind": "player",
		"seatIndex": seat_index,
		"seatNumber": seat_index + 1,
		"displayName": String(player.get("name", "")),
		"roleKey": String(player.get("role_key", "")),
		"role": _debug_role_label_for_player(seat_index),
		"alive": bool(player.get("alive", true)),
		"owner": String(player.get("owner", "")),
		"canViewWolfPrivate": can_view_wolf_private,
		"renderArrays": render_arrays,
		"modelPayload": model_payload,
	}


func _debug_final_observer_text_view(observer_index: int, observer: Dictionary) -> Dictionary:
	var can_view_wolf_private := true
	return {
		"key": "observer_%d" % [observer_index + 1],
		"kind": "observer",
		"seatIndex": -1,
		"seatNumber": -1,
		"displayName": _observer_display_name(observer, "观战"),
		"roleKey": "observer",
		"role": "观察者",
		"alive": true,
		"canViewWolfPrivate": can_view_wolf_private,
		"renderArrays": _debug_final_text_render_arrays(_history, can_view_wolf_private, -1),
		"modelPayload": {},
	}


func _debug_final_text_render_arrays(visible_history: Array, can_view_wolf_private: bool, viewer_index: int) -> Dictionary:
	var history_rows := _debug_history_render_rows(visible_history)
	var wolf_private_history := _debug_array_snapshot(_wolf_private_history) if can_view_wolf_private else []
	var wolf_private_rows := _debug_history_render_rows(wolf_private_history)
	return {
		"visibleHistoryText": _debug_rendered_texts_from_rows(history_rows),
		"historyPopupText": _debug_rendered_texts_from_rows(history_rows),
		"historyPopupRows": history_rows,
		"wolfPrivateHistoryText": _debug_rendered_texts_from_rows(wolf_private_rows),
		"wolfPrivateHistoryRows": wolf_private_rows,
		"viewerVisibleTimelineEventText": _debug_timeline_event_texts_for_viewer(viewer_index) if viewer_index >= 0 else [],
	}


func _debug_final_model_payload_for_seat(seat_index: int) -> Dictionary:
	if seat_index < 0 or seat_index >= _players.size() or not _debug_player_slot_occupied(seat_index):
		return {}
	var memory_payload := {
		"contextBudgetTokens": 1000000,
		"memoryContextBudgetTokens": 1024,
	}
	var visible_state := _bot_visible_state(seat_index, memory_payload)
	visible_state["timeline"] = _debug_visible_timeline_events_for_seat(seat_index)
	visible_state.erase("timelineTruncatedCount")
	var context := {
		"bot_id": _player_id_for_index(seat_index),
		"visible_state": visible_state,
		"allowed_actions": [],
		"memory_hints": {},
		"current_question": "渲染最终视角文本。",
	}
	return _bot_runtime.to_model_payload(context)


func _debug_visible_timeline_events_for_seat(seat_index: int) -> Array:
	var limit := maxi(1, _history.size() + _wolf_private_history.size() + 32)
	var events := _recent_timeline_events_for_viewer(limit, seat_index)
	var result := []
	for event_value in events:
		if event_value is Dictionary:
			var event: Dictionary = (event_value as Dictionary).duplicate(true)
			event.erase("_sortAt")
			result.append(event)
	return result


func _debug_timeline_event_texts_for_viewer(viewer_index: int) -> Array:
	var result := []
	for event_value in _debug_visible_timeline_events_for_seat(viewer_index):
		if event_value is Dictionary:
			var text := _debug_timeline_event_text(event_value as Dictionary)
			if text != "":
				result.append(text)
	return result


func _debug_timeline_event_text(event: Dictionary) -> String:
	var description := String(event.get("speechText", event.get("description", ""))).strip_edges()
	if description == "":
		return ""
	var speaker := "主持人"
	var actor_id := String(event.get("actorId", "")).strip_edges()
	if actor_id != "":
		speaker = _debug_player_seat_label_by_id(actor_id)
	elif String(event.get("type", "")) == "wolf_spoke":
		speaker = "狼队"
	return "%s:%s" % [speaker, description]


func _debug_player_seat_label_by_id(player_id: String) -> String:
	for i in range(_players.size()):
		if not (_players[i] is Dictionary):
			continue
		var player: Dictionary = _players[i]
		var id := String(player.get("id", "")).strip_edges()
		if id == player_id:
			return "%d号" % [i + 1]
	return "未知玩家"


func _debug_history_render_rows(history_items: Array) -> Array:
	var rows := []
	for item_value in history_items:
		if not (item_value is Dictionary):
			continue
		rows.append(_debug_history_render_row(item_value as Dictionary))
	return rows


func _debug_history_render_row(item: Dictionary) -> Dictionary:
	var seat := _history_item_seat_text(item)
	var name := _history_item_display_name(item)
	var speaker := String(item.get("speaker", "")).strip_edges()
	var text := _center_speech_display_text(item)
	var title := _debug_render_title(seat, name, speaker)
	return {
		"seat": seat,
		"name": name,
		"speaker": speaker,
		"text": text,
		"renderedText": "%s:%s" % [title, text],
		"visibility": String(item.get("visibility", "public")),
		"actionKey": String(item.get("action_key", "")),
		"speakerIndex": _history_item_speaker_index(item),
		"targetIndex": int(item.get("target_index", -1)),
	}


func _debug_render_title(seat: String, name: String, speaker: String) -> String:
	var clean_seat := seat.strip_edges()
	var clean_name := name.strip_edges()
	if clean_seat != "" and clean_name != "":
		return "%s %s" % [clean_seat, clean_name]
	if clean_name != "":
		return clean_name
	if speaker.strip_edges() != "":
		return speaker.strip_edges()
	return "主持人"


func _debug_rendered_texts_from_rows(rows: Array) -> Array:
	var result := []
	for row_value in rows:
		if row_value is Dictionary:
			result.append(String((row_value as Dictionary).get("renderedText", "")))
	return result


func _debug_center_speech_render_arrays() -> Dictionary:
	var current_rows := _debug_center_speech_rows(_center_speech_items)
	var pending_rows := _debug_center_speech_pending_rows(_center_speech_pending_items)
	var deferred_rows := _debug_center_speech_pending_rows(_center_speech_deferred_history_items)
	return {
		"currentText": _debug_rendered_texts_from_rows(current_rows),
		"currentRows": current_rows,
		"pendingText": _debug_rendered_texts_from_rows(pending_rows),
		"pendingRows": pending_rows,
		"deferredHistoryText": _debug_rendered_texts_from_rows(deferred_rows),
		"deferredHistoryRows": deferred_rows,
	}


func _debug_center_speech_pending_rows(items: Array) -> Array:
	var rows := []
	for value in items:
		if not (value is Dictionary):
			continue
		var wrapper: Dictionary = value
		var item_value = wrapper.get("item", wrapper)
		if item_value is Dictionary:
			rows.append(_debug_center_speech_row(item_value as Dictionary))
	return rows


func _debug_center_speech_rows(items: Array) -> Array:
	var rows := []
	for item_value in items:
		if item_value is Dictionary:
			rows.append(_debug_center_speech_row(item_value as Dictionary))
	return rows


func _debug_center_speech_row(entry: Dictionary) -> Dictionary:
	var speaker := String(entry.get("speaker", "")).strip_edges()
	var seat := String(entry.get("seat", _history_item_seat_text(entry))).strip_edges()
	var name := String(entry.get("name", _history_item_display_name(entry))).strip_edges()
	var full_text := _center_speech_display_text(entry)
	var visible_text := _center_speech_visible_text(entry) if entry.has("progress") else full_text
	var title := _debug_render_title(seat, name, speaker)
	return {
		"seat": seat,
		"name": name,
		"speaker": speaker,
		"text": visible_text,
		"fullText": full_text,
		"renderedText": "%s:%s" % [title, visible_text],
		"active": bool(entry.get("active", false)),
		"progress": float(entry.get("progress", 1.0)),
		"revealWithProgress": bool(entry.get("reveal_with_progress", false)),
	}


func _debug_model_memory_hint_texts(memory_hints: Dictionary) -> Array:
	var result := []
	for key in ["relevantMemory", "roundSummaries"]:
		var value = memory_hints.get(key, [])
		if value is Array:
			for item in value as Array:
				var text := String(item).strip_edges()
				if text != "":
					result.append("%s:%s" % [key, text])
	var long_term := String(memory_hints.get("longTermSummary", "")).strip_edges()
	if long_term != "":
		result.append("longTermSummary:%s" % long_term)
	return result


func _debug_model_player_texts(players_value) -> Array:
	var result := []
	if not (players_value is Array):
		return result
	for item in players_value as Array:
		if not (item is Dictionary):
			continue
		var player: Dictionary = item
		result.append("%s号 %s alive=%s role=%s" % [
			str(player.get("seatNumber", "")),
			String(player.get("displayName", "")),
			str(player.get("alive", true)),
			String(player.get("role", "")),
		])
	return result


func _debug_string_array(value) -> Array:
	var result := []
	if not (value is Array):
		return result
	for item in value as Array:
		result.append(String(item))
	return result


func _debug_role_label_for_player(index: int) -> String:
	if index < 0 or index >= _players.size() or not (_players[index] is Dictionary):
		return "未知"
	var role_key := String((_players[index] as Dictionary).get("role_key", "")).strip_edges()
	if role_key != "":
		return _role_catalog.role_label(role_key)
	var role := String((_players[index] as Dictionary).get("role", "")).strip_edges()
	return role if role != "" else "未知"


func _debug_player_slot_occupied(index: int) -> bool:
	if index < 0 or index >= _players.size() or not (_players[index] is Dictionary):
		return false
	return String((_players[index] as Dictionary).get("owner", "")).strip_edges() != ""


func _debug_dict(value) -> Dictionary:
	return value if value is Dictionary else {}


func _print_werewolf_perspective_text_debug_chunks(prefix: String, text: String, chunk_size: int = 1800) -> void:
	var clean_prefix := prefix.strip_edges()
	if clean_prefix == "":
		clean_prefix = "[WerewolfPerspectiveTextDebug]"
	if text == "":
		print("%s <empty>" % clean_prefix)
		return
	var size := maxi(256, chunk_size)
	var total := int(ceil(float(text.length()) / float(size)))
	for i in range(total):
		var start := i * size
		print("%s chunk=%d/%d\n%s" % [clean_prefix, i + 1, total, text.substr(start, size)])


func _debug_room_views(room: Dictionary, observers: Array) -> Array:
	var views := []
	views.append(_debug_host_view(room))
	for i in range(_players.size()):
		if not (_players[i] is Dictionary):
			continue
		var player: Dictionary = _players[i]
		if String(player.get("owner", "")).strip_edges() == "":
			continue
		var participant_id := _participant_id_for_player_view(player, i)
		views.append(_debug_participant_view("player_%d" % [i + 1], "player", participant_id, i, player))
	for i in range(observers.size()):
		if observers[i] is Dictionary:
			var observer: Dictionary = observers[i]
			var participant_id := String(observer.get("id", observer.get("participant_id", ""))).strip_edges()
			views.append(_debug_participant_view("observer_%d" % [i + 1], "observer", participant_id, -1, observer))
	return views


func _debug_host_view(room: Dictionary) -> Dictionary:
	return {
		"key": "host",
		"kind": "host",
		"participantId": "host",
		"seatIndex": -1,
		"displayName": String(room.get("host_name", "host")),
		"roleKey": "host",
		"canViewAll": true,
		"visibleHistory": _debug_array_snapshot(_history),
		"wolfPrivateHistory": _debug_array_snapshot(_wolf_private_history),
		"hiddenHistoryCount": 0,
		"currentAction": _debug_current_action_for_view("host", -1, true),
		"speechPrompt": _debug_speech_prompt_for_view("host", -1, true),
	}


func _debug_participant_view(key: String, kind: String, participant_id: String, seat_index: int, source: Dictionary) -> Dictionary:
	var is_observer := kind == "observer"
	var visible_history := _debug_visible_history_for_view(kind, participant_id, seat_index)
	var can_view_wolf_private := _debug_can_view_wolf_private_for_view(kind, seat_index)
	return {
		"key": key,
		"kind": kind,
		"participantId": participant_id,
		"controllerParticipantId": String(source.get("controller_participant_id", "")),
		"seatIndex": seat_index,
		"displayName": _debug_view_display_name(source, seat_index, kind),
		"roleKey": String(source.get("role_key", "")),
		"owner": String(source.get("owner", kind)),
		"canViewAll": is_observer,
		"visibleHistory": visible_history,
		"wolfPrivateHistory": _debug_array_snapshot(_wolf_private_history) if can_view_wolf_private else [],
		"hiddenHistoryCount": maxi(0, _history.size() - visible_history.size()),
		"currentAction": _debug_current_action_for_view(participant_id, seat_index, is_observer),
		"speechPrompt": _debug_speech_prompt_for_view(participant_id, seat_index, is_observer),
	}


func _debug_visible_history_for_view(kind: String, participant_id: String, seat_index: int) -> Array:
	if kind == "observer":
		return _debug_array_snapshot(_history)
	if seat_index >= 0:
		return _debug_visible_history_for_seat(seat_index)
	return _debug_visible_history_for_participant(participant_id)


func _debug_visible_history_for_seat(seat_index: int) -> Array:
	var result := []
	for item in _history:
		if item is Dictionary and _debug_history_item_visible_to_seat(item as Dictionary, seat_index):
			result.append((item as Dictionary).duplicate(true))
	return result


func _debug_visible_history_for_participant(participant_id: String) -> Array:
	var result := []
	for item in _history:
		if item is Dictionary and _history_item_visible_to_participant(item as Dictionary, participant_id):
			result.append((item as Dictionary).duplicate(true))
	return result


func _debug_history_item_visible_to_seat(item: Dictionary, seat_index: int) -> bool:
	var visibility := String(item.get("visibility", "public")).strip_edges()
	if visibility == "" or visibility == "public":
		return true
	if seat_index < 0:
		return false
	var visible_indices := _history_visible_to_indices(item)
	if visible_indices.has(seat_index):
		return true
	var actor_index := _history_item_speaker_index(item)
	match visibility:
		"private":
			return actor_index == seat_index
		"wolf":
			return _role_catalog.can_join_wolf_chat(_history_player_role_key(seat_index))
		"observer":
			return false
		_:
			return true


func _debug_can_view_wolf_private_for_view(kind: String, seat_index: int) -> bool:
	if kind == "observer":
		return true
	if seat_index < 0:
		return false
	if has_method("_can_view_wolf_private_history"):
		return bool(call("_can_view_wolf_private_history", seat_index))
	return false


func _debug_current_action_for_view(participant_id: String, seat_index: int, is_observer: bool) -> Dictionary:
	var action: Dictionary = _werewolf.get("current_action", {})
	if action.is_empty():
		return {}
	var actor_index := int(action.get("actor_index", _pending_actor_index))
	var can_control := false
	if not is_observer and seat_index >= 0:
		can_control = seat_index == actor_index
	elif not is_observer:
		can_control = _participant_controls_index(participant_id, actor_index)
	return {
		"label": String(action.get("label", _pending_action)),
		"key": String(action.get("key", "")),
		"icon": String(action.get("icon", _pending_action_icon)),
		"actorIndex": actor_index,
		"actorSeatNumber": actor_index + 1 if actor_index >= 0 else -1,
		"actorName": _player_title(actor_index) if actor_index >= 0 else "",
		"viewerCanControl": can_control,
		"viewerSeatIndex": seat_index,
	}


func _debug_speech_prompt_for_view(participant_id: String, seat_index: int, is_observer: bool) -> Dictionary:
	if _speech_prompt_index < 0:
		return {}
	var can_speak := false
	if not is_observer and seat_index >= 0:
		can_speak = seat_index == _speech_prompt_index
	elif not is_observer:
		can_speak = _participant_controls_index(participant_id, _speech_prompt_index)
	return {
		"speakerIndex": _speech_prompt_index,
		"speakerSeatNumber": _speech_prompt_index + 1,
		"speakerName": _player_title(_speech_prompt_index),
		"viewerCanSpeak": can_speak,
		"viewerSeatIndex": seat_index,
		"phase": String(_werewolf.get("phase", "")),
	}


func _debug_players_snapshot() -> Array:
	var result := []
	for i in range(_players.size()):
		if _players[i] is Dictionary:
			var player: Dictionary = (_players[i] as Dictionary).duplicate(true)
			player["seatIndex"] = i
			player["seatNumber"] = i + 1
			player["ttsEnabled"] = _player_tts_enabled(i)
			result.append(player)
	return result


func _debug_bot_snapshot() -> Dictionary:
	var tracker = _bot_request_tracker.snapshot() if _bot_request_tracker.has_method("snapshot") else {"counts": _bot_request_tracker.counts()}
	return {
		"requestTracker": tracker,
		"promptLog": _debug_bot_prompt_log_snapshot() if has_method("_debug_bot_prompt_log_snapshot") else {},
		"controlledModelProfiles": _controlled_bot_model_profiles_debug_snapshot() if has_method("_controlled_bot_model_profiles_debug_snapshot") else {},
		"waitingAction": _waiting_bot_action,
		"waitingSpeech": _waiting_bot_speech,
		"autoResolving": _auto_resolving,
		"flowHalted": _bot_flow_halted,
		"flowHaltError": _bot_flow_halt_error.duplicate(true),
		"wolfSpeechKeys": _bot_wolf_speech_keys.duplicate(true),
		"wolfTargetVoteKeys": _bot_wolf_target_vote_keys.duplicate(true),
		"wolfTargetVotes": _bot_wolf_target_votes.duplicate(true),
		"wolfTargetIntents": _wolf_target_intents_debug(),
		"wolfTargetVoteDebug": _wolf_target_vote_debug(),
	}


func _debug_tts_snapshot() -> Dictionary:
	var runtime := {}
	if _tts_runtime != null and _tts_runtime.has_method("debug_snapshot"):
		runtime = _tts_runtime.call("debug_snapshot")
	return {
		"historyQueue": _player_speech_output.queue_snapshot(),
		"runtime": runtime,
		"speakingIndex": _tts_speaking_index,
	}


func _debug_memory_snapshot(room_id: String) -> Dictionary:
	var scopes := []
	if _memory_manager == null:
		return {"scopes": scopes}
	for i in range(_players.size()):
		if not (_players[i] is Dictionary):
			continue
		var player: Dictionary = _players[i]
		var profile_id := _debug_bot_profile_id_for_player(i, player)
		if profile_id == "":
			continue
		var scope := _debug_memory_scope_for_player(i, player, room_id)
		scopes.append({
			"seatIndex": i,
			"seatNumber": i + 1,
			"playerId": String(player.get("id", "")),
			"botProfileId": profile_id,
			"name": String(player.get("name", "")),
			"scope": scope,
			"scopeKey": _memory_manager.scope_key(scope) if _memory_manager.has_method("scope_key") else "",
		})
	return {
		"loaded": bool(_memory_manager.get("_loaded")),
		"scopes": scopes,
		"scopeCount": scopes.size(),
	}


func _debug_memory_scope_for_player(index: int, player: Dictionary, room_id: String) -> Dictionary:
	var owner_id := _debug_bot_profile_id_for_player(index, player)
	if owner_id == "":
		owner_id = String(player.get("id", "")).strip_edges()
	if owner_id == "":
		owner_id = "bot_%d" % [index + 1]
	var memory_namespace := _debug_bot_profile_id_for_player(index, player)
	if memory_namespace == "":
		memory_namespace = String(player.get("id", "")).strip_edges()
	if memory_namespace == "":
		memory_namespace = owner_id
	return _memory_manager.scope(owner_id, "werewolf", memory_namespace, String(_werewolf.get("map_id", "basic_village")), room_id)


func _debug_bot_profile_id_for_player(index: int, player: Dictionary) -> String:
	if has_method("_local_private_bot_profile_id_for_seat"):
		return String(call("_local_private_bot_profile_id_for_seat", index)).strip_edges()
	return ""


func _participant_id_for_player_view(player: Dictionary, seat_index: int) -> String:
	var participant_id := String(player.get("participant_id", "")).strip_edges()
	if participant_id != "":
		return participant_id
	if String(player.get("owner", "")) == "self":
		return _current_network_participant_id()
	var player_id := String(player.get("id", "")).strip_edges()
	if player_id != "":
		return "player:%s" % player_id
	return "seat:%d" % [seat_index + 1]


func _debug_view_display_name(source: Dictionary, seat_index: int, kind: String) -> String:
	if kind == "observer":
		return _observer_display_name(source, "观战")
	var name := String(source.get("name", "")).strip_edges()
	if name != "":
		return name
	return "%d号位" % [seat_index + 1]


func _debug_array_snapshot(value: Array) -> Array:
	var result := []
	for item in value:
		if item is Dictionary:
			result.append((item as Dictionary).duplicate(true))
		elif item is Array:
			result.append((item as Array).duplicate(true))
		else:
			result.append(item)
	return result
