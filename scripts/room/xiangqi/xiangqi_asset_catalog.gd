extends RefCounted
class_name XiangqiAssetCatalog

const BACKGROUND_TABLE := "res://assets/images/xiangqi/backgrounds/table.svg"
const BOARD := "res://assets/images/xiangqi/board/board.svg"
const PIECE_RED := "res://assets/images/xiangqi/pieces/piece_red.svg"
const PIECE_BLACK := "res://assets/images/xiangqi/pieces/piece_black.svg"
const SELECTION := "res://assets/images/xiangqi/board/selection.svg"
const LEGAL_DOT := "res://assets/images/xiangqi/board/legal_dot.svg"
const VOICE := "res://assets/images/werewolf/actions/speaker.svg"


static func lobby_background_path() -> String:
	return BACKGROUND_TABLE


static func table_background_path() -> String:
	return BACKGROUND_TABLE


static func board_path() -> String:
	return BOARD


static func piece_base_path(side: String) -> String:
	return PIECE_RED if side == "red" else PIECE_BLACK


static func marker_path(marker_id: String) -> String:
	match marker_id:
		"selection":
			return SELECTION
		"legal_dot":
			return LEGAL_DOT
		_:
			return LEGAL_DOT


static func voice_path() -> String:
	return VOICE


static func action_path(action_id: String) -> String:
	match action_id:
		"draw":
			return "res://assets/images/xiangqi/actions/draw.svg"
		"undo":
			return "res://assets/images/xiangqi/actions/undo.svg"
		"resign":
			return "res://assets/images/xiangqi/actions/resign.svg"
		"timer":
			return "res://assets/images/xiangqi/actions/timer.svg"
		"pause":
			return "res://assets/images/xiangqi/actions/pause.svg"
		_:
			return "res://assets/images/xiangqi/actions/draw.svg"


static func map_background_path(_map_id: String) -> String:
	return BACKGROUND_TABLE


static func room_background_path(_room: Dictionary) -> String:
	return BACKGROUND_TABLE
