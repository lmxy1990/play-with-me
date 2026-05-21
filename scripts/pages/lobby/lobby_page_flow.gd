extends "res://scripts/pages/base/page_navigation_ui_base.gd"


func _show_lobby() -> void:
	_mode = Mode.LOBBY
	_bind_state()
	_merge_discovered_rooms()
	_clear_scene()
	_set_backdrop(_lobby_background_path(), Color(0.35, 0.24, 0.08, 0.035))

	var safe := MarginContainer.new()
	safe.set_anchors_preset(Control.PRESET_FULL_RECT)
	_margin_each(safe, 20, 16, 20, 18)
	_scene_root.add_child(safe)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	safe.add_child(root)

	root.add_child(_lobby_toolbar())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	root.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = maxi(1, mini(5, int((get_viewport_rect().size.x - 36.0) / 310.0)))
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	for room in _lobby_room_cards():
		grid.add_child(_room_card(room))


func _lobby_toolbar() -> PanelContainer:
	var panel := _panel(Color(0.96, 0.88, 0.66, 0.74), Color(0.58, 0.36, 0.12, 0.34), 8)
	panel.custom_minimum_size = Vector2(0, 72)
	var margin := MarginContainer.new()
	_margin_each(margin, 12, 9, 12, 9)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	margin.add_child(row)

	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", -2)
	row.add_child(title_box)
	title_box.add_child(_shimmer_title("游玩大厅"))

	row.add_child(_toolbar_texture_button(_werewolf_action_path("refresh_rooms"), "刷新房间", func(): _refresh_lobby_rooms(), true))
	row.add_child(_toolbar_texture_button(_werewolf_action_path("create_room"), "创建房间", func(): _open_create_room(), true))
	row.add_child(_toolbar_texture_button(_werewolf_action_path("scan_join"), "扫描加入", func(): _open_scan_join(true), true))
	row.add_child(_toolbar_texture_button(_werewolf_action_path("model_config"), "模型配置", func(): _open_model_config(), true))
	row.add_child(_toolbar_texture_button(_werewolf_action_path("bot"), "机器人配置", func(): _open_bot_config(), true))
	row.add_child(_toolbar_texture_button(_werewolf_action_path("voice_config"), "声音配置", func(): _open_voice_config(), true))
	row.add_child(_toolbar_texture_button(_werewolf_action_path("preferences"), "偏好设置", func(): _open_preferences(), true))
	return panel


func _lobby_room_cards() -> Array:
	var result := []
	var reconnect_room := _reconnect_lobby_room()
	var reconnect_room_id := String(reconnect_room.get("id", ""))
	if not reconnect_room.is_empty():
		result.append(reconnect_room)
	for room_value in _rooms:
		if not (room_value is Dictionary):
			continue
		var room: Dictionary = room_value
		if reconnect_room_id != "" and String(room.get("id", "")) == reconnect_room_id:
			continue
		result.append(room)
	return result


func _reconnect_lobby_room() -> Dictionary:
	var session: Dictionary = _room_session_store.load()
	if not _room_session_store.is_valid(session):
		return {}
	var host := String(session.get("host", "")).strip_edges()
	var port := int(session.get("port", 0))
	var room_id := String(session.get("roomId", "")).strip_edges()
	if room_id == "":
		room_id = "reconnect_room"
	return {
		"id": room_id,
		"name": "等待重连的房间",
		"state": "可重连",
		"type": "狼人杀",
		"players": "等待同步",
		"lock": "重连",
		"address": "%s:%d" % [host, port],
		"bg": _lobby_background_path(),
		"map_name": "上次对局",
		"reconnect": true,
		"saved_at_ms": int(session.get("savedAtMs", 0)),
	}


func _room_card(room: Dictionary) -> Control:
	var reconnect := bool(room.get("reconnect", false))
	var card := Control.new()
	card.custom_minimum_size = Vector2(296, 312)
	card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	card.clip_contents = true
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel := _panel(Color(0.88, 0.95, 0.88, 0.86) if reconnect else Color(0.98, 0.90, 0.68, 0.86), Color(0.12, 0.46, 0.43, 0.48) if reconnect else Color(0.62, 0.40, 0.16, 0.30), 8)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(panel)

	var body := VBoxContainer.new()
	body.set_anchors_preset(Control.PRESET_FULL_RECT)
	body.add_theme_constant_override("separation", 0)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(body)

	var cover := TextureRect.new()
	cover.texture = _texture(_room_background_path(room))
	cover.custom_minimum_size = Vector2(0, 134)
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(cover)

	var info := MarginContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_margin_each(info, 12, 10, 12, 12)
	body.add_child(info)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 9)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(col)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 6)
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(title_row)
	var room_title := _nowrap_label(String(room["name"]), 18, INK, true)
	room_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	room_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(room_title)
	var arrow := _nowrap_label("▶", 15, GOLD, true, HORIZONTAL_ALIGNMENT_CENTER)
	arrow.custom_minimum_size = Vector2(18, 0)
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(arrow)

	var meta_flow := HFlowContainer.new()
	meta_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta_flow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	meta_flow.add_theme_constant_override("h_separation", 7)
	meta_flow.add_theme_constant_override("v_separation", 7)
	meta_flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(meta_flow)

	var state := String(room.get("state", "等待中"))
	var lock := String(room.get("lock", "公开"))
	meta_flow.add_child(_stat_badge("↻" if reconnect else "●", state, GOLD if reconnect else TEAL if state == "等待中" else RED, 86 if reconnect else 78))
	meta_flow.add_child(_stat_badge("局", String(room.get("type", "狼人杀")), GOLD, 78))
	meta_flow.add_child(_stat_badge("图", String(room.get("map_name", "标准村庄")), GOLD, 118))
	meta_flow.add_child(_stat_badge("席", String(room.get("players", "0/0")), TEAL, 98 if reconnect else 68))
	meta_flow.add_child(_stat_badge("锁", lock, RED if lock == "密码" else GREEN, 70))
	meta_flow.add_child(_stat_badge("址", String(room.get("address", "192.168.1.20")), MUTED, 128))

	var hit := Button.new()
	hit.set_anchors_preset(Control.PRESET_FULL_RECT)
	hit.text = ""
	hit.tooltip_text = "进入房间"
	hit.focus_mode = Control.FOCUS_NONE
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_style_transparent_button(hit)
	hit.pressed.connect(func():
		if bool(room.get("reconnect", false)):
			_reconnect_last_room()
		elif bool(room.get("discovered", false)):
			_join_discovered_room(room)
		else:
			_enter_table()
	)
	card.add_child(hit)
	return card
