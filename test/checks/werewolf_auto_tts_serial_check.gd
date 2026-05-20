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

	if not _expect(room._mode == room.Mode.TABLE, "room starts on table"):
		return
	if not _expect(room._tts_runtime != null, "room has tts runtime"):
		return

	room._tts_runtime.stop()
	room._auto_resolve_waiting_for_tts = false
	room._auto_resolve_deferred_pending = false
	var gate_item := {
		"speaker": "主持人",
		"text": "串行推进现在等待展示确认。",
		"at": 1.0,
	}
	room._ensure_history_presentation_id(gate_item)
	room._register_presentation_ack_gate_for_history_item(gate_item)
	if not _expect(room._presentation_ack_gate_blocks_auto_advance(), "presentation ack gate blocks auto advance"):
		return

	room._schedule_auto_resolve_bot_turns()
	if not _expect(room._auto_resolve_waiting_for_tts, "auto resolve waits while presentation ack gate is pending"):
		return
	if not _expect(not room._auto_resolve_deferred_pending, "auto resolve is not deferred before ack gate opens"):
		return

	room._host_apply_presentation_ack(0, {
		"presentationId": room._history_presentation_id(gate_item),
		"participantId": room._current_network_participant_id(),
		"source": "test",
	})
	if not _expect(not room._presentation_ack_gate_blocks_auto_advance(), "presentation ack gate opens"):
		return
	if not _expect(room._auto_resolve_deferred_pending, "auto resolve is deferred after ack gate opens"):
		return
	await process_frame
	if not _expect(not room._auto_resolve_deferred_pending, "deferred auto resolve runs"):
		return

	room._center_speech_items.clear()
	room._center_speech_auto_wait_until_msec = 0
	room._auto_resolve_waiting_for_tts = false
	room._auto_resolve_deferred_pending = false
	room._show_center_speech_item_from_history({
		"speaker": "主持人",
		"text": "关闭语音时中间发言至少停留五秒。",
		"at": 2.0,
	}, false)
	if not _expect(room._center_speech_auto_wait_until_msec >= Time.get_ticks_msec() + 4500, "no-tts center speech creates a five second auto wait"):
		return
	room._schedule_auto_resolve_bot_turns()
	if not _expect(not room._auto_resolve_waiting_for_tts, "center speech hold no longer blocks auto resolve without ack gate"):
		return
	if not _expect(room._auto_resolve_deferred_pending, "auto resolve can be deferred while only center speech hold remains"):
		return
	room._center_speech_auto_wait_until_msec = 0
	room._resume_auto_resolve_after_center_speech_if_ready()
	await process_frame
	if not _expect(not room._auto_resolve_deferred_pending, "deferred auto resolve runs after no-tts center speech hold"):
		return

	room.queue_free()
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("werewolf_auto_tts_serial_check failed: %s" % message)
	quit(1)
	return false
