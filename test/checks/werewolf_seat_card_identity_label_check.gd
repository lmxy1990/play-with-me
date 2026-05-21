extends SceneTree

const SeatCardScript := preload("res://scripts/room/werewolf/seat_card.gd")


func _initialize() -> void:
	var visible_card := _seat_card(0, {
		"name": "deepseek-v4-flash",
		"owner": "bot",
		"role": "狼人",
		"role_title": "夜行者",
		"role_visible": true,
		"avatar": "res://assets/images/werewolf/avatars/robot.png",
		"alive": true,
		"ready": true,
	})
	root.add_child(visible_card)
	await process_frame

	if not _expect(_label_text(visible_card, "SeatNumberBadge") == "1号", "occupied card always shows seat number badge"):
		return
	if not _expect(_label_text(visible_card, "Title") == "1号 · 狼人 · 夜行者", "occupied card shows seat number, role and role title"):
		return
	if not _expect(_label_text(visible_card, "NameLabel") == "deepseek-v4-flash", "occupied card shows nickname"):
		return
	if not _expect(_inside_card(visible_card, "Title"), "role title is laid out inside the seat card"):
		return
	if not _expect(_inside_card(visible_card, "NameLabel"), "nickname is laid out inside the seat card"):
		return

	visible_card.start_motion(SeatCardScript.SeatMotion.THINKING)
	visible_card.start_motion(SeatCardScript.SeatMotion.SPEAKING)
	if not _expect(_direct_child_count(visible_card, "Title") == 1, "seat rebuild keeps exactly one title label"):
		return
	if not _expect(_direct_child_count(visible_card, "NameLabel") == 1, "seat rebuild keeps exactly one nickname label"):
		return
	if not _expect(_label_text(visible_card, "Title") == "1号 · 狼人 · 夜行者", "seat rebuild preserves role label and title"):
		return

	var badge_card := _seat_card(1, {
		"name": "角标玩家",
		"owner": "bot",
		"role": "守卫",
		"role_title": "守夜人",
		"role_visible": true,
		"avatar": "",
		"alive": true,
		"ready": true,
		"avatar_badges": [
			{"id": "sheriff", "icon": "test://sheriff", "tooltip": "警徽"},
			{"id": "guard", "icon": "test://guard", "tooltip": "守护"},
			{"id": "mvp", "icon": "test://mvp", "tooltip": "MVP"},
		],
	})
	badge_card.texture_provider = Callable(self, "_dummy_texture")
	badge_card.voice_icon_path = "test://voice"
	root.add_child(badge_card)
	await process_frame
	if not _expect(_control_inside_card(badge_card, "SheriffAvatarBadge"), "sheriff avatar badge is laid out inside the seat card"):
		return
	if not _expect(_control_inside_card(badge_card, "GuardAvatarBadge"), "guard avatar badge is laid out inside the seat card"):
		return
	if not _expect(_control_inside_card(badge_card, "MvpAvatarBadge"), "mvp avatar badge is laid out inside the seat card"):
		return
	if not _expect(_controls_do_not_overlap(badge_card, "SeatCardVoiceToggleButton", "SheriffAvatarBadge"), "voice toggle does not overlap avatar badges"):
		return

	var hidden_card := _seat_card(2, {
		"displayName": "联网玩家",
		"owner": "human",
		"role": "预言家",
		"role_title": "洞察者",
		"role_visible": false,
		"avatar": "",
		"alive": true,
		"ready": false,
	})
	root.add_child(hidden_card)
	await process_frame
	if not _expect(_label_text(hidden_card, "SeatNumberBadge") == "3号", "hidden-role card shows seat number badge"):
		return
	if not _expect(_label_text(hidden_card, "Title") == "3号 · 未知", "hidden-role card does not leak role"):
		return
	if not _expect(_label_text(hidden_card, "NameLabel") == "联网玩家", "hidden-role card uses displayName fallback"):
		return

	hidden_card.data["alive"] = false
	hidden_card.start_motion(SeatCardScript.SeatMotion.DEAD)
	if not _expect(_label_text(hidden_card, "Title") == "3号 · 未知", "dead hidden-role card does not reveal role"):
		return

	var empty_card := _seat_card(4, {
		"name": "5号位",
		"owner": "",
		"role": "待加入",
		"role_visible": true,
		"avatar": "",
		"alive": true,
		"ready": false,
	})
	root.add_child(empty_card)
	await process_frame
	if not _expect(_label_text(empty_card, "SeatNumberBadge") == "5号", "empty card shows seat number badge"):
		return
	if not _expect(_label_text(empty_card, "Title") == "5号 · 空位", "empty card shows slot state"):
		return
	if not _expect(_label_text(empty_card, "NameLabel") == "点击落座 / AI", "empty card shows join hint"):
		return

	visible_card.queue_free()
	badge_card.queue_free()
	hidden_card.queue_free()
	empty_card.queue_free()
	await process_frame
	quit(0)


func _seat_card(index: int, data: Dictionary) -> Control:
	var card := SeatCardScript.new()
	card.index = index
	card.data = data
	card.size = Vector2(96, 108)
	return card


func _label_text(card: Control, label_name: String) -> String:
	var label := card.find_child(label_name, false, false) as Label
	return String(label.text) if label != null else ""


func _inside_card(card: Control, label_name: String) -> bool:
	var label := card.find_child(label_name, false, false) as Label
	if label == null:
		return false
	return label.position.x >= 0.0 and label.position.y >= 0.0 and label.position.x + label.size.x <= card.size.x and label.position.y + label.size.y <= card.size.y


func _control_inside_card(card: Control, child_name: String) -> bool:
	var control := card.find_child(child_name, false, false) as Control
	if control == null:
		return false
	return control.position.x >= 0.0 and control.position.y >= 0.0 and control.position.x + control.size.x <= card.size.x and control.position.y + control.size.y <= card.size.y


func _controls_do_not_overlap(card: Control, left_name: String, right_name: String) -> bool:
	var left := card.find_child(left_name, false, false) as Control
	var right := card.find_child(right_name, false, false) as Control
	if left == null or right == null:
		return false
	return not Rect2(left.position, left.size).intersects(Rect2(right.position, right.size))


func _dummy_texture(_path: String) -> Texture2D:
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 1, 1, 1))
	return ImageTexture.create_from_image(image)


func _direct_child_count(card: Control, child_name: String) -> int:
	var count := 0
	for child in card.get_children():
		if String(child.name) == child_name:
			count += 1
	return count


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("werewolf_seat_card_identity_label_check failed: %s" % message)
	quit(1)
	return false
