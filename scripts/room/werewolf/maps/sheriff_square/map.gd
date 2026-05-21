extends RefCounted

const RoleConfigScript := preload("res://scripts/room/werewolf/maps/sheriff_square/role_config.gd")


func definition() -> Dictionary:
	return {
		"id": "sheriff_square",
		"name": "警长广场",
		"description": "开局先选警长，警长决定白天发言顺序；警长死亡可飞警徽或撕警徽。",
		"scene": "警长广场",
		"background": "res://assets/images/werewolf/backgrounds/map_sheriff_standard.png",
		"rule_text": _rules_by_count()[12],
		"rule_text_by_count": _rules_by_count(),
		"wolf_win_condition_by_count": {
			10: "slaughter_side",
			12: "slaughter_side",
		},
		"has_sheriff": true,
		"roles": RoleConfigScript.new().roles_by_count(),
	}


func _rules_by_count() -> Dictionary:
	return {
		10: "【警长广场 10人局】\n身份配置：狼人3、预言家1、女巫1、猎人1、白痴1、村民3。\n警长流程：开局先进行警长竞选发言与警长投票；警长每天白天发言前指定从某号位开始顺时针或逆时针发言；警长白天放逐投票额外计一票；警长死亡时先选择飞警徽给一名存活玩家或撕警徽。\n夜晚流程：狼人夜间共同选择袭击目标；预言家每夜查验一名玩家阵营；女巫拥有一瓶解药和一瓶毒药。\n白天流程：有存活警长时按警长指定顺序发言；无警长可决定时按座位顺序发言；发言结束后投票放逐；猎人出局且可开枪时进入开枪流程。\n胜利条件：狼人全部出局，好人胜利；村民全部出局或神职全部出局，狼人胜利。",
		12: "【警长广场 12人局】\n身份配置：狼人4、预言家1、女巫1、猎人1、白痴1、村民4。\n警长流程：开局先进行警长竞选发言与警长投票；警长每天白天发言前指定从某号位开始顺时针或逆时针发言；警长白天放逐投票额外计一票；警长死亡时先选择飞警徽给一名存活玩家或撕警徽。\n夜晚流程：狼人夜间共同选择袭击目标；预言家每夜查验一名玩家阵营；女巫拥有一瓶解药和一瓶毒药。\n白天流程：有存活警长时按警长指定顺序发言；无警长可决定时按座位顺序发言；发言结束后投票放逐；猎人出局且可开枪时进入开枪流程。\n胜利条件：狼人全部出局，好人胜利；村民全部出局或神职全部出局，狼人胜利。",
	}
