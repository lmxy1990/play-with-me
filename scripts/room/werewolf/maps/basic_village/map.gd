extends RefCounted

const RoleConfigScript := preload("res://scripts/room/werewolf/maps/basic_village/role_config.gd")
const RoleCatalogScript := preload("res://scripts/room/werewolf/werewolf_role_catalog.gd")


func definition() -> Dictionary:
	var roles := RoleConfigScript.new().roles_by_count()
	var rules := _rules_by_count(roles)
	return {
		"id": "basic_village",
		"name": "标准村庄",
		"description": "预言家、女巫、猎人的标准配置，节奏稳定。",
		"scene": "村庄长桌",
		"background": "res://assets/images/werewolf/backgrounds/map_basic.png",
		"rule_text": String(rules.get(6, "")),
		"rule_text_by_count": rules,
		"wolf_win_condition_by_count": _win_conditions(roles),
		"has_sheriff": false,
		"roles": roles,
	}


func _rules_by_count(roles_by_count: Dictionary) -> Dictionary:
	var result := {}
	for count_value in roles_by_count.keys():
		var count := int(count_value)
		var roles: Array = roles_by_count[count]
		result[count] = "【标准村庄 %d人局】\n身份配置：%s。\n夜晚流程：%s。\n白天流程：%s。\n胜利条件：%s" % [count, _role_summary(roles), _night_text(roles), _day_text(roles), _win_text(count)]
	return result


func _win_conditions(roles_by_count: Dictionary) -> Dictionary:
	var result := {}
	for count_value in roles_by_count.keys():
		var count := int(count_value)
		result[count] = "all_good_dead" if count == 6 else "slaughter_side"
	return result


func _win_text(count: int) -> String:
	if count == 6:
		return "狼人全部出局，好人胜利；所有好人全部出局，狼人胜利。"
	return "狼人全部出局，好人胜利；村民全部出局或神职全部出局，狼人胜利。"


func _role_summary(roles: Array) -> String:
	return RoleCatalogScript.new().role_setup_summary_from_roles(roles).replace("x", "")


func _night_text(roles: Array) -> String:
	var parts := ["狼人夜间共同选择袭击目标"]
	if roles.has("guard"):
		parts.append("守卫每夜守护一名玩家且不能连续两夜守同一人")
	if roles.has("seer"):
		parts.append("预言家每夜查验一名玩家阵营")
	if roles.has("witch"):
		parts.append("女巫拥有一瓶解药和一瓶毒药")
	return "；".join(parts)


func _day_text(roles: Array) -> String:
	var text := "按座位顺序发言，发言结束后投票放逐"
	if roles.has("hunter"):
		text += "；猎人出局且可开枪时进入开枪流程"
	if roles.has("idiot"):
		text += "；白痴被白天放逐时可亮牌免于出局"
	return text
