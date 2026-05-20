extends SceneTree

const SeatCardScript := preload("res://scripts/room/werewolf/seat_card.gd")


func _initialize() -> void:
	var visible_card := _seat_card(0, {
		"name": "deepseek-v4-flash",
		"owner": "bot",
		"role": "狼人",
		"role_visible": true,
		"avatar": "res://assets/images/werewolf/avatars/robot.png",
		"alive": true,
		"ready": true,
	})
	root.add_child(visible_card)
	await process_frame

	if not _expect(_label_text(visible_card, "SeatNumberBadge") == "1号", "occupied card always shows seat number badge"):
		return
	if not _expect(_label_text(visible_card, "Title") == "1号 · 狼人", "occupied card shows seat number and role"):
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
	if not _expect(_label_text(visible_card, "Title") == "1号 · 狼人", "seat rebuild preserves role label"):
		return

	var hidden_card := _seat_card(2, {
		"displayName": "联网玩家",
		"owner": "human",
		"role": "预言家",
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
