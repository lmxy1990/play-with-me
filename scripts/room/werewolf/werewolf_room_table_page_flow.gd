extends "res://scripts/room/werewolf/werewolf_room_lifecycle_page_flow.gd"

const CircleAvatarScript := preload("res://scripts/ui/common/circle_avatar.gd")

const CENTER_SPEECH_MAX_ITEMS := 1
const CENTER_SPEECH_FINISHED_HOLD_MSEC := 2200
const CENTER_SPEECH_NO_TTS_HOLD_MSEC := 5000

var _center_panel: PanelContainer
var _center_body: VBoxContainer
var _ready_button: Button
var _start_button: Button
var _observer_bar: PanelContainer
var _center_speech_items: Array = []
var _center_speech_pending_items: Array = []
var _center_speech_deferred_history_items: Array = []
var _center_speech_playback_finished := true
var _center_speech_last_signature := ""
var _center_speech_hold_until_msec := 0
var _center_speech_auto_wait_until_msec := 0


func _layout_table(table: Control) -> void:
	var seats: Array = table.get_meta("seats")
	var center: Control = table.get_meta("center")
	if table.size.x < 400 or table.size.y < 260:
		return

	var center_size := Vector2(clamp(table.size.x * 0.48, 460.0, 720.0), clamp(table.size.y * 0.42, 270.0, 380.0))
	center.size = center_size
	center.position = table.size * 0.5 - center_size * 0.5

	var seat_w: float = clamp(table.size.x * 0.092, 96.0, 120.0)
	var seat_h: float = clamp(table.size.y * 0.165, 108.0, 130.0)
	var radius_x: float = (table.size.x - seat_w) * 0.425
	var radius_y: float = (table.size.y - seat_h) * 0.405
	var c: Vector2 = table.size * 0.5
	var count: int = seats.size()
	for i in range(count):
		var angle: float = -PI * 0.5 + TAU * float(i) / float(count)
		var p: Vector2 = c + Vector2(cos(angle) * radius_x, sin(angle) * radius_y)
		var seat: Control = seats[i]
		seat.size = Vector2(seat_w, seat_h)
		seat.position = p - seat.size * 0.5


func _center_table_panel() -> PanelContainer:
	var panel := _panel(Color(0.98, 0.90, 0.69, 0.78), Color(0.58, 0.36, 0.12, 0.34), 8)
	panel.clip_contents = true
	_center_panel = panel
	var margin := MarginContainer.new()
	_margin_each(margin, 16, 12, 16, 12)
	panel.add_child(margin)
	var body := VBoxContainer.new()
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 7)
	margin.add_child(body)
	_center_body = body
	_refresh_center_panel()
	return panel


func _can_edit_name(index: int) -> bool:
	if index < 0 or index >= _players.size() or not (_players[index] is Dictionary):
		return false
	if _is_local_private_ai_seat(index):
		return false
	if _is_network_client():
		return _participant_controls_index(_current_network_participant_id(), index)
	return _room_runtime.editable_name(_players, index)


func _is_empty_seat(index: int) -> bool:
	return _room_runtime.empty_seat(_players, index)


func _refresh_seat(index: int) -> void:
	if _mode == Mode.TABLE and index >= 0 and index < _seat_cards.size():
		var seat_data := _seat_card_data(index)
		_seat_cards[index].data = seat_data
		_seat_cards[index].start_motion(int(seat_data.get("motion", SeatMotion.IDLE)))


func _refresh_all_seats() -> void:
	for i in range(_players.size()):
		_refresh_seat(i)


func _ready_button_text() -> String:
	if _is_game_started():
		return "已开局"
	if _local_player_index < 0 or _local_player_index >= _players.size():
		return "落座后准备"
	return "取消准备" if bool(_players[_local_player_index].get("ready", false)) else "准备"


func _refresh_room_controls() -> void:
	if _ready_button != null:
		_ready_button.text = _ready_button_text()
		_ready_button.disabled = _is_game_started()
	if _start_button != null:
		_start_button.visible = _should_show_start_button()
		_start_button.disabled = not _should_show_start_button()


func _push_action_prompt(action: String, icon: String, actor_index: int) -> void:
	_pending_action = action
	_pending_action_icon = icon
	_pending_actor_index = actor_index
	_speech_prompt_index = -1
	_system_message = "%s行动" % _player_title(actor_index)
	_show_room_system_message_toast()
	_refresh_center_panel()
	_flash_effect(_action_effect_kind(action))


func _resolve_pending_action(target_index: int, action_name: String = "") -> void:
	var action := _pending_action
	if _is_network_client():
		if not _participant_controls_index(_current_network_participant_id(), _pending_actor_index):
			_system_message = "等待 %s 行动" % _player_title(_pending_actor_index)
			_show_room_system_message_toast()
			_refresh_center_panel()
			_flash_effect("skip")
			return
		var payload := _werewolf_human_task_controller.action_result_payload(target_index, action_name)
		var sent := false
		if _current_device_task_id.strip_edges() != "":
			sent = _send_device_task_result(_current_device_task_id, payload)
			if sent:
				_current_device_task_id = ""
		else:
			_system_message = "等待主机下发行动任务"
			_show_room_system_message_toast()
			_refresh_center_panel()
			_flash_effect("skip")
			return
		_system_message = "已发送行动"
		_show_room_system_message_toast()
		_refresh_center_panel()
		_flash_effect("action" if sent else "skip")
		return
	if _current_device_task_id.strip_edges() != "":
		var payload := _werewolf_human_task_controller.action_result_payload(target_index, action_name)
		var sent := _send_device_task_result(_current_device_task_id, payload)
		if sent:
			_current_device_task_id = ""
		_system_message = "已提交行动" if sent else "行动提交失败"
		_show_room_system_message_toast()
		_refresh_center_panel()
		_flash_effect("action" if sent else "skip")
		return
	_system_message = "等待主机下发行动任务"
	_show_room_system_message_toast()
	_refresh_center_panel()
	_flash_effect("skip")


func _refresh_center_panel() -> void:
	if _center_body == null:
		return
	for child in _center_body.get_children():
		child.queue_free()
	if _center_panel != null:
		_center_panel.visible = true

	if _center_speech_should_take_focus():
		_center_body.alignment = BoxContainer.ALIGNMENT_BEGIN
		_fill_center_speech_display()
	elif not _center_speech_items.is_empty():
		_center_body.alignment = BoxContainer.ALIGNMENT_BEGIN
		_fill_center_speech_display()
	else:
		_center_body.alignment = BoxContainer.ALIGNMENT_CENTER
		_center_body.add_child(_center_idle_view())


func _center_idle_view() -> Control:
	var label := _label("等待玩家发言", 14, MUTED, true, HORIZONTAL_ALIGNMENT_CENTER)
	label.name = "CenterSpeechIdleLabel"
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return label


func _finish_speech(_text: String) -> void:
	if _is_network_client():
		if not _can_local_control_index(_speech_prompt_index):
			_system_message = "等待 %s 发言" % _player_title(_speech_prompt_index)
			_show_room_system_message_toast()
			_refresh_center_panel()
			_flash_effect("skip")
			return
		var payload := _werewolf_human_task_controller.speech_result_payload(_text)
		var sent := false
		if _current_device_task_id.strip_edges() != "":
			sent = _send_device_task_result(_current_device_task_id, payload)
			if sent:
				_current_device_task_id = ""
		else:
			_system_message = "等待主机下发发言任务"
			_show_room_system_message_toast()
			_refresh_center_panel()
			_flash_effect("skip")
			return
		_system_message = "已发送发言"
		_show_room_system_message_toast()
		_refresh_center_panel()
		_flash_effect("speech" if sent else "skip")
		return
	if _current_device_task_id.strip_edges() != "":
		var sent := _send_device_task_result(_current_device_task_id, _werewolf_human_task_controller.speech_result_payload(_text))
		if sent:
			_current_device_task_id = ""
		_system_message = "已提交发言" if sent else "发言提交失败"
		_show_room_system_message_toast()
		_refresh_center_panel()
		_flash_effect("speech" if sent else "skip")
		return
	_system_message = "等待主机下发发言任务"
	_show_room_system_message_toast()
	_refresh_center_panel()
	_flash_effect("skip")


func _show_history_toast_item(item: Dictionary) -> void:
	var speaker := String(item.get("speaker", "")).strip_edges()
	if speaker == "试听":
		return
	if _speaker_index_for_history(speaker) >= 0:
		return
	var text := _center_speech_display_text(item)
	if text == "":
		return
	var message := text if speaker in ["主持人", "房间", "系统"] else "%s：%s" % [speaker, text]
	if has_method("_show_system_progress_toast"):
		call("_show_system_progress_toast", message)


func _show_center_speech_item_from_history(item: Dictionary, wait_for_tts: bool = false) -> void:
	if not _center_speech_history_item_allowed(item):
		return
	if wait_for_tts:
		_show_center_speech_item(item, false, false)
		return
	_show_center_speech_item(item, true, true)


func _show_center_speech_item(item: Dictionary, finished_immediately: bool = false, block_auto_advance: bool = false, force_now: bool = false) -> void:
	var speaker := String(item.get("speaker", "")).strip_edges()
	if not _center_speech_history_item_allowed(item):
		return
	var text := _center_speech_display_text(item)
	if text == "":
		return
	var signature := _center_speech_signature(item)
	var match_key := _center_speech_match_key(item)
	var existing_index := _center_speech_index_for(signature, match_key)
	if existing_index >= 0:
		var existing: Dictionary = _center_speech_items[existing_index]
		var already_finished := not bool(existing.get("active", false)) and float(existing.get("progress", 0.0)) >= 1.0
		if already_finished and not finished_immediately:
			_center_speech_last_signature = signature
			_center_speech_playback_finished = true
			_refresh_center_panel()
			return
		existing["active"] = not finished_immediately
		existing["progress"] = 1.0 if finished_immediately else minf(float(existing.get("progress", 0.0)), 0.99)
		existing["signature"] = signature
		existing["match_key"] = match_key
		existing["presentation_id"] = String(item.get("presentation_id", item.get("presentationId", ""))).strip_edges()
		existing["presentationId"] = String(item.get("presentationId", item.get("presentation_id", ""))).strip_edges()
		existing["reveal_with_progress"] = bool(existing.get("reveal_with_progress", not finished_immediately)) and not finished_immediately
		_center_speech_items[existing_index] = existing
		_center_speech_last_signature = signature
		_center_speech_playback_finished = finished_immediately
		_start_center_speech_hold_timer(finished_immediately, block_auto_advance, String(existing.get("text", "")))
		_refresh_center_panel()
		return
	if signature == _center_speech_last_signature:
		_center_speech_playback_finished = finished_immediately
		_start_center_speech_hold_timer(finished_immediately, block_auto_advance, text)
		return
	if _center_speech_should_queue_item(signature, match_key, force_now):
		_enqueue_center_speech_item(item, finished_immediately, block_auto_advance, signature, match_key)
		return
	var entry := {
		"speaker": speaker,
		"speaker_index": _history_item_speaker_index(item) if has_method("_history_item_speaker_index") else _speaker_index_for_history(speaker),
		"avatar": _history_item_avatar_path(item) if has_method("_history_item_avatar_path") else "",
		"seat": _history_item_seat_text(item) if has_method("_history_item_seat_text") else "",
		"name": _history_item_display_name(item) if has_method("_history_item_display_name") else speaker,
		"text": text,
		"active": not finished_immediately,
		"progress": 1.0 if finished_immediately else 0.0,
		"reveal_with_progress": not finished_immediately,
		"signature": signature,
		"match_key": match_key,
		"presentation_id": String(item.get("presentation_id", item.get("presentationId", ""))).strip_edges(),
		"presentationId": String(item.get("presentationId", item.get("presentation_id", ""))).strip_edges(),
	}
	for i in range(_center_speech_items.size()):
		if _center_speech_items[i] is Dictionary:
			(_center_speech_items[i] as Dictionary)["active"] = false
	_center_speech_items.clear()
	while _center_speech_items.size() >= CENTER_SPEECH_MAX_ITEMS:
		_center_speech_items.pop_front()
	_center_speech_items.append(entry)
	_center_speech_last_signature = signature
	_center_speech_playback_finished = finished_immediately
	_start_center_speech_hold_timer(finished_immediately, block_auto_advance, text)
	_refresh_center_panel()


func _center_speech_should_queue_item(signature: String, match_key: String, force_now: bool) -> bool:
	if force_now:
		return false
	if _center_speech_items.is_empty() or not (_center_speech_items.back() is Dictionary):
		return false
	var current: Dictionary = _center_speech_items.back()
	var same_current := String(current.get("signature", "")) == signature or String(current.get("match_key", "")) == match_key
	if same_current:
		return false
	return _center_speech_should_take_focus() or _center_speech_blocks_auto_advance()


func _enqueue_center_speech_item(item: Dictionary, finished_immediately: bool, block_auto_advance: bool, signature: String, match_key: String) -> void:
	for i in range(_center_speech_pending_items.size()):
		if not (_center_speech_pending_items[i] is Dictionary):
			continue
		var pending: Dictionary = _center_speech_pending_items[i]
		if String(pending.get("signature", "")) == signature or String(pending.get("match_key", "")) == match_key:
			pending["item"] = item.duplicate(true)
			pending["finished_immediately"] = finished_immediately
			pending["block_auto_advance"] = block_auto_advance
			_center_speech_pending_items[i] = pending
			return
	_center_speech_pending_items.append({
		"item": item.duplicate(true),
		"finished_immediately": finished_immediately,
		"block_auto_advance": block_auto_advance,
		"signature": signature,
		"match_key": match_key,
	})


func _show_next_queued_center_speech_item() -> bool:
	if _center_speech_current_presentation_gate_pending():
		return false
	while not _center_speech_pending_items.is_empty():
		var pending = _center_speech_pending_items.pop_front()
		if not (pending is Dictionary):
			continue
		var pending_item = (pending as Dictionary).get("item", {})
		if not (pending_item is Dictionary):
			continue
		_show_center_speech_item(
			pending_item as Dictionary,
			bool((pending as Dictionary).get("finished_immediately", false)),
			bool((pending as Dictionary).get("block_auto_advance", false)),
			true
		)
		return true
	return false


func _defer_history_item_for_center_speech(item: Dictionary) -> bool:
	if not _center_speech_history_item_allowed(item):
		return false
	if not _center_speech_should_defer_history_item(item):
		return false
	var signature := _center_speech_signature(item)
	var match_key := _center_speech_match_key(item)
	for i in range(_center_speech_deferred_history_items.size()):
		if not (_center_speech_deferred_history_items[i] is Dictionary):
			continue
		var pending: Dictionary = _center_speech_deferred_history_items[i]
		if String(pending.get("signature", "")) == signature or String(pending.get("match_key", "")) == match_key:
			pending["item"] = item.duplicate(true)
			_center_speech_deferred_history_items[i] = pending
			return true
	_center_speech_deferred_history_items.append({
		"item": item.duplicate(true),
		"signature": signature,
		"match_key": match_key,
	})
	return true


func _center_speech_should_defer_history_item(item: Dictionary) -> bool:
	var signature := _center_speech_signature(item)
	var match_key := _center_speech_match_key(item)
	if _center_speech_index_for(signature, match_key) >= 0:
		return false
	if bool(item.get("__center_speech_deferred_resume", false)):
		return false
	if _center_speech_should_take_focus() or _center_speech_blocks_auto_advance():
		return true
	if _center_speech_waiting_without_tts():
		return true
	if _center_speech_current_presentation_gate_pending():
		return true
	return false


func _center_speech_current_presentation_gate_pending() -> bool:
	for item in _center_speech_items:
		if not (item is Dictionary):
			continue
		var presentation_id := String((item as Dictionary).get("presentation_id", (item as Dictionary).get("presentationId", ""))).strip_edges()
		if presentation_id == "":
			continue
		if _presentation_ack_has_pending_id(presentation_id):
			return true
	return false


func _center_speech_waiting_without_tts() -> bool:
	if _center_speech_auto_wait_until_msec <= Time.get_ticks_msec():
		return false
	if _tts_runtime != null and _tts_runtime.has_method("is_speaking") and bool(_tts_runtime.call("is_speaking")):
		return false
	return true


func _present_next_deferred_center_history_item() -> bool:
	while not _center_speech_deferred_history_items.is_empty():
		var pending = _center_speech_deferred_history_items.pop_front()
		if not (pending is Dictionary):
			continue
		var item = (pending as Dictionary).get("item", {})
		if not (item is Dictionary):
			continue
		(item as Dictionary)["__center_speech_deferred_resume"] = true
		if has_method("_present_history_item"):
			call("_present_history_item", item as Dictionary)
			return true
	return false


func _center_speech_history_item_allowed(item: Dictionary) -> bool:
	var speaker := String(item.get("speaker", "")).strip_edges()
	if speaker == "" or speaker == "试听":
		return false
	if _speaker_index_for_history(speaker) >= 0:
		return true
	return speaker in ["主持人", "房间", "系统"]


func _finish_center_speech_item(item: Dictionary) -> void:
	var signature := _center_speech_signature(item)
	var match_key := _center_speech_match_key(item)
	for i in range(_center_speech_items.size() - 1, -1, -1):
		if not (_center_speech_items[i] is Dictionary):
			continue
		var entry: Dictionary = _center_speech_items[i]
		if String(entry.get("signature", "")) == signature or String(entry.get("match_key", "")) == match_key:
			entry["active"] = false
			entry["progress"] = 1.0
			entry["reveal_with_progress"] = false
			_center_speech_items[i] = entry
			break
	_center_speech_playback_finished = true
	_start_center_speech_hold_timer(true, false, String(item.get("text", "")))
	_refresh_center_panel()


func _update_center_speech_progress(item: Dictionary, ratio: float) -> void:
	var signature := _center_speech_signature(item)
	var match_key := _center_speech_match_key(item)
	for i in range(_center_speech_items.size() - 1, -1, -1):
		if not (_center_speech_items[i] is Dictionary):
			continue
		var entry: Dictionary = _center_speech_items[i]
		if String(entry.get("signature", "")) == signature or String(entry.get("match_key", "")) == match_key:
			entry["progress"] = maxf(float(entry.get("progress", 0.0)), clampf(ratio, 0.0, 1.0))
			entry["active"] = float(entry.get("progress", 0.0)) < 1.0
			_center_speech_items[i] = entry
			_center_speech_playback_finished = false if bool(entry.get("active", false)) else true
			_refresh_center_panel()
			return


func _fail_center_speech_item(item: Dictionary, _error: String = "") -> void:
	_show_center_speech_item(item, true, true)
	_finish_center_speech_item(item)


func _fill_center_speech_display() -> void:
	if _center_speech_items.is_empty() or not (_center_speech_items.back() is Dictionary):
		return
	_center_body.add_child(_center_speech_entry_view(_center_speech_items.back() as Dictionary))


func _center_speech_entry_view(entry: Dictionary) -> Control:
	var root := VBoxContainer.new()
	root.name = "CenterSpeechEntry"
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 8)
	var header := HBoxContainer.new()
	header.name = "CenterSpeechHeader"
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", 8)
	header.add_child(_center_speech_avatar(entry))
	var active := bool(entry.get("active", false))
	var seat := String(entry.get("seat", "")).strip_edges()
	var name := String(entry.get("name", entry.get("speaker", ""))).strip_edges()
	var title := "%s %s" % [seat, name] if seat != "" else name
	var speaker_label := _nowrap_label(title, 13, TEAL if active else GOLD, true)
	speaker_label.name = "CenterSpeechSpeakerLabel"
	speaker_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	speaker_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(speaker_label)
	root.add_child(header)
	root.add_child(_center_speech_text_view(entry))
	return root


func _center_speech_text_view(entry: Dictionary) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = "CenterSpeechTextScroll"
	scroll.custom_minimum_size = Vector2(0, 0)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	scroll.clip_contents = true
	var progress := float(entry.get("progress", 1.0))
	var text := _center_speech_visible_text(entry)
	var content := _label(text, 13, INK, false)
	content.name = "CenterSpeechTextLabel"
	content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	content.clip_text = false
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	call_deferred("_scroll_center_speech_text_to_progress", scroll, progress)
	return scroll


func _center_speech_visible_text(entry: Dictionary) -> String:
	var text := String(entry.get("text", "")).strip_edges()
	if text == "":
		return ""
	if not bool(entry.get("reveal_with_progress", false)):
		return text
	var progress := clampf(float(entry.get("progress", 0.0)), 0.0, 1.0)
	if progress >= 1.0:
		return text
	var total_chars := text.length()
	if total_chars <= 0:
		return ""
	var visible_chars := int(ceil(float(total_chars) * progress))
	if visible_chars <= 0:
		return ""
	return text.substr(0, mini(total_chars, visible_chars))


func _scroll_center_speech_text_to_progress(scroll, progress: float) -> void:
	if scroll == null or not is_instance_valid(scroll) or not (scroll is ScrollContainer):
		return
	var scroll_container: ScrollContainer = scroll
	var bar := scroll_container.get_v_scroll_bar()
	if bar == null:
		return
	var max_value := maxf(0.0, bar.max_value - bar.page)
	bar.value = clampf(max_value * clampf(progress, 0.0, 1.0), 0.0, max_value)


func _center_speech_avatar(entry: Dictionary) -> Control:
	var avatar := CircleAvatarScript.new()
	avatar.texture = _texture(String(entry.get("avatar", "")))
	avatar.custom_minimum_size = Vector2(34, 34)
	avatar.ring_color = Color(0.96, 0.70, 0.32, 0.82)
	avatar.shadow_color = Color(0, 0, 0, 0.18)
	avatar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return avatar


func _center_speech_signature(item: Dictionary) -> String:
	return "%s|%s|%s" % [
		String(item.get("speaker", "")),
		_center_speech_display_text(item),
		str(item.get("at", "")),
	]


func _center_speech_match_key(item: Dictionary) -> String:
	return "%s|%s" % [
		String(item.get("speaker", "")),
		_center_speech_display_text(item),
	]


func _center_speech_display_text(item: Dictionary) -> String:
	var display_text := String(item.get("display_text", "")).strip_edges()
	if display_text != "":
		return display_text
	return String(item.get("text", "")).strip_edges()


func _center_speech_index_for(signature: String, match_key: String) -> int:
	for i in range(_center_speech_items.size() - 1, -1, -1):
		if not (_center_speech_items[i] is Dictionary):
			continue
		var entry: Dictionary = _center_speech_items[i]
		if String(entry.get("signature", "")) == signature or String(entry.get("match_key", "")) == match_key:
			return i
	return -1


func _center_speech_should_take_focus() -> bool:
	for item in _center_speech_items:
		if item is Dictionary and bool((item as Dictionary).get("active", false)):
			return true
	return not _center_speech_items.is_empty() and Time.get_ticks_msec() < _center_speech_hold_until_msec


func _center_speech_blocks_auto_advance() -> bool:
	if _center_speech_auto_wait_until_msec > Time.get_ticks_msec():
		return true
	for item in _center_speech_items:
		if item is Dictionary and bool((item as Dictionary).get("active", false)):
			return true
	return false


func _start_center_speech_hold_timer(enabled: bool, block_auto_advance: bool = false, text: String = "") -> void:
	if not enabled:
		_center_speech_hold_until_msec = 0
		return
	var hold_msec := CENTER_SPEECH_NO_TTS_HOLD_MSEC if block_auto_advance else CENTER_SPEECH_FINISHED_HOLD_MSEC
	if block_auto_advance and has_method("_presentation_text_delay_seconds_for_text"):
		hold_msec = int(ceil(float(call("_presentation_text_delay_seconds_for_text", text)) * 1000.0))
	_center_speech_hold_until_msec = Time.get_ticks_msec() + hold_msec
	var hold_token := _center_speech_hold_until_msec
	if block_auto_advance:
		_center_speech_auto_wait_until_msec = hold_token
	get_tree().create_timer(float(hold_msec) / 1000.0 + 0.05).timeout.connect(func():
		var should_resume_auto := false
		if _center_speech_hold_until_msec == hold_token:
			_center_speech_hold_until_msec = 0
		if _center_speech_auto_wait_until_msec == hold_token:
			_center_speech_auto_wait_until_msec = 0
			should_resume_auto = true
		if _center_speech_current_presentation_gate_pending():
			_refresh_center_panel()
			return
		if _present_next_deferred_center_history_item():
			return
		if _show_next_queued_center_speech_item():
			return
		_refresh_center_panel()
		if should_resume_auto and has_method("_resume_auto_resolve_after_center_speech_if_ready"):
			call("_resume_auto_resolve_after_center_speech_if_ready")
	)


func _center_speech_capacity_chars() -> int:
	var panel_size := Vector2(520, 240)
	if _center_panel != null:
		panel_size = _center_panel.size
	var chars_per_line := maxi(16, int(maxf(260.0, panel_size.x - 44.0) / 14.0))
	var lines := maxi(4, int(maxf(150.0, panel_size.y - 34.0) / 25.0))
	return chars_per_line * lines


func _show_room_system_message_toast() -> void:
	var message := _system_message.strip_edges()
	if message == "" or message in ["等待系统推送", "等待主持人", "等待下一条公开消息"]:
		return
	if has_method("_show_system_progress_toast"):
		call("_show_system_progress_toast", message)


func _clear_center_speech_display() -> void:
	_center_panel = null
	_center_speech_items.clear()
	_center_speech_pending_items.clear()
	_center_speech_deferred_history_items.clear()
	_center_speech_playback_finished = true
	_center_speech_last_signature = ""
	_center_speech_hold_until_msec = 0
	_center_speech_auto_wait_until_msec = 0
