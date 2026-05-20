extends SceneTree


func _initialize() -> void:
	var state = load("res://scripts/core/app_state.gd").new()
	state.persistence_enabled = false
	state.load_or_create()
	state.bot_profiles = [
		{
			"id": "bot_ui_alpha",
			"name": "界面机器人",
			"avatar_id": "avatar_01",
			"description": "页面检查",
			"persona": "谨慎，优先复核证据。",
			"model": "qwen:test",
			"voice": "系统默认",
			"enabled": true,
			"memory": {},
		},
	]

	var packed := load("res://scenes/bot_config.tscn") as PackedScene
	var page := packed.instantiate() as Control
	page.set_app_state(state)
	root.add_child(page)
	await process_frame
	assert(String(page._bot_profiles[0].get("name", "")) == "界面机器人")
	var save_result: Dictionary = page._bot_profile_repository.save_profile(0, {
		"name": "手动改名",
		"model": "qwen-renamed",
		"voice": "系统默认",
		"enabled": true,
	})
	assert(bool(save_result.get("ok", false)))
	assert(String((save_result.get("profile", {}) as Dictionary).get("name", "")) == "手动改名")
	page._bot_profiles = page._bot_profile_repository.list_profiles()
	page._model_configs = [
		{"model": "qwen-plus", "endpoint": "http://localhost"},
		{"model": "deepseek-chat", "endpoint": "http://localhost"},
	]
	assert(page._bot_name_from_model_name(page._default_bot_model_name(), -1) == "qwen-plus")
	page._bot_profiles.append({
		"id": "bot_ui_dup",
		"name": "deepseek-chat",
		"model": "deepseek-chat",
		"voice": "系统默认",
		"enabled": true,
	})
	assert(page._bot_name_from_model_name("deepseek-chat", -1) == "deepseek-chat 2")
	page._bot_editor(-1)
	await process_frame
	var bot_name_input := _find_line_edit_with_text(page, "qwen-plus")
	assert(bot_name_input != null)
	assert(bot_name_input.editable)
	var model_dropdown := _find_option_with_item(page, "deepseek-chat")
	assert(model_dropdown != null)
	model_dropdown.select(1)
	model_dropdown.item_selected.emit(1)
	await process_frame
	assert(bot_name_input.text == "deepseek-chat 2")
	bot_name_input.text = "自定义机器人"
	model_dropdown.select(0)
	model_dropdown.item_selected.emit(0)
	await process_frame
	assert(bot_name_input.text == "自定义机器人")
	assert(page._bot_name_for_save(-1, "deepseek-chat") == "deepseek-chat 2")
	assert(page._bot_name_for_save(-1, "deepseek-chat", "自定义机器人") == "自定义机器人")
	assert(page._bot_name_for_save(0, "deepseek-chat", "界面机器人") == "界面机器人")
	page._clear_modal()
	await process_frame

	var init_result: Dictionary = page._bot_facade.initialize_bot({
		"bot_id": "bot_ui_alpha",
		"scope": page._bot_profile_memory_scope({"id": "bot_ui_alpha"}),
		"persona_template": {"content": "谨慎，优先复核证据。"},
		"reason": "ui_check",
	})
	assert(bool(init_result.get("ok", false)))
	var commit_result: Dictionary = page._bot_facade.commit_bot_result({
		"bot_id": "bot_ui_alpha",
		"scope": page._bot_profile_memory_scope({"id": "bot_ui_alpha"}),
		"commit_reason": "ui_check",
		"memory_update": {
			"visibility": "self_private",
			"working_update": {"current_goal": "检查机器人记忆页面。"},
			"episodic_events": [
				{"content": "页面检查写入一条事件记忆。"},
			],
		},
	})
	assert(bool(commit_result.get("ok", false)))

	page._show_bot_memory_page(0)
	await process_frame
	assert(page._scene_root.get_child_count() > 0)
	var overview: Dictionary = page._bot_facade.get_bot_memory_overview({
		"bot_id": "bot_ui_alpha",
		"scope": page._bot_profile_memory_scope({"id": "bot_ui_alpha"}),
	})
	assert(bool(overview.get("ok", false)))
	var counts: Dictionary = (overview.get("data", {}) as Dictionary).get("layer_counts", {}) as Dictionary
	assert(int(counts.get("profile", 0)) == 1)
	assert(int(counts.get("working", 0)) == 1)
	assert(int(counts.get("episodic", 0)) == 1)

	page.queue_free()
	quit(0)


func _find_line_edit_with_text(root_node: Node, text: String) -> LineEdit:
	for child in root_node.find_children("*", "LineEdit", true, false):
		var line := child as LineEdit
		if line != null and line.text == text:
			return line
	return null


func _find_option_with_item(root_node: Node, item_text: String) -> OptionButton:
	for child in root_node.find_children("*", "OptionButton", true, false):
		var option := child as OptionButton
		if option == null:
			continue
		for i in range(option.item_count):
			if option.get_item_text(i) == item_text:
				return option
	return null
