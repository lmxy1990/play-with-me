extends RefCounted


const ACTION_SHERIFF_SPEECH_ORDER := "sheriff_speech_order"
const ACTION_SHERIFF_SPEECH_ORDER_CLOCKWISE := "sheriff_speech_order_clockwise"
const ACTION_SHERIFF_SPEECH_ORDER_COUNTERCLOCKWISE := "sheriff_speech_order_counterclockwise"
const ACTION_SHERIFF_BADGE := "sheriff_badge_action"
const ACTION_SHERIFF_BADGE_PASS := "sheriff_badge_pass"
const ACTION_SHERIFF_BADGE_DESTROY := "sheriff_badge_destroy"
const ACTION_WITCH_SAVE := "witch_save"
const ACTION_WITCH_POISON := "witch_poison"
const ACTION_WITCH_SKIP := "witch_skip"
const ACTION_SKIP := "skip"


func open_target_confirm(index: int, players: Array, werewolf_state: Dictionary, pending_actor_index: int, pending_action: String, callbacks: Dictionary) -> Dictionary:
	if index < 0 or index >= players.size() or _is_empty_seat(callbacks, index):
		return _blocked("请选择玩家头像", "skip")
	if not (players[index] is Dictionary):
		return _blocked("请选择玩家头像", "skip")
	var overlay_card := _callback(callbacks, "overlay_card")
	var overlay_body := _callback(callbacks, "overlay_body")
	if not overlay_card.is_valid() or not overlay_body.is_valid():
		return _blocked("真人玩家目标确认界面不可用", "skip")
	var card_value = overlay_card.call("确认目标", Vector2(560, 500), false, false)
	if not (card_value is Node):
		return _blocked("真人玩家目标确认界面不可用", "skip")
	var card: Node = card_value
	card.name = "TargetConfirmOverlay"
	var body_value = overlay_body.call(card)
	if not (body_value is VBoxContainer):
		return _blocked("真人玩家目标确认界面不可用", "skip")
	var body: VBoxContainer = body_value
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_theme_constant_override("separation", 8)
	var action_key := pending_action_key(werewolf_state)
	_add_label(body, callbacks, "%s · %s" % [_player_title(callbacks, pending_actor_index), pending_action], 17, _theme_color(callbacks, "ink"), true, HORIZONTAL_ALIGNMENT_CENTER)
	var hint := "点击座位直接提交。"
	match action_key:
		ACTION_SHERIFF_SPEECH_ORDER:
			hint = "先选发言起点，再点顺时针或逆时针。"
		ACTION_SHERIFF_BADGE:
			hint = "先选飞警徽目标，或直接撕毁警徽。"
		"witch_act":
			hint = "用药默认救狼刀目标，用毒使用当前目标。"
		"hunter_shoot":
			hint = "先选目标座位，再决定开枪或不开枪。"
	_add_label(body, callbacks, hint, 12, _theme_color(callbacks, "muted"), true, HORIZONTAL_ALIGNMENT_CENTER)
	var selection_label := Label.new()
	selection_label.name = "TargetSelectionLabel"
	selection_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	selection_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selection_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	selection_label.clip_text = true
	body.add_child(selection_label)
	var selected_target := {"index": index}
	var is_select_action := action_key in [ACTION_SHERIFF_SPEECH_ORDER, ACTION_SHERIFF_BADGE, "witch_act", "hunter_shoot"]
	var confirm_target := _callback(callbacks, "confirm_target")
	var actions: HBoxContainer = null
	if is_select_action:
		actions = HBoxContainer.new()
		actions.name = "TargetConfirmActions"
		actions.alignment = BoxContainer.ALIGNMENT_END
		actions.add_theme_constant_override("separation", 7)
	var seat_scroll := ScrollContainer.new()
	seat_scroll.name = "TargetSeatScroll"
	seat_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seat_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	seat_scroll.custom_minimum_size = Vector2(0, 238)
	seat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(seat_scroll)
	var seat_grid := GridContainer.new()
	seat_grid.name = "TargetSeatGrid"
	seat_grid.columns = 5
	seat_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seat_grid.add_theme_constant_override("h_separation", 7)
	seat_grid.add_theme_constant_override("v_separation", 7)
	seat_scroll.add_child(seat_grid)
	if actions != null:
		body.add_child(actions)
	var seat_buttons: Array = []
	var witch_night := {}
	if werewolf_state.get("night", {}) is Dictionary:
		witch_night = werewolf_state.get("night", {}) as Dictionary
	var witch_target_index := int(witch_night.get("wolf_target_index", -1))
	var witch_can_save := action_key == "witch_act" and witch_target_index >= 0 and witch_target_index < players.size() and players[witch_target_index] is Dictionary and bool(werewolf_state.get("witch_antidote", true)) and String((players[witch_target_index] as Dictionary).get("owner", "")).strip_edges() != "" and bool((players[witch_target_index] as Dictionary).get("alive", true))
	var witch_can_poison := action_key == "witch_act" and bool(werewolf_state.get("witch_poison", true))
	var refresh_controls := func():
		var selected_target_index := int(selected_target.get("index", -1))
		if selected_target_index >= 0 and selected_target_index < players.size() and players[selected_target_index] is Dictionary:
			selection_label.text = "当前目标：%s" % _player_title(callbacks, selected_target_index)
		else:
			selection_label.text = "请选择目标座位"
		for seat_button_value in seat_buttons:
			if not (seat_button_value is Button):
				continue
			var seat_button := seat_button_value as Button
			var seat_index := int(seat_button.get_meta("seat_index", -1))
			seat_button.button_pressed = is_select_action and seat_index == selected_target_index
		if actions == null:
			return
		var selected_alive := selected_target_index >= 0 and selected_target_index < players.size() and players[selected_target_index] is Dictionary and String((players[selected_target_index] as Dictionary).get("owner", "")).strip_edges() != "" and bool((players[selected_target_index] as Dictionary).get("alive", true))
		for child in actions.get_children():
			if not (child is Button):
				continue
			var button := child as Button
			match String(button.name):
				"WitchSkipButton":
					button.disabled = false
				"WitchSaveButton":
					button.disabled = not witch_can_save
				"WitchPoisonButton":
					button.disabled = not witch_can_poison or not selected_alive or selected_target_index == pending_actor_index
				"HunterSkipButton":
					button.disabled = false
				"HunterShootButton":
					button.disabled = not selected_alive or selected_target_index == pending_actor_index
				"BadgePassButton":
					button.disabled = not selected_alive or selected_target_index == pending_actor_index
				"BadgeDestroyButton":
					button.disabled = false
				"SpeechOrderClockwiseButton", "SpeechOrderCounterclockwiseButton":
					button.disabled = not selected_alive
	if action_key == ACTION_SHERIFF_SPEECH_ORDER:
		var counterclockwise_button := _button(callbacks, "逆时针", false, func(): confirm_target.call(int(selected_target.get("index", -1)), ACTION_SHERIFF_SPEECH_ORDER_COUNTERCLOCKWISE))
		counterclockwise_button.name = "SpeechOrderCounterclockwiseButton"
		actions.add_child(counterclockwise_button)
		var clockwise_button := _button(callbacks, "顺时针", true, func(): confirm_target.call(int(selected_target.get("index", -1)), ACTION_SHERIFF_SPEECH_ORDER_CLOCKWISE))
		clockwise_button.name = "SpeechOrderClockwiseButton"
		actions.add_child(clockwise_button)
	elif action_key == ACTION_SHERIFF_BADGE:
		var destroy_button := _button(callbacks, "撕警徽", false, func(): confirm_target.call(-1, ACTION_SHERIFF_BADGE_DESTROY))
		destroy_button.name = "BadgeDestroyButton"
		actions.add_child(destroy_button)
		var pass_button := _button(callbacks, "飞警徽", true, func(): confirm_target.call(int(selected_target.get("index", -1)), ACTION_SHERIFF_BADGE_PASS))
		pass_button.name = "BadgePassButton"
		actions.add_child(pass_button)
	elif action_key == "witch_act":
		var witch_skip_button := _button(callbacks, "不用药", false, func(): confirm_target.call(-1, ACTION_WITCH_SKIP))
		witch_skip_button.name = "WitchSkipButton"
		actions.add_child(witch_skip_button)
		if witch_can_poison:
			var poison_button := _button(callbacks, "用毒", true, func(): confirm_target.call(int(selected_target.get("index", -1)), ACTION_WITCH_POISON))
			poison_button.name = "WitchPoisonButton"
			actions.add_child(poison_button)
		if witch_can_save:
			var save_button := _button(callbacks, "用药", true, func(): confirm_target.call(witch_target_index, ACTION_WITCH_SAVE))
			save_button.name = "WitchSaveButton"
			actions.add_child(save_button)
	elif action_key == "hunter_shoot":
		var hunter_skip_button := _button(callbacks, "不开枪", false, func(): confirm_target.call(-1, ACTION_SKIP))
		hunter_skip_button.name = "HunterSkipButton"
		actions.add_child(hunter_skip_button)
		var shoot_button := _button(callbacks, "开枪", true, func(): confirm_target.call(int(selected_target.get("index", -1)), ""))
		shoot_button.name = "HunterShootButton"
		actions.add_child(shoot_button)
	for i in range(players.size()):
		if not (players[i] is Dictionary):
			continue
		var data: Dictionary = players[i]
		var seat_index := i
		var button := Button.new()
		button.name = "TargetSeatButton_%d" % [seat_index + 1]
		button.text = "%d号" % [seat_index + 1]
		button.toggle_mode = is_select_action
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 40)
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var seat_alive := bool(data.get("alive", true))
		var seat_owner := String(data.get("owner", "")).strip_edges()
		var seat_disabled := seat_owner == ""
		match action_key:
			ACTION_SHERIFF_SPEECH_ORDER, "guard_protect", "sheriff_vote":
				seat_disabled = seat_disabled or not seat_alive
			ACTION_SHERIFF_BADGE, "hunter_shoot", "seer_check", "vote", "wolf_kill":
				seat_disabled = seat_disabled or not seat_alive or seat_index == pending_actor_index
			"witch_act":
				if witch_can_save and seat_index == witch_target_index:
					seat_disabled = false
				else:
					seat_disabled = seat_disabled or not seat_alive or seat_index == pending_actor_index
			"mvp_vote":
				seat_disabled = seat_disabled
			_:
				seat_disabled = seat_disabled or not seat_alive
		button.disabled = seat_disabled
		button.set_meta("seat_index", seat_index)
		if is_select_action:
			button.pressed.connect(func():
				if button.disabled:
					return
				selected_target["index"] = seat_index
				refresh_controls.call()
			)
		else:
			button.pressed.connect(func():
				if button.disabled:
					return
				confirm_target.call(seat_index, "")
			)
		seat_buttons.append(button)
		seat_grid.add_child(button)
	refresh_controls.call()
	return {"ok": true}


func open_speech_editor(index: int, players: Array, callbacks: Dictionary) -> Dictionary:
	if index < 0 or index >= players.size() or _is_empty_seat(callbacks, index):
		return _blocked("发言玩家不存在", "skip")
	if not (players[index] is Dictionary):
		return _blocked("发言玩家不存在", "skip")
	var data: Dictionary = players[index]
	var overlay_card := _callback(callbacks, "overlay_card")
	var overlay_body := _callback(callbacks, "overlay_body")
	if not overlay_card.is_valid() or not overlay_body.is_valid():
		return _blocked("真人玩家发言界面不可用", "skip")
	var card_value = overlay_card.call("发言", Vector2(380, 360), false, false)
	if not (card_value is Node):
		return _blocked("真人玩家发言界面不可用", "skip")
	var card: Node = card_value
	card.name = "SpeechEditorOverlay"
	var body_value = overlay_body.call(card)
	if not (body_value is VBoxContainer):
		return _blocked("真人玩家发言界面不可用", "skip")
	var body: VBoxContainer = body_value
	body.add_child(_speech_editor_header(index, _display_data_for_index(index, data, callbacks), callbacks))
	_add_node(body, callbacks, "dense_form_label", ["发言内容"])
	var input := TextEdit.new()
	input.name = "SpeechInput"
	input.placeholder_text = "输入本轮发言"
	input.custom_minimum_size = Vector2(0, 120)
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	var style_input := _callback(callbacks, "style_input")
	if style_input.is_valid():
		style_input.call(input)
	body.add_child(input)
	_add_node(body, callbacks, "spacer")
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 7)
	body.add_child(actions)
	var submit_speech := _callback(callbacks, "submit_speech")
	actions.add_child(_button(callbacks, "跳过", false, func(): submit_speech.call("")))
	actions.add_child(_button(callbacks, "发送", true, func(): submit_speech.call(input.text)))
	input.grab_focus.call_deferred()
	return {"ok": true}


func open_name_editor(index: int, players: Array, local_nickname: String, callbacks: Dictionary) -> Dictionary:
	if index < 0 or index >= players.size() or not (players[index] is Dictionary):
		return _blocked("座位不存在", "skip")
	if not _can_edit_name(callbacks, index):
		return _blocked("", "skip")
	var overlay_card := _callback(callbacks, "overlay_card")
	var overlay_body := _callback(callbacks, "overlay_body")
	if not overlay_card.is_valid() or not overlay_body.is_valid():
		return _blocked("名字编辑界面不可用", "skip")
	var card_value = overlay_card.call("修改名字", Vector2(330, 220))
	if not (card_value is Node):
		return _blocked("名字编辑界面不可用", "skip")
	var body_value = overlay_body.call(card_value)
	if not (body_value is VBoxContainer):
		return _blocked("名字编辑界面不可用", "skip")
	var body: VBoxContainer = body_value
	_add_node(body, callbacks, "dense_form_label", ["名字"])
	var player: Dictionary = players[index]
	var input := LineEdit.new()
	input.name = "NameInput"
	input.text = String(player.get("name", local_nickname))
	input.placeholder_text = "输入名字"
	input.custom_minimum_size = Vector2(0, 34)
	var style_input := _callback(callbacks, "style_input")
	if style_input.is_valid():
		style_input.call(input)
	body.add_child(input)
	_add_node(body, callbacks, "spacer")
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 6)
	body.add_child(actions)
	var clear_modal := _callback(callbacks, "clear_modal")
	var save_name := _callback(callbacks, "save_name")
	actions.add_child(_button(callbacks, "取消", false, clear_modal))
	actions.add_child(_button(callbacks, "保存", true, func(): save_name.call(index, input.text)))
	input.grab_focus.call_deferred()
	return {"ok": true}


func open_seat_detail(index: int, players: Array, callbacks: Dictionary) -> Dictionary:
	if index < 0 or index >= players.size() or not (players[index] is Dictionary):
		return _blocked("座位不存在", "skip")
	var data: Dictionary = players[index]
	var alive := bool(data.get("alive", true))
	var owner := String(data.get("owner", "human"))
	var is_local_ai := _is_local_ai(callbacks, index)
	var overlay_card := _callback(callbacks, "overlay_card")
	var overlay_body := _callback(callbacks, "overlay_body")
	if not overlay_card.is_valid() or not overlay_body.is_valid():
		return _blocked("座位详情界面不可用", "skip")
	var card_value = overlay_card.call("座位信息", Vector2(340, 320))
	if not (card_value is Node):
		return _blocked("座位详情界面不可用", "skip")
	var card: Node = card_value
	card.name = "SeatDetailOverlay"
	var body_value = overlay_body.call(card)
	if not (body_value is VBoxContainer):
		return _blocked("座位详情界面不可用", "skip")
	var body: VBoxContainer = body_value
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	var display_data := _display_data_for_index(index, data, callbacks)
	_add_node(body, callbacks, "detail_avatar", [display_data, 92])
	_add_label(body, callbacks, "%d号 · %s" % [index + 1, _visible_role(callbacks, index)], 17, _theme_color(callbacks, "ink"), true, HORIZONTAL_ALIGNMENT_CENTER)
	var role_title := _visible_role_title(callbacks, index, data)
	if role_title != "":
		_add_label(body, callbacks, "头衔 · %s" % role_title, 13, _theme_color(callbacks, "gold"), true, HORIZONTAL_ALIGNMENT_CENTER)
	_add_label(body, callbacks, "状态 · %s" % seat_status_text(data), 14, _theme_color(callbacks, "green") if alive else _theme_color(callbacks, "red"), true, HORIZONTAL_ALIGNMENT_CENTER)
	body.add_child(_detail_name_row(index, players, callbacks))
	body.add_child(_seat_voice_toggle_row(index, callbacks))
	var tags := HFlowContainer.new()
	tags.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tags.alignment = FlowContainer.ALIGNMENT_CENTER
	tags.add_theme_constant_override("h_separation", 6)
	tags.add_theme_constant_override("v_separation", 6)
	body.add_child(tags)
	var owner_text := "AI" if is_local_ai else seat_owner_text(owner)
	var owner_color := _theme_color(callbacks, "teal") if is_local_ai else _theme_color(callbacks, "gold") if owner == "self" else _theme_color(callbacks, "muted")
	tags.add_child(_stat_badge(callbacks, "席", owner_text, owner_color, 82))
	tags.add_child(_stat_badge(callbacks, "态", String(data.get("state", "")), _theme_color(callbacks, "green") if alive else _theme_color(callbacks, "red"), 92))
	if is_local_ai:
		tags.add_child(_stat_badge(callbacks, "控", _player_controller_participant_id(callbacks, data), _theme_color(callbacks, "gold"), 112))
	var remove_gate := _remove_bot_gate(callbacks, index) if is_local_ai else {"ok": false}
	if bool(remove_gate.get("ok", false)):
		_add_node(body, callbacks, "spacer")
		var actions := HBoxContainer.new()
		actions.alignment = BoxContainer.ALIGNMENT_CENTER
		body.add_child(actions)
		var remove_bot_at := _callback(callbacks, "remove_bot_at")
		var remove_button := _button(callbacks, "移除机器人", false, func(): remove_bot_at.call(index), true)
		remove_button.name = "RemoveBotButton"
		actions.add_child(remove_button)
	return {"ok": true}


func pending_action_key(werewolf_state: Dictionary) -> String:
	var action_value = werewolf_state.get("current_action", {})
	if action_value is Dictionary:
		return String((action_value as Dictionary).get("key", "")).strip_edges()
	return ""


func seat_life_text(data: Dictionary) -> String:
	if not bool(data.get("alive", true)):
		return "死亡"
	return "已准备" if bool(data.get("ready", false)) else "未准备"


func seat_status_text(data: Dictionary) -> String:
	if not bool(data.get("alive", true)):
		return "死亡"
	if String(data.get("state", "")) != "":
		return String(data.get("state", ""))
	return "已准备" if bool(data.get("ready", false)) else "未准备"


func seat_owner_text(owner: String) -> String:
	match owner:
		"self":
			return "本人"
		"bot":
			return "机器人"
		_:
			return "玩家"


func _speech_editor_header(index: int, data: Dictionary, callbacks: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_node(row, callbacks, "detail_avatar", [data, 48])
	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 1)
	row.add_child(text_col)
	_add_node(text_col, callbacks, "nowrap_label", ["%d号 · %s" % [index + 1, String(data.get("name", ""))], 15, _theme_color(callbacks, "ink"), true])
	_add_node(text_col, callbacks, "nowrap_label", ["当前轮到该玩家发言", 12, _theme_color(callbacks, "gold"), true])
	return row


func _detail_name_row(index: int, players: Array, callbacks: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var player: Dictionary = players[index]
	var nowrap_label := _callback(callbacks, "nowrap_label")
	var name_value = null
	if nowrap_label.is_valid():
		name_value = nowrap_label.call(String(player.get("name", "")), 14, _theme_color(callbacks, "ink"), true, HORIZONTAL_ALIGNMENT_CENTER)
	if name_value is Label:
		var name_label: Label = name_value
		name_label.custom_minimum_size = Vector2(120, 22)
		row.add_child(name_label)
	if _can_edit_name(callbacks, index):
		var edit := TextureButton.new()
		var texture_path := _action_path(callbacks, "pencil")
		var texture := _texture(callbacks, texture_path)
		edit.texture_normal = texture
		edit.texture_hover = texture
		edit.texture_pressed = texture
		edit.ignore_texture_size = true
		edit.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		edit.custom_minimum_size = Vector2(22, 22)
		edit.focus_mode = Control.FOCUS_NONE
		edit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var open_name_editor := _callback(callbacks, "open_name_editor")
		edit.pressed.connect(func(): open_name_editor.call(index))
		row.add_child(edit)
	return row


func _seat_voice_toggle_row(index: int, callbacks: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 7)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_node(row, callbacks, "nowrap_label", ["头像旁白", 12, _theme_color(callbacks, "muted"), true, HORIZONTAL_ALIGNMENT_RIGHT])
	var enabled := _player_tts_enabled(callbacks, index)
	var toggle_player_tts := _callback(callbacks, "toggle_player_tts")
	var button := _button(callbacks, "声音开" if enabled else "声音关", enabled, func(): toggle_player_tts.call(index))
	button.name = "SeatVoiceToggleButton"
	row.add_child(button)
	return row


func _button(callbacks: Dictionary, text: String, primary: bool, callback: Callable, danger: bool = false) -> Button:
	var small_button := _callback(callbacks, "small_button")
	if small_button.is_valid():
		var button_value = small_button.call(text, primary, callback, danger)
		if button_value is Button:
			return button_value
	var button := Button.new()
	button.text = text
	button.pressed.connect(func():
		if callback.is_valid():
			callback.call()
	)
	return button


func _stat_badge(callbacks: Dictionary, mark: String, value: String, color: Color, min_width: float = 0.0) -> Control:
	var stat_badge := _callback(callbacks, "stat_badge")
	if stat_badge.is_valid():
		var badge_value = stat_badge.call(mark, value, color, min_width)
		if badge_value is Control:
			return badge_value
	var fallback := Label.new()
	fallback.text = "%s %s" % [mark, value]
	return fallback


func _add_label(parent: Node, callbacks: Dictionary, text: String, size: int, color: Color, bold: bool = false, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var label := _callback(callbacks, "label")
	if not label.is_valid():
		return
	var node_value = label.call(text, size, color, bold, align)
	if node_value is Node:
		parent.add_child(node_value)


func _add_node(parent: Node, callbacks: Dictionary, key: String, args: Array = []) -> void:
	var factory := _callback(callbacks, key)
	if not factory.is_valid():
		return
	var node_value = null
	match args.size():
		0:
			node_value = factory.call()
		1:
			node_value = factory.call(args[0])
		2:
			node_value = factory.call(args[0], args[1])
		3:
			node_value = factory.call(args[0], args[1], args[2])
		4:
			node_value = factory.call(args[0], args[1], args[2], args[3])
		5:
			node_value = factory.call(args[0], args[1], args[2], args[3], args[4])
	if node_value is Node:
		parent.add_child(node_value)


func _is_empty_seat(callbacks: Dictionary, index: int) -> bool:
	var is_empty := _callback(callbacks, "is_empty_seat")
	if is_empty.is_valid():
		return bool(is_empty.call(index))
	return false


func _player_title(callbacks: Dictionary, index: int) -> String:
	var title := _callback(callbacks, "player_title")
	if title.is_valid():
		return String(title.call(index))
	return "%d号玩家" % [index + 1] if index >= 0 else "玩家"


func _display_data_for_index(index: int, data: Dictionary, callbacks: Dictionary) -> Dictionary:
	var result := data.duplicate(true)
	var avatar_path := _avatar_for_index(callbacks, index)
	if avatar_path != "":
		result["avatar"] = avatar_path
	return result


func _avatar_for_index(callbacks: Dictionary, index: int) -> String:
	var avatar := _callback(callbacks, "avatar_for_index")
	if avatar.is_valid():
		return String(avatar.call(index)).strip_edges()
	return ""


func _visible_role_title(callbacks: Dictionary, index: int, data: Dictionary) -> String:
	var visible_role := _visible_role(callbacks, index)
	if visible_role in ["", "未知", "空位"]:
		return ""
	return String(data.get("role_title", data.get("roleTitle", ""))).strip_edges()


func _seat_status_text(callbacks: Dictionary, data: Dictionary) -> String:
	var status := _callback(callbacks, "seat_status_text")
	if status.is_valid():
		return String(status.call(data))
	return seat_status_text(data)


func _can_edit_name(callbacks: Dictionary, index: int) -> bool:
	var can_edit := _callback(callbacks, "can_edit_name")
	if can_edit.is_valid():
		return bool(can_edit.call(index))
	return false


func _is_local_ai(callbacks: Dictionary, index: int) -> bool:
	var is_local_ai := _callback(callbacks, "is_local_ai")
	if is_local_ai.is_valid():
		return bool(is_local_ai.call(index))
	return false


func _visible_role(callbacks: Dictionary, index: int) -> String:
	var visible_role := _callback(callbacks, "visible_role_for_index")
	if visible_role.is_valid():
		return String(visible_role.call(index))
	return "未知"


func _player_tts_enabled(callbacks: Dictionary, index: int) -> bool:
	var enabled := _callback(callbacks, "player_tts_enabled")
	if enabled.is_valid():
		return bool(enabled.call(index))
	return false


func _player_controller_participant_id(callbacks: Dictionary, data: Dictionary) -> String:
	var controller := _callback(callbacks, "player_controller_participant_id")
	if controller.is_valid():
		return String(controller.call(data))
	return String(data.get("controller_participant_id", ""))


func _remove_bot_gate(callbacks: Dictionary, index: int) -> Dictionary:
	var gate := _callback(callbacks, "remove_bot_gate")
	if gate.is_valid():
		var result = gate.call(index)
		if result is Dictionary:
			return result
	return {"ok": false}


func _action_path(callbacks: Dictionary, action_key: String) -> String:
	var action_path := _callback(callbacks, "action_path")
	if action_path.is_valid():
		return String(action_path.call(action_key))
	return ""


func _texture(callbacks: Dictionary, path: String) -> Texture2D:
	var texture := _callback(callbacks, "texture")
	if texture.is_valid():
		var result = texture.call(path)
		if result is Texture2D:
			return result
	return null


func _theme_color(callbacks: Dictionary, key: String) -> Color:
	var theme_value = callbacks.get("theme", {})
	if theme_value is Dictionary:
		var theme: Dictionary = theme_value
		if theme.has(key):
			return theme[key]
	return Color.WHITE


func _callback(callbacks: Dictionary, key: String) -> Callable:
	var value = callbacks.get(key, Callable())
	if value is Callable:
		return value
	return Callable()


func _blocked(message: String, effect: String) -> Dictionary:
	return {
		"ok": false,
		"message": message,
		"effect": effect,
	}
