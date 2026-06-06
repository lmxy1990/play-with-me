extends RefCounted
class_name XiangqiMapCatalog

const DEFAULT_MAP_ID := "xiangqi_standard"


func get_map_list() -> Array:
	return [{
		"id": DEFAULT_MAP_ID,
		"name": "标准象棋",
		"description": "2人标准中国象棋，红方先行",
		"scene": "竖版棋盘",
		"background": "res://assets/images/xiangqi/backgrounds/table.svg",
		"rule_text": "红先、标准中国象棋、可求和、可悔棋、可认输。计时默认关闭。",
		"supported_player_counts": [2],
	}]


func get_supported_player_counts(_map_id: String) -> Array:
	return [2]


func get_scene_slots(map_id: String, player_count: int) -> Dictionary:
	if map_id.strip_edges() == "":
		map_id = DEFAULT_MAP_ID
	if map_id != DEFAULT_MAP_ID or player_count != 2:
		return {}
	return {
		"map_id": DEFAULT_MAP_ID,
		"map_name": "标准象棋",
		"scene": "竖版棋盘",
		"player_count": 2,
		"slots": [
			{"slot_number": 1, "seat_index": 0, "name": "红方", "side": "red", "position": {"x": 0.16, "y": 0.5}},
			{"slot_number": 2, "seat_index": 1, "name": "黑方", "side": "black", "position": {"x": 0.84, "y": 0.5}},
		],
	}


func map_background_path(_map_id: String) -> String:
	return "res://assets/images/xiangqi/backgrounds/table.svg"
