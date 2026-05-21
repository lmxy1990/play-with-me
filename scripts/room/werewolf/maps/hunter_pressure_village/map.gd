extends RefCounted

const RoleConfigScript := preload("res://scripts/room/werewolf/maps/hunter_pressure_village/role_config.gd")


func definition() -> Dictionary:
	return {
		"id": "hunter_pressure_village",
		"name": "猎人压力村",
		"description": "弱化部分夜晚信息，猎人影响更大。",
		"scene": "山口村庄",
		"background": "res://assets/images/werewolf/backgrounds/map_hunter_pressure.png",
		"rule_text": _rules_by_count()[6],
		"rule_text_by_count": _rules_by_count(),
		"wolf_win_condition_by_count": {
			6: "all_good_dead",
			7: "all_good_dead",
			8: "all_good_dead",
			9: "all_good_dead",
		},
		"has_sheriff": false,
		"roles": RoleConfigScript.new().roles_by_count(),
	}


func _rules_by_count() -> Dictionary:
	return {
		6: "【猎人压力村 6人局】\n身份配置：狼人2、预言家1、猎人1、村民2。\n夜晚流程：狼人夜间共同选择袭击目标；预言家每夜查验一名玩家阵营；没有女巫用药流程。\n白天流程：按座位顺序发言，发言结束后投票放逐一名玩家。\n猎人规则：猎人出局且可开枪时进入开枪流程。\n胜利条件：狼人全部出局，好人胜利；所有好人全部出局，狼人胜利。",
		7: "【猎人压力村 7人局】\n身份配置：狼人2、女巫1、猎人1、村民3。\n夜晚流程：狼人夜间共同选择袭击目标；女巫拥有一瓶解药和一瓶毒药；没有预言家查验流程。\n白天流程：按座位顺序发言，发言结束后投票放逐一名玩家。\n猎人规则：猎人出局且可开枪时进入开枪流程。\n胜利条件：狼人全部出局，好人胜利；所有好人全部出局，狼人胜利。",
		8: "【猎人压力村 8人局】\n身份配置：狼人3、预言家1、猎人1、村民3。\n夜晚流程：狼人夜间共同选择袭击目标；预言家每夜查验一名玩家阵营；没有女巫用药流程。\n白天流程：按座位顺序发言，发言结束后投票放逐一名玩家。\n猎人规则：猎人出局且可开枪时进入开枪流程。\n胜利条件：狼人全部出局，好人胜利；所有好人全部出局，狼人胜利。",
		9: "【猎人压力村 9人局】\n身份配置：狼人3、预言家1、女巫1、猎人1、村民3。\n夜晚流程：狼人夜间共同选择袭击目标；预言家每夜查验一名玩家阵营；女巫拥有一瓶解药和一瓶毒药。\n白天流程：按座位顺序发言，发言结束后投票放逐一名玩家。\n猎人规则：猎人出局且可开枪时进入开枪流程。\n胜利条件：狼人全部出局，好人胜利；所有好人全部出局，狼人胜利。",
	}
