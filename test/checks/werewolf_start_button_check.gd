extends SceneTree


func _initialize() -> void:
	var state = load("res://scripts/core/app_state.gd").new()
	state.persistence_enabled = false
	state.load_or_create()
	state.create_room("狼人杀", 6, "", "basic_village", "标准村庄")

	var packed := load("res://scenes/werewolf_room.tscn") as PackedScene
	var room := packed.instantiate() as Control
	room.set_app_state(state)
	root.add_child(room)
	await process_frame
	await process_frame

	room._sit_at(0)
	await process_frame
	for i in range(1, 6):
		room._add_bot_at(i, {"id": "start_button_bot_%d" % i, "name": "Bot%d" % i, "model": "默认模型", "voice": "系统默认", "enabled": true})
		await process_frame
	if not _expect(not bool(room._werewolf.get("started", false)), "adding ready bots should not auto start"):
		return

	room._toggle_ready()
	await process_frame
	if not _expect(not bool(room._werewolf.get("started", false)), "ready should not auto start"):
		return
	if not _expect(room._start_button != null, "start button exists"):
		return
	if not _expect(room._start_button.visible, "start button is visible when all real players are ready"):
		return
	if not _expect(room._start_button.global_position.x > room.get_viewport_rect().size.x * 0.5, "start button is on the right side"):
		return
	if not _expect(room._ready_button.global_position.x > room.get_viewport_rect().size.x * 0.5, "ready button is on the right side"):
		return

	room._start_button.pressed.emit()
	await process_frame
	if not _expect(bool(room._werewolf.get("started", false)), "start button starts the game"):
		return
	if not _expect(not room._start_button.visible, "start button hides after game starts"):
		return
	if not _expect(room._pause_button != null, "pause button exists"):
		return
	if not _expect(room._pause_button.visible, "pause button is visible after game starts"):
		return
	if not _expect(String(room._pause_button.text) == "暂停", "pause button initially pauses"):
		return
	room._pause_button.pressed.emit()
	await process_frame
	if not _expect(bool(room._werewolf.get("paused", false)), "pause button pauses game"):
		return
	if not _expect(String(room._werewolf.get("pause_reason", "")) == "房主暂停", "pause reason is host pause"):
		return
	if not _expect(String(room._pause_button.text) == "继续", "paused button resumes"):
		return
	room._pause_button.pressed.emit()
	await process_frame
	if not _expect(not bool(room._werewolf.get("paused", false)), "pause button resumes game"):
		return
	if not _expect(String(room._pause_button.text) == "暂停", "resumed button pauses again"):
		return
	if not _expect(room._history.size() > 0, "started game should write opening timeline"):
		return
	room._history.append({"speaker": "主持人", "text": "上一局旧记录", "at": 99.0})
	room._werewolf["phase"] = "completed"
	room._werewolf["winner"] = "good"
	room._werewolf["memory_long_term_saved"] = true
	var restarted: bool = room._start_local_game_if_ready()
	await process_frame
	if not _expect(restarted, "completed game can restart in same room"):
		return
	if not _expect(not JSON.stringify(room._history).contains("上一局旧记录"), "restart should reset timeline history"):
		return
	if not _expect(not bool(room._werewolf.get("memory_long_term_saved", false)), "restart should use fresh werewolf state"):
		return
	if room._tts_runtime != null and room._tts_runtime.has_method("pending_count"):
		var pending_tts: int = int(room._tts_runtime.call("pending_count"))
		if not _expect(pending_tts <= room._history.size(), "restart should drop previous TTS queue"):
			return

	room.queue_free()
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("werewolf_start_button_check failed: %s" % message)
	quit(1)
	return false
