extends RefCounted
class_name SanguoshaRulePackCatalog

const DUEL_2P := "duel_2p"
const IDENTITY_4P := "identity_4p"
const IDENTITY_5P := "identity_5p"
const IDENTITY_6P := "identity_6p"
const IDENTITY_7P := "identity_7p"
const IDENTITY_8P := "identity_8p"
const DEFAULT_RULE_PACK_ID := DUEL_2P

const CARD_PACK_ID := "standard_108"
const GENERAL_PACK_ID := "standard_core_adult_female"
const SKILL_PACK_ID := "standard_core_skills"

const ENABLED_CARD_KEYS := [
	"slash",
	"dodge",
	"peach",
	"draw_two",
	"peach_garden",
	"arrow_barrage",
	"dismantle",
	"snatch",
	"duel",
	"barbarian_assault",
	"negate",
	"borrow_sword",
	"harvest",
	"indulgence",
	"lightning",
	"crossbow",
	"qilin_bow",
	"double_swords",
	"ice_sword",
	"green_dragon_blade",
	"blue_steel_blade",
	"serpent_spear",
	"rock_cleaving_axe",
	"halberd",
	"eight_diagram",
	"renwang_shield",
	"red_hare",
	"dayuan",
	"zixing",
	"zhuahuang_feidian",
	"jueying",
	"dilu",
]

const RULE_PACKS := {
	"duel_2p": {
		"id": "duel_2p",
		"name": "双人对决",
		"mode": "duel",
		"player_count": 2,
		"supported_player_counts": [2],
		"role_distribution": {"lord": 0, "loyalist": 0, "rebel": 0, "renegade": 0},
		"identity_sequence": ["duelist_a", "duelist_b"],
		"card_pack_id": CARD_PACK_ID,
		"general_pack_id": GENERAL_PACK_ID,
		"skill_pack_id": SKILL_PACK_ID,
		"general_offer_count": 5,
		"initial_hand_size": 4,
		"draw_count": 2,
		"lord_hp_bonus": 0,
		"enabled_card_keys": ENABLED_CARD_KEYS,
		"enabled_skill_keys": [],
		"rule_text": "2人对决，不使用隐藏身份；任一方阵亡时另一方获胜。",
	},
	"identity_4p": {
		"id": "identity_4p",
		"name": "四人身份局",
		"mode": "identity",
		"player_count": 4,
		"supported_player_counts": [4],
		"role_distribution": {"lord": 1, "loyalist": 1, "rebel": 1, "renegade": 1},
		"identity_sequence": ["lord", "loyalist", "rebel", "renegade"],
		"card_pack_id": CARD_PACK_ID,
		"general_pack_id": GENERAL_PACK_ID,
		"skill_pack_id": SKILL_PACK_ID,
		"general_offer_count": 3,
		"initial_hand_size": 4,
		"draw_count": 2,
		"lord_hp_bonus": 1,
		"enabled_card_keys": ENABLED_CARD_KEYS,
		"enabled_skill_keys": [],
		"rule_text": "4人身份局：主公1、忠臣1、反贼1、内奸1。",
	},
	"identity_5p": {
		"id": "identity_5p",
		"name": "五人身份局",
		"mode": "identity",
		"player_count": 5,
		"supported_player_counts": [5],
		"role_distribution": {"lord": 1, "loyalist": 1, "rebel": 2, "renegade": 1},
		"identity_sequence": ["lord", "loyalist", "rebel", "rebel", "renegade"],
		"card_pack_id": CARD_PACK_ID,
		"general_pack_id": GENERAL_PACK_ID,
		"skill_pack_id": SKILL_PACK_ID,
		"general_offer_count": 3,
		"initial_hand_size": 4,
		"draw_count": 2,
		"lord_hp_bonus": 1,
		"enabled_card_keys": ENABLED_CARD_KEYS,
		"enabled_skill_keys": [],
		"rule_text": "5人身份局：主公1、忠臣1、反贼2、内奸1。",
	},
	"identity_6p": {
		"id": "identity_6p",
		"name": "六人身份局",
		"mode": "identity",
		"player_count": 6,
		"supported_player_counts": [6],
		"role_distribution": {"lord": 1, "loyalist": 1, "rebel": 3, "renegade": 1},
		"identity_sequence": ["lord", "loyalist", "rebel", "rebel", "rebel", "renegade"],
		"card_pack_id": CARD_PACK_ID,
		"general_pack_id": GENERAL_PACK_ID,
		"skill_pack_id": SKILL_PACK_ID,
		"general_offer_count": 3,
		"initial_hand_size": 4,
		"draw_count": 2,
		"lord_hp_bonus": 1,
		"enabled_card_keys": ENABLED_CARD_KEYS,
		"enabled_skill_keys": [],
		"rule_text": "6人身份局：主公1、忠臣1、反贼3、内奸1。",
	},
	"identity_7p": {
		"id": "identity_7p",
		"name": "七人身份局",
		"mode": "identity",
		"player_count": 7,
		"supported_player_counts": [7],
		"role_distribution": {"lord": 1, "loyalist": 2, "rebel": 3, "renegade": 1},
		"identity_sequence": ["lord", "loyalist", "loyalist", "rebel", "rebel", "rebel", "renegade"],
		"card_pack_id": CARD_PACK_ID,
		"general_pack_id": GENERAL_PACK_ID,
		"skill_pack_id": SKILL_PACK_ID,
		"general_offer_count": 3,
		"initial_hand_size": 4,
		"draw_count": 2,
		"lord_hp_bonus": 1,
		"enabled_card_keys": ENABLED_CARD_KEYS,
		"enabled_skill_keys": [],
		"rule_text": "7人身份局：主公1、忠臣2、反贼3、内奸1。",
	},
	"identity_8p": {
		"id": "identity_8p",
		"name": "八人身份局",
		"mode": "identity",
		"player_count": 8,
		"supported_player_counts": [8],
		"role_distribution": {"lord": 1, "loyalist": 2, "rebel": 4, "renegade": 1},
		"identity_sequence": ["lord", "loyalist", "loyalist", "rebel", "rebel", "rebel", "rebel", "renegade"],
		"card_pack_id": CARD_PACK_ID,
		"general_pack_id": GENERAL_PACK_ID,
		"skill_pack_id": SKILL_PACK_ID,
		"general_offer_count": 3,
		"initial_hand_size": 4,
		"draw_count": 2,
		"lord_hp_bonus": 1,
		"enabled_card_keys": ENABLED_CARD_KEYS,
		"enabled_skill_keys": [],
		"rule_text": "8人身份局：主公1、忠臣2、反贼4、内奸1。",
	},
}


func get_rule_pack_list() -> Array:
	var result: Array = []
	for rule_pack_id in _rule_pack_order():
		var pack := get_rule_pack(String(rule_pack_id))
		if not pack.is_empty():
			result.append(pack)
	return result


func get_rule_pack(rule_pack_id: String) -> Dictionary:
	var normalized := rule_pack_id.strip_edges()
	if normalized == "":
		normalized = DEFAULT_RULE_PACK_ID
	if not RULE_PACKS.has(normalized):
		return {}
	return (RULE_PACKS[normalized] as Dictionary).duplicate(true)


func get_rule_pack_for_player_count(player_count: int) -> Dictionary:
	return get_rule_pack(rule_pack_id_for_player_count(player_count))


func rule_pack_id_for_player_count(player_count: int) -> String:
	match player_count:
		2:
			return DUEL_2P
		4:
			return IDENTITY_4P
		5:
			return IDENTITY_5P
		6:
			return IDENTITY_6P
		7:
			return IDENTITY_7P
		8:
			return IDENTITY_8P
		_:
			return ""


func supported_player_counts() -> Array:
	return [2, 4, 5, 6, 7, 8]


func role_distribution(rule_pack_id: String) -> Dictionary:
	var pack := get_rule_pack(rule_pack_id)
	if pack.is_empty():
		return {}
	return (pack.get("role_distribution", {}) as Dictionary).duplicate(true)


func identities_for_rule_pack(rule_pack_id: String) -> Array:
	var pack := get_rule_pack(rule_pack_id)
	if pack.is_empty():
		return []
	return (pack.get("identity_sequence", []) as Array).duplicate()


func role_label(role_key: String) -> String:
	match role_key:
		"lord":
			return "主公"
		"loyalist":
			return "忠臣"
		"rebel":
			return "反贼"
		"renegade":
			return "内奸"
		"duelist_a":
			return "先手"
		"duelist_b":
			return "后手"
		_:
			return "未知"


func is_identity_rule_pack(rule_pack_id: String) -> bool:
	var pack := get_rule_pack(rule_pack_id)
	return String(pack.get("mode", "")) == "identity"


func is_duel_rule_pack(rule_pack_id: String) -> bool:
	var pack := get_rule_pack(rule_pack_id)
	return String(pack.get("mode", "")) == "duel"


func _rule_pack_order() -> Array:
	return [DUEL_2P, IDENTITY_4P, IDENTITY_5P, IDENTITY_6P, IDENTITY_7P, IDENTITY_8P]
