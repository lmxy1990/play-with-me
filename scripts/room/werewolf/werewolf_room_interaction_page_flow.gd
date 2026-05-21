extends "res://scripts/room/werewolf/werewolf_room_overlay_page_flow.gd"

const InteractionCircleAvatarScript := preload("res://scripts/ui/common/circle_avatar.gd")
const WerewolfHumanPlayerInteractionControllerScript := preload("res://scripts/player/werewolf/human/werewolf_human_player_interaction_controller.gd")
const WerewolfHumanPlayerStateControllerScript := preload("res://scripts/player/werewolf/human/werewolf_human_player_state_controller.gd")

var _werewolf_human_interaction_controller = WerewolfHumanPlayerInteractionControllerScript.new()
var _werewolf_human_state_controller = WerewolfHumanPlayerStateControllerScript.new()

func _on_seat_pressed(index: int) -> void:
	_play_click()
	_selected_player_index = index
	if _pending_action != "":
		if _is_empty_seat(index):
			_system_message = "请选择玩家头像"
			_show_room_system_message_toast()
			_flash_effect("skip")
			return
		if not _can_local_control_index(_pending_actor_index):
			_system_message = "等待 %s 行动" % _player_title(_pending_actor_index)
			_show_room_system_message_toast()
			_open_seat_detail(index)
			return
		_open_target_confirm(index)
	elif _speech_prompt_index >= 0:
		if index == _speech_prompt_index and _can_local_control_index(_speech_prompt_index):
			_open_speech_editor(index)
		elif _is_empty_seat(index):
			_open_empty_seat_actions(index)
		else:
			if index == _speech_prompt_index:
				_system_message = "等待 %s 发言" % _player_title(_speech_prompt_index)
				_show_room_system_message_toast()
			_open_seat_detail(index)
	elif _is_empty_seat(index):
		_open_empty_seat_actions(index)
	else:
		_open_seat_detail(index)


func _on_seat_name_edit_pressed(index: int) -> void:
	_play_click()
	if _can_edit_name(index):
		_open_name_editor(index)


func _on_seat_voice_toggle_pressed(index: int) -> void:
	_play_click()
	_toggle_player_tts(index, false)


func _open_empty_seat_actions(index: int) -> void:
	_clear_modal()
	if index < 0 or index >= _seat_cards.size():
		return
	var seat: Control = _seat_cards[index] as Control
	if seat == null:
		return
	_modal_layer.add_child(_seat_bubble_outside_close_area())
	var seat_center: Vector2 = seat.global_position + seat.size * 0.5
	var is_observer := _is_observer_participant(_current_network_participant_id())
	var seat_text := "切换"
	if is_observer:
		seat_text = "加入游戏"
	elif _local_player_index < 0:
		seat_text = "落座"
	var left := _seat_bubble(_werewolf_action_path("seat"), seat_text, true, func(): _sit_at(index))
	left.position = seat_center + Vector2(-122, -20)
	_modal_layer.add_child(left)
	var right := _seat_bubble(_werewolf_action_path("bot"), "机器人", false, func(): _open_add_bot_dialog(index))
	right.position = seat_center + Vector2(28, -20)
	_modal_layer.add_child(right)


func _open_observer_slot_actions(_slot_index: int) -> void:
	if not _is_observer_participant(_current_network_participant_id()):
		_system_message = "当前不在观战位"
		_show_room_system_message_toast()
		return
	var empty_indices := _empty_player_seat_indices()
	var card := _overlay_card("观战操作", Vector2(380, 330))
	card.name = "ObserverActionsOverlay"
	var body := _overlay_body(card)
	body.add_child(_observer_action_header())
	if empty_indices.is_empty():
		body.add_child(_label("玩家席位已满，暂时不能加入游戏或添加机器人。", 12, MUTED))
		return
	var gate: Dictionary = _room_runtime.can_change_seat(_werewolf)
	var join_button := _small_button("加入游戏", true, func(): _sit_at(int(empty_indices[0])))
	join_button.name = "ObserverJoinGameButton"
	join_button.disabled = not bool(gate.get("ok", false))
	if join_button.disabled:
		join_button.tooltip_text = String(gate.get("message", "当前不能加入游戏"))
	body.add_child(join_button)
	body.add_child(_dense_form_label("添加机器人到玩家空位"))
	var seat_grid := GridContainer.new()
	seat_grid.name = "ObserverAddBotSeatGrid"
	seat_grid.columns = 3
	seat_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seat_grid.add_theme_constant_override("h_separation", 7)
	seat_grid.add_theme_constant_override("v_separation", 7)
	body.add_child(seat_grid)
	var bot_gate: Dictionary = _room_runtime.can_add_bot(_werewolf)
	for item in empty_indices:
		var seat_index := int(item)
		var button := _small_button("%d号位" % [seat_index + 1], false, func(): _open_add_bot_dialog(seat_index))
		button.name = "ObserverAddBotSeatButton"
		button.disabled = not bool(bot_gate.get("ok", false))
		if button.disabled:
			button.tooltip_text = String(bot_gate.get("message", "当前不能添加机器人"))
		seat_grid.add_child(button)


func _observer_action_header() -> Control:
	var observer := _local_observer()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_action_icon(_werewolf_action_path("bot"), 42))
	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 2)
	row.add_child(text_col)
	text_col.add_child(_nowrap_label(_observer_display_name(observer, _local_nickname), 15, INK, true))
	text_col.add_child(_label("观战不占玩家身份，但仍可管理自己的机器人参局。", 12, MUTED))
	return row


func _empty_player_seat_indices() -> Array:
	var result := []
	for i in range(_players.size()):
		if _is_empty_seat(i):
			result.append(i)
	return result


func _seat_bubble(icon_path: String, text: String, primary: bool, callback: Callable) -> Button:
	var button := Button.new()
	button.name = "SeatBubbleAction"
	button.set_meta("seat_bubble", true)
	button.text = text
	button.icon = _texture(icon_path)
	button.expand_icon = true
	button.custom_minimum_size = Vector2(104, 42)
	button.focus_mode = Control.FOCUS_NONE
	_style_button(button, primary)
	button.pressed.connect(func():
		_play_click()
		callback.call()
	)
	return button


func _seat_bubble_outside_close_area() -> Control:
	var area := Control.new()
	area.name = "ModalOutsideCloseArea"
	area.set_anchors_preset(Control.PRESET_FULL_RECT)
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	area.set_meta("seat_bubble_overlay", true)
	return area


func _input(event: InputEvent) -> void:
	if not _seat_bubble_close_event(event):
		return
	if _modal_layer == null or not is_instance_valid(_modal_layer):
		return
	if not _seat_bubble_overlay_active():
		return
	var event_position := _seat_bubble_event_position(event)
	if _seat_bubble_contains_global_position(event_position):
		return
	_clear_modal()


func _seat_bubble_close_event(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		return mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).pressed
	return false


func _seat_bubble_event_position(event: InputEvent) -> Vector2:
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).position
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).position
	return Vector2.ZERO


func _seat_bubble_overlay_active() -> bool:
	for child in _modal_layer.get_children():
		if child is Control and bool((child as Control).get_meta("seat_bubble", false)):
			return true
	return false


func _seat_bubble_contains_global_position(position: Vector2) -> bool:
	for child in _modal_layer.get_children():
		if not (child is Control):
			continue
		var control := child as Control
		if not bool(control.get_meta("seat_bubble", false)):
			continue
		if Rect2(control.global_position, control.size).has_point(position):
			return true
	return false


func _sit_at(index: int) -> void:
	var gate: Dictionary = _room_runtime.can_change_seat(_werewolf)
	if not bool(gate.get("ok", false)):
		_system_message = String(gate.get("message", "不能切换座位"))
		_show_room_system_message_toast()
		_flash_effect("skip")
		return
	if index < 0 or index >= _players.size() or not _is_empty_seat(index):
		return
	if _is_network_client():
		var sent := bool(_room_network_session.call("request_switch_seat", index))
		if not sent:
			_system_message = "房间连接不可用"
		elif _is_observer_participant(_current_network_participant_id()):
			_system_message = "已发送加入游戏请求"
		else:
			_system_message = "已发送落座请求"
		_show_room_system_message_toast()
		_clear_modal()
		_flash_effect("action" if sent else "skip")
		return
	var participant_id := _current_network_participant_id()
	var was_observer := _is_observer_participant(participant_id)
	var observer := _observer_for_participant(_active_room(), participant_id) if was_observer else {}
	var player_data := _local_player_data()
	if was_observer and not observer.is_empty():
		var observer_name := _observer_display_name(observer, _local_nickname)
		player_data["name"] = observer_name
		_local_nickname = observer_name
		player_data["device_id"] = String(observer.get("device_id", observer.get("deviceId", "")))
		player_data["public_key"] = String(observer.get("public_key", observer.get("publicKey", "")))
		_remove_observer(_active_room(), participant_id)
	if _local_player_index >= 0 and _local_player_index < _players.size():
		_players[_local_player_index] = _empty_seat_data(_local_player_index)
	player_data["ready"] = false
	player_data["state"] = "等待"
	_players[index] = player_data
	_local_player_index = index
	_refresh_all_seats()
	_system_message = "已落座 %d号位" % [index + 1]
	_show_room_system_message_toast()
	_refresh_center_panel()
	_refresh_room_controls()
	_commit_state()
	_clear_modal()
	_flash_effect("action")


func _ensure_local_room_slot() -> bool:
	if _is_network_client() or _is_game_started():
		return false
	var room := _active_room()
	if room.is_empty():
		return false
	var participant_id := _current_network_participant_id()
	var seated_index := _seat_for_participant_id(participant_id)
	if seated_index >= 0:
		_local_player_index = seated_index
		return false
	if _is_observer_participant(participant_id):
		_local_player_index = -1
		return false
	var empty_index := _first_empty_seat()
	if empty_index >= 0:
		var player_data := _local_player_data()
		player_data["ready"] = false
		player_data["state"] = "等待"
		_players[empty_index] = player_data
		_local_player_index = empty_index
		_system_message = "已自动落座 %d号位" % [empty_index + 1]
		_refresh_active_room_bot_occupancy()
		_commit_state()
		return true
	var observer_gate := _can_add_observer(room)
	if bool(observer_gate.get("ok", false)):
		_register_observer(room, participant_id, _local_nickname, _device_identity.auth_payload())
		_local_player_index = -1
		_system_message = "已进入观战位"
		_refresh_active_room_bot_occupancy()
		_commit_state()
		return true
	_system_message = String(observer_gate.get("message", "房间已满"))
	_commit_state()
	return false


func _toggle_ready() -> void:
	var gate: Dictionary = _room_runtime.can_toggle_ready(_werewolf, _players, _local_player_index)
	if not bool(gate.get("ok", false)):
		_system_message = String(gate.get("message", "请先点击空位落座"))
		_show_room_system_message_toast()
		_flash_effect("skip")
		return
	var ready_update: Dictionary = _werewolf_human_state_controller.ready_update(_players, _local_player_index, _player_title(_local_player_index))
	if not bool(ready_update.get("ok", false)):
		_system_message = String(ready_update.get("message", "请先点击空位落座"))
		_show_room_system_message_toast()
		_flash_effect(String(ready_update.get("effect", "skip")))
		return
	var ready := bool(ready_update.get("ready", false))
	if _is_network_client():
		var sent := bool(_room_network_session.call("request_player_ready", ready, _local_player_index))
		_system_message = "已发送准备请求" if sent else "房间连接不可用"
		_show_room_system_message_toast()
		_flash_effect("vote" if sent and ready else "skip")
		return
	_players[_local_player_index]["ready"] = ready
	_players[_local_player_index]["state"] = String(ready_update.get("state", "已准备" if ready else "等待"))
	_refresh_seat(_local_player_index)
	_refresh_room_controls()
	_system_message = String(ready_update.get("message", ""))
	_show_room_system_message_toast()
	_refresh_center_panel()
	_commit_state()
	_flash_effect(String(ready_update.get("effect", "vote" if ready else "skip")))


func _open_name_editor(index: int) -> void:
	var result: Dictionary = _werewolf_human_interaction_controller.open_name_editor(index, _players, _local_nickname, _werewolf_human_interaction_callbacks())
	if bool(result.get("ok", false)):
		return
	var message := String(result.get("message", "")).strip_edges()
	if message != "":
		_system_message = message
		_show_room_system_message_toast()
	_flash_effect(String(result.get("effect", "skip")))


func _open_nickname_editor() -> void:
	_open_name_editor(_local_player_index)


func _save_nickname(text: String) -> void:
	_save_name(_local_player_index, text)


func _save_name(index: int, text: String) -> void:
	if not _can_edit_name(index):
		return
	var gate: Dictionary = _room_runtime.can_rename(_werewolf)
	if not bool(gate.get("ok", false)):
		_system_message = String(gate.get("message", "不能修改名字"))
		_show_room_system_message_toast()
		_flash_effect("skip")
		return
	var next_name := _werewolf_human_state_controller.normalized_name(text)
	if _is_network_client():
		var sent := bool(_room_network_session.call("request_update_participant", index, next_name))
		_system_message = "已发送改名请求" if sent else "房间连接不可用"
		_show_room_system_message_toast()
		_clear_modal()
		_flash_effect("action" if sent else "skip")
		return
	_players[index]["name"] = next_name
	if String(_players[index].get("owner", "")) == "self":
		_local_nickname = next_name
	_refresh_seat(index)
	_system_message = _werewolf_human_state_controller.rename_message()
	_show_room_system_message_toast()
	_commit_state()
	_clear_modal()
	_flash_effect("action")


func _open_seat_detail(index: int) -> void:
	var result: Dictionary = _werewolf_human_interaction_controller.open_seat_detail(index, _players, _werewolf_human_interaction_callbacks())
	if bool(result.get("ok", false)):
		return
	_system_message = String(result.get("message", "座位不存在"))
	_show_room_system_message_toast()
	_flash_effect(String(result.get("effect", "skip")))


func _open_target_confirm(index: int) -> void:
	var result: Dictionary = _werewolf_human_interaction_controller.open_target_confirm(index, _players, _werewolf, _pending_actor_index, _pending_action, _werewolf_human_interaction_callbacks())
	if bool(result.get("ok", false)):
		return
	_system_message = String(result.get("message", "请选择玩家头像"))
	_show_room_system_message_toast()
	_flash_effect(String(result.get("effect", "skip")))


func _confirm_pending_target(index: int, action_name: String = "") -> void:
	_clear_modal()
	_resolve_pending_action(index, action_name)


func _open_speech_editor(index: int) -> void:
	var result: Dictionary = _werewolf_human_interaction_controller.open_speech_editor(index, _players, _werewolf_human_interaction_callbacks())
	if bool(result.get("ok", false)):
		return
	_system_message = String(result.get("message", "发言玩家不存在"))
	_show_room_system_message_toast()
	_flash_effect(String(result.get("effect", "skip")))


func _submit_speech_from_editor(text: String) -> void:
	_clear_modal()
	_finish_speech(text)


func _werewolf_human_interaction_callbacks() -> Dictionary:
	return {
		"overlay_card": Callable(self, "_overlay_card"),
		"overlay_body": Callable(self, "_overlay_body"),
		"detail_avatar": Callable(self, "_detail_avatar"),
		"label": Callable(self, "_label"),
		"nowrap_label": Callable(self, "_nowrap_label"),
		"dense_form_label": Callable(self, "_dense_form_label"),
		"spacer": Callable(self, "_spacer"),
		"small_button": Callable(self, "_small_button"),
		"style_input": Callable(self, "_style_input"),
		"stat_badge": Callable(self, "_stat_badge"),
		"clear_modal": Callable(self, "_clear_modal"),
		"confirm_target": Callable(self, "_confirm_pending_target"),
		"submit_speech": Callable(self, "_submit_speech_from_editor"),
		"save_name": Callable(self, "_save_name"),
		"open_name_editor": Callable(self, "_open_name_editor"),
		"is_empty_seat": Callable(self, "_is_empty_seat"),
		"player_title": Callable(self, "_player_title"),
		"seat_status_text": Callable(self, "_seat_status_text"),
		"can_edit_name": Callable(self, "_can_edit_name"),
		"visible_role_for_index": Callable(self, "_visible_role_for_index"),
		"avatar_for_index": Callable(self, "_avatar_for_current_view"),
		"is_local_ai": Callable(self, "_is_local_private_ai_seat"),
		"player_tts_enabled": Callable(self, "_player_tts_enabled"),
		"toggle_player_tts": Callable(self, "_toggle_player_tts"),
		"player_controller_participant_id": Callable(self, "_player_controller_participant_id"),
		"remove_bot_gate": Callable(self, "_remove_bot_gate"),
		"remove_bot_at": Callable(self, "_remove_bot_at"),
		"action_path": Callable(self, "_werewolf_action_path"),
		"texture": Callable(self, "_texture"),
		"theme": {
			"ink": INK,
			"gold": GOLD,
			"teal": TEAL,
			"green": GREEN,
			"red": RED,
			"muted": MUTED,
		},
	}


func _toggle_player_tts(index: int, reopen_detail: bool = true) -> void:
	if index < 0 or index >= _players.size() or _is_empty_seat(index):
		return
	var tts_update: Dictionary = _werewolf_human_state_controller.tts_toggle_update(_player_tts_enabled(index), _player_title(index))
	var next_enabled := bool(tts_update.get("enabled", true))
	_set_player_tts_enabled(index, next_enabled)
	_system_message = String(tts_update.get("message", ""))
	_show_room_system_message_toast()
	_refresh_seat(index)
	_refresh_center_panel()
	if reopen_detail:
		_open_seat_detail(index)


func _detail_avatar(data: Dictionary, size_px: int) -> Control:
	var avatar := InteractionCircleAvatarScript.new()
	avatar.texture = _texture(String(data["avatar"]) if bool(data["alive"]) else _werewolf_action_path("dead_avatar"))
	avatar.custom_minimum_size = Vector2(size_px, size_px)
	avatar.ring_color = Color(0.96, 0.70, 0.32, 0.84) if bool(data.get("alive", true)) else Color(0.66, 0.69, 0.63, 0.70)
	avatar.shadow_color = Color(0, 0, 0, 0.22)
	avatar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return avatar


func _seat_status_text(data: Dictionary) -> String:
	return _werewolf_human_interaction_controller.seat_status_text(data)


func _seat_owner_text(owner: String) -> String:
	return _werewolf_human_interaction_controller.seat_owner_text(owner)


func _open_action_panel() -> void:
	if _pending_action != "":
		_show_room_system_message_toast()
		return
	if not _is_game_started():
		_system_message = "请等待房主点击开始"
		_show_room_system_message_toast()
		_flash_effect("skip")
		return
	_system_message = "等待主持人"
	_show_room_system_message_toast()


func _trigger_speech() -> void:
	_werewolf["phase"] = "day_discussion"
	_sync_werewolf_view_state()
	_refresh_center_panel()
	_flash_effect("speech")


func _toggle_phase() -> void:
	if not _is_game_started():
		_phase_night = not _phase_night
	else:
		_phase_night = _engine.is_night_phase(_werewolf)
	_show_table()
	_flash_effect("phase")
