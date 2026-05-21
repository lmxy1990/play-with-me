extends SceneTree


func _initialize() -> void:
	var controller = load("res://scripts/player/werewolf/human/werewolf_human_player_state_controller.gd").new()
	var players := [
		{"name": "一号", "ready": false},
		{"name": "二号", "ready": true},
	]
	var ready: Dictionary = controller.ready_update(players, 0, "1号 一号")
	if not _expect(bool(ready.get("ok", false)), "ready update is accepted for seated player"):
		return
	if not _expect(bool(ready.get("ready", false)) and String(ready.get("state", "")) == "已准备", "ready update turns player ready"):
		return
	if not _expect(String(ready.get("message", "")) == "1号 一号 · 已准备", "ready message includes player title"):
		return
	var unready: Dictionary = controller.ready_update(players, 1, "2号 二号")
	if not _expect(not bool(unready.get("ready", true)) and String(unready.get("effect", "")) == "skip", "ready update can cancel ready"):
		return
	var invalid: Dictionary = controller.ready_update(players, -1, "")
	if not _expect(not bool(invalid.get("ok", true)), "invalid ready update is rejected"):
		return
	if not _expect(controller.normalized_name("  新名字  ") == "新名字", "name is trimmed"):
		return
	if not _expect(controller.normalized_name("   ") == "玩家", "blank name uses fallback"):
		return
	var tts: Dictionary = controller.tts_toggle_update(true, "1号 一号")
	if not _expect(not bool(tts.get("enabled", true)) and String(tts.get("message", "")) == "1号 一号 旁白已关闭", "tts toggle message is generated"):
		return
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("werewolf_human_player_state_controller_check failed: %s" % message)
	quit(1)
	return false
