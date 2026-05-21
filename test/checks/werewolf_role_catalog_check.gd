extends SceneTree

const RoleCatalogScript := preload("res://scripts/room/werewolf/werewolf_role_catalog.gd")


func _initialize() -> void:
	var catalog = RoleCatalogScript.new()
	var expected := {
		"seer": "预言家",
		"witch": "女巫",
		"hunter": "猎人",
		"guard": "守卫",
		"villager": "村民",
		"wolf": "狼人",
		"idiot": "白痴",
		"wolf_king": "狼王",
		"white_wolf_king": "白狼王",
		"dream_weaver": "摄梦人",
		"gravekeeper": "守墓人",
		"knight": "骑士",
		"wolf_beauty": "狼美人",
		"nightmare": "梦魇",
		"gargoyle": "石像鬼",
		"blood_moon_apostle": "血月使徒",
		"raven": "乌鸦",
		"mechanic": "机械师",
		"bear": "熊",
		"psychic": "通灵师",
		"fox": "狐狸",
		"cupid": "丘比特",
		"wild_child": "野孩子",
		"thief": "盗贼",
		"cursed_fox": "咒狐",
		"old_rogue": "老流氓",
		"magician": "魔术师",
		"hidden_wolf": "隐狼",
		"wolf_gunner": "狼枪",
		"wolf_seed": "种狼",
		"double_kill_wolf": "双刀狼",
		"little_girl": "小女孩",
		"pied_piper": "吹笛者",
		"lone_wolf": "独狼",
	}
	assert(catalog.all_role_keys().size() == expected.size())
	assert(catalog.role_key_from_enum(RoleCatalogScript.Role.SEER) == "seer")
	assert(catalog.role_enum_from_key("lone_wolf") == RoleCatalogScript.Role.LONE_WOLF)
	var avatars := {}
	var titles := {}
	for role_key in expected.keys():
		assert(catalog.all_role_keys().has(role_key))
		assert(catalog.role_label(role_key) == String(expected[role_key]))
		assert(catalog.definition(role_key).get("key") == role_key)
		assert(String(catalog.definition(role_key).get("title", "")) == catalog.role_title(role_key))
		assert(catalog.role_title(role_key) != "")
		assert(not titles.has(catalog.role_title(role_key)))
		titles[catalog.role_title(role_key)] = role_key
		var avatar := catalog.role_avatar(role_key)
		assert(avatar.begins_with("res://assets/images/werewolf/avatars/roles/"))
		assert(avatar.ends_with("%s.png" % role_key))
		assert(not avatars.has(avatar))
		avatars[avatar] = role_key
		assert(not catalog.role_skills(role_key).is_empty())
		assert(catalog.role_skill_text(role_key) != "")
	assert(catalog.role_aliases("villager").has("平民"))
	assert(catalog.is_wolf_team("wolf_king"))
	assert(catalog.can_join_wolf_chat("wolf_king"))
	assert(catalog.can_wolf_night_kill("wolf_king"))
	assert(catalog.is_wolf_team("gargoyle"))
	assert(not catalog.can_join_wolf_chat("gargoyle"))
	assert(not catalog.can_wolf_night_kill("gargoyle"))
	assert(catalog.is_wolf_team("hidden_wolf"))
	assert(catalog.seer_result_label("hidden_wolf") == "好人阵营")
	assert(catalog.is_third_party("pied_piper"))
	assert(catalog.seer_result_label("lone_wolf") == "狼人阵营")
	var counts: Array = catalog.role_counts(["wolf_king", "wolf", "seer", "old_rogue", "villager", "villager"])
	assert(counts.size() == 5)
	assert(String((counts[0] as Dictionary).get("role_key", "")) == "wolf")
	assert(String((counts[1] as Dictionary).get("role_key", "")) == "wolf_king")
	assert(catalog.role_setup_summary_from_roles(["wolf", "villager", "villager"]).contains("狼人x1"))
	assert(catalog.role_setup_summary_from_roles(["wolf", "villager", "villager"]).contains("村民x2"))
	quit()
