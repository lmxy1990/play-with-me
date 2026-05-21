extends "res://scripts/pages/config/config_page_base.gd"


func _init() -> void:
	initial_route = "voice_config"


func _show_voice_config_page(edit_index: int = -2) -> void:
	_mode = Mode.VOICE_CONFIG
	_clear_scene()
	_set_backdrop(_lobby_background_path(), Color(0.35, 0.24, 0.08, 0.055))
	var list := _config_page_shell("声音配置", func():
		navigate_requested.emit("lobby", {})
		_show_lobby()
	, func(): _show_voice_config_page(-1), true)
	for i in range(_voice_configs.size()):
		list.add_child(_voice_config_card(i))
	if edit_index != -2:
		_voice_editor(edit_index)



func _voice_config_card(index: int) -> PanelContainer:
	var data: Dictionary = _voice_configs[index]
	var card := _panel(Color(0.99, 0.92, 0.72, 0.84), Color(0.62, 0.40, 0.16, 0.22), 8)
	card.custom_minimum_size = Vector2(0, 132)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body := _panel_body(card, 9)
	var enabled := bool(data.get("enabled", true))
	var active := bool(data.get("active", false))
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	body.add_child(top)
	var name := _label(String(data["name"]), 16, INK, true)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name)
	if active:
		top.add_child(_stat_badge("用", "主用", TEAL, 62))
	if not enabled:
		top.add_child(_stat_badge("停", "停用", MUTED, 62))
	top.add_child(_stat_badge("声", _voice_badge_text(data), GOLD, 94))
	body.add_child(_label("%s · %s · 语速 %s · 音调 %s · 音量 %s" % [_voice_engine_label(String(data["engine"])), String(data["gender"]), String(data["speed"]), String(data.get("pitch", "1.00")), String(data.get("volume", "1.00"))], 11, MUTED))
	body.add_child(_config_card_hint(_voice_config_hint(data, enabled)))
	_add_config_card_hit(card, func(): _show_voice_config_page(index))
	return card



func _voice_badge_text(data: Dictionary) -> String:
	var voice := String(data.get("voice", "")).strip_edges()
	var engine := _normalize_voice_engine(String(data.get("engine", "")))
	if voice == "":
		return "%s默认" % _voice_engine_label(engine)
	return voice



func _voice_config_hint(data: Dictionary, enabled: bool) -> String:
	if not enabled:
		return "已停用"
	var engine := _normalize_voice_engine(String(data.get("engine", "")))
	var voice := String(data.get("voice", "")).strip_edges()
	if engine == "":
		return "缺少引擎"
	if not _voice_known_engine_ids().has(engine):
		return "引擎未接入"
	if not _voice_engine_available(engine):
		return "引擎不可用"
	if voice == "":
		return "%s默认" % _voice_engine_label(engine)
	return "点击编辑"



func _voice_engine_label(engine: String) -> String:
	return _tts_voice_catalog.engine_label(engine)



func _warm_up_voice_engine(engine: String, reason: String) -> Dictionary:
	if _tts_runtime == null:
		_setup_tts_runtime()
	_sync_voice_catalog_runtime()
	return _tts_voice_catalog.warm_up_engine(engine, reason)



func _reveal_voice_delete(card: Control, index: int) -> void:
	var existing := card.get_node_or_null("DeleteButton") as Button
	if existing != null:
		existing.visible = true
		return
	var button := _small_button("删除", false, func(): _delete_voice_config(index), true)
	button.name = "DeleteButton"
	button.anchor_left = 1.0
	button.anchor_right = 1.0
	button.anchor_top = 0.0
	button.anchor_bottom = 0.0
	button.offset_left = -96
	button.offset_right = -8
	button.offset_top = 8
	button.offset_bottom = 44
	card.add_child(button)
	button.grab_focus.call_deferred()



func _voice_editor(index: int) -> void:
	var is_editing_existing := index >= 0 and index < _voice_configs.size()
	var data := {"name": "", "engine": "system", "gender": "女声", "voice": "", "speed": "0.90", "pitch": "1.00", "volume": "1.00", "enabled": true, "active": false}
	if is_editing_existing:
		data = _voice_configs[index].duplicate(true)
	if _tts_runtime == null:
		_setup_tts_runtime()
	_voice_config_debug("open editor index=%d engine=%s gender=%s voice=%s" % [index, String(data["engine"]), String(data["gender"]), _voice_config_voice_debug(String(data["voice"]))])
	var popup := _book_popup("", _voice_editor_popup_size(is_editing_existing), func(): _show_voice_config_page())
	var popup_node := popup["popup"] as Control
	var left := popup["left"] as VBoxContainer
	var right := popup["right"] as VBoxContainer
	left.add_theme_constant_override("separation", 6)
	right.add_theme_constant_override("separation", 6)
	left.add_child(_book_section_label("基础信息"))
	var name := _book_compact_line(left, "名称", String(data["name"]))
	var state := {
		"engine": _voice_supported_engine_or_default(String(data["engine"])),
		"gender": String(data["gender"]),
	}
	var voice := _book_voice_dropdown(state["engine"], state["gender"], String(data["voice"]))
	var gender_switch: CheckButton = null
	var refresh_voice_controls := func(keep_selected_voice: bool):
		var disabled := _voice_gender_disabled_options(String(state["engine"]))
		if disabled.has(String(state["gender"])):
			state["gender"] = _first_available_voice_gender(String(state["engine"]))
		if gender_switch != null:
			_book_gender_switch_update(gender_switch, String(state["gender"]), disabled)
		var selected_voice := _book_voice_selected(voice) if keep_selected_voice else ""
		_populate_voice_dropdown(voice, String(state["engine"]), String(state["gender"]), selected_voice)
		_voice_config_debug("refresh voices engine=%s gender=%s keep=%s selected_before=%s selected_after=%s item_count=%d disabled=%s" % [String(state["engine"]), String(state["gender"]), str(keep_selected_voice), _voice_config_voice_debug(selected_voice), _voice_config_voice_debug(_book_voice_selected(voice)), voice.get_item_count(), JSON.stringify(disabled)])
	var voices_updated_callback := func(voices: Array):
		_voice_config_debug("runtime voices_updated current_engine=%s incoming_count=%d" % [String(state["engine"]), voices.size()])
		if not is_instance_valid(voice):
			return
		refresh_voice_controls.call(true)
	if _tts_runtime != null and _tts_runtime.has_signal("voices_updated"):
		_tts_runtime.voices_updated.connect(voices_updated_callback)
		popup_node.tree_exiting.connect(func():
			if _tts_runtime != null and _tts_runtime.voices_updated.is_connected(voices_updated_callback):
				_tts_runtime.voices_updated.disconnect(voices_updated_callback)
		)
	var engine_changed := func(value: String):
		var previous_gender := String(state["gender"])
		_voice_config_debug("engine changed from=%s to=%s gender=%s" % [String(state["engine"]), value, previous_gender])
		state["engine"] = value
		_warm_up_voice_engine(value, "engine_changed")
		refresh_voice_controls.call(false)
		_voice_config_debug("engine changed refreshed engine=%s gender_before=%s gender_after=%s" % [value, previous_gender, String(state["gender"])])
	_book_voice_engine_dropdown(left, String(state["engine"]), engine_changed)
	var gender_changed := func(value: String):
		_voice_config_debug("gender changed from=%s to=%s engine=%s" % [String(state["gender"]), value, String(state["engine"])])
		state["gender"] = value
		refresh_voice_controls.call(false)
	gender_switch = _book_gender_switch(left, String(state["gender"]), gender_changed, _voice_gender_disabled_options(String(state["engine"])))
	refresh_voice_controls.call(true)
	_warm_up_voice_engine(String(state["engine"]), "editor_open")
	_book_control_row(left, "音色", voice)
	voice.item_selected.connect(func(item_index: int):
		_voice_config_debug("voice selected engine=%s gender=%s index=%d voice=%s" % [String(state["engine"]), String(state["gender"]), item_index, _voice_config_voice_debug(_book_voice_selected(voice))])
	)
	left.add_child(_book_section_label("试听文本"))
	var status := _book_label("", 11, BOOK_MUTED, true)
	left.add_child(status)
	var preview_text := _book_voice_preview_text(left)

	right.add_child(_book_section_label("播报参数"))
	var speed := _book_slider(right, "语速", float(data["speed"]), 0.50, 1.50, 0.01)
	var pitch := _book_slider(right, "音调", float(data.get("pitch", "1.00")), 0.50, 1.50, 0.01)
	var volume := _book_slider(right, "音量", float(data.get("volume", "1.00")), 0.00, 1.00, 0.01)
	var enabled_box: CheckBox = null
	var active_box: CheckBox = null
	if is_editing_existing:
		var state_boxes := _book_voice_state_row(right, bool(data.get("enabled", true)), bool(data.get("active", false)))
		enabled_box = state_boxes["enabled"] as CheckBox
		active_box = state_boxes["active"] as CheckBox
		enabled_box.toggled.connect(func(pressed: bool):
			if not pressed and active_box != null:
				active_box.button_pressed = false
		)
		active_box.toggled.connect(func(pressed: bool):
			if pressed and enabled_box != null and not enabled_box.button_pressed:
				enabled_box.button_pressed = true
		)
	right.add_child(_spacer())
	var actions := _book_voice_editor_action_row(right)
	var preview_button := _book_icon_button(_werewolf_action_path("speaker"), "试听")
	preview_button.pressed.connect(func():
		_play_click()
		var selected_voice := _book_voice_selected(voice)
		_voice_config_debug("preview pressed engine=%s gender=%s voice=%s speed=%s pitch=%s volume=%s" % [String(state["engine"]), String(state["gender"]), _voice_config_voice_debug(selected_voice), _slider_value_text(speed), _slider_value_text(pitch), _slider_value_text(volume)])
		_warm_up_voice_engine(String(state["engine"]), "preview")
		_preview_voice_config(String(state["engine"]), selected_voice, _slider_value_text(speed), _slider_value_text(pitch), _slider_value_text(volume), status, preview_button, preview_text)
	)
	if index >= 0:
		actions.add_child(_book_button("删除", false, func(): _delete_voice_config(index), true))
	actions.add_child(preview_button)
	actions.add_child(_book_button("保存", true, func():
		_voice_config_debug("save pressed index=%d engine=%s gender=%s voice=%s" % [index, String(state["engine"]), String(state["gender"]), _voice_config_voice_debug(_book_voice_selected(voice))])
		var saved_enabled := enabled_box.button_pressed if enabled_box != null else true
		var saved_active := active_box.button_pressed if active_box != null else false
		_save_voice_config(index, name.text, String(state["engine"]), String(state["gender"]), _book_voice_selected(voice), _slider_value_text(speed), _slider_value_text(pitch), _slider_value_text(volume), saved_enabled, saved_active)
	))


func _voice_editor_popup_size(is_editing_existing: bool) -> Vector2:
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		viewport_size = Vector2(1280, 720)
	var width := minf(maxf(940.0, viewport_size.x * 0.78), maxf(760.0, viewport_size.x - 48.0))
	var page_frame_height := 86.0 + 82.0 + 24.0
	var left_content_height := 28.0 + 32.0 * 4.0 + 28.0 + 16.0 + 62.0 + 6.0 * 6.0
	var right_content_height := 28.0 + 36.0 * 3.0 + 36.0 + 6.0 * 4.0
	if is_editing_existing:
		right_content_height += 32.0 + 6.0
	var required_height := maxf(left_content_height, right_content_height) + page_frame_height + 18.0
	var height := minf(maxf(500.0, required_height), maxf(460.0, viewport_size.y - 44.0))
	return Vector2(width, height)


func _book_voice_editor_action_row(parent: VBoxContainer) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 7)
	parent.add_child(row)
	return row


func _book_checkbox_line(parent: VBoxContainer, title: String, value: bool, text: String = "启用", label_width: float = 0.0) -> CheckBox:
	var checkbox := CheckBox.new()
	checkbox.text = text
	checkbox.button_pressed = value
	checkbox.focus_mode = Control.FOCUS_NONE
	checkbox.custom_minimum_size = Vector2(0, 32)
	_style_book_checkbox(checkbox)
	_book_control_row(parent, title, checkbox, "", 0.0, label_width)
	return checkbox


func _book_voice_state_row(parent: VBoxContainer, enabled: bool, active: bool) -> Dictionary:
	var group := HBoxContainer.new()
	group.add_theme_constant_override("separation", 12)
	var enabled_box := _book_inline_checkbox("启用", enabled)
	var active_box := _book_inline_checkbox("设为默认", active)
	group.add_child(enabled_box)
	group.add_child(active_box)
	_book_control_row(parent, "状态", group)
	return {
		"enabled": enabled_box,
		"active": active_box,
	}


func _book_inline_checkbox(text: String, value: bool) -> CheckBox:
	var checkbox := CheckBox.new()
	checkbox.text = text
	checkbox.button_pressed = value
	checkbox.focus_mode = Control.FOCUS_NONE
	checkbox.custom_minimum_size = Vector2(104, 32)
	checkbox.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_style_book_checkbox(checkbox)
	return checkbox


func _book_voice_preview_text(parent: VBoxContainer) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(0, 62)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("normal_font_size", _ui_font_size(10))
	label.add_theme_color_override("default_color", BOOK_MUTED)
	parent.add_child(label)
	return label


func _book_voice_engine_dropdown(parent: VBoxContainer, selected_engine: String, changed: Callable = Callable()) -> OptionButton:
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(0, 32)
	option.focus_mode = Control.FOCUS_NONE
	_style_book_option(option)
	var selected_index := 0
	var normalized := _voice_supported_engine_or_default(selected_engine)
	var options := _voice_engine_options()
	for item in options:
		if not (item is Dictionary):
			continue
		var data: Dictionary = item
		var id := String(data.get("id", ""))
		option.add_item(String(data.get("label", id)))
		var item_index := option.get_item_count() - 1
		option.set_item_metadata(item_index, id)
		if id == normalized:
			selected_index = item_index
	option.select(selected_index)
	option.item_selected.connect(func(item_index: int):
		var id := String(option.get_item_metadata(item_index))
		if changed.is_valid():
			changed.call(id)
	)
	_book_control_row(parent, "引擎", option)
	return option


func _voice_engine_options(available_only: bool = false) -> Array:
	_sync_voice_catalog_runtime()
	return _tts_voice_catalog.engine_options(available_only)


func _voice_known_engine_ids() -> Array:
	return _tts_voice_catalog.known_engine_ids()


func _voice_supported_engine_or_default(engine: String, available_only: bool = false) -> String:
	_sync_voice_catalog_runtime()
	return _tts_voice_catalog.supported_engine_or_default(engine, available_only)


func _voice_engine_available(engine: String) -> bool:
	if _tts_runtime == null:
		_setup_tts_runtime()
	_sync_voice_catalog_runtime()
	return _tts_voice_catalog.engine_available(engine)


func _book_gender_switch(parent: VBoxContainer, selected_gender: String, changed: Callable = Callable(), disabled_values: Array = []) -> CheckButton:
	var button := CheckButton.new()
	button.custom_minimum_size = Vector2(112, 32)
	button.focus_mode = Control.FOCUS_NONE
	_style_book_gender_switch(button)
	_book_gender_switch_update(button, selected_gender, disabled_values)
	button.toggled.connect(func(pressed: bool):
		var disabled: Array = button.get_meta("disabled_values", [])
		var value := "男声" if pressed else "女声"
		if disabled.has(value):
			var available_gender := _opposite_voice_gender(value)
			_book_gender_switch_update(button, available_gender, disabled)
			if changed.is_valid():
				changed.call(available_gender)
			return
		_book_gender_switch_update(button, value, disabled)
		if changed.is_valid():
			changed.call(value)
	)
	_book_control_row(parent, "性别", button, "", 112)
	return button


func _style_book_gender_switch(button: CheckButton) -> void:
	button.add_theme_font_size_override("font_size", _ui_font_size(12))
	button.add_theme_color_override("font_color", BOOK_TEXT)
	button.add_theme_color_override("font_hover_color", BOOK_TEXT)
	button.add_theme_color_override("font_pressed_color", BOOK_TEXT)
	button.add_theme_color_override("font_disabled_color", Color(0.48, 0.38, 0.26, 0.58))


func _book_gender_switch_update(button: CheckButton, selected_gender: String, disabled_values: Array = []) -> void:
	if button == null:
		return
	var gender := "男声" if selected_gender == "男声" else "女声"
	if disabled_values.has(gender):
		gender = _first_available_gender_from_disabled(disabled_values)
	button.set_meta("disabled_values", disabled_values.duplicate())
	button.set_pressed_no_signal(gender == "男声")
	button.text = gender
	button.tooltip_text = "切换男声/女声"
	button.disabled = disabled_values.size() > 0


func _first_available_gender_from_disabled(disabled_values: Array) -> String:
	for gender in ["女声", "男声"]:
		if not disabled_values.has(gender):
			return gender
	return "女声"


func _opposite_voice_gender(gender: String) -> String:
	return "女声" if gender == "男声" else "男声"



func _book_radio_group(parent: VBoxContainer, title: String, options: Array, selected_value: String, changed: Callable = Callable(), disabled_values: Array = []) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 32)
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)
	var label := _book_form_label(title)
	label.custom_minimum_size = Vector2(76, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	for option_data in options:
		if not (option_data is Dictionary):
			continue
		var option: Dictionary = option_data
		var id := String(option.get("id", ""))
		var button := Button.new()
		button.set_meta("radio_id", id)
		button.set_meta("radio_label", String(option.get("label", id)))
		button.toggle_mode = true
		button.button_pressed = id == selected_value
		button.disabled = disabled_values.has(id)
		button.custom_minimum_size = Vector2(92, 30)
		button.focus_mode = Control.FOCUS_NONE
		_style_book_radio_button(button)
		button.pressed.connect(func():
			if button.disabled:
				return
			_book_radio_group_select(row, id)
			if changed.is_valid():
				changed.call(id)
		)
		row.add_child(button)
	_book_radio_group_refresh(row)
	return row



func _style_book_radio_button(button: Button) -> void:
	var empty := StyleBoxEmpty.new()
	button.add_theme_stylebox_override("normal", empty)
	button.add_theme_stylebox_override("hover", empty)
	button.add_theme_stylebox_override("pressed", empty)
	button.add_theme_stylebox_override("disabled", empty)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", BOOK_TEXT)
	button.add_theme_color_override("font_hover_color", BOOK_TEXT)
	button.add_theme_color_override("font_pressed_color", BOOK_TEXT)
	button.add_theme_color_override("font_disabled_color", Color(0.48, 0.38, 0.26, 0.58))
	button.add_theme_font_size_override("font_size", _ui_font_size(12))



func _book_icon_button(icon_path: String, tooltip: String) -> Button:
	var button := Button.new()
	button.tooltip_text = tooltip
	button.custom_minimum_size = Vector2(46, 36)
	button.focus_mode = Control.FOCUS_NONE
	button.icon = _texture(icon_path)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 28)
	_style_book_button(button, true)
	return button



func _book_radio_group_select(row: HBoxContainer, selected_value: String) -> void:
	for child in row.get_children():
		var button := child as Button
		if button == null or not button.has_meta("radio_id"):
			continue
		button.button_pressed = String(button.get_meta("radio_id")) == selected_value
	_book_radio_group_refresh(row)



func _book_radio_group_set_disabled(row: HBoxContainer, disabled_values: Array, selected_value: String) -> void:
	for child in row.get_children():
		var button := child as Button
		if button == null or not button.has_meta("radio_id"):
			continue
		var id := String(button.get_meta("radio_id"))
		button.disabled = disabled_values.has(id)
		button.button_pressed = id == selected_value and not button.disabled
	_book_radio_group_refresh(row)



func _book_radio_group_refresh(row: HBoxContainer) -> void:
	for child in row.get_children():
		var button := child as Button
		if button == null or not button.has_meta("radio_id"):
			continue
		var label := String(button.get_meta("radio_label"))
		button.text = "%s %s" % ["◉" if button.button_pressed else "○", label]



func _book_voice_dropdown(engine: String, gender: String, selected_voice: String) -> OptionButton:
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(0, 32)
	option.focus_mode = Control.FOCUS_NONE
	_style_book_option(option)
	_populate_voice_dropdown(option, engine, gender, selected_voice)
	return option



func _populate_voice_dropdown(option: OptionButton, engine: String, gender: String, selected_voice: String) -> void:
	if option == null:
		return
	option.clear()
	var normalized_engine := _normalize_voice_engine(engine)
	var voices := _voice_options_for(normalized_engine, gender)
	_voice_config_debug("populate dropdown engine=%s gender=%s requested=%s available=%d" % [normalized_engine, gender, _voice_config_voice_debug(selected_voice), voices.size()])
	var selected_index := -1
	var current := selected_voice.strip_edges()
	if _voice_engine_supports_default(normalized_engine):
		option.add_item("%s默认" % _voice_engine_label(normalized_engine))
		option.set_item_metadata(0, "")
		if current == "":
			selected_index = 0
	if current != "" and not _voice_options_have(voices, current):
		option.add_item("当前 · %s" % current)
		var current_index := option.get_item_count() - 1
		option.set_item_metadata(current_index, current)
		selected_index = current_index
	var seen := {}
	for item in voices:
		if not (item is Dictionary):
			continue
		var id := String((item as Dictionary).get("id", "")).strip_edges()
		if id == "" or seen.has(id):
			continue
		seen[id] = true
		var label := _voice_dropdown_label(_normalize_voice_engine(engine), id, String((item as Dictionary).get("name", id)))
		option.add_item(label)
		var item_index := option.get_item_count() - 1
		option.set_item_metadata(item_index, id)
		if selected_index < 0 and current != "" and id == current:
			selected_index = item_index
	if option.get_item_count() == 0:
		option.add_item("未找到音色")
		option.set_item_metadata(0, "")
		selected_index = 0
	option.select(maxi(0, selected_index))
	_voice_config_debug("populate dropdown done engine=%s selected_index=%d selected=%s item_count=%d" % [normalized_engine, option.selected, _voice_config_voice_debug(_book_voice_selected(option)), option.get_item_count()])



func _voice_options_for(engine: String, gender: String) -> Array:
	_sync_voice_catalog_runtime()
	return _tts_voice_catalog.voice_options_for(engine, gender)


func _voice_external_engine_ids() -> Array:
	return _tts_voice_catalog.external_engine_ids()


func _voice_engine_supports_default(engine: String) -> bool:
	return _tts_voice_catalog.engine_supports_default(engine)



func _voice_gender_disabled_options(engine: String) -> Array:
	_sync_voice_catalog_runtime()
	return _tts_voice_catalog.gender_disabled_options(engine)



func _first_available_voice_gender(engine: String) -> String:
	_sync_voice_catalog_runtime()
	return _tts_voice_catalog.first_available_gender(engine)



func _voice_dropdown_label(engine: String, voice_id: String, default_label: String) -> String:
	return _tts_voice_catalog.voice_dropdown_label(engine, voice_id, default_label)



func _kokoro_voice_number_label(voice_id: String) -> String:
	return _tts_voice_catalog.kokoro_voice_number_label(voice_id)



func _voice_options_have(voices: Array, voice_id: String) -> bool:
	return _tts_voice_catalog.voice_options_have(voices, voice_id)



func _book_voice_selected(option: OptionButton) -> String:
	if option == null or option.selected < 0:
		return ""
	return String(option.get_item_metadata(option.selected)).strip_edges()



func _book_slider(parent: VBoxContainer, title: String, value: float, min_value: float, max_value: float, step: float) -> HSlider:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 36)
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var label := _book_form_label(title)
	label.custom_minimum_size = Vector2(76, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = clampf(value, min_value, max_value)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var value_label := _book_label(_slider_value_text(slider), 12, BOOK_TEXT, true, HORIZONTAL_ALIGNMENT_RIGHT)
	value_label.custom_minimum_size = Vector2(48, 0)
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(value_label)
	slider.value_changed.connect(func(_value: float):
		value_label.text = _slider_value_text(slider)
	)
	return slider



func _slider_value_text(slider: HSlider) -> String:
	return "%.2f" % slider.value



func _fill_voice_chips(list: HFlowContainer, voice_line: LineEdit, gender: String, engine: String = "system") -> void:
	for child in list.get_children():
		child.queue_free()
	var normalized_engine := _normalize_voice_engine(engine)
	var voices: Array = []
	if normalized_engine == "system":
		voices = _system_tts_voices(gender)
	elif normalized_engine == "local_kokoro":
		voices = _kokoro_tts_voices(gender)
	elif _voice_external_engine_ids().has(normalized_engine):
		voices = _external_tts_voices(normalized_engine, gender)
	else:
		list.add_child(_book_label("未知引擎，请填写 system、local_kokoro、neko_tts、voxsherpa_tts 或 multi_tts", 11, BOOK_MUTED, false))
		return
	var added := 0
	for item in voices:
		if not (item is Dictionary):
			continue
		if gender != "" and String(item.get("gender", "")) != gender:
			continue
		var id := String(item.get("id", ""))
		var label := String(item.get("name", id))
		if id == "":
			continue
		list.add_child(_voice_chip(label, id, voice_line))
		added += 1
		if added >= 12:
			break
	if added == 0:
		list.add_child(_book_label("没有匹配音色，Android 真机上点击刷新后选择", 11, BOOK_MUTED, false))



func _system_tts_voices(gender: String) -> Array:
	if _tts_runtime == null:
		_setup_tts_runtime()
	_sync_voice_catalog_runtime()
	return _tts_voice_catalog.system_tts_voices(gender)



func _external_tts_voices(engine: String, gender: String) -> Array:
	if _tts_runtime == null:
		_setup_tts_runtime()
	_sync_voice_catalog_runtime()
	return _tts_voice_catalog.external_tts_voices(engine, gender)


func _voice_language_matches_chinese(language: String) -> bool:
	return _tts_voice_catalog.language_matches_chinese(language)


func _infer_system_voice_gender(voice: Dictionary) -> String:
	return _tts_voice_catalog.infer_system_voice_gender(voice)



func _kokoro_tts_voices(gender: String) -> Array:
	_sync_voice_catalog_runtime()
	return _tts_voice_catalog.kokoro_tts_voices(gender)



func _voice_chip(label: String, voice_id: String, voice_line: LineEdit) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(0, 28)
	button.focus_mode = Control.FOCUS_NONE
	_style_book_button(button, false)
	button.pressed.connect(func():
		_play_click()
		voice_line.text = voice_id
	)
	return button



func _save_voice_config(index: int, name: String, engine: String, gender: String, voice: String, speed: String, pitch: String = "1.00", volume: String = "1.00", enabled: bool = true, active: bool = false) -> void:
	var normalized_engine := _normalize_voice_engine(engine)
	var display_name := name.strip_edges()
	if display_name == "":
		display_name = _next_voice_default_name(normalized_engine, gender, index)
	if active:
		enabled = true
	_voice_config_debug("save config index=%d name=%s engine=%s gender=%s voice=%s speed=%s pitch=%s volume=%s enabled=%s active=%s" % [index, display_name, normalized_engine, gender, _voice_config_voice_debug(voice), speed, pitch, volume, str(enabled), str(active)])
	var result := _tts_voice_repository.save_profile(index, {
		"name": display_name,
		"engine": normalized_engine,
		"gender": gender.strip_edges(),
		"voice": voice.strip_edges(),
		"speed": speed.strip_edges(),
		"pitch": pitch.strip_edges(),
		"volume": volume.strip_edges(),
		"enabled": enabled,
		"active": active,
	})
	if not bool(result.get("ok", false)):
		_show_toast(String(result.get("error", "声音保存失败")), BOOK_RED)
		return
	_voice_configs = result.get("profiles", []) as Array
	_apply_voice_config_engine_services()
	_commit_state()
	_show_voice_config_page()



func _next_voice_default_name(engine: String, gender: String, edit_index: int = -1) -> String:
	return _tts_voice_repository.next_default_name(engine, gender, edit_index)



func _delete_voice_config(index: int) -> void:
	_voice_config_debug("delete config index=%d" % index)
	if index >= 0 and index < _voice_configs.size() and _voice_configs[index] is Dictionary:
		var profile: Dictionary = _voice_configs[index]
		var voice_names := [
			String(profile.get("name", "")).strip_edges(),
			String(profile.get("key", "")).strip_edges(),
		]
		var users := _bot_profiles_using_voice_names(voice_names)
		if not users.is_empty():
			_voice_config_debug("delete blocked name=%s key=%s used_by=%s" % [String(profile.get("name", "")), String(profile.get("key", "")), _bot_usage_names(users)])
			_show_toast("声音正在被机器人使用：%s，不能删除" % _bot_usage_names(users), BOOK_RED)
			return
	var result := _tts_voice_repository.delete_profile(index)
	if not bool(result.get("ok", false)):
		_show_toast(String(result.get("error", "声音删除失败")), BOOK_RED)
		return
	_voice_configs = result.get("profiles", []) as Array
	_apply_voice_config_engine_services()
	_commit_state()
	_show_voice_config_page()


func _voice_config_voice_debug(voice: String) -> String:
	var clean := voice.strip_edges()
	return "<default>" if clean == "" else clean


func _sync_voice_catalog_runtime() -> void:
	if _tts_voice_catalog != null:
		_tts_voice_catalog.set_runtime(_tts_runtime)


func _voice_config_debug(message: String) -> void:
	if OS.is_debug_build():
		print("[VoiceConfig][debug] %s" % message)


