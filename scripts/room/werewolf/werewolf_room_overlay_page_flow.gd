extends "res://scripts/room/werewolf/werewolf_room_bot_page_flow.gd"

const OverlayCircleAvatarScript := preload("res://scripts/ui/common/circle_avatar.gd")


func _open_qr() -> void:
	_start_host_room_network()
	_refresh_active_room_network_fields()
	var payload := _build_join_payload(false)
	var card := _overlay_card("加入二维码", Vector2(390, 540))
	var body := _overlay_body(card)
	body.add_child(_fake_qr(payload))
	var code_row := HBoxContainer.new()
	code_row.alignment = BoxContainer.ALIGNMENT_CENTER
	code_row.add_theme_constant_override("separation", 6)
	body.add_child(code_row)
	code_row.add_child(_stat_badge("网", "%s:%d" % [_local_host_address(), _room_network_port], TEAL, 142))
	code_row.add_child(_stat_badge("密", "房间信息已加密", GOLD, 146))
	var payload_line := LineEdit.new()
	payload_line.text = payload
	payload_line.editable = false
	payload_line.custom_minimum_size = Vector2(0, 32)
	_style_input(payload_line)
	body.add_child(payload_line)
	body.add_child(_small_button("复制加入码", false, func():
		if DisplayServer.get_name() != "headless":
			DisplayServer.clipboard_set(payload)
		_flash_effect("copy")
	))


func _switch_to_observer_gate() -> Dictionary:
	var room := _active_room()
	if room.is_empty():
		return {"ok": false, "message": "当前没有房间"}
	var participant_id := _current_network_participant_id()
	if _is_observer_participant(participant_id):
		return {"ok": false, "message": "当前已经在观战"}
	var gate: Dictionary = _room_runtime.can_change_seat(_werewolf)
	if not bool(gate.get("ok", false)):
		return {"ok": false, "message": String(gate.get("message", "游戏开始后不能切换为观战"))}
	var observer_gate := _can_add_observer_after_seat_release(room, participant_id)
	if not bool(observer_gate.get("ok", false)):
		return {"ok": false, "message": String(observer_gate.get("message", "当前不能观战"))}
	return {"ok": true, "message": ""}


func _switch_local_to_observer() -> void:
	var gate := _switch_to_observer_gate()
	if not bool(gate.get("ok", false)):
		_system_message = String(gate.get("message", "当前不能观战"))
		_show_room_system_message_toast()
		_flash_effect("skip")
		return
	if _is_network_client():
		var sent := bool(_room_network_session.call("request_switch_to_observer"))
		_system_message = "已发送观战请求" if sent else "房间连接不可用"
		_show_room_system_message_toast()
		_clear_modal()
		_flash_effect("action" if sent else "skip")
		return
	var participant_id := _current_network_participant_id()
	var index := _seat_for_participant_id(participant_id)
	var display_name := _local_nickname
	var auth := _device_identity.auth_payload()
	var identity := _preference_identity_snapshot()
	if index >= 0 and index < _players.size():
		var player: Dictionary = _players[index]
		display_name = String(player.get("name", _local_nickname))
		identity = player.duplicate(true)
		auth = {
			"deviceId": String(player.get("device_id", _device_identity.device_id)),
			"publicKey": String(player.get("public_key", _device_identity.public_key)),
		}
		_players[index] = _empty_seat_data(index)
	_register_observer(_active_room(), participant_id, display_name, auth, identity)
	_local_player_index = -1
	_system_message = "%s 切换为观战" % display_name
	_show_room_system_message_toast()
	_refresh_all_seats()
	_refresh_room_controls()
	_refresh_center_panel()
	_commit_state()
	_clear_modal()
	_flash_effect("action")


func _open_room_rules() -> void:
	var room: Dictionary = _active_room()
	var map_id := _room_rule_map_id(room)
	var map_name := _room_rule_map_name(room)
	var player_count := _room_rule_player_count(room)
	var rule_text := _room_rule_text(map_id, player_count)
	var map_data := _room_rule_map_data(map_id, map_name, rule_text)

	var viewport_size := get_viewport_rect().size
	var popup_size := Vector2(
		clampf(viewport_size.x - 40.0, 430.0, 600.0),
		clampf(viewport_size.y - 48.0, 430.0, 560.0)
	)
	var card := _overlay_card("房间规则", popup_size)
	card.name = "RoomRulesOverlay"
	var body := _overlay_body(card)
	body.add_child(_room_rules_summary(map_name, player_count))
	body.add_child(_room_rules_role_flow(map_data, player_count))
	body.add_child(_divider())

	var scroll := ScrollContainer.new()
	scroll.name = "RoomRulesTextScroll"
	scroll.custom_minimum_size = Vector2(0, 0)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	scroll.clip_contents = true
	body.add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_margin_each(margin, 2, 0, 8, 4)
	scroll.add_child(margin)
	margin.add_child(_room_rules_content(map_data, player_count, rule_text))


func _open_history() -> void:
	var panel := _side_overlay("历史对话")
	var body := _overlay_body(panel)
	var visible_history := _visible_history_for_current_participant()
	if visible_history.is_empty():
		body.add_child(_history_chat_line({"speaker": "主持人", "text": "暂无历史记录"}))
		return
	var scroll := ScrollContainer.new()
	scroll.name = "HistoryChatScroll"
	scroll.custom_minimum_size = Vector2(0, 0)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	scroll.clip_contents = true
	body.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "HistoryChatList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	list.add_theme_constant_override("separation", 9)
	scroll.add_child(list)
	var start: int = maxi(0, visible_history.size() - 60)
	for i in range(start, visible_history.size()):
		var item = visible_history[i]
		if item is Dictionary:
			list.add_child(_history_chat_line(item as Dictionary))
	call_deferred("_scroll_history_chat_to_bottom", scroll)


func _scroll_history_chat_to_bottom(scroll: ScrollContainer) -> void:
	if scroll == null or not is_instance_valid(scroll):
		return
	var bar := scroll.get_v_scroll_bar()
	if bar != null:
		bar.value = bar.max_value


func _history_chat_line(item: Dictionary) -> Control:
	var index := _history_item_speaker_index(item)
	var mine := index >= 0 and index == _local_player_index and not _is_observer_participant(_current_network_participant_id())
	var row := HBoxContainer.new()
	row.name = "HistoryChatRow"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_END if mine else BoxContainer.ALIGNMENT_BEGIN
	row.add_theme_constant_override("separation", 7)
	var avatar := _history_avatar_control(item, 34)
	var bubble := _history_chat_bubble(item, mine)
	if mine:
		row.add_child(_history_row_spacer())
		row.add_child(bubble)
		row.add_child(avatar)
	else:
		row.add_child(avatar)
		row.add_child(bubble)
		row.add_child(_history_row_spacer())
	return row


func _history_row_spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spacer


func _history_avatar_control(item: Dictionary, size_px: int) -> Control:
	var avatar := OverlayCircleAvatarScript.new()
	avatar.name = "HistoryAvatar"
	avatar.texture = _texture(_history_item_avatar_path(item))
	avatar.custom_minimum_size = Vector2(size_px, size_px)
	avatar.ring_color = Color(0.96, 0.70, 0.32, 0.72)
	avatar.shadow_color = Color(0, 0, 0, 0.16)
	avatar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if has_method("_wire_player_avatar_detail"):
		call("_wire_player_avatar_detail", avatar, _history_item_speaker_index(item))
	return avatar


func _history_chat_bubble(item: Dictionary, mine: bool) -> PanelContainer:
	var bg := Color(0.16, 0.55, 0.57, 0.26) if mine else Color(0.99, 0.92, 0.72, 0.78)
	var border := Color(0.16, 0.55, 0.57, 0.42) if mine else Color(0.62, 0.40, 0.16, 0.22)
	var bubble := _panel(bg, border, 8)
	bubble.name = "HistoryChatBubble"
	bubble.custom_minimum_size = Vector2(210, 0)
	bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	_margin_each(margin, 9, 7, 9, 7)
	bubble.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	margin.add_child(body)
	var seat := _history_item_seat_text(item)
	var name := _history_item_display_name(item)
	var meta := "%s %s" % [seat, name] if seat != "" else name
	var meta_label := _nowrap_label(meta, 11, GOLD if not mine else Color(0.92, 0.80, 0.52), true)
	meta_label.name = "HistoryChatMetaLabel"
	_force_ltr_label(meta_label)
	body.add_child(meta_label)
	var display_text := _center_speech_display_text(item) if has_method("_center_speech_display_text") else String(item.get("text", ""))
	var content := _label(display_text, 12, INK, false)
	content.name = "HistoryChatContentLabel"
	_force_ltr_label(content)
	content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	content.clip_text = false
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(content)
	return bubble


func _open_replay() -> void:
	_play_click()
	navigate_requested.emit("replay", {})


func _room_rule_map_id(room: Dictionary) -> String:
	var fallback := "basic_village" if not bool(_werewolf.get("started", false)) else String(_werewolf.get("map_id", "basic_village"))
	var map_id := String(room.get("map_id", fallback)).strip_edges()
	return "basic_village" if map_id == "" else map_id


func _room_rule_map_name(room: Dictionary) -> String:
	var fallback := "标准村庄" if not bool(_werewolf.get("started", false)) else String(_werewolf.get("map_name", "标准村庄"))
	var map_name := String(room.get("map_name", fallback)).strip_edges()
	return "标准村庄" if map_name == "" else map_name


func _room_rule_text(map_id: String, player_count: int) -> String:
	var rule_text := ""
	if _engine != null and _engine.has_method("map_rule_text"):
		rule_text = String(_engine.map_rule_text(map_id, player_count)).strip_edges()
	if rule_text == "":
		rule_text = String(_werewolf.get("map_rule_text", "")).strip_edges()
	if rule_text == "":
		rule_text = "按当前房间地图配置推进。"
	return rule_text


func _room_rule_player_count(room: Dictionary) -> int:
	var count := int(room.get("max_players", _players.size()))
	var occupied := _occupied_indices().size()
	if bool(_werewolf.get("started", false)) and occupied > 0:
		count = occupied
	if count <= 0:
		count = _players.size()
	return maxi(1, count)


func _room_rule_map_data(map_id: String, map_name: String, rule_text: String) -> Dictionary:
	if _engine != null and _engine.has_method("get_map_list"):
		var maps: Array = _engine.get_map_list()
		for item in maps:
			if item is Dictionary:
				var data: Dictionary = item as Dictionary
				if String(data.get("id", "")).strip_edges() == map_id:
					return data.duplicate(true)
	return {
		"id": map_id,
		"name": map_name,
		"rule_text": rule_text,
	}


func _room_rules_summary(map_name: String, player_count: int) -> Control:
	var row := HBoxContainer.new()
	row.name = "RoomRulesSummary"
	row.add_theme_constant_override("separation", 7)
	row.add_child(_stat_badge("图", map_name, GOLD, 178))
	row.add_child(_stat_badge("席", "%d人局" % player_count, TEAL, 94))
	return row


func _room_rules_role_flow(map_data: Dictionary, player_count: int) -> Control:
	var flow := HFlowContainer.new()
	flow.name = "RoomRulesRoleCounts"
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 5)
	for item in _map_role_counts(map_data, player_count):
		if item is Dictionary:
			flow.add_child(_map_role_text(item as Dictionary))
	if flow.get_child_count() == 0:
		flow.add_child(_map_plain_text("角色配置随房间人数生成", MUTED))
	return flow


func _room_rules_content(map_data: Dictionary, player_count: int, rule_text: String) -> Control:
	var content := VBoxContainer.new()
	content.name = "RoomRulesContent"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	content.add_theme_constant_override("separation", 9)
	for section_value in _room_rule_sections_from_text(rule_text, String(map_data.get("name", "")), player_count):
		var section: Dictionary = section_value
		content.add_child(_room_rule_section_from_text(String(section.get("title", "")), section.get("lines", []) as Array))
	return content


func _room_rule_sections_from_text(rule_text: String, map_name: String, player_count: int) -> Array:
	var result := []
	var title := ""
	var lines: Array = []
	var normalized := rule_text.replace("\r\n", "\n").replace("\r", "\n")
	for raw_line in normalized.split("\n", false):
		var line := String(raw_line).strip_edges()
		if line == "":
			continue
		if _room_rule_is_title_line(line):
			if title != "" or not lines.is_empty():
				result.append({"title": title, "lines": lines.duplicate()})
			title = _room_rule_title_text(line)
			lines.clear()
		else:
			lines.append(line)
	if title == "" and result.is_empty():
		title = "%s %d人局" % [map_name if map_name != "" else "房间规则", player_count]
	if title != "" or not lines.is_empty():
		result.append({"title": title, "lines": lines.duplicate()})
	if result.is_empty():
		result.append({"title": "规则说明", "lines": ["规则文本未配置。"]})
	return result


func _room_rule_is_title_line(line: String) -> bool:
	return line.length() >= 2 and line.begins_with("【") and line.ends_with("】")


func _room_rule_title_text(line: String) -> String:
	if not _room_rule_is_title_line(line):
		return line
	return line.substr(1, line.length() - 2)


func _room_rule_section_from_text(title: String, lines: Array) -> Control:
	var section := _room_rule_section(title, [])
	var body := section.find_child("RoomRuleSectionBody", true, false) as VBoxContainer
	if body == null:
		return section
	for line in lines:
		body.add_child(_room_rule_line_control(String(line)))
	if lines.is_empty():
		body.add_child(_room_rule_text_label("规则文本未配置。"))
	return section


func _room_rule_line_control(text: String) -> Control:
	var separator_index := text.find("：")
	if separator_index <= 0:
		var plain := _room_rule_text_label(text)
		plain.name = "RoomRulesText"
		return plain
	var box := VBoxContainer.new()
	box.name = "RoomRuleTextLine"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 2)
	var label := _nowrap_label(text.substr(0, separator_index + 1), 12, GOLD, true)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(label)
	var value := _room_rule_text_label(text.substr(separator_index + 1).strip_edges())
	value.name = "RoomRulesText"
	box.add_child(value)
	return box


func _room_rule_section(title: String, lines: Array) -> PanelContainer:
	var panel := _panel(Color(0.99, 0.92, 0.72, 0.74), Color(0.62, 0.40, 0.16, 0.22), 8)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body := _panel_body(panel, 9)
	body.name = "RoomRuleSectionBody"
	body.add_theme_constant_override("separation", 5)
	var title_label := _nowrap_label(title, 14, GOLD, true)
	title_label.name = "RoomRuleSectionTitle"
	body.add_child(title_label)
	for line in lines:
		body.add_child(_room_rule_bullet(String(line)))
	return panel


func _room_rule_bullet(text: String) -> Label:
	return _room_rule_text_label("· %s" % text)


func _room_rule_text_label(text: String) -> Label:
	var label := _label(text, 12, INK, false)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	label.clip_text = false
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label
