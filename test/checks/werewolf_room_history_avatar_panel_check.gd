extends SceneTree

const MaskScript := preload("res://scripts/ui/common/circular_texture_mask.gd")


func _initialize() -> void:
	_check_circle_mask_alpha()

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

	room._players = [
		_player("self", "玩家A", "villager"),
		_player("bot_b", "玩家B", "wolf"),
		_player("bot_c", "玩家C", "seer"),
		_player("bot_d", "玩家D", "witch"),
		_player("bot_e", "玩家E", "villager"),
		_player("bot_f", "玩家F", "wolf"),
	]
	room._local_player_index = 0
	room._history = _history_items(34)
	room._open_history()
	await process_frame
	await process_frame

	var scroll := room.find_child("HistoryChatScroll", true, false) as ScrollContainer
	if not _expect(scroll != null, "history popup has a scroll container"):
		return
	if not _expect(scroll.mouse_filter == Control.MOUSE_FILTER_STOP, "history scroll receives touch input"):
		return
	if not _expect(scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO, "history scroll allows vertical scrolling"):
		return
	var list := room.find_child("HistoryChatList", true, false) as VBoxContainer
	if not _expect(list != null and list.get_child_count() >= 30, "history records are stacked in the scroll list"):
		return
	if not _expect(room.find_child("HistoryAvatar", true, false) != null, "history rows use circular avatars"):
		return
	if not _expect(room.find_child("HistoryChatMetaLabel", true, false) != null, "history rows show slot name"):
		return
	if not _expect(room.find_child("HistoryChatContentLabel", true, false) != null, "history rows show speech content"):
		return

	room._clear_modal()
	room._center_speech_items.clear()
	var speech := "我这轮只看原始发言内容，保留 12 号和 JSON: {\"a\":1} 这些字符。"
	room._show_center_speech_item({"speaker": "2号 玩家B", "text": speech, "at": 88.0}, true, false, true)
	await process_frame
	var center_label := room.find_child("CenterSpeechTextLabel", true, false) as Label
	if not _expect(center_label != null, "center panel renders a plain text label"):
		return
	if not _expect(center_label.text == speech, "center panel preserves original text"):
		return
	if not _expect(room.find_child("CenterSpeechTextScroll", true, false) != null, "center panel text area is scrollable"):
		return
	if not _expect(not _contains_progress_bar(room._center_panel), "center panel no longer shows progress format"):
		return
	if not _expect(not _contains_rich_text(room._center_panel), "center panel no longer uses bbcode output"):
		return

	room.queue_free()
	await process_frame
	quit(0)


func _check_circle_mask_alpha() -> void:
	var image := Image.create(20, 20, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 0, 0, 1))
	var texture := ImageTexture.create_from_image(image)
	var mask = MaskScript.new()
	var masked: Texture2D = mask.masked(texture, 24)
	assert(masked != null)
	var result := masked.get_image()
	assert(result.get_pixel(0, 0).a < 0.05)
	assert(result.get_pixel(12, 12).a > 0.95)


func _history_items(count: int) -> Array:
	var result := []
	for i in range(count):
		var index := i % 3
		result.append({
			"speaker": "%d号 玩家%s" % [index + 1, String.chr(65 + index)],
			"speaker_index": index,
			"text": "第%d条发言，测试历史弹窗滚动和头像圆形裁剪。" % [i + 1],
			"visibility": "public",
			"at": float(i + 1),
		})
	return result


func _player(id: String, name: String, role_key: String) -> Dictionary:
	var role_names := {
		"villager": "村民",
		"wolf": "狼人",
		"seer": "预言家",
		"witch": "女巫",
	}
	return {
		"id": id,
		"name": name,
		"owner": "self" if id == "self" else "bot",
		"role": String(role_names.get(role_key, role_key)),
		"role_key": role_key,
		"avatar": "",
		"alive": true,
		"ready": true,
	}


func _contains_progress_bar(node: Node) -> bool:
	if node is ProgressBar:
		return true
	for child in node.get_children():
		if _contains_progress_bar(child):
			return true
	return false


func _contains_rich_text(node: Node) -> bool:
	if node is RichTextLabel:
		return true
	for child in node.get_children():
		if _contains_rich_text(child):
			return true
	return false


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("werewolf_room_history_avatar_panel_check failed: %s" % message)
	quit(1)
	return false
