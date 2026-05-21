extends SceneTree


func _initialize() -> void:
	var parser = load("res://scripts/player/werewolf/ai/ai_werewolf_target_intent.gd").new()
	assert(int(parser.infer("我倾向今晚先处理 5号位，别拖。").get("seat_number", -1)) == 5)
	assert(int(parser.infer("同意刀六号，白天再推票。").get("seat_number", -1)) == 6)
	assert(int(parser.infer("3号可以杀，收益更高。").get("seat_number", -1)) == 3)
	assert(int(parser.infer("先别刀5号，目标换到2号。").get("seat_number", -1)) == 2)
	assert(parser.infer("不要杀三号，留着抗推。").is_empty())

	var state = load("res://scripts/core/app_state.gd").new()
	state.persistence_enabled = false
	state.load_or_create()
	var page = load("res://scenes/werewolf_room.tscn").instantiate()
	page.set_app_state(state)
	root.add_child(page)
	await process_frame

	_seed_players(page)
	_check_private_timeline_visibility(page)
	_check_intent_overrides_vote(page)
	_check_vote_resolution(page)
	_check_network_snapshot_filters_wolf_history(page)

	page.queue_free()
	await process_frame
	quit()


func _seed_players(page) -> void:
	page._players = [
		_player("wolf_a", "甲", "wolf", "bot", "wolf_a_participant"),
		_player("wolf_b", "乙", "wolf", "bot", "wolf_b_participant"),
		_player("villager_c", "丙", "villager", "human", "villager_c_participant"),
		_player("villager_d", "丁", "villager", "human", "villager_d_participant"),
	]
	page._werewolf = {
		"phase": "wolf_action",
		"day": 1,
		"map_name": "标准村庄",
		"has_sheriff": false,
		"votes": {},
		"night": {},
		"current_action": {"key": "wolf_kill", "actor_index": 0, "label": "刀人"},
		"last_guarded_index": -1,
		"post_game": {"stage": ""},
	}
	page._history = [
		{"speaker": "主持人", "text": "第1夜开始。", "at": 1.0},
	]
	page._reset_wolf_private_flow()


func _check_private_timeline_visibility(page) -> void:
	assert(page._record_bot_wolf_chat(0, "我倾向今晚先刀3号位。"))
	var wolf_state: Dictionary = page._bot_visible_state(0, {})
	var wolf_timeline: Array = wolf_state["timeline"]
	assert(String((wolf_timeline.back() as Dictionary).get("type", "")) == "wolf_spoke")
	var villager_state: Dictionary = page._bot_visible_state(2, {})
	for event in villager_state["timeline"]:
		assert(String((event as Dictionary).get("type", "")) != "wolf_spoke")
	assert(page._history.size() == 1)


func _check_intent_overrides_vote(page) -> void:
	var normalized: Dictionary = page._normalized_wolf_target_vote_decision(0, {
		"ok": true,
		"action": "wolf_kill",
		"target_index": 3,
	})
	assert(int(normalized.get("target_index", -1)) == 2)


func _check_vote_resolution(page) -> void:
	page._reset_wolf_private_flow()
	assert(page._record_bot_wolf_target_vote(0, {"action": "wolf_kill", "target_index": 3}))
	assert(page._record_bot_wolf_target_vote(1, {"action": "wolf_kill", "target_index": 2}))
	assert(page._resolved_wolf_target_index(0) == 2)


func _check_network_snapshot_filters_wolf_history(page) -> void:
	page._reset_wolf_private_flow()
	assert(page._record_bot_wolf_chat(0, "目标换到4号位。"))
	var wolf_snapshot: Dictionary = page._network_snapshot_for_participant("wolf_a_participant")
	assert((wolf_snapshot["wolfPrivateHistory"] as Array).size() == 1)
	var villager_snapshot: Dictionary = page._network_snapshot_for_participant("villager_c_participant")
	assert((villager_snapshot["wolfPrivateHistory"] as Array).is_empty())


func _player(id: String, name: String, role_key: String, owner: String, participant_id: String) -> Dictionary:
	var role_names := {
		"wolf": "狼人",
		"villager": "村民",
	}
	return {
		"id": id,
		"participant_id": participant_id,
		"name": name,
		"role": String(role_names.get(role_key, role_key)),
		"role_key": role_key,
		"avatar": "",
		"state": "等待",
		"motion": 0,
		"alive": true,
		"ready": true,
		"owner": owner,
	}
