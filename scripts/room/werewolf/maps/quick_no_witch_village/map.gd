extends RefCounted

const RoleConfigScript := preload("res://scripts/room/werewolf/maps/quick_no_witch_village/role_config.gd")


func definition() -> Dictionary:
	return {
		"id": "quick_no_witch_village",
		"name": "快节奏村庄",
		"description": "去掉女巫救毒，夜晚更短，白天推理压力更集中。",
		"scene": "钟楼村口",
		"background": "res://assets/images/werewolf/backgrounds/map_quick_no_witch.png",
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
		6: "【快节奏村庄 6人局】\n身份配置：狼人2、预言家1、猎人1、村民2。\n夜晚流程：狼人夜间共同选择袭击目标；预言家每夜查验一名玩家阵营；没有女巫用药流程。\n白天流程：按座位顺序发言，发言结束后投票放逐一名玩家。\n猎人规则：猎人出局且可开枪时进入开枪流程。\n胜利条件：狼人全部出局，好人胜利；所有好人全部出局，狼人胜利。",
		7: "【快节奏村庄 7人局】\n身份配置：狼人2、预言家1、猎人1、村民3。\n夜晚流程：狼人夜间共同选择袭击目标；预言家每夜查验一名玩家阵营；没有女巫用药流程。\n白天流程：按座位顺序发言，发言结束后投票放逐一名玩家。\n猎人规则：猎人出局且可开枪时进入开枪流程。\n胜利条件：狼人全部出局，好人胜利；所有好人全部出局，狼人胜利。",
		8: "【快节奏村庄 8人局】\n身份配置：狼人3、预言家1、猎人1、村民3。\n夜晚流程：狼人夜间共同选择袭击目标；预言家每夜查验一名玩家阵营；没有女巫用药流程。\n白天流程：按座位顺序发言，发言结束后投票放逐一名玩家。\n猎人规则：猎人出局且可开枪时进入开枪流程。\n胜利条件：狼人全部出局，好人胜利；所有好人全部出局，狼人胜利。",
		9: "【快节奏村庄 9人局】\n身份配置：狼人3、预言家1、猎人1、村民4。\n夜晚流程：狼人夜间共同选择袭击目标；预言家每夜查验一名玩家阵营；没有女巫用药流程。\n白天流程：按座位顺序发言，发言结束后投票放逐一名玩家。\n猎人规则：猎人出局且可开枪时进入开枪流程。\n胜利条件：狼人全部出局，好人胜利；所有好人全部出局，狼人胜利。",
	}
