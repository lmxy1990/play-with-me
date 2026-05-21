extends SceneTree


func _initialize() -> void:
	var state = load("res://scripts/core/app_state.gd").new()
	state.persistence_enabled = false
	state.load_or_create()
	state.create_room("狼人杀", 6, "", "basic_village", "标准村庄")
	if not _expect(state.history.is_empty(), "room creation stays out of history"):
		return

	var packed := load("res://scenes/werewolf_room.tscn") as PackedScene
	var room := packed.instantiate() as Control
	room.set_app_state(state)
	root.add_child(room)
	await process_frame
	await process_frame
	if not _expect(room._history.is_empty(), "fresh room has no lifecycle history"):
		return
	room._sit_at(0)
	await process_frame
	if not _expect(room._history.is_empty(), "sitting down stays out of history"):
		return
	room._add_bot_at(1)
	await process_frame
	if not _expect(room._history.is_empty(), "adding bot stays out of history"):
		return
	room._remove_bot_at(1)
	await process_frame
	if not _expect(room._history.is_empty(), "removing bot stays out of history"):
		return
	room._toggle_ready()
	await process_frame
	if not _expect(room._history.is_empty(), "ready state stays out of history"):
		return
	room._switch_local_to_observer()
	await process_frame
	if not _expect(room._history.is_empty(), "observer switch stays out of history"):
		return
	var lifecycle_room: Dictionary = room._active_room()
	lifecycle_room["observers"] = []

	room._players = [
		{"id": "self", "name": "我", "owner": "self", "participant_id": "", "role_key": "villager", "avatar": room._werewolf_avatar_path("villager"), "alive": true},
		{"id": "wolf", "name": "狼", "owner": "human", "participant_id": "peer_wolf", "role_key": "wolf", "avatar": room._werewolf_avatar_path("wolf"), "alive": true},
		{"id": "seer", "name": "预言家", "owner": "human", "participant_id": "peer_seer", "role_key": "seer", "avatar": room._werewolf_avatar_path("seer"), "alive": true},
	]
	room._local_player_index = 0
	room._history = [
		{"speaker": "主持人", "text": "第1夜开始。", "visibility": "public"},
		{"speaker": "2号 狼", "text": "选择袭击1号 我。", "speaker_index": 1, "actor_index": 1, "visibility": "wolf", "action_key": "wolf_kill"},
		{"speaker": "3号 预言家", "text": "查验2号 狼：狼人阵营。", "speaker_index": 2, "actor_index": 2, "visibility": "private", "visible_to_indices": [2]},
		{"speaker": "1号 我", "text": "我自己的私有行动。", "speaker_index": 0, "actor_index": 0, "visibility": "private", "visible_to_indices": [0]},
	]

	var visible: Array = room._visible_history_for_current_participant()
	if not _expect(visible.size() == 2, "local villager only sees public and own private history"):
		return
	if not _expect(String((visible[1] as Dictionary).get("text", "")) == "我自己的私有行动。", "own private history remains visible"):
		return

	var active: Dictionary = room._active_room()
	active["observers"] = [{"id": "host", "displayName": "观战"}]
	var observer_visible: Array = room._visible_history_for_current_participant()
	if not _expect(observer_visible.size() == 4, "observer sees complete history"):
		return
	active["observers"] = []

	room._set_player_tts_enabled(0, false)
	var muted_item := {"speaker": "1号 我", "speaker_index": 0, "text": "静音后仍然显示文本。", "at": 8.0}
	if not _expect(room._queue_tts_for_history(muted_item).is_empty(), "muted speaker is not queued to tts"):
		return
	room._show_center_speech_item_from_history(muted_item)
	await process_frame
	if not _expect(room._center_speech_items.size() == 1, "muted speech still appears in center panel"):
		return

	room._set_player_tts_enabled(0, true)
	room._refresh_all_seats()
	await process_frame
	if not _expect(room._seat_cards.size() > 0, "table has seat cards"):
		return
	var seat_card := room._seat_cards[0] as Control
	var voice_toggle := seat_card.find_child("SeatCardVoiceToggleButton", true, false)
	if not _expect(voice_toggle != null, "seat avatar has voice toggle"):
		return
	voice_toggle.emit_signal("pressed")
	await process_frame
	if not _expect(not room._player_tts_enabled(0), "seat avatar voice toggle mutes tts"):
		return
	room._set_player_tts_enabled(0, true)
	room._refresh_seat(0)

	room._center_speech_items.clear()
	room._center_speech_pending_items.clear()
	room._center_speech_hold_until_msec = 0
	room._center_speech_auto_wait_until_msec = 0
	var progress_item := {"speaker": "1号 我", "speaker_index": 0, "text": "同步播放进度。", "at": 9.0}
	room._show_center_speech_item(progress_item, false, false, true)
	room._update_center_speech_progress(progress_item, 0.5)
	if not _expect(absf(float((room._center_speech_items.back() as Dictionary).get("progress", 0.0)) - 0.5) < 0.01, "center speech progress is updated"):
		return
	room._update_center_speech_progress(progress_item, 0.2)
	if not _expect(absf(float((room._center_speech_items.back() as Dictionary).get("progress", 0.0)) - 0.5) < 0.01, "center speech progress never moves backward"):
		return
	await process_frame
	var progress_label := room.find_child("CenterSpeechTextLabel", true, false) as Label
	if not _expect(progress_label != null, "center speech progress renders text label"):
		return
	var progress_text := String(progress_label.text)
	if not _expect(String((room._center_speech_items.back() as Dictionary).get("text", "")) == String(progress_item.get("text", "")), "center speech keeps full original text in state while progress updates"):
		return
	if not _expect(String(progress_item.get("text", "")).find(progress_text) == 0 and progress_text.length() > 0 and progress_text.length() < String(progress_item.get("text", "")).length(), "center speech label reveals text by playback progress"):
		return

	room._center_speech_items.clear()
	room._center_speech_pending_items.clear()
	room._center_speech_deferred_history_items.clear()
	var display_item := {"speaker": "2号 mimo-v2.5", "speaker_index": 1, "text": "投票给 3号 kimi-k2.6。", "at": 9.5}
	var tts_item: Dictionary = room._player_speech_output.build_item(display_item, {"enabled": true, "engine": "system"}, room._players.size())
	room._show_center_speech_item_from_history(display_item, true)
	if not _expect(room._center_speech_items.size() == 1, "tts queued history appears in center panel before playback starts"):
		return
	if not _expect(String((room._center_speech_items[0] as Dictionary).get("text", "")) == "投票给 3号 kimi-k2.6。", "tts queued history shows original text before playback starts"):
		return
	if not _expect(bool((room._center_speech_items[0] as Dictionary).get("active", false)), "tts queued history stays active while waiting for playback"):
		return
	room._on_tts_speech_started(tts_item)
	room._on_tts_speech_progress(tts_item, 0.5)
	if not _expect(room._center_speech_items.size() == 1, "sanitized tts item updates existing center speech instead of duplicating it"):
		return
	if not _expect(String((room._center_speech_items[0] as Dictionary).get("text", "")) == "投票给 3号 kimi-k2.6。", "center speech displays original history text"):
		return
	if not _expect(absf(float((room._center_speech_items[0] as Dictionary).get("progress", 0.0)) - 0.5) < 0.01, "sanitized tts item keeps progress on original display entry"):
		return
	await process_frame
	var tts_progress_label := room.find_child("CenterSpeechTextLabel", true, false) as Label
	var tts_visible_text := String(tts_progress_label.text) if tts_progress_label != null else ""
	if not _expect(tts_progress_label != null and String(display_item.get("text", "")).find(tts_visible_text) == 0 and tts_visible_text.length() > 0 and tts_visible_text.length() < String(display_item.get("text", "")).length(), "tts center label reveals original display text by playback progress"):
		return

	room._center_speech_items.clear()
	room._center_speech_pending_items.clear()
	room._center_speech_deferred_history_items.clear()
	room._center_speech_hold_until_msec = 0
	room._center_speech_auto_wait_until_msec = 0
	var queued_tts_speech := {"speaker": "1号 我", "speaker_index": 0, "text": "玩家语音生成时也要先展示，不被主持人提示马上覆盖。", "at": 9.55}
	var queued_tts_prompt := {"speaker": "主持人", "text": "请 2号 狼 发言。", "at": 9.56}
	room._show_center_speech_item_from_history(queued_tts_speech, true)
	room._show_center_speech_item_from_history(queued_tts_prompt, true)
	if not _expect(String((room._center_speech_items.back() as Dictionary).get("text", "")) == "玩家语音生成时也要先展示，不被主持人提示马上覆盖。", "tts player speech stays in center while playback is pending"):
		return
	await process_frame
	var queued_tts_label := room.find_child("CenterSpeechTextLabel", true, false) as Label
	if not _expect(queued_tts_label != null and String(queued_tts_label.text) == "", "tts player speech text is not dumped before playback progress"):
		return
	if not _expect(room._center_speech_pending_items.size() == 1, "following tts prompt waits in the center speech queue"):
		return

	room._center_speech_items.clear()
	room._center_speech_pending_items.clear()
	room._center_speech_deferred_history_items.clear()
	var queued_speech := {"speaker": "1号 我", "speaker_index": 0, "text": "玩家发言应该先展示，不被主持人提示马上覆盖。", "at": 9.6}
	var queued_prompt := {"speaker": "主持人", "text": "请 2号 狼 发言。", "at": 9.7}
	room._show_center_speech_item_from_history(queued_speech, false)
	room._show_center_speech_item_from_history(queued_prompt, false)
	if not _expect(String((room._center_speech_items.back() as Dictionary).get("text", "")) == "玩家发言应该先展示，不被主持人提示马上覆盖。", "no-tts player speech stays in center while its hold is active"):
		return
	if not _expect(room._center_speech_pending_items.size() == 1, "next no-tts prompt waits in the center speech queue"):
		return
	room._center_speech_hold_until_msec = 0
	room._center_speech_auto_wait_until_msec = 0
	if not _expect(room._show_next_queued_center_speech_item(), "queued no-tts prompt can be presented after the current hold"):
		return
	if not _expect(String((room._center_speech_items.back() as Dictionary).get("text", "")) == "请 2号 狼 发言。", "queued prompt appears after previous center speech"):
		return

	room._center_speech_items.clear()
	room._center_speech_pending_items.clear()
	room._center_speech_deferred_history_items.clear()
	room._center_speech_hold_until_msec = 0
	room._center_speech_auto_wait_until_msec = 0
	if room._tts_runtime != null:
		room._tts_runtime.stop()
	room._set_player_tts_enabled(0, false)
	var muted_batch_speech := {"speaker": "1号 我", "speaker_index": 0, "text": "我被静音时也要完整展示五秒。", "at": 9.8}
	var tts_prompt_after_muted := {"speaker": "主持人", "text": "请 2号 狼 发言。", "at": 9.9}
	room._present_history_item(muted_batch_speech)
	room._present_history_item(tts_prompt_after_muted)
	if not _expect(String((room._center_speech_items.back() as Dictionary).get("text", "")) == "我被静音时也要完整展示五秒。", "muted player speech is not preempted by following tts prompt"):
		return
	if not _expect(room._center_speech_deferred_history_items.size() == 1, "following tts prompt waits behind muted player speech"):
		return
	if room._tts_runtime != null:
		if not _expect(int(room._tts_runtime.pending_count()) == 0, "deferred tts prompt is not queued before muted speech hold expires"):
			return
	room._center_speech_auto_wait_until_msec = 0
	if not _expect(room._present_next_deferred_center_history_item(), "deferred tts prompt presents after muted speech hold"):
		return
	if not _expect(String((room._center_speech_items.back() as Dictionary).get("text", "")) == "请 2号 狼 发言。", "deferred tts prompt becomes current center item"):
		return
	room._set_player_tts_enabled(0, true)
	if room._tts_runtime != null:
		room._tts_runtime.stop()

	room._center_speech_items.clear()
	room._center_speech_pending_items.clear()
	room._center_speech_deferred_history_items.clear()
	room._center_speech_hold_until_msec = 0
	room._center_speech_auto_wait_until_msec = 0
	room._set_player_tts_enabled(0, true)
	if room._tts_runtime != null:
		room._tts_runtime.stop()
	var live_tts_speech := {"speaker": "1号 我", "speaker_index": 0, "text": "正在播放的玩家发言必须独占展示。", "at": 9.95}
	var live_tts_prompt := {"speaker": "主持人", "text": "下一条主持人提示不能提前进入语音队列。", "at": 9.96}
	room._present_history_item(live_tts_speech)
	room._present_history_item(live_tts_prompt)
	if not _expect(room._center_speech_deferred_history_items.size() == 1, "following history waits while current tts center speech is active"):
		return
	if room._tts_runtime != null:
		if not _expect(int(room._tts_runtime.pending_count()) == 1, "deferred history is not queued to tts before current speech finishes"):
			return
		room._tts_runtime.stop()

	var live_item := {"speaker": "1号 我", "speaker_index": 0, "text": "这条发言要进入历史并立即显示。", "at": 10.0}
	room._center_speech_items.clear()
	room._center_speech_pending_items.clear()
	room._center_speech_deferred_history_items.clear()
	room._center_speech_hold_until_msec = 0
	room._center_speech_auto_wait_until_msec = 0
	room._append_history_item(live_item)
	await process_frame
	if not _expect(String((room._history.back() as Dictionary).get("text", "")) == "这条发言要进入历史并立即显示。", "submitted speech enters history"):
		return
	if not _expect(String((room._center_speech_items.back() as Dictionary).get("text", "")) == "这条发言要进入历史并立即显示。", "submitted speech appears in center panel immediately"):
		return
	var live_label := room.find_child("CenterSpeechTextLabel", true, false) as Label
	if not _expect(live_label != null and String(live_label.text) != "这条发言要进入历史并立即显示。", "submitted tts speech does not dump full text before playback progress"):
		return
	room._update_center_speech_progress(live_item, 0.6)
	await process_frame
	live_label = room.find_child("CenterSpeechTextLabel", true, false) as Label
	var live_visible_text := String(live_label.text) if live_label != null else ""
	if not _expect(live_label != null and String(live_item.get("text", "")).find(live_visible_text) == 0 and live_visible_text.length() > 0 and live_visible_text.length() < String(live_item.get("text", "")).length(), "submitted tts speech reveals text by playback progress"):
		return

	room._open_history()
	await process_frame
	if not _expect(room._modal_layer.find_child("HistoryChatRow", true, false) != null, "history uses chat rows"):
		return
	if not _expect(room._modal_layer.find_child("HistoryAvatar", true, false) != null, "history shows avatars"):
		return
	if not _expect(room._modal_layer.find_child("HistoryChatBubble", true, false) != null, "history shows chat bubbles"):
		return
	var backdrop := room._modal_layer.find_child("ModalOutsideCloseArea", false, false) as Control
	if not _expect(backdrop != null, "history overlay has outside-close backdrop"):
		return
	_click_control(backdrop)
	await process_frame
	if not _expect(room._modal_layer.get_child_count() == 0, "clicking outside overlay closes modal"):
		return

	room.queue_free()
	quit(0)


func _click_control(control: Control) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = Vector2(1, 1)
	control.emit_signal("gui_input", event)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("werewolf_history_visibility_tts_check failed: %s" % message)
	quit(1)
	return false
