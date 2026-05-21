extends "res://scripts/pages/config/config_page_base.gd"

const ModelAdapterRegistryScript := preload("res://scripts/core/model/model_adapter_registry.gd")

var _model_test_requests := {}
var _model_test_events := {}
var _model_schema_test_passes := {}
var _model_test_capabilities := {}
var _model_detected_formt_adapters := {}
var _model_detected_reason_adapters := {}
var _active_model_editor_controls := {}
var _adapter_registry = ModelAdapterRegistryScript.new()
const CONTEXT_WINDOW_UI_RATIO := 0.7
const CONTEXT_TOKEN_LABEL := "上下文"
const MAX_CONTEXT_LABEL := "MaxContext"
const MAX_OUTPUT_TOKEN_LABEL := "MaxOutput"
const REASONING_LABEL := "Reasoning"
const FORMT_ADAPTER_AUTO := "auto"
const FORMT_ADAPTER_NONE := "none"
const FORMT_ADAPTER_OPENAI_JSON_SCHEMA := "openai_json_schema"
const FORMT_ADAPTER_OPENAI_JSON_OBJECT := "openai_json_object"
const FORMT_ADAPTER_OPENAI_TOOL_FORCED := "openai_tool_forced"
const FORMT_ADAPTER_OPENAI_TOOL_OPTIONAL := "openai_tool_optional"
const FORMT_ADAPTER_OPENAI_MIMO_TOOL := "openai_mimo_tool"
const FORMT_ADAPTER_GEMINI_JSON_SCHEMA := "gemini_json_schema"
const FORMT_ADAPTER_ANTHROPIC_TOOL := "anthropic_tool"
const FORMT_ADAPTER_OLLAMA_FORMAT_SCHEMA := "ollama_format_schema"
const REASON_ADAPTER_AUTO := "auto"
const REASON_ADAPTER_NATIVE := "native"
const REASON_ADAPTER_OPENAI_REASONING_EFFORT := "openai_reasoning_effort"
const REASON_ADAPTER_DEEPSEEK_THINKING := "deepseek_thinking"
const REASON_ADAPTER_GLM_THINKING := "glm_thinking"
const REASON_ADAPTER_ARK_THINKING := "ark_thinking"
const REASON_ADAPTER_MINIMAX_REASONING_SPLIT := "minimax_reasoning_split"
const REASON_ADAPTER_MIMO_CHAT_TEMPLATE := "mimo_chat_template"
const REASON_ADAPTER_KIMI_THINKING_CONTROL := "kimi_thinking_control"
const DEFAULT_MAX_CONTEXT_TOKEN := 262144
const DEFAULT_MAX_OUTPUT_TOKEN := 4096
const MODEL_FIELD_LABEL_WIDTH := 112.0
const MODEL_SHORT_FIELD_WIDTH := 96.0
const MODEL_TOKEN_FIELD_WIDTH := 128.0


func _init() -> void:
	initial_route = "model_config"


func _show_model_config_page(edit_index: int = -2) -> void:
	_mode = Mode.MODEL_CONFIG
	_ensure_model_test_signal()
	_clear_scene()
	_set_backdrop(_lobby_background_path(), Color(0.35, 0.24, 0.08, 0.055))
	var list := _config_page_shell("模型配置", func():
		navigate_requested.emit("lobby", {})
		_show_lobby()
	, Callable(), false, [
		{"text": "粘贴新增", "primary": false, "callback": func(): _model_paste_import_dialog()},
		{"text": "批量新增", "primary": false, "callback": func(): _model_batch_editor()},
		{"text": "新增", "primary": true, "callback": func(): _model_editor(-1)},
	])
	for i in range(_model_configs.size()):
		list.add_child(_model_config_card(i))
	if edit_index != -2:
		_model_editor(edit_index)



func _model_config_card(index: int) -> Control:
	var data: Dictionary = _model_configs[index]
	var card := Control.new()
	card.custom_minimum_size = Vector2(0, 108)
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
	var display_model := String(data.get("model", "")).strip_edges()
	if display_model == "":
		display_model = String(data.get("name", "未命名模型")).strip_edges()
	var model_label := _label(display_model, 16, INK, true)
	model_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(model_label)
	top.add_child(_stat_badge("模", String(data.get("model", "")), TEAL, 132))
	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", 8)
	body.add_child(meta)
	meta.add_child(_room_meta(_model_provider_label(String(data.get("provider", ""))), GOLD))
	meta.add_child(_room_meta(_formt_adapter_label(String(data.get("formt_adapter", FORMT_ADAPTER_AUTO))), TEAL))
	meta.add_child(_room_meta(_reason_adapter_label(String(data.get("reason_adapter", REASON_ADAPTER_AUTO)), String(data.get("provider", ""))), GOLD))
	meta.add_child(_room_meta(_max_context_label(_max_context_tokens_from_config(data)), TEAL))
	meta.add_child(_room_meta(_max_output_label(_max_output_tokens_from_config(data)), GOLD))
	if bool(data.get("reasoning", false)):
		meta.add_child(_room_meta("Reasoning", GOLD))
	var endpoint := _label(String(data.get("endpoint", "")), 11, MUTED)
	endpoint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.add_child(endpoint)
	body.add_child(_config_card_hint("点击编辑"))
	_add_config_card_hit(card, func(): _show_model_config_page(index))
	return card



func _reveal_model_delete(card: Control, index: int) -> void:
	var existing := card.get_node_or_null("DeleteButton") as Button
	if existing != null:
		existing.visible = true
		return
	var button := _small_button("删除", false, func(): _delete_model_config(index), true)
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



func _model_editor(index: int) -> void:
	var is_edit := index >= 0 and index < _model_configs.size()
	var default_max_context := DEFAULT_MAX_CONTEXT_TOKEN
	var data := {"id": 0, "provider": "openai_api", "model": "", "endpoint": _model_provider_default_endpoint("openai_api"), "memory": "", "api_key": "", "context_window_tokens": _context_tokens_from_max_context(default_max_context), "max_context": default_max_context, "max_output": DEFAULT_MAX_OUTPUT_TOKEN, "temperature": 0.6, "reasoning": false, "formt_adapter": FORMT_ADAPTER_AUTO, "reason_adapter": REASON_ADAPTER_AUTO}
	if is_edit:
		data = _model_configs[index].duplicate(true)
	var popup := _book_popup("", Vector2(980, 520), func(): _show_model_config_page())
	var left := popup["left"] as VBoxContainer
	var right := popup["right"] as VBoxContainer

	left.add_theme_constant_override("separation", 6)
	right.add_theme_constant_override("separation", 6)
	left.add_child(_book_section_label("连接"))
	if is_edit:
		var id_line := _book_compact_line(left, "ID", str(int(data.get("id", 0))), false, "", MODEL_SHORT_FIELD_WIDTH, MODEL_FIELD_LABEL_WIDTH)
		id_line.editable = false
	var provider := _book_provider_dropdown(String(data.get("provider", "")))
	_book_control_row(left, "端点类型", provider, "", 168.0, MODEL_FIELD_LABEL_WIDTH)
	var endpoint := _book_compact_line(left, "BaseUrl", String(data.get("endpoint", _model_provider_default_endpoint(_book_provider_selected(provider)))), false, "", 0.0, MODEL_FIELD_LABEL_WIDTH)
	var api_key := _book_compact_line(left, "Key", String(data.get("api_key", "")), true, "", 0.0, MODEL_FIELD_LABEL_WIDTH)
	var model_value := String(data.get("model", "")).strip_edges()
	if model_value == "":
		model_value = String(data.get("name", "")).strip_edges()
	var initial_reasoning := bool(data.get("reasoning", false))
	var reason_adapter := _book_reason_adapter_dropdown(_book_provider_selected(provider), String(data.get("reason_adapter", REASON_ADAPTER_AUTO)), model_value, initial_reasoning)
	_book_control_row(left, "思考兼容", reason_adapter, "", 168.0, MODEL_FIELD_LABEL_WIDTH)

	right.add_child(_book_section_label("模型"))
	var stored_max_context := _max_context_tokens_from_config(data, default_max_context)
	var model := _book_compact_line(right, "Model", model_value, false, "", 0.0, MODEL_FIELD_LABEL_WIDTH)
	var max_context := _book_compact_line(right, MAX_CONTEXT_LABEL, str(stored_max_context), false, "", MODEL_TOKEN_FIELD_WIDTH, MODEL_FIELD_LABEL_WIDTH)
	var max_output := _book_compact_line(right, MAX_OUTPUT_TOKEN_LABEL, str(_max_output_tokens_from_config(data)), false, "", MODEL_SHORT_FIELD_WIDTH, MODEL_FIELD_LABEL_WIDTH)
	var temperature := _book_compact_line(right, "Temperature", _format_model_temperature(float(data.get("temperature", 0.6))), false, "", MODEL_SHORT_FIELD_WIDTH, MODEL_FIELD_LABEL_WIDTH)
	var reasoning := _book_checkbox_line(right, REASONING_LABEL, bool(data.get("reasoning", false)), "启用", MODEL_FIELD_LABEL_WIDTH)
	var formt_adapter := _book_formt_adapter_dropdown(_book_provider_selected(provider), String(data.get("formt_adapter", FORMT_ADAPTER_AUTO)))
	_book_control_row(right, "结构兼容", formt_adapter, "", 168.0, MODEL_FIELD_LABEL_WIDTH)
	provider.item_selected.connect(func(_selected: int):
		if _model_endpoint_should_follow(endpoint.text):
			endpoint.text = _model_provider_default_endpoint(_book_provider_selected(provider))
		var provider_id := _book_provider_selected(provider)
		var model_id := model.text.strip_edges()
		var endpoint_value := endpoint.text.strip_edges()
		var api_key_value := api_key.text
		var reasoning_enabled := bool(reasoning.button_pressed)
		var selected_formt_adapter := _formt_adapter_selected(formt_adapter)
		if selected_formt_adapter != FORMT_ADAPTER_AUTO and not _formt_adapter_can_save(selected_formt_adapter):
			selected_formt_adapter = _model_detected_formt_adapter(provider_id, endpoint_value, api_key_value, model_id, reasoning_enabled)
		_populate_formt_adapter_dropdown(formt_adapter, provider_id, selected_formt_adapter)
		var selected_reason_adapter := _reason_adapter_selected(reason_adapter)
		if selected_reason_adapter != REASON_ADAPTER_AUTO and not _reason_adapter_can_save(reasoning_enabled, selected_reason_adapter):
			selected_reason_adapter = _model_detected_reason_adapter(provider_id, endpoint_value, api_key_value, model_id, reasoning_enabled)
		_populate_reason_adapter_dropdown(reason_adapter, provider_id, model.text, selected_reason_adapter, reasoning_enabled)
	)
	right.add_child(_spacer())
	var actions := _book_action_row(right)
	if index >= 0:
		actions.add_child(_book_button("删除", false, func(): _delete_model_config(index), true))
	var test_button: Button
	var save_button: Button
	test_button = _book_button("测试", false, func():
		_test_model_config(_book_provider_selected(provider), endpoint.text, api_key.text, model.text, bool(reasoning.button_pressed), test_button, _formt_adapter_selected(formt_adapter), formt_adapter, _reason_adapter_selected(reason_adapter), reason_adapter)
		_update_model_editor_save_state(save_button, index, model.text, _book_provider_selected(provider), endpoint.text, api_key.text, bool(reasoning.button_pressed), _formt_adapter_selected(formt_adapter), _reason_adapter_selected(reason_adapter))
	)
	actions.add_child(test_button)
	save_button = _book_button("保存", true, func():
		var model_id := model.text.strip_edges()
		var base_url := endpoint.text.strip_edges()
		if model_id == "" or base_url == "":
			_show_toast("Model 和 BaseUrl 不能为空", BOOK_RED)
			return
		var max_context_tokens := _tokens_from_context_text(max_context.text)
		var context_tokens := _context_tokens_from_max_context(max_context_tokens)
		var max_output_tokens := _positive_int_from_text(max_output.text, DEFAULT_MAX_OUTPUT_TOKEN)
		_save_model_config(index, model_id, _book_provider_selected(provider), base_url, "", api_key.text, context_tokens, max_context_tokens, max_output_tokens, _temperature_from_text(temperature.text, 0.6), bool(reasoning.button_pressed), _formt_adapter_selected(formt_adapter), _reason_adapter_selected(reason_adapter))
	)
	actions.add_child(save_button)
	test_button.set_meta("save_button", save_button)
	test_button.set_meta("provider_option", provider)
	test_button.set_meta("endpoint_line", endpoint)
	test_button.set_meta("api_key_line", api_key)
	test_button.set_meta("model_line", model)
	test_button.set_meta("reasoning_checkbox", reasoning)
	test_button.set_meta("formt_adapter_option", formt_adapter)
	test_button.set_meta("reason_adapter_option", reason_adapter)
	test_button.set_meta("edit_index", index)
	_active_model_editor_controls = {
		"save_button": save_button,
		"test_button": test_button,
		"provider_option": provider,
		"endpoint_line": endpoint,
		"api_key_line": api_key,
		"model_line": model,
		"reasoning_checkbox": reasoning,
		"formt_adapter_option": formt_adapter,
		"reason_adapter_option": reason_adapter,
		"edit_index": index,
	}
	var refresh_save_state_only := func():
		_update_model_editor_save_state(save_button, index, model.text, _book_provider_selected(provider), endpoint.text, api_key.text, bool(reasoning.button_pressed), _formt_adapter_selected(formt_adapter), _reason_adapter_selected(reason_adapter))
	var refresh_dynamic_controls := func():
		var provider_id := _book_provider_selected(provider)
		var model_id := model.text.strip_edges()
		var endpoint_value := endpoint.text.strip_edges()
		var api_key_value := api_key.text
		var reasoning_enabled := bool(reasoning.button_pressed)
		var selected_reason_adapter := _reason_adapter_selected(reason_adapter)
		if selected_reason_adapter != REASON_ADAPTER_AUTO and not _reason_adapter_can_save(reasoning_enabled, selected_reason_adapter):
			selected_reason_adapter = _model_detected_reason_adapter(provider_id, endpoint_value, api_key_value, model_id, reasoning_enabled)
		_populate_reason_adapter_dropdown(reason_adapter, provider_id, model.text, selected_reason_adapter, reasoning_enabled)
		refresh_save_state_only.call()
	model.text_changed.connect(refresh_dynamic_controls)
	endpoint.text_changed.connect(refresh_dynamic_controls)
	api_key.text_changed.connect(refresh_dynamic_controls)
	reasoning.toggled.connect(func(_pressed: bool): refresh_dynamic_controls.call())
	formt_adapter.item_selected.connect(func(_selected: int): refresh_save_state_only.call())
	reason_adapter.item_selected.connect(func(_selected: int): refresh_save_state_only.call())
	refresh_dynamic_controls.call()



func _model_paste_import_dialog() -> void:
	var popup := _book_popup("", Vector2(980, 520), func(): _show_model_config_page())
	var left := popup["left"] as VBoxContainer
	var right := popup["right"] as VBoxContainer
	left.add_theme_constant_override("separation", 8)
	right.add_theme_constant_override("separation", 8)

	left.add_child(_book_section_label("粘贴新增"))
	var text_area := TextEdit.new()
	text_area.name = "ModelPasteImportText"
	text_area.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text_area.scroll_fit_content_height = false
	text_area.custom_minimum_size = Vector2(0, 340)
	text_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_style_book_input(text_area)
	left.add_child(text_area)

	var status := _book_label("", 12, BOOK_MUTED, false)
	status.custom_minimum_size = Vector2(0, 24)
	left.add_child(status)

	right.add_child(_book_section_label("识别结果"))
	var provider_label := _model_paste_result_line(right, "端点类型", "")
	var endpoint_label := _model_paste_result_line(right, "BaseUrl", "")
	var key_label := _model_paste_result_line(right, "Key", "")
	var model_label := _model_paste_result_line(right, "模型", "")
	right.add_child(_spacer())

	var preview := func():
		var recognized := _recognize_model_paste(text_area.text)
		_model_paste_update_preview(recognized, provider_label, endpoint_label, key_label, model_label, status)
		return recognized

	text_area.text_changed.connect(func():
		preview.call()
	)

	var actions := _book_action_row(right)
	actions.add_child(_book_button("粘贴", false, func():
		text_area.text = DisplayServer.clipboard_get()
		preview.call()
	))
	actions.add_child(_book_button("识别", true, func():
		var recognized: Dictionary = preview.call()
		if not bool(recognized.get("ok", false)):
			_show_toast(String(recognized.get("error", "未识别到可用模型配置")), BOOK_RED)
			return
		_model_batch_editor(recognized)
	))
	preview.call()


func _model_paste_result_line(parent: VBoxContainer, title: String, value: String) -> Label:
	var label := _book_label(value, 12, BOOK_TEXT, false)
	label.custom_minimum_size = Vector2(0, 32)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_book_control_row(parent, title, label, "", 0.0, MODEL_FIELD_LABEL_WIDTH)
	return label


func _model_paste_update_preview(recognized: Dictionary, provider_label: Label, endpoint_label: Label, key_label: Label, model_label: Label, status: Label) -> void:
	var provider := _model_provider_label(String(recognized.get("provider", "openai_api")))
	var endpoint := String(recognized.get("endpoint", "")).strip_edges()
	var api_key := String(recognized.get("api_key", "")).strip_edges()
	var models := _string_array_from_variant(recognized.get("models", []))
	provider_label.text = provider
	endpoint_label.text = endpoint if endpoint != "" else "未识别"
	key_label.text = "已识别" if api_key != "" else "未识别"
	model_label.text = ", ".join(models.slice(0, mini(models.size(), 5))) if not models.is_empty() else "未识别"
	if models.size() > 5:
		model_label.text += " +%d" % (models.size() - 5)
	if bool(recognized.get("ok", false)):
		_book_status(status, "可导入 %d 个模型" % models.size() if not models.is_empty() else "已识别连接", BOOK_GREEN)
	else:
		_book_status(status, String(recognized.get("error", "等待粘贴内容")), BOOK_MUTED)


func _model_batch_editor(prefill: Dictionary = {}) -> void:
	var popup := _book_popup("", Vector2(1020, 520), func(): _show_model_config_page())
	var left := popup["left"] as VBoxContainer
	var right := popup["right"] as VBoxContainer
	left.add_theme_constant_override("separation", 6)
	right.add_theme_constant_override("separation", 6)

	left.add_child(_book_section_label("连接"))
	var prefill_provider := _model_provider_id(String(prefill.get("provider", "openai_api")))
	var prefill_endpoint := String(prefill.get("endpoint", "")).strip_edges()
	if prefill_endpoint == "":
		prefill_endpoint = _model_provider_default_endpoint(prefill_provider)
	var provider := _book_provider_dropdown(prefill_provider)
	_book_control_row(left, "端点类型", provider, "", 168.0, MODEL_FIELD_LABEL_WIDTH)
	var endpoint := _book_compact_line(left, "BaseUrl", prefill_endpoint, false, "", 0.0, MODEL_FIELD_LABEL_WIDTH)
	var api_key := _book_compact_line(left, "Key", String(prefill.get("api_key", "")), true, "", 0.0, MODEL_FIELD_LABEL_WIDTH)
	var max_context := _book_compact_line(left, MAX_CONTEXT_LABEL, str(DEFAULT_MAX_CONTEXT_TOKEN), false, "", MODEL_TOKEN_FIELD_WIDTH, MODEL_FIELD_LABEL_WIDTH)
	var temperature := _book_compact_line(left, "Temperature", "0.60", false, "", MODEL_SHORT_FIELD_WIDTH, MODEL_FIELD_LABEL_WIDTH)
	var reasoning := _book_checkbox_line(left, REASONING_LABEL, false, "启用", MODEL_FIELD_LABEL_WIDTH)
	provider.item_selected.connect(func(_selected: int):
		if _model_endpoint_should_follow(endpoint.text):
			endpoint.text = _model_provider_default_endpoint(_book_provider_selected(provider))
	)

	var selected_models := {}
	right.add_child(_book_section_label("模型列表"))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 330)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	right.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 3)
	scroll.add_child(list)
	_enable_catalog_drag_scroll(scroll, list)

	left.add_child(_spacer())
	var left_actions := _book_action_row(left)
	left_actions.add_child(_book_button("获取模型", false, func():
		_fetch_model_catalog(_book_provider_selected(provider), endpoint.text, api_key.text, null, list, null, "batch", selected_models)
	))
	left_actions.add_child(_book_button("测试选中", false, func():
		_test_batch_model_configs(_book_provider_selected(provider), endpoint.text, api_key.text, bool(reasoning.button_pressed), selected_models)
	))
	left_actions.add_child(_book_button("批量添加", true, func():
		_save_batch_model_configs(_book_provider_selected(provider), endpoint.text, api_key.text, max_context.text, temperature.text, bool(reasoning.button_pressed), selected_models)
	))
	var prefill_models := _model_catalog_items_from_model_ids(_string_array_from_variant(prefill.get("models", [])))
	if not prefill_models.is_empty():
		_fill_batch_model_catalog(prefill_models, list, selected_models)
		_show_toast("已识别 %d 个模型" % prefill_models.size(), BOOK_GREEN)


func _recognize_model_paste(text: String) -> Dictionary:
	var source := text.strip_edges()
	var models := _extract_models_from_paste(source)
	var endpoint := _extract_endpoint_from_paste(source)
	var api_key := _extract_api_key_from_paste(source)
	var provider := _infer_pasted_provider(source, endpoint, models)
	endpoint = _normalize_pasted_endpoint(provider, endpoint)
	if endpoint == "":
		endpoint = _model_provider_default_endpoint(provider)
	if source == "":
		return {
			"ok": false,
			"provider": provider,
			"endpoint": "",
			"api_key": "",
			"models": [],
			"error": "等待粘贴内容",
		}
	if models.is_empty() and endpoint == _model_provider_default_endpoint(provider) and api_key == "":
		return {
			"ok": false,
			"provider": provider,
			"endpoint": endpoint,
			"api_key": api_key,
			"models": [],
			"error": "未识别到 BaseUrl、Key 或模型",
		}
	return {
		"ok": true,
		"provider": provider,
		"endpoint": endpoint,
		"api_key": api_key,
		"models": models,
	}


func _extract_endpoint_from_paste(text: String) -> String:
	var json_value = _parse_json_like_text(text)
	var from_json := _endpoint_from_json_value(json_value)
	if from_json != "":
		return from_json
	var urls := _regex_group_values(text, "(?i)https?://[^\\s\"'<>，。；;]+", 0)
	if not urls.is_empty():
		return _best_endpoint_url(urls)
	var host := _first_regex_group(text, "(?im)(?:api[_\\s-]*host|base[_\\s-]*host|host|地址)\\s*[:=：]\\s*['\"]?([^'\"\\s,;]+)")
	var port := _first_regex_group(text, "(?im)(?:api[_\\s-]*(?:port|端口)|port|端口)\\s*[:=：]\\s*(\\d{2,5})")
	if port != "":
		var port_value := int(port)
		var clean_host := host.strip_edges()
		if clean_host == "":
			clean_host = "127.0.0.1"
		if clean_host.begins_with("http://") or clean_host.begins_with("https://"):
			clean_host = clean_host.replace("http://", "").replace("https://", "")
		if port_value == 11434:
			return "http://%s:%d/api" % [clean_host, port_value]
		return "http://%s:%d/v1" % [clean_host, port_value]
	return ""


func _extract_api_key_from_paste(text: String) -> String:
	var json_value = _parse_json_like_text(text)
	var from_json := _api_key_from_json_value(json_value)
	if from_json != "":
		return from_json
	var bearer := _first_regex_group(text, "(?im)authorization\\s*:\\s*bearer\\s+([^\\s\"',;]+)")
	if bearer != "":
		return _clean_pasted_secret(bearer)
	var key := _first_regex_group(text, "(?im)(?:api[_\\s-]*key|apikey|access[_\\s-]*token|token|secret|密钥|key)\\s*[:=：]\\s*['\"]?([^'\"\\s,;]+)")
	if key != "":
		return _clean_pasted_secret(key)
	return ""


func _extract_models_from_paste(text: String) -> Array:
	var models := []
	var json_value = _parse_json_like_text(text)
	_collect_models_from_json_value(json_value, "", models)
	for line in text.split("\n", false):
		var clean_line := String(line).strip_edges()
		if clean_line == "":
			continue
		var explicit := _first_regex_group(clean_line, "(?i)(?:model[_\\s-]*(?:name|id)?|models|模型)\\s*[:=：]\\s*(.+)$")
		if explicit != "":
			_collect_model_tokens(explicit, models)
		elif _looks_like_model_id(clean_line):
			_add_model_id(models, clean_line)
	for candidate in _regex_group_values(text, "(?i)\\b(?:gpt|o[1-9]|claude|gemini|deepseek|qwen|llama|mistral|mixtral|glm|moonshot|kimi|ernie|yi|codellama|phi|gemma|doubao)[A-Za-z0-9._:/+\\-]*\\b", 0):
		_add_model_id(models, candidate)
	return models


func _parse_json_like_text(text: String):
	var source := text.strip_edges()
	if source == "":
		return null
	var parsed = _try_parse_json(source)
	if parsed != null:
		return parsed
	var object_start := source.find("{")
	var object_end := source.rfind("}")
	if object_start >= 0 and object_end > object_start:
		parsed = _try_parse_json(source.substr(object_start, object_end - object_start + 1))
		if parsed != null:
			return parsed
	var array_start := source.find("[")
	var array_end := source.rfind("]")
	if array_start >= 0 and array_end > array_start:
		parsed = _try_parse_json(source.substr(array_start, array_end - array_start + 1))
		if parsed != null:
			return parsed
	return null


func _try_parse_json(source: String):
	var json := JSON.new()
	if json.parse(source) != OK:
		return null
	return json.data


func _endpoint_from_json_value(value) -> String:
	if value is Dictionary:
		for key in (value as Dictionary).keys():
			var key_text := String(key).to_lower()
			var raw = (value as Dictionary).get(key)
			if raw is String and (key_text in ["endpoint", "base_url", "baseurl", "api_base", "apibase", "url", "host"]):
				var candidate := String(raw).strip_edges()
				if candidate.begins_with("http://") or candidate.begins_with("https://"):
					return candidate
			var nested := _endpoint_from_json_value(raw)
			if nested != "":
				return nested
	elif value is Array:
		for item in value:
			var nested := _endpoint_from_json_value(item)
			if nested != "":
				return nested
	return ""


func _api_key_from_json_value(value) -> String:
	if value is Dictionary:
		for key in (value as Dictionary).keys():
			var key_text := String(key).to_lower().replace("-", "_")
			var raw = (value as Dictionary).get(key)
			if raw is String and key_text in ["api_key", "apikey", "key", "token", "access_token", "secret"]:
				var candidate := _clean_pasted_secret(String(raw))
				if candidate != "":
					return candidate
			var nested := _api_key_from_json_value(raw)
			if nested != "":
				return nested
	elif value is Array:
		for item in value:
			var nested := _api_key_from_json_value(item)
			if nested != "":
				return nested
	return ""


func _collect_models_from_json_value(value, parent_key: String, models: Array) -> void:
	if value is Dictionary:
		for key in (value as Dictionary).keys():
			var key_text := String(key).to_lower()
			var raw = (value as Dictionary).get(key)
			if raw is String:
				if key_text in ["model", "model_id", "modelid", "model_name", "modelname", "deployment", "deployment_id"]:
					_add_model_id(models, String(raw))
				elif parent_key in ["models", "data"] and key_text in ["id", "name"]:
					_add_model_id(models, String(raw))
			_collect_models_from_json_value(raw, key_text, models)
	elif value is Array:
		for item in value:
			if item is String and parent_key in ["models", "model", "model_ids"]:
				_add_model_id(models, String(item))
			else:
				_collect_models_from_json_value(item, parent_key, models)


func _collect_model_tokens(text: String, models: Array) -> void:
	var cleaned := text.strip_edges()
	if cleaned.begins_with("[") and cleaned.ends_with("]"):
		cleaned = cleaned.substr(1, cleaned.length() - 2)
	for token in cleaned.split(",", false):
		var piece := _clean_pasted_model_id(String(token))
		if piece.contains(" "):
			for nested in piece.split(" ", false):
				_add_model_id(models, String(nested))
		else:
			_add_model_id(models, piece)


func _add_model_id(models: Array, model_id: String) -> void:
	var clean := _clean_pasted_model_id(model_id)
	if clean == "" or not _looks_like_model_id(clean):
		return
	if not models.has(clean):
		models.append(clean)


func _clean_pasted_model_id(model_id: String) -> String:
	var clean := model_id.strip_edges()
	clean = clean.trim_prefix("\"").trim_prefix("'").trim_suffix("\"").trim_suffix("'")
	clean = clean.trim_suffix(",").trim_suffix(";")
	clean = clean.trim_suffix("]").trim_suffix("}").trim_suffix(")")
	clean = clean.trim_prefix("[").trim_prefix("{").trim_prefix("(")
	return clean.strip_edges()


func _looks_like_model_id(value: String) -> bool:
	var clean := _clean_pasted_model_id(value)
	if clean == "" or clean.length() > 96:
		return false
	var lower := clean.to_lower()
	if lower.begins_with("http://") or lower.begins_with("https://"):
		return false
	if lower.begins_with("sk-") or lower.contains("api_key"):
		return false
	if lower in ["model", "models", "api", "key", "endpoint", "baseurl", "base_url"]:
		return false
	var regex := RegEx.new()
	if regex.compile("(?i)^(?:gpt|o[1-9]|claude|gemini|deepseek|qwen|llama|mistral|mixtral|glm|moonshot|kimi|ernie|yi|codellama|phi|gemma|doubao)[A-Za-z0-9._:/+\\-]*$") != OK:
		return false
	return regex.search(clean) != null


func _infer_pasted_provider(text: String, endpoint: String, models: Array) -> String:
	var endpoint_lower := endpoint.to_lower()
	if endpoint_lower.contains("ollama") or endpoint_lower.contains(":11434") or endpoint_lower.contains("/api/tags"):
		return "ollama"
	if endpoint_lower.contains("anthropic"):
		return "anthropic"
	if endpoint_lower.contains("googleapis") or endpoint_lower.contains("gemini"):
		return "gemini"
	var text_lower := text.to_lower()
	if text_lower.contains("ollama") or text_lower.contains(":11434"):
		return "ollama"
	if text_lower.contains("anthropic") or text_lower.contains("x-api-key"):
		return "anthropic"
	if text_lower.contains("googleapis") or text_lower.contains("x-goog-api-key"):
		return "gemini"
	if endpoint.strip_edges() != "":
		return "openai_api"
	var model_text := ",".join(models).to_lower()
	if model_text.contains("claude"):
		return "anthropic"
	if model_text.contains("gemini"):
		return "gemini"
	return "openai_api"


func _normalize_pasted_endpoint(provider: String, endpoint: String) -> String:
	var clean := _clean_model_endpoint(endpoint)
	if clean == "":
		return ""
	var provider_id := _model_provider_id(provider)
	if provider_id == "ollama":
		if clean.ends_with("/api/chat"):
			clean = clean.substr(0, clean.length() - "/chat".length())
		if clean.ends_with("/api/tags"):
			clean = clean.substr(0, clean.length() - "/tags".length())
		if clean.ends_with("/api"):
			return clean
		return "%s/api" % clean
	if provider_id == "gemini":
		var models_marker := clean.find("/models/")
		if models_marker >= 0:
			clean = clean.substr(0, models_marker)
		if clean.ends_with(":generateContent"):
			clean = clean.substr(0, clean.rfind("/models"))
		return clean
	if provider_id == "anthropic":
		if clean.ends_with("/messages"):
			clean = clean.substr(0, clean.length() - "/messages".length())
		if clean.ends_with("/models"):
			clean = clean.substr(0, clean.length() - "/models".length())
		return clean
	if clean.ends_with("/chat/completions"):
		clean = clean.substr(0, clean.length() - "/chat/completions".length())
	if clean.ends_with("/models"):
		clean = clean.substr(0, clean.length() - "/models".length())
	if not clean.contains("/v1") and _endpoint_has_only_host_and_port(clean):
		clean = "%s/v1" % clean
	return clean


func _endpoint_has_only_host_and_port(endpoint: String) -> bool:
	var clean := endpoint.replace("http://", "").replace("https://", "")
	return not clean.contains("/")


func _best_endpoint_url(urls: Array) -> String:
	var cleaned := []
	for url in urls:
		var clean := _clean_pasted_url(String(url))
		if clean != "":
			cleaned.append(clean)
	if cleaned.is_empty():
		return ""
	for url in cleaned:
		var lower := String(url).to_lower()
		if lower.contains("/v1") or lower.contains(":11434") or lower.contains("openai") or lower.contains("anthropic") or lower.contains("googleapis") or lower.contains("ollama"):
			return String(url)
	return String(cleaned[0])


func _clean_pasted_url(url: String) -> String:
	var clean := url.strip_edges()
	while clean.ends_with(".") or clean.ends_with(",") or clean.ends_with(";") or clean.ends_with(")") or clean.ends_with("]") or clean.ends_with("}"):
		clean = clean.substr(0, clean.length() - 1)
	return clean


func _clean_pasted_secret(value: String) -> String:
	var clean := value.strip_edges()
	clean = clean.trim_prefix("\"").trim_prefix("'").trim_suffix("\"").trim_suffix("'")
	clean = clean.trim_suffix(",").trim_suffix(";")
	return clean.strip_edges()


func _regex_group_values(text: String, pattern: String, group_index: int) -> Array:
	var regex := RegEx.new()
	if regex.compile(pattern) != OK:
		return []
	var values := []
	for result in regex.search_all(text):
		if group_index == 0 or group_index <= result.get_group_count():
			var value := result.get_string(group_index).strip_edges()
			if value != "":
				values.append(value)
	return values


func _first_regex_group(text: String, pattern: String) -> String:
	var values := _regex_group_values(text, pattern, 1)
	return String(values[0]) if not values.is_empty() else ""


func _string_array_from_variant(value) -> Array:
	var result := []
	if value is Array:
		for item in value:
			if item is Dictionary:
				var data := item as Dictionary
				_add_model_id(result, String(data.get("id", data.get("model", ""))))
			else:
				_add_model_id(result, String(item))
	elif value is String:
		_collect_model_tokens(String(value), result)
	return result


func _model_catalog_items_from_model_ids(model_ids: Array) -> Array:
	var items := []
	for model_id in model_ids:
		var clean := String(model_id).strip_edges()
		if clean != "":
			items.append({
				"id": clean,
				"display_name": clean,
				"description": "pasted",
			})
	return items



func _save_batch_model_configs(provider: String, endpoint: String, api_key: String, max_context_text: String, temperature_text: String, reasoning: bool, selected_models: Dictionary) -> void:
	var provider_id := _model_provider_id(provider)
	var base_url := endpoint.strip_edges()
	if base_url == "":
		_show_toast("BaseUrl 不能为空", BOOK_RED)
		return
	var max_context := _tokens_from_context_text(max_context_text)
	var context_tokens := _context_tokens_from_max_context(max_context)
	var temperature := _temperature_from_text(temperature_text, 0.6)
	_model_config_log("batch save requested provider=%s endpoint=%s max_context=%d context=%d max_output=%d temperature=%.2f reasoning=%s selected=%d" % [provider_id, base_url, max_context, context_tokens, DEFAULT_MAX_OUTPUT_TOKEN, temperature, reasoning, selected_models.size()])
	var added := 0
	var skipped := 0
	var untested := 0
	for model_id_variant in selected_models.keys():
		var model_id := String(model_id_variant).strip_edges()
		if model_id == "" or not bool(selected_models.get(model_id_variant, false)):
			continue
		var detected_adapter := _model_detected_formt_adapter(provider_id, base_url, api_key, model_id, reasoning)
		var detected_reason_adapter := _model_detected_reason_adapter(provider_id, base_url, api_key, model_id, reasoning)
		var item := _model_config_item(0, model_id, provider_id, base_url, api_key, context_tokens, max_context, DEFAULT_MAX_OUTPUT_TOKEN, temperature, reasoning, detected_adapter, detected_reason_adapter)
		if not _model_schema_test_passed_for_item(item):
			untested += 1
			continue
		if _model_config_exists(provider_id, base_url, model_id):
			skipped += 1
			continue
		if _save_model_config_item(-1, item, false):
			added += 1
	if added <= 0:
		var reason := "，请先通过结构化测试" if untested > 0 else "，已存在的会自动跳过" if skipped > 0 else ""
		_show_toast("没有新增模型%s" % reason, BOOK_RED)
		return
	_commit_state()
	var skipped_text := "，跳过 %d 个重复项" % skipped if skipped > 0 else ""
	if untested > 0:
		skipped_text += "，%d 个未通过测试" % untested
	_show_toast("已添加 %d 个模型%s" % [added, skipped_text], BOOK_GREEN)
	_show_model_config_page()



func _model_config_exists(provider: String, endpoint: String, model: String) -> bool:
	var key := _model_config_key(provider, endpoint, model)
	for item in _model_configs:
		if item is Dictionary and _model_config_key(String((item as Dictionary).get("provider", "")), String((item as Dictionary).get("endpoint", "")), String((item as Dictionary).get("model", ""))) == key:
			return true
	return false



func _model_config_key(provider: String, endpoint: String, model: String) -> String:
	return "%s|%s|%s" % [_model_provider_id(provider), _clean_model_endpoint(endpoint).to_lower(), model.strip_edges().to_lower()]


func _test_batch_model_configs(provider: String, endpoint: String, api_key: String, reasoning: bool, selected_models: Dictionary) -> void:
	var provider_id := _model_provider_id(provider)
	var base_url := endpoint.strip_edges()
	if base_url == "":
		_show_toast("BaseUrl 不能为空", BOOK_RED)
		return
	var requested := 0
	for model_id_variant in selected_models.keys():
		var model_id := String(model_id_variant).strip_edges()
		if model_id == "" or not bool(selected_models.get(model_id_variant, false)):
			continue
		_test_model_config(provider_id, base_url, api_key, model_id, reasoning, null, FORMT_ADAPTER_AUTO, null)
		requested += 1
	if requested <= 0:
		_show_toast("请选择需要测试的模型", BOOK_RED)
	else:
		_show_toast("已提交 %d 个结构化测试" % requested, BOOK_GREEN)


func _ensure_model_test_signal() -> void:
	if _model_chat_client == null:
		return
	var callback := Callable(self, "_dispatch_model_chat_completed")
	if not _model_chat_client.completed.is_connected(callback):
		_model_chat_client.completed.connect(callback)
	var event_callback := Callable(self, "_dispatch_model_chat_protocol_event")
	if not _model_chat_client.protocol_event.is_connected(event_callback):
		_model_chat_client.protocol_event.connect(event_callback)


func _on_model_chat_result(request_id: int, completed_result: Dictionary) -> void:
	if not _model_test_requests.has(request_id):
		return
	_on_model_test_result(request_id, completed_result)


func _on_model_chat_event(request_id: int, event: Dictionary) -> void:
	if not _model_test_requests.has(request_id):
		return
	if event.is_empty():
		return
	var events: Array = _model_test_events.get(request_id, [])
	events.append(event.duplicate(true))
	_model_test_events[request_id] = events


func _test_model_config(provider: String, endpoint: String, api_key: String, model: String, reasoning: bool, button: Button, formt_adapter: String = FORMT_ADAPTER_AUTO, adapter_option: OptionButton = null, reason_adapter: String = REASON_ADAPTER_AUTO, reason_adapter_option: OptionButton = null) -> void:
	var provider_id := _model_provider_id(provider)
	var base_url := endpoint.strip_edges()
	var model_id := model.strip_edges()
	if model_id == "" or base_url == "":
		_model_config_log("test skipped: missing model or endpoint provider=%s endpoint=%s model=%s" % [provider_id, base_url, model_id], true)
		_show_toast("模型名和 BaseUrl 不能为空", BOOK_RED)
		return
	_ensure_model_test_signal()
	if button != null and is_instance_valid(button):
		button.disabled = true
	var candidates := _formt_adapter_test_candidates(provider_id, model_id, formt_adapter)
	if candidates.is_empty():
		if button != null and is_instance_valid(button):
			button.disabled = false
		_show_toast("当前端点类型没有可测试的结构兼容", BOOK_RED)
		return
	var context := {
		"button": button,
		"adapter_option": adapter_option,
		"reason_adapter_option": reason_adapter_option,
		"provider": provider_id,
		"endpoint": base_url,
		"api_key": api_key,
		"model": model_id,
		"reasoning": reasoning,
		"reason_adapter": _normalize_reason_adapter(reason_adapter),
		"candidates": candidates,
		"candidate_index": 0,
	}
	_clear_model_test_capabilities(provider_id, base_url, api_key, model_id, reasoning)
	_start_model_config_schema_test_attempt(context)
	_show_toast("开始测试：结构化输出（%s）" % _formt_adapter_label(String(candidates[0])), BOOK_GREEN)


func _start_model_config_schema_test_attempt(context: Dictionary) -> void:
	var provider_id := String(context.get("provider", ""))
	var base_url := String(context.get("endpoint", ""))
	var api_key := String(context.get("api_key", ""))
	var model_id := String(context.get("model", ""))
	var reasoning := bool(context.get("reasoning", false))
	var candidates: Array = context.get("candidates", [])
	var candidate_index := int(context.get("candidate_index", 0))
	if candidate_index < 0 or candidate_index >= candidates.size():
		return
	var adapter := _normalize_formt_adapter(String(candidates[candidate_index]))
	var profile := {
		"provider": provider_id,
		"endpoint": base_url,
		"api_key": api_key,
		"model": model_id,
		"formt_adapter": adapter,
		"reason_adapter": _normalize_reason_adapter(String(context.get("reason_adapter", REASON_ADAPTER_AUTO))),
		"reasoning": reasoning,
		"connection_test": true,
	}
	var messages := [
		{"role": "system", "content": "你是连接测试助手。当前结构化测试动作为 schema_check，目标座位号为 1。"},
		{"role": "user", "content": "确认当前模型连接可用，并完成当前结构化测试动作。"},
	]
	var request_options := _model_connection_test_options()
	request_options["output_adapter"] = adapter
	request_options["model_test_mode"] = "schema"
	var test_key := _model_schema_test_key(provider_id, base_url, api_key, model_id, reasoning, adapter)
	_show_toast("正在尝试结构兼容（%s） %d/%d" % [
		_formt_adapter_label(adapter),
		candidate_index + 1,
		candidates.size(),
	], BOOK_MUTED)
	var request_id := _complete_model_request(profile, messages, 0.0, 512, 20.0, request_options, "model_config.connection_test")
	var pending := context.duplicate(true)
	pending["formt_adapter"] = adapter
	pending["test_key"] = test_key
	pending["test_mode"] = "schema"
	_model_test_requests[request_id] = pending
	_model_config_log("schema test request started id=%d provider=%s endpoint=%s model=%s formt_adapter=%s attempt=%d/%d api_key=%s reasoning=%s schema=%s" % [request_id, provider_id, base_url, model_id, adapter, candidate_index + 1, candidates.size(), _api_key_state(api_key), reasoning, String((request_options.get("response_schema", {}) as Dictionary).get("name", ""))])


func _on_model_test_result(request_id: int, completed_result: Dictionary) -> void:
	if not _model_test_requests.has(request_id):
		return
	var request: Dictionary = _model_test_requests[request_id]
	_model_test_requests.erase(request_id)
	var request_events: Array = _model_test_events.get(request_id, [])
	_model_test_events.erase(request_id)
	var provider := String(request.get("provider", ""))
	var endpoint := String(request.get("endpoint", ""))
	var api_key := String(request.get("api_key", ""))
	var model := String(request.get("model", ""))
	var reasoning := bool(request.get("reasoning", false))
	var formt_adapter := _normalize_formt_adapter(String(request.get("formt_adapter", FORMT_ADAPTER_AUTO)))
	var test_key := String(request.get("test_key", ""))
	var button := request.get("button") as Button
	var mode := String(request.get("test_mode", "schema"))
	if completed_result.is_empty():
		completed_result = {"ok": false, "text": "", "error": "模型结果为空", "diagnostic": {}}
	var result_ok := bool(completed_result.get("ok", false))
	var result_text := String(completed_result.get("text", ""))
	var result_error := String(completed_result.get("error", ""))
	var diagnostic := completed_result.get("diagnostic", {}) as Dictionary if completed_result.get("diagnostic", {}) is Dictionary else _take_model_test_diagnostic(request_id)
	match mode:
		"schema":
			var schema_ok := result_ok and _model_schema_test_response_valid(result_text)
			if schema_ok:
				_record_model_test_capability(provider, endpoint, api_key, model, reasoning, formt_adapter, "schema_ok", true)
				if test_key != "":
					_model_schema_test_passes[test_key] = true
				_model_detected_formt_adapters[_model_schema_test_base_key(provider, endpoint, api_key, model, reasoning)] = formt_adapter
				_show_toast("结构化输出通过（%s）" % _formt_adapter_label(formt_adapter), BOOK_GREEN)
				var adapter_option := request.get("adapter_option") as OptionButton
				if adapter_option != null and is_instance_valid(adapter_option):
					_select_formt_adapter(adapter_option, formt_adapter)
				_start_model_config_text_test_attempt(request)
				return
			var schema_error := _short_model_test_status(result_error) if not result_ok else _model_schema_test_error(result_text)
			if test_key != "":
				_model_schema_test_passes.erase(test_key)
			_mark_model_test_incompatible(provider, endpoint, api_key, model, reasoning, formt_adapter, schema_error)
			var candidates: Array = request.get("candidates", [])
			var candidate_index := int(request.get("candidate_index", 0))
			if candidate_index + 1 < candidates.size():
				request["candidate_index"] = candidate_index + 1
				_start_model_config_schema_test_attempt(request)
				_show_toast("结构化失败（%s）：%s，继续尝试下一个适配器" % [_formt_adapter_label(formt_adapter), schema_error], BOOK_MUTED)
				return
			if button != null and is_instance_valid(button):
				button.disabled = false
				_refresh_model_editor_save_state_from_test_button(button)
			_show_toast("结构化测试失败（%s）：%s" % [_formt_adapter_label(formt_adapter), schema_error], BOOK_RED)
		"text":
			var text_ok := result_ok and _model_text_test_response_valid(result_text)
			_record_model_test_capability(provider, endpoint, api_key, model, reasoning, formt_adapter, "text_ok", text_ok)
			if not text_ok:
				var text_error := _short_model_test_status(result_error) if not result_ok else _model_text_test_error(result_text)
				_mark_model_test_incompatible(provider, endpoint, api_key, model, reasoning, formt_adapter, text_error)
				if button != null and is_instance_valid(button):
					button.disabled = false
					_refresh_model_editor_save_state_from_test_button(button)
				_show_toast("文本输出测试失败（%s）：%s" % [_formt_adapter_label(formt_adapter), text_error], BOOK_RED)
				return
			var selected_reason_adapter := _normalize_reason_adapter(String(request.get("reason_adapter", REASON_ADAPTER_AUTO)))
			var display_reason_adapter := selected_reason_adapter
			if display_reason_adapter == REASON_ADAPTER_AUTO:
				var reason_candidates := _reason_adapter_test_candidates(provider, model, reasoning, formt_adapter, selected_reason_adapter)
				if not reason_candidates.is_empty():
					display_reason_adapter = String(reason_candidates[0])
			_show_toast("文本输出通过（%s）" % _reason_adapter_label(display_reason_adapter, provider), BOOK_GREEN)
			_start_model_config_reasoning_test_attempt(request)
			return
		"reasoning":
			var detected_reason_adapter := _model_test_reason_adapter_from_request(request)
			var reasoning_event_present := _model_reasoning_test_event_present(request_events)
			var reasoning_output_ok := result_ok and _model_reasoning_test_matches_expectation(reasoning, detected_reason_adapter, reasoning_event_present)
			_model_config_log("reasoning test result provider=%s endpoint=%s model=%s reasoning=%s reason_adapter=%s ok=%s event_present=%s event_count=%d candidate_index=%d" % [
				provider,
				endpoint,
				model,
				str(reasoning),
				detected_reason_adapter,
				str(reasoning_output_ok),
				str(reasoning_event_present),
				request_events.size(),
				int(request.get("reason_candidate_index", 0)) + 1,
			])
			_record_model_test_capability(provider, endpoint, api_key, model, reasoning, formt_adapter, "reasoning_output_ok", reasoning_output_ok, detected_reason_adapter)
			if not reasoning_output_ok:
				var reason_candidates: Array = request.get("reason_candidates", [])
				var reason_index := int(request.get("reason_candidate_index", 0))
				var reasoning_error := _model_reasoning_test_error(reasoning, detected_reason_adapter, reasoning_event_present)
				_mark_model_reason_adapter_incompatible(provider, endpoint, api_key, model, reasoning, formt_adapter, detected_reason_adapter, reasoning_error)
				if reason_index + 1 < reason_candidates.size():
					_model_config_log("reasoning test retry provider=%s endpoint=%s model=%s reasoning=%s from=%s next=%s next_index=%d/%d" % [
						provider,
						endpoint,
						model,
						str(reasoning),
						_normalize_reason_adapter(String(reason_candidates[reason_index])),
						_normalize_reason_adapter(String(reason_candidates[reason_index + 1])),
						reason_index + 2,
						reason_candidates.size(),
					], true)
					request["reason_candidate_index"] = reason_index + 1
					_start_model_config_reasoning_test_attempt(request)
					_show_toast("思考测试失败（%s）：%s，继续尝试下一个兼容策略" % [_reason_adapter_label(_normalize_reason_adapter(String(reason_candidates[reason_index])), provider), reasoning_error], BOOK_MUTED)
					return
				if button != null and is_instance_valid(button):
					button.disabled = false
					_refresh_model_editor_save_state_from_test_button(button)
				var failed_reason_adapter := _normalize_reason_adapter(String(request.get("reason_adapter", REASON_ADAPTER_AUTO)))
				if failed_reason_adapter == REASON_ADAPTER_AUTO and not reason_candidates.is_empty():
					failed_reason_adapter = _normalize_reason_adapter(String(reason_candidates[min(reason_index, reason_candidates.size() - 1)]))
				_model_config_log("reasoning test exhausted provider=%s endpoint=%s model=%s reasoning=%s failed_reason_adapter=%s candidates=%s error=%s" % [
					provider,
					endpoint,
					model,
					str(reasoning),
					failed_reason_adapter,
					JSON.stringify(reason_candidates),
					reasoning_error,
				], true)
				_show_toast("思考测试失败（%s）：%s" % [_reason_adapter_label(failed_reason_adapter, provider), reasoning_error], BOOK_RED)
				return
			detected_reason_adapter = _model_test_reason_adapter_from_request(request)
			if detected_reason_adapter == REASON_ADAPTER_AUTO:
				var reason_candidates: Array = request.get("reason_candidates", [])
				var reason_index := int(request.get("reason_candidate_index", 0))
				if not reason_candidates.is_empty() and reason_index >= 0 and reason_index < reason_candidates.size():
					detected_reason_adapter = _normalize_reason_adapter(String(reason_candidates[reason_index]))
			_model_detected_reason_adapters[_model_schema_test_base_key(provider, endpoint, api_key, model, reasoning)] = detected_reason_adapter
			_model_config_log("reasoning test success provider=%s endpoint=%s model=%s reasoning=%s detected_reason_adapter=%s cached=%s" % [
				provider,
				endpoint,
				model,
				str(reasoning),
				detected_reason_adapter,
				_model_detected_reason_adapter(provider, endpoint, api_key, model, reasoning),
			])
			var reason_adapter_option := request.get("reason_adapter_option") as OptionButton
			if reason_adapter_option != null and is_instance_valid(reason_adapter_option):
				_model_config_log("reason adapter option before direct select selected=%s count=%d" % [
					_reason_adapter_selected(reason_adapter_option),
					reason_adapter_option.get_item_count(),
				])
				_select_reason_adapter(reason_adapter_option, detected_reason_adapter)
				_model_config_log("reason adapter option after direct select selected=%s" % [
					_reason_adapter_selected(reason_adapter_option),
				])
			_finalize_model_test_success(provider, endpoint, api_key, model, reasoning, formt_adapter, detected_reason_adapter, button)
		_:
			if button != null and is_instance_valid(button):
				button.disabled = false
				_refresh_model_editor_save_state_from_test_button(button)
			_show_toast("测试失败：未知测试阶段", BOOK_RED)


func _model_connection_test_options() -> Dictionary:
	return {
		"output_type": "json",
		"response_schema": {
			"name": "model_action_schema_test_v1",
			"strict": true,
			"schema": {
				"type": "object",
				"additionalProperties": false,
				"properties": {
					"action": {
						"type": "string",
						"enum": ["schema_check"],
						"description": "结构化输出能力测试动作，必须返回 schema_check。",
					},
					"targetSeatNumber": {
						"type": "integer",
						"enum": [1],
						"description": "结构化输出能力测试目标座位号，必须是 JSON number/integer。",
					},
				},
				"required": ["action", "targetSeatNumber"],
			},
		},
	}


func _model_text_connection_test_options(reasoning: bool, stream: bool = false) -> Dictionary:
	return {
		"transport_mode": "stream" if stream else "sync",
		"output_type": "text",
		"output_adapter": FORMT_ADAPTER_NONE,
		"reason_adapter": REASON_ADAPTER_NATIVE if not reasoning else REASON_ADAPTER_AUTO,
		"reasoning_mode": "on" if reasoning else "off",
		"model_test_mode": "reasoning" if reasoning else "text",
	}


func _start_model_config_text_test_attempt(context: Dictionary) -> void:
	var provider_id := String(context.get("provider", ""))
	var base_url := String(context.get("endpoint", ""))
	var api_key := String(context.get("api_key", ""))
	var model_id := String(context.get("model", ""))
	var reasoning := bool(context.get("reasoning", false))
	var formt_adapter := _normalize_formt_adapter(String(context.get("formt_adapter", FORMT_ADAPTER_AUTO)))
	var selected_reason_adapter := _normalize_reason_adapter(String(context.get("reason_adapter", REASON_ADAPTER_AUTO)))
	var reason_adapter := _text_test_reason_adapter(provider_id, model_id, formt_adapter, selected_reason_adapter)
	var profile := {
		"provider": provider_id,
		"endpoint": base_url,
		"api_key": api_key,
		"model": model_id,
		"formt_adapter": FORMT_ADAPTER_NONE,
		"reason_adapter": reason_adapter,
		"reasoning": false,
		"connection_test": true,
	}
	var messages := [
		{"role": "system", "content": "你是连接测试助手。请直接输出纯文本 ok，不要 JSON，不要 Markdown，不要代码块。"},
		{"role": "user", "content": "直接输出：ok"},
	]
	var request_options := _model_text_connection_test_options(false, false)
	request_options["reason_adapter"] = reason_adapter
	_show_toast("正在尝试文本输出测试（%s）" % _reason_adapter_label(reason_adapter, provider_id), BOOK_MUTED)
	var request_id := _complete_model_request(profile, messages, 0.0, 64, 20.0, request_options, "model_config.text_test")
	var pending := context.duplicate(true)
	pending["test_mode"] = "text"
	pending["formt_adapter"] = formt_adapter
	_model_test_requests[request_id] = pending
	_model_config_log("text test request started id=%d provider=%s endpoint=%s model=%s reasoning=%s reason_adapter=%s" % [request_id, provider_id, base_url, model_id, reasoning, reason_adapter])


func _text_test_reason_adapter(provider: String, model: String, formt_adapter: String = FORMT_ADAPTER_AUTO, selected_reason_adapter: String = REASON_ADAPTER_AUTO) -> String:
	var selected := _normalize_reason_adapter(selected_reason_adapter)
	if _reason_adapter_can_save(false, selected):
		return selected
	var detected := _reason_adapter_detected_for_model(provider, model, formt_adapter)
	match detected:
		REASON_ADAPTER_DEEPSEEK_THINKING, REASON_ADAPTER_GLM_THINKING, REASON_ADAPTER_ARK_THINKING, REASON_ADAPTER_MINIMAX_REASONING_SPLIT, REASON_ADAPTER_MIMO_CHAT_TEMPLATE, REASON_ADAPTER_KIMI_THINKING_CONTROL:
			return detected
		_:
			return REASON_ADAPTER_NATIVE


func _start_model_config_reasoning_test_attempt(context: Dictionary) -> void:
	var provider_id := String(context.get("provider", ""))
	var base_url := String(context.get("endpoint", ""))
	var api_key := String(context.get("api_key", ""))
	var model_id := String(context.get("model", ""))
	var formt_adapter := _normalize_formt_adapter(String(context.get("formt_adapter", FORMT_ADAPTER_AUTO)))
	var reasoning_enabled := bool(context.get("reasoning", false))
	var reason_candidates: Array = context.get("reason_candidates", [])
	if reason_candidates.is_empty():
		reason_candidates = _reason_adapter_test_candidates(provider_id, model_id, reasoning_enabled, formt_adapter, String(context.get("reason_adapter", REASON_ADAPTER_AUTO)))
	else:
		var normalized_candidates := []
		for item in reason_candidates:
			var candidate := _normalize_reason_adapter(String(item))
			if candidate != REASON_ADAPTER_AUTO and not normalized_candidates.has(candidate):
				normalized_candidates.append(candidate)
		reason_candidates = normalized_candidates
	if reason_candidates.is_empty():
		_model_config_log("reasoning test skipped: no reason adapter candidates provider=%s endpoint=%s model=%s formt_adapter=%s selected=%s" % [
			provider_id,
			base_url,
			model_id,
			formt_adapter,
			String(context.get("reason_adapter", REASON_ADAPTER_AUTO)),
		], true)
		var empty_button := context.get("button") as Button
		if empty_button != null and is_instance_valid(empty_button):
			empty_button.disabled = false
			_refresh_model_editor_save_state_from_test_button(empty_button)
		_show_toast("思考测试失败：没有可用的思考兼容候选", BOOK_RED)
		return
	var reason_index := int(context.get("reason_candidate_index", 0))
	if reason_index < 0 or reason_index >= reason_candidates.size():
		_model_config_log("reasoning test skipped: candidate index out of range provider=%s endpoint=%s model=%s index=%d size=%d candidates=%s" % [
			provider_id,
			base_url,
			model_id,
			reason_index,
			reason_candidates.size(),
			JSON.stringify(reason_candidates),
		], true)
		var range_button := context.get("button") as Button
		if range_button != null and is_instance_valid(range_button):
			range_button.disabled = false
			_refresh_model_editor_save_state_from_test_button(range_button)
		_show_toast("思考测试失败：兼容候选索引越界", BOOK_RED)
		return
	var reason_adapter := _normalize_reason_adapter(String(reason_candidates[reason_index]))
	var profile := {
		"provider": provider_id,
		"endpoint": base_url,
		"api_key": api_key,
		"model": model_id,
		"formt_adapter": FORMT_ADAPTER_NONE,
		"reason_adapter": reason_adapter,
		"reasoning": reasoning_enabled,
		"connection_test": true,
	}
	var messages := []
	if reasoning_enabled:
		messages = [
			{"role": "system", "content": "你是连接测试助手。请启用思考模式，并最终输出纯文本 ok。"},
			{"role": "user", "content": "先思考，再直接输出：ok"},
		]
	else:
		messages = [
			{"role": "system", "content": "你是连接测试助手。请关闭思考模式，不要输出任何 reasoning/thinking 内容，最终只输出纯文本 ok。"},
			{"role": "user", "content": "不要思考，不要输出 reasoning 内容，直接输出：ok"},
		]
	var request_options := _model_text_connection_test_options(reasoning_enabled, false)
	request_options["reasoning_mode"] = "on" if reasoning_enabled else "off"
	request_options["reason_adapter"] = reason_adapter
	_show_toast("正在尝试思考兼容（%s） %d/%d" % [
		_reason_adapter_label(reason_adapter, provider_id),
		reason_index + 1,
		reason_candidates.size(),
	], BOOK_MUTED)
	var reasoning_test_output_tokens := 512 if reason_adapter == REASON_ADAPTER_MINIMAX_REASONING_SPLIT else 128
	var request_id := _complete_model_request(profile, messages, 0.0, reasoning_test_output_tokens, 20.0, request_options, "model_config.reasoning_test")
	var pending := context.duplicate(true)
	pending["test_mode"] = "reasoning"
	pending["formt_adapter"] = formt_adapter
	pending["reason_adapter"] = reason_adapter
	pending["reason_candidates"] = reason_candidates
	pending["reason_candidate_index"] = reason_index
	_model_test_requests[request_id] = pending
	_model_config_log("reasoning test request started id=%d provider=%s endpoint=%s model=%s reasoning=%s reason_adapter=%s candidate_index=%d/%d candidates=%s" % [
		request_id,
		provider_id,
		base_url,
		model_id,
		str(reasoning_enabled),
		reason_adapter,
		reason_index + 1,
		reason_candidates.size(),
		JSON.stringify(reason_candidates),
	])


func _model_schema_test_response_valid(content: String) -> bool:
	var parsed := _parse_model_schema_test_response(content)
	if parsed.is_empty():
		return false
	if not parsed.has("action") or not parsed.has("targetSeatNumber"):
		return false
	if parsed.size() != 2:
		return false
	return String(parsed.get("action", "")).strip_edges() == "schema_check" and _model_schema_test_target_seat(parsed.get("targetSeatNumber", -1)) == 1


func _model_text_test_response_valid(content: String) -> bool:
	return content.strip_edges().to_lower() == "ok"


func _model_text_test_error(content: String) -> String:
	var clean := content.strip_edges()
	if clean == "":
		return "文本模式测试失败：模型没有返回纯文本"
	return "文本模式测试失败：返回内容不是 ok"


func _model_reasoning_test_event_present(events: Array) -> bool:
	for item in events:
		if not (item is Dictionary):
			continue
		var event: Dictionary = item
		if String(event.get("type", "")) != "chunk":
			continue
		if String(event.get("kind", "")) != "reasoning":
			continue
		if String(event.get("text", "")).strip_edges() != "":
			return true
	return false


func _model_reasoning_test_matches_expectation(reasoning_enabled: bool, reason_adapter: String, reasoning_event_present: bool) -> bool:
	if not reasoning_enabled and _normalize_reason_adapter(reason_adapter) == REASON_ADAPTER_MINIMAX_REASONING_SPLIT:
		return true
	return reasoning_event_present == reasoning_enabled


func _model_reasoning_test_error(reasoning_enabled: bool, reason_adapter: String, reasoning_event_present: bool) -> String:
	if not reasoning_enabled and _normalize_reason_adapter(reason_adapter) == REASON_ADAPTER_MINIMAX_REASONING_SPLIT:
		return "MiniMax reasoning_split 只表示拆分思考；关闭思考时返回独立 reasoning 事件不阻塞保存，但正文必须保持纯文本"
	return "思考开关与 reasoning 事件不匹配：期望%s，实际%s" % [
		"有" if reasoning_enabled else "无",
		"有" if reasoning_event_present else "无",
	]


func _model_test_reason_adapter_from_request(request: Dictionary) -> String:
	var detected_reason_adapter := _normalize_reason_adapter(String(request.get("reason_adapter", REASON_ADAPTER_AUTO)))
	if detected_reason_adapter != REASON_ADAPTER_AUTO:
		return detected_reason_adapter
	var reason_candidates: Array = request.get("reason_candidates", [])
	var reason_index := int(request.get("reason_candidate_index", 0))
	if not reason_candidates.is_empty() and reason_index >= 0 and reason_index < reason_candidates.size():
		return _normalize_reason_adapter(String(reason_candidates[reason_index]))
	return REASON_ADAPTER_AUTO


func _model_schema_test_error(content: String) -> String:
	var parsed := _parse_model_schema_test_response(content)
	if parsed.is_empty():
		return "schema 校验失败：模型没有返回 JSON 对象"
	if not parsed.has("action"):
		return "schema 校验失败：缺少 action"
	if not parsed.has("targetSeatNumber"):
		return "schema 校验失败：缺少 targetSeatNumber"
	if parsed.size() != 2:
		return "schema 校验失败：包含多余字段"
	if String(parsed.get("action", "")).strip_edges() != "schema_check":
		return "schema 校验失败：action 不符合要求"
	if _model_schema_test_target_seat(parsed.get("targetSeatNumber", -1)) != 1:
		return "schema 校验失败：targetSeatNumber 不符合要求"
	return "schema 校验失败"


func _parse_model_schema_test_response(content: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(content.strip_edges()) != OK:
		return {}
	if not (json.data is Dictionary):
		return {}
	return (json.data as Dictionary)


func _model_schema_test_target_seat(value) -> int:
	if value is int:
		return int(value)
	if value is float:
		return int(value) if float(value) == float(int(value)) else -1
	return -1


func _model_schema_test_base_key(provider: String, endpoint: String, api_key: String, model: String, reasoning: bool) -> String:
	return "%s|%s|%s|%s|%s" % [
		_model_provider_id(provider),
		_clean_model_endpoint(endpoint).to_lower(),
		model.strip_edges().to_lower(),
		str(api_key.strip_edges().hash()),
		str(reasoning),
	]


func _model_test_capability_key(provider: String, endpoint: String, api_key: String, model: String, reasoning: bool, formt_adapter: String, reason_adapter: String = REASON_ADAPTER_AUTO) -> String:
	return "%s|%s" % [
		_model_schema_test_key(provider, endpoint, api_key, model, reasoning, formt_adapter),
		_normalize_reason_adapter(reason_adapter),
	]


func _clear_model_test_capabilities(provider: String, endpoint: String, api_key: String, model: String, reasoning: bool) -> void:
	var base_key := _model_schema_test_base_key(provider, endpoint, api_key, model, reasoning)
	for key in _model_test_capabilities.keys():
		if String(key).begins_with("%s|" % base_key):
			_model_test_capabilities.erase(key)


func _record_model_test_capability(provider: String, endpoint: String, api_key: String, model: String, reasoning: bool, formt_adapter: String, field: String, value, reason_adapter: String = REASON_ADAPTER_AUTO) -> void:
	var key := _model_test_capability_key(provider, endpoint, api_key, model, reasoning, formt_adapter, reason_adapter)
	var existing: Dictionary = _model_test_capabilities.get(key, {})
	existing[field] = value
	_model_test_capabilities[key] = existing


func _mark_model_test_incompatible(provider: String, endpoint: String, api_key: String, model: String, reasoning: bool, formt_adapter: String, reason: String) -> void:
	_record_model_test_capability(provider, endpoint, api_key, model, reasoning, formt_adapter, "compatible", false)
	_record_model_test_capability(provider, endpoint, api_key, model, reasoning, formt_adapter, "error", reason)


func _mark_model_reason_adapter_incompatible(provider: String, endpoint: String, api_key: String, model: String, reasoning: bool, formt_adapter: String, reason_adapter: String, reason: String) -> void:
	_record_model_test_capability(provider, endpoint, api_key, model, reasoning, formt_adapter, "compatible", false, reason_adapter)
	_record_model_test_capability(provider, endpoint, api_key, model, reasoning, formt_adapter, "error", reason, reason_adapter)


func _finalize_model_test_success(provider: String, endpoint: String, api_key: String, model: String, reasoning: bool, formt_adapter: String, reason_adapter: String, button: Button) -> void:
	_record_model_test_capability(provider, endpoint, api_key, model, reasoning, formt_adapter, "compatible", true, reason_adapter)
	_model_config_log("finalize model test success provider=%s endpoint=%s model=%s reasoning=%s formt_adapter=%s reason_adapter=%s button_valid=%s" % [
		provider,
		endpoint,
		model,
		str(reasoning),
		formt_adapter,
		reason_adapter,
		str(button != null and is_instance_valid(button)),
	])
	if button != null and is_instance_valid(button):
		var formt_adapter_option = button.get_meta("formt_adapter_option", null) as OptionButton
		if formt_adapter_option != null and is_instance_valid(formt_adapter_option):
			_select_formt_adapter(formt_adapter_option, formt_adapter)
		var reason_adapter_option = button.get_meta("reason_adapter_option", null) as OptionButton
		if reason_adapter_option != null and is_instance_valid(reason_adapter_option):
			_select_reason_adapter(reason_adapter_option, reason_adapter)
		_apply_detected_model_adapters_to_test_button(button)
		button.disabled = false
		_refresh_model_editor_save_state_from_test_button(button)
	else:
		_apply_detected_model_adapters_to_active_editor(provider, endpoint, api_key, model, reasoning)
	_show_toast("思考检测通过（%s）" % _reason_adapter_label(reason_adapter, provider), BOOK_GREEN)


func _apply_detected_model_adapters_to_active_editor(provider: String, endpoint: String, api_key: String, model: String, reasoning: bool) -> void:
	if _active_model_editor_controls.is_empty():
		return
	var save_button = _active_model_editor_controls.get("save_button", null) as Button
	var provider_option = _active_model_editor_controls.get("provider_option", null) as OptionButton
	var endpoint_line = _active_model_editor_controls.get("endpoint_line", null) as LineEdit
	var api_key_line = _active_model_editor_controls.get("api_key_line", null) as LineEdit
	var model_line = _active_model_editor_controls.get("model_line", null) as LineEdit
	var reasoning_checkbox = _active_model_editor_controls.get("reasoning_checkbox", null) as CheckBox
	var formt_adapter_option = _active_model_editor_controls.get("formt_adapter_option", null) as OptionButton
	var reason_adapter_option = _active_model_editor_controls.get("reason_adapter_option", null) as OptionButton
	if save_button == null or provider_option == null or endpoint_line == null or api_key_line == null or model_line == null or reasoning_checkbox == null or formt_adapter_option == null or reason_adapter_option == null:
		return
	if not is_instance_valid(save_button) or not is_instance_valid(provider_option) or not is_instance_valid(endpoint_line) or not is_instance_valid(api_key_line) or not is_instance_valid(model_line) or not is_instance_valid(reasoning_checkbox) or not is_instance_valid(formt_adapter_option) or not is_instance_valid(reason_adapter_option):
		return
	var provider_id := _book_provider_selected(provider_option)
	var endpoint_value: String = endpoint_line.text.strip_edges()
	var api_key_value: String = api_key_line.text
	var model_id: String = model_line.text.strip_edges()
	var reasoning_enabled := bool(reasoning_checkbox.button_pressed)
	if provider_id != _model_provider_id(provider) or endpoint_value != endpoint.strip_edges() or api_key_value != api_key or model_id != model.strip_edges() or reasoning_enabled != reasoning:
		return
	var detected_formt_adapter := _model_detected_formt_adapter(provider_id, endpoint_value, api_key_value, model_id, reasoning_enabled)
	var detected_reason_adapter := _model_detected_reason_adapter(provider_id, endpoint_value, api_key_value, model_id, reasoning_enabled)
	if _formt_adapter_can_save(detected_formt_adapter):
		_select_formt_adapter(formt_adapter_option, detected_formt_adapter)
	if _reason_adapter_can_save(reasoning_enabled, detected_reason_adapter):
		_select_reason_adapter(reason_adapter_option, detected_reason_adapter)
	_update_model_editor_save_state(
		save_button,
		int(_active_model_editor_controls.get("edit_index", -1)),
		model_line.text,
		provider_id,
		endpoint_line.text,
		api_key_line.text,
		reasoning_enabled,
		_formt_adapter_selected(formt_adapter_option),
		_reason_adapter_selected(reason_adapter_option)
	)


func _take_model_test_diagnostic(request_id: int) -> Dictionary:
	if not has_method("_take_model_chat_completed_diagnostic"):
		return {}
	return _take_model_chat_completed_diagnostic(request_id)


func _take_model_test_result(request_id: int) -> Dictionary:
	if not has_method("_take_model_chat_completed_result"):
		return {}
	return _take_model_chat_completed_result(request_id)


func _model_schema_test_key(provider: String, endpoint: String, api_key: String, model: String, reasoning: bool, formt_adapter: String = FORMT_ADAPTER_AUTO) -> String:
	return "%s|%s" % [
		_model_schema_test_base_key(provider, endpoint, api_key, model, reasoning),
		_normalize_formt_adapter(formt_adapter),
	]


func _model_detected_formt_adapter(provider: String, endpoint: String, api_key: String, model: String, reasoning: bool) -> String:
	var key := _model_schema_test_base_key(provider, endpoint, api_key, model, reasoning)
	return _normalize_formt_adapter(String(_model_detected_formt_adapters.get(key, FORMT_ADAPTER_AUTO)))


func _model_detected_reason_adapter(provider: String, endpoint: String, api_key: String, model: String, reasoning: bool) -> String:
	var key := _model_schema_test_base_key(provider, endpoint, api_key, model, reasoning)
	return _normalize_reason_adapter(String(_model_detected_reason_adapters.get(key, REASON_ADAPTER_AUTO)))


func _model_schema_test_passed_for_item(item: Dictionary) -> bool:
	var formt_adapter := _normalize_formt_adapter(String(item.get("formt_adapter", FORMT_ADAPTER_AUTO)))
	if not _formt_adapter_can_save(formt_adapter):
		return false
	var reason_adapter := _normalize_reason_adapter(String(item.get("reason_adapter", REASON_ADAPTER_AUTO)))
	if not _reason_adapter_can_save(bool(item.get("reasoning", false)), reason_adapter):
		return false
	var capability_key := _model_test_capability_key(
		String(item.get("provider", "")),
		String(item.get("endpoint", "")),
		String(item.get("api_key", "")),
		String(item.get("model", "")),
		bool(item.get("reasoning", false)),
		formt_adapter,
		reason_adapter
	)
	var capability: Dictionary = _model_test_capabilities.get(capability_key, {})
	if not capability.is_empty():
		return bool(capability.get("compatible", false))
	var legacy_key := _model_schema_test_key(
		String(item.get("provider", "")),
		String(item.get("endpoint", "")),
		String(item.get("api_key", "")),
		String(item.get("model", "")),
		bool(item.get("reasoning", false)),
		formt_adapter
	)
	return bool(_model_schema_test_passes.get(legacy_key, false)) and reason_adapter == _model_detected_reason_adapter(
		String(item.get("provider", "")),
		String(item.get("endpoint", "")),
		String(item.get("api_key", "")),
		String(item.get("model", "")),
		bool(item.get("reasoning", false))
	)


func _model_config_requires_schema_test(index: int, item: Dictionary) -> bool:
	if index < 0 or index >= _model_configs.size() or not (_model_configs[index] is Dictionary):
		return true
	var existing: Dictionary = _model_configs[index]
	return _model_schema_test_key(
		String(existing.get("provider", "")),
		String(existing.get("endpoint", "")),
		String(existing.get("api_key", "")),
		String(existing.get("model", existing.get("name", ""))),
		bool(existing.get("reasoning", false)),
		String(existing.get("formt_adapter", FORMT_ADAPTER_AUTO))
	) != _model_schema_test_key(
		String(item.get("provider", "")),
		String(item.get("endpoint", "")),
		String(item.get("api_key", "")),
		String(item.get("model", "")),
		bool(item.get("reasoning", false)),
		String(item.get("formt_adapter", FORMT_ADAPTER_AUTO))
	) or _normalize_reason_adapter(String(existing.get("reason_adapter", REASON_ADAPTER_AUTO))) != _normalize_reason_adapter(String(item.get("reason_adapter", REASON_ADAPTER_AUTO)))


func _update_model_editor_save_state(button: Button, index: int, model: String, provider: String, endpoint: String, api_key: String, reasoning: bool, formt_adapter: String, reason_adapter: String) -> void:
	if button == null or not is_instance_valid(button):
		return
	var model_id := model.strip_edges()
	var base_url := endpoint.strip_edges()
	if model_id == "" or base_url == "":
		button.disabled = true
		_model_config_log("save state disabled: empty model or endpoint index=%d provider=%s endpoint=%s model=%s" % [index, provider, base_url, model_id])
		return
	var adapter := _normalize_formt_adapter(formt_adapter)
	if not _formt_adapter_can_save(adapter):
		adapter = _model_detected_formt_adapter(_model_provider_id(provider), base_url, api_key, model_id, reasoning)
	if not _formt_adapter_can_save(adapter):
		button.disabled = true
		_model_config_log("save state disabled: invalid formt adapter index=%d provider=%s endpoint=%s model=%s ui_formt=%s detected_formt=%s" % [
			index,
			_model_provider_id(provider),
			base_url,
			model_id,
			formt_adapter,
			_model_detected_formt_adapter(_model_provider_id(provider), base_url, api_key, model_id, reasoning),
		], true)
		return
	var thinking_adapter := _normalize_reason_adapter(reason_adapter)
	if not _reason_adapter_can_save(reasoning, thinking_adapter):
		thinking_adapter = _model_detected_reason_adapter(_model_provider_id(provider), base_url, api_key, model_id, reasoning)
	if not _reason_adapter_can_save(reasoning, thinking_adapter):
		button.disabled = true
		_model_config_log("save state disabled: invalid reason adapter index=%d provider=%s endpoint=%s model=%s ui_reason=%s detected_reason=%s reasoning=%s" % [
			index,
			_model_provider_id(provider),
			base_url,
			model_id,
			reason_adapter,
			_model_detected_reason_adapter(_model_provider_id(provider), base_url, api_key, model_id, reasoning),
			str(reasoning),
		], true)
		return
	var item := _model_config_item(0, model_id, _model_provider_id(provider), base_url, api_key, 8192, DEFAULT_MAX_CONTEXT_TOKEN, DEFAULT_MAX_OUTPUT_TOKEN, 0.6, reasoning, adapter, thinking_adapter)
	if _model_config_requires_schema_test(index, item):
		button.disabled = not _model_schema_test_passed_for_item(item)
		_model_config_log("save state schema check index=%d provider=%s endpoint=%s model=%s requires=%s passed=%s formt=%s reason=%s disabled=%s" % [
			index,
			_model_provider_id(provider),
			base_url,
			model_id,
			str(true),
			str(_model_schema_test_passed_for_item(item)),
			adapter,
			thinking_adapter,
			str(button.disabled),
		])
		return
	button.disabled = false
	_model_config_log("save state enabled index=%d provider=%s endpoint=%s model=%s formt=%s reason=%s reasoning=%s" % [
		index,
		_model_provider_id(provider),
		base_url,
		model_id,
		adapter,
		thinking_adapter,
		str(reasoning),
	])


func _refresh_model_editor_save_state_from_test_button(test_button: Button) -> void:
	if test_button == null or not is_instance_valid(test_button):
		return
	var save_button = test_button.get_meta("save_button", null) as Button
	var provider_option = test_button.get_meta("provider_option", null) as OptionButton
	var endpoint_line = test_button.get_meta("endpoint_line", null) as LineEdit
	var api_key_line = test_button.get_meta("api_key_line", null) as LineEdit
	var model_line = test_button.get_meta("model_line", null) as LineEdit
	var reasoning_checkbox = test_button.get_meta("reasoning_checkbox", null) as CheckBox
	var formt_adapter_option = test_button.get_meta("formt_adapter_option", null) as OptionButton
	var reason_adapter_option = test_button.get_meta("reason_adapter_option", null) as OptionButton
	if save_button == null or provider_option == null or endpoint_line == null or api_key_line == null or model_line == null or reasoning_checkbox == null or formt_adapter_option == null or reason_adapter_option == null:
		return
	if not is_instance_valid(save_button) or not is_instance_valid(provider_option) or not is_instance_valid(endpoint_line) or not is_instance_valid(api_key_line) or not is_instance_valid(model_line) or not is_instance_valid(reasoning_checkbox) or not is_instance_valid(formt_adapter_option) or not is_instance_valid(reason_adapter_option):
		return
	_update_model_editor_save_state(
		save_button,
		int(test_button.get_meta("edit_index", -1)),
		model_line.text,
		_book_provider_selected(provider_option),
		endpoint_line.text,
		api_key_line.text,
		bool(reasoning_checkbox.button_pressed),
		_formt_adapter_selected(formt_adapter_option),
		_reason_adapter_selected(reason_adapter_option)
	)


func _apply_detected_model_adapters_to_test_button(test_button: Button) -> void:
	if test_button == null or not is_instance_valid(test_button):
		return
	var provider_option = test_button.get_meta("provider_option", null) as OptionButton
	var endpoint_line = test_button.get_meta("endpoint_line", null) as LineEdit
	var api_key_line = test_button.get_meta("api_key_line", null) as LineEdit
	var model_line = test_button.get_meta("model_line", null) as LineEdit
	var reasoning_checkbox = test_button.get_meta("reasoning_checkbox", null) as CheckBox
	var formt_adapter_option = test_button.get_meta("formt_adapter_option", null) as OptionButton
	var reason_adapter_option = test_button.get_meta("reason_adapter_option", null) as OptionButton
	if provider_option == null or endpoint_line == null or api_key_line == null or model_line == null or reasoning_checkbox == null or formt_adapter_option == null or reason_adapter_option == null:
		return
	if not is_instance_valid(provider_option) or not is_instance_valid(endpoint_line) or not is_instance_valid(api_key_line) or not is_instance_valid(model_line) or not is_instance_valid(reasoning_checkbox) or not is_instance_valid(formt_adapter_option) or not is_instance_valid(reason_adapter_option):
		return
	var provider_id := _book_provider_selected(provider_option)
	var endpoint_value: String = endpoint_line.text.strip_edges()
	var api_key_value: String = api_key_line.text
	var model_id: String = model_line.text.strip_edges()
	var reasoning_enabled := bool(reasoning_checkbox.button_pressed)
	var detected_formt_adapter := _model_detected_formt_adapter(provider_id, endpoint_value, api_key_value, model_id, reasoning_enabled)
	_model_config_log("apply detected adapters provider=%s endpoint=%s model=%s reasoning=%s detected_formt=%s detected_reason=%s ui_formt_before=%s ui_reason_before=%s" % [
		provider_id,
		endpoint_value,
		model_id,
		str(reasoning_enabled),
		detected_formt_adapter,
		_model_detected_reason_adapter(provider_id, endpoint_value, api_key_value, model_id, reasoning_enabled),
		_formt_adapter_selected(formt_adapter_option),
		_reason_adapter_selected(reason_adapter_option),
	])
	if _formt_adapter_can_save(detected_formt_adapter):
		_select_formt_adapter(formt_adapter_option, detected_formt_adapter)
	var detected_reason_adapter := _model_detected_reason_adapter(provider_id, endpoint_value, api_key_value, model_id, reasoning_enabled)
	if _reason_adapter_can_save(reasoning_enabled, detected_reason_adapter):
		_select_reason_adapter(reason_adapter_option, detected_reason_adapter)
	_model_config_log("apply detected adapters result ui_formt_after=%s ui_reason_after=%s" % [
		_formt_adapter_selected(formt_adapter_option),
		_reason_adapter_selected(reason_adapter_option),
	])


func _normalize_formt_adapter(value: String) -> String:
	return _adapter_registry.normalize_formt_adapter(value)


func _normalize_reason_adapter(value: String) -> String:
	return _adapter_registry.normalize_reason_adapter(value)


func _formt_adapter_can_save(formt_adapter: String) -> bool:
	return _adapter_registry.formt_adapter_can_save(formt_adapter)


func _reason_adapter_can_save(reasoning: bool, reason_adapter: String) -> bool:
	return _adapter_registry.reason_adapter_can_save(reasoning, reason_adapter)


func _formt_adapter_label(formt_adapter: String) -> String:
	return _adapter_registry.formt_adapter_label(formt_adapter)


func _reason_adapter_native_label(provider: String) -> String:
	return _adapter_registry.reason_adapter_native_label(provider)


func _reason_adapter_label(reason_adapter: String, provider: String = "") -> String:
	return _adapter_registry.reason_adapter_label(reason_adapter, provider)


func _formt_adapter_test_candidates(provider: String, model: String, selected_adapter: String = FORMT_ADAPTER_AUTO) -> Array:
	return _adapter_registry.formt_adapter_test_candidates(provider, model, selected_adapter)


func _provider_formt_adapter_candidates(provider: String, model: String = "") -> Array:
	return _adapter_registry.provider_formt_adapter_candidates(provider, model)


func _reason_adapter_detected_for_model(provider: String, model: String, formt_adapter: String = FORMT_ADAPTER_AUTO) -> String:
	return _adapter_registry.reason_adapter_detected_for_model(provider, model, formt_adapter)


func _reason_adapter_test_candidates(provider: String, model: String, reasoning: bool, formt_adapter: String = FORMT_ADAPTER_AUTO, selected_adapter: String = REASON_ADAPTER_AUTO) -> Array:
	return _adapter_registry.reason_adapter_test_candidates(provider, model, reasoning, formt_adapter, selected_adapter)


func _auto_reason_adapter_candidates(provider_candidates: Array, model: String) -> Array:
	return _adapter_registry.auto_reason_adapter_candidates(provider_candidates, model)


func _provider_reason_adapter_candidates(provider: String, model: String = "") -> Array:
	return _adapter_registry.provider_reason_adapter_candidates(provider, model)


func _unique_string_array(values: Array) -> Array:
	var result := []
	for value in values:
		var text := String(value).strip_edges()
		if text != "" and not result.has(text):
			result.append(text)
	return result


func _short_model_test_status(text: String) -> String:
	var clean := text.strip_edges().replace("\r", " ").replace("\n", " ")
	while clean.contains("  "):
		clean = clean.replace("  ", " ")
	if clean.length() > 64:
		return "%s..." % clean.substr(0, 61)
	return clean


func _api_key_state(api_key: String) -> String:
	return "set" if api_key.strip_edges() != "" else "empty"


func _book_checkbox_line(parent: VBoxContainer, title: String, value: bool, text: String = "启用", label_width: float = 0.0) -> CheckBox:
	var checkbox := CheckBox.new()
	checkbox.text = text
	checkbox.button_pressed = value
	checkbox.focus_mode = Control.FOCUS_NONE
	checkbox.custom_minimum_size = Vector2(0, 32)
	_style_book_checkbox(checkbox)
	_book_control_row(parent, title, checkbox, "", 0.0, label_width)
	return checkbox


func _model_config_log(message: String, warn: bool = false) -> void:
	var line := "[ModelConfig] %s" % message
	if warn:
		push_warning(line)
	else:
		print(line)



func _clean_model_endpoint(endpoint: String) -> String:
	var clean := endpoint.strip_edges()
	while clean.ends_with("/") and clean.length() > 1:
		clean = clean.substr(0, clean.length() - 1)
	return clean



func _book_provider_dropdown(provider: String) -> OptionButton:
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(0, 32)
	option.focus_mode = Control.FOCUS_NONE
	var selected := 0
	var provider_id := _model_provider_id(provider)
	var options := _model_provider_options()
	for i in range(options.size()):
		var item: Dictionary = options[i]
		option.add_item(String(item.get("label", "")))
		var item_index := option.get_item_count() - 1
		option.set_item_metadata(item_index, String(item.get("id", "")))
		if String(item.get("id", "")) == provider_id:
			selected = item_index
	option.select(selected)
	_style_book_option(option)
	return option



func _book_provider_selected(option: OptionButton) -> String:
	if option == null or option.selected < 0:
		return "openai_api"
	var meta = option.get_item_metadata(option.selected)
	return _model_provider_id(String(meta))


func _book_formt_adapter_dropdown(provider: String, formt_adapter: String) -> OptionButton:
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(0, 32)
	option.focus_mode = Control.FOCUS_NONE
	_populate_formt_adapter_dropdown(option, provider, formt_adapter)
	_style_book_option(option)
	return option


func _book_reason_adapter_dropdown(provider: String, reason_adapter: String, model: String = "", reasoning: bool = false) -> OptionButton:
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(0, 32)
	option.focus_mode = Control.FOCUS_NONE
	_populate_reason_adapter_dropdown(option, provider, model, reason_adapter, reasoning)
	_style_book_option(option)
	return option


func _populate_formt_adapter_dropdown(option: OptionButton, provider: String, selected_adapter: String) -> void:
	if option == null:
		return
	var selected := _normalize_formt_adapter(selected_adapter)
	var candidates := _provider_formt_adapter_candidates(provider)
	option.clear()
	option.add_item(_formt_adapter_label(FORMT_ADAPTER_AUTO))
	option.set_item_metadata(option.get_item_count() - 1, FORMT_ADAPTER_AUTO)
	for adapter in candidates:
		option.add_item(_formt_adapter_label(String(adapter)))
		option.set_item_metadata(option.get_item_count() - 1, String(adapter))
	if not candidates.has(selected):
		selected = FORMT_ADAPTER_AUTO
	_select_formt_adapter(option, selected)


func _populate_reason_adapter_dropdown(option: OptionButton, provider: String, model: String, selected_adapter: String, reasoning: bool) -> void:
	if option == null:
		return
	var _unused_model := model
	var _unused_reasoning := reasoning
	var selected := _normalize_reason_adapter(selected_adapter)
	var candidates := _provider_reason_adapter_candidates(provider)
	option.clear()
	option.add_item(_reason_adapter_label(REASON_ADAPTER_AUTO, provider))
	option.set_item_metadata(option.get_item_count() - 1, REASON_ADAPTER_AUTO)
	for adapter in candidates:
		option.add_item(_reason_adapter_label(String(adapter), provider))
		option.set_item_metadata(option.get_item_count() - 1, String(adapter))
	if selected != REASON_ADAPTER_AUTO and not _reason_adapter_present_in_option(option, selected):
		selected = REASON_ADAPTER_AUTO
	_select_reason_adapter(option, selected)
	_model_config_log("populate reason adapter provider=%s model=%s reasoning=%s selected_request=%s selected_final=%s count=%d" % [
		provider,
		model,
		str(reasoning),
		selected_adapter,
		_reason_adapter_selected(option),
		option.get_item_count(),
	])


func _formt_adapter_selected(option: OptionButton) -> String:
	if option == null or option.selected < 0:
		return FORMT_ADAPTER_AUTO
	var meta = option.get_item_metadata(option.selected)
	return _normalize_formt_adapter(String(meta))


func _reason_adapter_selected(option: OptionButton) -> String:
	if option == null or option.selected < 0:
		return REASON_ADAPTER_AUTO
	var meta = option.get_item_metadata(option.selected)
	return _normalize_reason_adapter(String(meta))


func _select_formt_adapter(option: OptionButton, formt_adapter: String) -> void:
	if option == null:
		return
	var adapter := _normalize_formt_adapter(formt_adapter)
	for i in range(option.get_item_count()):
		if _normalize_formt_adapter(String(option.get_item_metadata(i))) == adapter:
			option.select(i)
			return
	for i in range(option.get_item_count()):
		if _normalize_formt_adapter(String(option.get_item_metadata(i))) == FORMT_ADAPTER_AUTO:
			option.select(i)
			return


func _select_reason_adapter(option: OptionButton, reason_adapter: String) -> void:
	if option == null:
		return
	var adapter := _normalize_reason_adapter(reason_adapter)
	for i in range(option.get_item_count()):
		if _normalize_reason_adapter(String(option.get_item_metadata(i))) == adapter:
			option.select(i)
			return
	for i in range(option.get_item_count()):
		if _normalize_reason_adapter(String(option.get_item_metadata(i))) == REASON_ADAPTER_AUTO:
			option.select(i)
			return


func _reason_adapter_present_in_option(option: OptionButton, reason_adapter: String) -> bool:
	for i in range(option.get_item_count()):
		if _normalize_reason_adapter(String(option.get_item_metadata(i))) == _normalize_reason_adapter(reason_adapter):
			return true
	return false



func _model_provider_options() -> Array:
	return [
		{"id": "openai_api", "label": "OpenAI API", "endpoint": "https://api.openai.com/v1"},
		{"id": "anthropic", "label": "Anthropic", "endpoint": "https://api.anthropic.com/v1"},
		{"id": "gemini", "label": "Gemini", "endpoint": "https://generativelanguage.googleapis.com/v1beta"},
		{"id": "ollama", "label": "Ollama", "endpoint": "http://127.0.0.1:11434/api"},
	]



func _model_provider_id(provider: String) -> String:
	return _adapter_registry.model_provider_id(provider)



func _model_provider_label(provider: String) -> String:
	var provider_id := _model_provider_id(provider)
	for item in _model_provider_options():
		if item is Dictionary and String((item as Dictionary).get("id", "")) == provider_id:
			return String((item as Dictionary).get("label", "OpenAI API"))
	return "OpenAI API"



func _model_provider_default_endpoint(provider: String) -> String:
	var provider_id := _model_provider_id(provider)
	for item in _model_provider_options():
		if item is Dictionary and String((item as Dictionary).get("id", "")) == provider_id:
			return String((item as Dictionary).get("endpoint", "https://api.openai.com/v1"))
	return "https://api.openai.com/v1"



func _model_endpoint_should_follow(endpoint: String) -> bool:
	var clean := endpoint.strip_edges()
	if clean == "":
		return true
	for item in _model_provider_options():
		if item is Dictionary and clean == String((item as Dictionary).get("endpoint", "")):
			return true
	return false



func _context_tokens_from_max_context(max_context: int) -> int:
	return maxi(1, roundi(float(maxi(1, max_context)) * CONTEXT_WINDOW_UI_RATIO))


func _context_tokens_from_max_token(max_token: int) -> int:
	return _context_tokens_from_max_context(max_token)


func _tokens_from_context_text(text: String) -> int:
	var clean := text.strip_edges().to_lower()
	var multiplier := 1
	if clean.ends_with("k"):
		multiplier = 1024
		clean = clean.trim_suffix("k").strip_edges()
	var value := clean.to_int()
	if value <= 0:
		return DEFAULT_MAX_CONTEXT_TOKEN
	return maxi(1, value * multiplier)

func _positive_int_from_text(text: String, default_value: int) -> int:
	var value := text.strip_edges().to_int()
	if value <= 0:
		value = default_value
	return maxi(1, value)


func _temperature_from_text(text: String, default_value: float) -> float:
	var clean := text.strip_edges()
	var value := default_value
	if clean != "":
		value = clean.to_float()
	return clampf(value, 0.0, 2.0)


func _format_model_temperature(value: float) -> String:
	return "%.2f" % clampf(value, 0.0, 2.0)



func _context_token_label(tokens: int) -> String:
	return "%s %d" % [CONTEXT_TOKEN_LABEL, maxi(1, tokens)]


func _max_context_tokens_from_config(config: Dictionary, default_value: int = 262144) -> int:
	return maxi(1, int(config.get("max_context", config.get("max_token", default_value))))


func _max_output_tokens_from_config(config: Dictionary, default_value: int = DEFAULT_MAX_OUTPUT_TOKEN) -> int:
	if config.has("max_output"):
		return maxi(1, int(config.get("max_output", default_value)))
	return default_value


func _max_context_label(tokens: int) -> String:
	return "%s %d" % [MAX_CONTEXT_LABEL, maxi(1, tokens)]


func _max_output_label(tokens: int) -> String:
	return "%s %d" % [MAX_OUTPUT_TOKEN_LABEL, maxi(1, tokens)]



func _fetch_model_catalog(provider: String, endpoint: String, api_key: String, status_label: Label = null, list: Control = null, model_line: LineEdit = null, mode: String = "single", selected_state: Dictionary = {}) -> void:
	if list == null:
		_model_config_log("catalog request skipped: list control is null mode=%s provider=%s endpoint=%s" % [mode, _model_provider_id(provider), endpoint.strip_edges()], true)
		return
	for child in list.get_children():
		child.queue_free()
	var provider_id := _model_provider_id(provider)
	var base_url := endpoint.strip_edges()
	var profile := {
		"provider": provider_id,
		"endpoint": base_url,
		"api_key": api_key,
	}
	var request_id := int(_model_catalog_client.list_models(profile, 20.0))
	_model_catalog_requests[request_id] = {
		"status": status_label,
		"list": list,
		"model_line": model_line,
		"mode": mode,
		"selected": selected_state,
		"provider": provider_id,
		"endpoint": base_url,
	}
	_model_config_log("catalog request started id=%d mode=%s provider=%s endpoint=%s api_key=%s" % [request_id, mode, provider_id, base_url, _api_key_state(api_key)])
	if status_label != null:
		_book_status(status_label, "正在拉取模型列表...", BOOK_GREEN)
	_show_toast("正在获取模型...", BOOK_GREEN)



func _on_model_catalog_completed(request_id: int, ok: bool, models: Array, error: String) -> void:
	if not _model_catalog_requests.has(request_id):
		return
	var request: Dictionary = _model_catalog_requests[request_id]
	_model_catalog_requests.erase(request_id)
	var mode := String(request.get("mode", "single"))
	var provider := String(request.get("provider", ""))
	var endpoint := String(request.get("endpoint", ""))
	var status := request.get("status") as Label
	var list := request.get("list") as Control
	var model_line := request.get("model_line") as LineEdit
	if list == null:
		_model_config_log("catalog request completed id=%d mode=%s provider=%s endpoint=%s but list control is null" % [request_id, mode, provider, endpoint], true)
		return
	for child in list.get_children():
		child.queue_free()
	if not ok:
		_model_config_log("catalog request completed id=%d mode=%s provider=%s endpoint=%s ok=false error=%s" % [request_id, mode, provider, endpoint, _short_model_test_status(error)], true)
		if status != null:
			_book_status(status, "拉取失败：%s" % error, BOOK_RED)
		_show_toast("获取模型失败：%s" % _short_model_test_status(error), BOOK_RED)
		return
	if models.is_empty():
		_model_config_log("catalog request completed id=%d mode=%s provider=%s endpoint=%s ok=true models=0" % [request_id, mode, provider, endpoint], true)
		if status != null:
			_book_status(status, "没有返回可用模型", BOOK_MUTED)
		_show_toast("没有返回可用模型", BOOK_MUTED)
		return
	_model_config_log("catalog request completed id=%d mode=%s provider=%s endpoint=%s ok=true models=%d" % [request_id, mode, provider, endpoint, models.size()])
	if mode == "batch":
		_fill_batch_model_catalog(models, list, request.get("selected", {}))
		_show_toast("已获取 %d 个模型" % models.size(), BOOK_GREEN)
		return
	if model_line == null:
		return
	if status != null:
		_book_status(status, "选择一个模型填入", BOOK_GREEN)
	var limit: int = mini(models.size(), 18)
	for i in range(limit):
		var item = models[i]
		if item is Dictionary:
			var id := String(item.get("id", ""))
			if id != "":
				list.add_child(_catalog_model_chip(id, model_line))
	if models.size() > limit:
		list.add_child(_book_label("+%d" % [models.size() - limit], 11, BOOK_MUTED, true))



func _fill_batch_model_catalog(models: Array, list: Control, selected_state: Dictionary) -> void:
	selected_state.clear()
	var added := 0
	for item in models:
		if not (item is Dictionary):
			continue
		var model_id := String((item as Dictionary).get("id", "")).strip_edges()
		if model_id == "":
			continue
		selected_state[model_id] = true
		var checkbox := CheckBox.new()
		checkbox.text = model_id
		checkbox.button_pressed = true
		checkbox.focus_mode = Control.FOCUS_NONE
		checkbox.custom_minimum_size = Vector2(0, 34)
		checkbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_book_checkbox(checkbox)
		checkbox.toggled.connect(_on_batch_model_checkbox_toggled.bind(selected_state, model_id))
		var scroll := _parent_scroll_container(list)
		if scroll != null:
			_enable_catalog_drag_scroll(scroll, checkbox)
		list.add_child(checkbox)
		added += 1
	if added == 0:
		_show_toast("没有可添加的模型", BOOK_MUTED)



func _on_batch_model_checkbox_toggled(pressed: bool, selected_state: Dictionary, model_id: String) -> void:
	selected_state[model_id] = pressed


func _parent_scroll_container(control: Control) -> ScrollContainer:
	var node := control.get_parent()
	while node != null:
		if node is ScrollContainer:
			return node as ScrollContainer
		node = node.get_parent()
	return null


func _enable_catalog_drag_scroll(scroll: ScrollContainer, control: Control) -> void:
	if scroll == null or control == null:
		return
	control.gui_input.connect(func(event: InputEvent):
		if event is InputEventScreenDrag:
			scroll.scroll_vertical = maxi(0, scroll.scroll_vertical - int((event as InputEventScreenDrag).relative.y))
		elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			scroll.scroll_vertical = maxi(0, scroll.scroll_vertical - int((event as InputEventMouseMotion).relative.y))
	)



func _catalog_model_chip(model_id: String, model_line: LineEdit) -> Button:
	var button := Button.new()
	button.text = model_id
	button.custom_minimum_size = Vector2(0, 30)
	button.focus_mode = Control.FOCUS_NONE
	_style_book_button(button, false)
	button.pressed.connect(func():
		_play_click()
		model_line.text = model_id
	)
	return button



func _save_model_config(index: int, model: String, provider: String, endpoint: String, memory: String, api_key: String = "", context_window_tokens: int = 8192, max_context: int = 262144, max_output: int = DEFAULT_MAX_OUTPUT_TOKEN, temperature: float = 0.6, reasoning: bool = false, formt_adapter: String = FORMT_ADAPTER_AUTO, reason_adapter: String = REASON_ADAPTER_AUTO) -> void:
	var model_id := model.strip_edges()
	var existing_id := int(_model_configs[index].get("id", 0)) if index >= 0 and index < _model_configs.size() and _model_configs[index] is Dictionary else 0
	var adapter := _normalize_formt_adapter(formt_adapter)
	if not _formt_adapter_can_save(adapter):
		adapter = _model_detected_formt_adapter(_model_provider_id(provider), endpoint, api_key, model_id, reasoning)
	if not _formt_adapter_can_save(adapter):
		_model_config_log("save blocked: invalid formt_adapter index=%d provider=%s endpoint=%s model=%s adapter=%s" % [index, _model_provider_id(provider), endpoint.strip_edges(), model_id, formt_adapter], true)
		_show_toast("请先通过结构化测试选择具体适配器", BOOK_RED)
		return
	var thinking_adapter := _normalize_reason_adapter(reason_adapter)
	if not _reason_adapter_can_save(reasoning, thinking_adapter):
		thinking_adapter = _model_detected_reason_adapter(_model_provider_id(provider), endpoint, api_key, model_id, reasoning)
	if not _reason_adapter_can_save(reasoning, thinking_adapter):
		_model_config_log("save blocked: invalid reason_adapter index=%d provider=%s endpoint=%s model=%s adapter=%s" % [index, _model_provider_id(provider), endpoint.strip_edges(), model_id, reason_adapter], true)
		_show_toast("请先通过思考模式测试选择具体适配器", BOOK_RED)
		return
	_model_config_log("save requested index=%d id=%d provider=%s endpoint=%s model=%s formt_adapter=%s reason_adapter=%s max_context=%d context=%d max_output=%d temperature=%.2f reasoning=%s api_key=%s" % [index, existing_id, _model_provider_id(provider), endpoint.strip_edges(), model_id, adapter, thinking_adapter, max_context, context_window_tokens, max_output, temperature, reasoning, _api_key_state(api_key)])
	var item := _model_config_item(existing_id, model_id, _model_provider_id(provider), endpoint, api_key, context_window_tokens, max_context, max_output, temperature, reasoning, adapter, thinking_adapter)
	if _model_config_requires_schema_test(index, item) and not _model_schema_test_passed_for_item(item):
		_model_config_log("save blocked: schema test missing index=%d provider=%s endpoint=%s model=%s formt_adapter=%s reasoning=%s" % [index, _model_provider_id(provider), endpoint.strip_edges(), model_id, adapter, reasoning], true)
		_show_toast("请先通过模型结构化测试", BOOK_RED)
		return
	if not _save_model_config_item(index, item, true):
		return
	_commit_state()
	_show_toast("模型已保存", BOOK_GREEN)
	_show_model_config_page()


func _model_config_item(id: int, model_name: String, provider: String, endpoint: String, api_key: String, context_window_tokens: int, max_context: int, max_output: int, temperature: float, reasoning: bool = false, formt_adapter: String = FORMT_ADAPTER_AUTO, reason_adapter: String = REASON_ADAPTER_AUTO) -> Dictionary:
	var clean_model := model_name.strip_edges()
	return {
		"id": id,
		"model": clean_model,
		"provider": _model_provider_id(provider),
		"endpoint": endpoint.strip_edges(),
		"memory": "",
		"api_key": api_key.strip_edges(),
		"context_window_tokens": maxi(1, context_window_tokens),
		"max_context": maxi(1, max_context),
		"max_output": maxi(1, max_output),
		"temperature": clampf(temperature, 0.0, 2.0),
		"reasoning": reasoning,
		"formt_adapter": _normalize_formt_adapter(formt_adapter),
		"reason_adapter": _normalize_reason_adapter(reason_adapter),
	}


func _save_model_config_item(index: int, item: Dictionary, show_error: bool = true) -> bool:
	if not _formt_adapter_can_save(String(item.get("formt_adapter", FORMT_ADAPTER_AUTO))):
		if show_error:
			_show_toast("模型适配器必须先通过测试后保存", BOOK_RED)
		return false
	if not _reason_adapter_can_save(bool(item.get("reasoning", false)), String(item.get("reason_adapter", REASON_ADAPTER_AUTO))):
		if show_error:
			_show_toast("思考兼容必须先通过测试后保存", BOOK_RED)
		return false
	var store_available := _model_config_store.is_available()
	_model_config_log("save path persistence_enabled=%s store_backend=%s store_available=%s model=%s endpoint=%s id=%d" % [
		str(bool(_app_state != null and _app_state.persistence_enabled)),
		str(_model_config_store.backend_attached()),
		str(store_available),
		String(item.get("model", "")),
		String(item.get("endpoint", "")),
		int(item.get("id", 0)),
	], not store_available)
	if bool(_app_state != null and _app_state.persistence_enabled) and _model_config_store.backend_attached() and not store_available:
		if show_error:
			_show_toast("模型配置存储不可用，未写入数据库", BOOK_RED)
		return false
	if store_available:
		var saved := _model_config_store.save_config(item)
		if not bool(saved.get("ok", false)):
			if show_error:
				_show_toast(String(saved.get("error", "模型保存失败")), BOOK_RED)
			return false
		_model_config_log("model store save ok id=%d provider=%s endpoint=%s model=%s formt_adapter=%s reason_adapter=%s" % [
			int(saved.get("id", 0)),
			String(saved.get("provider", "")),
			String(saved.get("endpoint", "")),
			String(saved.get("model", "")),
			String(saved.get("formt_adapter", FORMT_ADAPTER_AUTO)),
			String(saved.get("reason_adapter", REASON_ADAPTER_AUTO)),
		])
		saved.erase("ok")
		if index >= 0 and index < _model_configs.size():
			_model_configs[index] = saved
		else:
			_model_configs.append(saved)
		_model_configs = _model_config_store.list_configs()
		for stored_item in _model_configs:
			if not (stored_item is Dictionary):
				continue
			var stored: Dictionary = stored_item
			if int(stored.get("id", 0)) == int(saved.get("id", 0)):
				_model_config_log("model store reload item id=%d provider=%s endpoint=%s model=%s formt_adapter=%s reason_adapter=%s" % [
					int(stored.get("id", 0)),
					String(stored.get("provider", "")),
					String(stored.get("endpoint", "")),
					String(stored.get("model", "")),
					String(stored.get("formt_adapter", FORMT_ADAPTER_AUTO)),
					String(stored.get("reason_adapter", REASON_ADAPTER_AUTO)),
				])
				break
		return true
	if bool(_app_state != null and _app_state.persistence_enabled):
		_model_config_log("save blocked: persistence enabled but model store unavailable model=%s endpoint=%s" % [
			String(item.get("model", "")),
			String(item.get("endpoint", "")),
		], true)
		if show_error:
			_show_toast("模型配置未写入数据库，请稍后重试", BOOK_RED)
		return false
	_model_configs = _config_repository.save_model(_model_configs, index, String(item.get("model", "")), String(item.get("provider", "")), String(item.get("endpoint", "")), "", String(item.get("api_key", "")), int(item.get("context_window_tokens", 8192)), int(item.get("max_context", item.get("max_token", 262144))), _max_output_tokens_from_config(item), float(item.get("temperature", 0.6)), bool(item.get("reasoning", false)), String(item.get("formt_adapter", FORMT_ADAPTER_AUTO)), String(item.get("reason_adapter", REASON_ADAPTER_AUTO)))
	return true



func _delete_model_config(index: int) -> void:
	if index >= 0 and index < _model_configs.size() and _model_configs[index] is Dictionary:
		var model_name := String((_model_configs[index] as Dictionary).get("model", (_model_configs[index] as Dictionary).get("name", ""))).strip_edges()
		var users := _bot_profiles_using_model_name(model_name)
		if not users.is_empty():
			_model_config_log("delete blocked: model=%s used_by=%s" % [model_name, _bot_usage_names(users)], true)
			_show_toast("模型正在被机器人使用：%s，不能删除" % _bot_usage_names(users), BOOK_RED)
			return
	if index >= 0 and index < _model_configs.size() and _model_configs[index] is Dictionary and _model_config_store.is_available():
		var deleted := _model_config_store.delete_config(int((_model_configs[index] as Dictionary).get("id", 0)))
		if not bool(deleted.get("ok", false)):
			_show_toast(String(deleted.get("error", "模型删除失败")), BOOK_RED)
			return
	_model_configs = _config_repository.delete_at(_model_configs, index)
	_commit_state()
	_show_toast("模型已删除", BOOK_GREEN)
	_show_model_config_page()


