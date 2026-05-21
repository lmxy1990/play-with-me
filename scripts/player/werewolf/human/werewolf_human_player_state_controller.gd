extends RefCounted


func ready_update(players: Array, index: int, player_title: String) -> Dictionary:
	if index < 0 or index >= players.size() or not (players[index] is Dictionary):
		return {"ok": false, "message": "请先点击空位落座", "effect": "skip"}
	var player: Dictionary = players[index]
	var ready := not bool(player.get("ready", false))
	return {
		"ok": true,
		"ready": ready,
		"state": "已准备" if ready else "等待",
		"message": "%s · %s" % [player_title, "已准备" if ready else "取消准备"],
		"effect": "vote" if ready else "skip",
	}


func normalized_name(text: String, fallback: String = "玩家") -> String:
	var next_name := text.strip_edges()
	return fallback if next_name == "" else next_name


func rename_message() -> String:
	return "名字已修改"


func tts_toggle_update(current_enabled: bool, player_title: String) -> Dictionary:
	var next_enabled := not current_enabled
	return {
		"ok": true,
		"enabled": next_enabled,
		"message": "%s 旁白%s" % [player_title, "已开启" if next_enabled else "已关闭"],
	}
