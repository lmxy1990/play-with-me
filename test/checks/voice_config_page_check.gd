extends SceneTree


class FakeAvailabilityRuntime:
	extends RefCounted

	func is_engine_available(engine: String) -> bool:
		return ["system", "multi_tts"].has(engine)

	func available_system_voices(_language: String = "") -> Array:
		return [
			{"id": "zh-CN::female", "name": "Chinese Female", "engine": "system", "language": "zh-CN"},
			{"id": "en-US::female", "name": "English Female", "engine": "system", "language": "en-US"},
			{"id": "en-US::male", "name": "English Male", "engine": "system", "language": "en-US"},
		]

	func available_external_voices(engine: String, _language: String = "") -> Array:
		return [
			{"id": "en-US::neko-female", "name": "Neko Female", "engine": engine, "language": "en-US", "networkRequired": true},
			{"id": "zh-CN::neko-female", "name": "Neko Female CN", "engine": engine, "language": "zh-CN", "networkRequired": true},
			{"id": "cmn-Hans-CN::neko-male", "name": "Neko Male", "engine": engine, "language": "cmn-Hans-CN", "networkRequired": true},
		]

	func stop() -> void:
		pass


func _initialize() -> void:
	var state = load("res://scripts/core/app_state.gd").new()
	state.persistence_enabled = false
	state.load_or_create()

	var packed := load("res://scenes/voice_config.tscn") as PackedScene
	var page := packed.instantiate() as Control
	page.set_app_state(state)
	root.add_child(page)
	await process_frame

	var parent := VBoxContainer.new()
	root.add_child(parent)
	var engine_dropdown: OptionButton = page._book_voice_engine_dropdown(parent, "kokoro", Callable())
	assert(engine_dropdown.get_item_count() == 5)
	assert(String(engine_dropdown.get_item_metadata(engine_dropdown.selected)) == "local_kokoro")
	assert(page._voice_supported_engine_or_default("NekoTTS") == "neko_tts")
	assert(page._voice_supported_engine_or_default("VoxSherpa-TTS") == "voxsherpa_tts")
	assert(page._voice_supported_engine_or_default("MultiTTS") == "multi_tts")
	var original_runtime = page._tts_runtime
	page._tts_runtime = FakeAvailabilityRuntime.new()
	var filtered_engine_dropdown: OptionButton = page._book_voice_engine_dropdown(parent, "NekoTTS", Callable())
	assert(filtered_engine_dropdown.get_item_count() == 5)
	assert(String(filtered_engine_dropdown.get_item_metadata(filtered_engine_dropdown.selected)) == "neko_tts")
	var available_options: Array = page._voice_engine_options(true)
	assert(available_options.size() == 2)
	assert(String((available_options[0] as Dictionary).get("id", "")) == "system")
	assert(String((available_options[1] as Dictionary).get("id", "")) == "multi_tts")
	assert(page._voice_supported_engine_or_default("NekoTTS", true) == "system")
	page._tts_runtime = original_runtime

	var gender_switch: CheckButton = page._book_gender_switch(parent, "男声", Callable(), [])
	assert(gender_switch.button_pressed)
	assert(gender_switch.text == "男声")
	page._book_gender_switch_update(gender_switch, "女声", ["男声"])
	assert(not gender_switch.button_pressed)
	assert(gender_switch.disabled)

	var voice_dropdown: OptionButton = page._book_voice_dropdown("local_kokoro", "女声", "")
	assert(voice_dropdown.get_item_count() > 0)
	assert(String(page._book_voice_selected(voice_dropdown)).begins_with("zf_"))
	var first_female_voice := String(page._book_voice_selected(voice_dropdown))
	page._populate_voice_dropdown(voice_dropdown, "local_kokoro", "男声", "")
	assert(String(page._book_voice_selected(voice_dropdown)).begins_with("zm_"))
	assert(String(page._book_voice_selected(voice_dropdown)) != first_female_voice)
	page._tts_runtime = FakeAvailabilityRuntime.new()
	var external_voice_dropdown: OptionButton = page._book_voice_dropdown("NekoTTS", "女声", "")
	assert(external_voice_dropdown.get_item_count() >= 2)
	assert(String(page._book_voice_selected(external_voice_dropdown)) == "")
	assert(String(external_voice_dropdown.get_item_text(external_voice_dropdown.selected)).contains("NekoTTS默认"))
	assert(page._system_tts_voices("女声").size() == 2)
	assert(String((page._system_tts_voices("女声")[1] as Dictionary).get("id", "")) == "en-US::female")
	assert(page._system_tts_voices("男声").size() == 1)
	assert(String((page._system_tts_voices("男声")[0] as Dictionary).get("id", "")) == "en-US::male")
	assert(page._external_tts_voices("NekoTTS", "女声").size() == 2)
	assert(String((page._external_tts_voices("NekoTTS", "女声")[0] as Dictionary).get("id", "")) == "en-US::neko-female")
	assert(String((page._external_tts_voices("NekoTTS", "女声")[1] as Dictionary).get("id", "")) == "zh-CN::neko-female")
	page._tts_runtime = original_runtime
	var state_row: Dictionary = page._book_voice_state_row(parent, true, false)
	assert(state_row.has("enabled"))
	assert(state_row.has("active"))
	assert(bool((state_row["enabled"] as CheckBox).button_pressed))
	assert(not bool((state_row["active"] as CheckBox).button_pressed))
	var action_row: HBoxContainer = page._book_voice_editor_action_row(parent)
	action_row.add_child(Button.new())
	action_row.add_child(Button.new())
	action_row.add_child(Button.new())
	assert(action_row.get_child_count() == 3)
	assert(action_row.alignment == BoxContainer.ALIGNMENT_END)
	assert(int(action_row.get_theme_constant("separation")) <= 8)

	var normalized: Array = page._normalize_voice_configs([
		{"id": 1, "name": "停用主用", "engine": "system", "enabled": false, "active": true},
		{"id": 2, "name": "启用一", "engine": "system", "enabled": true, "active": true},
		{"id": 3, "name": "启用二", "engine": "kokoro", "enabled": true, "active": true},
	])
	var active_count := 0
	for item in normalized:
		if item is Dictionary and bool((item as Dictionary).get("active", false)):
			active_count += 1
	assert(active_count == 1)
	assert(bool((normalized[1] as Dictionary).get("active", false)))
	assert(not bool((normalized[0] as Dictionary).get("active", false)))
	assert(String((normalized[1] as Dictionary).get("key", "")) == "voice_config_2")

	var preview_label := RichTextLabel.new()
	parent.add_child(preview_label)
	page._voice_preview_text_label = preview_label
	page._update_voice_preview_text("试听文本", 0.0, false)
	assert(preview_label.text == "试听文本")
	assert(not preview_label.bbcode_enabled)
	page._update_voice_preview_text("试听文本", 0.5, true)
	assert(preview_label.bbcode_enabled)
	assert(preview_label.text.find("[b]试听") >= 0)

	page._voice_configs = page._tts_voice_repository.set_profiles([
		{"id": 1, "name": "系统默认", "engine": "local_kokoro", "gender": "女声", "voice": "zf_001", "enabled": true, "active": true},
		{"id": 2, "name": "旁白", "engine": "system", "gender": "女声", "voice": "", "enabled": true, "active": false},
	])
	page._bot_profiles = [
		{"id": "bot_voice_user", "name": "声音用户", "model": "qwen:test", "voice": "旁白", "enabled": true},
	]
	var voice_index := _find_voice_index(page, "旁白")
	assert(voice_index >= 0)
	page._delete_voice_config(voice_index)
	assert(_find_voice_index(page, "旁白") >= 0)
	page._bot_profiles = []
	page._delete_voice_config(voice_index)
	assert(_find_voice_index(page, "旁白") < 0)

	voice_dropdown.queue_free()
	external_voice_dropdown.queue_free()
	filtered_engine_dropdown.queue_free()
	page.queue_free()
	parent.queue_free()
	await process_frame
	await process_frame
	quit()


func _find_voice_index(page: Control, profile_name: String) -> int:
	for i in range(page._voice_configs.size()):
		if page._voice_configs[i] is Dictionary and String((page._voice_configs[i] as Dictionary).get("name", "")) == profile_name:
			return i
	return -1
