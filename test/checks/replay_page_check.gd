extends SceneTree


func _initialize() -> void:
	var state = load("res://scripts/core/app_state.gd").new()
	state.persistence_enabled = false
	state.load_or_create()
	state.players = [
		_player("张安", "预言家", true, "self", "res://assets/images/werewolf/avatars/seer.png"),
		_player("李宁", "狼人", false, "bot", "res://assets/images/werewolf/avatars/wolf.png"),
		_player("周雨", "女巫", true, "bot", "res://assets/images/werewolf/avatars/witch.png"),
	]
	state.werewolf = {
		"phase": "completed",
		"started": true,
		"winner": "好人",
		"post_game": {"stage": "completed", "mvp_index": 0},
	}
	state.history = [
		{"speaker": "主持人", "text": "游戏开始。", "at": 100},
		{"speaker": "查验结果", "text": "1号查验2号为狼人。", "at": 200},
		{"speaker": "主持人", "text": "好人胜利。", "at": 300},
		{"speaker": "MVP投票", "text": "本局 MVP：1号 张安。", "at": 400},
	]
	state.update_active_room_counts()

	var page := _page("res://scenes/replay.tscn", state)
	root.add_child(page)
	await process_frame

	assert(page._review_result_text().contains("MVP"))
	assert(page._review_occupied_text() == "3/3")
	assert(page._review_is_mvp(0))
	assert(page._review_events().size() == 4)
	assert(page._review_event_type(state.history[1]) == "inspect")

	page.queue_free()
	await process_frame
	quit()


func _page(path: String, state) -> Control:
	var packed := load(path) as PackedScene
	var page := packed.instantiate() as Control
	page.set_app_state(state)
	return page


func _player(name: String, role: String, alive: bool, owner: String, avatar: String) -> Dictionary:
	return {
		"name": name,
		"role": role,
		"avatar": avatar,
		"state": "复盘" if alive else "死亡",
		"motion": 0,
		"alive": alive,
		"ready": true,
		"owner": owner,
	}
