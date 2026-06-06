extends RefCounted
class_name XiangqiEngine

const SIDE_RED := "red"
const SIDE_BLACK := "black"
const RESULT_PLAYING := "playing"
const RESULT_RED_WIN := "red_win"
const RESULT_BLACK_WIN := "black_win"
const RESULT_DRAW := "draw"

const PIECE_TEXT := {
	"red": {"king": "帅", "advisor": "仕", "elephant": "相", "horse": "马", "rook": "车", "cannon": "炮", "soldier": "兵"},
	"black": {"king": "将", "advisor": "士", "elephant": "象", "horse": "马", "rook": "车", "cannon": "炮", "soldier": "卒"},
}


func default_state(options: Dictionary = {}) -> Dictionary:
	var clock_enabled := bool(options.get("clock_enabled", false))
	var time_limit_ms := int(options.get("time_limit_ms", 600000))
	if time_limit_ms <= 0:
		time_limit_ms = 600000
	var state := {
		"game_id": "xiangqi",
		"phase": "lobby",
		"started": false,
		"paused": false,
		"board": _initial_board(),
		"side_to_move": SIDE_RED,
		"turn_number": 1,
		"ply_number": 0,
		"move_history": [],
		"captured_pieces": [],
		"last_move": {},
		"check_side": "",
		"pending_draw_offer": {},
		"pending_undo_offer": {},
		"clock_enabled": clock_enabled,
		"clock_state": _initial_clock_state(clock_enabled, time_limit_ms),
		"game_result": RESULT_PLAYING,
		"result_reason": "",
	}
	state["check_side"] = _side_in_check(state, state["side_to_move"])
	return state


func start_state(options: Dictionary = {}) -> Dictionary:
	var state := default_state(options)
	state["phase"] = "playing"
	state["started"] = true
	state["paused"] = false
	if bool(state.get("clock_enabled", false)):
		var clock: Dictionary = state.get("clock_state", {})
		clock["running_side"] = SIDE_RED
		clock["started_at_ms"] = Time.get_ticks_msec()
		clock["paused"] = false
		clock["pause_reason"] = ""
		state["clock_state"] = clock
	return state


func piece_label(piece: Dictionary) -> String:
	var side := String(piece.get("side", ""))
	var kind := String(piece.get("kind", ""))
	var side_map: Dictionary = PIECE_TEXT.get(side, {})
	return String(side_map.get(kind, "?"))


func side_label(side: String) -> String:
	return "红方" if side == SIDE_RED else "黑方"


func side_for_seat(index: int) -> String:
	return SIDE_RED if index == 0 else SIDE_BLACK


func seat_for_side(side: String) -> int:
	return 0 if side == SIDE_RED else 1


func legal_moves_for_side(state: Dictionary, side: String) -> Array:
	var result: Array = []
	var board: Array = _board(state)
	for rank in range(10):
		for file in range(9):
			var piece := _piece_at(board, file, rank)
			if piece.is_empty() or String(piece.get("side", "")) != side:
				continue
			var from := {"file": file, "rank": rank}
			for to in _pseudo_moves_for_piece(board, file, rank, piece):
				if _move_keeps_self_safe(state, side, from, to):
					result.append({"from": from, "to": to, "piece": piece.duplicate(true), "label": _move_label(piece, from, to)})
	return result


func legal_moves_from(state: Dictionary, file: int, rank: int) -> Array:
	var board: Array = _board(state)
	var piece := _piece_at(board, file, rank)
	if piece.is_empty():
		return []
	var side := String(piece.get("side", ""))
	var from := {"file": file, "rank": rank}
	var result: Array = []
	for to in _pseudo_moves_for_piece(board, file, rank, piece):
		if _move_keeps_self_safe(state, side, from, to):
			result.append(to)
	return result


func apply_move(state: Dictionary, from_file: int, from_rank: int, to_file: int, to_rank: int) -> Dictionary:
	if _game_over(state):
		return _error("game_over", "棋局已结束")
	if not _is_playing(state):
		return _error("not_playing", "对局未开始")
	if bool(state.get("paused", false)):
		return _error("paused", "棋局已暂停")
	if _has_pending_offer(state):
		return _error("pending_offer", "等待对方处理请求")
	var side := String(state.get("side_to_move", SIDE_RED))
	var board: Array = _board(state)
	var piece := _piece_at(board, from_file, from_rank)
	if piece.is_empty():
		return _error("empty_from", "起点没有棋子")
	if String(piece.get("side", "")) != side:
		return _error("wrong_side", "只能移动当前行棋方棋子")
	var legal := false
	for move in legal_moves_from(state, from_file, from_rank):
		if int(move.get("file", -1)) == to_file and int(move.get("rank", -1)) == to_rank:
			legal = true
			break
	if not legal:
		return _error("illegal_move", "走法不合法")

	var next := state.duplicate(true)
	var next_board: Array = _board(next)
	var captured := _piece_at(next_board, to_file, to_rank)
	_set_piece(next_board, from_file, from_rank, {})
	_set_piece(next_board, to_file, to_rank, piece)
	next["board"] = next_board
	var move_record := {
		"side": side,
		"piece": piece.duplicate(true),
		"from": {"file": from_file, "rank": from_rank},
		"to": {"file": to_file, "rank": to_rank},
		"captured": captured.duplicate(true),
		"text": _move_label(piece, {"file": from_file, "rank": from_rank}, {"file": to_file, "rank": to_rank}),
	}
	next["last_move"] = move_record.duplicate(true)
	var history: Array = next.get("move_history", [])
	history.append(move_record)
	next["move_history"] = history
	if not captured.is_empty():
		var captured_pieces: Array = next.get("captured_pieces", [])
		captured_pieces.append(captured.duplicate(true))
		next["captured_pieces"] = captured_pieces
	var next_side := _opponent(side)
	next["side_to_move"] = next_side
	next["ply_number"] = int(next.get("ply_number", 0)) + 1
	next["turn_number"] = int(floor(float(int(next["ply_number"])) / 2.0)) + 1
	next["pending_draw_offer"] = {}
	next["pending_undo_offer"] = {}
	next["check_side"] = _side_in_check(next, next_side)
	_apply_terminal_state(next, next_side)
	return {"ok": true, "state": next, "move": move_record}


func offer_draw(state: Dictionary, side: String) -> Dictionary:
	if not _valid_side(side):
		return _error("invalid_side", "无效的行棋方")
	if _game_over(state):
		return _error("game_over", "棋局已结束")
	if not _is_playing(state):
		return _error("not_playing", "对局未开始")
	if _has_pending_offer(state):
		return _error("pending_offer", "已有待处理请求")
	var next := state.duplicate(true)
	next["pending_draw_offer"] = {"side": side, "seat_index": seat_for_side(side), "at": Time.get_unix_time_from_system()}
	return {"ok": true, "state": next}


func respond_draw(state: Dictionary, side: String, accepted: bool) -> Dictionary:
	if not _valid_side(side):
		return _error("invalid_side", "无效的行棋方")
	if _game_over(state):
		return _error("game_over", "棋局已结束")
	if not _is_playing(state):
		return _error("not_playing", "对局未开始")
	var pending: Dictionary = state.get("pending_draw_offer", {})
	if pending.is_empty():
		return _error("no_draw_offer", "当前没有求和请求")
	if String(pending.get("side", "")) == side:
		return _error("same_side", "不能响应自己的求和请求")
	var next := state.duplicate(true)
	next["pending_draw_offer"] = {}
	if accepted:
		next["game_result"] = RESULT_DRAW
		next["phase"] = "completed"
		next["result_reason"] = "draw_agreed"
	return {"ok": true, "state": next}


func offer_undo(state: Dictionary, side: String) -> Dictionary:
	if not _valid_side(side):
		return _error("invalid_side", "无效的行棋方")
	if _game_over(state):
		return _error("game_over", "棋局已结束")
	if not _is_playing(state):
		return _error("not_playing", "对局未开始")
	if _has_pending_offer(state):
		return _error("pending_offer", "已有待处理请求")
	var history: Array = state.get("move_history", [])
	if history.is_empty():
		return _error("no_move", "还没有可悔棋的走法")
	var next := state.duplicate(true)
	next["pending_undo_offer"] = {"side": side, "seat_index": seat_for_side(side), "at": Time.get_unix_time_from_system()}
	return {"ok": true, "state": next}


func respond_undo(state: Dictionary, side: String, accepted: bool) -> Dictionary:
	if not _valid_side(side):
		return _error("invalid_side", "无效的行棋方")
	if _game_over(state):
		return _error("game_over", "棋局已结束")
	if not _is_playing(state):
		return _error("not_playing", "对局未开始")
	var pending: Dictionary = state.get("pending_undo_offer", {})
	if pending.is_empty():
		return _error("no_undo_offer", "当前没有悔棋请求")
	if String(pending.get("side", "")) == side:
		return _error("same_side", "不能响应自己的悔棋请求")
	var next := state.duplicate(true)
	next["pending_undo_offer"] = {}
	if not accepted:
		return {"ok": true, "state": next}
	var history: Array = next.get("move_history", [])
	if history.is_empty():
		return _error("no_move", "还没有可悔棋的走法")
	var last: Dictionary = history.pop_back()
	var board: Array = _board(next)
	var from: Dictionary = last.get("from", {})
	var to: Dictionary = last.get("to", {})
	var piece: Dictionary = last.get("piece", {})
	var captured: Dictionary = last.get("captured", {})
	_set_piece(board, int(to.get("file", -1)), int(to.get("rank", -1)), captured)
	_set_piece(board, int(from.get("file", -1)), int(from.get("rank", -1)), piece)
	if not captured.is_empty():
		var captured_pieces: Array = next.get("captured_pieces", [])
		if not captured_pieces.is_empty():
			captured_pieces.pop_back()
		next["captured_pieces"] = captured_pieces
	next["board"] = board
	next["move_history"] = history
	next["last_move"] = history.back().duplicate(true) if not history.is_empty() and history.back() is Dictionary else {}
	next["side_to_move"] = String(last.get("side", SIDE_RED))
	next["ply_number"] = maxi(0, int(next.get("ply_number", 0)) - 1)
	next["turn_number"] = int(floor(float(int(next["ply_number"])) / 2.0)) + 1
	next["game_result"] = RESULT_PLAYING
	next["phase"] = "playing"
	next["result_reason"] = ""
	next["check_side"] = _side_in_check(next, String(next["side_to_move"]))
	return {"ok": true, "state": next}


func resign(state: Dictionary, side: String) -> Dictionary:
	if not _valid_side(side):
		return _error("invalid_side", "无效的行棋方")
	if _game_over(state):
		return _error("game_over", "棋局已结束")
	if not _is_playing(state):
		return _error("not_playing", "对局未开始")
	var next := state.duplicate(true)
	next["game_result"] = RESULT_BLACK_WIN if side == SIDE_RED else RESULT_RED_WIN
	next["phase"] = "completed"
	next["result_reason"] = "resign"
	return {"ok": true, "state": next}


func board_summary(state: Dictionary) -> Array:
	var result: Array = []
	var board: Array = _board(state)
	for rank in range(10):
		for file in range(9):
			var piece := _piece_at(board, file, rank)
			if piece.is_empty():
				continue
			result.append({
				"file": file,
				"rank": rank,
				"side": String(piece.get("side", "")),
				"kind": String(piece.get("kind", "")),
				"label": piece_label(piece),
			})
	return result


func _initial_board() -> Array:
	var board: Array = []
	for _rank in range(10):
		var row: Array = []
		for _file in range(9):
			row.append({})
		board.append(row)
	_place_back_rank(board, SIDE_RED, 0)
	_place_back_rank(board, SIDE_BLACK, 9)
	_place_piece(board, 1, 2, SIDE_RED, "cannon")
	_place_piece(board, 7, 2, SIDE_RED, "cannon")
	_place_piece(board, 1, 7, SIDE_BLACK, "cannon")
	_place_piece(board, 7, 7, SIDE_BLACK, "cannon")
	for file in [0, 2, 4, 6, 8]:
		_place_piece(board, file, 3, SIDE_RED, "soldier")
		_place_piece(board, file, 6, SIDE_BLACK, "soldier")
	return board


func _place_back_rank(board: Array, side: String, rank: int) -> void:
	var kinds := ["rook", "horse", "elephant", "advisor", "king", "advisor", "elephant", "horse", "rook"]
	for file in range(kinds.size()):
		_place_piece(board, file, rank, side, String(kinds[file]))


func _place_piece(board: Array, file: int, rank: int, side: String, kind: String) -> void:
	_set_piece(board, file, rank, {"side": side, "kind": kind})


func _initial_clock_state(clock_enabled: bool, time_limit_ms: int) -> Dictionary:
	if not clock_enabled:
		return {}
	return {
		"clock_enabled": true,
		"time_limit_ms": time_limit_ms,
		"red_remaining_ms": time_limit_ms,
		"black_remaining_ms": time_limit_ms,
		"running_side": SIDE_RED,
		"started_at_ms": Time.get_ticks_msec(),
		"paused": false,
		"pause_reason": "",
	}


func _board(state: Dictionary) -> Array:
	var value = state.get("board", [])
	return value if value is Array else []


func _piece_at(board: Array, file: int, rank: int) -> Dictionary:
	if file < 0 or file > 8 or rank < 0 or rank > 9:
		return {}
	if rank >= board.size() or not (board[rank] is Array):
		return {}
	var row: Array = board[rank]
	if file >= row.size() or not (row[file] is Dictionary):
		return {}
	return (row[file] as Dictionary).duplicate(true)


func _set_piece(board: Array, file: int, rank: int, piece: Dictionary) -> void:
	if file < 0 or file > 8 or rank < 0 or rank > 9:
		return
	while board.size() <= rank:
		board.append([])
	if not (board[rank] is Array):
		board[rank] = []
	var row: Array = board[rank]
	while row.size() <= file:
		row.append({})
	row[file] = piece.duplicate(true)
	board[rank] = row


func _pseudo_moves_for_piece(board: Array, file: int, rank: int, piece: Dictionary) -> Array:
	match String(piece.get("kind", "")):
		"king":
			return _king_moves(board, file, rank, piece)
		"advisor":
			return _advisor_moves(board, file, rank, piece)
		"elephant":
			return _elephant_moves(board, file, rank, piece)
		"horse":
			return _horse_moves(board, file, rank, piece)
		"rook":
			return _rook_moves(board, file, rank, piece)
		"cannon":
			return _cannon_moves(board, file, rank, piece)
		"soldier":
			return _soldier_moves(board, file, rank, piece)
		_:
			return []


func _king_moves(board: Array, file: int, rank: int, piece: Dictionary) -> Array:
	var side := String(piece.get("side", ""))
	var result: Array = []
	for delta in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var to_file: int = file + delta.x
		var to_rank: int = rank + delta.y
		if _in_palace(side, to_file, to_rank) and _can_land(board, to_file, to_rank, side):
			result.append({"file": to_file, "rank": to_rank})
	var step := 1 if side == SIDE_RED else -1
	var scan_rank := rank + step
	while scan_rank >= 0 and scan_rank <= 9:
		var target := _piece_at(board, file, scan_rank)
		if not target.is_empty():
			if String(target.get("kind", "")) == "king" and String(target.get("side", "")) != side:
				result.append({"file": file, "rank": scan_rank})
			break
		scan_rank += step
	return result


func _advisor_moves(board: Array, file: int, rank: int, piece: Dictionary) -> Array:
	var side := String(piece.get("side", ""))
	var result: Array = []
	for delta in [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
		var to_file: int = file + delta.x
		var to_rank: int = rank + delta.y
		if _in_palace(side, to_file, to_rank) and _can_land(board, to_file, to_rank, side):
			result.append({"file": to_file, "rank": to_rank})
	return result


func _elephant_moves(board: Array, file: int, rank: int, piece: Dictionary) -> Array:
	var side := String(piece.get("side", ""))
	var result: Array = []
	for delta in [Vector2i(2, 2), Vector2i(2, -2), Vector2i(-2, 2), Vector2i(-2, -2)]:
		var eye_file := file + int(delta.x / 2)
		var eye_rank := rank + int(delta.y / 2)
		var to_file: int = file + delta.x
		var to_rank: int = rank + delta.y
		if not _in_board(to_file, to_rank):
			continue
		if side == SIDE_RED and to_rank > 4:
			continue
		if side == SIDE_BLACK and to_rank < 5:
			continue
		if not _piece_at(board, eye_file, eye_rank).is_empty():
			continue
		if _can_land(board, to_file, to_rank, side):
			result.append({"file": to_file, "rank": to_rank})
	return result


func _horse_moves(board: Array, file: int, rank: int, piece: Dictionary) -> Array:
	var side := String(piece.get("side", ""))
	var candidates := [Vector2i(1, 2), Vector2i(-1, 2), Vector2i(1, -2), Vector2i(-1, -2), Vector2i(2, 1), Vector2i(2, -1), Vector2i(-2, 1), Vector2i(-2, -1)]
	var result: Array = []
	for to in candidates:
		var leg := _horse_leg_delta(to)
		if not _piece_at(board, file + leg.x, rank + leg.y).is_empty():
			continue
		var to_file: int = file + to.x
		var to_rank: int = rank + to.y
		if _in_board(to_file, to_rank) and _can_land(board, to_file, to_rank, side):
			result.append({"file": to_file, "rank": to_rank})
	return result


func _horse_leg_delta(move_delta: Vector2i) -> Vector2i:
	if abs(move_delta.x) == 2:
		return Vector2i(1 if move_delta.x > 0 else -1, 0)
	return Vector2i(0, 1 if move_delta.y > 0 else -1)


func _rook_moves(board: Array, file: int, rank: int, piece: Dictionary) -> Array:
	return _line_moves(board, file, rank, String(piece.get("side", "")), false)


func _cannon_moves(board: Array, file: int, rank: int, piece: Dictionary) -> Array:
	return _line_moves(board, file, rank, String(piece.get("side", "")), true)


func _line_moves(board: Array, file: int, rank: int, side: String, cannon: bool) -> Array:
	var result: Array = []
	for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var seen_screen := false
		var to_file: int = file + dir.x
		var to_rank: int = rank + dir.y
		while _in_board(to_file, to_rank):
			var target := _piece_at(board, to_file, to_rank)
			if not cannon:
				if target.is_empty():
					result.append({"file": to_file, "rank": to_rank})
				else:
					if String(target.get("side", "")) != side:
						result.append({"file": to_file, "rank": to_rank})
					break
			else:
				if not seen_screen:
					if target.is_empty():
						result.append({"file": to_file, "rank": to_rank})
					else:
						seen_screen = true
				else:
					if not target.is_empty():
						if String(target.get("side", "")) != side:
							result.append({"file": to_file, "rank": to_rank})
						break
			to_file += dir.x
			to_rank += dir.y
	return result


func _soldier_moves(board: Array, file: int, rank: int, piece: Dictionary) -> Array:
	var side := String(piece.get("side", ""))
	var result: Array = []
	var forward := 1 if side == SIDE_RED else -1
	var candidates := [Vector2i(0, forward)]
	if (side == SIDE_RED and rank >= 5) or (side == SIDE_BLACK and rank <= 4):
		candidates.append(Vector2i(1, 0))
		candidates.append(Vector2i(-1, 0))
	for delta in candidates:
		var to_file: int = file + delta.x
		var to_rank: int = rank + delta.y
		if _in_board(to_file, to_rank) and _can_land(board, to_file, to_rank, side):
			result.append({"file": to_file, "rank": to_rank})
	return result


func _can_land(board: Array, file: int, rank: int, side: String) -> bool:
	if not _in_board(file, rank):
		return false
	var target := _piece_at(board, file, rank)
	return target.is_empty() or String(target.get("side", "")) != side


func _in_board(file: int, rank: int) -> bool:
	return file >= 0 and file <= 8 and rank >= 0 and rank <= 9


func _in_palace(side: String, file: int, rank: int) -> bool:
	if file < 3 or file > 5:
		return false
	if side == SIDE_RED:
		return rank >= 0 and rank <= 2
	return rank >= 7 and rank <= 9


func _move_keeps_self_safe(state: Dictionary, side: String, from: Dictionary, to: Dictionary) -> bool:
	var test := state.duplicate(true)
	var board: Array = _board(test).duplicate(true)
	for i in range(board.size()):
		if board[i] is Array:
			board[i] = (board[i] as Array).duplicate(true)
	var piece := _piece_at(board, int(from.get("file", -1)), int(from.get("rank", -1)))
	_set_piece(board, int(from.get("file", -1)), int(from.get("rank", -1)), {})
	_set_piece(board, int(to.get("file", -1)), int(to.get("rank", -1)), piece)
	test["board"] = board
	return _side_in_check(test, side) == ""


func _side_in_check(state: Dictionary, side: String) -> String:
	var board: Array = _board(state)
	var king := _find_king(board, side)
	if king.is_empty():
		return side
	if _kings_face(board):
		return side
	var enemy := _opponent(side)
	for rank in range(10):
		for file in range(9):
			var piece := _piece_at(board, file, rank)
			if piece.is_empty() or String(piece.get("side", "")) != enemy:
				continue
			for move in _pseudo_moves_for_piece(board, file, rank, piece):
				if int(move.get("file", -1)) == int(king.get("file", -1)) and int(move.get("rank", -1)) == int(king.get("rank", -1)):
					return side
	return ""


func _find_king(board: Array, side: String) -> Dictionary:
	for rank in range(10):
		for file in range(9):
			var piece := _piece_at(board, file, rank)
			if String(piece.get("side", "")) == side and String(piece.get("kind", "")) == "king":
				return {"file": file, "rank": rank}
	return {}


func _kings_face(board: Array) -> bool:
	var red := _find_king(board, SIDE_RED)
	var black := _find_king(board, SIDE_BLACK)
	if red.is_empty() or black.is_empty():
		return false
	if int(red.get("file", -1)) != int(black.get("file", -1)):
		return false
	var file := int(red.get("file", -1))
	var start := mini(int(red.get("rank", 0)), int(black.get("rank", 0))) + 1
	var end := maxi(int(red.get("rank", 0)), int(black.get("rank", 0)))
	for rank in range(start, end):
		if not _piece_at(board, file, rank).is_empty():
			return false
	return true


func _apply_terminal_state(state: Dictionary, side_to_move: String) -> void:
	var legal := legal_moves_for_side(state, side_to_move)
	if not legal.is_empty():
		return
	var checked := _side_in_check(state, side_to_move) != ""
	state["game_result"] = RESULT_RED_WIN if side_to_move == SIDE_BLACK else RESULT_BLACK_WIN
	state["phase"] = "completed"
	state["result_reason"] = "checkmate" if checked else "stalemate"


func _game_over(state: Dictionary) -> bool:
	return String(state.get("game_result", RESULT_PLAYING)) != RESULT_PLAYING


func _is_playing(state: Dictionary) -> bool:
	return bool(state.get("started", false)) and String(state.get("phase", "")) == "playing"


func _has_pending_offer(state: Dictionary) -> bool:
	var draw_value = state.get("pending_draw_offer", {})
	var undo_value = state.get("pending_undo_offer", {})
	return (draw_value is Dictionary and not (draw_value as Dictionary).is_empty()) or (undo_value is Dictionary and not (undo_value as Dictionary).is_empty())


func _valid_side(side: String) -> bool:
	return side == SIDE_RED or side == SIDE_BLACK


func _opponent(side: String) -> String:
	return SIDE_BLACK if side == SIDE_RED else SIDE_RED


func _move_label(piece: Dictionary, from: Dictionary, to: Dictionary) -> String:
	return "%s%s%d,%d-%d,%d" % [
		side_label(String(piece.get("side", ""))),
		piece_label(piece),
		int(from.get("file", 0)) + 1,
		int(from.get("rank", 0)) + 1,
		int(to.get("file", 0)) + 1,
		int(to.get("rank", 0)) + 1,
	]


func _error(code: String, message: String) -> Dictionary:
	return {"ok": false, "error": code, "message": message}
