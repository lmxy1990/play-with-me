extends SceneTree

const BOT_AVATAR := "res://assets/images/werewolf/avatars/robot.png"


func _initialize() -> void:
	var state = load("res://scripts/core/app_state.gd").new()
	state.persistence_enabled = false
	state.load_or_create()
	state.create_room("狼人杀", 6, "", "basic_village", "标准村庄")
	state.bot_profiles = [
		{
			"id": "card_bot_alpha",
			"name": "Alpha Bot",
			"description": "卡片选择检查",
			"persona": "谨慎发言",
			"model": "qwen-plus",
			"voice": "系统默认",
			"enabled": true,
			"memory": {},
		},
		{
			"id": "card_bot_disabled",
			"name": "Disabled Bot",
			"model": "deepseek-chat",
			"voice": "系统默认",
			"enabled": false,
			"memory": {},
		},
	]

	var packed := load("res://scenes/werewolf_room.tscn") as PackedScene
	var room := packed.instantiate() as Control
	room.set_app_state(state)
	root.add_child(room)
	await process_frame
	room._open_add_bot_dialog(1)
	await process_frame

	var list := room.find_child("AddBotProfileList", true, false) as GridContainer
	assert(list != null)
	assert(list.get_child_count() == 1)
	var card := room.find_child("AddBotProfileCard", true, false) as Control
	assert(card != null)
	var hit := card.find_child("AddBotProfileHit", true, false) as Button
	assert(hit != null)

	hit.pressed.emit()
	await process_frame
	assert(String(room._players[1].get("owner", "")) == "human")
	assert(String(room._players[1].get("participant_id", "")) == "")
	assert(String(room._players[1].get("controller_participant_id", "")) == "host")
	assert(String(room._players[1].get("name", "")) == "Alpha Bot")
	assert(not room._players[1].has("bot_profile_id"))
	assert(not room._players[1].has("model"))
	assert(not room._players[1].has("voice"))
	# Local device keeps private AI config in the seat-private cache; snapshots and tasks strip it.
	var private_profile: Dictionary = room._local_private_bot_profile_for_seat(1)
	assert(String(private_profile.get("id", "")) == "card_bot_alpha")
	assert(String(private_profile.get("model", "")) == "qwen-plus")
	assert(String(room._players[1].get("role", "")) == "未知")
	assert(String(room._players[1].get("role_key", "")) == "")
	assert(String(room._players[1].get("avatar", "")) == BOT_AVATAR)
	assert(room._modal_layer.get_child_count() == 0)

	room.queue_free()
	quit(0)
