extends "res://scripts/pages/base/page_navigation_ui_base.gd"


func _init() -> void:
	initial_route = "replay"


func apply_route_payload(_payload: Dictionary) -> void:
	_show_replay_page()


func _show_replay_page() -> void:
	_mode = Mode.REPLAY
	_bind_state()
	_clear_scene()
	_set_backdrop(_day_background_path(), Color(0.35, 0.24, 0.08, 0.055))

	var safe := MarginContainer.new()
	safe.set_anchors_preset(Control.PRESET_FULL_RECT)
	_margin_each(safe, 20, 16, 20, 18)
	_scene_root.add_child(safe)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	safe.add_child(root)
	root.add_child(_review_header())

	var wide := get_viewport_rect().size.x >= 760.0
	if wide:
		var row := HBoxContainer.new()
		row.size_flags_vertical = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 12)
		root.add_child(row)
		row.add_child(_players_panel(Vector2(350, 0)))
		row.add_child(_timeline_panel())
	else:
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		root.add_child(scroll)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 12)
		scroll.add_child(col)
		col.add_child(_players_panel(Vector2(0, 0)))
		col.add_child(_timeline_panel())


func _review_header() -> PanelContainer:
	var panel := _panel(Color(0.96, 0.88, 0.66, 0.76), Color(0.58, 0.36, 0.12, 0.34), 8)
	panel.custom_minimum_size = Vector2(0, 64)
	var margin := MarginContainer.new()
	_margin_each(margin, 12, 8, 12, 8)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	margin.add_child(row)
	row.add_child(_small_button("返回", false, func():
		navigate_requested.emit("table", {})
	))
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", -2)
	row.add_child(title_box)
	var room := _active_room()
	title_box.add_child(_nowrap_label("本局复盘 · %s" % String(room.get("name", "狼人杀")), 19, GOLD, true))
	title_box.add_child(_nowrap_label(_review_result_text(), 12, INK, true))
	row.add_child(_stat_badge("图", String(room.get("map_name", "标准村庄")), GOLD, 126))
	row.add_child(_stat_badge("人", _review_occupied_text(), TEAL, 78))
	return panel


func _players_panel(min_size: Vector2) -> PanelContainer:
	var panel := _panel(Color(0.98, 0.90, 0.69, 0.72), Color(0.58, 0.36, 0.12, 0.24), 8)
	panel.custom_minimum_size = min_size
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var body := _panel_body(panel, 12)
	body.add_child(_section_title("最终身份"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	for i in range(_players.size()):
		var player = _players[i]
		if player is Dictionary:
			list.add_child(_review_player_row(i, player as Dictionary))
	if list.get_child_count() == 0:
		list.add_child(_empty_hint("暂无玩家数据"))
	return panel


func _timeline_panel() -> PanelContainer:
	var panel := _panel(Color(0.98, 0.90, 0.69, 0.72), Color(0.58, 0.36, 0.12, 0.24), 8)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var body := _panel_body(panel, 12)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	body.add_child(title_row)
	title_row.add_child(_section_title("关键时间线"))
	title_row.add_child(_stat_badge("条", str(_history.size()), TEAL, 66))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 7)
	scroll.add_child(list)
	for item in _review_events():
		list.add_child(_review_event_row(item as Dictionary))
	if list.get_child_count() == 0:
		list.add_child(_empty_hint("暂无时间线"))
	return panel


func _section_title(text: String) -> Label:
	var label := _nowrap_label(text, 16, INK, true)
	label.custom_minimum_size = Vector2(0, 24)
	return label


func _review_player_row(index: int, player: Dictionary) -> PanelContainer:
	var alive := bool(player.get("alive", true))
	var row := _panel(Color(0.99, 0.92, 0.72, 0.84), Color(0.62, 0.40, 0.16, 0.18), 7)
	row.custom_minimum_size = Vector2(0, 62)
	var margin := MarginContainer.new()
	_margin_each(margin, 9, 7, 9, 7)
	row.add_child(margin)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	margin.add_child(body)
	var avatar := TextureRect.new()
	avatar.texture = _texture(String(player.get("avatar", "")) if alive else _werewolf_action_path("dead_avatar"))
	avatar.custom_minimum_size = Vector2(42, 42)
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	avatar.clip_contents = true
	body.add_child(avatar)
	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 0)
	body.add_child(text_col)
	text_col.add_child(_nowrap_label("%d号 · %s" % [index + 1, _review_role(player)], 13, GOLD if _review_is_mvp(index) else INK, true))
	text_col.add_child(_nowrap_label("%s · %s" % [String(player.get("name", "")), "存活" if alive else "死亡"], 12, GREEN if alive else RED, true))
	if _review_is_mvp(index):
		body.add_child(_stat_badge("M", "MVP", GOLD, 62))
	else:
		body.add_child(_stat_badge("态", "存活" if alive else "出局", GREEN if alive else RED, 66))
	return row


func _review_event_row(item: Dictionary) -> PanelContainer:
	var event_type := _review_event_type(item)
	var color := _event_color(event_type)
	var row := _panel(Color(0.99, 0.92, 0.72, 0.84), Color(color.r, color.g, color.b, 0.28), 7)
	row.custom_minimum_size = Vector2(0, 46)
	var margin := MarginContainer.new()
	_margin_each(margin, 8, 6, 8, 6)
	row.add_child(margin)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 7)
	margin.add_child(body)
	body.add_child(_stat_badge(_event_mark(event_type), _event_label(event_type), color, 90))
	var text := _nowrap_label(_review_event_text(item), 12, INK, false)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(text)
	body.add_child(_nowrap_label(_format_event_time(item.get("at", "")), 10, MUTED, false, HORIZONTAL_ALIGNMENT_RIGHT))
	return row


func _review_events() -> Array:
	var result := []
	for item in _history:
		if item is Dictionary:
			result.append(item)
	return result


func _review_result_text() -> String:
	var winner := String(_werewolf.get("winner", "")).strip_edges()
	for i in range(_history.size() - 1, -1, -1):
		var item = _history[i]
		if item is Dictionary:
			var text := String((item as Dictionary).get("text", "")).strip_edges()
			if text.contains("胜利") or text.contains("MVP"):
				return text
	if winner != "":
		return "%s胜利" % winner
	var phase := String(_werewolf.get("phase", ""))
	if not (phase in ["post_game_summary", "mvp_vote", "completed"]):
		return "当前对局尚未结束"
	return "游戏已结束"


func _review_occupied_text() -> String:
	var occupied := 0
	for player in _players:
		if player is Dictionary and String((player as Dictionary).get("owner", "")) != "":
			occupied += 1
	return "%d/%d" % [occupied, _players.size()]


func _review_role(player: Dictionary) -> String:
	var role := String(player.get("role", "未知")).strip_edges()
	if role == "" or role == "待加入":
		return "未知"
	return role


func _review_is_mvp(index: int) -> bool:
	var post = _werewolf.get("post_game", {})
	if not (post is Dictionary):
		return false
	return int((post as Dictionary).get("mvp_index", -1)) == index


func _review_event_text(item: Dictionary) -> String:
	var speaker := String(item.get("speaker", "")).strip_edges()
	var text := String(item.get("text", "")).strip_edges()
	if speaker == "":
		return text
	return "%s · %s" % [speaker, text]


func _review_event_type(item: Dictionary) -> String:
	var speaker := String(item.get("speaker", ""))
	var text := String(item.get("text", ""))
	if speaker == "MVP投票" or text.contains("MVP"):
		return "mvp"
	if text.contains("胜利"):
		return "result"
	if speaker == "投票" or text.contains("放逐"):
		return "vote"
	if speaker == "夜间记录" or text.contains("夜") or text.contains("昨夜"):
		return "night"
	if speaker == "查验结果":
		return "inspect"
	if speaker == "猎人" or text.contains("死亡") or text.contains("出局"):
		return "death"
	if speaker == "主持人" or speaker == "房间":
		return "system"
	return "speech"


func _event_mark(event_type: String) -> String:
	match event_type:
		"mvp":
			return "M"
		"result":
			return "胜"
		"vote":
			return "票"
		"night":
			return "夜"
		"inspect":
			return "验"
		"death":
			return "亡"
		"system":
			return "令"
		_:
			return "言"


func _event_label(event_type: String) -> String:
	match event_type:
		"mvp":
			return "MVP"
		"result":
			return "结果"
		"vote":
			return "投票"
		"night":
			return "夜晚"
		"inspect":
			return "查验"
		"death":
			return "出局"
		"system":
			return "系统"
		_:
			return "发言"


func _event_color(event_type: String) -> Color:
	match event_type:
		"mvp":
			return GOLD
		"result":
			return GREEN
		"vote":
			return TEAL
		"night":
			return Color(0.58, 0.50, 0.88)
		"inspect":
			return Color(0.40, 0.70, 0.95)
		"death":
			return RED
		"system":
			return MUTED
		_:
			return INK


func _format_event_time(value) -> String:
	var timestamp := 0
	if value is int:
		timestamp = int(value)
	elif value is float:
		timestamp = int(value)
	elif value is String:
		timestamp = int((value as String).to_int())
	if timestamp <= 0:
		return ""
	var dict := Time.get_datetime_dict_from_unix_time(timestamp)
	return "%02d:%02d" % [int(dict.get("hour", 0)), int(dict.get("minute", 0))]


func _empty_hint(text: String) -> PanelContainer:
	var row := _panel(Color(0.99, 0.92, 0.72, 0.76), Color(0.62, 0.40, 0.16, 0.16), 7)
	var margin := MarginContainer.new()
	_margin_each(margin, 8, 8, 8, 8)
	row.add_child(margin)
	margin.add_child(_nowrap_label(text, 12, MUTED, false, HORIZONTAL_ALIGNMENT_CENTER))
	return row
