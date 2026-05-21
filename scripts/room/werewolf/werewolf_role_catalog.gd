extends RefCounted
class_name WerewolfRoleCatalog

const TEAM_GOOD := "good"
const TEAM_WOLF := "wolf"
const TEAM_THIRD_PARTY := "third_party"

const ROLE_TYPE_WOLF := "wolf"
const ROLE_TYPE_VILLAGER := "villager"
const ROLE_TYPE_GOD := "god"
const ROLE_TYPE_THIRD_PARTY := "third_party"

const SLAUGHTER_GROUP_WOLF := "wolf"
const SLAUGHTER_GROUP_VILLAGER := "villager"
const SLAUGHTER_GROUP_GOD := "god"
const SLAUGHTER_GROUP_THIRD_PARTY := "third_party"

const AVATAR_ROLE_DIR := "res://assets/images/werewolf/avatars/roles/"
const AVATAR_WOLF := "res://assets/images/werewolf/avatars/roles/wolf.png"
const AVATAR_VILLAGER := "res://assets/images/werewolf/avatars/roles/villager.png"
const AVATAR_SEER := "res://assets/images/werewolf/avatars/roles/seer.png"
const AVATAR_WITCH := "res://assets/images/werewolf/avatars/roles/witch.png"
const AVATAR_HUNTER := "res://assets/images/werewolf/avatars/roles/hunter.png"
const AVATAR_GUARD := "res://assets/images/werewolf/avatars/roles/guard.png"

const ROLE_SEER := "seer"
const ROLE_WITCH := "witch"
const ROLE_HUNTER := "hunter"
const ROLE_GUARD := "guard"
const ROLE_VILLAGER := "villager"
const ROLE_WOLF := "wolf"
const ROLE_IDIOT := "idiot"
const ROLE_WOLF_KING := "wolf_king"
const ROLE_WHITE_WOLF_KING := "white_wolf_king"
const ROLE_DREAM_WEAVER := "dream_weaver"
const ROLE_GRAVEKEEPER := "gravekeeper"
const ROLE_KNIGHT := "knight"
const ROLE_WOLF_BEAUTY := "wolf_beauty"
const ROLE_NIGHTMARE := "nightmare"
const ROLE_GARGOYLE := "gargoyle"
const ROLE_BLOOD_MOON_APOSTLE := "blood_moon_apostle"
const ROLE_RAVEN := "raven"
const ROLE_MECHANIC := "mechanic"
const ROLE_BEAR := "bear"
const ROLE_PSYCHIC := "psychic"
const ROLE_FOX := "fox"
const ROLE_CUPID := "cupid"
const ROLE_WILD_CHILD := "wild_child"
const ROLE_THIEF := "thief"
const ROLE_CURSED_FOX := "cursed_fox"
const ROLE_OLD_ROGUE := "old_rogue"
const ROLE_MAGICIAN := "magician"
const ROLE_HIDDEN_WOLF := "hidden_wolf"
const ROLE_WOLF_GUNNER := "wolf_gunner"
const ROLE_WOLF_SEED := "wolf_seed"
const ROLE_DOUBLE_KILL_WOLF := "double_kill_wolf"
const ROLE_LITTLE_GIRL := "little_girl"
const ROLE_PIED_PIPER := "pied_piper"
const ROLE_LONE_WOLF := "lone_wolf"

enum Role {
	SEER,
	WITCH,
	HUNTER,
	GUARD,
	VILLAGER,
	WOLF,
	IDIOT,
	WOLF_KING,
	WHITE_WOLF_KING,
	DREAM_WEAVER,
	GRAVEKEEPER,
	KNIGHT,
	WOLF_BEAUTY,
	NIGHTMARE,
	GARGOYLE,
	BLOOD_MOON_APOSTLE,
	RAVEN,
	MECHANIC,
	BEAR,
	PSYCHIC,
	FOX,
	CUPID,
	WILD_CHILD,
	THIEF,
	CURSED_FOX,
	OLD_ROGUE,
	MAGICIAN,
	HIDDEN_WOLF,
	WOLF_GUNNER,
	WOLF_SEED,
	DOUBLE_KILL_WOLF,
	LITTLE_GIRL,
	PIED_PIPER,
	LONE_WOLF,
}

const ROLE_ORDER := [
	ROLE_SEER,
	ROLE_WITCH,
	ROLE_HUNTER,
	ROLE_GUARD,
	ROLE_VILLAGER,
	ROLE_WOLF,
	ROLE_IDIOT,
	ROLE_WOLF_KING,
	ROLE_WHITE_WOLF_KING,
	ROLE_DREAM_WEAVER,
	ROLE_GRAVEKEEPER,
	ROLE_KNIGHT,
	ROLE_WOLF_BEAUTY,
	ROLE_NIGHTMARE,
	ROLE_GARGOYLE,
	ROLE_BLOOD_MOON_APOSTLE,
	ROLE_RAVEN,
	ROLE_MECHANIC,
	ROLE_BEAR,
	ROLE_PSYCHIC,
	ROLE_FOX,
	ROLE_CUPID,
	ROLE_WILD_CHILD,
	ROLE_THIEF,
	ROLE_CURSED_FOX,
	ROLE_OLD_ROGUE,
	ROLE_MAGICIAN,
	ROLE_HIDDEN_WOLF,
	ROLE_WOLF_GUNNER,
	ROLE_WOLF_SEED,
	ROLE_DOUBLE_KILL_WOLF,
	ROLE_LITTLE_GIRL,
	ROLE_PIED_PIPER,
	ROLE_LONE_WOLF,
]

const SUMMARY_ROLE_ORDER := [
	ROLE_WOLF,
	ROLE_WOLF_KING,
	ROLE_WHITE_WOLF_KING,
	ROLE_WOLF_BEAUTY,
	ROLE_NIGHTMARE,
	ROLE_GARGOYLE,
	ROLE_BLOOD_MOON_APOSTLE,
	ROLE_HIDDEN_WOLF,
	ROLE_WOLF_GUNNER,
	ROLE_WOLF_SEED,
	ROLE_DOUBLE_KILL_WOLF,
	ROLE_SEER,
	ROLE_WITCH,
	ROLE_HUNTER,
	ROLE_GUARD,
	ROLE_IDIOT,
	ROLE_DREAM_WEAVER,
	ROLE_GRAVEKEEPER,
	ROLE_KNIGHT,
	ROLE_RAVEN,
	ROLE_MECHANIC,
	ROLE_BEAR,
	ROLE_PSYCHIC,
	ROLE_FOX,
	ROLE_CUPID,
	ROLE_WILD_CHILD,
	ROLE_THIEF,
	ROLE_OLD_ROGUE,
	ROLE_MAGICIAN,
	ROLE_LITTLE_GIRL,
	ROLE_VILLAGER,
	ROLE_CURSED_FOX,
	ROLE_PIED_PIPER,
	ROLE_LONE_WOLF,
]

const ROLE_TITLES := {
	ROLE_SEER: "洞察者",
	ROLE_WITCH: "秘药师",
	ROLE_HUNTER: "持枪者",
	ROLE_GUARD: "守夜人",
	ROLE_VILLAGER: "村庄居民",
	ROLE_WOLF: "夜行者",
	ROLE_IDIOT: "翻牌者",
	ROLE_WOLF_KING: "狼族王者",
	ROLE_WHITE_WOLF_KING: "白昼狼王",
	ROLE_DREAM_WEAVER: "梦境行者",
	ROLE_GRAVEKEEPER: "墓园守望",
	ROLE_KNIGHT: "审判骑士",
	ROLE_WOLF_BEAUTY: "魅影狼姬",
	ROLE_NIGHTMARE: "梦魇使者",
	ROLE_GARGOYLE: "石眼窥视者",
	ROLE_BLOOD_MOON_APOSTLE: "血月使徒",
	ROLE_RAVEN: "诅咒信使",
	ROLE_MECHANIC: "机关匠",
	ROLE_BEAR: "咆哮守望",
	ROLE_PSYCHIC: "亡语通灵",
	ROLE_FOX: "灵狐",
	ROLE_CUPID: "爱神使者",
	ROLE_WILD_CHILD: "荒野之子",
	ROLE_THIEF: "换牌者",
	ROLE_CURSED_FOX: "咒印灵狐",
	ROLE_OLD_ROGUE: "免疫老手",
	ROLE_MAGICIAN: "戏法师",
	ROLE_HIDDEN_WOLF: "潜伏狼",
	ROLE_WOLF_GUNNER: "狼族枪手",
	ROLE_WOLF_SEED: "狼种播撒者",
	ROLE_DOUBLE_KILL_WOLF: "双刃狼",
	ROLE_LITTLE_GIRL: "窥夜少女",
	ROLE_PIED_PIPER: "迷音笛手",
	ROLE_LONE_WOLF: "孤狼",
}

const DEFINITIONS := {
	ROLE_SEER: {
		"key": ROLE_SEER,
		"label": "预言家",
		"aliases": ["先知"],
		"team": TEAM_GOOD,
		"role_type": ROLE_TYPE_GOD,
		"slaughter_group": SLAUGHTER_GROUP_GOD,
		"avatar": AVATAR_SEER,
		"skills": [
			{"id": "seer_check", "name": "查验", "timing": "night", "effect": "每夜选择一名玩家，获得该玩家的阵营结果。"},
		],
		"capabilities": {"seer_check": true, "seer_result": TEAM_GOOD},
	},
	ROLE_WITCH: {
		"key": ROLE_WITCH,
		"label": "女巫",
		"team": TEAM_GOOD,
		"role_type": ROLE_TYPE_GOD,
		"slaughter_group": SLAUGHTER_GROUP_GOD,
		"avatar": AVATAR_WITCH,
		"skills": [
			{"id": "witch_antidote", "name": "解药", "timing": "night", "effect": "整局一次，夜晚得知狼刀目标后可救下该目标。"},
			{"id": "witch_poison", "name": "毒药", "timing": "night", "effect": "整局一次，夜晚选择一名玩家使其出局。"},
		],
		"capabilities": {"witch_act": true, "view_wolf_target": true, "seer_result": TEAM_GOOD},
	},
	ROLE_HUNTER: {
		"key": ROLE_HUNTER,
		"label": "猎人",
		"team": TEAM_GOOD,
		"role_type": ROLE_TYPE_GOD,
		"slaughter_group": SLAUGHTER_GROUP_GOD,
		"avatar": AVATAR_HUNTER,
		"skills": [
			{"id": "hunter_shoot", "name": "猎枪", "timing": "on_death", "effect": "出局且状态允许时，可开枪带走一名玩家，也可以不开枪。"},
		],
		"capabilities": {"hunter_shoot": true, "seer_result": TEAM_GOOD},
	},
	ROLE_GUARD: {
		"key": ROLE_GUARD,
		"label": "守卫",
		"team": TEAM_GOOD,
		"role_type": ROLE_TYPE_GOD,
		"slaughter_group": SLAUGHTER_GROUP_GOD,
		"avatar": AVATAR_GUARD,
		"skills": [
			{"id": "guard_protect", "name": "守护", "timing": "night", "effect": "每夜守护一名玩家，使其免于当夜狼刀；通常不能连续两夜守护同一人。"},
		],
		"capabilities": {"guard_protect": true, "seer_result": TEAM_GOOD},
	},
	ROLE_VILLAGER: {
		"key": ROLE_VILLAGER,
		"label": "村民",
		"aliases": ["平民"],
		"team": TEAM_GOOD,
		"role_type": ROLE_TYPE_VILLAGER,
		"slaughter_group": SLAUGHTER_GROUP_VILLAGER,
		"avatar": AVATAR_VILLAGER,
		"skills": [
			{"id": "villager_vote", "name": "发言投票", "timing": "day", "effect": "没有夜间技能，依靠发言、推理和白天投票帮助好人阵营获胜。"},
		],
		"capabilities": {"seer_result": TEAM_GOOD},
	},
	ROLE_WOLF: {
		"key": ROLE_WOLF,
		"label": "狼人",
		"team": TEAM_WOLF,
		"role_type": ROLE_TYPE_WOLF,
		"slaughter_group": SLAUGHTER_GROUP_WOLF,
		"avatar": AVATAR_WOLF,
		"skills": [
			{"id": "wolf_chat", "name": "狼队夜聊", "timing": "night", "effect": "夜晚与狼队沟通目标。"},
			{"id": "wolf_kill", "name": "袭击", "timing": "night", "effect": "夜晚共同选择一名非狼队玩家作为袭击目标。"},
		],
		"capabilities": {"wolf_chat": true, "wolf_night_kill": true, "see_wolf_teammates": true, "visible_to_wolf_teammates": true, "view_wolf_target": true, "seer_result": TEAM_WOLF},
	},
	ROLE_IDIOT: {
		"key": ROLE_IDIOT,
		"label": "白痴",
		"team": TEAM_GOOD,
		"role_type": ROLE_TYPE_GOD,
		"slaughter_group": SLAUGHTER_GROUP_GOD,
		"avatar": AVATAR_VILLAGER,
		"skills": [
			{"id": "idiot_reveal", "name": "翻牌免死", "timing": "on_exile", "effect": "被白天放逐时可翻牌免于出局，之后通常失去投票能力。"},
		],
		"capabilities": {"idiot_reveal": true, "seer_result": TEAM_GOOD},
	},
	ROLE_WOLF_KING: {
		"key": ROLE_WOLF_KING,
		"label": "狼王",
		"team": TEAM_WOLF,
		"role_type": ROLE_TYPE_WOLF,
		"slaughter_group": SLAUGHTER_GROUP_WOLF,
		"avatar": AVATAR_WOLF,
		"skills": [
			{"id": "wolf_kill", "name": "袭击", "timing": "night", "effect": "参与狼队夜晚袭击。"},
			{"id": "wolf_king_shoot", "name": "狼王枪", "timing": "on_death", "effect": "出局时可带走一名玩家，具体禁枪条件由地图规则决定。"},
		],
		"capabilities": {"wolf_chat": true, "wolf_night_kill": true, "see_wolf_teammates": true, "visible_to_wolf_teammates": true, "view_wolf_target": true, "wolf_death_shoot": true, "seer_result": TEAM_WOLF},
	},
	ROLE_WHITE_WOLF_KING: {
		"key": ROLE_WHITE_WOLF_KING,
		"label": "白狼王",
		"team": TEAM_WOLF,
		"role_type": ROLE_TYPE_WOLF,
		"slaughter_group": SLAUGHTER_GROUP_WOLF,
		"avatar": AVATAR_WOLF,
		"skills": [
			{"id": "wolf_kill", "name": "袭击", "timing": "night", "effect": "参与狼队夜晚袭击。"},
			{"id": "white_wolf_explode", "name": "自爆带人", "timing": "day", "effect": "白天可自爆并带走一名玩家，随后进入夜晚或按地图规则推进。"},
		],
		"capabilities": {"wolf_chat": true, "wolf_night_kill": true, "see_wolf_teammates": true, "visible_to_wolf_teammates": true, "view_wolf_target": true, "day_explode": true, "seer_result": TEAM_WOLF},
	},
	ROLE_DREAM_WEAVER: {
		"key": ROLE_DREAM_WEAVER,
		"label": "摄梦人",
		"team": TEAM_GOOD,
		"role_type": ROLE_TYPE_GOD,
		"slaughter_group": SLAUGHTER_GROUP_GOD,
		"avatar": AVATAR_VILLAGER,
		"skills": [
			{"id": "dream_weave", "name": "摄梦", "timing": "night", "effect": "每夜选择一名玩家进入梦境；梦境的保护、连摄死亡等效果由地图规则定义。"},
		],
		"capabilities": {"dream_weave": true, "seer_result": TEAM_GOOD},
	},
	ROLE_GRAVEKEEPER: {
		"key": ROLE_GRAVEKEEPER,
		"label": "守墓人",
		"team": TEAM_GOOD,
		"role_type": ROLE_TYPE_GOD,
		"slaughter_group": SLAUGHTER_GROUP_GOD,
		"avatar": AVATAR_VILLAGER,
		"skills": [
			{"id": "gravekeeper_check", "name": "验尸", "timing": "night", "effect": "夜晚查看上一白天被放逐玩家的阵营或身份结果。"},
		],
		"capabilities": {"gravekeeper_check": true, "seer_result": TEAM_GOOD},
	},
	ROLE_KNIGHT: {
		"key": ROLE_KNIGHT,
		"label": "骑士",
		"team": TEAM_GOOD,
		"role_type": ROLE_TYPE_GOD,
		"slaughter_group": SLAUGHTER_GROUP_GOD,
		"avatar": AVATAR_VILLAGER,
		"skills": [
			{"id": "knight_duel", "name": "决斗", "timing": "day", "effect": "白天指定一名玩家决斗；若目标为狼人阵营则目标出局，否则骑士出局。"},
		],
		"capabilities": {"knight_duel": true, "seer_result": TEAM_GOOD},
	},
	ROLE_WOLF_BEAUTY: {
		"key": ROLE_WOLF_BEAUTY,
		"label": "狼美人",
		"team": TEAM_WOLF,
		"role_type": ROLE_TYPE_WOLF,
		"slaughter_group": SLAUGHTER_GROUP_WOLF,
		"avatar": AVATAR_WOLF,
		"skills": [
			{"id": "wolf_kill", "name": "袭击", "timing": "night", "effect": "参与狼队夜晚袭击。"},
			{"id": "wolf_beauty_charm", "name": "魅惑", "timing": "night", "effect": "夜晚魅惑一名玩家；狼美人出局时按规则带走被魅惑目标。"},
		],
		"capabilities": {"wolf_chat": true, "wolf_night_kill": true, "see_wolf_teammates": true, "visible_to_wolf_teammates": true, "view_wolf_target": true, "charm": true, "seer_result": TEAM_WOLF},
	},
	ROLE_NIGHTMARE: {
		"key": ROLE_NIGHTMARE,
		"label": "梦魇",
		"team": TEAM_WOLF,
		"role_type": ROLE_TYPE_WOLF,
		"slaughter_group": SLAUGHTER_GROUP_WOLF,
		"avatar": AVATAR_WOLF,
		"skills": [
			{"id": "wolf_kill", "name": "袭击", "timing": "night", "effect": "参与狼队夜晚袭击。"},
			{"id": "nightmare_block", "name": "恐惧", "timing": "night", "effect": "夜晚封禁一名玩家，使其当夜技能失效。"},
		],
		"capabilities": {"wolf_chat": true, "wolf_night_kill": true, "see_wolf_teammates": true, "visible_to_wolf_teammates": true, "view_wolf_target": true, "night_block": true, "seer_result": TEAM_WOLF},
	},
	ROLE_GARGOYLE: {
		"key": ROLE_GARGOYLE,
		"label": "石像鬼",
		"team": TEAM_WOLF,
		"role_type": ROLE_TYPE_WOLF,
		"slaughter_group": SLAUGHTER_GROUP_WOLF,
		"avatar": AVATAR_WOLF,
		"skills": [
			{"id": "gargoyle_check", "name": "窥视", "timing": "night", "effect": "夜晚查看一名玩家的身份或阵营；通常不参与普通狼队夜聊和刀人。"},
		],
		"capabilities": {"gargoyle_check": true, "seer_result": TEAM_WOLF},
	},
	ROLE_BLOOD_MOON_APOSTLE: {
		"key": ROLE_BLOOD_MOON_APOSTLE,
		"label": "血月使徒",
		"team": TEAM_WOLF,
		"role_type": ROLE_TYPE_WOLF,
		"slaughter_group": SLAUGHTER_GROUP_WOLF,
		"avatar": AVATAR_WOLF,
		"skills": [
			{"id": "wolf_kill", "name": "袭击", "timing": "night", "effect": "参与狼队夜晚袭击。"},
			{"id": "blood_moon_exile_delay", "name": "血月", "timing": "on_exile", "effect": "白天出局后触发血月效果，延迟死亡或影响当日流程，具体由地图规则定义。"},
		],
		"capabilities": {"wolf_chat": true, "wolf_night_kill": true, "see_wolf_teammates": true, "visible_to_wolf_teammates": true, "view_wolf_target": true, "blood_moon": true, "seer_result": TEAM_WOLF},
	},
	ROLE_RAVEN: {
		"key": ROLE_RAVEN,
		"label": "乌鸦",
		"team": TEAM_GOOD,
		"role_type": ROLE_TYPE_GOD,
		"slaughter_group": SLAUGHTER_GROUP_GOD,
		"avatar": AVATAR_VILLAGER,
		"skills": [
			{"id": "raven_curse", "name": "诅咒", "timing": "night", "effect": "每夜诅咒一名玩家，使其次日白天投票结算时额外获得票数。"},
		],
		"capabilities": {"raven_curse": true, "seer_result": TEAM_GOOD},
	},
	ROLE_MECHANIC: {
		"key": ROLE_MECHANIC,
		"label": "机械师",
		"team": TEAM_GOOD,
		"role_type": ROLE_TYPE_GOD,
		"slaughter_group": SLAUGHTER_GROUP_GOD,
		"avatar": AVATAR_VILLAGER,
		"skills": [
			{"id": "mechanic_puppet", "name": "操控", "timing": "night", "effect": "操控机械单位或复制指定技能效果，具体可用技能由地图规则配置。"},
		],
		"capabilities": {"mechanic_puppet": true, "seer_result": TEAM_GOOD},
	},
	ROLE_BEAR: {
		"key": ROLE_BEAR,
		"label": "熊",
		"team": TEAM_GOOD,
		"role_type": ROLE_TYPE_GOD,
		"slaughter_group": SLAUGHTER_GROUP_GOD,
		"avatar": AVATAR_VILLAGER,
		"skills": [
			{"id": "bear_roar", "name": "咆哮", "timing": "day_start", "effect": "天亮时根据相邻存活玩家是否存在狼人阵营给出咆哮提示。"},
		],
		"capabilities": {"bear_roar": true, "seer_result": TEAM_GOOD},
	},
	ROLE_PSYCHIC: {
		"key": ROLE_PSYCHIC,
		"label": "通灵师",
		"team": TEAM_GOOD,
		"role_type": ROLE_TYPE_GOD,
		"slaughter_group": SLAUGHTER_GROUP_GOD,
		"avatar": AVATAR_VILLAGER,
		"skills": [
			{"id": "psychic_commune", "name": "通灵", "timing": "night", "effect": "夜晚查看死亡玩家相关信息，或与亡者信息交互；具体范围由地图规则定义。"},
		],
		"capabilities": {"psychic_commune": true, "seer_result": TEAM_GOOD},
	},
	ROLE_FOX: {
		"key": ROLE_FOX,
		"label": "狐狸",
		"team": TEAM_GOOD,
		"role_type": ROLE_TYPE_GOD,
		"slaughter_group": SLAUGHTER_GROUP_GOD,
		"avatar": AVATAR_VILLAGER,
		"skills": [
			{"id": "fox_sniff", "name": "嗅探", "timing": "night", "effect": "夜晚查看连续三名玩家中是否存在狼人阵营；若没有狼人通常失去技能。"},
		],
		"capabilities": {"fox_sniff": true, "seer_result": TEAM_GOOD},
	},
	ROLE_CUPID: {
		"key": ROLE_CUPID,
		"label": "丘比特",
		"team": TEAM_GOOD,
		"role_type": ROLE_TYPE_GOD,
		"slaughter_group": SLAUGHTER_GROUP_GOD,
		"avatar": AVATAR_VILLAGER,
		"skills": [
			{"id": "cupid_link", "name": "连情侣", "timing": "first_night", "effect": "首夜选择两名玩家成为情侣；情侣同生共死，胜利归属由地图规则决定。"},
		],
		"capabilities": {"cupid_link": true, "seer_result": TEAM_GOOD},
	},
	ROLE_WILD_CHILD: {
		"key": ROLE_WILD_CHILD,
		"label": "野孩子",
		"team": TEAM_GOOD,
		"role_type": ROLE_TYPE_GOD,
		"slaughter_group": SLAUGHTER_GROUP_GOD,
		"avatar": AVATAR_VILLAGER,
		"skills": [
			{"id": "wild_child_model", "name": "榜样", "timing": "first_night", "effect": "首夜选择一名榜样；榜样死亡后野孩子通常转为狼人阵营。"},
		],
		"capabilities": {"wild_child_model": true, "seer_result": TEAM_GOOD},
	},
	ROLE_THIEF: {
		"key": ROLE_THIEF,
		"label": "盗贼",
		"team": TEAM_GOOD,
		"role_type": ROLE_TYPE_GOD,
		"slaughter_group": SLAUGHTER_GROUP_GOD,
		"avatar": AVATAR_VILLAGER,
		"skills": [
			{"id": "thief_swap", "name": "换牌", "timing": "setup", "effect": "开局从额外身份中选择一个作为本局实际身份。"},
		],
		"capabilities": {"thief_swap": true, "seer_result": TEAM_GOOD},
	},
	ROLE_CURSED_FOX: {
		"key": ROLE_CURSED_FOX,
		"label": "咒狐",
		"team": TEAM_THIRD_PARTY,
		"role_type": ROLE_TYPE_THIRD_PARTY,
		"slaughter_group": SLAUGHTER_GROUP_THIRD_PARTY,
		"avatar": AVATAR_VILLAGER,
		"skills": [
			{"id": "cursed_fox_survive", "name": "诅咒生存", "timing": "passive", "effect": "独立阵营，围绕自身存活触发胜利或惩罚效果，具体条件由地图规则定义。"},
		],
		"capabilities": {"third_party_win": true, "seer_result": TEAM_THIRD_PARTY},
	},
	ROLE_OLD_ROGUE: {
		"key": ROLE_OLD_ROGUE,
		"label": "老流氓",
		"team": TEAM_GOOD,
		"role_type": ROLE_TYPE_VILLAGER,
		"slaughter_group": SLAUGHTER_GROUP_VILLAGER,
		"avatar": AVATAR_VILLAGER,
		"skills": [
			{"id": "old_rogue_resist", "name": "老练", "timing": "passive", "effect": "对部分控制、毒杀或带走效果具备抗性；具体免疫范围由地图规则定义。"},
		],
		"capabilities": {"old_rogue_resist": true, "seer_result": TEAM_GOOD},
	},
	ROLE_MAGICIAN: {
		"key": ROLE_MAGICIAN,
		"label": "魔术师",
		"team": TEAM_GOOD,
		"role_type": ROLE_TYPE_GOD,
		"slaughter_group": SLAUGHTER_GROUP_GOD,
		"avatar": AVATAR_VILLAGER,
		"skills": [
			{"id": "magician_swap", "name": "交换", "timing": "night", "effect": "夜晚交换两名玩家的技能承受对象，用于重定向当夜效果。"},
		],
		"capabilities": {"magician_swap": true, "seer_result": TEAM_GOOD},
	},
	ROLE_HIDDEN_WOLF: {
		"key": ROLE_HIDDEN_WOLF,
		"label": "隐狼",
		"team": TEAM_WOLF,
		"role_type": ROLE_TYPE_WOLF,
		"slaughter_group": SLAUGHTER_GROUP_WOLF,
		"avatar": AVATAR_WOLF,
		"skills": [
			{"id": "hidden_wolf", "name": "隐匿", "timing": "passive", "effect": "属于狼人阵营但通常不进入普通狼队视野，预言家查验可显示为好人。"},
		],
		"capabilities": {"hidden_wolf": true, "seer_result": TEAM_GOOD},
	},
	ROLE_WOLF_GUNNER: {
		"key": ROLE_WOLF_GUNNER,
		"label": "狼枪",
		"team": TEAM_WOLF,
		"role_type": ROLE_TYPE_WOLF,
		"slaughter_group": SLAUGHTER_GROUP_WOLF,
		"avatar": AVATAR_WOLF,
		"skills": [
			{"id": "wolf_kill", "name": "袭击", "timing": "night", "effect": "参与狼队夜晚袭击。"},
			{"id": "wolf_gun", "name": "狼枪", "timing": "on_death", "effect": "出局时可按规则开枪带走一名玩家。"},
		],
		"capabilities": {"wolf_chat": true, "wolf_night_kill": true, "see_wolf_teammates": true, "visible_to_wolf_teammates": true, "view_wolf_target": true, "wolf_death_shoot": true, "seer_result": TEAM_WOLF},
	},
	ROLE_WOLF_SEED: {
		"key": ROLE_WOLF_SEED,
		"label": "种狼",
		"team": TEAM_WOLF,
		"role_type": ROLE_TYPE_WOLF,
		"slaughter_group": SLAUGHTER_GROUP_WOLF,
		"avatar": AVATAR_WOLF,
		"skills": [
			{"id": "wolf_kill", "name": "袭击", "timing": "night", "effect": "参与狼队夜晚袭击。"},
			{"id": "wolf_seed_infect", "name": "感染", "timing": "night", "effect": "在特定条件下将目标转化、感染或加入狼队，具体次数和限制由地图规则定义。"},
		],
		"capabilities": {"wolf_chat": true, "wolf_night_kill": true, "see_wolf_teammates": true, "visible_to_wolf_teammates": true, "view_wolf_target": true, "infect": true, "seer_result": TEAM_WOLF},
	},
	ROLE_DOUBLE_KILL_WOLF: {
		"key": ROLE_DOUBLE_KILL_WOLF,
		"label": "双刀狼",
		"team": TEAM_WOLF,
		"role_type": ROLE_TYPE_WOLF,
		"slaughter_group": SLAUGHTER_GROUP_WOLF,
		"avatar": AVATAR_WOLF,
		"skills": [
			{"id": "double_wolf_kill", "name": "双刀", "timing": "night", "effect": "夜晚可触发额外击杀目标，触发条件和次数由地图规则定义。"},
		],
		"capabilities": {"wolf_chat": true, "wolf_night_kill": true, "see_wolf_teammates": true, "visible_to_wolf_teammates": true, "view_wolf_target": true, "extra_kill": true, "seer_result": TEAM_WOLF},
	},
	ROLE_LITTLE_GIRL: {
		"key": ROLE_LITTLE_GIRL,
		"label": "小女孩",
		"team": TEAM_GOOD,
		"role_type": ROLE_TYPE_VILLAGER,
		"slaughter_group": SLAUGHTER_GROUP_VILLAGER,
		"avatar": AVATAR_VILLAGER,
		"skills": [
			{"id": "little_girl_peek", "name": "偷看", "timing": "night", "effect": "夜晚可窥探狼队行动信息，但被发现时可能受到惩罚。"},
		],
		"capabilities": {"little_girl_peek": true, "seer_result": TEAM_GOOD},
	},
	ROLE_PIED_PIPER: {
		"key": ROLE_PIED_PIPER,
		"label": "吹笛者",
		"team": TEAM_THIRD_PARTY,
		"role_type": ROLE_TYPE_THIRD_PARTY,
		"slaughter_group": SLAUGHTER_GROUP_THIRD_PARTY,
		"avatar": AVATAR_VILLAGER,
		"skills": [
			{"id": "pied_piper_charm", "name": "迷惑", "timing": "night", "effect": "每夜迷惑玩家；当所有存活玩家满足迷惑条件时可独立获胜。"},
		],
		"capabilities": {"pied_piper_charm": true, "third_party_win": true, "seer_result": TEAM_THIRD_PARTY},
	},
	ROLE_LONE_WOLF: {
		"key": ROLE_LONE_WOLF,
		"label": "独狼",
		"team": TEAM_THIRD_PARTY,
		"role_type": ROLE_TYPE_THIRD_PARTY,
		"slaughter_group": SLAUGHTER_GROUP_THIRD_PARTY,
		"avatar": AVATAR_WOLF,
		"skills": [
			{"id": "lone_wolf_hunt", "name": "独行", "timing": "night", "effect": "独立阵营，按地图规则获得单独击杀或生存目标，并争取独立胜利。"},
		],
		"capabilities": {"lone_wolf": true, "third_party_win": true, "seer_result": TEAM_WOLF},
	},
}


func all_role_keys() -> Array:
	return ROLE_ORDER.duplicate()


func role_key_from_enum(role: int) -> String:
	if role < 0 or role >= ROLE_ORDER.size():
		return ""
	return String(ROLE_ORDER[role])


func role_enum_from_key(role_key: String) -> int:
	return ROLE_ORDER.find(_normalize_role_key(role_key))


func definitions() -> Dictionary:
	return DEFINITIONS.duplicate(true)


func definition(role_key: String) -> Dictionary:
	var key := _normalize_role_key(role_key)
	if key == "":
		key = ROLE_VILLAGER
	if DEFINITIONS.has(key):
		return _normalized_definition((DEFINITIONS[key] as Dictionary).duplicate(true), key)
	return _normalized_definition({
		"key": key,
		"label": key,
		"team": TEAM_GOOD,
		"role_type": ROLE_TYPE_VILLAGER,
		"slaughter_group": SLAUGHTER_GROUP_VILLAGER,
		"avatar": AVATAR_VILLAGER,
		"skills": [],
		"capabilities": {"seer_result": TEAM_GOOD},
	}, key)


func role_label(role_key: String) -> String:
	return String(definition(role_key).get("label", "村民"))


func role_title(role_key: String) -> String:
	var title := String(definition(role_key).get("title", "")).strip_edges()
	return title if title != "" else role_label(role_key)


func role_aliases(role_key: String) -> Array:
	return _as_array(definition(role_key).get("aliases", [])).duplicate()


func role_team(role_key: String) -> String:
	return String(definition(role_key).get("team", TEAM_GOOD))


func role_type(role_key: String) -> String:
	return String(definition(role_key).get("role_type", ROLE_TYPE_VILLAGER))


func slaughter_group(role_key: String) -> String:
	return String(definition(role_key).get("slaughter_group", ROLE_TYPE_VILLAGER))


func role_avatar(role_key: String) -> String:
	var data := definition(role_key)
	var avatar := String(data.get("avatar", "")).strip_edges()
	if avatar != "":
		return avatar
	if role_team(role_key) == TEAM_WOLF:
		return AVATAR_WOLF
	return AVATAR_VILLAGER


func role_skills(role_key: String) -> Array:
	return _as_array(definition(role_key).get("skills", [])).duplicate(true)


func role_skill_text(role_key: String) -> String:
	var parts := []
	for skill_value in role_skills(role_key):
		if not (skill_value is Dictionary):
			continue
		var skill: Dictionary = skill_value
		var name := String(skill.get("name", "")).strip_edges()
		var effect := String(skill.get("effect", "")).strip_edges()
		if name != "" and effect != "":
			parts.append("%s：%s" % [name, effect])
		elif effect != "":
			parts.append(effect)
	return "；".join(parts)


func role_effects(role_key: String) -> Array:
	var result := []
	for skill_value in role_skills(role_key):
		if skill_value is Dictionary:
			var effect := String((skill_value as Dictionary).get("effect", "")).strip_edges()
			if effect != "":
				result.append(effect)
	return result


func has_capability(role_key: String, capability_name: String) -> bool:
	return bool(role_capabilities(role_key).get(capability_name, false))


func role_capabilities(role_key: String) -> Dictionary:
	return _as_dict(definition(role_key).get("capabilities", {})).duplicate(true)


func is_wolf_team(role_key: String) -> bool:
	return role_team(role_key) == TEAM_WOLF


func is_good_team(role_key: String) -> bool:
	return role_team(role_key) == TEAM_GOOD


func is_third_party(role_key: String) -> bool:
	return role_team(role_key) == TEAM_THIRD_PARTY


func is_villager_role(role_key: String) -> bool:
	return role_type(role_key) == ROLE_TYPE_VILLAGER


func is_god_role(role_key: String) -> bool:
	return role_type(role_key) == ROLE_TYPE_GOD


func counts_as_wolf_for_win(role_key: String) -> bool:
	return is_wolf_team(role_key)


func counts_as_good_for_win(role_key: String) -> bool:
	return is_good_team(role_key)


func can_join_wolf_chat(role_key: String) -> bool:
	return has_capability(role_key, "wolf_chat")


func can_wolf_night_kill(role_key: String) -> bool:
	return has_capability(role_key, "wolf_night_kill")


func can_view_wolf_target(role_key: String) -> bool:
	return has_capability(role_key, "view_wolf_target") or can_join_wolf_chat(role_key)


func can_see_wolf_teammates(role_key: String) -> bool:
	return has_capability(role_key, "see_wolf_teammates")


func visible_to_wolf_teammates(role_key: String) -> bool:
	return has_capability(role_key, "visible_to_wolf_teammates")


func can_be_wolf_kill_target(role_key: String) -> bool:
	return bool(role_capabilities(role_key).get("wolf_kill_targetable", not is_wolf_team(role_key)))


func seer_result_key(role_key: String) -> String:
	return String(role_capabilities(role_key).get("seer_result", role_team(role_key)))


func seer_result_label(role_key: String) -> String:
	match seer_result_key(role_key):
		TEAM_WOLF:
			return "狼人阵营"
		TEAM_THIRD_PARTY:
			return "第三方阵营"
		_:
			return "好人阵营"


func role_counts(roles: Array) -> Array:
	var counts := {}
	var unknown_order := []
	for role in roles:
		var role_key := _normalize_role_key(String(role))
		if role_key == "":
			role_key = ROLE_VILLAGER
		counts[role_key] = int(counts.get(role_key, 0)) + 1
		if not SUMMARY_ROLE_ORDER.has(role_key) and not unknown_order.has(role_key):
			unknown_order.append(role_key)
	var result: Array = []
	var order := SUMMARY_ROLE_ORDER.duplicate()
	order.append_array(unknown_order)
	for role_key_value in order:
		var role_key := String(role_key_value)
		var count := int(counts.get(role_key, 0))
		if count > 0:
			result.append({"role_key": role_key, "role_name": role_label(role_key), "count": count})
	return result


func role_setup_summary_from_roles(roles: Array) -> String:
	var parts := []
	for item in role_counts(roles):
		var row: Dictionary = item
		parts.append("%sx%d" % [String(row.get("role_name", "")), int(row.get("count", 0))])
	return " / ".join(parts)


func role_setup_summary_from_players(players: Array) -> String:
	var roles := []
	for player_value in players:
		if not (player_value is Dictionary):
			continue
		var player: Dictionary = player_value
		if String(player.get("owner", "")) == "":
			continue
		var role_key := String(player.get("role_key", ROLE_VILLAGER))
		roles.append(role_key)
	return role_setup_summary_from_roles(roles)


func _normalize_role_key(role_key: String) -> String:
	var key := role_key.strip_edges()
	return key if key != "" else ROLE_VILLAGER


func _normalized_definition(data: Dictionary, key: String) -> Dictionary:
	data["key"] = key
	data["title"] = String(ROLE_TITLES.get(key, data.get("title", data.get("label", key)))).strip_edges()
	data["avatar"] = _role_avatar_path(key)
	return data


func _role_avatar_path(key: String) -> String:
	if ROLE_ORDER.has(key):
		return "%s%s.png" % [AVATAR_ROLE_DIR, key]
	return AVATAR_VILLAGER


func _as_array(value) -> Array:
	return value if value is Array else []


func _as_dict(value) -> Dictionary:
	return value if value is Dictionary else {}
