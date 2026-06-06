extends RefCounted
class_name SanguoshaEngine

const RulePackCatalogScript := preload("res://scripts/room/sanguosha/sanguosha_rule_pack_catalog.gd")
const MapCatalogScript := preload("res://scripts/room/sanguosha/sanguosha_map_catalog.gd")
const CardCatalogScript := preload("res://scripts/room/sanguosha/sanguosha_card_catalog.gd")
const GeneralCatalogScript := preload("res://scripts/room/sanguosha/sanguosha_general_catalog.gd")

const PHASE_LOBBY := "lobby"
const PHASE_PLAY := "play"
const PHASE_RESPONSE := "response"
const PHASE_COMPLETED := "completed"

const RESULT_PLAYING := "playing"
const WINNER_DUELIST_A := "duelist_a"
const WINNER_DUELIST_B := "duelist_b"
const WINNER_LORD_CAMP := "lord_camp"
const WINNER_REBEL_CAMP := "rebel_camp"
const WINNER_RENEGADE := "renegade"

const EQUIPMENT_SLOTS := ["weapon", "armor", "attack_horse", "defense_horse"]

var _rules = RulePackCatalogScript.new()
var _maps = MapCatalogScript.new()
var _cards = CardCatalogScript.new()
var _generals = GeneralCatalogScript.new()


func default_state(options: Dictionary = {}) -> Dictionary:
	var map_id := String(options.get("map_id", MapCatalogScript.DEFAULT_MAP_ID)).strip_edges()
	if map_id == "":
		map_id = MapCatalogScript.DEFAULT_MAP_ID
	var map_data := _maps.get_map(map_id)
	var rule_pack_id := String(options.get("rule_pack_id", map_data.get("rule_pack_id", RulePackCatalogScript.DEFAULT_RULE_PACK_ID))).strip_edges()
	var rule_pack := _rules.get_rule_pack(rule_pack_id)
	return {
		"game_id": "sanguosha",
		"phase": PHASE_LOBBY,
		"started": false,
		"paused": false,
		"map_id": map_id,
		"map_name": String(map_data.get("name", "")),
		"rule_pack_id": rule_pack_id,
		"general_pack_id": String(rule_pack.get("general_pack_id", RulePackCatalogScript.GENERAL_PACK_ID)),
		"card_pack_id": String(rule_pack.get("card_pack_id", RulePackCatalogScript.CARD_PACK_ID)),
		"skill_pack_id": String(rule_pack.get("skill_pack_id", RulePackCatalogScript.SKILL_PACK_ID)),
		"round_number": 1,
		"turn_seat": 0,
		"phase_owner": 0,
		"players": [],
		"hands": [],
		"deck": [],
		"discard_pile": [],
		"equipment": [],
		"judge_area": [],
		"current_action": {},
		"response_window": {},
		"pending_damage": {},
		"dying_context": {},
		"play_limits": {},
		"enabled_card_keys": (rule_pack.get("enabled_card_keys", []) as Array).duplicate(),
		"enabled_skill_keys": (rule_pack.get("enabled_skill_keys", []) as Array).duplicate(),
		"event_log": [],
		"winner": "",
		"game_result": RESULT_PLAYING,
		"result_reason": "",
	}


func start_state(player_count: int = 2, map_id: String = "", options: Dictionary = {}) -> Dictionary:
	var normalized_map_id := map_id.strip_edges()
	if normalized_map_id == "":
		normalized_map_id = _map_id_for_player_count(player_count)
	var map_data := _maps.get_map(normalized_map_id)
	if map_data.is_empty():
		return _setup_error_state(player_count, normalized_map_id, "invalid_map", "三国杀地图不存在")
	var supported_counts := _maps.get_supported_player_counts(normalized_map_id)
	if not supported_counts.has(player_count):
		return _setup_error_state(player_count, normalized_map_id, "unsupported_player_count", "该三国杀地图不支持当前人数")
	var rule_pack_id := String(map_data.get("rule_pack_id", ""))
	var rule_pack := _rules.get_rule_pack(rule_pack_id)
	if rule_pack.is_empty():
		return _setup_error_state(player_count, normalized_map_id, "invalid_rule_pack", "三国杀规则包不存在")

	var general_pack_id := String(rule_pack.get("general_pack_id", RulePackCatalogScript.GENERAL_PACK_ID))
	var card_pack_id := String(rule_pack.get("card_pack_id", RulePackCatalogScript.CARD_PACK_ID))
	var general_pool := _generals.generals(general_pack_id)
	var offer_count := int(rule_pack.get("general_offer_count", 3))
	if general_pool.size() < player_count:
		return _setup_error_state(player_count, normalized_map_id, "not_enough_generals", "三国杀武将数量不足")
	if general_pool.size() < player_count * offer_count:
		offer_count = max(1, int(floor(float(general_pool.size()) / float(maxi(player_count, 1)))))

	var state := default_state({"map_id": normalized_map_id, "rule_pack_id": rule_pack_id})
	state["phase"] = PHASE_PLAY
	state["started"] = true
	state["map_id"] = normalized_map_id
	state["map_name"] = String(map_data.get("name", ""))
	state["rule_pack_id"] = rule_pack_id
	state["general_pack_id"] = general_pack_id
	state["card_pack_id"] = card_pack_id
	state["skill_pack_id"] = String(rule_pack.get("skill_pack_id", RulePackCatalogScript.SKILL_PACK_ID))
	state["enabled_card_keys"] = (rule_pack.get("enabled_card_keys", []) as Array).duplicate()
	state["enabled_skill_keys"] = (rule_pack.get("enabled_skill_keys", []) as Array).duplicate()

	var identities := _rules.identities_for_rule_pack(rule_pack_id)
	var offers := _general_offers(general_pool, player_count, offer_count)
	var players: Array = []
	var hands: Array = []
	var equipment: Array = []
	var judge_area: Array = []
	for seat_index in range(player_count):
		var role_key := String(identities[seat_index])
		var general_options: Array = offers[seat_index] if seat_index < offers.size() else []
		var selected_general: Dictionary = general_options[0] if not general_options.is_empty() else general_pool[seat_index]
		var max_hp := int(selected_general.get("max_hp", 4))
		if role_key == "lord":
			max_hp += int(rule_pack.get("lord_hp_bonus", 1))
		players.append({
			"seat_index": seat_index,
			"name": "%d号位" % [seat_index + 1],
			"identity": role_key,
			"identity_name": _rules.role_label(role_key),
			"identity_visible": role_key == "lord" or rule_pack_id == RulePackCatalogScript.DUEL_2P,
			"general_id": String(selected_general.get("general_id", "")),
			"general_name": String(selected_general.get("name", "")),
			"general_options": _general_option_ids(general_options),
			"kingdom": String(selected_general.get("kingdom", "")),
			"rules_gender": String(selected_general.get("rules_gender", "")),
			"skills": (selected_general.get("skills", []) as Array).duplicate(),
			"max_hp": max_hp,
			"hp": max_hp,
			"alive": true,
			"hand_count": 0,
			"equipment_count": 0,
		})
		hands.append([])
		equipment.append(_empty_equipment())
		judge_area.append([])
	state["players"] = players
	state["hands"] = hands
	state["equipment"] = equipment
	state["judge_area"] = judge_area
	state["deck"] = _build_deck(card_pack_id, options)
	state["discard_pile"] = []
	state["play_limits"] = {"turn_seat": 0, "slash_count": 0}
	state["turn_seat"] = 0
	state["phase_owner"] = 0

	var initial_hand_size := int(rule_pack.get("initial_hand_size", 4))
	for _card_index in range(initial_hand_size):
		for seat_index in range(player_count):
			_draw_cards(state, seat_index, 1)
	_update_all_public_counts(state)
	state["event_log"] = [{
		"event": "game_started",
		"map_id": normalized_map_id,
		"rule_pack_id": rule_pack_id,
		"player_count": player_count,
		"at": Time.get_unix_time_from_system(),
	}]
	state["current_action"] = _play_action_request(state, 0)
	return state


func legal_actions(state: Dictionary, seat_index: int) -> Array:
	if _game_over(state) or not bool(state.get("started", false)):
		return []
	if seat_index < 0 or seat_index >= _players(state).size():
		return []
	if not _is_alive(state, seat_index):
		return []
	var response_window: Dictionary = state.get("response_window", {})
	if not response_window.is_empty():
		return _legal_response_actions(state, seat_index, response_window)
	if String(state.get("phase", "")) != PHASE_PLAY:
		return []
	if int(state.get("turn_seat", -1)) != seat_index:
		return []
	return _legal_play_actions(state, seat_index)


func apply_action(state: Dictionary, seat_index: int, action: Dictionary) -> Dictionary:
	if _game_over(state):
		return _error("game_over", "牌局已结束")
	if not bool(state.get("started", false)):
		return _error("not_started", "牌局未开始")
	if seat_index < 0 or seat_index >= _players(state).size():
		return _error("invalid_seat", "无效座位")
	if not _is_alive(state, seat_index):
		return _error("dead_player", "阵亡角色不能行动")
	var legal := _resolve_legal_action(state, seat_index, action)
	if legal.is_empty():
		return _error("illegal_action", "三国杀行动不合法")
	var action_type := String(legal.get("action_type", ""))
	match action_type:
		"end_play":
			return _apply_end_play(state, seat_index)
		"play_card":
			return _apply_play_card(state, seat_index, legal)
		"respond_card":
			return _apply_respond_card(state, seat_index, legal)
		"pass":
			return _apply_pass(state, seat_index, legal)
		_:
			return _error("unknown_action", "未知三国杀行动")


func distance_between(state: Dictionary, from_seat: int, to_seat: int) -> int:
	var players := _players(state)
	var total: int = players.size()
	if from_seat == to_seat or from_seat < 0 or to_seat < 0 or from_seat >= total or to_seat >= total:
		return 0
	var diff: int = abs(from_seat - to_seat)
	var base_distance: int = mini(diff, total - diff)
	var distance: int = base_distance + _attack_distance_delta(state, from_seat) + _defense_distance_delta(state, to_seat)
	return maxi(1, distance)


func attack_range(state: Dictionary, seat_index: int) -> int:
	var weapon := _equipment_card(state, seat_index, "weapon")
	if weapon.is_empty():
		return 1
	var metadata: Dictionary = weapon.get("metadata", {})
	return maxi(1, int(metadata.get("range", 1)))


func card_in_hand(state: Dictionary, seat_index: int, card_key: String) -> Dictionary:
	for card_value in _hand(state, seat_index):
		var card: Dictionary = card_value
		if String(card.get("card_key", "")) == card_key:
			return card.duplicate(true)
	return {}


func card_by_id_in_hand(state: Dictionary, seat_index: int, card_id: String) -> Dictionary:
	for card_value in _hand(state, seat_index):
		var card: Dictionary = card_value
		if String(card.get("card_id", "")) == card_id:
			return card.duplicate(true)
	return {}


func _legal_play_actions(state: Dictionary, seat_index: int) -> Array:
	var actions: Array = [{
		"action_id": "a_end_play",
		"action_type": "end_play",
		"card_ids": [],
		"target_seats": [],
		"label": "结束出牌",
		"score_hint": 0,
		"tags": ["phase"],
	}]
	for card_value in _hand(state, seat_index):
		var card: Dictionary = card_value
		var card_id := String(card.get("card_id", ""))
		var card_key := String(card.get("card_key", ""))
		var card_name := String(card.get("name", card_key))
		if card_key == "slash":
			if not _can_use_slash(state, seat_index):
				continue
			for target_seat in _slash_targets(state, seat_index):
				actions.append({
					"action_id": "a_play_%s_t_%d" % [card_id, target_seat],
					"action_type": "play_card",
					"card_ids": [card_id],
					"target_seats": [target_seat],
					"card_key": card_key,
					"label": "使用%s -> %d号位" % [card_name, target_seat + 1],
					"score_hint": 70,
					"tags": ["damage", "slash"],
				})
		elif card_key == "draw_two":
			actions.append({
				"action_id": "a_play_%s" % card_id,
				"action_type": "play_card",
				"card_ids": [card_id],
				"target_seats": [seat_index],
				"card_key": card_key,
				"label": "使用%s" % card_name,
				"score_hint": 90,
				"tags": ["draw", "trick"],
			})
		elif card_key == "peach" and _player_hp(state, seat_index) < _player_max_hp(state, seat_index):
			actions.append({
				"action_id": "a_play_%s" % card_id,
				"action_type": "play_card",
				"card_ids": [card_id],
				"target_seats": [seat_index],
				"card_key": card_key,
				"label": "使用%s" % card_name,
				"score_hint": 80,
				"tags": ["heal", "self"],
			})
		elif card_key == "peach_garden" and _any_wounded(state):
			actions.append({
				"action_id": "a_play_%s" % card_id,
				"action_type": "play_card",
				"card_ids": [card_id],
				"target_seats": _alive_seats(state),
				"card_key": card_key,
				"label": "使用%s" % card_name,
				"score_hint": 35,
				"tags": ["heal", "trick"],
			})
		elif _equipment_slot(card) != "":
			actions.append({
				"action_id": "a_play_%s" % card_id,
				"action_type": "play_card",
				"card_ids": [card_id],
				"target_seats": [seat_index],
				"card_key": card_key,
				"label": "装备%s" % card_name,
				"score_hint": _equip_score_hint(card),
				"tags": ["equip", _equipment_slot(card)],
			})
	return actions


func _legal_response_actions(state: Dictionary, seat_index: int, response_window: Dictionary) -> Array:
	if int(response_window.get("target_seat", -1)) != seat_index:
		return []
	var required: Array = response_window.get("required_card_keys", [])
	var actions: Array = []
	for card_key_value in required:
		var card_key := String(card_key_value)
		for card_value in _hand(state, seat_index):
			var card: Dictionary = card_value
			if String(card.get("card_key", "")) != card_key:
				continue
			var card_id := String(card.get("card_id", ""))
			actions.append({
				"action_id": "a_respond_%s" % card_id,
				"action_type": "respond_card",
				"card_ids": [card_id],
				"target_seats": [int(response_window.get("source_seat", -1))],
				"card_key": card_key,
				"label": "打出%s" % String(card.get("name", card_key)),
				"score_hint": 60,
				"tags": ["response", card_key],
			})
	actions.append({
		"action_id": "a_pass_response",
		"action_type": "pass",
		"card_ids": [],
		"target_seats": [],
		"label": "不响应",
		"score_hint": -10,
		"tags": ["response", "default"],
	})
	return actions


func _apply_end_play(state: Dictionary, seat_index: int) -> Dictionary:
	var next := state.duplicate(true)
	var next_seat := _next_alive_seat(next, seat_index)
	if next_seat < 0:
		_apply_win_conditions(next)
		return {"ok": true, "state": next}
	if next_seat <= seat_index:
		next["round_number"] = int(next.get("round_number", 1)) + 1
	next["turn_seat"] = next_seat
	next["phase_owner"] = next_seat
	next["phase"] = PHASE_PLAY
	next["response_window"] = {}
	next["pending_damage"] = {}
	next["play_limits"] = {"turn_seat": next_seat, "slash_count": 0}
	var rule_pack := _rules.get_rule_pack(String(next.get("rule_pack_id", "")))
	_draw_cards(next, next_seat, int(rule_pack.get("draw_count", 2)))
	_append_event(next, {
		"event": "turn_started",
		"seat_index": next_seat,
		"round_number": int(next.get("round_number", 1)),
		"draw_count": int(rule_pack.get("draw_count", 2)),
	})
	next["current_action"] = _play_action_request(next, next_seat)
	return {"ok": true, "state": next}


func _apply_play_card(state: Dictionary, seat_index: int, action: Dictionary) -> Dictionary:
	var card_ids: Array = action.get("card_ids", [])
	if card_ids.is_empty():
		return _error("missing_card", "缺少要使用的牌")
	var card_id := String(card_ids[0])
	var next := state.duplicate(true)
	var taken := _take_card_from_hand(next, seat_index, card_id)
	if not bool(taken.get("ok", false)):
		return _error("missing_card", "手牌中没有这张牌")
	var card: Dictionary = taken.get("card", {})
	var card_key := String(card.get("card_key", ""))
	if card_key == "slash":
		return _play_slash(next, seat_index, card, action)
	if card_key == "draw_two":
		_discard_card(next, card)
		_draw_cards(next, seat_index, 2)
		_append_event(next, {"event": "card_played", "seat_index": seat_index, "card": _public_card(card), "effect": "draw_two", "draw_count": 2})
		next["current_action"] = _play_action_request(next, seat_index)
		return {"ok": true, "state": next}
	if card_key == "peach":
		_discard_card(next, card)
		_heal(next, seat_index, 1)
		_append_event(next, {"event": "card_played", "seat_index": seat_index, "card": _public_card(card), "effect": "heal", "amount": 1})
		next["current_action"] = _play_action_request(next, seat_index)
		return {"ok": true, "state": next}
	if card_key == "peach_garden":
		_discard_card(next, card)
		var healed: Array = []
		for target_seat in _alive_seats(next):
			if _player_hp(next, target_seat) < _player_max_hp(next, target_seat):
				_heal(next, target_seat, 1)
				healed.append(target_seat)
		_append_event(next, {"event": "card_played", "seat_index": seat_index, "card": _public_card(card), "effect": "peach_garden", "healed_seats": healed})
		next["current_action"] = _play_action_request(next, seat_index)
		return {"ok": true, "state": next}
	if _equipment_slot(card) != "":
		_equip_card(next, seat_index, card)
		next["current_action"] = _play_action_request(next, seat_index)
		return {"ok": true, "state": next}
	return _error("unsupported_card", "当前规则骨架还没有实现这张牌")


func _play_slash(next: Dictionary, seat_index: int, card: Dictionary, action: Dictionary) -> Dictionary:
	var targets: Array = action.get("target_seats", [])
	if targets.size() != 1:
		return _error("invalid_target", "杀必须指定一个目标")
	var target_seat := int(targets[0])
	_discard_card(next, card)
	var limits: Dictionary = next.get("play_limits", {})
	limits["turn_seat"] = seat_index
	limits["slash_count"] = int(limits.get("slash_count", 0)) + 1
	next["play_limits"] = limits
	next["phase"] = PHASE_RESPONSE
	next["phase_owner"] = target_seat
	next["pending_damage"] = {
		"source_seat": seat_index,
		"target_seat": target_seat,
		"amount": 1,
		"card": _public_card(card),
		"reason": "slash",
	}
	next["response_window"] = {
		"window_id": "rw_%d_%s" % [Time.get_ticks_usec(), String(card.get("card_id", ""))],
		"kind": "dodge_slash",
		"source_seat": seat_index,
		"target_seat": target_seat,
		"responders": [target_seat],
		"cursor": 0,
		"required_card_keys": ["dodge"],
		"context": {
			"card": _public_card(card),
			"damage": 1,
			"return_phase": PHASE_PLAY,
			"return_seat": seat_index,
		},
		"default_action": {"action_type": "pass"},
		"result": {},
	}
	_append_event(next, {"event": "card_played", "seat_index": seat_index, "target_seat": target_seat, "card": _public_card(card), "effect": "slash"})
	next["current_action"] = _response_action_request(next, target_seat)
	return {"ok": true, "state": next}


func _apply_respond_card(state: Dictionary, seat_index: int, action: Dictionary) -> Dictionary:
	var response_window: Dictionary = state.get("response_window", {})
	if response_window.is_empty():
		return _error("no_response_window", "当前没有响应窗口")
	var card_ids: Array = action.get("card_ids", [])
	if card_ids.is_empty():
		return _error("missing_card", "缺少响应牌")
	var next := state.duplicate(true)
	var taken := _take_card_from_hand(next, seat_index, String(card_ids[0]))
	if not bool(taken.get("ok", false)):
		return _error("missing_card", "手牌中没有这张响应牌")
	var card: Dictionary = taken.get("card", {})
	_discard_card(next, card)
	_append_event(next, {"event": "card_responded", "seat_index": seat_index, "card": _public_card(card), "window_id": String(response_window.get("window_id", ""))})
	if String(response_window.get("kind", "")) == "dodge_slash" and String(card.get("card_key", "")) == "dodge":
		next["response_window"] = {}
		next["pending_damage"] = {}
		next["phase"] = PHASE_PLAY
		next["phase_owner"] = int(response_window.get("source_seat", next.get("turn_seat", 0)))
		next["current_action"] = _play_action_request(next, int(next.get("turn_seat", 0)))
		return {"ok": true, "state": next}
	return _error("unsupported_response", "当前响应牌不能结算这个窗口")


func _apply_pass(state: Dictionary, seat_index: int, _action: Dictionary) -> Dictionary:
	var response_window: Dictionary = state.get("response_window", {})
	if response_window.is_empty():
		return _error("no_response_window", "当前没有响应窗口")
	if int(response_window.get("target_seat", -1)) != seat_index:
		return _error("wrong_responder", "当前不是该座位响应")
	var next := state.duplicate(true)
	_append_event(next, {"event": "response_passed", "seat_index": seat_index, "window_id": String(response_window.get("window_id", "")), "kind": String(response_window.get("kind", ""))})
	if String(response_window.get("kind", "")) == "dodge_slash":
		var damage: Dictionary = next.get("pending_damage", {})
		next["response_window"] = {}
		next["pending_damage"] = {}
		_apply_damage(next, int(damage.get("source_seat", -1)), int(damage.get("target_seat", seat_index)), int(damage.get("amount", 1)), String(damage.get("reason", "slash")), damage.get("card", {}))
		if not _game_over(next):
			next["phase"] = PHASE_PLAY
			next["phase_owner"] = int(response_window.get("source_seat", next.get("turn_seat", 0)))
			next["current_action"] = _play_action_request(next, int(next.get("turn_seat", 0)))
		return {"ok": true, "state": next}
	return _error("unsupported_pass", "当前响应窗口不能跳过")


func _resolve_legal_action(state: Dictionary, seat_index: int, action: Dictionary) -> Dictionary:
	var action_id := String(action.get("action_id", "")).strip_edges()
	var action_type := String(action.get("action_type", "")).strip_edges()
	var card_ids: Array = action.get("card_ids", [])
	var target_seats: Array = action.get("target_seats", [])
	for legal_value in legal_actions(state, seat_index):
		var legal: Dictionary = legal_value
		if action_id != "" and String(legal.get("action_id", "")) == action_id:
			return legal.duplicate(true)
		if action_type == "" or String(legal.get("action_type", "")) != action_type:
			continue
		if _string_array(legal.get("card_ids", [])) != _string_array(card_ids):
			continue
		if _int_array(legal.get("target_seats", [])) != _int_array(target_seats):
			continue
		return legal.duplicate(true)
	return {}


func _can_use_slash(state: Dictionary, seat_index: int) -> bool:
	if _has_skill(state, seat_index, "paoxiao"):
		return true
	var weapon := _equipment_card(state, seat_index, "weapon")
	if String(weapon.get("card_key", "")) == "crossbow":
		return true
	var limits: Dictionary = state.get("play_limits", {})
	return int(limits.get("slash_count", 0)) < 1


func _slash_targets(state: Dictionary, seat_index: int) -> Array:
	var result: Array = []
	var range_limit := attack_range(state, seat_index)
	for target_seat in _alive_seats(state):
		if target_seat == seat_index:
			continue
		if distance_between(state, seat_index, target_seat) <= range_limit:
			result.append(target_seat)
	return result


func _apply_damage(state: Dictionary, source_seat: int, target_seat: int, amount: int, reason: String, card_data) -> void:
	if target_seat < 0 or target_seat >= _players(state).size() or not _is_alive(state, target_seat):
		return
	var players := _players(state)
	var player: Dictionary = players[target_seat]
	player["hp"] = int(player.get("hp", 0)) - maxi(1, amount)
	players[target_seat] = player
	state["players"] = players
	_append_event(state, {"event": "damage", "source_seat": source_seat, "target_seat": target_seat, "amount": maxi(1, amount), "reason": reason, "card": card_data})
	if int(player.get("hp", 0)) <= 0:
		_mark_dead(state, target_seat, source_seat, reason)
	_apply_win_conditions(state)


func _mark_dead(state: Dictionary, target_seat: int, source_seat: int, reason: String) -> void:
	var players := _players(state)
	var player: Dictionary = players[target_seat]
	player["hp"] = 0
	player["alive"] = false
	players[target_seat] = player
	state["players"] = players
	_append_event(state, {"event": "death", "seat_index": target_seat, "source_seat": source_seat, "reason": reason, "identity": String(player.get("identity", ""))})


func _apply_win_conditions(state: Dictionary) -> void:
	if _game_over(state):
		return
	var rule_pack_id := String(state.get("rule_pack_id", ""))
	if _rules.is_duel_rule_pack(rule_pack_id):
		var players := _players(state)
		if players.size() < 2:
			return
		if not _is_alive(state, 0) and _is_alive(state, 1):
			_complete_game(state, WINNER_DUELIST_B, "duel_enemy_dead")
		elif not _is_alive(state, 1) and _is_alive(state, 0):
			_complete_game(state, WINNER_DUELIST_A, "duel_enemy_dead")
		return
	if not _rules.is_identity_rule_pack(rule_pack_id):
		return
	var lord_alive := false
	var rebel_alive := false
	var renegade_alive := false
	var loyal_or_lord_alive := false
	var alive_count := 0
	var alive_identity := ""
	for player_value in _players(state):
		var player: Dictionary = player_value
		if not bool(player.get("alive", false)):
			continue
		alive_count += 1
		alive_identity = String(player.get("identity", ""))
		match alive_identity:
			"lord":
				lord_alive = true
				loyal_or_lord_alive = true
			"loyalist":
				loyal_or_lord_alive = true
			"rebel":
				rebel_alive = true
			"renegade":
				renegade_alive = true
	if not lord_alive:
		if alive_count == 1 and alive_identity == "renegade":
			_complete_game(state, WINNER_RENEGADE, "renegade_killed_lord_last")
		else:
			_complete_game(state, WINNER_REBEL_CAMP, "lord_dead")
	elif lord_alive and loyal_or_lord_alive and not rebel_alive and not renegade_alive:
		_complete_game(state, WINNER_LORD_CAMP, "enemies_eliminated")


func _complete_game(state: Dictionary, winner: String, reason: String) -> void:
	state["winner"] = winner
	state["game_result"] = winner
	state["phase"] = PHASE_COMPLETED
	state["result_reason"] = reason
	state["current_action"] = {}
	state["response_window"] = {}
	state["pending_damage"] = {}
	_append_event(state, {"event": "game_completed", "winner": winner, "reason": reason})


func _draw_cards(state: Dictionary, seat_index: int, count: int) -> void:
	if seat_index < 0 or seat_index >= _hands(state).size():
		return
	var deck: Array = state.get("deck", [])
	var hands := _hands(state)
	var hand: Array = hands[seat_index]
	var drawn := 0
	for _i in range(maxi(0, count)):
		if deck.is_empty():
			break
		var card: Dictionary = deck[0]
		deck.remove_at(0)
		hand.append(card)
		drawn += 1
	hands[seat_index] = hand
	state["deck"] = deck
	state["hands"] = hands
	_update_public_hand_count(state, seat_index)
	if drawn > 0:
		_append_event(state, {"event": "cards_drawn", "seat_index": seat_index, "count": drawn})


func _take_card_from_hand(state: Dictionary, seat_index: int, card_id: String) -> Dictionary:
	var hands := _hands(state)
	if seat_index < 0 or seat_index >= hands.size():
		return {"ok": false}
	var hand: Array = hands[seat_index]
	for i in range(hand.size()):
		if not (hand[i] is Dictionary):
			continue
		var card: Dictionary = hand[i]
		if String(card.get("card_id", "")) == card_id:
			hand.remove_at(i)
			hands[seat_index] = hand
			state["hands"] = hands
			_update_public_hand_count(state, seat_index)
			return {"ok": true, "card": card.duplicate(true)}
	return {"ok": false}


func _discard_card(state: Dictionary, card: Dictionary) -> void:
	var discard: Array = state.get("discard_pile", [])
	discard.append(card.duplicate(true))
	state["discard_pile"] = discard


func _equip_card(state: Dictionary, seat_index: int, card: Dictionary) -> void:
	var slot := _equipment_slot(card)
	if slot == "":
		return
	var equipment := _equipment(state)
	var seat_equipment: Dictionary = equipment[seat_index]
	var replaced: Dictionary = seat_equipment.get(slot, {})
	if not replaced.is_empty():
		_discard_card(state, replaced)
		_append_event(state, {"event": "equipment_replaced", "seat_index": seat_index, "slot": slot, "old_card": _public_card(replaced)})
	seat_equipment[slot] = card.duplicate(true)
	equipment[seat_index] = seat_equipment
	state["equipment"] = equipment
	_update_public_equipment_count(state, seat_index)
	_append_event(state, {"event": "card_played", "seat_index": seat_index, "card": _public_card(card), "effect": "equip", "slot": slot})


func _heal(state: Dictionary, seat_index: int, amount: int) -> void:
	var players := _players(state)
	if seat_index < 0 or seat_index >= players.size():
		return
	var player: Dictionary = players[seat_index]
	var old_hp := int(player.get("hp", 0))
	player["hp"] = mini(int(player.get("max_hp", old_hp)), old_hp + maxi(1, amount))
	players[seat_index] = player
	state["players"] = players
	_append_event(state, {"event": "healed", "seat_index": seat_index, "amount": int(player.get("hp", 0)) - old_hp})


func _play_action_request(state: Dictionary, seat_index: int) -> Dictionary:
	return {
		"request_id": "play_%d_%d" % [seat_index, Time.get_ticks_usec()],
		"seat_index": seat_index,
		"request_type": "play_phase",
		"current_question": "请选择出牌或结束出牌",
		"legal_actions": legal_actions(state, seat_index),
		"default_action": {"action_id": "a_end_play", "action_type": "end_play"},
	}


func _response_action_request(state: Dictionary, seat_index: int) -> Dictionary:
	return {
		"request_id": "response_%d_%d" % [seat_index, Time.get_ticks_usec()],
		"seat_index": seat_index,
		"request_type": "respond_card",
		"current_question": "请选择响应牌或不响应",
		"legal_actions": legal_actions(state, seat_index),
		"default_action": {"action_id": "a_pass_response", "action_type": "pass"},
	}


func _build_deck(card_pack_id: String, options: Dictionary) -> Array:
	var deck: Array = []
	var templates := _cards.cards(card_pack_id)
	for i in range(templates.size()):
		var card: Dictionary = templates[i]
		var game_card := card.duplicate(true)
		game_card["card_id"] = "c_%03d" % [i + 1]
		game_card["pack_id"] = card_pack_id
		deck.append(game_card)
	deck = _deck_with_front_template_ids(deck, options.get("deck_front_template_ids", []))
	deck = _deck_with_front_card_keys(deck, options.get("deck_front_card_keys", []))
	return deck


func _deck_with_front_template_ids(deck: Array, template_ids_value) -> Array:
	if not (template_ids_value is Array):
		return deck
	var template_ids: Array = template_ids_value
	for i in range(template_ids.size() - 1, -1, -1):
		var template_id := String(template_ids[i])
		for deck_index in range(deck.size()):
			var card: Dictionary = deck[deck_index]
			if String(card.get("template_id", "")) == template_id:
				deck.remove_at(deck_index)
				deck.push_front(card)
				break
	return deck


func _deck_with_front_card_keys(deck: Array, card_keys_value) -> Array:
	if not (card_keys_value is Array):
		return deck
	var card_keys: Array = card_keys_value
	for i in range(card_keys.size() - 1, -1, -1):
		var card_key := String(card_keys[i])
		for deck_index in range(deck.size()):
			var card: Dictionary = deck[deck_index]
			if String(card.get("card_key", "")) == card_key:
				deck.remove_at(deck_index)
				deck.push_front(card)
				break
	return deck


func _general_offers(general_pool: Array, player_count: int, offer_count: int) -> Array:
	var offers: Array = []
	var cursor := 0
	for _seat_index in range(player_count):
		var seat_options: Array = []
		for _i in range(offer_count):
			if cursor >= general_pool.size():
				break
			var general: Dictionary = general_pool[cursor]
			seat_options.append(general.duplicate(true))
			cursor += 1
		if seat_options.is_empty() and not general_pool.is_empty():
			seat_options.append((general_pool[0] as Dictionary).duplicate(true))
		offers.append(seat_options)
	return offers


func _general_option_ids(general_options: Array) -> Array:
	var result: Array = []
	for general_value in general_options:
		var general: Dictionary = general_value
		result.append(String(general.get("general_id", "")))
	return result


func _map_id_for_player_count(player_count: int) -> String:
	match player_count:
		2:
			return "sanguosha_duel_2p"
		4:
			return "sanguosha_identity_4p"
		5:
			return "sanguosha_identity_5p"
		6:
			return "sanguosha_identity_6p"
		7:
			return "sanguosha_identity_7p"
		8:
			return "sanguosha_identity_8p"
		_:
			return MapCatalogScript.DEFAULT_MAP_ID


func _setup_error_state(player_count: int, map_id: String, code: String, message: String) -> Dictionary:
	var state := default_state({"map_id": map_id})
	state["setup_error"] = {"code": code, "message": message, "player_count": player_count}
	return state


func _players(state: Dictionary) -> Array:
	var value = state.get("players", [])
	return value if value is Array else []


func _hands(state: Dictionary) -> Array:
	var value = state.get("hands", [])
	return value if value is Array else []


func _equipment(state: Dictionary) -> Array:
	var value = state.get("equipment", [])
	return value if value is Array else []


func _hand(state: Dictionary, seat_index: int) -> Array:
	var hands := _hands(state)
	if seat_index < 0 or seat_index >= hands.size() or not (hands[seat_index] is Array):
		return []
	return (hands[seat_index] as Array).duplicate(true)


func _equipment_card(state: Dictionary, seat_index: int, slot: String) -> Dictionary:
	var equipment := _equipment(state)
	if seat_index < 0 or seat_index >= equipment.size() or not (equipment[seat_index] is Dictionary):
		return {}
	var seat_equipment: Dictionary = equipment[seat_index]
	var card_value = seat_equipment.get(slot, {})
	return (card_value as Dictionary).duplicate(true) if card_value is Dictionary else {}


func _empty_equipment() -> Dictionary:
	return {"weapon": {}, "armor": {}, "attack_horse": {}, "defense_horse": {}}


func _equipment_slot(card: Dictionary) -> String:
	var subtype := String(card.get("subtype", ""))
	if EQUIPMENT_SLOTS.has(subtype):
		return subtype
	return ""


func _equip_score_hint(card: Dictionary) -> int:
	match _equipment_slot(card):
		"weapon":
			return 65
		"attack_horse":
			return 50
		"defense_horse":
			return 45
		"armor":
			return 40
		_:
			return 20


func _attack_distance_delta(state: Dictionary, seat_index: int) -> int:
	var delta := 0
	var horse := _equipment_card(state, seat_index, "attack_horse")
	if not horse.is_empty():
		var metadata: Dictionary = horse.get("metadata", {})
		delta += int(metadata.get("distance_to_others_delta", -1))
	if _has_skill(state, seat_index, "mashu"):
		delta -= 1
	return delta


func _defense_distance_delta(state: Dictionary, seat_index: int) -> int:
	var horse := _equipment_card(state, seat_index, "defense_horse")
	if horse.is_empty():
		return 0
	var metadata: Dictionary = horse.get("metadata", {})
	return int(metadata.get("distance_from_others_delta", 1))


func _has_skill(state: Dictionary, seat_index: int, skill_key: String) -> bool:
	var players := _players(state)
	if seat_index < 0 or seat_index >= players.size():
		return false
	var player: Dictionary = players[seat_index]
	var skills: Array = player.get("skills", [])
	return skills.has(skill_key)


func _player_hp(state: Dictionary, seat_index: int) -> int:
	var players := _players(state)
	if seat_index < 0 or seat_index >= players.size():
		return 0
	var player: Dictionary = players[seat_index]
	return int(player.get("hp", 0))


func _player_max_hp(state: Dictionary, seat_index: int) -> int:
	var players := _players(state)
	if seat_index < 0 or seat_index >= players.size():
		return 0
	var player: Dictionary = players[seat_index]
	return int(player.get("max_hp", 0))


func _is_alive(state: Dictionary, seat_index: int) -> bool:
	var players := _players(state)
	if seat_index < 0 or seat_index >= players.size():
		return false
	var player: Dictionary = players[seat_index]
	return bool(player.get("alive", false))


func _alive_seats(state: Dictionary) -> Array:
	var result: Array = []
	var players := _players(state)
	for i in range(players.size()):
		var player: Dictionary = players[i]
		if bool(player.get("alive", false)):
			result.append(i)
	return result


func _next_alive_seat(state: Dictionary, seat_index: int) -> int:
	var players := _players(state)
	if players.is_empty():
		return -1
	for step in range(1, players.size() + 1):
		var candidate := (seat_index + step) % players.size()
		if _is_alive(state, candidate):
			return candidate
	return -1


func _any_wounded(state: Dictionary) -> bool:
	for seat_index in _alive_seats(state):
		if _player_hp(state, seat_index) < _player_max_hp(state, seat_index):
			return true
	return false


func _update_all_public_counts(state: Dictionary) -> void:
	for seat_index in range(_players(state).size()):
		_update_public_hand_count(state, seat_index)
		_update_public_equipment_count(state, seat_index)


func _update_public_hand_count(state: Dictionary, seat_index: int) -> void:
	var players := _players(state)
	var hands := _hands(state)
	if seat_index < 0 or seat_index >= players.size() or seat_index >= hands.size():
		return
	var player: Dictionary = players[seat_index]
	var hand: Array = hands[seat_index]
	player["hand_count"] = hand.size()
	players[seat_index] = player
	state["players"] = players


func _update_public_equipment_count(state: Dictionary, seat_index: int) -> void:
	var players := _players(state)
	var equipment := _equipment(state)
	if seat_index < 0 or seat_index >= players.size() or seat_index >= equipment.size():
		return
	var seat_equipment: Dictionary = equipment[seat_index]
	var count := 0
	for slot in EQUIPMENT_SLOTS:
		var card_value = seat_equipment.get(String(slot), {})
		if card_value is Dictionary and not (card_value as Dictionary).is_empty():
			count += 1
	var player: Dictionary = players[seat_index]
	player["equipment_count"] = count
	players[seat_index] = player
	state["players"] = players


func _public_card(card: Dictionary) -> Dictionary:
	return {
		"card_id": String(card.get("card_id", "")),
		"template_id": String(card.get("template_id", "")),
		"card_key": String(card.get("card_key", "")),
		"name": String(card.get("name", "")),
		"suit": String(card.get("suit", "")),
		"rank": String(card.get("rank", "")),
		"type": String(card.get("type", "")),
		"subtype": String(card.get("subtype", "")),
		"metadata": (card.get("metadata", {}) as Dictionary).duplicate(true),
	}


func _append_event(state: Dictionary, event: Dictionary) -> void:
	var event_log: Array = state.get("event_log", [])
	var item := event.duplicate(true)
	if not item.has("at"):
		item["at"] = Time.get_unix_time_from_system()
	event_log.append(item)
	state["event_log"] = event_log


func _game_over(state: Dictionary) -> bool:
	return String(state.get("phase", "")) == PHASE_COMPLETED or String(state.get("winner", "")) != ""


func _string_array(value) -> Array:
	if not (value is Array):
		return []
	var result: Array = []
	for item in value:
		result.append(String(item))
	return result


func _int_array(value) -> Array:
	if not (value is Array):
		return []
	var result: Array = []
	for item in value:
		result.append(int(item))
	return result


func _error(code: String, message: String) -> Dictionary:
	return {"ok": false, "error": code, "message": message}
