extends "res://scripts/pages/config/config_page_base.gd"

const BOT_FIELD_LABEL_WIDTH := 88.0


func _init() -> void:
	initial_route = "bot_config"


func _show_bot_config_page(edit_index: int = -2) -> void:
	_mode = Mode.BOT_CONFIG
	if OS.is_debug_build():
		print("[BotConfigPage][debug] show_page profiles=%d edit_index=%d" % [_bot_profiles.size(), edit_index])
	_clear_scene()
	_set_backdrop(_lobby_background_path(), Color(0.35, 0.24, 0.08, 0.055))
	var list := _config_page_shell("机器人配置", func():
		navigate_requested.emit("lobby", {})
		_show_lobby()
	, func(): _bot_editor(-1), true)
	if _bot_profiles.is_empty():
		list.add_child(_empty_bot_card())
	for i in range(_bot_profiles.size()):
		list.add_child(_bot_config_card(i))
	if edit_index != -2:
		_bot_editor(edit_index)


func _bot_config_card(index: int) -> Control:
	var data: Dictionary = _bot_profiles[index]
	var card := Control.new()
	card.custom_minimum_size = Vector2(0, 150)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.clip_contents = false

	var panel := _panel(Color(0.99, 0.92, 0.72, 0.84), Color(0.62, 0.40, 0.16, 0.22), 8)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(panel)
	var body := _panel_body(panel, 9)
	body.add_theme_constant_override("separation", 6)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	body.add_child(top)
	var name := _label(String(data.get("name", "未命名机器人")), 16, INK, true)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name)
	if not bool(data.get("enabled", true)):
		top.add_child(_stat_badge("停", "停用", MUTED, 62))
	top.add_child(_stat_badge("忆", _bot_memory_badge(data), TEAL, 104))

	var description := String(data.get("description", "")).strip_edges()
	if description == "":
		description = "未填写描述"
	body.add_child(_label(description, 11, MUTED))

	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", 8)
	body.add_child(meta)
	meta.add_child(_room_meta(_bot_model_label(data), GOLD))
	meta.add_child(_room_meta(_bot_voice_label(data), TEAL))
	body.add_child(_config_card_hint("点击编辑"))
	_add_config_card_hit(card, func(): _show_bot_config_page(index))

	var memory_button := _small_button("记忆", false, func(): _show_bot_memory_page(index))
	memory_button.name = "MemoryButton"
	memory_button.anchor_left = 1.0
	memory_button.anchor_right = 1.0
	memory_button.anchor_top = 1.0
	memory_button.anchor_bottom = 1.0
	memory_button.offset_left = -104
	memory_button.offset_right = -10
	memory_button.offset_top = -46
	memory_button.offset_bottom = -10
	card.add_child(memory_button)
	return card


func _empty_bot_card() -> PanelContainer:
	var card := _panel(Color(0.99, 0.92, 0.72, 0.70), Color(0.62, 0.40, 0.16, 0.20), 8)
	card.custom_minimum_size = Vector2(0, 116)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body := _panel_body(card, 12)
	body.add_child(_label("还没有机器人配置", 16, INK, true))
	body.add_child(_label("点击右上角新增，创建可供房间选择的机器人档案。", 12, MUTED))
	return card


func _bot_editor(index: int) -> void:
	var is_edit := index >= 0 and index < _bot_profiles.size()
	var default_model_name := _default_bot_model_name()
	var data := {
		"name": _bot_name_from_model_name(default_model_name, index),
		"description": "",
		"persona": "",
		"model": default_model_name,
		"voice": _default_bot_voice_name(),
		"enabled": true,
		"memory": _bot_profile_repository.normalize_memory({}),
	}
	if is_edit:
		data = _bot_profiles[index].duplicate(true)
	if OS.is_debug_build():
		print("[BotConfigPage][debug] open_editor index=%d edit=%s id=%s name=%s model=%s voice=%s persona_chars=%d enabled=%s" % [
			index,
			str(is_edit),
			String(data.get("id", "")),
			String(data.get("name", "")),
			String(data.get("model", "")),
			String(data.get("voice", "")),
			String(data.get("persona", "")).length(),
			str(bool(data.get("enabled", true))),
		])

	var popup := _book_popup("", Vector2(900, 520), func(): _show_bot_config_page())
	var left := popup["left"] as VBoxContainer
	var right := popup["right"] as VBoxContainer
	left.add_theme_constant_override("separation", 6)
	right.add_theme_constant_override("separation", 6)

	left.add_child(_book_section_label("基础信息"))
	var initial_model_name := String(data.get("model", default_model_name))
	var name := _book_compact_line(left, "名称", _bot_name_for_save(index, initial_model_name, String(data.get("name", ""))), false, "", 0.0, BOT_FIELD_LABEL_WIDTH)
	name.name = "BotProfileNameLine"
	name.placeholder_text = _bot_name_from_model_name(initial_model_name, index)
	var auto_name_state := {"value": name.text}
	var description := _book_text_area(left, "描述", String(data.get("description", "")), 76.0)
	var enabled := _book_bot_checkbox(left, "状态", bool(data.get("enabled", true)), "启用", BOT_FIELD_LABEL_WIDTH)

	right.add_child(_book_section_label("能力引用"))
	var model := _book_bot_option(right, "模型", _model_name_options(), String(data.get("model", "")), BOT_FIELD_LABEL_WIDTH)
	var voice := _book_bot_option(right, "声音", _voice_name_options(), String(data.get("voice", "")), BOT_FIELD_LABEL_WIDTH)
	var persona := _book_text_area(right, "人设", String(data.get("persona", "")), 134.0)
	persona.placeholder_text = "可空。为空时只根据机器人记忆自进化；填写后作为初始人格模板。"
	model.item_selected.connect(func(_selected: int):
		var previous_auto := String(auto_name_state.get("value", ""))
		var next_auto := _bot_name_from_model_name(_option_selected_text(model), index)
		if name.text.strip_edges() == "" or name.text.strip_edges() == previous_auto:
			name.text = next_auto
		name.placeholder_text = next_auto
		auto_name_state["value"] = next_auto
	)

	right.add_child(_spacer())
	var actions := _book_action_row(right)
	if is_edit:
		actions.add_child(_book_button("删除", false, func(): _delete_bot_profile(index), true))
		actions.add_child(_book_button("记忆", false, func(): _show_bot_memory_page(index)))
	actions.add_child(_book_button("保存", true, func():
		_save_bot_profile(index, {
			"name": name.text,
			"description": description.text,
			"persona": persona.text,
			"model": _option_selected_text(model),
			"voice": _option_selected_text(voice),
			"enabled": bool(enabled.button_pressed),
		})
	))
	description.grab_focus.call_deferred()


func _show_bot_memory_page(index: int) -> void:
	if index < 0 or index >= _bot_profiles.size():
		if OS.is_debug_build():
			print("[BotConfigPage][debug] memory_page ignored invalid_index=%d profiles=%d" % [index, _bot_profiles.size()])
		return
	var data: Dictionary = _bot_profiles[index]
	var bot_id := String(data.get("id", "")).strip_edges()
	var scope_data := _bot_profile_memory_scope(data)
	var overview_result: Dictionary = _bot_facade.get_bot_memory_overview({
		"bot_id": bot_id,
		"scope": scope_data,
		"include_recent_samples": true,
		"redact_private": false,
	})
	var overview_data: Dictionary = overview_result.get("data", {}) as Dictionary
	if OS.is_debug_build():
		print("[BotConfigPage][debug] memory_page index=%d id=%s name=%s ok=%s layers=%s" % [
			index,
			bot_id,
			String(data.get("name", "")),
			str(bool(overview_result.get("ok", false))),
			JSON.stringify(overview_data.get("layer_counts", {})),
		])
	_mode = Mode.BOT_CONFIG
	_clear_scene()
	_set_backdrop(_lobby_background_path(), Color(0.35, 0.24, 0.08, 0.055))

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
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 9)
	header_margin.add_child(header_row)
	header_row.add_child(_small_button("返回", false, func(): _show_bot_config_page()))
	var title := _label("机器人记忆", 19, INK, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header_row.add_child(title)
	header_row.add_child(_small_button("刷新", false, func(): _show_bot_memory_page(index)))
	header_row.add_child(_small_button("编辑", true, func(): _show_bot_config_page(index)))

	var panel := _panel(Color(0.98, 0.90, 0.69, 0.66), Color(0.58, 0.36, 0.12, 0.24), 8)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(panel)
	var panel_body := _panel_body(panel, 12)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	panel_body.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)
	if not bool(overview_result.get("ok", false)):
		content.add_child(_bot_memory_empty_block(String(overview_result.get("error", "记忆读取失败"))))
		return
	content.add_child(_bot_memory_overview_block(data, overview_data))
	for layer in _bot_memory_layers():
		if layer is Dictionary:
			content.add_child(_bot_memory_layer_block(data, layer as Dictionary))
	content.add_child(_bot_memory_reports_block(data))


func _bot_memory_panel(index: int) -> void:
	_show_bot_memory_page(index)


func _save_bot_profile(index: int, request: Dictionary) -> void:
	var save_request := request.duplicate(true)
	var selected_model_name := String(save_request.get("model", "")).strip_edges()
	save_request["name"] = _bot_name_for_save(index, selected_model_name, String(save_request.get("name", "")))
	if OS.is_debug_build():
		print("[BotConfigPage][debug] save_profile request index=%d name=%s model=%s voice=%s persona_chars=%d enabled=%s" % [
			index,
			String(save_request.get("name", "")).strip_edges(),
			String(save_request.get("model", "")).strip_edges(),
			String(save_request.get("voice", "")).strip_edges(),
			String(save_request.get("persona", "")).length(),
			str(bool(save_request.get("enabled", true))),
		])
	var result: Dictionary
	if index >= 0 and index < _bot_profiles.size() and _bot_profiles[index] is Dictionary:
		var update_request: Dictionary = save_request.duplicate(true)
		update_request["bot_id"] = String((_bot_profiles[index] as Dictionary).get("id", ""))
		result = _bot_facade.update_bot_profile(update_request)
	else:
		var create_request: Dictionary = save_request.duplicate(true)
		create_request["display_name"] = String(save_request.get("name", ""))
		create_request["initial_persona"] = {"content": String(save_request.get("persona", ""))}
		result = _bot_facade.create_or_get_bot_profile(create_request)
	if not bool(result.get("ok", false)):
		if OS.is_debug_build():
			print("[BotConfigPage][debug] save_profile failed index=%d error=%s" % [index, String(result.get("error", ""))])
		_show_toast(String(result.get("error", "机器人保存失败")), BOOK_RED)
		return
	_bot_profiles = _bot_profile_repository.list_profiles()
	var saved_profile: Dictionary = ((result.get("data", {}) as Dictionary).get("bot_profile", {}) as Dictionary)
	if OS.is_debug_build():
		print("[BotConfigPage][debug] save_profile ok index=%d id=%s total=%d" % [index, String(saved_profile.get("id", "")), _bot_profiles.size()])
	var init_result: Dictionary = _bot_facade.initialize_bot({
		"bot_id": String(saved_profile.get("id", "")),
		"scope": _bot_profile_memory_scope(saved_profile),
		"persona_template": {"content": String(saved_profile.get("persona", ""))},
		"reason": "bot_profile_saved",
	})
	if OS.is_debug_build():
		print("[BotConfigPage][debug] init_memory_after_save id=%s ok=%s warnings=%s" % [
			String(saved_profile.get("id", "")),
			str(bool(init_result.get("ok", false))),
			JSON.stringify(init_result.get("warnings", [])),
		])
	_commit_state()
	_show_toast("机器人已保存", BOOK_GREEN)
	_show_bot_config_page()


func _delete_bot_profile(index: int) -> void:
	var deleting_id := ""
	var deleting_name := ""
	if index >= 0 and index < _bot_profiles.size() and _bot_profiles[index] is Dictionary:
		deleting_id = String((_bot_profiles[index] as Dictionary).get("id", ""))
		deleting_name = String((_bot_profiles[index] as Dictionary).get("name", ""))
	if OS.is_debug_build():
		print("[BotConfigPage][debug] delete_profile request index=%d id=%s name=%s" % [index, deleting_id, deleting_name])
	var result: Dictionary = _bot_facade.delete_bot_profile({
		"bot_id": deleting_id,
		"delete_memory": true,
	})
	if not bool(result.get("ok", false)):
		if OS.is_debug_build():
			print("[BotConfigPage][debug] delete_profile failed index=%d error=%s" % [index, String(result.get("error", ""))])
		_show_toast(String(result.get("error", "机器人删除失败")), BOOK_RED)
		return
	_bot_profiles = _bot_profile_repository.list_profiles()
	if OS.is_debug_build():
		print("[BotConfigPage][debug] delete_profile ok index=%d total=%d" % [index, _bot_profiles.size()])
	_commit_state()
	_show_toast("机器人已删除", BOOK_GREEN)
	_show_bot_config_page()


func _book_text_area(parent: VBoxContainer, title: String, value: String, height: float) -> TextEdit:
	parent.add_child(_book_form_label(title))
	var edit := TextEdit.new()
	edit.text = value
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.custom_minimum_size = Vector2(0, height)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_book_input(edit)
	parent.add_child(edit)
	return edit


func _book_memory_readonly(title: String, value: String, height: float) -> PanelContainer:
	var panel := _panel(Color(1.0, 0.94, 0.76, 0.72), Color(0.55, 0.34, 0.13, 0.30), 7)
	panel.custom_minimum_size = Vector2(0, height)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body := _panel_body(panel, 8)
	body.add_theme_constant_override("separation", 4)
	body.add_child(_book_label(title, 12, BOOK_GOLD, true))
	var text := value.strip_edges()
	if text == "":
		text = "暂无记录"
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	body.add_child(scroll)
	var label := _book_label(text, 12, BOOK_MUTED)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.clip_text = false
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(label)
	return panel


func _bot_memory_overview_block(data: Dictionary, overview_data: Dictionary) -> PanelContainer:
	var panel := _panel(Color(1.0, 0.94, 0.76, 0.74), Color(0.55, 0.34, 0.13, 0.28), 8)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body := _panel_body(panel, 10)
	body.add_theme_constant_override("separation", 8)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	body.add_child(top)
	var name := _book_label(String(data.get("name", "机器人")), 16, BOOK_TEXT, true)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name)
	var health: Dictionary = overview_data.get("memory_health", {}) as Dictionary
	var status := String(health.get("status", "empty"))
	top.add_child(_stat_badge("态", _bot_memory_health_text(status), _bot_memory_health_color(status), 92))
	var index_status: Dictionary = overview_data.get("index_status", {}) as Dictionary
	var mode_text := String(index_status.get("retrieval_mode", "text_retrieval"))
	top.add_child(_stat_badge("检", mode_text, TEAL, 122))

	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", 8)
	body.add_child(meta)
	meta.add_child(_room_meta(_bot_model_label(data), GOLD))
	meta.add_child(_room_meta(_bot_voice_label(data), TEAL))
	meta.add_child(_room_meta("向量:%s" % ("开" if bool(index_status.get("vector_enabled", false)) else "关"), MUTED))
	meta.add_child(_room_meta("待索引:%d" % int(index_status.get("pending_embedding_count", 0)), MUTED))

	var counts: Dictionary = overview_data.get("layer_counts", {}) as Dictionary
	var count_row := HBoxContainer.new()
	count_row.add_theme_constant_override("separation", 6)
	body.add_child(count_row)
	for item in _bot_memory_layers_with_profile():
		if item is Dictionary:
			var layer: Dictionary = item
			count_row.add_child(_stat_badge(
				String(layer.get("short", "")),
				"%d" % int(counts.get(String(layer.get("type", "")), 0)),
				layer.get("color", TEAL),
				64
			))
	return panel


func _bot_memory_layer_block(data: Dictionary, layer: Dictionary) -> PanelContainer:
	var memory_type := String(layer.get("type", ""))
	var bot_id := String(data.get("id", "")).strip_edges()
	var list_result: Dictionary = _bot_facade.list_bot_memory_records({
		"bot_id": bot_id,
		"scope": _bot_profile_memory_scope(data),
		"memory_type": memory_type,
		"limit": 12,
		"offset": 0,
		"redact_private": false,
	})
	var list_data: Dictionary = list_result.get("data", {}) as Dictionary
	var items: Array = list_data.get("items", []) as Array
	var total := int(list_data.get("total", 0))
	var panel := _panel(Color(1.0, 0.94, 0.76, 0.70), Color(0.55, 0.34, 0.13, 0.26), 8)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body := _panel_body(panel, 10)
	body.add_theme_constant_override("separation", 8)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	body.add_child(top)
	var title := _book_label(String(layer.get("title", memory_type)), 14, BOOK_TEXT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(_stat_badge(String(layer.get("short", "")), "%d" % total, layer.get("color", TEAL), 70))
	if not bool(list_result.get("ok", false)):
		body.add_child(_book_label(String(list_result.get("error", "读取失败")), 12, BOOK_RED))
		return panel
	if items.is_empty():
		body.add_child(_book_label("暂无记录", 12, BOOK_MUTED))
		return panel
	for item in items:
		if item is Dictionary:
			body.add_child(_bot_memory_record_row(item as Dictionary, layer))
	return panel


func _bot_memory_record_row(record: Dictionary, layer: Dictionary) -> PanelContainer:
	var panel := _panel(Color(0.98, 0.90, 0.69, 0.62), Color(0.50, 0.30, 0.11, 0.20), 7)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body := _panel_body(panel, 8)
	body.add_theme_constant_override("separation", 5)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	body.add_child(top)
	top.add_child(_room_meta(String(record.get("status", "active")), layer.get("color", TEAL)))
	var subject := String(record.get("subject_id", "")).strip_edges()
	if subject != "":
		top.add_child(_room_meta(subject, MUTED))
	top.add_child(_room_meta("重要 %.2f" % float(record.get("importance", 0.0)), GOLD))
	top.add_child(_room_meta("置信 %.2f" % float(record.get("confidence", 0.0)), MUTED))
	var content := String(record.get("content", record.get("content_preview", ""))).strip_edges()
	if content == "":
		content = String(record.get("content_preview", "")).strip_edges()
	if content == "":
		content = "暂无内容"
	var label := _book_label(content, 12, BOOK_TEXT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(label)
	return panel


func _bot_memory_reports_block(data: Dictionary) -> PanelContainer:
	var reports_result: Dictionary = _bot_facade.get_bot_memory_reports({
		"bot_id": String(data.get("id", "")),
		"scope": _bot_profile_memory_scope(data),
		"report_types": ["context_build", "memory_update", "maintenance", "index"],
		"limit": 8,
		"redact_private": true,
	})
	var reports_data: Dictionary = reports_result.get("data", {}) as Dictionary
	var latest: Dictionary = reports_data.get("latest", {}) as Dictionary
	var index_status: Dictionary = latest.get("index", {}) as Dictionary
	var update_report: Dictionary = latest.get("memory_update", {}) as Dictionary
	var context_report: Dictionary = latest.get("context_build", {}) as Dictionary
	var panel := _panel(Color(1.0, 0.94, 0.76, 0.70), Color(0.55, 0.34, 0.13, 0.26), 8)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body := _panel_body(panel, 10)
	body.add_theme_constant_override("separation", 8)
	body.add_child(_book_section_label("调试报告"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	body.add_child(row)
	row.add_child(_stat_badge("检", String(index_status.get("retrieval_mode", "text_retrieval")), TEAL, 122))
	row.add_child(_stat_badge("向", "开" if bool(index_status.get("vector_enabled", false)) else "关", MUTED, 64))
	row.add_child(_stat_badge("E", "%d/%d" % [
		int(index_status.get("ready_embedding_count", 0)),
		int(index_status.get("required_embedding_count", 0)),
	], GOLD, 86))
	row.add_child(_stat_badge("待", "%d" % int(index_status.get("pending_embedding_count", 0)), GOLD, 64))
	var backend_row := HFlowContainer.new()
	backend_row.add_theme_constant_override("separation", 8)
	body.add_child(backend_row)
	backend_row.add_child(_room_meta("后端:%s" % String(index_status.get("vector_backend", "none")), TEAL))
	backend_row.add_child(_room_meta("模型:%s" % String(index_status.get("embedding_model", "none")), GOLD))
	backend_row.add_child(_room_meta("native sqlite:%s" % ("开" if bool(index_status.get("native_sqlite_vec_enabled", false)) else "关"), MUTED))
	backend_row.add_child(_room_meta("native hnsw:%s" % ("开" if bool(index_status.get("native_hnswlib_enabled", false)) else "关"), MUTED))
	var graph_row := HFlowContainer.new()
	graph_row.add_theme_constant_override("separation", 8)
	body.add_child(graph_row)
	graph_row.add_child(_room_meta("事件向量:%d" % int(index_status.get("event_vector_count", 0)), TEAL))
	graph_row.add_child(_room_meta("语义向量:%d" % int(index_status.get("semantic_vector_count", 0)), TEAL))
	graph_row.add_child(_room_meta("图:%d/%d" % [
		int(index_status.get("hnsw_graph_nodes", 0)),
		int(index_status.get("hnsw_graph_edges", 0)),
	], MUTED))
	graph_row.add_child(_room_meta("维度:%d" % int(index_status.get("embedding_dimension", 0)), MUTED))
	var updated_layers := _array_or_empty(update_report.get("updated_layers", []))
	var retrieval_report: Dictionary = context_report.get("retrieval_report", {}) as Dictionary
	var candidate_counts: Dictionary = context_report.get("candidate_counts", retrieval_report.get("candidate_counts", {})) as Dictionary
	var selected_count := int(candidate_counts.get("selected", 0))
	body.add_child(_book_label("最近更新层: %s" % ("无" if updated_layers.is_empty() else ",".join(updated_layers)), 12, BOOK_MUTED))
	body.add_child(_book_label("最近上下文选中: %d" % selected_count, 12, BOOK_MUTED))
	return panel


func _bot_memory_empty_block(message: String) -> PanelContainer:
	var panel := _panel(Color(1.0, 0.94, 0.76, 0.70), Color(0.55, 0.34, 0.13, 0.26), 8)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body := _panel_body(panel, 12)
	body.add_child(_book_label(message, 13, BOOK_RED, true))
	return panel


func _bot_profile_memory_scope(data: Dictionary) -> Dictionary:
	var bot_id := String(data.get("id", "")).strip_edges()
	return _memory_manager.scope(bot_id, "bot", bot_id, "profile", "")


func _bot_memory_layers() -> Array:
	return [
		{"type": "working", "title": "工作记忆", "short": "工", "color": TEAL},
		{"type": "relationship", "title": "关系记忆", "short": "关", "color": GOLD},
		{"type": "episodic", "title": "事件记忆", "short": "事", "color": BOOK_GREEN},
		{"type": "semantic", "title": "语义记忆", "short": "义", "color": FRESH_LILAC},
		{"type": "reflection", "title": "反思记忆", "short": "思", "color": BOOK_RED},
	]


func _bot_memory_layers_with_profile() -> Array:
	var result := [{"type": "profile", "title": "人格快照", "short": "人", "color": FRESH_LILAC}]
	for item in _bot_memory_layers():
		result.append(item)
	return result


func _bot_memory_health_text(status: String) -> String:
	match status:
		"empty":
			return "无记忆"
		"text_retrieval":
			return "文本"
		"degraded":
			return "降级"
		"ok":
			return "正常"
		_:
			return status


func _bot_memory_health_color(status: String) -> Color:
	match status:
		"empty":
			return MUTED
		"text_retrieval":
			return TEAL
		"degraded":
			return BOOK_RED
		"ok":
			return BOOK_GREEN
		_:
			return MUTED


func _array_or_empty(value) -> Array:
	if value is Array:
		return (value as Array).duplicate(true)
	return []


func _book_bot_checkbox(parent: VBoxContainer, title: String, value: bool, text: String, label_width: float) -> CheckBox:
	var checkbox := CheckBox.new()
	checkbox.text = text
	checkbox.button_pressed = value
	checkbox.focus_mode = Control.FOCUS_NONE
	checkbox.custom_minimum_size = Vector2(0, 32)
	_style_book_checkbox(checkbox)
	_book_control_row(parent, title, checkbox, "", 0.0, label_width)
	return checkbox


func _book_bot_option(parent: VBoxContainer, title: String, options: Array, selected: String, label_width: float) -> OptionButton:
	var option := OptionButton.new()
	for item in options:
		option.add_item(String(item))
	if option.item_count == 0:
		option.add_item("")
	_select_option_text(option, selected)
	_style_book_option(option)
	_book_control_row(parent, title, option, "", 0.0, label_width)
	return option


func _model_name_options() -> Array:
	var result := []
	for item in _model_configs:
		if not (item is Dictionary):
			continue
		var model := String((item as Dictionary).get("model", "")).strip_edges()
		if model == "":
			model = String((item as Dictionary).get("name", "")).strip_edges()
		if model != "":
			result.append(model)
	if result.is_empty():
		result.append("默认模型")
	return result


func _voice_name_options() -> Array:
	var result := []
	for item in _voice_configs:
		if item is Dictionary:
			var name := String((item as Dictionary).get("name", "")).strip_edges()
			if name != "":
				result.append(name)
	if result.is_empty():
		result.append("系统默认")
	return result


func _default_bot_model_name() -> String:
	var options := _model_name_options()
	return String(options[0]) if not options.is_empty() else "默认模型"


func _bot_name_from_model_name(model_name: String, edit_index: int = -1) -> String:
	var clean := model_name.strip_edges()
	if clean == "":
		clean = "默认模型"
	var existing := {}
	for i in range(_bot_profiles.size()):
		if i == edit_index:
			continue
		if _bot_profiles[i] is Dictionary:
			var name := String((_bot_profiles[i] as Dictionary).get("name", "")).strip_edges()
			if name != "":
				existing[name] = true
	if not existing.has(clean):
		return clean
	var serial := 2
	while existing.has("%s %d" % [clean, serial]):
		serial += 1
	return "%s %d" % [clean, serial]


func _bot_name_for_save(index: int, model_name: String, requested_name: String = "") -> String:
	var clean := requested_name.strip_edges()
	if clean == "":
		clean = model_name.strip_edges()
	if clean == "":
		clean = "默认模型"
	return _bot_unique_name(clean, index)


func _bot_unique_name(base_name: String, edit_index: int = -1) -> String:
	var clean := base_name.strip_edges()
	if clean == "":
		clean = "未命名机器人"
	var existing := {}
	for i in range(_bot_profiles.size()):
		if i == edit_index:
			continue
		if _bot_profiles[i] is Dictionary:
			var name := String((_bot_profiles[i] as Dictionary).get("name", "")).strip_edges()
			if name != "":
				existing[name] = true
	if not existing.has(clean):
		return clean
	var serial := 2
	while existing.has("%s %d" % [clean, serial]):
		serial += 1
	return "%s %d" % [clean, serial]


func _default_bot_voice_name() -> String:
	var options := _voice_name_options()
	return String(options[0]) if not options.is_empty() else "系统默认"


func _select_option_text(option: OptionButton, selected: String) -> void:
	var key := selected.strip_edges()
	for i in range(option.item_count):
		if option.get_item_text(i) == key:
			option.select(i)
			return
	option.select(0)


func _option_selected_text(option: OptionButton) -> String:
	if option == null or option.item_count <= 0:
		return ""
	return option.get_item_text(option.selected)


func _bot_memory_badge(data: Dictionary) -> String:
	var bot_id := String(data.get("id", "")).strip_edges()
	if bot_id != "":
		var overview_result: Dictionary = _bot_facade.get_bot_memory_overview({
			"bot_id": bot_id,
			"scope": _bot_profile_memory_scope(data),
			"redact_private": true,
		})
		if bool(overview_result.get("ok", false)):
			var overview_data: Dictionary = overview_result.get("data", {}) as Dictionary
			var counts: Dictionary = overview_data.get("layer_counts", {}) as Dictionary
			var total := 0
			for key in ["profile", "working", "relationship", "semantic", "episodic", "reflection"]:
				total += int(counts.get(key, 0))
			if total > 0:
				return "%d条" % total
	var memory: Dictionary = _bot_profile_repository.normalize_memory(data.get("memory", {}))
	for key in ["profile", "working", "long_term", "notes"]:
		if String(memory.get(key, "")).strip_edges() != "":
			return "已有记忆"
	return "自进化"


func _bot_model_label(data: Dictionary) -> String:
	var model := String(data.get("model", "")).strip_edges()
	return "模型:%s" % (model if model != "" else "默认模型")


func _bot_voice_label(data: Dictionary) -> String:
	var voice := String(data.get("voice", "")).strip_edges()
	return "声音:%s" % (voice if voice != "" else "系统默认")
