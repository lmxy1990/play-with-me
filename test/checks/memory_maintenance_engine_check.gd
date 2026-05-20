extends SceneTree


func _initialize() -> void:
	var manager = load("res://scripts/core/memory/memory_manager.gd").new()
	manager.persistence_enabled = false
	manager.prefer_android_sqlite = false
	manager.load_or_create()
	var scope: Dictionary = manager.scope("bot_maintenance", "bot", "bot_maintenance", "profile")
	var now := Time.get_unix_time_from_system()
	var update_result: Dictionary = manager.update_memory({
		"bot_id": "bot_maintenance",
		"scope": scope,
		"update_reason": "maintenance_check",
		"memory_update": {
			"visibility": "self_private",
			"episodic_events": [
				{
					"content": "这是一条过期且低价值的临时事件。",
					"importance": 0.05,
					"confidence": 0.10,
					"expires_at": now - 10.0,
				},
			],
			"semantic_candidates": [
				{
					"content": "复盘时优先说明结论并列出关键依据",
					"subject_id": "user_a",
					"importance": 0.82,
					"confidence": 0.84,
					"status": "active",
				},
				{
					"content": "复盘时优先说明结论并列出关键依据。",
					"subject_id": "user_a",
					"importance": 0.78,
					"confidence": 0.80,
					"status": "active",
				},
			],
		},
	})
	_expect(bool(update_result.get("ok", false)), "memory update should succeed")
	var index_before: Dictionary = manager.get_memory_index_status({"scope": scope}).get("data", {}) as Dictionary
	_expect(bool(index_before.get("vector_enabled", false)), "vector index should be ready before maintenance")

	var maintenance_result: Dictionary = manager.maintain_memory({
		"bot_id": "bot_maintenance",
		"scope": scope,
		"maintenance_type": "manual",
		"options": {
			"enable_distillation": false,
			"enable_merge": true,
			"enable_forgetting": true,
			"merge_threshold": 0.70,
			"forgetting_threshold": 0.20,
		},
	})
	_expect(bool(maintenance_result.get("ok", false)), "maintenance should succeed")
	var report: Dictionary = (maintenance_result.get("data", {}) as Dictionary).get("maintenance_report", {}) as Dictionary
	_expect(int(report.get("merged_count", 0)) >= 1, "maintenance should merge similar semantic memories")
	_expect(int(report.get("archived_count", 0)) >= 1, "maintenance should archive expired low-value memory")
	_expect(bool((report.get("index_status", {}) as Dictionary).get("vector_enabled", false)), "vector index should remain enabled")

	var semantic_list: Dictionary = manager.list_memory_records({
		"scope": scope,
		"memory_type": "semantic",
		"status": "active",
		"redact_private": false,
	})
	_expect(int((semantic_list.get("data", {}) as Dictionary).get("total", 0)) == 1, "similar semantic memories should collapse into one active record")
	var archived_list: Dictionary = manager.list_memory_records({
		"scope": scope,
		"memory_type": "episodic",
		"status": "archived",
		"redact_private": false,
	})
	_expect(int((archived_list.get("data", {}) as Dictionary).get("total", 0)) == 1, "expired episodic memory should be archived")
	quit(0)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
