extends SceneTree


func _initialize() -> void:
	var repository = load("res://scripts/core/bot/bot_profile_repository.gd").new()
	var profiles: Array = repository.load_or_seed([])
	_expect(profiles.is_empty(), "seed should be empty")

	var saved: Dictionary = repository.save_profile(-1, {
		"name": "推理机器人",
		"description": "负责稳定发言",
		"persona": "谨慎，先收集信息再判断。",
		"model": "qwen:test",
		"voice": "系统默认",
		"enabled": true,
		"memory": {
			"profile": "偏好短句表达",
			"working": "当前局关注 3 号",
			"long_term": "倾向保守投票",
			"notes": "测试备注",
		},
	})
	_expect(bool(saved.get("ok", false)), "save should succeed")
	profiles = saved.get("profiles", []) as Array
	_expect(profiles.size() == 1, "save should create one profile")
	var profile: Dictionary = profiles[0]
	_expect(String(profile.get("name", "")) == "推理机器人", "name should be saved")
	_expect(String(profile.get("model", "")) == "qwen:test", "model should be saved")
	_expect(String(profile.get("voice", "")) == "系统默认", "voice should be saved")
	_expect(String(profile.get("id", "")).begins_with("bot_"), "id should be generated")
	_expect(not profile.has("memory_namespace"), "memory should not expose a separate namespace")
	_expect(repository.summary_for_bot(String(profile.get("name", ""))).find("谨慎") >= 0, "summary should include persona")
	_expect(repository.summary_for_bot(String(profile.get("id", ""))).find("短句") >= 0, "summary should include profile memory")

	var updated: Dictionary = repository.save_profile(0, {
		"name": "推理机器人2",
		"description": "",
		"persona": "更积极发言。",
		"model": "qwen:test",
		"voice": "系统默认",
		"enabled": false,
	})
	_expect(bool(updated.get("ok", false)), "update should succeed")
	profiles = updated.get("profiles", []) as Array
	_expect(profiles.size() == 1, "update should keep one profile")
	_expect(String((profiles[0] as Dictionary).get("name", "")) == "推理机器人2", "updated name should be saved")
	_expect(not bool((profiles[0] as Dictionary).get("enabled", true)), "enabled should be saved")
	_expect(repository.enabled_profiles().is_empty(), "disabled profile should not be enabled")

	var deleted: Dictionary = repository.delete_profile(0)
	_expect(bool(deleted.get("ok", false)), "delete should succeed")
	_expect((deleted.get("profiles", []) as Array).is_empty(), "delete should remove profile")
	quit(0)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
