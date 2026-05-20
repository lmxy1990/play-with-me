extends SceneTree

const AppStateScript := preload("res://scripts/core/app_state.gd")
const RoomScene := preload("res://scenes/werewolf_room.tscn")


func _initialize() -> void:
	var state = AppStateScript.new()
	state.persistence_enabled = false
	state.load_or_create()
	state.bot_profiles = [
		{
			"id": "shared_bot",
			"name": "共享机器人",
			"model": "qwen-plus",
			"voice": "系统默认",
			"enabled": true,
		},
	]

	state.create_room("狼人杀", 6, "", "basic_village", "标准村庄")
	var first_room_id := String(state.active_room_id)
	var first := RoomScene.instantiate()
	first.set_app_state(state)
	root.add_child(first)
	await process_frame
	var bot_seat := 1
	first._add_bot_at(bot_seat, state.bot_profiles[0] as Dictionary)
	await process_frame
	var first_room: Dictionary = first._active_room()
	if not ((first_room.get("active_bot_profile_ids", []) as Array).has("shared_bot")):
		_fail("first room did not publish active bot profile id")
		return
	first.queue_free()
	await process_frame

	state.create_room("狼人杀", 6, "", "basic_village", "标准村庄")
	var second := RoomScene.instantiate()
	second.set_app_state(state)
	root.add_child(second)
	await process_frame
	second._add_bot_at(bot_seat, state.bot_profiles[0] as Dictionary)
	await process_frame
	if String(second._players[bot_seat].get("owner", "")) != "":
		_fail("same bot profile was allowed in two rooms")
		return
	if not String(second._system_message).contains("正在房间"):
		_fail("occupied bot profile did not show occupied message")
		return

	for i in range(second._rooms.size() - 1, -1, -1):
		if second._rooms[i] is Dictionary and String((second._rooms[i] as Dictionary).get("id", "")) == first_room_id:
			second._rooms.remove_at(i)
	second._add_bot_at(bot_seat, state.bot_profiles[0] as Dictionary)
	await process_frame
	if String(second._players[bot_seat].get("owner", "")) != "human" or String(second._players[bot_seat].get("participant_id", "")) != "":
		_fail("bot profile was not released after first room disappeared")
		return
	second.queue_free()
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
