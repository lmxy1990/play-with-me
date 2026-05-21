extends "res://scripts/room/werewolf/werewolf_room_progress_page_flow.gd"


func _open_add_bot_dialog(index: int) -> void:
	var gate: Dictionary = _room_runtime.can_add_bot(_werewolf)
	if not bool(gate.get("ok", false)):
		if OS.is_debug_build():
			print("[WerewolfRoom][debug] open_add_bot blocked index=%d phase=%s message=%s" % [index, String(_werewolf.get("phase", "")), String(gate.get("message", ""))])
		_system_message = String(gate.get("message", "不能添加机器人"))
		_show_room_system_message_toast()
		_flash_effect("skip")
		return
	var enabled_profiles := _enabled_bot_profiles()
	if OS.is_debug_build():
		print("[WerewolfRoom][debug] open_add_bot index=%d profiles=%d enabled=%d serial=%d network_client=%s" % [
			index,
			_bot_profiles.size(),
			enabled_profiles.size(),
			_bot_serial,
			str(_is_network_client()),
		])
	var viewport_size := get_viewport_rect().size
	var popup_size := Vector2(
		minf(680.0, maxf(390.0, viewport_size.x - 32.0)),
		minf(520.0, maxf(360.0, viewport_size.y - 48.0))
	)
	var card := _overlay_card("添加机器人", popup_size)
	var body := _overlay_body(card)
	body.add_child(_dense_form_label("点击卡片添加到 %d号位" % [index + 1]))
	if enabled_profiles.is_empty():
		if OS.is_debug_build():
			print("[WerewolfRoom][debug] add_bot selection empty profiles=%d enabled=0" % _bot_profiles.size())
		body.add_child(_empty_add_bot_profile_card())
	else:
		var scroll := ScrollContainer.new()
		scroll.name = "AddBotProfileListScroll"
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		body.add_child(scroll)
		var list := GridContainer.new()
		list.name = "AddBotProfileList"
		list.columns = 1 if popup_size.x < 560.0 else 2
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("h_separation", 10)
		list.add_theme_constant_override("v_separation", 10)
		scroll.add_child(list)
		for profile_value in enabled_profiles:
			var profile: Dictionary = profile_value
			list.add_child(_add_bot_profile_choice_card(index, profile))
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 6)
	body.add_child(actions)
	actions.add_child(_small_button("取消", false, func(): _clear_modal()))


func _add_bot_at(index: int, bot_profile: Dictionary = {}) -> void:
	var gate: Dictionary = _room_runtime.can_add_bot(_werewolf)
	if not bool(gate.get("ok", false)):
		if OS.is_debug_build():
			print("[WerewolfRoom][debug] add_bot blocked index=%d phase=%s message=%s" % [index, String(_werewolf.get("phase", "")), String(gate.get("message", ""))])
		_system_message = String(gate.get("message", "不能添加机器人"))
		_show_room_system_message_toast()
		_flash_effect("skip")
		return
	if index < 0 or index >= _players.size() or not _is_empty_seat(index):
		if OS.is_debug_build():
			print("[WerewolfRoom][debug] add_bot invalid_seat index=%d seats=%d empty=%s" % [index, _players.size(), str(index >= 0 and index < _players.size() and _is_empty_seat(index))])
		return
	var profile := _normalized_bot_profile_for_add(bot_profile)
	var bot_profile_id := String(profile.get("id", "")).strip_edges()
	var model_name := _bot_profile_model_name(profile)
	var final_name := String(profile.get("name", profile.get("displayName", ""))).strip_edges()
	if final_name == "":
		final_name = "机器人%d" % _bot_serial
	var voice_name := _bot_profile_voice_name(profile)
	var active_room_id := String(_active_room().get("id", "")).strip_edges()
	if bot_profile_id != "" and _active_bot_profile_ids().has(bot_profile_id):
		if OS.is_debug_build():
			print("[WerewolfRoom][debug] add_bot occupied_current_room seat=%d profile_id=%s room_id=%s" % [
				index,
				bot_profile_id,
				active_room_id,
			])
		_system_message = "该机器人已在当前房间中"
		_show_room_system_message_toast()
		_flash_effect("skip")
		return
	var occupancy_gate := _bot_profile_available_for_room(bot_profile_id, active_room_id)
	if not bool(occupancy_gate.get("ok", true)):
		if OS.is_debug_build():
			print("[WerewolfRoom][debug] add_bot occupied seat=%d profile_id=%s room_id=%s message=%s" % [
				index,
				bot_profile_id,
				active_room_id,
				String(occupancy_gate.get("message", "")),
			])
		_system_message = String(occupancy_gate.get("message", "该机器人正在其他房间中"))
		_show_room_system_message_toast()
		_flash_effect("skip")
		return
	if OS.is_debug_build():
		print("[WerewolfRoom][debug] add_bot resolved seat=%d profile_id=%s name=%s model=%s voice=%s serial=%d network_client=%s" % [
			index,
			bot_profile_id,
			final_name,
			model_name,
			voice_name,
			_bot_serial,
			str(_is_network_client()),
		])
	if _is_network_client():
		_cache_local_private_bot_profile_for_seat(index, profile)
		var sent := bool(_room_network_session.call("request_add_controlled_player", index, final_name))
		if OS.is_debug_build():
			print("[WerewolfRoom][debug] add_bot network_request seat=%d profile_id=%s sent=%s private_cached=true" % [index, bot_profile_id, str(sent)])
		_system_message = "已发送添加机器人请求" if sent else "房间连接不可用"
		_show_room_system_message_toast()
		_clear_modal()
		_flash_effect("guard" if sent else "skip")
		return
	var avatars := _werewolf_bot_avatar_paths()
	var avatar_index := (_bot_serial - 1) % avatars.size()
	_players[index] = {
		"id": "player_%d" % _bot_serial,
		"name": final_name,
		"role": "未知",
		"role_key": "",
		"avatar": avatars[avatar_index],
		"state": "已准备",
		"motion": SeatMotion.IDLE,
		"alive": true,
		"ready": true,
		"owner": "human",
		"participant_id": "",
		"controller_participant_id": _current_network_participant_id(),
	}
	_cache_local_bot_private_fields(index, profile)
	if has_method("_initialize_controlled_bot_model_profiles"):
		call("_initialize_controlled_bot_model_profiles", "add_bot_local", true)
	if OS.is_debug_build():
		print("[WerewolfRoom][debug] add_bot local_added seat=%d player_id=%s profile_id=%s controller=%s" % [
			index,
			String((_players[index] as Dictionary).get("id", "")),
			bot_profile_id,
			_current_network_participant_id(),
		])
	_bot_serial += 1
	_refresh_seat(index)
	_system_message = "机器人加入 %d号位" % [index + 1]
	_show_room_system_message_toast()
	_refresh_center_panel()
	_refresh_room_controls()
	_refresh_active_room_bot_occupancy()
	_commit_state()
	_clear_modal()
	_flash_effect("guard")


func _cache_local_bot_private_fields(index: int, profile: Dictionary) -> void:
	if index < 0 or index >= _players.size() or not (_players[index] is Dictionary):
		return
	_cache_local_private_bot_profile_for_seat(index, profile)


func _remove_bot_at(index: int) -> void:
	var gate := _remove_bot_gate(index)
	if not bool(gate.get("ok", false)):
		_system_message = String(gate.get("message", "不能移除机器人"))
		_show_room_system_message_toast()
		_flash_effect("skip")
		return
	if _is_network_client():
		var sent := bool(_room_network_session.call("request_remove_bot", index))
		_system_message = "已发送移除机器人请求" if sent else "房间连接不可用"
		_show_room_system_message_toast()
		_clear_modal()
		_flash_effect("skip" if not sent else "action")
		return
	var bot_name := String(_players[index].get("name", "机器人"))
	_players[index] = _empty_seat_data(index)
	if has_method("_clear_local_private_bot_profile_for_seat"):
		call("_clear_local_private_bot_profile_for_seat", index)
	if has_method("_initialize_controlled_bot_model_profiles"):
		call("_initialize_controlled_bot_model_profiles", "remove_bot_local", true)
	_refresh_seat(index)
	_system_message = "%s 已移除" % bot_name
	_show_room_system_message_toast()
	_refresh_center_panel()
	_refresh_room_controls()
	_refresh_active_room_bot_occupancy()
	_commit_state()
	_clear_modal()
	_flash_effect("skip")


func _remove_bot_gate(index: int) -> Dictionary:
	if _is_game_started():
		return {"ok": false, "message": "对局已开始，不能移除机器人"}
	var gate: Dictionary = _room_runtime.can_add_bot(_werewolf)
	if not bool(gate.get("ok", false)):
		return {"ok": false, "message": String(gate.get("message", "不能移除机器人"))}
	if index < 0 or index >= _players.size():
		return {"ok": false, "message": "机器人不存在"}
	var player: Dictionary = _players[index]
	if _local_private_bot_profile_id_for_seat(index) == "":
		return {"ok": false, "message": "该座位不是机器人"}
	if not _participant_controls_index(_current_network_participant_id(), index):
		return {"ok": false, "message": "只能移除自己添加的机器人"}
	if _local_control_player_ready():
		return {"ok": false, "message": "已准备后不能移除机器人"}
	return {"ok": true, "message": ""}


func _local_control_player_ready() -> bool:
	var participant_id := _current_network_participant_id()
	if participant_id.strip_edges() == "":
		return false
	var player_index := _seat_for_participant_id(participant_id)
	if player_index < 0 or player_index >= _players.size():
		return false
	return bool(_players[player_index].get("ready", false))


func _add_bot_profile_choice_card(seat_index: int, profile: Dictionary) -> Control:
	var card := Control.new()
	card.name = "AddBotProfileCard"
	card.custom_minimum_size = Vector2(260, 132)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.clip_contents = false

	var panel := _panel(Color(0.99, 0.92, 0.72, 0.84), Color(0.62, 0.40, 0.16, 0.24), 8)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(panel)
	var body := _panel_body(panel, 9)
	body.add_theme_constant_override("separation", 6)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	body.add_child(top)
	var name := String(profile.get("name", "未命名机器人")).strip_edges()
	if name == "":
		name = "未命名机器人"
	var title := _nowrap_label(name, 15, INK, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(_stat_badge("位", "%d号" % [seat_index + 1], GOLD, 70))

	var description := String(profile.get("description", "")).strip_edges()
	if description == "":
		description = "未填写描述"
	body.add_child(_label(description, 11, MUTED))

	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", 8)
	body.add_child(meta)
	meta.add_child(_room_meta("模型 · %s" % _bot_profile_model_name(profile), GOLD))
	meta.add_child(_room_meta("声音 · %s" % _bot_profile_voice_name(profile), TEAL))
	var persona_text := "人设 · %s" % ("已设定" if String(profile.get("persona", "")).strip_edges() != "" else "自进化")
	body.add_child(_label(persona_text, 11, MUTED, true, HORIZONTAL_ALIGNMENT_RIGHT))

	var profile_copy := profile.duplicate(true)
	_add_bot_profile_card_hit(card, func():
		if OS.is_debug_build():
			print("[WerewolfRoom][debug] add_bot card_selected seat=%d id=%s name=%s model=%s voice=%s persona_chars=%d" % [
				seat_index,
				String(profile_copy.get("id", "")),
				String(profile_copy.get("name", "")),
				_bot_profile_model_name(profile_copy),
				_bot_profile_voice_name(profile_copy),
				String(profile_copy.get("persona", "")).length(),
			])
		_add_bot_at(seat_index, profile_copy)
	)
	return card


func _empty_add_bot_profile_card() -> PanelContainer:
	var card := _panel(Color(0.99, 0.92, 0.72, 0.72), Color(0.62, 0.40, 0.16, 0.20), 8)
	card.custom_minimum_size = Vector2(0, 118)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body := _panel_body(card, 12)
	body.add_child(_label("没有可用机器人配置", 16, INK, true))
	body.add_child(_label("请先在机器人配置页新增或启用机器人。", 12, MUTED))
	return card


func _add_bot_profile_card_hit(card: Control, callback: Callable) -> void:
	var hit := Button.new()
	hit.name = "AddBotProfileHit"
	hit.set_anchors_preset(Control.PRESET_FULL_RECT)
	hit.text = ""
	hit.focus_mode = Control.FOCUS_NONE
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_style_transparent_button(hit)
	var drag_state := {"dragged": false, "distance": 0.0}
	hit.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				drag_state["dragged"] = false
				drag_state["distance"] = 0.0
		elif event is InputEventScreenTouch:
			if event.pressed:
				drag_state["dragged"] = false
				drag_state["distance"] = 0.0
		elif event is InputEventScreenDrag:
			_forward_add_bot_profile_card_drag(card, float((event as InputEventScreenDrag).relative.y), drag_state)
			hit.accept_event()
		elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_forward_add_bot_profile_card_drag(card, float((event as InputEventMouseMotion).relative.y), drag_state)
			hit.accept_event()
	)
	hit.pressed.connect(func():
		if bool(drag_state.get("dragged", false)):
			drag_state["dragged"] = false
			return
		_play_click()
		callback.call()
	)
	card.add_child(hit)


func _forward_add_bot_profile_card_drag(card: Control, delta_y: float, drag_state: Dictionary) -> void:
	if absf(delta_y) <= 0.0:
		return
	drag_state["distance"] = float(drag_state.get("distance", 0.0)) + absf(delta_y)
	if float(drag_state.get("distance", 0.0)) >= 8.0:
		drag_state["dragged"] = true
	var scroll := _add_bot_profile_parent_scroll(card)
	if scroll == null:
		return
	scroll.scroll_vertical = maxi(0, scroll.scroll_vertical - int(round(delta_y)))


func _add_bot_profile_parent_scroll(control: Control) -> ScrollContainer:
	var node := control.get_parent()
	while node != null:
		if node is ScrollContainer:
			return node as ScrollContainer
		node = node.get_parent()
	return null


func _enabled_bot_profiles() -> Array:
	var result := []
	var room_id := String(_active_room().get("id", "")).strip_edges()
	var current_room_bot_ids := _active_bot_profile_ids()
	for item in _bot_profiles:
		if not (item is Dictionary):
			continue
		var profile: Dictionary = item
		if not bool(profile.get("enabled", true)):
			continue
		var profile_id := String(profile.get("id", "")).strip_edges()
		if profile_id != "" and current_room_bot_ids.has(profile_id):
			continue
		var occupancy_gate := _bot_profile_available_for_room(profile_id, room_id)
		if not bool(occupancy_gate.get("ok", true)):
			continue
		result.append(profile.duplicate(true))
	if OS.is_debug_build():
		print("[WerewolfRoom][debug] enabled_bot_profiles total=%d enabled=%d" % [_bot_profiles.size(), result.size()])
	return result


func _normalized_bot_profile_for_add(profile: Dictionary) -> Dictionary:
	if not profile.is_empty():
		return profile.duplicate(true)
	var first := _bot_profile_repository.first_enabled_profile()
	if not first.is_empty():
		if OS.is_debug_build():
			print("[WerewolfRoom][debug] normalized_bot_profile source=first_enabled id=%s name=%s" % [String(first.get("id", "")), String(first.get("name", ""))])
		return first
	if OS.is_debug_build():
		print("[WerewolfRoom][debug] normalized_bot_profile source=generated serial=%d" % _bot_serial)
	return {
		"id": "",
		"name": "默认模型",
		"model": "默认模型",
		"voice": "系统默认",
		"persona": "",
	}


func _bot_profile_model_name(profile: Dictionary) -> String:
	var model_name := String(profile.get("model", "")).strip_edges()
	return model_name if model_name != "" else "默认模型"


func _bot_profile_voice_name(profile: Dictionary) -> String:
	var voice_name := String(profile.get("voice", "")).strip_edges()
	return voice_name if voice_name != "" else "系统默认"
