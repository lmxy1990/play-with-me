extends SceneTree


func _initialize() -> void:
	var engine = load("res://scripts/room/xiangqi/xiangqi_engine.gd").new()
	_check_default_state(engine)
	_check_actions_require_started(engine)
	_check_opening_move_and_turn(engine)
	_check_wrong_side_rejected(engine)
	_check_horse_leg_block(engine)
	_check_elephant_eye_and_river(engine)
	_check_cannon_screen(engine)
	_check_flying_king_and_self_check(engine)
	_check_pending_offer_blocks_play(engine)
	_check_draw_undo_resign(engine)
	_check_undo_restores_capture_list(engine)
	_check_app_state_xiangqi_room()
	quit()


func _check_default_state(engine) -> void:
	var state: Dictionary = engine.default_state()
	_expect(String(state.get("game_id", "")) == "xiangqi", "default state game id mismatch")
	_expect(String(state.get("phase", "")) == "lobby", "default state phase mismatch")
	_expect(not bool(state.get("started", true)), "default state should wait in lobby")
	_expect(String(state.get("side_to_move", "")) == engine.SIDE_RED, "red should move first")
	_expect(int(state.get("turn_number", 0)) == 1, "turn number should start at 1")
	_expect((state.get("board", []) as Array).size() == 10, "board should have 10 ranks")
	_expect(engine.board_summary(state).size() == 32, "initial board should have 32 pieces")
	_expect(engine.legal_moves_for_side(state, engine.SIDE_RED).size() > 0, "red should have legal opening moves")


func _check_actions_require_started(engine) -> void:
	var state: Dictionary = engine.default_state()
	var move: Dictionary = engine.apply_move(state, 0, 3, 0, 4)
	_expect(not bool(move.get("ok", false)), "move should require started game")
	_expect(String(move.get("error", "")) == "not_playing", "not started move error mismatch")
	var draw: Dictionary = engine.offer_draw(state, engine.SIDE_RED)
	_expect(not bool(draw.get("ok", false)), "draw should require started game")
	var resign: Dictionary = engine.resign(state, engine.SIDE_RED)
	_expect(not bool(resign.get("ok", false)), "resign should require started game")


func _check_opening_move_and_turn(engine) -> void:
	var state: Dictionary = engine.start_state()
	var result: Dictionary = engine.apply_move(state, 0, 3, 0, 4)
	_expect(bool(result.get("ok", false)), "red soldier opening move should be legal")
	var next: Dictionary = result.get("state", {})
	_expect(String(next.get("side_to_move", "")) == engine.SIDE_BLACK, "side should switch after move")
	_expect(int(next.get("ply_number", -1)) == 1, "ply should increment after move")
	_expect(int(next.get("turn_number", -1)) == 1, "turn should stay 1 after red first move")
	_expect((next.get("move_history", []) as Array).size() == 1, "move history should record accepted move")


func _check_wrong_side_rejected(engine) -> void:
	var state: Dictionary = engine.start_state()
	var result: Dictionary = engine.apply_move(state, 0, 6, 0, 5)
	_expect(not bool(result.get("ok", false)), "black cannot move on red turn")
	_expect(String(result.get("error", "")) == "wrong_side", "wrong side error mismatch")


func _check_horse_leg_block(engine) -> void:
	var center := _custom_state(engine, [
		_piece(4, 4, engine.SIDE_RED, "horse"),
		_piece(4, 0, engine.SIDE_RED, "king"),
		_piece(4, 1, engine.SIDE_RED, "soldier"),
		_piece(4, 9, engine.SIDE_BLACK, "king"),
	])
	var center_moves: Array = engine.legal_moves_from(center, 4, 4)
	for target in [[5, 6], [3, 6], [5, 2], [3, 2], [6, 5], [6, 3], [2, 5], [2, 3]]:
		_expect(_has_target(center_moves, int(target[0]), int(target[1])), "horse should move in 日 shape")
	for illegal in [[4, 5], [5, 5], [6, 4], [4, 6]]:
		_expect(not _has_target(center_moves, int(illegal[0]), int(illegal[1])), "horse should not move like king or elephant")

	var blocked := _custom_state(engine, [
		_piece(1, 0, engine.SIDE_RED, "horse"),
		_piece(1, 1, engine.SIDE_RED, "soldier"),
		_piece(4, 0, engine.SIDE_RED, "king"),
		_piece(4, 5, engine.SIDE_RED, "soldier"),
		_piece(4, 9, engine.SIDE_BLACK, "king"),
	])
	var moves: Array = engine.legal_moves_from(blocked, 1, 0)
	_expect(not _has_target(moves, 0, 2), "horse should not jump through blocked leg")
	_expect(not _has_target(moves, 2, 2), "horse should not jump through blocked leg")
	var open := _custom_state(engine, [
		_piece(1, 0, engine.SIDE_RED, "horse"),
		_piece(4, 0, engine.SIDE_RED, "king"),
		_piece(4, 5, engine.SIDE_RED, "soldier"),
		_piece(4, 9, engine.SIDE_BLACK, "king"),
	])
	moves = engine.legal_moves_from(open, 1, 0)
	_expect(_has_target(moves, 0, 2), "horse should move when leg is open")
	_expect(_has_target(moves, 2, 2), "horse should move when leg is open")

	var block_up := _custom_state(engine, [
		_piece(4, 4, engine.SIDE_RED, "horse"),
		_piece(4, 5, engine.SIDE_RED, "soldier"),
		_piece(4, 0, engine.SIDE_RED, "king"),
		_piece(4, 9, engine.SIDE_BLACK, "king"),
	])
	moves = engine.legal_moves_from(block_up, 4, 4)
	_expect(not _has_target(moves, 3, 6), "horse upper leg should block up-left target")
	_expect(not _has_target(moves, 5, 6), "horse upper leg should block up-right target")

	var block_down := _custom_state(engine, [
		_piece(4, 4, engine.SIDE_RED, "horse"),
		_piece(4, 3, engine.SIDE_RED, "soldier"),
		_piece(4, 0, engine.SIDE_RED, "king"),
		_piece(4, 9, engine.SIDE_BLACK, "king"),
	])
	moves = engine.legal_moves_from(block_down, 4, 4)
	_expect(not _has_target(moves, 3, 2), "horse lower leg should block down-left target")
	_expect(not _has_target(moves, 5, 2), "horse lower leg should block down-right target")

	var block_left := _custom_state(engine, [
		_piece(4, 4, engine.SIDE_RED, "horse"),
		_piece(3, 4, engine.SIDE_RED, "soldier"),
		_piece(4, 0, engine.SIDE_RED, "king"),
		_piece(4, 9, engine.SIDE_BLACK, "king"),
	])
	moves = engine.legal_moves_from(block_left, 4, 4)
	_expect(not _has_target(moves, 2, 3), "horse left leg should block left-down target")
	_expect(not _has_target(moves, 2, 5), "horse left leg should block left-up target")

	var block_right := _custom_state(engine, [
		_piece(4, 4, engine.SIDE_RED, "horse"),
		_piece(5, 4, engine.SIDE_RED, "soldier"),
		_piece(4, 0, engine.SIDE_RED, "king"),
		_piece(4, 9, engine.SIDE_BLACK, "king"),
	])
	moves = engine.legal_moves_from(block_right, 4, 4)
	_expect(not _has_target(moves, 6, 3), "horse right leg should block right-down target")
	_expect(not _has_target(moves, 6, 5), "horse right leg should block right-up target")


func _check_elephant_eye_and_river(engine) -> void:
	var blocked := _custom_state(engine, [
		_piece(2, 0, engine.SIDE_RED, "elephant"),
		_piece(3, 1, engine.SIDE_RED, "soldier"),
		_piece(4, 0, engine.SIDE_RED, "king"),
		_piece(4, 5, engine.SIDE_RED, "soldier"),
		_piece(4, 9, engine.SIDE_BLACK, "king"),
	])
	var moves: Array = engine.legal_moves_from(blocked, 2, 0)
	_expect(not _has_target(moves, 4, 2), "elephant eye should block diagonal move")
	var open := _custom_state(engine, [
		_piece(2, 4, engine.SIDE_RED, "elephant"),
		_piece(4, 0, engine.SIDE_RED, "king"),
		_piece(4, 5, engine.SIDE_RED, "soldier"),
		_piece(4, 9, engine.SIDE_BLACK, "king"),
	])
	moves = engine.legal_moves_from(open, 2, 4)
	_expect(not _has_target(moves, 4, 6), "red elephant should not cross river")
	_expect(_has_target(moves, 0, 2), "red elephant should move inside own side")


func _check_cannon_screen(engine) -> void:
	var state := _custom_state(engine, [
		_piece(1, 2, engine.SIDE_RED, "cannon"),
		_piece(1, 5, engine.SIDE_RED, "soldier"),
		_piece(1, 7, engine.SIDE_BLACK, "horse"),
		_piece(4, 0, engine.SIDE_RED, "king"),
		_piece(4, 5, engine.SIDE_RED, "soldier"),
		_piece(4, 9, engine.SIDE_BLACK, "king"),
	])
	var moves: Array = engine.legal_moves_from(state, 1, 2)
	_expect(_has_target(moves, 1, 3), "cannon should move before screen")
	_expect(not _has_target(moves, 1, 5), "cannon cannot land on own screen")
	_expect(_has_target(moves, 1, 7), "cannon should capture over exactly one screen")


func _check_flying_king_and_self_check(engine) -> void:
	var state := _custom_state(engine, [
		_piece(4, 0, engine.SIDE_RED, "king"),
		_piece(4, 1, engine.SIDE_RED, "rook"),
		_piece(4, 9, engine.SIDE_BLACK, "king"),
	])
	var result: Dictionary = engine.apply_move(state, 4, 1, 3, 1)
	_expect(not bool(result.get("ok", false)), "move exposing flying kings should be rejected")
	_expect(String(result.get("error", "")) == "illegal_move", "self check should be illegal move")


func _check_pending_offer_blocks_play(engine) -> void:
	var state: Dictionary = engine.start_state()
	var draw: Dictionary = engine.offer_draw(state, engine.SIDE_RED)
	_expect(bool(draw.get("ok", false)), "draw setup should be accepted")
	var draw_state: Dictionary = draw.get("state", {})
	var move: Dictionary = engine.apply_move(draw_state, 0, 3, 0, 4)
	_expect(not bool(move.get("ok", false)), "move should wait for pending draw response")
	_expect(String(move.get("error", "")) == "pending_offer", "pending draw move error mismatch")
	var second_draw: Dictionary = engine.offer_draw(draw_state, engine.SIDE_BLACK)
	_expect(not bool(second_draw.get("ok", false)), "second draw offer should be rejected while pending")
	_expect(String(second_draw.get("error", "")) == "pending_offer", "duplicate draw error mismatch")

	var moved: Dictionary = engine.apply_move(state, 0, 3, 0, 4)
	_expect(bool(moved.get("ok", false)), "undo setup move should be accepted")
	var undo: Dictionary = engine.offer_undo(moved.get("state", {}), engine.SIDE_BLACK)
	_expect(bool(undo.get("ok", false)), "undo setup should be accepted")
	var undo_state: Dictionary = undo.get("state", {})
	var blocked_move: Dictionary = engine.apply_move(undo_state, 0, 6, 0, 5)
	_expect(not bool(blocked_move.get("ok", false)), "move should wait for pending undo response")
	_expect(String(blocked_move.get("error", "")) == "pending_offer", "pending undo move error mismatch")
	var blocked_draw: Dictionary = engine.offer_draw(undo_state, engine.SIDE_RED)
	_expect(not bool(blocked_draw.get("ok", false)), "draw should be rejected while undo is pending")


func _check_draw_undo_resign(engine) -> void:
	var state: Dictionary = engine.start_state()
	var draw: Dictionary = engine.offer_draw(state, engine.SIDE_RED)
	_expect(bool(draw.get("ok", false)), "draw offer should be accepted")
	var draw_state: Dictionary = draw.get("state", {})
	_expect(not (draw_state.get("pending_draw_offer", {}) as Dictionary).is_empty(), "draw offer should be pending")
	var draw_response: Dictionary = engine.respond_draw(draw_state, engine.SIDE_BLACK, true)
	_expect(bool(draw_response.get("ok", false)), "draw response should be accepted")
	_expect(String((draw_response.get("state", {}) as Dictionary).get("game_result", "")) == engine.RESULT_DRAW, "accepted draw should end as draw")

	var moved: Dictionary = engine.apply_move(state, 0, 3, 0, 4)
	_expect(bool(moved.get("ok", false)), "setup move should be accepted")
	var undo_offer: Dictionary = engine.offer_undo(moved.get("state", {}), engine.SIDE_RED)
	_expect(bool(undo_offer.get("ok", false)), "undo offer should be accepted after a move")
	var undo_response: Dictionary = engine.respond_undo(undo_offer.get("state", {}), engine.SIDE_BLACK, true)
	_expect(bool(undo_response.get("ok", false)), "undo response should be accepted")
	var undo_state: Dictionary = undo_response.get("state", {})
	_expect((undo_state.get("move_history", []) as Array).is_empty(), "undo should remove last move")
	_expect(String(undo_state.get("side_to_move", "")) == engine.SIDE_RED, "undo should restore side to move")

	var resign: Dictionary = engine.resign(state, engine.SIDE_RED)
	_expect(bool(resign.get("ok", false)), "resign should be accepted")
	_expect(String((resign.get("state", {}) as Dictionary).get("game_result", "")) == engine.RESULT_BLACK_WIN, "red resign should make black win")


func _check_undo_restores_capture_list(engine) -> void:
	var state := _custom_state(engine, [
		_piece(4, 0, engine.SIDE_RED, "king"),
		_piece(0, 0, engine.SIDE_RED, "rook"),
		_piece(4, 5, engine.SIDE_RED, "soldier"),
		_piece(0, 3, engine.SIDE_BLACK, "horse"),
		_piece(4, 9, engine.SIDE_BLACK, "king"),
	])
	var captured_move: Dictionary = engine.apply_move(state, 0, 0, 0, 3)
	_expect(bool(captured_move.get("ok", false)), "rook capture setup should be accepted")
	var captured_state: Dictionary = captured_move.get("state", {})
	_expect((captured_state.get("captured_pieces", []) as Array).size() == 1, "capture should append captured piece")
	var undo_offer: Dictionary = engine.offer_undo(captured_state, engine.SIDE_BLACK)
	_expect(bool(undo_offer.get("ok", false)), "capture undo offer should be accepted")
	var undo_response: Dictionary = engine.respond_undo(undo_offer.get("state", {}), engine.SIDE_RED, true)
	_expect(bool(undo_response.get("ok", false)), "capture undo response should be accepted")
	var undo_state: Dictionary = undo_response.get("state", {})
	_expect((undo_state.get("captured_pieces", []) as Array).is_empty(), "undo should remove restored capture from captured list")
	var restored := _piece_at_state(undo_state, 0, 3)
	_expect(String(restored.get("side", "")) == engine.SIDE_BLACK and String(restored.get("kind", "")) == "horse", "undo should restore captured piece")
	_expect(String(undo_state.get("side_to_move", "")) == engine.SIDE_RED, "capture undo should restore side to move")


func _check_app_state_xiangqi_room() -> void:
	var state = load("res://scripts/core/app_state.gd").new()
	state.persistence_enabled = false
	state.load_or_create()
	var room: Dictionary = state.create_room("象棋", 2, "", "xiangqi_standard", "标准象棋", true, 3, {
		"game_room_id": "xiangqi",
		"clock_enabled": true,
		"time_limit_ms": 600000,
	})
	_expect(String(room.get("game_room_id", "")) == "xiangqi", "created room should be xiangqi")
	_expect(String(room.get("type", "")) == "象棋", "created room type should be xiangqi")
	_expect(int(room.get("max_players", 0)) == 2, "xiangqi room should have two seats")
	_expect(bool(room.get("clock_enabled", false)), "xiangqi clock option should be stored")
	_expect(not state.xiangqi.is_empty(), "xiangqi state should be initialized")
	_expect(state.werewolf.is_empty(), "werewolf state should be empty for xiangqi room")
	_expect(String(state.xiangqi.get("game_id", "")) == "xiangqi", "xiangqi state game id mismatch")
	_expect(bool(state.xiangqi.get("clock_enabled", false)), "xiangqi engine should receive clock option")


func _custom_state(engine, pieces: Array) -> Dictionary:
	var board: Array = []
	for _rank in range(10):
		var row: Array = []
		for _file in range(9):
			row.append({})
		board.append(row)
	for item_value in pieces:
		var item: Dictionary = item_value
		var rank := int(item.get("rank", 0))
		var file := int(item.get("file", 0))
		var row: Array = board[rank]
		row[file] = {"side": String(item.get("side", "")), "kind": String(item.get("kind", ""))}
		board[rank] = row
	return {
		"game_id": "xiangqi",
		"phase": "playing",
		"started": true,
		"paused": false,
		"board": board,
		"side_to_move": engine.SIDE_RED,
		"turn_number": 1,
		"ply_number": 0,
		"move_history": [],
		"captured_pieces": [],
		"last_move": {},
		"check_side": "",
		"pending_draw_offer": {},
		"pending_undo_offer": {},
		"clock_enabled": false,
		"clock_state": {},
		"game_result": engine.RESULT_PLAYING,
		"result_reason": "",
	}


func _piece(file: int, rank: int, side: String, kind: String) -> Dictionary:
	return {"file": file, "rank": rank, "side": side, "kind": kind}


func _has_target(moves: Array, file: int, rank: int) -> bool:
	for move_value in moves:
		if move_value is Dictionary and int((move_value as Dictionary).get("file", -1)) == file and int((move_value as Dictionary).get("rank", -1)) == rank:
			return true
	return false


func _piece_at_state(state: Dictionary, file: int, rank: int) -> Dictionary:
	var board_value = state.get("board", [])
	if not (board_value is Array):
		return {}
	var board: Array = board_value
	if rank < 0 or rank >= board.size() or not (board[rank] is Array):
		return {}
	var row: Array = board[rank]
	if file < 0 or file >= row.size() or not (row[file] is Dictionary):
		return {}
	return (row[file] as Dictionary).duplicate(true)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	assert(false, message)
