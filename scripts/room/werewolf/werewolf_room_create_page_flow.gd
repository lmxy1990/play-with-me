extends "res://scripts/room/werewolf/werewolf_room_table_page_flow.gd"

const XiangqiMapCatalogScript := preload("res://scripts/room/xiangqi/xiangqi_map_catalog.gd")


func _open_create_room() -> void:
	var popup := _book_popup("", Vector2(1000, 640), func(): _clear_modal())
	var popup_node := popup["popup"] as Control
	var left := popup["left"] as VBoxContainer
	var right := popup["right"] as VBoxContainer
	left.add_theme_constant_override("separation", 9)
	right.add_theme_constant_override("separation", 6)

	var werewolf_maps: Array = _engine.get_map_list()
	if werewolf_maps.is_empty():
		werewolf_maps.append({"id": "basic_village", "name": "标准村庄", "supported_player_counts": [6]})
	var xiangqi_maps: Array = XiangqiMapCatalogScript.new().get_map_list()
	if xiangqi_maps.is_empty():
		xiangqi_maps.append({"id": "xiangqi_standard", "name": "标准象棋", "supported_player_counts": [2]})
	var maps_holder := {"items": werewolf_maps}
	var selected_game := {"value": "狼人杀"}
	var selected_map := {"index": 0}
	var selected_count := {"value": _first_supported_count(maps_holder["items"], 0)}
	var compression_enabled := {"value": false}
	var clock_enabled := {"value": false}
	var count_buttons: Array = []
	var refresh_maps := {"fn": Callable()}
	var refresh_counts := {"fn": Callable()}

	left.add_child(_create_section_label("玩法"))
	var game_select := OptionButton.new()
	game_select.name = "CreateRoomGameSelect"
	game_select.custom_minimum_size = Vector2(190, 34)
	_style_create_room_option(game_select)
	game_select.add_item("狼人杀")
	game_select.set_item_metadata(0, "狼人杀")
	game_select.add_item("象棋")
	game_select.set_item_metadata(1, "象棋")
	left.add_child(_create_room_control_row("玩法", game_select, "", 190.0, 48.0))

	left.add_child(_create_section_label("席位"))
	var count_row := HFlowContainer.new()
	count_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count_row.add_theme_constant_override("h_separation", 14)
	count_row.add_theme_constant_override("v_separation", 10)
	left.add_child(count_row)
	refresh_counts["fn"] = func() -> void:
		for child in count_row.get_children():
			count_row.remove_child(child)
			child.queue_free()
		count_buttons.clear()
		var maps: Array = maps_holder["items"]
		var counts := _supported_counts_for_selected_map(maps, int(selected_map["index"]))
		if counts.is_empty():
			counts = [2] if String(selected_game["value"]) == "象棋" else [6]
		if not counts.has(int(selected_count["value"])):
			selected_count["value"] = int(counts[0])
		for count_value_item in counts:
			var count_value := int(count_value_item)
			var button := _create_choice_button("%d席" % count_value, count_value, Vector2(74, 38), 16, "count")
			button.pressed.connect(func():
				_play_click()
				selected_count["value"] = count_value
				var refresh_count_fn: Callable = refresh_counts["fn"]
				if refresh_count_fn.is_valid():
					refresh_count_fn.call()
				var refresh_map_fn: Callable = refresh_maps["fn"]
				if refresh_map_fn.is_valid():
					refresh_map_fn.call()
			)
			count_buttons.append(button)
			count_row.add_child(button)
			_style_create_choice_button(button, int(button.get_meta("value", 0)) == int(selected_count["value"]))
	(refresh_counts["fn"] as Callable).call()

	var password_gap := Control.new()
	password_gap.custom_minimum_size = Vector2(0, 18)
	left.add_child(password_gap)
	left.add_child(_create_section_label("密码 · 可空"))
	var password := LineEdit.new()
	password.custom_minimum_size = Vector2(0, 36)
	password.placeholder_text = "••••"
	_style_create_password_input(password)
	left.add_child(_password_input_row(password))

	left.add_child(_create_section_label("AI"))
	var compression_check := _create_room_checkbox_row(left, "压缩", false, "启用")
	compression_check.name = "TimelineCompressionCheck"
	var compression_check_row := compression_check.get_parent() as Control
	var compression_model := _create_room_model_dropdown()
	compression_model.name = "TimelineCompressionModel"
	var compression_model_row := _create_room_control_row("模型", compression_model, "", 190.0, 48.0)
	left.add_child(compression_model_row)
	var compression_interval := _create_room_text_line(left, "间隔", str(AppState.DEFAULT_TIMELINE_COMPRESSION_INTERVAL), "轮", 74.0, 48.0)
	compression_interval.name = "TimelineCompressionInterval"
	var compression_interval_row := compression_interval.get_parent() as Control
	var max_output_tokens := _create_room_text_line(left, "输出", str(AppState.DEFAULT_ROOM_MAX_OUTPUT_TOKENS), "tokens", 98.0, 48.0)
	max_output_tokens.name = "RoomMaxOutputTokens"
	var max_output_tokens_row := max_output_tokens.get_parent() as Control
	var clock_check := _create_room_checkbox_row(left, "计时", false, "启用")
	clock_check.name = "XiangqiClockCheck"
	var clock_check_row := clock_check.get_parent() as Control
	var clock_minutes := OptionButton.new()
	clock_minutes.name = "XiangqiClockMinutes"
	clock_minutes.custom_minimum_size = Vector2(120, 32)
	_style_create_room_option(clock_minutes)
	for minutes in [5, 10, 15, 20, 30]:
		clock_minutes.add_item("%d分钟" % minutes)
		clock_minutes.set_item_metadata(clock_minutes.item_count - 1, minutes * 60000)
	clock_minutes.select(1)
	var clock_row := _create_room_control_row("时长", clock_minutes, "", 120.0, 48.0)
	left.add_child(clock_row)
	var refresh_compression_controls := func() -> void:
		var is_xiangqi := String(selected_game["value"]) == "象棋"
		if compression_check_row != null:
			compression_check_row.visible = not is_xiangqi
		compression_model_row.visible = not is_xiangqi
		if compression_interval_row != null:
			compression_interval_row.visible = not is_xiangqi
		if max_output_tokens_row != null:
			max_output_tokens_row.visible = not is_xiangqi
		compression_model.disabled = is_xiangqi or not bool(compression_enabled["value"])
		compression_interval.editable = (not is_xiangqi) and bool(compression_enabled["value"])
		compression_model.modulate = Color(1, 1, 1, 1) if bool(compression_enabled["value"]) and not is_xiangqi else Color(1, 1, 1, 0.52)
		compression_interval.modulate = Color(1, 1, 1, 1) if bool(compression_enabled["value"]) and not is_xiangqi else Color(1, 1, 1, 0.52)
		if clock_check_row != null:
			clock_check_row.visible = is_xiangqi
		clock_row.visible = is_xiangqi
		clock_minutes.disabled = not bool(clock_enabled["value"])
		clock_minutes.modulate = Color(1, 1, 1, 1) if bool(clock_enabled["value"]) else Color(1, 1, 1, 0.52)
	compression_check.toggled.connect(func(pressed: bool):
		compression_enabled["value"] = pressed
		refresh_compression_controls.call()
	)
	clock_check.toggled.connect(func(pressed: bool):
		clock_enabled["value"] = pressed
		refresh_compression_controls.call()
	)
	refresh_compression_controls.call()

	var map_slot := MarginContainer.new()
	map_slot.name = "MapSlot"
	map_slot.custom_minimum_size = Vector2(0, 300)
	map_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_slot.mouse_filter = Control.MOUSE_FILTER_STOP
	right.add_child(map_slot)

	var select_map_delta := func(delta: int) -> void:
		var maps: Array = maps_holder["items"]
		if maps.is_empty():
			return
		var next := (int(selected_map["index"]) + delta) % maps.size()
		if next < 0:
			next = maps.size() - 1
		selected_map["index"] = next
		var refresh_count_fn: Callable = refresh_counts["fn"]
		if refresh_count_fn.is_valid():
			refresh_count_fn.call()
		var refresh_map_fn: Callable = refresh_maps["fn"]
		if refresh_map_fn.is_valid():
			refresh_map_fn.call()
	refresh_maps["fn"] = func() -> void:
		for child in map_slot.get_children():
			map_slot.remove_child(child)
			child.queue_free()
		var maps: Array = maps_holder["items"]
		if maps.is_empty():
			return
		var index := int(selected_map["index"])
		var map_data: Dictionary = maps[index] as Dictionary
		map_slot.add_child(_map_showcase_card(index, map_data, int(selected_count["value"]), maps.size()))

	var swipe := {"active": false, "x": 0.0}
	map_slot.gui_input.connect(func(event: InputEvent):
		if event is InputEventScreenTouch:
			if event.pressed:
				swipe["active"] = true
				swipe["x"] = event.position.x
			elif bool(swipe["active"]):
				var dx: float = float(event.position.x) - float(swipe["x"])
				swipe["active"] = false
				if absf(dx) > 40.0:
					select_map_delta.call(-1 if dx > 0.0 else 1)
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				swipe["active"] = true
				swipe["x"] = event.position.x
			elif bool(swipe["active"]):
				var dx: float = float(event.position.x) - float(swipe["x"])
				swipe["active"] = false
				if absf(dx) > 40.0:
					select_map_delta.call(-1 if dx > 0.0 else 1)
	)

	(refresh_maps["fn"] as Callable).call()
	game_select.item_selected.connect(func(index: int):
		_play_click()
		var value = game_select.get_item_metadata(index)
		selected_game["value"] = String(value)
		maps_holder["items"] = xiangqi_maps if String(selected_game["value"]) == "象棋" else werewolf_maps
		selected_map["index"] = 0
		selected_count["value"] = _first_supported_count(maps_holder["items"], 0)
		var refresh_count_fn: Callable = refresh_counts["fn"]
		if refresh_count_fn.is_valid():
			refresh_count_fn.call()
		var refresh_map_fn: Callable = refresh_maps["fn"]
		if refresh_map_fn.is_valid():
			refresh_map_fn.call()
		refresh_compression_controls.call()
	)
	right.add_child(_spacer())
	var actions := _book_action_row(right)
	var confirm := _book_button("确认", true, func():
		var maps: Array = maps_holder["items"]
		if maps.is_empty():
			return
		var selected_map_index := int(selected_map.get("index", 0))
		if selected_map_index < 0 or selected_map_index >= maps.size():
			selected_map_index = 0
		var chosen_map: Dictionary = maps[selected_map_index] as Dictionary
		var is_xiangqi := String(selected_game["value"]) == "象棋"
		var room_options := {
			"game_room_id": "xiangqi" if is_xiangqi else "werewolf",
			"timeline_compression_enabled": (not is_xiangqi) and bool(compression_enabled["value"]),
			"timeline_compression_model": _create_room_selected_model_name(compression_model),
			"timeline_compression_interval": _create_room_positive_int(compression_interval.text, AppState.DEFAULT_TIMELINE_COMPRESSION_INTERVAL),
			"timeline_compression_prompt": AppState.DEFAULT_TIMELINE_COMPRESSION_PROMPT,
			"bot_max_output_tokens": _create_room_positive_int(max_output_tokens.text, AppState.DEFAULT_ROOM_MAX_OUTPUT_TOKENS),
			"clock_enabled": is_xiangqi and bool(clock_enabled["value"]),
			"time_limit_ms": _create_room_selected_metadata_int(clock_minutes, 600000),
		}
		_create_room_and_enter(String(selected_game["value"]), int(selected_count["value"]), password.text, String(chosen_map.get("id", "")), String(chosen_map.get("name", "")), room_options)
	)
	confirm.name = "CreateRoomConfirmButton"
	confirm.custom_minimum_size = Vector2(158, 46)
	_style_create_confirm_button(confirm)
	actions.add_child(confirm)
	if popup_node != null:
		popup_node.tree_exiting.connect(func():
			refresh_maps["fn"] = Callable()
			refresh_counts["fn"] = Callable()
			count_buttons.clear()
			maps_holder.clear()
			werewolf_maps.clear()
			xiangqi_maps.clear()
			selected_game.clear()
			selected_count.clear()
			selected_map.clear()
			compression_enabled.clear()
			clock_enabled.clear()
			swipe.clear()
		)


func _supported_counts_for_selected_map(maps: Array, selected_map_index: int) -> Array:
	if selected_map_index < 0 or selected_map_index >= maps.size() or not (maps[selected_map_index] is Dictionary):
		return [6]
	var map_data: Dictionary = maps[selected_map_index]
	var counts_value = map_data.get("supported_player_counts", [])
	var counts: Array = []
	if counts_value is Array:
		for item in counts_value:
			counts.append(int(item))
	var map_id := String(map_data.get("id", "")).strip_edges()
	if counts.is_empty() and _engine != null and _engine.has_method("get_supported_player_counts"):
		counts = _engine.get_supported_player_counts(map_id)
	if counts.is_empty():
		counts = [6]
	counts.sort()
	return counts


func _first_supported_count(maps: Array, selected_map_index: int) -> int:
	var counts := _supported_counts_for_selected_map(maps, selected_map_index)
	return int(counts[0]) if not counts.is_empty() else 6


func _create_section_label(text: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var label := _nowrap_label(text, 13, BOOK_GOLD, true, HORIZONTAL_ALIGNMENT_CENTER)
	label.custom_minimum_size = Vector2(0, 20)
	box.add_child(label)
	var line := HSeparator.new()
	line.add_theme_color_override("separator", Color(0.62, 0.38, 0.12, 0.22))
	box.add_child(line)
	return box


func _create_choice_button(text: String, value, min_size: Vector2 = Vector2(118, 48), font_size: int = 15, kind: String = "mode") -> Button:
	var button := Button.new()
	button.custom_minimum_size = min_size
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.set_meta("value", value)
	button.set_meta("label", text)
	button.set_meta("font_size", font_size)
	button.set_meta("kind", kind)
	_style_create_choice_button(button, false)
	return button


func _style_create_choice_button(button: Button, selected: bool) -> void:
	var label := String(button.get_meta("label", button.text))
	button.text = "%s  %s" % ["●" if selected else "○", label]
	var empty := StyleBoxEmpty.new()
	button.add_theme_stylebox_override("normal", empty)
	button.add_theme_stylebox_override("hover", empty)
	button.add_theme_stylebox_override("pressed", empty)
	button.add_theme_stylebox_override("focus", empty)
	var font := BOOK_GOLD if selected else BOOK_MUTED
	button.add_theme_color_override("font_color", font)
	button.add_theme_color_override("font_hover_color", font.lightened(0.12))
	button.add_theme_color_override("font_pressed_color", font.darkened(0.10))
	button.add_theme_color_override("font_focus_color", font)
	button.add_theme_font_size_override("font_size", _ui_font_size(int(button.get_meta("font_size", 15))))


func _password_input_row(line: LineEdit) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 40)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _choice_style_box(Color(1.0, 0.94, 0.76, 0.90), Color(0.62, 0.38, 0.12, 0.42), 8, 2))
	var margin := MarginContainer.new()
	_margin_each(margin, 12, 1, 10, 1)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)
	var key := TextureRect.new()
	key.texture = _texture(_werewolf_action_path("key"))
	key.custom_minimum_size = Vector2(28, 28)
	key.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	key.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(key)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(line)
	return panel


func _style_create_password_input(line: LineEdit) -> void:
	var empty := StyleBoxEmpty.new()
	line.add_theme_stylebox_override("normal", empty)
	line.add_theme_stylebox_override("focus", empty)
	line.add_theme_stylebox_override("read_only", empty)
	line.add_theme_color_override("font_color", BOOK_TEXT)
	line.add_theme_color_override("font_focus_color", BOOK_TEXT)
	line.add_theme_color_override("font_selected_color", Color(1.0, 0.98, 0.90))
	line.add_theme_color_override("font_uneditable_color", Color(0.38, 0.27, 0.14))
	line.add_theme_color_override("font_placeholder_color", Color(0.43, 0.30, 0.16, 0.38))
	line.add_theme_color_override("selection_color", Color(0.52, 0.30, 0.08, 0.84))
	line.add_theme_color_override("caret_color", BOOK_GOLD)
	line.add_theme_font_size_override("font_size", _ui_font_size(16))


func _create_room_checkbox_row(parent: VBoxContainer, title: String, value: bool, text: String) -> CheckBox:
	var checkbox := CheckBox.new()
	checkbox.text = text
	checkbox.button_pressed = value
	checkbox.custom_minimum_size = Vector2(0, 30)
	_style_book_checkbox(checkbox)
	parent.add_child(_create_room_control_row(title, checkbox, "", 0.0, 48.0))
	return checkbox


func _create_room_text_line(parent: VBoxContainer, title: String, value: String, suffix: String = "", control_width: float = 0.0, label_width: float = 48.0) -> LineEdit:
	var line := LineEdit.new()
	line.text = value
	line.custom_minimum_size = Vector2(0, 32)
	_style_book_input(line)
	parent.add_child(_create_room_control_row(title, line, suffix, control_width, label_width))
	return line


func _create_room_control_row(title: String, control: Control, suffix: String = "", control_width: float = 0.0, label_width: float = 48.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 34)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	var label := _nowrap_label(title, 13, BOOK_MUTED, true, HORIZONTAL_ALIGNMENT_RIGHT)
	label.custom_minimum_size = Vector2(label_width, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	if control_width > 0.0:
		control.custom_minimum_size.x = maxf(control.custom_minimum_size.x, control_width)
		control.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	else:
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	if suffix != "":
		var suffix_label := _nowrap_label(suffix, 12, BOOK_MUTED, true, HORIZONTAL_ALIGNMENT_LEFT)
		suffix_label.custom_minimum_size = Vector2(42, 0)
		suffix_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(suffix_label)
	return row


func _create_room_model_dropdown() -> OptionButton:
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(190, 32)
	_style_create_room_option(option)
	option.add_item("默认模型")
	option.set_item_metadata(0, "")
	for item_value in _model_configs:
		if not (item_value is Dictionary):
			continue
		var item: Dictionary = item_value
		var model_name := String(item.get("model", item.get("name", ""))).strip_edges()
		if model_name == "":
			continue
		var provider := String(item.get("provider", "")).strip_edges()
		var label := model_name if provider == "" else "%s · %s" % [model_name, provider]
		option.add_item(label)
		option.set_item_metadata(option.item_count - 1, model_name)
	return option


func _style_create_room_option(option: OptionButton) -> void:
	_style_book_button(option, false)
	option.add_theme_font_size_override("font_size", _ui_font_size(12))
	option.add_theme_color_override("font_color", BOOK_TEXT)
	option.add_theme_color_override("font_hover_color", BOOK_TEXT)
	option.add_theme_color_override("font_pressed_color", BOOK_TEXT)


func _create_room_selected_model_name(option: OptionButton) -> String:
	if option == null or option.item_count <= 0:
		return ""
	var index := option.selected
	if index < 0 or index >= option.item_count:
		return ""
	return String(option.get_item_metadata(index)).strip_edges()


func _create_room_positive_int(text: String, default_value: int) -> int:
	var value := text.strip_edges().to_int()
	if value <= 0:
		value = default_value
	return maxi(1, value)


func _create_room_selected_metadata_int(option: OptionButton, default_value: int) -> int:
	if option == null or option.item_count <= 0:
		return default_value
	var index := option.selected
	if index < 0 or index >= option.item_count:
		return default_value
	return int(option.get_item_metadata(index))


func _choice_style_box(bg: Color, border: Color, radius: int, width: int, horizontal_margin: int = 12) -> StyleBoxFlat:
	var box := _style_box(bg, border, radius, width)
	box.shadow_color = Color(0.18, 0.10, 0.03, 0.18)
	box.shadow_size = 5
	box.shadow_offset = Vector2(0, 1)
	box.set_content_margin(SIDE_LEFT, horizontal_margin)
	box.set_content_margin(SIDE_RIGHT, horizontal_margin)
	box.set_content_margin(SIDE_TOP, 4)
	box.set_content_margin(SIDE_BOTTOM, 4)
	return box


func _style_create_confirm_button(button: Button) -> void:
	var bg := Color(0.84, 0.51, 0.15, 0.96)
	var border := Color(0.56, 0.31, 0.08, 0.76)
	var font := Color(0.14, 0.08, 0.03)
	button.add_theme_stylebox_override("normal", _choice_style_box(bg, border, 8, 2))
	button.add_theme_stylebox_override("hover", _choice_style_box(bg.lightened(0.08), border.lightened(0.08), 8, 2))
	button.add_theme_stylebox_override("pressed", _choice_style_box(bg.darkened(0.12), border, 8, 2))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", font)
	button.add_theme_color_override("font_hover_color", font)
	button.add_theme_color_override("font_pressed_color", font)
	button.add_theme_font_size_override("font_size", _ui_font_size(22))


func _map_showcase_card(index: int, map_data: Dictionary, selected_count: int, total_maps: int) -> Control:
	var card := Control.new()
	card.name = "MapShowcaseCard"
	card.custom_minimum_size = Vector2(0, 300)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := _panel(Color(0.99, 0.92, 0.72, 0.72), Color(0.62, 0.40, 0.16, 0.22), 8)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(panel)
	var body := VBoxContainer.new()
	body.set_anchors_preset(Control.PRESET_FULL_RECT)
	body.add_theme_constant_override("separation", 6)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(body)

	var top_margin := MarginContainer.new()
	_margin_each(top_margin, 10, 1, 10, 0)
	body.add_child(top_margin)
	var text_col := VBoxContainer.new()
	text_col.add_theme_constant_override("separation", 1)
	text_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_margin.add_child(text_col)
	var name := _nowrap_label(String(map_data.get("name", "狼人杀地图")), 19, BOOK_TEXT, true, HORIZONTAL_ALIGNMENT_CENTER)
	name.custom_minimum_size = Vector2(0, 29)
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_col.add_child(name)
	var description := _nowrap_label(String(map_data.get("description", "")), 13, BOOK_MUTED, true, HORIZONTAL_ALIGNMENT_CENTER)
	description.custom_minimum_size = Vector2(0, 22)
	description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_col.add_child(description)

	var image_margin := MarginContainer.new()
	image_margin.custom_minimum_size = Vector2(0, 152)
	image_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	image_margin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	image_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_margin_each(image_margin, 18, 0, 18, 0)
	body.add_child(image_margin)
	var image_panel := _panel(Color(0.98, 0.90, 0.68, 0.72), Color(0.62, 0.40, 0.16, 0.38), 8)
	image_panel.custom_minimum_size = Vector2(0, 152)
	image_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	image_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	image_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image_margin.add_child(image_panel)
	var cover := TextureRect.new()
	cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	cover.texture = _texture(_map_cover_path(String(map_data.get("id", ""))))
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image_panel.add_child(cover)

	var bottom_margin := MarginContainer.new()
	bottom_margin.custom_minimum_size = Vector2(0, 62)
	bottom_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_margin.size_flags_vertical = Control.SIZE_SHRINK_END
	_margin_each(bottom_margin, 8, 3, 8, 4)
	bottom_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(bottom_margin)
	var role_flow := HFlowContainer.new()
	role_flow.name = "MapRoleCounts"
	role_flow.custom_minimum_size = Vector2(0, 54)
	role_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	role_flow.add_theme_constant_override("h_separation", 12)
	role_flow.add_theme_constant_override("v_separation", 5)
	role_flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_margin.add_child(role_flow)
	role_flow.add_child(_map_plain_text("%d人局" % selected_count, BOOK_GOLD))
	for item in _map_role_counts(map_data, selected_count):
		role_flow.add_child(_map_role_text(item as Dictionary))
	role_flow.add_child(_map_plain_text("%d/%d" % [index + 1, max(1, total_maps)], FRESH_LILAC))
	return card


func _map_role_counts(map_data: Dictionary, selected_count: int) -> Array:
	if String(map_data.get("id", "")).strip_edges().begins_with("xiangqi"):
		return [
			{"text": "红方 1", "color": BOOK_RED},
			{"text": "黑方 1", "color": Color(0.12, 0.12, 0.11)},
		]
	var roles: Array = []
	if _engine != null and _engine.has_method("get_role_config"):
		roles = _engine.get_role_config(String(map_data.get("id", "")), selected_count)
	if roles.is_empty():
		roles = ["wolf", "wolf", "seer", "witch", "villager", "villager"]
	var colors := {
		"wolf": BOOK_RED,
		"seer": Color(0.09, 0.33, 0.52),
		"witch": Color(0.38, 0.20, 0.54),
		"hunter": Color(0.54, 0.25, 0.06),
		"guard": BOOK_GREEN,
		"villager": BOOK_MUTED,
	}
	var result: Array = []
	for item_value in _role_catalog.role_counts(roles):
		var item: Dictionary = item_value
		var role_key := String(item.get("role_key", ""))
		var count := int(item.get("count", 0))
		if count <= 0:
			continue
		result.append({
			"text": "%s %d" % [_create_room_role_label(role_key, String(item.get("role_name", role_key))), count],
			"color": colors.get(role_key, BOOK_TEXT),
		})
	return result


func _create_room_role_label(role_key: String, fallback: String = "") -> String:
	if role_key == "villager":
		return "平民"
	if _role_catalog != null and _role_catalog.has_method("role_label"):
		var label := String(_role_catalog.role_label(role_key)).strip_edges()
		if label != "":
			return label
	return fallback if fallback.strip_edges() != "" else role_key


func _map_role_text(data: Dictionary) -> Label:
	return _map_plain_text(String(data.get("text", "")), data.get("color", BOOK_TEXT) as Color)


func _map_plain_text(text: String, color: Color) -> Label:
	var label := _nowrap_label(text, 14, color, true, HORIZONTAL_ALIGNMENT_LEFT)
	label.custom_minimum_size = Vector2(maxi(54, text.length() * 15), 24)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_shadow_color", Color(0.18, 0.10, 0.03, 0.12))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label


func _map_cover_path(map_id: String) -> String:
	if map_id.strip_edges().begins_with("xiangqi"):
		return "res://assets/images/xiangqi/backgrounds/table.svg"
	return _map_background_path(map_id)


func _create_room_and_enter(game_type: String, player_count: int, password: String, map_id: String = "", map_name: String = "", room_options: Dictionary = {}) -> void:
	var game_room_id := String(room_options.get("game_room_id", "werewolf")).strip_edges()
	if _app_state != null:
		var created_room: Dictionary = _app_state.create_room(game_type, player_count, password, map_id, map_name, true, 3, room_options)
		created_room["bg"] = _room_background_path(created_room)
		_bind_state()
	else:
		var normalized_options := AppState._normalized_room_options(room_options)
		var fallback_map_id := AppState.XIANGQI_MAP_ID if game_room_id == "xiangqi" else AppState.DEFAULT_MAP_ID
		var fallback_map_name := AppState.XIANGQI_MAP_NAME if game_room_id == "xiangqi" else AppState.DEFAULT_MAP_NAME
		var room := {
			"id": "local_room",
			"name": "%s房间" % game_type,
			"state": "等待中",
			"type": game_type,
			"players": "0/%d" % player_count,
			"lock": "密码" if password.strip_edges() != "" else "公开",
			"address": "本机",
			"bg": _room_background_path({"game_room_id": game_room_id, "map_id": map_id}),
			"password": password,
			"game_room_id": game_room_id,
			"gameId": game_room_id,
			"max_players": player_count,
			"map_id": map_id if map_id.strip_edges() != "" else fallback_map_id,
			"map_name": map_name if map_name.strip_edges() != "" else fallback_map_name,
		}
		for key in normalized_options.keys():
			room[key] = normalized_options[key]
		_rooms = [room]
		_players.clear()
		for i in range(player_count):
			_players.append(_empty_seat_data(i))
	_system_message = "房间已创建"
	_start_host_room_network()
	_refresh_active_room_network_fields()
	_commit_state()
	_publish_active_room()
	_enter_table()
	_show_room_system_message_toast()
