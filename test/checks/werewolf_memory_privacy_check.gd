extends SceneTree

const BuilderScript := preload("res://scripts/room/werewolf/player/ai_robot/ai_werewolf_turn_context_builder.gd")
const MemoryScript := preload("res://scripts/room/werewolf/player/ai_robot/ai_werewolf_memory.gd")
const MemoryContextScript := preload("res://scripts/room/werewolf/player/ai_robot/ai_werewolf_memory_context.gd")


func _initialize() -> void:
	var builder = BuilderScript.new()
	var memory = MemoryScript.new()
	var memory_context = MemoryContextScript.new()
	var input := _input()

	var seer_events: Array = builder.visible_timeline_events(input, 10, 2)
	var seer_observation: Dictionary = memory.observation_entry_from_timeline_events(input["werewolf"] as Dictionary, input["players"] as Array, 2, seer_events)
	var seer_content := String(seer_observation.get("content", ""))
	assert(not seer_content.contains("今晚刀4号"))
	assert(not seer_content.contains("狼队投票"))
	assert(seer_content.contains("请选择今晚查验谁"))

	var wolf_events: Array = builder.visible_timeline_events(input, 10, 0)
	var wolf_observation: Dictionary = memory.observation_entry_from_timeline_events(input["werewolf"] as Dictionary, input["players"] as Array, 0, wolf_events)
	var wolf_content := String(wolf_observation.get("content", ""))
	assert(wolf_content.contains("今晚刀4号"))
	assert(wolf_content.count("今晚刀4号") == 1)

	var merged: Array = memory_context.merge_retrieved_memory([
		{
			"content": "近期相关记忆：狼队私聊：今晚刀4号。",
			"source": "recent",
			"metadata": {"kind": "visible_context"},
		},
		{
			"content": "预言家查验4号是好人。",
			"source": "recent",
			"metadata": {"kind": "seer_check"},
		},
	], [], 4)
	assert(merged.size() == 1)
	assert(String((merged[0] as Dictionary).get("content", "")) == "预言家查验4号是好人。")
	quit()


func _input() -> Dictionary:
	return {
		"room_id": "memory_privacy_check",
		"werewolf": {
			"phase": "seer_action",
			"day": 1,
			"current_action": {"key": "seer_check", "actor_index": 2, "label": "查验"},
			"night": {},
		},
		"players": [
			_player("wolf_a", "甲", "wolf"),
			_player("wolf_b", "乙", "wolf"),
			_player("seer_c", "丙", "seer"),
			_player("villager_d", "丁", "villager"),
		],
		"history": [
			{"speaker": "主持人", "text": "第1夜开始。", "visibility": "public", "at": 1.0},
			{"speaker": "1号 甲", "text": "今晚刀4号。", "actor_index": 0, "speaker_index": 0, "visibility": "wolf", "action_key": "wolf_chat", "at": 2.0},
			{"speaker": "主持人", "text": "狼队投票：请 1号 甲 选择今晚袭击目标。", "visibility": "wolf", "action_key": "wolf_kill", "at": 3.0},
			{"speaker": "主持人", "text": "私密询问：3号 丙 请选择今晚查验谁。", "visibility": "private", "visible_to_indices": [2], "actor_index": 2, "action_key": "seer_check", "at": 4.0},
		],
		"wolf_private_history": [
			{"speaker": "1号 甲", "text": "今晚刀4号。", "actor_index": 0, "actor_id": "old_wolf_a", "day": 1, "phase": "wolf_chat", "at": 2.0},
		],
		"wolf_target_votes": {},
		"wolf_speech_count": 1,
		"max_wolf_night_chat_messages": 3,
		"phase_label": "预言家行动",
		"map_rule_text": "4人检查局规则。",
	}


func _player(id: String, name: String, role_key: String) -> Dictionary:
	var role_names := {
		"wolf": "狼人",
		"seer": "预言家",
		"villager": "村民",
	}
	return {
		"id": id,
		"name": name,
		"role": String(role_names.get(role_key, role_key)),
		"role_key": role_key,
		"alive": true,
		"ready": true,
		"owner": "bot",
	}
