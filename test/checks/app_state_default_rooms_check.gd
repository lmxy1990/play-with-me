extends SceneTree

const AppStateScript := preload("res://scripts/core/app_state.gd")


func _initialize() -> void:
	var fresh = AppStateScript.new()
	fresh.persistence_enabled = false
	fresh.load_or_create()
	assert(fresh.rooms.is_empty())
	assert(String(fresh.active_room_id) == "")

	var reset = AppStateScript.new()
	reset.persistence_enabled = false
	reset._apply_json({
		"state_version": 2,
		"rooms": [
			{"id": "local_room_1", "name": "本地长桌", "state": "等待中", "type": "狼人杀", "players": "0/6", "lock": "公开", "address": "本机"},
			{"id": "room_real", "name": "用户房间", "state": "等待中", "type": "狼人杀", "players": "0/6", "lock": "公开", "address": "本机"},
		],
		"players": [],
		"active_room_id": "local_room_1",
		"werewolf": {},
		"history": [],
	})
	assert(reset.rooms.is_empty())
	assert(String(reset.active_room_id) == "")
	assert(String(reset.system_message) == "等待创建房间")

	var runtime = AppStateScript.new()
	runtime.persistence_enabled = false
	runtime._apply_defaults()
	runtime._apply_json({
		"state_version": AppStateScript.STATE_VERSION,
		"model_configs": [{"id": 1, "model": "qwen-plus", "endpoint": "http://model"}],
		"voice_configs": [{"id": "voice_a", "name": "Voice A"}],
		"bot_profiles": [{"id": "bot_a", "name": "Bot A", "enabled": true}],
		"local_nickname": "测试玩家",
		"rooms": [{"id": "old_room", "name": "旧房间"}],
		"players": [{"name": "旧玩家", "owner": "self"}],
		"active_room_id": "old_room",
		"bot_serial": 8,
		"phase_night": true,
		"system_message": "旧消息",
		"werewolf": {"phase": "vote", "started": true},
		"history": [{"speaker": "旧", "text": "旧记录"}],
	})
	assert(runtime.rooms.is_empty())
	assert(runtime.players.size() == 6)
	assert(String(runtime.active_room_id) == "")
	assert(int(runtime.bot_serial) == 1)
	assert(not bool(runtime.phase_night))
	assert(String(runtime.system_message) == "等待创建房间")
	assert(String(runtime.werewolf.get("phase", "")) == "lobby")
	assert(runtime.history.is_empty())
	assert(String(runtime.local_nickname) == "测试玩家")
	assert(runtime.model_configs.size() == 1)
	assert(runtime.voice_configs.size() == 1)
	assert(runtime.bot_profiles.size() == 1)

	var saved: Dictionary = runtime.to_json()
	assert(not saved.has("rooms"))
	assert(not saved.has("players"))
	assert(not saved.has("active_room_id"))
	assert(not saved.has("werewolf"))
	assert(not saved.has("history"))
	quit()
