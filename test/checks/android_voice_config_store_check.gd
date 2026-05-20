extends SceneTree

const StoreScript := preload("res://scripts/core/tts/adapters/android_voice_config_store.gd")


class FakeVoiceConfigPlugin:
	extends Node

	var voices := []
	var next_id := 1

	func voice_config_available() -> bool:
		return true

	func voice_config_list() -> String:
		return JSON.stringify(voices)

	func voice_config_save(config_json: String) -> String:
		var config: Dictionary = JSON.parse_string(config_json)
		var id := int(config.get("id", 0))
		if id <= 0:
			id = next_id
			next_id += 1
		var item := {
			"id": id,
			"name": String(config.get("name", "")),
			"engine": String(config.get("engine", "")),
			"gender": String(config.get("gender", "")),
			"voice": String(config.get("voice", "")),
			"speed": String(config.get("speed", "0.90")),
			"pitch": String(config.get("pitch", "1.00")),
			"volume": String(config.get("volume", "1.00")),
			"enabled": bool(config.get("enabled", true)),
			"active": bool(config.get("active", false)),
		}
		for i in range(voices.size()):
			if int((voices[i] as Dictionary).get("id", 0)) == id:
				voices[i] = item
				return JSON.stringify({"ok": true, "voice": item})
		voices.append(item)
		return JSON.stringify({"ok": true, "voice": item})

	func voice_config_delete(id: int) -> String:
		for i in range(voices.size() - 1, -1, -1):
			if int((voices[i] as Dictionary).get("id", 0)) == id:
				voices.remove_at(i)
		return JSON.stringify({"ok": true})


class TestVoiceConfigStore:
	extends StoreScript

	var plugin

	func _init(plugin_ref) -> void:
		plugin = plugin_ref

	func _plugin():
		return plugin


func _initialize() -> void:
	var plugin := FakeVoiceConfigPlugin.new()
	root.add_child(plugin)
	var store := TestVoiceConfigStore.new(plugin)
	assert(store.is_available())
	var saved := store.save_config({
		"name": "Kokoro 女声",
		"engine": "local_kokoro",
		"gender": "女声",
		"voice": "zf_001",
		"speed": "0.90",
		"pitch": "1.00",
		"volume": "0.80",
		"enabled": true,
		"active": true,
	})
	assert(bool(saved.get("ok", false)))
	assert(int(saved.get("id", 0)) == 1)
	assert(String(saved.get("engine", "")) == "local_kokoro")
	assert(String(saved.get("voice", "")) == "zf_001")
	assert(bool(saved.get("enabled", false)))
	assert(bool(saved.get("active", false)))
	var configs := store.list_configs()
	assert(configs.size() == 1)
	assert(String((configs[0] as Dictionary).get("name", "")) == "Kokoro 女声")
	assert(bool(store.delete_config(1).get("ok", false)))
	assert(store.list_configs().is_empty())
	quit()
