extends "res://scripts/pages/base/page_navigation_ui_base.gd"


func apply_route_payload(payload: Dictionary) -> void:
	if not payload.has("edit_index"):
		return
	var edit_index := int(payload.get("edit_index", -2))
	match initial_route:
		"model_config":
			_show_model_config_page(edit_index)
		"voice_config":
			_show_voice_config_page(edit_index)
		"bot_config":
			_show_bot_config_page(edit_index)


func _show_model_config_page(_edit_index: int = -2) -> void:
	pass


func _show_voice_config_page(_edit_index: int = -2) -> void:
	pass


func _show_bot_config_page(_edit_index: int = -2) -> void:
	pass

func _config_page_shell(title: String, back_callback: Callable, add_callback: Callable, show_add: bool = true, extra_actions: Array = []) -> GridContainer:
	var safe := MarginContainer.new()
	safe.set_anchors_preset(Control.PRESET_FULL_RECT)
	_margin_each(safe, 20, 16, 20, 18)
	_scene_root.add_child(safe)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	safe.add_child(root)

	var header := _panel(Color(0.96, 0.88, 0.66, 0.76), Color(0.58, 0.36, 0.12, 0.34), 8)
	header.custom_minimum_size = Vector2(0, 58)
	root.add_child(header)
	var header_margin := MarginContainer.new()
	_margin_each(header_margin, 12, 8, 12, 8)
	header.add_child(header_margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	header_margin.add_child(row)
	row.add_child(_small_button("返回", false, back_callback))
	var label := _label(title, 19, INK, true)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	if show_add:
		row.add_child(_small_button("新增", true, add_callback))
	for action in extra_actions:
		if not (action is Dictionary):
			continue
		var action_data: Dictionary = action
		var callback: Callable = action_data.get("callback", Callable())
		if not callback.is_valid():
			continue
		row.add_child(_small_button(String(action_data.get("text", "")), bool(action_data.get("primary", false)), callback))

	var list_panel := _panel(Color(0.98, 0.90, 0.69, 0.66), Color(0.58, 0.36, 0.12, 0.24), 8)
	list_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(list_panel)
	var list_root := _panel_body(list_panel, 12)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	list_root.add_child(scroll)
	var list := GridContainer.new()
	list.columns = maxi(2, mini(3, int((get_viewport_rect().size.x - 112.0) / 380.0)))
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("h_separation", 12)
	list.add_theme_constant_override("v_separation", 12)
	scroll.add_child(list)
	return list



func _config_card_hint(text: String) -> Label:
	var label := _label(text, 11, TEAL, true, HORIZONTAL_ALIGNMENT_RIGHT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label



func _add_config_card_hit(card: Control, callback: Callable) -> void:
	var hit := Button.new()
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
			_forward_config_card_drag(card, float((event as InputEventScreenDrag).relative.y), drag_state)
			hit.accept_event()
		elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_forward_config_card_drag(card, float((event as InputEventMouseMotion).relative.y), drag_state)
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


func _forward_config_card_drag(card: Control, delta_y: float, drag_state: Dictionary) -> void:
	if absf(delta_y) <= 0.0:
		return
	drag_state["distance"] = float(drag_state.get("distance", 0.0)) + absf(delta_y)
	if float(drag_state.get("distance", 0.0)) >= 8.0:
		drag_state["dragged"] = true
	var scroll := _config_parent_scroll_container(card)
	if scroll == null:
		return
	scroll.scroll_vertical = maxi(0, scroll.scroll_vertical - int(round(delta_y)))


func _config_parent_scroll_container(control: Control) -> ScrollContainer:
	var node := control.get_parent()
	while node != null:
		if node is ScrollContainer:
			return node as ScrollContainer
		node = node.get_parent()
	return null


func _bot_profiles_using_model_name(model_name: String) -> Array:
	return _bot_profiles_using_field_values("model", [model_name])


func _bot_profiles_using_voice_names(voice_names: Array) -> Array:
	return _bot_profiles_using_field_values("voice", voice_names)


func _bot_profiles_using_field_values(field_name: String, values: Array) -> Array:
	var candidates := {}
	for value in values:
		var clean := String(value).strip_edges()
		if clean != "":
			candidates[clean] = true
	if candidates.is_empty():
		return []
	var result := []
	for item in _bot_profiles:
		if not (item is Dictionary):
			continue
		var profile: Dictionary = item
		var profile_value := String(profile.get(field_name, "")).strip_edges()
		if profile_value != "" and candidates.has(profile_value):
			result.append(profile.duplicate(true))
	return result


func _bot_usage_names(profiles: Array, limit: int = 3) -> String:
	var names := []
	for item in profiles:
		if not (item is Dictionary):
			continue
		var profile: Dictionary = item
		var name := String(profile.get("name", profile.get("display_name", ""))).strip_edges()
		if name == "":
			name = String(profile.get("id", "未命名机器人")).strip_edges()
		if name == "":
			name = "未命名机器人"
		if not names.has(name):
			names.append(name)
	var shown := names.slice(0, mini(names.size(), maxi(1, limit)))
	var suffix := " 等%d个" % names.size() if names.size() > shown.size() else ""
	return "、".join(shown) + suffix



func _book_control_row(parent: VBoxContainer, title: String, control: Control, suffix: String = "", control_width: float = 0.0, label_width: float = 0.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 32)
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	var label := _book_form_label(title)
	var resolved_label_width := label_width if label_width > 0.0 else float(maxi(76, title.length() * 10))
	label.custom_minimum_size = Vector2(resolved_label_width, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	control.custom_minimum_size.y = maxf(control.custom_minimum_size.y, 32.0)
	if control_width > 0.0:
		control.custom_minimum_size.x = maxf(control.custom_minimum_size.x, control_width)
		control.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	else:
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	if suffix != "":
		var suffix_label := _book_label(suffix, 12, BOOK_MUTED, true, HORIZONTAL_ALIGNMENT_CENTER)
		suffix_label.custom_minimum_size = Vector2(20, 0)
		suffix_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(suffix_label)
	return row



func _book_compact_line(parent: VBoxContainer, title: String, value: String, secret: bool = false, suffix: String = "", control_width: float = 0.0, label_width: float = 0.0) -> LineEdit:
	var line := LineEdit.new()
	line.text = value
	line.secret = secret
	line.custom_minimum_size = Vector2(0, 32)
	_style_book_input(line)
	_book_control_row(parent, title, line, suffix, control_width, label_width)
	return line



func _style_book_option(option: OptionButton) -> void:
	_style_book_button(option, false)
	option.add_theme_font_size_override("font_size", _ui_font_size(12))
	option.add_theme_color_override("font_color", BOOK_TEXT)
	option.add_theme_color_override("font_hover_color", BOOK_TEXT)
	option.add_theme_color_override("font_pressed_color", BOOK_TEXT)


