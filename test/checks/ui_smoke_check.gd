extends SceneTree


class FakeUiScanner:
	extends RefCounted

	signal scan_succeeded(payload: String)
	signal scan_failed(error: String)
	signal scan_cancelled()

	var started := 0

	func start_scan() -> Dictionary:
		started += 1
		return {"ok": true}


func _initialize() -> void:
	var state = load("res://scripts/core/app_state.gd").new()
	state.persistence_enabled = false
	state.load_or_create()

	var lobby := _page("res://scenes/lobby.tscn", state)
	root.add_child(lobby)
	await process_frame
	lobby._open_create_room()
	await process_frame
	lobby._clear_modal()
	lobby._open_scan_join()
	await process_frame
	lobby._clear_modal()
	var scanner := FakeUiScanner.new()
	lobby.set_android_qr_scanner(scanner)
	lobby._open_scan_join(true)
	await process_frame
	await process_frame
	assert(scanner.started == 1)
	assert(lobby._scan_join_active)
	assert(lobby._scan_payload_input == null)
	assert(lobby._scan_status_label == null)
	assert(lobby._modal_layer.get_child_count() == 0)
	scanner.scan_succeeded.emit("{\"app\":\"chat_with_me\",\"version\":3,\"format\":\"lan_join_plain\",\"host\":\"192.168.1.2\",\"port\":42871,\"roomId\":\"ui-smoke-room\",\"roomName\":\"UI Smoke\",\"mapId\":\"basic_village\",\"mapName\":\"标准村庄\"}")
	await process_frame
	assert(lobby._modal_layer.get_child_count() > 0)
	assert(lobby._scan_status_label != null)
	assert(String(lobby._scan_status_label.text).strip_edges() != "")
	lobby._clear_modal()
	lobby.queue_free()
	await process_frame

	var model_page := _page("res://scenes/model_config.tscn", state)
	root.add_child(model_page)
	await process_frame
	assert(model_page._tokens_from_context_text("262144") == 262144)
	assert(model_page._context_tokens_from_max_context(262144) == 183501)
	var batch_model_id := "ui-smoke-batch-%d" % Time.get_ticks_usec()
	var batch_before: int = model_page._model_configs.size()
	var batch_base_key: String = model_page._model_schema_test_base_key("Ollama", "http://127.0.0.1:11434/ui-smoke", "", batch_model_id, false)
	model_page._model_detected_formt_adapters[batch_base_key] = "ollama_format_schema"
	model_page._model_detected_reason_adapters[batch_base_key] = "native"
	model_page._model_schema_test_passes[model_page._model_schema_test_key("Ollama", "http://127.0.0.1:11434/ui-smoke", "", batch_model_id, false, "ollama_format_schema")] = true
	model_page._save_batch_model_configs("Ollama", "http://127.0.0.1:11434/ui-smoke", "", "262144", "0.60", false, {batch_model_id: true})
	await process_frame
	assert(model_page._model_configs.size() == batch_before + 1)
	var batch_config: Dictionary = model_page._model_configs[model_page._model_configs.size() - 1]
	assert(String(batch_config.get("model", "")) == batch_model_id)
	assert(not batch_config.has("name"))
	assert(int(batch_config.get("max_context", 0)) == 262144)
	assert(int(batch_config.get("max_output", 0)) == 4096)
	assert(int(batch_config.get("context_window_tokens", 0)) == 183501)
	assert(not bool(batch_config.get("reasoning", false)))
	assert(String(batch_config.get("formt_adapter", "")) == "ollama_format_schema")
	assert(String(batch_config.get("reason_adapter", "")) == "native")
	model_page._delete_model_config(model_page._model_configs.size() - 1)
	await process_frame
	model_page._show_model_config_page(-1)
	await process_frame
	var single_base_key: String = model_page._model_schema_test_base_key("Ollama", "http://127.0.0.1:11434", "", "test:latest", false)
	model_page._model_detected_reason_adapters[single_base_key] = "native"
	model_page._model_schema_test_passes[model_page._model_schema_test_key("Ollama", "http://127.0.0.1:11434", "", "test:latest", false, "ollama_format_schema")] = true
	model_page._save_model_config(-1, "test:latest", "Ollama", "http://127.0.0.1:11434", "测试记忆", "", 183501, 262144, 4096, 0.6, false, "ollama_format_schema", "native")
	await process_frame
	model_page._show_model_config_page(0)
	await process_frame
	model_page._delete_model_config(model_page._model_configs.size() - 1)
	await process_frame
	model_page.queue_free()
	await process_frame

	var voice_page := _page("res://scenes/voice_config.tscn", state)
	root.add_child(voice_page)
	await process_frame
	voice_page._show_voice_config_page(-1)
	await process_frame
	voice_page._save_voice_config(-1, "测试声音", "system", "女声", "manual_voice", "0.90")
	await process_frame
	voice_page._show_voice_config_page(0)
	await process_frame
	voice_page._delete_voice_config(voice_page._voice_configs.size() - 1)
	await process_frame
	voice_page.queue_free()
	await process_frame

	var bot_page := _page("res://scenes/bot_config.tscn", state)
	root.add_child(bot_page)
	await process_frame
	bot_page._show_bot_config_page(-1)
	await process_frame
	bot_page._save_bot_profile(-1, {"name": "测试机器人", "description": "UI smoke", "persona": "谨慎发言", "model": "默认模型", "voice": "系统默认", "enabled": true})
	await process_frame
	assert(bot_page._bot_profiles.size() == 1)
	bot_page._bot_memory_panel(0)
	await process_frame
	bot_page._delete_bot_profile(0)
	await process_frame
	assert(bot_page._bot_profiles.is_empty())
	bot_page.queue_free()
	await process_frame

	state.werewolf["phase"] = "completed"
	state.werewolf["post_game"] = {"stage": "completed", "mvp_index": -1}
	state.history.append({"speaker": "主持人", "text": "好人胜利。", "at": Time.get_unix_time_from_system()})
	var replay_page := _page("res://scenes/replay.tscn", state)
	root.add_child(replay_page)
	await process_frame
	replay_page.queue_free()
	await process_frame

	var room := _page("res://scenes/werewolf_room.tscn", state)
	root.add_child(room)
	await process_frame
	room._model_configs = []
	room._sit_at(0)
	await process_frame
	room._toggle_ready()
	await process_frame
	room._save_name(0, "测试玩家")
	await process_frame
	room._on_seat_name_edit_pressed(0)
	await process_frame
	room._clear_modal()
	for i in range(1, 6):
		room._add_bot_at(i, {"id": "ui_smoke_bot_%d" % i, "name": "机器人%d" % i, "model": "默认模型", "voice": "系统默认", "enabled": true})
		await process_frame
	await process_frame
	room._on_seat_name_edit_pressed(1)
	await process_frame
	room._clear_modal()
	if room._pending_action != "":
		var target := _first_valid_target(room)
		room._on_seat_pressed(target)
		await process_frame
	if room._pending_action != "":
		var target_2 := _first_valid_target(room)
		room._on_seat_pressed(target_2)
		await process_frame
	if room._pending_action != "":
		var target_3 := _first_valid_target(room)
		room._on_seat_pressed(target_3)
		await process_frame
	if room._speech_prompt_index >= 0:
		room._finish_speech("我发言结束")
		await process_frame
	if room._pending_action != "":
		var vote_target := _first_valid_target(room)
		room._on_seat_pressed(vote_target)
		await process_frame
	room._open_empty_seat_actions(5)
	await process_frame
	room._clear_modal()
	room._open_add_bot_dialog(5)
	await process_frame
	room._clear_modal()
	room._open_qr()
	await process_frame
	room._clear_modal()
	room._open_history()
	await process_frame
	room._clear_modal()
	room._open_seat_detail(mini(5, room._players.size() - 1))
	await process_frame
	room._clear_modal()
	room._open_action_panel()
	await process_frame
	room._trigger_speech()
	await process_frame
	room._finish_speech("我发言结束")
	_simulate_death_effect(room)
	room._toggle_phase()
	await process_frame
	room.queue_free()
	await process_frame

	quit()


func _page(path: String, state) -> Control:
	var packed := load(path) as PackedScene
	var page := packed.instantiate() as Control
	page.set_app_state(state)
	return page


func _first_valid_target(room) -> int:
	var actor := int(room._pending_actor_index)
	for i in range(room._players.size()):
		if i == actor:
			continue
		var player: Dictionary = room._players[i]
		if String(player.get("owner", "")) != "" and bool(player.get("alive", true)):
			if String(room._pending_action) == "刀人" and String(player.get("role_key", "")) == "wolf":
				continue
			return i
	return max(0, mini(room._players.size() - 1, actor))


func _simulate_death_effect(room) -> void:
	for i in range(room._players.size()):
		if String(room._players[i].get("owner", "")) != "" and bool(room._players[i].get("alive", true)):
			room._set_seat_motion(i, room.SeatMotion.DEAD, false)
			room._add_history("主持人", "%s 死亡。" % room._player_title(i))
			room._commit_state()
			room._flash_effect("death")
			return
