extends RefCounted

const PLAYER_TYPE := "ai"
const CONTROLLER_TYPE := "ai"


func player_id_for_bot(bot_serial: int) -> String:
	return "player_%d" % bot_serial


func avatar_index_for_bot(bot_serial: int, avatar_count: int) -> int:
	if avatar_count <= 0:
		return 0
	return maxi(0, bot_serial - 1) % avatar_count


func controller_type() -> String:
	return CONTROLLER_TYPE

