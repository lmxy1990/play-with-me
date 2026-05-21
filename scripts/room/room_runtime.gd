extends RefCounted
class_name RoomRuntime

const MIN_WEREWOLF_PLAYERS := 6
const MAX_WEREWOLF_PLAYERS := 12


func is_game_started(werewolf: Dictionary) -> bool:
	var phase := String(werewolf.get("phase", "lobby"))
	return bool(werewolf.get("started", false)) and not (phase in ["post_game_summary", "mvp_vote", "completed"])


func can_change_seat(werewolf: Dictionary) -> Dictionary:
	if is_game_started(werewolf):
		return _rejected("对局已开始，不能切换座位")
	return _accepted()


func can_add_bot(werewolf: Dictionary) -> Dictionary:
	if is_game_started(werewolf):
		return _rejected("对局已开始，不能添加机器人")
	return _accepted()


func can_rename(werewolf: Dictionary) -> Dictionary:
	if is_game_started(werewolf):
		return _rejected("对局已开始，不能修改名字")
	return _accepted()


func can_toggle_ready(werewolf: Dictionary, players: Array, local_player_index: int) -> Dictionary:
	if is_game_started(werewolf):
		return _rejected("对局已开始")
	if local_player_index < 0 or local_player_index >= players.size():
		return _rejected("请先点击空位落座")
	if String(players[local_player_index].get("owner", "")) == "":
		return _rejected("请先点击空位落座")
	return _accepted()


func editable_name(players: Array, index: int) -> bool:
	if index < 0 or index >= players.size():
		return false
	var owner := String(players[index].get("owner", ""))
	return owner == "self"


func empty_seat(players: Array, index: int) -> bool:
	if index < 0 or index >= players.size():
		return false
	return String(players[index].get("owner", "")) == ""


func occupied_indices(players: Array) -> Array:
	var indices := []
	for i in range(players.size()):
		if String(players[i].get("owner", "")) != "":
			indices.append(i)
	return indices


func human_count(players: Array) -> int:
	var count := 0
	for player in players:
		var owner := String(player.get("owner", ""))
		var participant_id := String(player.get("participant_id", "")).strip_edges()
		if owner == "self" or participant_id != "":
			count += 1
	return count


func bot_count(players: Array) -> int:
	var count := 0
	for player in players:
		var owner := String(player.get("owner", ""))
		var participant_id := String(player.get("participant_id", "")).strip_edges()
		var controller := String(player.get("controller_participant_id", player.get("controllerParticipantId", ""))).strip_edges()
		if owner != "" and participant_id == "" and controller != "":
			count += 1
	return count


func start_gate(players: Array, werewolf: Dictionary) -> Dictionary:
	if is_game_started(werewolf):
		return _rejected("对局已开始")
	var occupied := occupied_indices(players)
	if occupied.size() < MIN_WEREWOLF_PLAYERS:
		return _waiting("等待玩家准备：%d/%d" % [occupied.size(), max(MIN_WEREWOLF_PLAYERS, players.size())])
	if occupied.size() > MAX_WEREWOLF_PLAYERS:
		return _waiting("当前版本支持 6 到 12 人狼人杀")
	for item in occupied:
		var index := int(item)
		if not bool(players[index].get("ready", false)):
			return _waiting("等待所有入座玩家准备")
	return {
		"ok": true,
		"waiting": false,
		"message": "可以开局",
		"occupied_indices": occupied,
	}


func _accepted() -> Dictionary:
	return {
		"ok": true,
		"message": "",
	}


func _waiting(message: String) -> Dictionary:
	return {
		"ok": false,
		"waiting": true,
		"message": message,
	}


func _rejected(message: String) -> Dictionary:
	return {
		"ok": false,
		"waiting": false,
		"message": message,
	}
