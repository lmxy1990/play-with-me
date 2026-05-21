extends "res://scripts/pages/config/config_page_base.gd"

const DEFAULT_PLAYBACK_VOICE_CONFIG_ID := "voice_system_default"

var _device_key_visible := false
var _avatar_mask_material: ShaderMaterial


func _init() -> void:
	initial_route = "preferences"


func _show_preferences_page() -> void:
	_mode = Mode.PREFERENCES
	_clear_scene()
	_set_backdrop(_lobby_background_path(), Color(0.35, 0.24, 0.08, 0.055))
	var repository = _ensure_preference_repository()
	if repository == null:
		_show_preferences_error("偏好设置模块不可用")
		return
	var ensured: Dictionary = repository.ensure_preferences()
	if not bool(ensured.get("ok", false)):
		_show_preferences_error(String(ensured.get("error", "偏好设置初始化失败")))
		return
	_apply_preference_identity_to_runtime()
	var state: Dictionary = ensured.get("state", {})
	var avatars_result: Dictionary = repository.list_avatars()
	var avatars: Array = avatars_result.get("avatars", []) if bool(avatars_result.get("ok", false)) else []
	_build_preferences_shell(state, avatars)


func _show_preferences_error(message: String) -> void:
	var body := _preferences_page_shell("偏好设置")
	var panel := _panel(Color(0.99, 0.92, 0.72, 0.84), Color(0.62, 0.15, 0.10, 0.42), 8)
	panel.custom_minimum_size = Vector2(0, 120)
	body.add_child(panel)
	var content := _panel_body(panel, 14)
	content.add_child(_label(message, 16, RED, true))


func _build_preferences_shell(state: Dictionary, _avatars: Array) -> void:
	var body := _preferences_page_shell("偏好设置")
	var top: BoxContainer
	if get_viewport_rect().size.x < 860.0:
		top = VBoxContainer.new()
	else:
		top = HBoxContainer.new()
	top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_theme_constant_override("separation", 12)
	body.add_child(top)

	var profile := _preference_profile_panel(state)
	profile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(profile)

	var secret := _preference_secret_panel()
	secret.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(secret)

	var playback_voice := _preference_playback_voice_panel(state)
	playback_voice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(playback_voice)


func _preferences_page_shell(title: String) -> VBoxContainer:
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
	row.add_child(_small_button("返回", false, func():
		navigate_requested.emit("lobby", {})
		_show_lobby()
	))
	var label := _label(title, 19, INK, true)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	row.add_child(_stat_badge("本", "本机身份", TEAL, 96))

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	root.add_child(scroll)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	scroll.add_child(body)
	return body


func _preference_profile_panel(state: Dictionary) -> PanelContainer:
	var panel := _panel(Color(0.99, 0.92, 0.72, 0.84), Color(0.62, 0.40, 0.16, 0.22), 8)
	panel.custom_minimum_size = Vector2(0, 170)
	var margin := MarginContainer.new()
	_margin_each(margin, 14, 12, 14, 12)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	margin.add_child(row)

	var avatar_data := _current_avatar_data(String(state.get("avatar_id", "")))
	row.add_child(_preference_avatar_picker_button(avatar_data))

	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 8)
	row.add_child(form)
	form.add_child(_book_section_label("昵称"))
	var nickname := LineEdit.new()
	nickname.name = "PreferenceNicknameInput"
	nickname.text = String(state.get("nickname", ""))
	nickname.placeholder_text = "输入昵称"
	nickname.custom_minimum_size = Vector2(0, 36)
	_style_book_input(nickname)
	form.add_child(nickname)
	var meta := _book_label("头像：%s" % String(avatar_data.get("label", String(state.get("avatar_id", "")))), 12, BOOK_MUTED, true)
	form.add_child(meta)
	form.add_child(_spacer())
	var actions := _book_action_row(form)
	actions.add_child(_book_button("保存昵称", true, func():
		_save_preference_nickname(nickname.text)
	))
	return panel


func _preference_avatar_picker_button(avatar: Dictionary) -> Control:
	var holder := Control.new()
	holder.name = "PreferenceAvatarPicker"
	holder.custom_minimum_size = Vector2(112, 112)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var preview := _preference_avatar_preview(avatar, 104, true)
	preview.set_anchors_preset(Control.PRESET_FULL_RECT)
	preview.offset_left = 4
	preview.offset_top = 4
	preview.offset_right = -4
	preview.offset_bottom = -4
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(preview)

	var hit := Button.new()
	hit.name = "PreferenceAvatarPickerButton"
	hit.set_anchors_preset(Control.PRESET_FULL_RECT)
	hit.text = ""
	hit.focus_mode = Control.FOCUS_NONE
	hit.tooltip_text = "选择头像"
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_style_transparent_button(hit)
	hit.pressed.connect(func():
		_play_click()
		_show_avatar_picker_popup(String(avatar.get("id", "")))
	)
	holder.add_child(hit)
	return holder


func _preference_secret_panel() -> PanelContainer:
	var repository = _ensure_preference_repository()
	var secret_result: Dictionary = repository.get_device_private_key_view()
	var private_key := String(secret_result.get("value", "")) if bool(secret_result.get("ok", false)) else ""
	var panel := _panel(Color(0.99, 0.92, 0.72, 0.84), Color(0.62, 0.40, 0.16, 0.22), 8)
	panel.custom_minimum_size = Vector2(0, 170)
	var body := _panel_body(panel, 12)
	body.add_child(_book_section_label("设备私钥"))
	var line := LineEdit.new()
	line.name = "PreferenceDevicePrivateKey"
	line.text = private_key
	line.secret = not _device_key_visible
	line.editable = false
	line.custom_minimum_size = Vector2(0, 36)
	_style_book_input(line)
	body.add_child(line)
	body.add_child(_book_label("只读凭据，用于基础认证能力派生设备身份。", 11, BOOK_MUTED, true))
	body.add_child(_spacer())
	var actions := _book_action_row(body)
	actions.add_child(_book_button("隐藏" if _device_key_visible else "查看", false, func():
		_toggle_device_key_visible()
	))
	actions.add_child(_book_button("复制", true, func():
		_copy_device_private_key(private_key)
	))
	return panel


func _preference_playback_voice_panel(state: Dictionary) -> PanelContainer:
	var panel := _panel(Color(0.99, 0.92, 0.72, 0.84), Color(0.62, 0.40, 0.16, 0.22), 8)
	panel.custom_minimum_size = Vector2(0, 148)
	var body := _panel_body(panel, 12)
	body.add_child(_book_section_label("播放声音配置"))
	var profiles := _preference_playback_voice_profiles()
	var selected_config_id := String(state.get("playback_voice_config_id", DEFAULT_PLAYBACK_VOICE_CONFIG_ID)).strip_edges()
	if selected_config_id == "":
		selected_config_id = DEFAULT_PLAYBACK_VOICE_CONFIG_ID
	var option := OptionButton.new()
	option.name = "PreferencePlaybackVoiceDropdown"
	option.custom_minimum_size = Vector2(0, 36)
	option.focus_mode = Control.FOCUS_NONE
	_style_book_option(option)
	var selected_index := 0
	for item in profiles:
		if not (item is Dictionary):
			continue
		var profile: Dictionary = item
		var config_id := _preference_voice_config_id(profile)
		option.add_item(_preference_voice_config_label(profile))
		var item_index := option.get_item_count() - 1
		option.set_item_metadata(item_index, config_id)
		if config_id == selected_config_id:
			selected_index = item_index
	if option.get_item_count() == 0:
		option.add_item("没有启用的声音配置")
		option.set_item_metadata(0, "")
		option.disabled = true
	option.select(selected_index)
	_book_control_row(body, "声音", option)
	body.add_child(_book_label("播报历史消息时使用该声音配置；具体引擎、音色和参数在声音配置页维护。", 11, BOOK_MUTED, true))
	body.add_child(_spacer())
	var actions := _book_action_row(body)
	actions.add_child(_book_button("保存声音", true, func():
		_save_preference_playback_voice_config(_selected_preference_voice_config_id(option))
	))
	return panel


func _preference_playback_voice_profiles() -> Array:
	var profiles: Array = _tts_voice_repository.list_profiles()
	if profiles.is_empty():
		_load_voice_configs_from_storage()
		profiles = _tts_voice_repository.list_profiles()
	if profiles.is_empty():
		profiles = _normalize_voice_configs(_voice_configs)
	var result: Array = []
	for item in profiles:
		if item is Dictionary and bool((item as Dictionary).get("enabled", true)):
			result.append((item as Dictionary).duplicate(true))
	return result


func _preference_voice_config_id(profile: Dictionary) -> String:
	var key := str(profile.get("key", "")).strip_edges()
	if key != "":
		return key
	var name := String(profile.get("name", "")).strip_edges()
	var engine := _normalize_voice_engine(String(profile.get("engine", "system")))
	var voice := String(profile.get("voice", "")).strip_edges()
	if name == "系统默认" and engine == "system" and voice == "":
		return DEFAULT_PLAYBACK_VOICE_CONFIG_ID
	var raw_id := str(profile.get("id", "")).strip_edges()
	if raw_id.is_valid_int() and int(raw_id) > 0:
		return "voice_config_%d" % int(raw_id)
	return "voice_config_0"


func _preference_voice_config_label(profile: Dictionary) -> String:
	var name := String(profile.get("name", "")).strip_edges()
	if name == "":
		name = "未命名声音"
	var engine := _tts_voice_catalog.engine_label(String(profile.get("engine", "system")))
	var voice := String(profile.get("voice", "")).strip_edges()
	var voice_text := "默认音色" if voice == "" else voice
	return "%s · %s · %s" % [name, engine, voice_text]


func _selected_preference_voice_config_id(option: OptionButton) -> String:
	if option == null or option.get_item_count() <= 0 or option.selected < 0:
		return ""
	return String(option.get_item_metadata(option.selected)).strip_edges()


func _show_avatar_picker_popup(selected_id: String) -> void:
	var repository = _ensure_preference_repository()
	if repository == null:
		_show_toast("偏好设置模块不可用", BOOK_RED)
		return
	var avatars_result: Dictionary = repository.list_avatars()
	if not bool(avatars_result.get("ok", false)):
		_show_toast(String(avatars_result.get("error", "头像列表读取失败")), BOOK_RED)
		return
	var avatars: Array = avatars_result.get("avatars", [])
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		viewport_size = Vector2(1280, 720)
	var popup_size := Vector2(
		minf(860.0, maxf(340.0, viewport_size.x - 36.0)),
		minf(580.0, maxf(360.0, viewport_size.y - 48.0))
	)
	var card := _overlay_card("选择头像", popup_size)
	card.name = "PreferenceAvatarPickerPopup"
	var body := card.find_child("Body", true, false) as VBoxContainer
	if body == null:
		return

	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", 8)
	body.add_child(meta)
	var title := _book_section_label("默认头像")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.add_child(title)
	meta.add_child(_stat_badge("数", "%d/24" % avatars.size(), GOLD, 74))

	var scroll := ScrollContainer.new()
	scroll.name = "PreferenceAvatarPickerScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	body.add_child(scroll)

	var grid := GridContainer.new()
	grid.name = "PreferenceAvatarGrid"
	grid.columns = _avatar_picker_columns(popup_size.x)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	for item in avatars:
		if item is Dictionary:
			var avatar: Dictionary = item
			grid.add_child(_preference_avatar_card(avatar, String(avatar.get("id", "")) == selected_id))


func _avatar_picker_columns(width: float) -> int:
	return maxi(2, mini(5, int((width - 72.0) / 134.0)))


func _preference_avatar_card(avatar: Dictionary, selected: bool) -> Control:
	var card := Control.new()
	card.name = "PreferenceAvatar_%s" % String(avatar.get("id", "avatar"))
	card.custom_minimum_size = Vector2(124, 142)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.clip_contents = false
	var border := BOOK_GOLD if selected else Color(0.62, 0.40, 0.16, 0.22)
	var bg := Color(1.0, 0.94, 0.75, 0.94) if selected else Color(0.99, 0.92, 0.72, 0.78)
	var panel := _panel(bg, border, 8)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(panel)
	var body := VBoxContainer.new()
	body.set_anchors_preset(Control.PRESET_FULL_RECT)
	body.add_theme_constant_override("separation", 5)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(body)
	var top_margin := MarginContainer.new()
	_margin_each(top_margin, 8, 9, 8, 0)
	top_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(top_margin)
	top_margin.add_child(_preference_avatar_preview(avatar, 70, selected))
	var label := _book_label(String(avatar.get("label", "")), 12, BOOK_TEXT, true, HORIZONTAL_ALIGNMENT_CENTER)
	label.custom_minimum_size = Vector2(0, 24)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(label)
	var kind := _book_label(_avatar_kind_label(String(avatar.get("kind", ""))), 10, BOOK_MUTED, true, HORIZONTAL_ALIGNMENT_CENTER)
	kind.custom_minimum_size = Vector2(0, 20)
	kind.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(kind)
	if selected:
		var current := _book_label("当前", 10, BOOK_GOLD, true, HORIZONTAL_ALIGNMENT_CENTER)
		current.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(current)
	var hit := Button.new()
	hit.set_anchors_preset(Control.PRESET_FULL_RECT)
	hit.text = ""
	hit.focus_mode = Control.FOCUS_NONE
	hit.tooltip_text = "选择%s" % String(avatar.get("label", "头像"))
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
			_forward_avatar_picker_drag(card, float((event as InputEventScreenDrag).relative.y), drag_state)
			hit.accept_event()
		elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_forward_avatar_picker_drag(card, float((event as InputEventMouseMotion).relative.y), drag_state)
			hit.accept_event()
	)
	hit.pressed.connect(func():
		if bool(drag_state.get("dragged", false)):
			drag_state["dragged"] = false
			return
		_play_click()
		_save_preference_avatar(String(avatar.get("id", "")))
	)
	card.add_child(hit)
	return card


func _forward_avatar_picker_drag(card: Control, delta_y: float, drag_state: Dictionary) -> void:
	if absf(delta_y) <= 0.0:
		return
	drag_state["distance"] = float(drag_state.get("distance", 0.0)) + absf(delta_y)
	if float(drag_state.get("distance", 0.0)) >= 8.0:
		drag_state["dragged"] = true
	var scroll := _avatar_picker_parent_scroll_container(card)
	if scroll == null:
		return
	scroll.scroll_vertical = maxi(0, scroll.scroll_vertical - int(round(delta_y)))


func _avatar_picker_parent_scroll_container(control: Control) -> ScrollContainer:
	var node := control.get_parent()
	while node != null:
		if node is ScrollContainer:
			return node as ScrollContainer
		node = node.get_parent()
	return null


func _preference_avatar_preview(avatar: Dictionary, size_px: int, selected: bool = false) -> Control:
	var holder := PanelContainer.new()
	holder.custom_minimum_size = Vector2(size_px, size_px)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var border := BOOK_GOLD if selected else Color(0.52, 0.28, 0.08, 0.38)
	holder.add_theme_stylebox_override("panel", _style_box(_avatar_color(String(avatar.get("id", ""))), border, 999, 2 if selected else 1))
	var margin := MarginContainer.new()
	_margin_each(margin, 4, 4, 4, 4)
	holder.add_child(margin)
	var avatar_path := String(avatar.get("path", "")).strip_edges()
	var texture: Texture2D = null
	if avatar_path != "" and ResourceLoader.exists(avatar_path):
		texture = _texture(avatar_path)
	if texture != null:
		var image := TextureRect.new()
		image.texture = texture
		image.custom_minimum_size = Vector2(maxi(1, size_px - 8), maxi(1, size_px - 8))
		image.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		image.size_flags_vertical = Control.SIZE_EXPAND_FILL
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.material = _avatar_circle_mask_material()
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.add_child(image)
	else:
		var text := _avatar_short_label(avatar)
		var label := _book_label(text, maxi(16, int(size_px / 3.0)), Color(0.18, 0.10, 0.04), true, HORIZONTAL_ALIGNMENT_CENTER)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.add_child(label)
	return holder


func _avatar_circle_mask_material() -> ShaderMaterial:
	if _avatar_mask_material != null:
		return _avatar_mask_material
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;

void fragment() {
	vec4 tex = texture(TEXTURE, UV) * COLOR;
	float dist = length(UV - vec2(0.5)) * 2.0;
	float edge = max(fwidth(dist) * 1.5, 0.004);
	tex.a *= 1.0 - smoothstep(1.0 - edge, 1.0, dist);
	COLOR = tex;
}
"""
	_avatar_mask_material = ShaderMaterial.new()
	_avatar_mask_material.shader = shader
	return _avatar_mask_material


func _current_avatar_data(avatar_id: String) -> Dictionary:
	var repository = _ensure_preference_repository()
	if repository == null:
		return {"id": avatar_id, "label": avatar_id, "kind": "", "path": ""}
	var avatars_result: Dictionary = repository.list_avatars()
	if not bool(avatars_result.get("ok", false)):
		return {"id": avatar_id, "label": avatar_id, "kind": "", "path": ""}
	for item in avatars_result.get("avatars", []):
		if item is Dictionary and String((item as Dictionary).get("id", "")) == avatar_id:
			return (item as Dictionary).duplicate(true)
	return {"id": avatar_id, "label": avatar_id, "kind": "", "path": ""}


func _save_preference_nickname(nickname: String) -> void:
	var repository = _ensure_preference_repository()
	if repository == null:
		_show_toast("偏好设置模块不可用", BOOK_RED)
		return
	var result: Dictionary = repository.update_nickname({"nickname": nickname})
	if not bool(result.get("ok", false)):
		_show_toast(String(result.get("error", "昵称保存失败")), BOOK_RED)
		return
	_apply_preference_identity_to_runtime()
	if _app_state != null:
		_app_state.local_nickname = _local_nickname
		_app_state.save()
	_show_preferences_page()
	_show_toast("昵称已保存", BOOK_GREEN)


func _save_preference_avatar(avatar_id: String) -> void:
	var repository = _ensure_preference_repository()
	if repository == null:
		_show_toast("偏好设置模块不可用", BOOK_RED)
		return
	var result: Dictionary = repository.update_avatar({"avatar_id": avatar_id})
	if not bool(result.get("ok", false)):
		_show_toast(String(result.get("error", "头像保存失败")), BOOK_RED)
		return
	_show_preferences_page()
	_show_toast("头像已保存", BOOK_GREEN)


func _save_preference_playback_voice_config(config_id: String) -> void:
	var repository = _ensure_preference_repository()
	if repository == null:
		_show_toast("偏好设置模块不可用", BOOK_RED)
		return
	var result: Dictionary = repository.update_playback_voice_config({"playback_voice_config_id": config_id})
	if not bool(result.get("ok", false)):
		_show_toast(String(result.get("error", "播放声音保存失败")), BOOK_RED)
		return
	_show_preferences_page()
	_show_toast("播放声音已保存", BOOK_GREEN)


func _toggle_device_key_visible() -> void:
	_device_key_visible = not _device_key_visible
	_show_preferences_page()


func _copy_device_private_key(private_key: String) -> void:
	if private_key.strip_edges() == "":
		_show_toast("私钥为空", BOOK_RED)
		return
	DisplayServer.clipboard_set(private_key)
	_show_toast("私钥已复制", BOOK_GREEN)


func _avatar_kind_label(kind: String) -> String:
	match kind:
		"animal":
			return "卡通动物"
		"person":
			return "卡通人物"
		_:
			return "默认头像"


func _avatar_short_label(avatar: Dictionary) -> String:
	var label := String(avatar.get("label", "")).strip_edges()
	if label == "":
		return "?"
	return label.substr(0, mini(2, label.length()))


func _avatar_color(avatar_id: String) -> Color:
	var colors := [
		Color(0.93, 0.66, 0.36, 0.92),
		Color(0.52, 0.72, 0.54, 0.92),
		Color(0.45, 0.64, 0.78, 0.92),
		Color(0.72, 0.56, 0.80, 0.92),
		Color(0.86, 0.55, 0.53, 0.92),
		Color(0.78, 0.70, 0.42, 0.92),
	]
	var hash := 0
	for i in range(avatar_id.length()):
		hash += avatar_id.unicode_at(i)
	return colors[abs(hash) % colors.size()]
