extends SceneTree


var _overlay_root: Control
var _confirmed_targets: Array = []
var _submitted_speeches: Array = []
var _saved_names: Array = []
var _removed_bot_indices: Array = []
var _players := [
	{"name": "一号", "state": "存活", "alive": true, "owner": "self", "avatar": ""},
	{"name": "二号", "state": "死亡", "alive": false, "owner": "bot", "avatar": "", "controller_participant_id": "host"},
]


func _initialize() -> void:
	var controller = load("res://scripts/player/werewolf/human/werewolf_human_player_interaction_controller.gd").new()
	if not _expect(controller.pending_action_key({"current_action": {"key": "sheriff_badge_action"}}) == "sheriff_badge_action", "action key reads current action"):
		return
	_overlay_root = Control.new()
	get_root().add_child(_overlay_root)
	var badge_result: Dictionary = controller.open_target_confirm(0, _players, {"current_action": {"key": "sheriff_badge_action"}}, 0, "警徽处理", _callbacks())
	if not _expect(bool(badge_result.get("ok", false)), "badge target confirm opens"):
		return
	var badge_card := _overlay_root.find_child("TargetConfirmOverlay", true, false)
	if not _expect(badge_card != null, "target confirm card is named"):
		return
	var destroy_button := _find_button(badge_card, "撕警徽")
	if not _expect(destroy_button != null, "destroy badge button exists"):
		return
	destroy_button.emit_signal("pressed")
	if not _expect(_confirmed_targets.size() == 1, "destroy badge emits target action"):
		return
	if not _expect(int(_confirmed_targets[0].get("target", 99)) == -1, "destroy badge target is empty"):
		return
	if not _expect(String(_confirmed_targets[0].get("action", "")) == "sheriff_badge_destroy", "destroy badge action is explicit"):
		return
	var dead_badge_result: Dictionary = controller.open_target_confirm(1, _players, {"current_action": {"key": "sheriff_badge_action"}}, 0, "警徽处理", _callbacks())
	if not _expect(bool(dead_badge_result.get("ok", false)), "dead target confirm opens for destroy option"):
		return
	var pass_button := _find_button(_overlay_root.find_child("TargetConfirmOverlay", true, false), "飞警徽")
	if not _expect(pass_button != null and pass_button.disabled, "dead player cannot receive badge"):
		return
	var speech_result: Dictionary = controller.open_speech_editor(0, _players, _callbacks())
	if not _expect(bool(speech_result.get("ok", false)), "speech editor opens"):
		return
	var input := _overlay_root.find_child("SpeechInput", true, false) as TextEdit
	if not _expect(input != null, "speech input exists"):
		return
	input.text = "我来发言。"
	var send_button := _find_button(_overlay_root.find_child("SpeechEditorOverlay", true, false), "发送")
	if not _expect(send_button != null, "send speech button exists"):
		return
	send_button.emit_signal("pressed")
	if not _expect(_submitted_speeches.size() == 1 and String(_submitted_speeches[0]) == "我来发言。", "send speech submits text"):
		return
	var name_result: Dictionary = controller.open_name_editor(0, _players, "本机", _callbacks())
	if not _expect(bool(name_result.get("ok", false)), "name editor opens"):
		return
	var name_input := _overlay_root.find_child("NameInput", true, false) as LineEdit
	if not _expect(name_input != null and name_input.text == "一号", "name editor shows current name"):
		return
	name_input.text = "新名字"
	var save_button := _find_button(_overlay_root.find_child("OverlayCard", true, false), "保存")
	if not _expect(save_button != null, "save name button exists"):
		return
	save_button.emit_signal("pressed")
	if not _expect(_saved_names.size() == 1 and String(_saved_names[0].get("name", "")) == "新名字", "save name callback receives text"):
		return
	var detail_result: Dictionary = controller.open_seat_detail(1, _players, _callbacks())
	if not _expect(bool(detail_result.get("ok", false)), "seat detail opens"):
		return
	var remove_button := _find_button(_overlay_root.find_child("SeatDetailOverlay", true, false), "移除机器人")
	if not _expect(remove_button != null, "local AI seat shows remove button"):
		return
	remove_button.emit_signal("pressed")
	if not _expect(_removed_bot_indices == [1], "remove bot callback receives index"):
		return
	quit(0)


func _callbacks() -> Dictionary:
	return {
		"overlay_card": Callable(self, "_overlay_card"),
		"overlay_body": Callable(self, "_overlay_body"),
		"detail_avatar": Callable(self, "_detail_avatar"),
		"label": Callable(self, "_label"),
		"nowrap_label": Callable(self, "_nowrap_label"),
		"dense_form_label": Callable(self, "_dense_form_label"),
		"spacer": Callable(self, "_spacer"),
		"small_button": Callable(self, "_small_button"),
		"style_input": Callable(self, "_style_input"),
		"stat_badge": Callable(self, "_stat_badge"),
		"clear_modal": Callable(self, "_clear_modal"),
		"confirm_target": Callable(self, "_confirm_target"),
		"submit_speech": Callable(self, "_submit_speech"),
		"save_name": Callable(self, "_save_name"),
		"open_name_editor": Callable(self, "_open_name_editor"),
		"is_empty_seat": Callable(self, "_is_empty_seat"),
		"player_title": Callable(self, "_player_title"),
		"seat_status_text": Callable(self, "_seat_status_text"),
		"can_edit_name": Callable(self, "_can_edit_name"),
		"visible_role_for_index": Callable(self, "_visible_role_for_index"),
		"is_local_ai": Callable(self, "_is_local_ai"),
		"player_tts_enabled": Callable(self, "_player_tts_enabled"),
		"toggle_player_tts": Callable(self, "_toggle_player_tts"),
		"player_controller_participant_id": Callable(self, "_player_controller_participant_id"),
		"remove_bot_gate": Callable(self, "_remove_bot_gate"),
		"remove_bot_at": Callable(self, "_remove_bot_at"),
		"action_path": Callable(self, "_action_path"),
		"texture": Callable(self, "_texture"),
		"theme": {
			"ink": Color(0.1, 0.1, 0.1),
			"gold": Color(0.7, 0.4, 0.1),
			"teal": Color(0.1, 0.4, 0.4),
			"green": Color(0.2, 0.5, 0.2),
			"red": Color(0.8, 0.2, 0.1),
			"muted": Color(0.5, 0.5, 0.5),
		},
	}


func _overlay_card(title: String, _size: Vector2) -> PanelContainer:
	_clear_modal()
	var card := PanelContainer.new()
	card.name = "OverlayCard"
	var body := VBoxContainer.new()
	body.name = "Body"
	card.add_child(body)
	_overlay_root.add_child(card)
	return card


func _overlay_body(card: Node) -> VBoxContainer:
	return card.find_child("Body", true, false) as VBoxContainer


func _detail_avatar(_data: Dictionary, size_px: int) -> Control:
	var avatar := Control.new()
	avatar.name = "Avatar"
	avatar.custom_minimum_size = Vector2(size_px, size_px)
	return avatar


func _label(text: String, _size: int, _color: Color, _bold: bool = false, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	return label


func _nowrap_label(text: String, size: int, color: Color, bold: bool = false, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	return _label(text, size, color, bold, align)


func _dense_form_label(text: String) -> Label:
	return _label(text, 12, Color.WHITE, true)


func _spacer() -> Control:
	return Control.new()


func _small_button(text: String, _primary: bool, callback: Callable, _danger: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(func(): callback.call())
	return button


func _style_input(_control: Control) -> void:
	pass


func _stat_badge(mark: String, value: String, _color: Color, _min_width: float = 0.0) -> PanelContainer:
	var badge := PanelContainer.new()
	badge.name = "StatBadge"
	var label := Label.new()
	label.text = "%s %s" % [mark, value]
	badge.add_child(label)
	return badge


func _clear_modal() -> void:
	for child in _overlay_root.get_children():
		_overlay_root.remove_child(child)
		child.free()


func _confirm_target(index: int, action_name: String) -> void:
	_confirmed_targets.append({
		"target": index,
		"action": action_name,
	})


func _submit_speech(text: String) -> void:
	_submitted_speeches.append(text)


func _save_name(index: int, text: String) -> void:
	_saved_names.append({
		"index": index,
		"name": text,
	})


func _open_name_editor(_index: int) -> void:
	pass


func _is_empty_seat(index: int) -> bool:
	if index < 0 or index >= _players.size():
		return true
	return String((_players[index] as Dictionary).get("owner", "")) == ""


func _player_title(index: int) -> String:
	return "%d号玩家" % [index + 1]


func _seat_status_text(data: Dictionary) -> String:
	return "死亡" if not bool(data.get("alive", true)) else String(data.get("state", ""))


func _can_edit_name(index: int) -> bool:
	return index == 0


func _visible_role_for_index(index: int) -> String:
	return "身份%d" % [index + 1]


func _is_local_ai(index: int) -> bool:
	return index == 1


func _player_tts_enabled(index: int) -> bool:
	return index == 0


func _toggle_player_tts(_index: int) -> void:
	pass


func _player_controller_participant_id(data: Dictionary) -> String:
	return String(data.get("controller_participant_id", ""))


func _remove_bot_gate(index: int) -> Dictionary:
	return {"ok": index == 1}


func _remove_bot_at(index: int) -> void:
	_removed_bot_indices.append(index)


func _action_path(action: String) -> String:
	return action


func _texture(_path: String):
	return null


func _find_button(root: Node, text: String) -> Button:
	if root == null:
		return null
	if root is Button and (root as Button).text == text:
		return root as Button
	for child in root.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("werewolf_human_player_interaction_controller_check failed: %s" % message)
	quit(1)
	return false
