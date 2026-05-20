extends SceneTree


func _initialize() -> void:
	var state = load("res://scripts/core/app_state.gd").new()
	state.persistence_enabled = false
	state.load_or_create()
	state.create_room("狼人杀", 6, "", "basic_village", "标准村庄")

	var packed := load("res://scenes/werewolf_room.tscn") as PackedScene
	var room := packed.instantiate() as Control
	room.set_app_state(state)
	root.add_child(room)
	await process_frame
	await process_frame

	room._players = [
		{"id": "self", "name": "我", "owner": "self", "participant_id": "host", "role": "村民", "role_key": "villager", "avatar": room._werewolf_avatar_path("villager"), "alive": true, "ready": true},
		{"id": "wolf", "name": "狼", "owner": "bot", "controller_participant_id": "host", "role": "狼人", "role_key": "wolf", "avatar": room._werewolf_avatar_path("wolf"), "alive": true, "ready": true},
		{"id": "seer", "name": "预言家", "owner": "human", "participant_id": "seer_peer", "role": "预言家", "role_key": "seer", "avatar": room._werewolf_avatar_path("seer"), "alive": true, "ready": true},
	]
	room._local_player_index = 0
	room._werewolf = room._engine.default_state()
	room._werewolf["started"] = true
	room._werewolf["phase"] = "wolf_action"
	room._werewolf["day"] = 1
	room._werewolf["current_action"] = {"key": "wolf_kill", "label": "狼人袭击", "actor_index": 1, "icon": "kill"}
	room._history = [
		{"speaker": "主持人", "text": "第1夜开始。", "visibility": "public", "at": 1.0},
		{"speaker": "2号 狼", "text": "选择袭击1号 我。", "speaker_index": 1, "actor_index": 1, "visibility": "wolf", "action_key": "wolf_kill", "at": 2.0},
		{"speaker": "3号 预言家", "text": "查验2号 狼：狼人阵营。", "speaker_index": 2, "actor_index": 2, "visibility": "private", "visible_to_indices": [2], "at": 3.0},
	]
	room._wolf_private_history = [
		{"speaker": "2号 狼", "speaker_index": 1, "text": "今晚先刀1号。", "day": 1, "phase": "wolf_chat", "at": 4.0},
	]
	var active_room: Dictionary = room._active_room()
	active_room["observers"] = [{"id": "host", "displayName": "本机观战"}, {"id": "observer_peer", "displayName": "观战者"}]
	room._show_center_speech_item({"speaker": "1号 我", "speaker_index": 0, "text": "我是一张好人牌。", "at": 5.0}, true)
	room._write_werewolf_debug_snapshot()

	var snapshot: Dictionary = room._debug_werewolf_room_snapshot()
	if not _expect(bool(snapshot.get("ok", false)), "snapshot ok"):
		return
	if not _expect(String(snapshot.get("api", "")) == "werewolf_room_debug_snapshot.v1", "snapshot api version"):
		return
	if not _expect((snapshot.get("players", []) as Array).size() == 3, "snapshot players"):
		return
	if not _expect(int((snapshot.get("counts", {}) as Dictionary).get("wolfPrivateHistory", 0)) == 1, "snapshot wolf private count"):
		return
	if not _expect(FileAccess.file_exists("user://werewolf_room_debug_snapshot.json"), "snapshot file is written"):
		return

	var villager_view := _view(snapshot, "player_1")
	var wolf_view := _view(snapshot, "player_2")
	var observer_view := _view(snapshot, "observer_1")
	if not _expect(not villager_view.is_empty(), "villager view exists"):
		return
	if not _expect(not wolf_view.is_empty(), "wolf view exists"):
		return
	if not _expect(not observer_view.is_empty(), "observer view exists"):
		return
	if not _expect((villager_view.get("visibleHistory", []) as Array).size() == 1, "villager sees only public history"):
		return
	if not _expect((villager_view.get("wolfPrivateHistory", []) as Array).is_empty(), "villager cannot see wolf private history"):
		return
	if not _expect(not bool((villager_view.get("currentAction", {}) as Dictionary).get("viewerCanControl", true)), "villager cannot control wolf action"):
		return
	if not _expect((wolf_view.get("visibleHistory", []) as Array).size() == 2, "wolf sees public and wolf history"):
		return
	if not _expect((wolf_view.get("wolfPrivateHistory", []) as Array).size() == 1, "wolf sees wolf private history"):
		return
	if not _expect(bool((wolf_view.get("currentAction", {}) as Dictionary).get("viewerCanControl", false)), "wolf controls own action"):
		return
	if not _expect((observer_view.get("visibleHistory", []) as Array).size() == 3, "observer sees all history"):
		return
	if not _expect((observer_view.get("wolfPrivateHistory", []) as Array).size() == 1, "observer sees wolf private history"):
		return
	if not _expect((snapshot.get("botDebug", {}) as Dictionary).has("requestTracker"), "bot debug is present"):
		return
	if not _expect((snapshot.get("ttsDebug", {}) as Dictionary).has("runtime"), "tts debug is present"):
		return
	if not _expect((snapshot.get("centerSpeech", {}) as Dictionary).has("items"), "center speech debug is present"):
		return
	room._werewolf["phase"] = "completed"
	room._werewolf["winner"] = "good"
	room._werewolf["post_game"] = {"stage": "completed", "mvp_index": 0}
	var final_payload: Dictionary = room._debug_werewolf_final_perspective_text_payload()
	if not _expect(String(final_payload.get("api", "")) == "werewolf_final_perspective_text_debug.v1", "final perspective debug api version"):
		return
	var final_villager_view := _view(final_payload, "player_1")
	var final_wolf_view := _view(final_payload, "player_2")
	if not _expect(not final_villager_view.is_empty(), "final villager view exists"):
		return
	if not _expect(not final_wolf_view.is_empty(), "final wolf view exists"):
		return
	var villager_arrays: Dictionary = final_villager_view.get("renderArrays", {})
	var wolf_arrays: Dictionary = final_wolf_view.get("renderArrays", {})
	if not _expect((villager_arrays.get("visibleHistoryText", []) as Array).has("主持人:第1夜开始。"), "final villager visible history text rendered"):
		return
	if not _expect((villager_arrays.get("wolfPrivateHistoryText", []) as Array).is_empty(), "final villager private wolf text hidden"):
		return
	if not _expect((wolf_arrays.get("wolfPrivateHistoryText", []) as Array).has("2号 狼:今晚先刀1号。"), "final wolf private history text rendered"):
		return
	if not _expect((wolf_arrays.get("modelTimelineText", []) as Array).has("狼队:今晚先刀1号。"), "final wolf model timeline text rendered"):
		return
	if not _expect((wolf_arrays.get("modelPlayerText", []) as Array).any(func(text): return String(text).contains("role=狼人")), "final model player text includes role"):
		return

	room.queue_free()
	quit(0)


func _view(snapshot: Dictionary, key: String) -> Dictionary:
	var views: Array = snapshot.get("views", [])
	for item in views:
		if item is Dictionary and String((item as Dictionary).get("key", "")) == key:
			return item as Dictionary
	return {}


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("werewolf_room_debug_snapshot_check failed: %s" % message)
	quit(1)
	return false
