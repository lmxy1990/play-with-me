extends RefCounted
class_name WerewolfWinConditions

const RoleCatalogScript := preload("res://scripts/room/werewolf/werewolf_role_catalog.gd")

const ALL_WOLVES_DEAD := "all_wolves_dead"
const ALL_GOOD_DEAD := "all_good_dead"
const SLAUGHTER_SIDE := "slaughter_side"
const PIED_PIPER_ALL_CHARMED := "pied_piper_all_charmed"
const SOLO_ROLE_LAST_ALIVE := "solo_role_last_alive"
const LOVERS_LAST_ALIVE := "lovers_last_alive"

const WINNER_GOOD := "good"
const WINNER_WOLF := "wolf"
const WINNER_THIRD_PARTY := "third_party"
const WINNER_LOVERS := "lovers"

const DEFAULT_MAP_ID := "basic_village"

var _role_catalog = RoleCatalogScript.new()


func default_wolf_condition_key(player_count: int) -> String:
	return SLAUGHTER_SIDE if player_count >= 12 else ALL_GOOD_DEAD


func condition_text(condition_key: String) -> String:
	match condition_key:
		ALL_WOLVES_DEAD:
			return "狼人阵营全部出局，好人阵营胜利。"
		SLAUGHTER_SIDE:
			return "狼人阵营胜利：村民全部出局或神职全部出局。"
		PIED_PIPER_ALL_CHARMED:
			return "吹笛者胜利：所有存活玩家均被迷惑。"
		SOLO_ROLE_LAST_ALIVE:
			return "独立阵营胜利：指定独立角色成为最后存活阵营。"
		LOVERS_LAST_ALIVE:
			return "情侣胜利：场上只剩情侣存活。"
		_:
			return "狼人阵营胜利：所有好人全部出局。"


func condition_summary(condition_key: String) -> String:
	if condition_key == SLAUGHTER_SIDE:
		return "狼人全部出局则好人胜利；村民全部出局或神职全部出局则狼人胜利。"
	return "狼人全部出局则好人胜利；所有好人全部出局则狼人胜利。"


func check(state: Dictionary, players: Array) -> Dictionary:
	var counts := alive_role_counts(players)
	var third_party_win := check_third_party_conditions(state, players, counts)
	if not third_party_win.is_empty():
		return third_party_win
	var good_win := check_all_wolves_dead(counts)
	if not good_win.is_empty():
		return good_win
	var wolf_condition := String(state.get("wolf_win_condition", "")).strip_edges()
	if wolf_condition == "":
		wolf_condition = default_wolf_condition_key(int(counts.get("occupied", 0)))
	if wolf_condition == SLAUGHTER_SIDE:
		return check_slaughter_side(counts)
	return check_all_good_dead(counts)


func check_all_wolves_dead(counts: Dictionary) -> Dictionary:
	if int(counts.get("wolves", 0)) <= 0:
		return _win(WINNER_GOOD, "好人胜利。", ALL_WOLVES_DEAD)
	return {}


func check_all_good_dead(counts: Dictionary) -> Dictionary:
	if int(counts.get("good", 0)) <= 0:
		return _win(WINNER_WOLF, "狼人胜利。", ALL_GOOD_DEAD)
	return {}


func check_slaughter_side(counts: Dictionary) -> Dictionary:
	if int(counts.get("villagers", 0)) <= 0 or int(counts.get("gods", 0)) <= 0:
		return _win(WINNER_WOLF, "狼人胜利。", SLAUGHTER_SIDE)
	return {}


func check_third_party_conditions(state: Dictionary, players: Array, counts: Dictionary = {}) -> Dictionary:
	var enabled := _condition_keys(state)
	if enabled.has(PIED_PIPER_ALL_CHARMED):
		var pied_piper := _check_pied_piper_all_charmed(state, players)
		if not pied_piper.is_empty():
			return pied_piper
	if enabled.has(LOVERS_LAST_ALIVE):
		var lovers := _check_lovers_last_alive(state, players)
		if not lovers.is_empty():
			return lovers
	if enabled.has(SOLO_ROLE_LAST_ALIVE):
		var solo := _check_solo_role_last_alive(state, players, counts)
		if not solo.is_empty():
			return solo
	return {}


func alive_role_counts(players: Array) -> Dictionary:
	var role_counts := {}
	var alive_roles := []
	var occupied := 0
	var alive := 0
	var wolves := 0
	var good := 0
	var villagers := 0
	var gods := 0
	var third_party := 0
	for i in range(players.size()):
		if not (players[i] is Dictionary):
			continue
		var player: Dictionary = players[i]
		if String(player.get("owner", "")) == "":
			continue
		occupied += 1
		if not bool(player.get("alive", true)):
			continue
		alive += 1
		var role_key := String(player.get("role_key", RoleCatalogScript.ROLE_VILLAGER))
		role_counts[role_key] = int(role_counts.get(role_key, 0)) + 1
		alive_roles.append("%d:%s" % [i, role_key])
		if _role_catalog.counts_as_wolf_for_win(role_key):
			wolves += 1
			continue
		if _role_catalog.counts_as_good_for_win(role_key):
			good += 1
			match _role_catalog.slaughter_group(role_key):
				RoleCatalogScript.SLAUGHTER_GROUP_GOD:
					gods += 1
				_:
					villagers += 1
			continue
		third_party += 1
	return {
		"occupied": occupied,
		"alive": alive,
		"wolves": wolves,
		"good": good,
		"villagers": villagers,
		"gods": gods,
		"third_party": third_party,
		"role_counts": role_counts,
		"alive_roles": alive_roles,
	}


func _check_pied_piper_all_charmed(state: Dictionary, players: Array) -> Dictionary:
	var charmed := _index_set(_as_array(state.get("pied_piper_charmed_indices", [])))
	var has_alive_piper := false
	for i in range(players.size()):
		if not _is_alive_occupied(players, i):
			continue
		var role_key := String((players[i] as Dictionary).get("role_key", ""))
		if role_key == RoleCatalogScript.ROLE_PIED_PIPER:
			has_alive_piper = true
			continue
		if not charmed.has(i):
			return {}
	if has_alive_piper:
		return _win(WINNER_THIRD_PARTY, "吹笛者胜利。", PIED_PIPER_ALL_CHARMED)
	return {}


func _check_lovers_last_alive(state: Dictionary, players: Array) -> Dictionary:
	var lover_indices := _index_set(_as_array(state.get("lover_indices", [])))
	if lover_indices.size() < 2:
		return {}
	var alive_indices := []
	for i in range(players.size()):
		if _is_alive_occupied(players, i):
			alive_indices.append(i)
	if alive_indices.is_empty():
		return {}
	for index in alive_indices:
		if not lover_indices.has(int(index)):
			return {}
	return _win(WINNER_LOVERS, "情侣胜利。", LOVERS_LAST_ALIVE)


func _check_solo_role_last_alive(state: Dictionary, players: Array, counts: Dictionary = {}) -> Dictionary:
	var solo_roles := _as_array(state.get("solo_win_roles", []))
	if solo_roles.is_empty():
		solo_roles = [RoleCatalogScript.ROLE_LONE_WOLF, RoleCatalogScript.ROLE_CURSED_FOX]
	var alive := int(counts.get("alive", -1))
	if alive < 0:
		alive = int(alive_role_counts(players).get("alive", 0))
	if alive <= 0:
		return {}
	for i in range(players.size()):
		if not _is_alive_occupied(players, i):
			continue
		var role_key := String((players[i] as Dictionary).get("role_key", ""))
		if solo_roles.has(role_key) and alive == 1:
			return _win(WINNER_THIRD_PARTY, "%s胜利。" % _role_catalog.role_label(role_key), SOLO_ROLE_LAST_ALIVE)
	return {}


func _condition_keys(state: Dictionary) -> Array:
	var result := []
	var configured := _as_array(state.get("win_conditions", state.get("victory_conditions", [])))
	for item in configured:
		var key := String(item).strip_edges()
		if key != "" and not result.has(key):
			result.append(key)
	return result


func _win(winner: String, message: String, condition_key: String) -> Dictionary:
	return {
		"winner": winner,
		"message": message,
		"condition": condition_key,
	}


func _is_alive_occupied(players: Array, index: int) -> bool:
	if index < 0 or index >= players.size() or not (players[index] is Dictionary):
		return false
	var player: Dictionary = players[index]
	return String(player.get("owner", "")) != "" and bool(player.get("alive", true))


func _index_set(values: Array) -> Dictionary:
	var result := {}
	for value in values:
		result[int(value)] = true
	return result


func _as_array(value) -> Array:
	return value if value is Array else []
