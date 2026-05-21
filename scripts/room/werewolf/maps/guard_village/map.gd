extends RefCounted

const RoleConfigScript := preload("res://scripts/room/werewolf/maps/guard_village/role_config.gd")


func definition() -> Dictionary:
	return {
		"id": "guard_village",
		"name": "守卫村庄",
		"description": "加入守卫夜间保护机制。",
		"scene": "守卫村庄",
		"background": "res://assets/images/werewolf/backgrounds/map_guard_standard.png",
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
		6: "【守卫村庄 6人局】\n身份配置：狼人2、预言家1、守卫1、村民2。\n夜晚流程：狼人夜间共同选择袭击目标；守卫每夜守护一名玩家且不能连续两夜守同一人；预言家每夜查验一名玩家阵营。\n白天流程：按座位顺序发言，发言结束后投票放逐一名玩家。\n胜利条件：狼人全部出局，好人胜利；所有好人全部出局，狼人胜利。",
		7: "【守卫村庄 7人局】\n身份配置：狼人2、预言家1、女巫1、守卫1、村民2。\n夜晚流程：狼人夜间共同选择袭击目标；守卫守护且不能连守；预言家查验；女巫拥有一瓶解药和一瓶毒药。\n白天流程：按座位顺序发言，发言结束后投票放逐一名玩家。\n胜利条件：狼人全部出局，好人胜利；所有好人全部出局，狼人胜利。",
		8: "【守卫村庄 8人局】\n身份配置：狼人2、预言家1、女巫1、猎人1、守卫1、村民2。\n夜晚流程：狼人夜间共同选择袭击目标；守卫守护且不能连守；预言家查验；女巫拥有一瓶解药和一瓶毒药。\n白天流程：按座位顺序发言后投票放逐；猎人出局且可开枪时进入开枪流程。\n胜利条件：狼人全部出局，好人胜利；所有好人全部出局，狼人胜利。",
		9: "【守卫村庄 9人局】\n身份配置：狼人3、预言家1、女巫1、猎人1、守卫1、村民2。\n夜晚流程：狼人夜间共同选择袭击目标；守卫守护且不能连守；预言家查验；女巫拥有一瓶解药和一瓶毒药。\n白天流程：按座位顺序发言后投票放逐；猎人出局且可开枪时进入开枪流程。\n胜利条件：狼人全部出局，好人胜利；所有好人全部出局，狼人胜利。",
	}
