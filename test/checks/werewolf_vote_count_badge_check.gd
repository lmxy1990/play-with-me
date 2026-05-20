extends SceneTree


func _initialize() -> void:
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

	room._players[0] = _player("p1", "一号", "self", "villager", "村民")
	room._players[1] = _player("p2", "二号", "human", "wolf", "狼人")
	room._players[2] = _player("p3", "三号", "human", "seer", "预言家")
	room._werewolf = room._engine.default_state()
	room._werewolf["phase"] = "vote"
	room._werewolf["sheriff_player_index"] = 0
	room._werewolf["votes"] = {"0": 1, "1": 2, "2": 1}
	room._refresh_all_seats()
	await process_frame

	if not _expect(_vote_badge_text(room, 0) == "0票", "vote phase shows zero count on occupied players"):
		return
	if not _expect(_vote_badge_text(room, 1) == "3票", "day vote count uses sheriff weight"):
		return
	if not _expect(_vote_badge_text(room, 2) == "1票", "day vote count shows received votes"):
		return

	room._werewolf["phase"] = "mvp_vote"
	room._werewolf["votes"] = {"0": 1}
	room._werewolf["post_game"] = {"mvp_votes": {"0": 2, "1": 2}}
	room._refresh_all_seats()
	await process_frame
	if not _expect(_vote_badge_text(room, 1) == "0票", "mvp vote ignores stale public vote counts"):
		return
	if not _expect(_vote_badge_text(room, 2) == "2票", "mvp vote uses post-game vote counts"):
		return

	room._werewolf["phase"] = "day_discussion"
	room._refresh_all_seats()
	await process_frame
	if not _expect(_vote_badge_text(room, 0) == "", "vote badge hides outside vote phases"):
		return

	room.queue_free()
	quit(0)


func _player(id: String, name: String, owner: String, role_key: String, role: String) -> Dictionary:
	return {
		"id": id,
		"name": name,
		"owner": owner,
		"participant_id": id,
		"role_key": role_key,
		"role": role,
		"avatar": "",
		"state": "",
		"motion": 0,
		"alive": true,
		"ready": true,
	}


func _vote_badge_text(room: Control, index: int) -> String:
	if index < 0 or index >= room._seat_cards.size():
		return ""
	var seat := room._seat_cards[index] as Control
	if seat == null:
		return ""
	var label := seat.find_child("VoteCountBadge", true, false) as Label
	if label == null:
		return ""
	return String(label.text)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("werewolf_vote_count_badge_check failed: %s" % message)
	quit(1)
	return false
