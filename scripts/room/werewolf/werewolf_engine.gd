extends RefCounted
class_name WerewolfEngine

const WerewolfMapCatalogScript := preload("res://scripts/room/werewolf/werewolf_map_catalog.gd")
const WerewolfRoleCatalogScript := preload("res://scripts/room/werewolf/werewolf_role_catalog.gd")
const WerewolfWinConditionsScript := preload("res://scripts/room/werewolf/werewolf_win_conditions.gd")

const ACTION_INSPECT := "res://assets/images/werewolf/actions/inspect.png"
const ACTION_VOTE := "res://assets/images/werewolf/actions/vote.png"
const ACTION_KILL := "res://assets/images/werewolf/actions/kill.png"
const ACTION_GUARD := "res://assets/images/werewolf/actions/guard.png"
const ACTION_POTION := "res://assets/images/werewolf/actions/potion.png"
const ACTION_SPEECH := "res://assets/images/werewolf/actions/speech.png"
const ACTION_SKIP := "res://assets/images/werewolf/actions/skip.png"

const DEFAULT_MAP_ID := "basic_village"

enum SeatMotion { IDLE, THINKING, SPEAKING, DEAD }

var _map_catalog = WerewolfMapCatalogScript.new()
var _role_catalog = WerewolfRoleCatalogScript.new()
var _win_conditions = WerewolfWinConditionsScript.new()


func default_state() -> Dictionary:
	return {
		"phase": "lobby",
		"day": 0,
		"started": false,
		"current_action": {},
		"speech_index": -1,
		"night": {},
		"votes": {},
		"spoken_indices": [],
		"last_words_pending": [],
		"last_words_used": [],
		"last_words_return_phase": "",
		"hunter_return_phase": "",
		"pending_night_deaths": [],
		"pending_vote_exile_index": -1,
		"sheriff_badge_return_phase": "",
		"sheriff_badge_dead_index": -1,
		"sheriff_badge_candidates": [],
		"sheriff_badge_check_hunter": false,
		"last_guarded_index": -1,
		"seer_check_history": {},
		"witch_antidote": true,
		"witch_poison": true,
		"sheriff_player_index": -1,
		"day_speech_order": [],
		"day_speech_order_start_index": -1,
		"day_speech_order_direction": "",
		"day_speech_order_day": 0,
		"day_speech_order_decider_index": -1,
		"map_id": DEFAULT_MAP_ID,
		"map_name": "标准村庄",
		"map_scene": "村庄长桌",
		"has_sheriff": false,
		"winner": "",
		"wolf_win_condition": "all_good_dead",
		"post_game": {
			"stage": "",
			"summary_pending": [],
			"summaries": {},
			"mvp_votes": {},
			"mvp_index": -1,
		},
	}


func start_game(room_id: String, players: Array, occupied_indices: Array, local_index: int = -1, map_id: String = DEFAULT_MAP_ID) -> Dictionary:
	var count: int = occupied_indices.size()
	var map_data: Dictionary = _map_catalog.get_map(map_id)
	var roles: Array = _map_catalog.get_role_config(map_id, count)
	if map_data.is_empty():
		return _error("未知狼人杀地图：%s" % map_id)
	if roles.is_empty():
		return _error("当前狼人杀地图不支持 %d 人" % count)
	roles.shuffle()

	var next_players: Array = _duplicate_players(players)
	for order in range(occupied_indices.size()):
		var seat_index: int = int(occupied_indices[order])
		if seat_index < 0 or seat_index >= next_players.size():
			continue
		var role_key: String = String(roles[order])
		var player: Dictionary = next_players[seat_index]
		var base_avatar := String(player.get("base_avatar", player.get("avatar", ""))).strip_edges()
		player["id"] = String(player.get("id", "seat_%d" % [seat_index + 1]))
		player["role_key"] = role_key
		player["role"] = _map_catalog.role_label(role_key)
		player["role_title"] = _map_catalog.role_title(role_key)
		player["role_avatar"] = _map_catalog.role_avatar(role_key)
		player["base_avatar"] = base_avatar
		player["avatar"] = base_avatar
		player["alive"] = true
		player["ready"] = true
		player["state"] = "等待"
		player["motion"] = SeatMotion.IDLE
		player["death_reason"] = ""
		player["can_hunter_shoot"] = false
		player["has_hunter_shot"] = false
		player["idiot_revealed"] = false
		next_players[seat_index] = player

	var state: Dictionary = default_state()
	state["room_id"] = room_id
	state["day"] = 1
	state["started"] = true
	state["map_id"] = map_id
	state["map_name"] = String(map_data.get("name", "标准村庄"))
	state["map_scene"] = String(map_data.get("scene", "村庄长桌"))
	state["map_rule_text"] = _map_catalog.rule_text(map_id, count)
	state["wolf_win_condition"] = _map_catalog.wolf_win_condition_key(map_id, count)
	state["has_sheriff"] = bool(map_data.get("has_sheriff", false))
	if bool(state.get("has_sheriff", false)):
		state["phase"] = "sheriff_speech"
		state["spoken_indices"] = []
	else:
		state["phase"] = "wolf_chat"
		state["night"] = _new_night(1)
		state["spoken_indices"] = []

	var history: Array = [
		_history("主持人", "游戏开始，身份已发放。"),
		_history("主持人", "本局狼人杀开始，共%d名游戏参与者。本局地图：%s。" % [count, String(state.get("map_name", ""))]),
		_history("主持人", _participant_text(next_players, occupied_indices)),
	]
	if bool(state.get("has_sheriff", false)):
		history.append(_history("主持人", "警长竞选发言开始，请所有存活玩家依次发表竞选或退水意见。"))
	else:
		history.append(_history("主持人", "第1夜开始。"))

	var transition: Dictionary = _advance_auto(state, next_players)
	state = transition["werewolf"]
	next_players = transition["players"]
	history.append_array(transition["history"])
	_prepare_prompt(state, next_players, local_index)
	var message: String = _prompt_message(state, next_players)
	_append_prompt_history(history, state, next_players)
	return {
		"ok": true,
		"players": next_players,
		"werewolf": state,
		"history": history,
		"message": message,
		"effect": "phase",
		"death_indices": transition["death_indices"],
	}


func apply_target(state: Dictionary, players: Array, target_index: int, local_index: int = -1, action_choice: String = "") -> Dictionary:
	var next_state: Dictionary = state.duplicate(true)
	var next_players: Array = _duplicate_players(players)
	var action: Dictionary = _as_dict(next_state.get("current_action", {}))
	if action.is_empty():
		return _error("当前没有需要选择目标的行动")

	var actor_index: int = int(action.get("actor_index", -1))
	var action_key: String = String(action.get("key", ""))
	var badge_choice := ""
	if action_key == "sheriff_badge_action":
		badge_choice = _sheriff_badge_action_from_choice(action_choice)
	if not (action_key == "sheriff_badge_action" and badge_choice == "destroy"):
		var validation: Dictionary = _validate_target(next_state, next_players, actor_index, target_index, action_key)
		if not bool(validation.get("ok", false)):
			return validation

	var history: Array = []
	var death_indices: Array = []
	var message := ""
	var effect: String = String(action.get("effect", "action"))
	match action_key:
		"wolf_kill":
			effect = "vote"
			history.append(_actor_history(next_players, actor_index, "投票袭击 %s。" % _player_title(next_players, target_index), "wolf", target_index, action_key))
			_record_vote(next_state, actor_index, target_index)
			if _all_alive_wolves_voted(next_state, next_players):
				var wolf_vote_resolved: Dictionary = _resolve_wolf_target_vote(next_state, next_players)
				next_state = wolf_vote_resolved["werewolf"]
				history.append_array(wolf_vote_resolved["history"])
				message = String(wolf_vote_resolved.get("message", "狼队投票完成"))
			else:
				message = "狼队目标票已记录"
		"guard_protect":
			var guard_night: Dictionary = _as_dict(next_state.get("night", _new_night(int(next_state.get("day", 1)))))
			guard_night["guarded_index"] = target_index
			next_state["night"] = guard_night
			next_state["last_guarded_index"] = target_index
			history.append(_actor_history(next_players, actor_index, "我守护 %s。" % _player_title(next_players, target_index), "private", target_index, action_key))
			next_state["phase"] = "seer_action"
			message = "守卫行动完成"
		"seer_check":
			var camp: String = _role_catalog.seer_result_label(String(next_players[target_index].get("role_key", "")))
			var check_history: Dictionary = _as_dict(next_state.get("seer_check_history", {}))
			var actor_key: String = str(actor_index)
			var actor_history: Dictionary = _as_dict(check_history.get(actor_key, {}))
			actor_history[str(target_index)] = camp
			check_history[actor_key] = actor_history
			next_state["seer_check_history"] = check_history
			history.append(_actor_history(next_players, actor_index, "我查验 %s。" % _player_title(next_players, target_index), "private", target_index, action_key))
			history.append(_moderator_private_history(next_players, actor_index, "查验结果：%s 是%s。" % [_player_title(next_players, target_index), camp], target_index, action_key))
			next_state["phase"] = "witch_action"
			message = "查验完成"
		"witch_act":
			var witch_result: Dictionary = _apply_witch_action(next_state, next_players, actor_index, target_index)
			if not bool(witch_result.get("ok", false)):
				return witch_result
			history.append_array(witch_result["history"])
			var resolved: Dictionary = _resolve_night(next_state, next_players)
			next_state = resolved["werewolf"]
			next_players = resolved["players"]
			death_indices.append_array(resolved["death_indices"])
			history.append_array(resolved["history"])
			message = String(resolved.get("message", "天亮了"))
			effect = "potion" if death_indices.is_empty() else "death"
		"sheriff_vote":
			history.append(_actor_history(next_players, actor_index, "投 %s 为警长。" % _player_title(next_players, target_index), "public", target_index, action_key))
			_record_vote(next_state, actor_index, target_index)
			if _all_alive_voted(next_state, next_players):
				var sheriff_resolved: Dictionary = _resolve_sheriff_vote(next_state, next_players)
				next_state = sheriff_resolved["werewolf"]
				history.append_array(sheriff_resolved["history"])
				message = String(sheriff_resolved.get("message", "警长投票完成"))
			else:
				message = "警长投票已记录"
		"sheriff_speech_order":
			var direction := _speech_order_direction_from_action_choice(action_choice)
			if direction == "":
				return _error("请选择顺时针或逆时针发言")
			var speech_order := _build_day_speech_order(next_players, target_index, direction)
			if speech_order.is_empty():
				return _error("发言顺序目标无效")
			_set_day_speech_order(next_state, target_index, direction, speech_order, actor_index)
			next_state["phase"] = "day_discussion"
			next_state["spoken_indices"] = []
			history.append(_actor_history(
				next_players,
				actor_index,
				"指定从 %s 开始%s发言。发言顺序：%s。" % [
					_player_title(next_players, target_index),
					_speech_order_direction_label(direction),
					_speech_order_titles(next_players, speech_order),
				],
				"public",
				target_index,
				action_key
			))
			message = "警长已指定发言顺序"
			effect = "speech"
		"sheriff_badge_action":
			if badge_choice == "":
				return _error("请选择飞警徽或撕警徽")
			if badge_choice == "pass":
				next_state["sheriff_player_index"] = target_index
				history.append(_actor_history(
					next_players,
					actor_index,
					"将警徽移交给 %s。" % _player_title(next_players, target_index),
					"public",
					target_index,
					"sheriff_badge_pass"
				))
				message = "警徽已移交"
				effect = "vote"
			else:
				next_state["sheriff_player_index"] = -1
				history.append(_actor_history(
					next_players,
					actor_index,
					"撕毁警徽，本局不再有警长。",
					"public",
					-1,
					"sheriff_badge_destroy"
				))
				message = "警徽已撕毁"
				effect = "skip"
			var badge_continued: Dictionary = _continue_after_sheriff_badge(next_state, next_players)
			next_state = badge_continued["werewolf"]
			next_players = badge_continued["players"]
			death_indices.append_array(badge_continued["death_indices"])
			history.append_array(badge_continued["history"])
		"vote":
			history.append(_actor_history(next_players, actor_index, "投票给 %s。" % _player_title(next_players, target_index), "public", target_index, action_key))
			_record_vote(next_state, actor_index, target_index)
			if _all_alive_voted(next_state, next_players):
				var vote_resolved: Dictionary = _resolve_vote(next_state, next_players)
				next_state = vote_resolved["werewolf"]
				next_players = vote_resolved["players"]
				death_indices.append_array(vote_resolved["death_indices"])
				history.append_array(vote_resolved["history"])
				message = String(vote_resolved.get("message", "投票完成"))
				effect = "death" if not death_indices.is_empty() else "vote"
			else:
				message = "投票已记录"
		"hunter_shoot":
			_mark_hunter_spent(next_players, actor_index)
			_kill_player(next_players, target_index, "猎枪", "hunter")
			death_indices.append(target_index)
			history.append(_actor_history(next_players, actor_index, "开枪带走 %s。" % _player_title(next_players, target_index), "public", target_index, action_key))
			var after_hunter: Dictionary = _after_hunter_action(next_state, next_players)
			next_state = after_hunter["werewolf"]
			next_players = after_hunter["players"]
			death_indices.append_array(after_hunter["death_indices"])
			history.append_array(after_hunter["history"])
			message = String(after_hunter.get("message", "猎人行动完成"))
			effect = "kill"
		"mvp_vote":
			var mvp_post: Dictionary = _as_dict(next_state.get("post_game", {}))
			var mvp_votes: Dictionary = _as_dict(mvp_post.get("mvp_votes", {}))
			mvp_votes[str(actor_index)] = target_index
			mvp_post["mvp_votes"] = mvp_votes
			next_state["post_game"] = mvp_post
			history.append(_actor_history(next_players, actor_index, "投给 %s 作为本局 MVP。" % _player_title(next_players, target_index), "public", target_index, action_key))
			if _all_occupied_voted(next_state, next_players):
				var mvp_index: int = _top_voted_index(mvp_votes, next_players, false)
				mvp_post["stage"] = "completed"
				mvp_post["mvp_index"] = mvp_index
				next_state["post_game"] = mvp_post
				next_state["phase"] = "completed"
				next_state["current_action"] = {}
				history.append(_history("主持人", "本局 MVP：%s。" % _player_title(next_players, mvp_index)))
				message = "复盘完成"
			else:
				message = "MVP 投票已记录"
		_:
			return _error("未知行动")

	var transition: Dictionary = _advance_auto(next_state, next_players)
	next_state = transition["werewolf"]
	next_players = transition["players"]
	death_indices.append_array(transition["death_indices"])
	history.append_array(transition["history"])
	_prepare_prompt(next_state, next_players, local_index)
	if message == "":
		message = _prompt_message(next_state, next_players)
	var prompt: String = _prompt_message(next_state, next_players)
	_append_prompt_history(history, next_state, next_players)

	return {
		"ok": true,
		"players": next_players,
		"werewolf": next_state,
		"history": history,
		"message": message if message != "" else prompt,
		"effect": effect,
		"target_index": target_index,
		"death_indices": _unique_indices(death_indices),
		"action": action,
	}


func submit_speech(state: Dictionary, players: Array, text: String, local_index: int = -1) -> Dictionary:
	var next_state: Dictionary = state.duplicate(true)
	var next_players: Array = _duplicate_players(players)
	var phase: String = String(next_state.get("phase", "lobby"))
	var speaker_index: int = int(next_state.get("speech_index", -1))
	if speaker_index < 0 or speaker_index >= next_players.size() or String(next_players[speaker_index].get("owner", "")) == "":
		return _error("发言玩家不存在")
	if not (phase in ["last_words", "post_game_summary"]) and not bool(next_players[speaker_index].get("alive", true)):
		return _error("死亡玩家不能在当前阶段发言")

	var content: String = text.strip_edges()
	if content == "":
		content = _empty_speech_text(phase)
	var history: Array = [_history(_player_title(next_players, speaker_index), content)]
	var message := ""

	match phase:
		"sheriff_speech":
			_mark_spoken(next_state, speaker_index)
			_set_player_waiting(next_players, speaker_index, "等待警长投票")
			if _all_alive_spoken(next_state, next_players):
				next_state["phase"] = "sheriff_vote"
				next_state["votes"] = {}
				next_state["spoken_indices"] = []
				history.append(_history("主持人", "警长竞选发言结束，开始投票选出本局警长。"))
				message = "开始警长投票"
			else:
				message = "警长发言已记录"
		"day_discussion":
			_mark_spoken(next_state, speaker_index)
			_set_player_waiting(next_players, speaker_index, "等待投票")
			if _all_alive_spoken(next_state, next_players):
				next_state["phase"] = "vote"
				next_state["votes"] = {}
				next_state["spoken_indices"] = []
				history.append(_history("主持人", "开始投票。"))
				message = "开始投票"
			else:
				message = "发言已记录"
		"wolf_chat":
			history = [_actor_history(next_players, speaker_index, content, "wolf", -1, "wolf_chat")]
			_mark_spoken(next_state, speaker_index)
			_set_player_waiting(next_players, speaker_index, "等待狼队行动")
			if _all_alive_wolves_spoken(next_state, next_players):
				next_state["phase"] = "wolf_action"
				next_state["spoken_indices"] = []
				next_state["votes"] = {}
				message = "狼队夜聊结束，开始投票决定袭击目标"
			else:
				message = "狼队夜聊已记录"
		"last_words":
			var pending: Array = _as_array(next_state.get("last_words_pending", []))
			if pending.is_empty() or int(pending[0]) != speaker_index:
				return _error("请按死亡顺序发表遗言")
			pending.pop_front()
			next_state["last_words_pending"] = pending
			var used: Array = _as_array(next_state.get("last_words_used", []))
			if not used.has(speaker_index):
				used.append(speaker_index)
			next_state["last_words_used"] = used
			if pending.is_empty():
				var continued: Dictionary = _continue_after_last_words(next_state, next_players)
				next_state = continued["werewolf"]
				next_players = continued["players"]
				history.append_array(continued["history"])
				message = String(continued.get("message", "遗言结束"))
			else:
				message = "遗言已记录"
		"post_game_summary":
			var post: Dictionary = _as_dict(next_state.get("post_game", {}))
			var summaries: Dictionary = _as_dict(post.get("summaries", {}))
			summaries[str(speaker_index)] = content
			post["summaries"] = summaries
			var summary_pending: Array = _as_array(post.get("summary_pending", []))
			if not summary_pending.is_empty() and int(summary_pending[0]) == speaker_index:
				summary_pending.pop_front()
			else:
				summary_pending.erase(speaker_index)
			post["summary_pending"] = summary_pending
			if summary_pending.is_empty():
				post["stage"] = "mvp_vote"
				post["mvp_votes"] = {}
				next_state["phase"] = "mvp_vote"
				history.append(_history("主持人", "赛后总结结束，开始评选 MVP。"))
				message = "开始 MVP 投票"
			else:
				message = "总结已记录"
			next_state["post_game"] = post
		_:
			return _error("当前不是发言阶段")

	var transition: Dictionary = _advance_auto(next_state, next_players)
	next_state = transition["werewolf"]
	next_players = transition["players"]
	history.append_array(transition["history"])
	_prepare_prompt(next_state, next_players, local_index)
	var prompt: String = _prompt_message(next_state, next_players)
	if message == "":
		message = prompt
	_append_prompt_history(history, next_state, next_players)
	return {
		"ok": true,
		"players": next_players,
		"werewolf": next_state,
		"history": history,
		"message": message,
		"effect": "speech",
		"death_indices": transition["death_indices"],
	}


func skip_current_action(state: Dictionary, players: Array, local_index: int = -1) -> Dictionary:
	var next_state: Dictionary = state.duplicate(true)
	var next_players: Array = _duplicate_players(players)
	var action: Dictionary = _as_dict(next_state.get("current_action", {}))
	if action.is_empty():
		return _error("当前没有可跳过的行动")
	var actor_index: int = int(action.get("actor_index", -1))
	var action_key: String = String(action.get("key", ""))
	if action_key == "witch_act" and String(next_state.get("phase", "")) != "witch_action":
		return _error("女巫只能在夜晚行动")
	if not _can_skip_action(action_key):
		return _error("当前行动不能跳过")
	var history: Array = []
	var death_indices: Array = []
	match action_key:
		"witch_act":
			history.append(_actor_history(next_players, actor_index, "我今晚不用药。", "private", -1, action_key))
			var resolved: Dictionary = _resolve_night(next_state, next_players)
			next_state = resolved["werewolf"]
			next_players = resolved["players"]
			death_indices.append_array(resolved["death_indices"])
			history.append_array(resolved["history"])
		"hunter_shoot":
			_mark_hunter_spent(next_players, actor_index)
			history.append(_actor_history(next_players, actor_index, "不使用猎枪。", "public", -1, action_key))
			var after_hunter: Dictionary = _after_hunter_action(next_state, next_players)
			next_state = after_hunter["werewolf"]
			next_players = after_hunter["players"]
			death_indices.append_array(after_hunter["death_indices"])
			history.append_array(after_hunter["history"])
		"sheriff_badge_action":
			next_state["sheriff_player_index"] = -1
			history.append(_actor_history(next_players, actor_index, "撕毁警徽，本局不再有警长。", "public", -1, "sheriff_badge_destroy"))
			var badge_continued: Dictionary = _continue_after_sheriff_badge(next_state, next_players)
			next_state = badge_continued["werewolf"]
			next_players = badge_continued["players"]
			death_indices.append_array(badge_continued["death_indices"])
			history.append_array(badge_continued["history"])
		_:
			return _error("当前行动不能跳过")
	var transition: Dictionary = _advance_auto(next_state, next_players)
	next_state = transition["werewolf"]
	next_players = transition["players"]
	death_indices.append_array(transition["death_indices"])
	history.append_array(transition["history"])
	_prepare_prompt(next_state, next_players, local_index)
	_append_prompt_history(history, next_state, next_players)
	return {
		"ok": true,
		"players": next_players,
		"werewolf": next_state,
		"history": history,
		"message": _prompt_message(next_state, next_players),
		"effect": "skip",
		"death_indices": _unique_indices(death_indices),
	}


func phase_label(state: Dictionary) -> String:
	match String(state.get("phase", "lobby")):
		"sheriff_speech":
			return "警长竞选发言"
		"sheriff_vote":
			return "警长投票"
		"sheriff_speech_order":
			return "警长决定发言顺序"
		"sheriff_badge_action":
			return "警徽处理"
		"wolf_chat":
			return "狼队夜聊"
		"wolf_action":
			return "狼人行动"
		"guard_action":
			return "守卫行动"
		"seer_action":
			return "预言家行动"
		"witch_action":
			return "女巫行动"
		"last_words":
			return "遗言"
		"day_discussion":
			return "白天发言"
		"vote":
			return "放逐投票"
		"hunter_action":
			return "猎人行动"
		"game_over":
			return "游戏结束"
		"replay_round":
			return "复盘回合"
		"post_game_summary":
			return "赛后总结"
		"mvp_vote":
			return "MVP 投票"
		"completed":
			return "已完成"
		_:
			return "等待开局"


func is_night_phase(state: Dictionary) -> bool:
	return String(state.get("phase", "lobby")) in ["wolf_chat", "wolf_action", "guard_action", "seer_action", "witch_action"]


func suggested_target_for_current_action(state: Dictionary, players: Array) -> int:
	var action: Dictionary = _as_dict(state.get("current_action", {}))
	if action.is_empty():
		return -1
	var actor_index: int = int(action.get("actor_index", -1))
	var action_key: String = String(action.get("key", ""))
	match action_key:
		"wolf_kill":
			return _first_legal_target(state, players, actor_index, action_key)
		"guard_protect":
			return _first_legal_target(state, players, actor_index, action_key)
		"seer_check":
			return _first_legal_target(state, players, actor_index, action_key)
		"witch_act":
			var night: Dictionary = _as_dict(state.get("night", {}))
			var wolf_target: int = int(night.get("wolf_target_index", -1))
			if wolf_target >= 0 and bool(state.get("witch_antidote", true)) and _is_alive_occupied(players, wolf_target):
				return wolf_target
			return _first_legal_target(state, players, actor_index, action_key)
		"sheriff_vote", "sheriff_speech_order", "sheriff_badge_action", "vote", "hunter_shoot", "mvp_vote":
			return _first_legal_target(state, players, actor_index, action_key)
		_:
			return -1


func get_map_list() -> Array:
	return _map_catalog.get_map_list()


func get_supported_player_counts(map_id: String) -> Array:
	return _map_catalog.get_supported_player_counts(map_id)


func get_scene_slots(map_id: String, player_count: int) -> Dictionary:
	return _map_catalog.get_scene_slots(map_id, player_count)


func get_role_config(map_id: String, player_count: int) -> Array:
	return _map_catalog.get_role_config(map_id, player_count)


func _prepare_prompt(state: Dictionary, players: Array, local_index: int) -> void:
	_clear_prompts(state, players)
	var phase: String = String(state.get("phase", "lobby"))
	if phase == "lobby":
		return
	match phase:
		"sheriff_speech":
			var sheriff_speaker: int = _next_unspoken_alive_actor(state, players)
			state["speech_index"] = sheriff_speaker
			_mark_speaking(players, sheriff_speaker, "竞选发言")
		"sheriff_vote":
			var sheriff_voter: int = _next_unvoted_alive_actor(state, players)
			if sheriff_voter >= 0:
				_set_action(state, players, sheriff_voter, "sheriff_vote", "警长", ACTION_VOTE, "vote")
		"sheriff_speech_order":
			var sheriff: int = int(state.get("sheriff_player_index", -1))
			if _is_alive_occupied(players, sheriff):
				_set_action(state, players, sheriff, "sheriff_speech_order", "发言顺序", ACTION_SPEECH, "speech")
		"sheriff_badge_action":
			var dead_sheriff: int = int(state.get("sheriff_badge_dead_index", state.get("sheriff_player_index", -1)))
			if _is_occupied(players, dead_sheriff) and not bool(players[dead_sheriff].get("alive", true)):
				_set_action(state, players, dead_sheriff, "sheriff_badge_action", "警徽", ACTION_VOTE, "vote")
		"wolf_chat":
			var wolf_speaker: int = _next_unspoken_alive_wolf(state, players)
			state["speech_index"] = wolf_speaker
			_mark_speaking(players, wolf_speaker, "狼队夜聊")
		"wolf_action":
			var wolf_voter: int = _next_unvoted_alive_wolf(state, players)
			if wolf_voter >= 0:
				_set_action(state, players, wolf_voter, "wolf_kill", "投刀", ACTION_KILL, "vote")
		"guard_action":
			var guard: int = _first_alive_role(players, "guard")
			if guard >= 0:
				_set_action(state, players, guard, "guard_protect", "守护", ACTION_GUARD, "guard")
		"seer_action":
			var seer: int = _first_alive_role(players, "seer")
			if seer >= 0:
				_set_action(state, players, seer, "seer_check", "查验", ACTION_INSPECT, "inspect")
		"witch_action":
			var witch: int = _first_alive_role(players, "witch")
			if witch >= 0 and not _should_auto_skip_witch(state, players):
				_set_action(state, players, witch, "witch_act", "用药", ACTION_POTION, "potion")
		"last_words":
			var pending: Array = _as_array(state.get("last_words_pending", []))
			if not pending.is_empty():
				var last_speaker: int = int(pending[0])
				state["speech_index"] = last_speaker
				_mark_speaking(players, last_speaker, "发表遗言")
		"day_discussion":
			var speaker: int = _next_unspoken_day_speaker(state, players)
			state["speech_index"] = speaker
			_mark_speaking(players, speaker, "发言中")
		"vote":
			var voter: int = _next_unvoted_alive_actor(state, players)
			if voter >= 0:
				_set_action(state, players, voter, "vote", "投票", ACTION_VOTE, "vote")
		"hunter_action":
			var hunter: int = _first_hunter_can_shoot(players)
			if hunter >= 0:
				_set_action(state, players, hunter, "hunter_shoot", "开枪", ACTION_KILL, "kill")
		"post_game_summary", "mvp_vote":
			_prepare_post_game_prompt(state, players)


func _prepare_post_game_prompt(state: Dictionary, players: Array) -> void:
	var post: Dictionary = _as_dict(state.get("post_game", {}))
	match String(state.get("phase", "")):
		"post_game_summary":
			var pending: Array = _as_array(post.get("summary_pending", []))
			if not pending.is_empty():
				var speaker: int = int(pending[0])
				state["speech_index"] = speaker
				_mark_speaking(players, speaker, "赛后总结")
		"mvp_vote":
			var voter: int = _next_mvp_voter(state, players)
			if voter >= 0:
				_set_action(state, players, voter, "mvp_vote", "MVP", ACTION_VOTE, "vote")


func _clear_prompts(state: Dictionary, players: Array) -> void:
	state["current_action"] = {}
	state["speech_index"] = -1
	for i in range(players.size()):
		if String(players[i].get("owner", "")) == "":
			continue
		var player: Dictionary = players[i]
		if int(player.get("motion", SeatMotion.IDLE)) != SeatMotion.DEAD:
			player["motion"] = SeatMotion.IDLE
			if String(player.get("state", "")) in ["思考中", "发言中", "竞选发言", "决定发言顺序", "狼队夜聊", "等待狼队行动", "等待投票", "等待警长投票", "发表遗言", "赛后总结"]:
				player["state"] = "等待"
			players[i] = player


func _set_action(state: Dictionary, players: Array, actor_index: int, key: String, label: String, icon: String, effect: String) -> void:
	state["current_action"] = {
		"key": key,
		"label": label,
		"icon": icon,
		"effect": effect,
		"actor_index": actor_index,
	}
	if actor_index >= 0 and actor_index < players.size():
		var player: Dictionary = players[actor_index]
		if int(player.get("motion", SeatMotion.IDLE)) != SeatMotion.DEAD:
			player["motion"] = SeatMotion.THINKING
		player["state"] = "思考中"
		players[actor_index] = player


func _mark_speaking(players: Array, index: int, state_text: String) -> void:
	if index < 0 or index >= players.size():
		return
	var player: Dictionary = players[index]
	if int(player.get("motion", SeatMotion.IDLE)) != SeatMotion.DEAD:
		player["motion"] = SeatMotion.SPEAKING
	player["state"] = state_text
	players[index] = player


func _advance_auto(state: Dictionary, players: Array) -> Dictionary:
	var next_state: Dictionary = state
	var next_players: Array = players
	var history: Array = []
	var death_indices: Array = []
	var guard := 0
	while guard < 12:
		guard += 1
		var phase: String = String(next_state.get("phase", ""))
		if phase == "game_over":
			next_state["phase"] = "replay_round"
			var post: Dictionary = _as_dict(next_state.get("post_game", {}))
			post["stage"] = "replay_round"
			post["replay_round"] = _replay_round_data(next_state, next_players)
			next_state["post_game"] = post
			history.append(_history("主持人", "复盘回合数据已生成。"))
			continue
		if phase == "replay_round":
			var replay_post: Dictionary = _as_dict(next_state.get("post_game", {}))
			replay_post["stage"] = "summary"
			next_state["post_game"] = replay_post
			next_state["phase"] = "post_game_summary"
			history.append(_history("主持人", "进入赛后总结。"))
			continue
		if phase == "wolf_chat" and not _has_alive_wolf_chat_actor(next_players):
			next_state["phase"] = "wolf_action"
			next_state["spoken_indices"] = []
			next_state["votes"] = {}
			continue
		if phase == "wolf_chat" and _all_alive_wolves_spoken(next_state, next_players):
			next_state["phase"] = "wolf_action"
			next_state["spoken_indices"] = []
			next_state["votes"] = {}
			continue
		if phase == "wolf_action" and not _has_alive_wolf_kill_actor(next_players):
			var win: Dictionary = _check_win(next_state, next_players)
			if String(win.get("winner", "")) != "":
				next_state = _finish_game(next_state, next_players, String(win["winner"]))
				history.append(_history("主持人", String(win["message"])))
			break
		if phase == "sheriff_speech_order" and not _sheriff_can_decide_speech_order(next_state, next_players):
			_enter_day_discussion_gate(next_state, next_players)
			history.append(_history("主持人", "警长无法决定发言顺序，白天按座位顺序发言。"))
			continue
		if phase == "sheriff_badge_action" and not _sheriff_badge_actor_can_act(next_state, next_players):
			next_state["sheriff_player_index"] = -1
			var badge_continued: Dictionary = _continue_after_sheriff_badge(next_state, next_players)
			next_state = badge_continued["werewolf"]
			next_players = badge_continued["players"]
			history.append(_history("主持人", "死亡警长无法处理警徽，警徽自动撕毁。"))
			history.append_array(badge_continued["history"])
			death_indices.append_array(badge_continued["death_indices"])
			continue
		if phase == "guard_action" and not _has_alive_role(next_players, "guard"):
			next_state["phase"] = "seer_action"
			continue
		if phase == "seer_action" and not _has_alive_role(next_players, "seer"):
			next_state["phase"] = "witch_action"
			continue
		if phase == "witch_action" and (not _has_alive_role(next_players, "witch") or _should_auto_skip_witch(next_state, next_players)):
			var resolved: Dictionary = _resolve_night(next_state, next_players)
			next_state = resolved["werewolf"]
			next_players = resolved["players"]
			history.append_array(resolved["history"])
			death_indices.append_array(resolved["death_indices"])
			continue
		break
	return {
		"werewolf": next_state,
		"players": next_players,
		"history": history,
		"death_indices": _unique_indices(death_indices),
	}


func _apply_witch_action(state: Dictionary, players: Array, actor_index: int, target_index: int) -> Dictionary:
	var night: Dictionary = _as_dict(state.get("night", {}))
	var wolf_target: int = int(night.get("wolf_target_index", -1))
	var history: Array = []
	if target_index == wolf_target and bool(state.get("witch_antidote", true)):
		night["witch_saved"] = true
		state["witch_antidote"] = false
		state["night"] = night
		history.append(_actor_history(players, actor_index, "我使用解药救 %s。" % _player_title(players, target_index), "private", target_index, "witch_act"))
		return {"ok": true, "history": history}
	if bool(state.get("witch_poison", true)):
		night["witch_poison_target_index"] = target_index
		state["witch_poison"] = false
		state["night"] = night
		history.append(_actor_history(players, actor_index, "我对 %s 使用毒药。" % _player_title(players, target_index), "private", target_index, "witch_act"))
		return {"ok": true, "history": history}
	return _error("女巫已无可用药水")


func _resolve_night(state: Dictionary, players: Array) -> Dictionary:
	var next_state: Dictionary = state.duplicate(true)
	var night: Dictionary = _as_dict(next_state.get("night", {}))
	var raw_deaths: Array = []
	var wolf_target: int = int(night.get("wolf_target_index", -1))
	var guarded: int = int(night.get("guarded_index", -1))
	var poison_target: int = int(night.get("witch_poison_target_index", -1))
	if wolf_target >= 0 and wolf_target != guarded and not bool(night.get("witch_saved", false)):
		raw_deaths.append(wolf_target)
	if poison_target >= 0:
		raw_deaths.append(poison_target)
	var deaths: Array = _unique_indices(raw_deaths)
	var pending_deaths: Array = []
	for item in deaths:
		var index: int = int(item)
		var reason := "女巫毒杀" if index == poison_target else "夜晚死亡"
		var death_key := "witch_poison" if index == poison_target else "wolf"
		pending_deaths.append({"index": index, "reason": reason, "death_reason": death_key})

	var history: Array = []
	next_state["night"] = {}
	next_state["spoken_indices"] = []
	if _grant_hunter_shot_for_pending_deaths(players, pending_deaths):
		next_state["pending_night_deaths"] = pending_deaths
		var pending_names: Array = []
		for item in pending_deaths:
			var entry: Dictionary = item
			pending_names.append(_player_title(players, int(entry.get("index", -1))))
		history.append(_history("主持人", "夜晚结算结果指向：%s，先处理出局前技能。" % "、".join(pending_names)))
		next_state["phase"] = "hunter_action"
		next_state["hunter_return_phase"] = "night_death_settlement"
		return _transition_result(players, next_state, history, [], "猎人可开枪")

	var settled: Dictionary = _settle_night_deaths(next_state, players, pending_deaths)
	next_state = settled["werewolf"]
	players = settled["players"]
	history.append_array(settled["history"])
	return _transition_result(players, next_state, history, settled["death_indices"], String(settled.get("message", "天亮了")))


func _resolve_sheriff_vote(state: Dictionary, players: Array) -> Dictionary:
	var votes: Dictionary = _as_dict(state.get("votes", {}))
	var sheriff_index: int = _top_voted_index(votes, players, true)
	state["sheriff_player_index"] = sheriff_index
	state["phase"] = "wolf_chat"
	state["votes"] = {}
	state["night"] = _new_night(1)
	state["spoken_indices"] = []
	var history: Array = [
		_history("主持人", "本局警长：%s。" % _player_title(players, sheriff_index)),
		_history("主持人", "第1夜开始。"),
	]
	return {"werewolf": state, "players": players, "history": history, "death_indices": [], "message": "警长已产生"}


func _resolve_wolf_target_vote(state: Dictionary, players: Array) -> Dictionary:
	var votes: Dictionary = _as_dict(state.get("votes", {}))
	var counts: Dictionary = _vote_counts(votes, state, false)
	var top_targets: Array = _legal_wolf_vote_targets(players, _top_voted_indices(counts))
	var tied := top_targets.size() > 1
	var target_index := -1
	if top_targets.size() == 1:
		target_index = int(top_targets[0])
	elif tied:
		target_index = int(top_targets[randi() % top_targets.size()])
	if target_index < 0:
		var wolf: int = _first_alive_wolf_kill_actor(players)
		target_index = _first_legal_target(state, players, wolf, "wolf_kill") if wolf >= 0 else -1
	if target_index < 0:
		state["votes"] = {}
		state["phase"] = "guard_action"
		return _transition_result(players, state, [_moderator_wolf_history("狼队没有可袭击目标，跳过袭击。", "wolf_kill")], [], "狼队跳过袭击")
	var night: Dictionary = _as_dict(state.get("night", _new_night(int(state.get("day", 1)))))
	night["wolf_target_index"] = target_index
	state["night"] = night
	state["votes"] = {}
	state["phase"] = "guard_action"
	var text := "狼队投票结束，决定袭击 %s。" % _player_title(players, target_index)
	if tied:
		text = "狼队目标票平票，系统随机决定袭击 %s。" % _player_title(players, target_index)
	return _transition_result(players, state, [_moderator_wolf_history(text, "wolf_kill")], [], "狼队投票完成")


func _legal_wolf_vote_targets(players: Array, targets: Array) -> Array:
	var result := []
	for item in targets:
		var index := int(item)
		if index < 0 or index >= players.size():
			continue
		if not _is_alive_occupied(players, index):
			continue
		if not _role_catalog.can_be_wolf_kill_target(String(players[index].get("role_key", ""))):
			continue
		result.append(index)
	return result


func _resolve_vote(state: Dictionary, players: Array) -> Dictionary:
	var votes: Dictionary = _as_dict(state.get("votes", {}))
	var counts: Dictionary = _vote_counts(votes, state, true)
	var top_targets: Array = _top_voted_indices(counts)
	var history: Array = []
	var deaths: Array = []
	var message := ""
	state["votes"] = {}
	if top_targets.size() != 1:
		history.append(_history("主持人", "投票平票，无人出局。"))
		_start_next_night(state)
		history.append(_history("主持人", "第%d夜开始。" % int(state.get("day", 1))))
		message = "平票，进入夜晚"
		return _transition_result(players, state, history, deaths, message)

	var exiled_index: int = int(top_targets[0])
	if _can_idiot_reveal(players, exiled_index):
		_reveal_idiot(players, exiled_index)
		history.append(_history("主持人", "%s被投票放逐，白痴翻牌免于出局，之后失去投票权。" % _player_title(players, exiled_index)))
		_start_next_night(state)
		history.append(_history("主持人", "第%d夜开始。" % int(state.get("day", 1))))
		return _transition_result(players, state, history, deaths, "白痴翻牌免死，进入夜晚")

	state["pending_vote_exile_index"] = exiled_index
	if _grant_hunter_shot_on_pending_exile(players, exiled_index):
		history.append(_history("主持人", "投票结果指向：%s，先处理出局前技能。" % _player_title(players, exiled_index)))
		state["phase"] = "hunter_action"
		state["hunter_return_phase"] = "vote_exile_settlement"
		message = "猎人可开枪"
		return _transition_result(players, state, history, deaths, message)

	var settled: Dictionary = _settle_pending_vote_exile(state, players)
	state = settled["werewolf"]
	players = settled["players"]
	deaths.append_array(settled["death_indices"])
	history.append_array(settled["history"])
	message = String(settled.get("message", "投票完成"))
	return _transition_result(players, state, history, deaths, message)


func _after_hunter_action(state: Dictionary, players: Array) -> Dictionary:
	var history: Array = []
	var deaths: Array = []
	var return_phase: String = String(state.get("hunter_return_phase", "win_check"))
	state["hunter_return_phase"] = ""
	var win: Dictionary = _check_win(state, players)
	if String(win.get("winner", "")) != "":
		state["pending_night_deaths"] = []
		state["pending_vote_exile_index"] = -1
		state = _finish_game(state, players, String(win["winner"]))
		history.append(_history("主持人", String(win["message"])))
		return _transition_result(players, state, history, deaths, String(win["message"]))
	if return_phase == "night_death_settlement":
		var pending: Array = _as_array(state.get("pending_night_deaths", []))
		state["pending_night_deaths"] = []
		var night_settled: Dictionary = _settle_night_deaths(state, players, pending)
		state = night_settled["werewolf"]
		players = night_settled["players"]
		history.append_array(night_settled["history"])
		deaths.append_array(night_settled["death_indices"])
		return _transition_result(players, state, history, deaths, String(night_settled.get("message", "猎人行动完成")))
	if return_phase == "vote_exile_settlement":
		var settled: Dictionary = _settle_pending_vote_exile(state, players)
		state = settled["werewolf"]
		players = settled["players"]
		history.append_array(settled["history"])
		deaths.append_array(settled["death_indices"])
		return _transition_result(players, state, history, deaths, String(settled.get("message", "猎人行动完成")))
	var candidates: Array = _pending_last_words_candidates(state, players)
	var badge: Dictionary = _start_sheriff_badge_action_if_needed(state, players, candidates, return_phase, false)
	if bool(badge.get("started", false)):
		state = badge["werewolf"]
		history.append_array(badge["history"])
		return _transition_result(players, state, history, deaths, String(badge.get("message", "警徽处理")))
	var last_words: Dictionary = _start_last_words_if_needed(state, players, candidates, return_phase)
	state = last_words["werewolf"]
	history.append_array(last_words["history"])
	return _transition_result(players, state, history, deaths, String(last_words.get("message", "猎人行动完成")))


func _settle_night_deaths(state: Dictionary, players: Array, pending_deaths: Array) -> Dictionary:
	var history: Array = []
	var deaths: Array = []
	for item in pending_deaths:
		if not (item is Dictionary):
			continue
		var entry: Dictionary = item
		var index := int(entry.get("index", -1))
		if not _is_alive_occupied(players, index):
			continue
		_kill_player(players, index, String(entry.get("reason", "夜晚死亡")), String(entry.get("death_reason", "wolf")))
		deaths.append(index)
	state["pending_night_deaths"] = []

	var death_names: Array = []
	for item in deaths:
		death_names.append(_player_title(players, int(item)))
	var message := "昨夜平安夜。"
	if not death_names.is_empty():
		message = "昨夜死亡：%s。" % "、".join(death_names)
	history.append(_history("主持人", message))

	var win: Dictionary = _check_win(state, players)
	if String(win.get("winner", "")) != "":
		state = _finish_game(state, players, String(win["winner"]))
		history.append(_history("主持人", String(win["message"])))
		return _transition_result(players, state, history, deaths, String(win["message"]))

	var candidates: Array = _pending_last_words_candidates(state, players)
	var badge: Dictionary = _start_sheriff_badge_action_if_needed(state, players, candidates, "day_entry", false)
	if bool(badge.get("started", false)):
		state = badge["werewolf"]
		history.append_array(badge["history"])
		return _transition_result(players, state, history, deaths, String(badge.get("message", message)))

	var last_words: Dictionary = _start_last_words_if_needed(state, players, candidates, "day_entry")
	state = last_words["werewolf"]
	history.append_array(last_words["history"])
	message = String(last_words.get("message", message))
	return _transition_result(players, state, history, deaths, message)


func _settle_pending_vote_exile(state: Dictionary, players: Array) -> Dictionary:
	var exiled_index := int(state.get("pending_vote_exile_index", -1))
	state["pending_vote_exile_index"] = -1
	if not _is_alive_occupied(players, exiled_index):
		return _transition_result(players, state, [], [], "投票完成")

	_kill_player(players, exiled_index, "放逐", "exiled")
	var history := [_history("主持人", "%s被投票放逐。" % _player_title(players, exiled_index))]
	var deaths := [exiled_index]

	var win: Dictionary = _check_win(state, players)
	if String(win.get("winner", "")) != "":
		state = _finish_game(state, players, String(win["winner"]))
		history.append(_history("主持人", String(win["message"])))
		return _transition_result(players, state, history, deaths, String(win["message"]))

	var candidates: Array = _pending_last_words_candidates(state, players)
	var badge: Dictionary = _start_sheriff_badge_action_if_needed(state, players, candidates, "win_check", false)
	if bool(badge.get("started", false)):
		state = badge["werewolf"]
		history.append_array(badge["history"])
		return _transition_result(players, state, history, deaths, String(badge.get("message", "警徽处理")))

	var last_words: Dictionary = _start_last_words_if_needed(state, players, candidates, "win_check")
	state = last_words["werewolf"]
	history.append_array(last_words["history"])
	return _transition_result(players, state, history, deaths, String(last_words.get("message", "投票完成")))


func _start_sheriff_badge_action_if_needed(state: Dictionary, players: Array, candidates: Array, return_phase: String, check_hunter_after_badge: bool) -> Dictionary:
	if not _sheriff_badge_needed(state, players, candidates):
		return {"started": false, "werewolf": state, "players": players, "history": [], "death_indices": [], "message": ""}
	var sheriff_index: int = int(state.get("sheriff_player_index", -1))
	state["phase"] = "sheriff_badge_action"
	state["current_action"] = {}
	state["speech_index"] = -1
	state["sheriff_badge_dead_index"] = sheriff_index
	state["sheriff_badge_return_phase"] = return_phase
	state["sheriff_badge_candidates"] = _unique_indices(candidates)
	state["sheriff_badge_check_hunter"] = check_hunter_after_badge
	return {
		"started": true,
		"werewolf": state,
		"players": players,
		"history": [_history("主持人", "警长 %s 死亡，请选择飞警徽或撕警徽。" % _player_title(players, sheriff_index))],
		"death_indices": [],
		"message": "警徽处理",
	}


func _sheriff_badge_needed(state: Dictionary, players: Array, candidates: Array) -> bool:
	if not bool(state.get("has_sheriff", false)):
		return false
	var sheriff_index: int = int(state.get("sheriff_player_index", -1))
	if sheriff_index < 0 or not _is_occupied(players, sheriff_index):
		return false
	if bool(players[sheriff_index].get("alive", true)):
		return false
	for item in candidates:
		if int(item) == sheriff_index:
			return true
	return false


func _sheriff_badge_actor_can_act(state: Dictionary, players: Array) -> bool:
	var sheriff_index: int = int(state.get("sheriff_badge_dead_index", state.get("sheriff_player_index", -1)))
	return _is_occupied(players, sheriff_index) and sheriff_index == int(state.get("sheriff_player_index", -1)) and not bool(players[sheriff_index].get("alive", true))


func _continue_after_sheriff_badge(state: Dictionary, players: Array) -> Dictionary:
	var return_phase: String = String(state.get("sheriff_badge_return_phase", "win_check"))
	var candidates: Array = _as_array(state.get("sheriff_badge_candidates", []))
	var check_hunter_after_badge := bool(state.get("sheriff_badge_check_hunter", false))
	_clear_sheriff_badge_pending(state)
	if return_phase in ["day_entry", "day_discussion", "win_check"]:
		var win: Dictionary = _check_win(state, players)
		if String(win.get("winner", "")) != "":
			state = _finish_game(state, players, String(win["winner"]))
			return _transition_result(players, state, [_history("主持人", String(win["message"]))], [], String(win["message"]))
		if check_hunter_after_badge and _first_hunter_can_shoot(players) >= 0:
			state["phase"] = "hunter_action"
			state["hunter_return_phase"] = return_phase
			return _transition_result(players, state, [], [], "猎人可开枪")
		return _start_last_words_if_needed(state, players, candidates, return_phase)
	state["phase"] = return_phase
	return _transition_result(players, state, [], [], phase_label(state))


func _clear_sheriff_badge_pending(state: Dictionary) -> void:
	state["sheriff_badge_return_phase"] = ""
	state["sheriff_badge_dead_index"] = -1
	state["sheriff_badge_candidates"] = []
	state["sheriff_badge_check_hunter"] = false


func _start_last_words_if_needed(state: Dictionary, players: Array, candidates: Array, return_phase: String) -> Dictionary:
	var pending: Array = []
	var used: Array = _as_array(state.get("last_words_used", []))
	for item in candidates:
		var index: int = int(item)
		if index < 0 or index >= players.size():
			continue
		if bool(players[index].get("alive", true)):
			continue
		if used.has(index) or pending.has(index):
			continue
		pending.append(index)
	pending.sort()
	if pending.is_empty():
		return _continue_after_last_words_with_phase(state, players, return_phase)
	state["phase"] = "last_words"
	state["last_words_pending"] = pending
	state["last_words_return_phase"] = return_phase
	return {
		"werewolf": state,
		"players": players,
		"history": [_history("主持人", "进入遗言阶段，死亡玩家按座位顺序发表遗言。")],
		"death_indices": [],
		"message": "遗言阶段",
	}


func _continue_after_last_words(state: Dictionary, players: Array) -> Dictionary:
	var return_phase: String = String(state.get("last_words_return_phase", "day_discussion"))
	state["last_words_pending"] = []
	state["last_words_return_phase"] = ""
	return _continue_after_last_words_with_phase(state, players, return_phase)


func _continue_after_last_words_with_phase(state: Dictionary, players: Array, return_phase: String) -> Dictionary:
	if return_phase in ["day_entry", "day_discussion"]:
		var win: Dictionary = _check_win(state, players)
		if String(win.get("winner", "")) != "":
			state = _finish_game(state, players, String(win["winner"]))
			return _transition_result(players, state, [_history("主持人", String(win["message"]))], [], String(win["message"]))
		_enter_day_discussion_gate(state, players)
		var message := "警长决定发言顺序" if String(state.get("phase", "")) == "sheriff_speech_order" else "进入白天发言"
		return _transition_result(players, state, [], [], message)
	if return_phase == "win_check":
		var checked: Dictionary = _check_win(state, players)
		if String(checked.get("winner", "")) != "":
			state = _finish_game(state, players, String(checked["winner"]))
			return _transition_result(players, state, [_history("主持人", String(checked["message"]))], [], String(checked["message"]))
		_start_next_night(state)
		return _transition_result(players, state, [_history("主持人", "第%d夜开始。" % int(state.get("day", 1)))], [], "进入夜晚")
	state["phase"] = return_phase
	return _transition_result(players, state, [], [], phase_label(state))


func _start_next_night(state: Dictionary) -> void:
	var next_day: int = int(state.get("day", 1)) + 1
	state["day"] = next_day
	state["phase"] = "wolf_chat"
	state["night"] = _new_night(next_day)
	state["votes"] = {}
	state["spoken_indices"] = []
	_clear_day_speech_order(state)


func _enter_day_discussion_gate(state: Dictionary, players: Array) -> void:
	state["spoken_indices"] = []
	_clear_day_speech_order(state)
	if _sheriff_can_decide_speech_order(state, players):
		state["phase"] = "sheriff_speech_order"
	else:
		state["phase"] = "day_discussion"


func _sheriff_can_decide_speech_order(state: Dictionary, players: Array) -> bool:
	if not bool(state.get("has_sheriff", false)):
		return false
	var sheriff_index: int = int(state.get("sheriff_player_index", -1))
	return _is_alive_occupied(players, sheriff_index)


func _clear_day_speech_order(state: Dictionary) -> void:
	state["day_speech_order"] = []
	state["day_speech_order_start_index"] = -1
	state["day_speech_order_direction"] = ""
	state["day_speech_order_day"] = 0
	state["day_speech_order_decider_index"] = -1


func _set_day_speech_order(state: Dictionary, start_index: int, direction: String, order: Array, decider_index: int) -> void:
	state["day_speech_order"] = order.duplicate()
	state["day_speech_order_start_index"] = start_index
	state["day_speech_order_direction"] = direction
	state["day_speech_order_day"] = int(state.get("day", 0))
	state["day_speech_order_decider_index"] = decider_index


func _build_day_speech_order(players: Array, start_index: int, direction: String) -> Array:
	if players.is_empty() or not _is_alive_occupied(players, start_index):
		return []
	var result: Array = []
	var step := -1 if direction == "counterclockwise" else 1
	var index := start_index
	for _i in range(players.size()):
		if _is_alive_occupied(players, index):
			result.append(index)
		index = (index + step + players.size()) % players.size()
	return result


func _speech_order_direction_from_action_choice(action_choice: String) -> String:
	var choice := action_choice.strip_edges().to_lower()
	match choice:
		"sheriff_speech_order_clockwise", "clockwise", "顺时针":
			return "clockwise"
		"sheriff_speech_order_counterclockwise", "counterclockwise", "逆时针":
			return "counterclockwise"
		_:
			return ""


func _speech_order_direction_label(direction: String) -> String:
	return "逆时针" if direction == "counterclockwise" else "顺时针"


func _sheriff_badge_action_from_choice(action_choice: String) -> String:
	var choice := action_choice.strip_edges().to_lower()
	match choice:
		"sheriff_badge_pass", "pass", "飞警徽":
			return "pass"
		"sheriff_badge_destroy", "destroy", "tear", "撕警徽":
			return "destroy"
		_:
			return ""


func _speech_order_titles(players: Array, order: Array) -> String:
	var parts: Array = []
	for item in order:
		parts.append(_player_title(players, int(item)))
	return "、".join(parts)


func _finish_game(state: Dictionary, players: Array, winner: String) -> Dictionary:
	var next_state: Dictionary = state.duplicate(true)
	next_state["phase"] = "game_over"
	next_state["current_action"] = {}
	next_state["speech_index"] = -1
	next_state["winner"] = winner
	var occupied: Array = _occupied_indices(players)
	next_state["post_game"] = {
		"stage": "game_over",
		"summary_pending": occupied,
		"summaries": {},
		"mvp_votes": {},
		"mvp_index": -1,
		"replay_round": {},
	}
	for i in range(players.size()):
		if String(players[i].get("owner", "")) != "":
			var player: Dictionary = players[i]
			player["state"] = "复盘回合"
			if bool(player.get("alive", true)):
				player["motion"] = SeatMotion.IDLE
			players[i] = player
	return next_state


func _replay_round_data(state: Dictionary, players: Array) -> Dictionary:
	var seats: Array = []
	for i in range(players.size()):
		if not _is_occupied(players, i):
			continue
		var player: Dictionary = players[i]
		seats.append({
			"seat_number": i + 1,
			"name": String(player.get("name", "")),
			"role_key": String(player.get("role_key", "")),
			"role_name": String(player.get("role", "")),
			"alive": bool(player.get("alive", true)),
			"death_reason": String(player.get("death_reason", "")),
		})
	return {
		"winner": String(state.get("winner", "")),
		"map_id": String(state.get("map_id", "")),
		"map_name": String(state.get("map_name", "")),
		"day": int(state.get("day", 0)),
		"seats": seats,
	}


func _check_win(state: Dictionary, players: Array) -> Dictionary:
	var check_state := state.duplicate(true)
	if String(check_state.get("wolf_win_condition", "")).strip_edges() == "":
		check_state["wolf_win_condition"] = _map_catalog.wolf_win_condition_key(String(check_state.get("map_id", DEFAULT_MAP_ID)), _occupied_indices(players).size())
	return _win_conditions.check(check_state, players)


func _validate_target(state: Dictionary, players: Array, actor_index: int, target_index: int, action_key: String) -> Dictionary:
	if action_key == "mvp_vote":
		if not _is_occupied(players, actor_index):
			return _error("行动玩家不存在")
		if not _is_occupied(players, target_index):
			return _error("目标玩家不存在")
		return {"ok": true}
	if action_key == "sheriff_badge_action":
		if not _is_occupied(players, actor_index):
			return _error("行动玩家不存在")
		if actor_index != int(state.get("sheriff_badge_dead_index", state.get("sheriff_player_index", -1))):
			return _error("只有死亡警长可以处理警徽")
		if actor_index != int(state.get("sheriff_player_index", -1)):
			return _error("只有当前警长可以移交警徽")
		if bool(players[actor_index].get("alive", true)):
			return _error("警长仍存活，无需处理警徽")
		if not _is_alive_occupied(players, target_index):
			return _error("警徽只能移交给存活玩家")
		if target_index == actor_index:
			return _error("不能把警徽移交给自己")
		return {"ok": true}
	if not _is_alive_occupied(players, actor_index):
		if action_key != "hunter_shoot" or not _is_occupied(players, actor_index):
			return _error("行动玩家不存在或已死亡")
	if not _is_alive_occupied(players, target_index):
		return _error("目标玩家不存在或已死亡")
	match action_key:
		"wolf_kill":
			if not _role_catalog.can_be_wolf_kill_target(String(players[target_index].get("role_key", ""))):
				return _error("狼人不能选择狼队友")
			if target_index == actor_index:
				return _error("不能选择自己")
		"guard_protect":
			if target_index == int(state.get("last_guarded_index", -1)):
				return _error("守卫不能连续两夜守护同一名玩家")
		"sheriff_vote":
			pass
		"sheriff_speech_order":
			if actor_index != int(state.get("sheriff_player_index", -1)):
				return _error("只有警长可以决定发言顺序")
		"vote":
			if not _can_vote(players, actor_index):
				return _error("当前玩家不能投票")
			if target_index == actor_index:
				return _error("不能选择自己")
		"seer_check", "hunter_shoot":
			if target_index == actor_index:
				return _error("不能选择自己")
		"witch_act":
			if String(state.get("phase", "")) != "witch_action":
				return _error("女巫只能在夜晚行动")
			var night: Dictionary = _as_dict(state.get("night", {}))
			var wolf_target: int = int(night.get("wolf_target_index", -1))
			if target_index == wolf_target and bool(state.get("witch_antidote", true)):
				return {"ok": true}
			if not bool(state.get("witch_poison", true)):
				return _error("女巫已无可用药水")
			if target_index == actor_index:
				return _error("女巫不能毒自己")
		_:
			pass
	return {"ok": true}


func _kill_player(players: Array, index: int, reason: String, death_reason: String) -> void:
	if index < 0 or index >= players.size():
		return
	var player: Dictionary = players[index]
	if String(player.get("owner", "")) == "":
		return
	player["alive"] = false
	player["motion"] = SeatMotion.DEAD
	player["state"] = reason
	player["death_reason"] = death_reason
	if String(player.get("role_key", "")) == "hunter" and not bool(player.get("has_hunter_shot", false)):
		player["can_hunter_shoot"] = true
	players[index] = player


func _grant_hunter_shot_on_pending_exile(players: Array, index: int) -> bool:
	if not _is_alive_occupied(players, index):
		return false
	var player: Dictionary = players[index]
	if String(player.get("role_key", "")) != "hunter" or bool(player.get("has_hunter_shot", false)):
		return false
	player["can_hunter_shoot"] = true
	players[index] = player
	return true


func _grant_hunter_shot_for_pending_deaths(players: Array, pending_deaths: Array) -> bool:
	var granted := false
	for item in pending_deaths:
		if not (item is Dictionary):
			continue
		var entry: Dictionary = item
		if _grant_hunter_shot_on_pending_exile(players, int(entry.get("index", -1))):
			granted = true
	return granted


func _can_idiot_reveal(players: Array, index: int) -> bool:
	if index < 0 or index >= players.size() or not (players[index] is Dictionary):
		return false
	var player: Dictionary = players[index]
	return String(player.get("role_key", "")) == "idiot" and not bool(player.get("idiot_revealed", false))


func _reveal_idiot(players: Array, index: int) -> void:
	var player: Dictionary = players[index]
	player["idiot_revealed"] = true
	player["idiot_reveal_source"] = "vote_exile"
	player["state"] = "白痴翻牌"
	player["motion"] = SeatMotion.IDLE
	players[index] = player


func _mark_hunter_spent(players: Array, index: int) -> void:
	if index < 0 or index >= players.size():
		return
	var player: Dictionary = players[index]
	player["can_hunter_shoot"] = false
	player["has_hunter_shot"] = true
	players[index] = player


func _prompt_message(state: Dictionary, players: Array) -> String:
	var action: Dictionary = _as_dict(state.get("current_action", {}))
	if not action.is_empty():
		return _action_prompt_message(state, players, action)
	var speech_index: int = int(state.get("speech_index", -1))
	if speech_index >= 0:
		match String(state.get("phase", "")):
			"wolf_chat":
				var spoken: Array = _as_array(state.get("spoken_indices", []))
				var prefix := "黑夜降临，请狼队按座位顺序发言。" if spoken.is_empty() else "狼队夜聊继续。"
				return "%s 当前由 %s 发言。" % [prefix, _player_title(players, speech_index)]
			"last_words":
				return "请 %s 发表遗言。" % _player_title(players, speech_index)
			"post_game_summary":
				return "请 %s 发表赛后总结。" % _player_title(players, speech_index)
			_:
				return "请 %s 发言。" % _player_title(players, speech_index)
	if String(state.get("phase", "lobby")) == "completed":
		var post: Dictionary = _as_dict(state.get("post_game", {}))
		var mvp_index: int = int(post.get("mvp_index", -1))
		if mvp_index >= 0:
			return "复盘完成 · MVP %s" % _player_title(players, mvp_index)
		return "复盘完成"
	return phase_label(state)


func _action_prompt_message(state: Dictionary, players: Array, action: Dictionary) -> String:
	var actor_index: int = int(action.get("actor_index", -1))
	var actor := _player_title(players, actor_index)
	match String(action.get("key", "")):
		"wolf_kill":
			return "狼队投票：请 %s 选择今晚袭击目标。" % actor
		"guard_protect":
			return "私密询问：%s，请选择今晚守护谁。" % actor
		"seer_check":
			return "私密询问：%s，请选择今晚查验谁。" % actor
		"witch_act":
			return _witch_prompt_message(state, players, actor_index)
		"sheriff_vote":
			return "请 %s 投票选择本局警长。" % actor
		"sheriff_speech_order":
			return "请警长 %s 指定白天发言起点和顺时针或逆时针方向。" % actor
		"sheriff_badge_action":
			return "请死亡警长 %s 选择飞警徽给一名存活玩家，或撕毁警徽。" % actor
		"vote":
			return "请 %s 投票选择放逐对象。" % actor
		"hunter_shoot":
			return "请 %s 决定是否开枪并选择目标。" % actor
		"mvp_vote":
			return "请 %s 投票选择本局 MVP。" % actor
		_:
			return "%s · %s" % [actor, String(action.get("label", "行动"))]


func _witch_prompt_message(state: Dictionary, players: Array, actor_index: int) -> String:
	var actor := _player_title(players, actor_index)
	var night: Dictionary = _as_dict(state.get("night", {}))
	var wolf_target: int = int(night.get("wolf_target_index", -1))
	var can_save := wolf_target >= 0 and bool(state.get("witch_antidote", true)) and _is_alive_occupied(players, wolf_target)
	var can_poison := bool(state.get("witch_poison", true)) and _has_alive_target_except(players, actor_index)
	if can_save and can_poison:
		return "女巫行动：%s，今晚 %s 被袭击。请选择使用解药、毒药或不用药；若用毒，请选择目标。" % [actor, _player_title(players, wolf_target)]
	if can_save:
		return "女巫行动：%s，今晚 %s 被袭击。是否使用解药？" % [actor, _player_title(players, wolf_target)]
	if can_poison:
		return "女巫行动：%s，今晚没有可救目标。是否使用毒药；若用毒，请选择目标。" % actor
	return "女巫行动：%s，今晚没有可用药水。" % actor


func _append_prompt_history(history: Array, state: Dictionary, players: Array) -> void:
	var item := _prompt_history_for_state(state, players)
	if item.is_empty():
		return
	for existing in history:
		if existing is Dictionary and _same_prompt_history(existing as Dictionary, item):
			return
	history.append(item)


func _same_prompt_history(left: Dictionary, right: Dictionary) -> bool:
	return (
		String(left.get("speaker", "")) == String(right.get("speaker", ""))
		and String(left.get("text", "")) == String(right.get("text", ""))
		and String(left.get("visibility", "public")) == String(right.get("visibility", "public"))
		and String(left.get("action_key", "")) == String(right.get("action_key", ""))
	)


func _prompt_history_for_state(state: Dictionary, players: Array) -> Dictionary:
	var text := _prompt_message(state, players).strip_edges()
	if text == "" or String(state.get("phase", "")) == "completed":
		return {}
	var action: Dictionary = _as_dict(state.get("current_action", {}))
	if not action.is_empty():
		var actor_index: int = int(action.get("actor_index", -1))
		var action_key := String(action.get("key", ""))
		if action_key == "wolf_kill":
			var wolf_item := _history("主持人", text)
			wolf_item["visibility"] = "wolf"
			wolf_item["action_key"] = action_key
			return wolf_item
		if action_key in ["guard_protect", "seer_check", "witch_act"]:
			return _moderator_private_history(players, actor_index, text, -1, action_key)
		var action_item := _history("主持人", text)
		action_item["action_key"] = action_key
		return action_item
	if String(state.get("phase", "")) == "wolf_chat":
		var wolf_chat_item := _history("主持人", text)
		wolf_chat_item["visibility"] = "wolf"
		wolf_chat_item["action_key"] = "wolf_chat"
		return wolf_chat_item
	return _history("主持人", text)


func _new_night(day: int) -> Dictionary:
	return {
		"day": day,
		"wolf_target_index": -1,
		"guarded_index": -1,
		"witch_saved": false,
		"witch_poison_target_index": -1,
	}


func _should_auto_skip_witch(state: Dictionary, players: Array) -> bool:
	if String(state.get("phase", "")) != "witch_action":
		return true
	var witch: int = _first_alive_role(players, "witch")
	if witch < 0:
		return false
	var night: Dictionary = _as_dict(state.get("night", {}))
	var wolf_target: int = int(night.get("wolf_target_index", -1))
	var can_save: bool = wolf_target >= 0 and bool(state.get("witch_antidote", true)) and _is_alive_occupied(players, wolf_target)
	var can_poison: bool = bool(state.get("witch_poison", true)) and _has_alive_target_except(players, witch)
	return not can_save and not can_poison


func _record_vote(state: Dictionary, actor_index: int, target_index: int) -> void:
	var votes: Dictionary = _as_dict(state.get("votes", {}))
	votes[str(actor_index)] = target_index
	state["votes"] = votes


func _vote_counts(votes: Dictionary, state: Dictionary, use_sheriff_weight: bool) -> Dictionary:
	var counts: Dictionary = {}
	var sheriff_index: int = int(state.get("sheriff_player_index", -1))
	for voter_key in votes.keys():
		var target_index: int = int(votes[voter_key])
		var weight := 1
		if use_sheriff_weight and int(String(voter_key).to_int()) == sheriff_index:
			weight = 2
		counts[str(target_index)] = int(counts.get(str(target_index), 0)) + weight
	return counts


func _top_voted_indices(counts: Dictionary) -> Array:
	var top: Array = []
	var max_votes := 0
	for key in counts.keys():
		var count: int = int(counts[key])
		if count > max_votes:
			max_votes = count
			top = [int(String(key).to_int())]
		elif count == max_votes:
			top.append(int(String(key).to_int()))
	top.sort()
	return top


func _top_voted_index(votes: Dictionary, players: Array, alive_only: bool) -> int:
	var counts: Dictionary = _vote_counts(votes, {}, false)
	var top: Array = _top_voted_indices(counts)
	for item in top:
		var index: int = int(item)
		if alive_only and not _is_alive_occupied(players, index):
			continue
		if not alive_only and not _is_occupied(players, index):
			continue
		return index
	for i in range(players.size()):
		if alive_only and _is_alive_occupied(players, i):
			return i
		if not alive_only and _is_occupied(players, i):
			return i
	return -1


func _all_alive_voted(state: Dictionary, players: Array) -> bool:
	var votes: Dictionary = _as_dict(state.get("votes", {}))
	for i in range(players.size()):
		if _can_vote(players, i) and not votes.has(str(i)):
			return false
	return true


func _all_alive_wolves_voted(state: Dictionary, players: Array) -> bool:
	var has_wolf := false
	var votes: Dictionary = _as_dict(state.get("votes", {}))
	for i in range(players.size()):
		if _is_alive_wolf_kill_actor(players, i):
			has_wolf = true
			if not votes.has(str(i)):
				return false
	return has_wolf


func _all_occupied_voted(state: Dictionary, players: Array) -> bool:
	var post: Dictionary = _as_dict(state.get("post_game", {}))
	var votes: Dictionary = _as_dict(post.get("mvp_votes", {}))
	for i in range(players.size()):
		if _is_occupied(players, i) and not votes.has(str(i)):
			return false
	return true


func _mark_spoken(state: Dictionary, index: int) -> void:
	var spoken: Array = _as_array(state.get("spoken_indices", []))
	if not spoken.has(index):
		spoken.append(index)
	state["spoken_indices"] = spoken


func _all_alive_spoken(state: Dictionary, players: Array) -> bool:
	var spoken: Array = _as_array(state.get("spoken_indices", []))
	for i in range(players.size()):
		if _is_alive_occupied(players, i) and not spoken.has(i):
			return false
	return true


func _next_unspoken_alive_actor(state: Dictionary, players: Array) -> int:
	var spoken: Array = _as_array(state.get("spoken_indices", []))
	for i in range(players.size()):
		if _is_alive_occupied(players, i) and not spoken.has(i):
			return i
	return -1


func _next_unspoken_day_speaker(state: Dictionary, players: Array) -> int:
	var spoken: Array = _as_array(state.get("spoken_indices", []))
	var order: Array = _as_array(state.get("day_speech_order", []))
	if int(state.get("day_speech_order_day", 0)) == int(state.get("day", 0)) and not order.is_empty():
		for item in order:
			var index := int(item)
			if _is_alive_occupied(players, index) and not spoken.has(index):
				return index
	return _next_unspoken_alive_actor(state, players)


func _next_unspoken_alive_wolf(state: Dictionary, players: Array) -> int:
	var spoken: Array = _as_array(state.get("spoken_indices", []))
	for i in range(players.size()):
		if _is_alive_wolf_chat_actor(players, i) and not spoken.has(i):
			return i
	return -1


func _all_alive_wolves_spoken(state: Dictionary, players: Array) -> bool:
	var has_wolf := false
	var spoken: Array = _as_array(state.get("spoken_indices", []))
	for i in range(players.size()):
		if _is_alive_wolf_chat_actor(players, i):
			has_wolf = true
			if not spoken.has(i):
				return false
	return has_wolf


func _next_unvoted_alive_actor(state: Dictionary, players: Array) -> int:
	var votes: Dictionary = _as_dict(state.get("votes", {}))
	for i in range(players.size()):
		if _can_vote(players, i) and not votes.has(str(i)):
			return i
	return -1


func _next_unvoted_alive_wolf(state: Dictionary, players: Array) -> int:
	var votes: Dictionary = _as_dict(state.get("votes", {}))
	for i in range(players.size()):
		if _is_alive_wolf_kill_actor(players, i) and not votes.has(str(i)):
			return i
	return -1


func _next_mvp_voter(state: Dictionary, players: Array) -> int:
	var post: Dictionary = _as_dict(state.get("post_game", {}))
	var votes: Dictionary = _as_dict(post.get("mvp_votes", {}))
	for i in range(players.size()):
		if _is_occupied(players, i) and not votes.has(str(i)):
			return i
	return -1


func _first_alive_role(players: Array, role: String) -> int:
	for i in range(players.size()):
		if _is_alive_occupied(players, i) and String(players[i].get("role_key", "")) == role:
			return i
	return -1


func _has_alive_role(players: Array, role: String) -> bool:
	return _first_alive_role(players, role) >= 0


func _first_alive_wolf_kill_actor(players: Array) -> int:
	for i in range(players.size()):
		if _is_alive_wolf_kill_actor(players, i):
			return i
	return -1


func _has_alive_wolf_kill_actor(players: Array) -> bool:
	return _first_alive_wolf_kill_actor(players) >= 0


func _has_alive_wolf_chat_actor(players: Array) -> bool:
	for i in range(players.size()):
		if _is_alive_wolf_chat_actor(players, i):
			return true
	return false


func _is_alive_wolf_kill_actor(players: Array, index: int) -> bool:
	if not _is_alive_occupied(players, index):
		return false
	return _role_catalog.can_wolf_night_kill(String(players[index].get("role_key", "")))


func _is_alive_wolf_chat_actor(players: Array, index: int) -> bool:
	if not _is_alive_occupied(players, index):
		return false
	return _role_catalog.can_join_wolf_chat(String(players[index].get("role_key", "")))


func _first_hunter_can_shoot(players: Array) -> int:
	for i in range(players.size()):
		if _is_occupied(players, i) and String(players[i].get("role_key", "")) == "hunter" and bool(players[i].get("can_hunter_shoot", false)):
			return i
	return -1


func _pending_last_words_candidates(state: Dictionary, players: Array) -> Array:
	var used: Array = _as_array(state.get("last_words_used", []))
	var candidates: Array = []
	for i in range(players.size()):
		if _is_occupied(players, i) and not bool(players[i].get("alive", true)) and not used.has(i):
			candidates.append(i)
	return candidates


func _first_legal_target(state: Dictionary, players: Array, actor_index: int, action_key: String) -> int:
	for i in range(players.size()):
		var validation: Dictionary = _validate_target(state, players, actor_index, i, action_key)
		if bool(validation.get("ok", false)):
			return i
	return -1


func _has_alive_target_except(players: Array, actor_index: int) -> bool:
	for i in range(players.size()):
		if i != actor_index and _is_alive_occupied(players, i):
			return true
	return false


func _can_vote(players: Array, index: int) -> bool:
	if not _is_alive_occupied(players, index):
		return false
	return not bool((players[index] as Dictionary).get("idiot_revealed", false))


func _is_alive_occupied(players: Array, index: int) -> bool:
	if not _is_occupied(players, index):
		return false
	var player: Dictionary = players[index]
	return bool(player.get("alive", true))


func _is_occupied(players: Array, index: int) -> bool:
	if index < 0 or index >= players.size():
		return false
	var player: Dictionary = players[index]
	return String(player.get("owner", "")) != ""


func _occupied_indices(players: Array) -> Array:
	var indices: Array = []
	for i in range(players.size()):
		if _is_occupied(players, i):
			indices.append(i)
	return indices


func _set_player_waiting(players: Array, index: int, state_text: String) -> void:
	if index < 0 or index >= players.size():
		return
	var player: Dictionary = players[index]
	if int(player.get("motion", SeatMotion.IDLE)) != SeatMotion.DEAD:
		player["motion"] = SeatMotion.IDLE
	player["state"] = state_text
	players[index] = player


func _can_skip_action(action_key: String) -> bool:
	return action_key in ["witch_act", "hunter_shoot", "sheriff_badge_action"]


func _empty_speech_text(phase: String) -> String:
	match phase:
		"wolf_chat":
			return "（跳过狼队夜聊）"
		"last_words":
			return "（未发表遗言）"
		"post_game_summary":
			return "（跳过总结）"
		_:
			return "（跳过发言）"


func _transition_result(players: Array, state: Dictionary, history: Array, death_indices: Array, message: String) -> Dictionary:
	return {
		"players": players,
		"werewolf": state,
		"history": history,
		"death_indices": _unique_indices(death_indices),
		"message": message,
	}


func _duplicate_players(players: Array) -> Array:
	var next_players: Array = []
	for player in players:
		if player is Dictionary:
			next_players.append((player as Dictionary).duplicate(true))
		else:
			next_players.append(player)
	return next_players


func _unique_indices(indices: Array) -> Array:
	var seen: Dictionary = {}
	var unique: Array = []
	for item in indices:
		var index: int = int(item)
		if not seen.has(index):
			seen[index] = true
			unique.append(index)
	return unique


func _participant_text(players: Array, occupied_indices: Array) -> String:
	var parts: Array = []
	for item in occupied_indices:
		var index: int = int(item)
		parts.append(_player_title(players, index))
	return "游戏参与者：%s。" % "；".join(parts)


func _player_title(players: Array, index: int) -> String:
	if index >= 0 and index < players.size():
		return "%d号 %s" % [index + 1, String(players[index].get("name", ""))]
	return "主持人"


func _history(speaker: String, text: String) -> Dictionary:
	return {
		"speaker": speaker,
		"text": text,
		"visibility": "public",
		"at": Time.get_unix_time_from_system(),
	}


func _moderator_private_history(players: Array, actor_index: int, text: String, target_index: int = -1, action_key: String = "") -> Dictionary:
	var item := _history("主持人", text)
	item["visibility"] = "private"
	item["visible_to_indices"] = [actor_index]
	if actor_index >= 0:
		item["recipient_index"] = actor_index
	if target_index >= 0:
		item["target_index"] = target_index
	if action_key.strip_edges() != "":
		item["action_key"] = action_key
	return item


func _moderator_wolf_history(text: String, action_key: String = "") -> Dictionary:
	var item := _history("主持人", text)
	item["visibility"] = "wolf"
	if action_key.strip_edges() != "":
		item["action_key"] = action_key
	return item


func _actor_history(players: Array, actor_index: int, text: String, visibility: String = "public", target_index: int = -1, action_key: String = "") -> Dictionary:
	var item := _history(_player_title(players, actor_index), text)
	item["speaker_index"] = actor_index
	item["actor_index"] = actor_index
	item["visibility"] = visibility
	if target_index >= 0:
		item["target_index"] = target_index
	if action_key.strip_edges() != "":
		item["action_key"] = action_key
	if visibility == "private":
		item["visible_to_indices"] = [actor_index]
	return item


func _as_dict(value) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary)
	return {}


func _as_array(value) -> Array:
	if value is Array:
		return (value as Array)
	return []


func _error(message: String) -> Dictionary:
	return {
		"ok": false,
		"message": message,
		"history": [],
		"effect": "skip",
	}
