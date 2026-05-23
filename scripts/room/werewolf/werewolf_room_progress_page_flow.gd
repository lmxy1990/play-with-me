extends "res://scripts/pages/base/page_navigation_ui_base.gd"

const OBSERVER_SLOT_LIMIT := 3

var _system_progress_toast: PanelContainer
var _system_progress_toast_tween: Tween
var _last_system_progress_toast := ""
var _last_system_progress_toast_msec := 0
var _room_summary_status_label: Label
var _room_interaction_status_label: Label


func _clear_scene() -> void:
	super._clear_scene()
	_room_summary_status_label = null
	_room_interaction_status_label = null


func _build_table_hud() -> void:
	var top_left := VBoxContainer.new()
	top_left.position = Vector2(16, 14)
	top_left.custom_minimum_size = Vector2(342, 0)
	top_left.add_theme_constant_override("separation", 6)
	_hud_layer.add_child(top_left)
	var summary_status := _compact_status(_room_summary_status_text(), TEAL)
	_room_summary_status_label = _status_label(summary_status, "RoomSummaryStatusLabel")
	top_left.add_child(summary_status)
	var interaction_status := _compact_status(_interaction_status_text(), INK)
	_room_interaction_status_label = _status_label(interaction_status, "RoomInteractionStatusLabel")
	top_left.add_child(interaction_status)

	_observer_bar = _observer_slots_bar()
	_observer_bar.anchor_left = 1.0
	_observer_bar.anchor_right = 1.0
	_observer_bar.anchor_top = 0.5
	_observer_bar.anchor_bottom = 0.5
	_observer_bar.offset_left = -108
	_observer_bar.offset_right = -14
	_observer_bar.offset_top = -79
	_observer_bar.offset_bottom = 79
	_hud_layer.add_child(_observer_bar)
	_refresh_observer_slots()

	var top_right := HBoxContainer.new()
	top_right.anchor_left = 1.0
	top_right.anchor_right = 1.0
	top_right.offset_left = -314 if _is_post_game_phase() else -256
	top_right.offset_right = -16
	top_right.offset_top = 14
	top_right.offset_bottom = 52
	top_right.add_theme_constant_override("separation", 6)
	_hud_layer.add_child(top_right)
	top_right.add_child(_mini_icon_button("QR", func(): call("_open_qr")))
	top_right.add_child(_mini_icon_button("规则", func(): call("_open_room_rules")))
	top_right.add_child(_mini_icon_button("历史", func(): call("_open_history")))
	if _is_post_game_phase():
		top_right.add_child(_mini_icon_button("复盘", func(): call("_open_replay")))
	top_right.add_child(_mini_icon_button("退出", func(): _leave_room_to_lobby()))

	var player_bar := HBoxContainer.new()
	player_bar.anchor_left = 1.0
	player_bar.anchor_right = 1.0
	player_bar.anchor_top = 1.0
	player_bar.anchor_bottom = 1.0
	player_bar.offset_left = -282
	player_bar.offset_right = -16
	player_bar.offset_top = -52
	player_bar.offset_bottom = -14
	player_bar.alignment = BoxContainer.ALIGNMENT_END
	player_bar.add_theme_constant_override("separation", 6)
	_hud_layer.add_child(player_bar)
	_pause_button = _small_button(_pause_button_text(), false, func(): call("_toggle_werewolf_pause_from_button"))
	_pause_button.name = "PauseGameButton"
	_pause_button.visible = _should_show_pause_button()
	player_bar.add_child(_pause_button)
	_ready_button = _small_button(_ready_button_text(), true, func(): call("_toggle_ready"))
	player_bar.add_child(_ready_button)
	_start_button = _small_button("开始", true, func(): call("_start_game_from_button"))
	_start_button.name = "StartGameButton"
	_start_button.visible = _should_show_start_button()
	player_bar.add_child(_start_button)


func _refresh_room_controls() -> void:
	super._refresh_room_controls()
	_refresh_top_left_status()
	_refresh_observer_slots()


func _refresh_center_panel() -> void:
	super._refresh_center_panel()
	_refresh_top_left_status()


func _room_summary_status_text() -> String:
	var room: Dictionary = _active_room()
	var seat_capacity := _players.size()
	if not room.is_empty():
		seat_capacity = int(room.get("max_players", seat_capacity))
	seat_capacity = maxi(1, seat_capacity)
	var observer_total := _room_observers().size()
	var total_capacity := _room_capacity(room) if not room.is_empty() else seat_capacity + OBSERVER_SLOT_LIMIT
	total_capacity = maxi(total_capacity, seat_capacity + observer_total)
	return "容量 %d/%d · 席位 %d/%d · 真人 %d / AI %d · 观战 %d/%d" % [
		_occupied_indices().size() + observer_total,
		total_capacity,
		_occupied_indices().size(),
		seat_capacity,
		_human_count(),
		_bot_count(),
		observer_total,
		OBSERVER_SLOT_LIMIT,
	]


func _refresh_top_left_status() -> void:
	if _room_summary_status_label != null and is_instance_valid(_room_summary_status_label):
		_room_summary_status_label.text = _room_summary_status_text()
	if _room_interaction_status_label != null and is_instance_valid(_room_interaction_status_label):
		_room_interaction_status_label.text = _interaction_status_text()


func _status_label(root_node: Node, label_name: String) -> Label:
	for child in root_node.get_children():
		if child is Label:
			var label := child as Label
			label.name = label_name
			return label
		var nested := _status_label(child, label_name)
		if nested != null:
			return nested
	return null


func _refresh_observer_slots() -> void:
	if _observer_bar == null or not is_instance_valid(_observer_bar):
		return
	for child in _observer_bar.get_children():
		child.queue_free()
	var observers := _room_observers()
	var margin := MarginContainer.new()
	_margin_each(margin, 5, 5, 5, 5)
	_observer_bar.add_child(margin)
	var list := VBoxContainer.new()
	list.name = "ObserverSlotList"
	list.add_theme_constant_override("separation", 5)
	margin.add_child(list)
	for i in range(OBSERVER_SLOT_LIMIT):
		var observer := {}
		if i < observers.size() and observers[i] is Dictionary:
			observer = observers[i] as Dictionary
		list.add_child(_observer_slot_button(i, observer))


func _observer_slots_bar() -> PanelContainer:
	var bar := _panel(Color(0.98, 0.91, 0.70, 0.76), Color(0.16, 0.55, 0.57, 0.34), 8)
	bar.name = "ObserverSlotsBar"
	bar.custom_minimum_size = Vector2(94, 158)
	bar.visible = true
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	return bar


func _room_observers() -> Array:
	var room: Dictionary = _active_room()
	var value = room.get("observers", [])
	if value is Array:
		return (value as Array).duplicate(true)
	return []


func _local_observer() -> Dictionary:
	var participant_id: String = _current_network_participant_id()
	var room: Dictionary = _active_room()
	if participant_id.strip_edges() == "" or room.is_empty():
		return {}
	return _observer_for_participant(room, participant_id)


func _observer_display_name(observer: Dictionary, fallback: String) -> String:
	var name: String = String(observer.get("displayName", observer.get("name", fallback))).strip_edges()
	return fallback if name == "" else name


func _observer_slot_button(slot_index: int, observer: Dictionary) -> Button:
	var occupied := not observer.is_empty()
	var participant_id := _current_network_participant_id()
	var mine := occupied and String(observer.get("id", "")).strip_edges() == participant_id
	var can_enter := not occupied and _can_local_enter_observer_slot()
	var can_manage := mine and not _is_game_started()
	var button := Button.new()
	button.name = "ObserverSlotButton%d" % [slot_index + 1]
	var fallback_name := "自己" if mine else "空位"
	var slot_name := _observer_display_name(observer, fallback_name) if occupied else "空位"
	button.text = "观战%d\n%s" % [
		slot_index + 1,
		slot_name,
	]
	if can_manage:
		button.tooltip_text = "观战操作"
	elif can_enter:
		button.tooltip_text = "切换为观战"
	else:
		button.tooltip_text = button.text.replace("\n", " ")
	button.custom_minimum_size = Vector2(82, 44)
	button.focus_mode = Control.FOCUS_NONE
	button.clip_text = true
	button.disabled = not (can_enter or can_manage)
	_style_observer_slot_button(button, occupied, mine, can_enter)
	if can_manage:
		button.pressed.connect(func():
			call("_open_observer_slot_actions", slot_index)
		)
	elif can_enter:
		button.pressed.connect(func():
			call("_switch_local_to_observer")
		)
	return button


func _can_local_enter_observer_slot() -> bool:
	if _is_game_started():
		return false
	if _is_observer_participant(_current_network_participant_id()):
		return false
	var gate_value = call("_switch_to_observer_gate") if has_method("_switch_to_observer_gate") else {"ok": false}
	var gate: Dictionary = gate_value if gate_value is Dictionary else {"ok": false}
	return bool(gate.get("ok", false))


func _style_observer_slot_button(button: Button, occupied: bool, mine: bool, can_enter: bool) -> void:
	var color := GOLD if mine else TEAL if occupied else MUTED
	var bg_alpha := 0.30 if mine else 0.18 if occupied else 0.08
	if can_enter:
		color = TEAL
		bg_alpha = 0.14
	var bg := Color(color.r, color.g, color.b, bg_alpha)
	var border := Color(color.r, color.g, color.b, 0.42 if can_enter or mine else 0.24)
	button.add_theme_stylebox_override("normal", _style_box(bg, border, 7, 1))
	button.add_theme_stylebox_override("hover", _style_box(bg.lightened(0.08), border.lightened(0.10), 7, 1))
	button.add_theme_stylebox_override("pressed", _style_box(bg.darkened(0.12), border, 7, 1))
	button.add_theme_stylebox_override("disabled", _style_box(bg, border, 7, 1))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_disabled_color", INK if occupied else MUTED)
	button.add_theme_font_size_override("font_size", _ui_font_size(10))


func _system_progress_panel(message: String = "") -> PanelContainer:
	var panel := _panel(Color(0.010, 0.016, 0.020, 0.78), Color(0.96, 0.70, 0.32, 0.42), 8)
	panel.name = "SystemProgressToast"
	panel.set_meta("system_progress_toast", true)
	var margin := MarginContainer.new()
	_margin_each(margin, 16, 8, 16, 8)
	panel.add_child(margin)
	var label := _label(message, 13, Color.WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
	label.name = "SystemProgressToastLabel"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = false
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(0, 30)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(label)
	return panel


func _refresh_system_progress_panel() -> void:
	pass


func _show_system_progress_toast(message: String = "", hold_seconds: float = 4.2) -> void:
	if _hud_layer == null:
		if OS.is_debug_build():
			print("[WerewolfSystemProgressToast][debug] skip reason=no_hud message_chars=%d" % message.strip_edges().length())
		return
	var clean := message.strip_edges()
	if clean == "":
		clean = _system_message.strip_edges()
	if clean == "":
		if OS.is_debug_build():
			print("[WerewolfSystemProgressToast][debug] skip reason=empty")
		return
	var now := Time.get_ticks_msec()
	if clean == _last_system_progress_toast and now - _last_system_progress_toast_msec < 5000:
		if OS.is_debug_build():
			print("[WerewolfSystemProgressToast][debug] skip reason=duplicate chars=%d message=%s" % [clean.length(), clean])
		return
	_last_system_progress_toast = clean
	_last_system_progress_toast_msec = now
	_clear_system_progress_toast()
	var toast := _system_progress_panel(clean)
	toast.anchor_left = 0.5
	toast.anchor_right = 0.5
	toast.offset_left = -260
	toast.offset_right = 260
	toast.offset_top = 14
	toast.offset_bottom = 70
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.modulate.a = 0.0
	_system_progress_toast = toast
	_hud_layer.add_child(toast)
	if OS.is_debug_build():
		print("[WerewolfSystemProgressToast][debug] show chars=%d hold=%.2f message=%s" % [clean.length(), hold_seconds, clean])
	_system_progress_toast_tween = create_tween()
	_system_progress_toast_tween.tween_property(toast, "modulate:a", 1.0, 0.12)
	_system_progress_toast_tween.tween_interval(hold_seconds)
	_system_progress_toast_tween.tween_property(toast, "modulate:a", 0.0, 0.22)
	_system_progress_toast_tween.tween_callback(func():
		if toast != null and is_instance_valid(toast):
			toast.queue_free()
		if _system_progress_toast == toast:
			_system_progress_toast = null
	)


func _clear_system_progress_toast() -> void:
	if _system_progress_toast_tween != null:
		_system_progress_toast_tween.kill()
		_system_progress_toast_tween = null
	if _system_progress_toast != null and is_instance_valid(_system_progress_toast):
		_system_progress_toast.queue_free()
	if _hud_layer == null:
		_system_progress_toast = null
		return
	for child in _hud_layer.get_children():
		if bool(child.get_meta("system_progress_toast", false)) or String(child.name).begins_with("SystemProgressToast"):
			child.queue_free()
	_system_progress_toast = null


func _fill_system_progress(body: VBoxContainer, message: String = "") -> void:
	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_theme_constant_override("separation", 8)
	body.add_child(title_row)
	var room := _active_room()
	title_row.add_child(_nowrap_label("狼人杀 · %s" % String(room.get("map_name", "标准村庄")), 15, INK, true, HORIZONTAL_ALIGNMENT_CENTER))
	title_row.add_child(_chip(_phase_status_text(), GOLD))
	var clean_message := message.strip_edges()
	if clean_message != "" and clean_message != _phase_status_text():
		var message_label := _label(clean_message, 12, INK, true, HORIZONTAL_ALIGNMENT_CENTER)
		message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		message_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		message_label.custom_minimum_size = Vector2(0, 20)
		body.add_child(message_label)
	var steps := HBoxContainer.new()
	steps.alignment = BoxContainer.ALIGNMENT_CENTER
	steps.add_theme_constant_override("separation", 8)
	body.add_child(steps)
	var active := _progress_stage_key()
	for item in [
		{"key": "ready", "text": "准备"},
		{"key": "night", "text": "夜晚"},
		{"key": "speech", "text": "发言"},
		{"key": "vote", "text": "投票"},
		{"key": "result", "text": "结算"},
	]:
		var step: Dictionary = item
		steps.add_child(_progress_step(String(step.get("key", "")), String(step.get("text", "")), active))


func _progress_step(key: String, text: String, active: String) -> PanelContainer:
	var selected := key == active
	var color := GOLD if selected else MUTED
	var step := _panel(Color(color.r, color.g, color.b, 0.18 if selected else 0.06), Color(color.r, color.g, color.b, 0.54 if selected else 0.16), 999)
	step.custom_minimum_size = Vector2(68, 23)
	var margin := MarginContainer.new()
	_margin_each(margin, 8, 1, 8, 1)
	step.add_child(margin)
	margin.add_child(_nowrap_label(text, 11, color, true, HORIZONTAL_ALIGNMENT_CENTER))
	return step


func _progress_stage_key() -> String:
	if not _is_game_started():
		return "ready"
	var phase := String(_werewolf.get("phase", "lobby"))
	if phase in ["wolf_chat", "wolf_action", "guard_action", "seer_action", "witch_action"]:
		return "night"
	if phase in ["sheriff_speech", "day_discussion", "last_words"]:
		return "speech"
	if phase in ["sheriff_vote", "vote", "hunter_action"]:
		return "vote"
	return "result"
