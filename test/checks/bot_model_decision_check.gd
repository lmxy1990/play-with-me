extends SceneTree


func _initialize() -> void:
	var state = load("res://scripts/core/app_state.gd").new()
	state.persistence_enabled = false
	state.load_or_create()
	var page = load("res://scenes/werewolf_room.tscn").instantiate()
	page.set_app_state(state)
	root.add_child(page)
	await process_frame
	page._players = []
	for i in range(6):
		page._players.append({
			"id": "p%d" % i,
			"name": "玩家%d" % [i + 1],
			"role": "狼人" if i == 0 else "村民",
			"role_key": "wolf" if i == 0 else "villager",
			"avatar": "",
			"state": "等待",
			"motion": 0,
			"alive": true,
			"ready": true,
			"owner": "bot",
		})
	var target: int = page._target_from_model_decision("{\"action\":\"wolf_kill\",\"targetSeatNumber\":2}", 0, "wolf_kill")
	assert(target == 1)
	var illegal_self: int = page._target_from_model_decision("{\"action\":\"wolf_kill\",\"targetSeatNumber\":1}", 0, "wolf_kill")
	assert(illegal_self == -1)
	var illegal_action: int = page._target_from_model_decision("{\"action\":\"vote\",\"targetSeatNumber\":2}", 0, "wolf_kill")
	assert(illegal_action == -1)
	page.queue_free()
	await process_frame
	quit()
