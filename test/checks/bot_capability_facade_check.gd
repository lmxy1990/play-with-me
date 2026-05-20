extends SceneTree


func _initialize() -> void:
	var repository = load("res://scripts/core/bot/bot_profile_repository.gd").new()
	repository.load_or_seed([])
	var memory_manager = load("res://scripts/core/memory/memory_manager.gd").new()
	memory_manager.persistence_enabled = false
	memory_manager.prefer_android_sqlite = false
	memory_manager.load_or_create()
	var facade = load("res://scripts/core/bot/bot_capability_facade.gd").new()
	facade.configure(repository, memory_manager)

	var create_result: Dictionary = facade.create_or_get_bot_profile({
		"bot_id": "bot_alpha",
		"display_name": "阿尔法",
		"avatar_id": "avatar_01",
		"description": "测试机器人",
		"initial_persona": {"content": "谨慎，重视证据。"},
		"model": "qwen:test",
		"voice": "系统默认",
	})
	_expect(bool(create_result.get("ok", false)), "create profile should succeed")
	var profile: Dictionary = (create_result.get("data", {}) as Dictionary).get("bot_profile", {}) as Dictionary
	_expect(String(profile.get("bot_id", "")) == "bot_alpha", "explicit bot_id should be preserved")
	_expect(String(profile.get("avatar_id", "")) == "avatar_01", "avatar_id should be preserved")
	var rename_result: Dictionary = facade.update_bot_profile({
		"bot_id": "bot_alpha",
		"display_name": "被忽略的改名",
		"description": "更新后的说明",
		"model": "deepseek:test",
	})
	_expect(bool(rename_result.get("ok", false)), "update profile should succeed")
	var renamed_profile: Dictionary = (rename_result.get("data", {}) as Dictionary).get("bot_profile", {}) as Dictionary
	_expect(String(renamed_profile.get("display_name", "")) == "阿尔法", "bot display name should not be changed by update")
	_expect(String(renamed_profile.get("description", "")) == "更新后的说明", "other profile fields should still update")
	_expect(String(renamed_profile.get("model", "")) == "deepseek:test", "model should still update")

	var list_result: Dictionary = facade.list_bot_profiles({"query": "阿尔法"})
	_expect(int((list_result.get("data", {}) as Dictionary).get("total", 0)) == 1, "profile list should find bot")

	var init_result: Dictionary = facade.initialize_bot({
		"bot_id": "bot_alpha",
		"reason": "bot_created",
		"relationship_targets": [
			{"target_id": "player_1", "target_type": "player", "content": "对1号玩家保持观察。"},
		],
	})
	_expect(bool(init_result.get("ok", false)), "initialize should succeed")
	var init_data: Dictionary = init_result.get("data", {}) as Dictionary
	_expect(("persona_snapshot" in (init_data.get("initialized_parts", []) as Array)), "persona should initialize")
	_expect(("relationship_memory" in (init_data.get("initialized_parts", []) as Array)), "relationship should initialize")

	var commit_result: Dictionary = facade.commit_bot_result({
		"bot_id": "bot_alpha",
		"commit_reason": "confirmed_event",
		"memory_update": {
			"visibility": "self_private",
			"working_update": {"current_goal": "继续验证1号玩家发言。"},
			"episodic_events": [
				{"content": "1号玩家连续两轮发言立场摇摆。", "subject_id": "player_1", "importance": 0.74, "confidence": 0.82},
			],
			"semantic_candidates": [
				{"content": "连续立场摇摆需要结合投票记录复核。", "importance": 0.78, "confidence": 0.70},
			],
		},
	})
	_expect(bool(commit_result.get("ok", false)), "commit should succeed")
	var commit_data: Dictionary = commit_result.get("data", {}) as Dictionary
	_expect(("working" in (commit_data.get("updated_layers", []) as Array)), "working layer should update")
	_expect(("episodic" in (commit_data.get("updated_layers", []) as Array)), "episodic layer should update")

	var overview_result: Dictionary = facade.get_bot_memory_overview({
		"bot_id": "bot_alpha",
		"include_recent_samples": true,
	})
	_expect(bool(overview_result.get("ok", false)), "overview should succeed")
	var overview_data: Dictionary = overview_result.get("data", {}) as Dictionary
	var summary: Dictionary = overview_data.get("bot_profile_summary", {}) as Dictionary
	_expect(String(summary.get("display_name", "")) == "阿尔法", "overview should include profile summary")
	var counts: Dictionary = overview_data.get("layer_counts", {}) as Dictionary
	_expect(int(counts.get("profile", 0)) == 1, "profile count should be 1")
	_expect(int(counts.get("working", 0)) == 1, "working count should be 1")
	_expect(int(counts.get("relationship", 0)) == 1, "relationship count should be 1")
	_expect(int(counts.get("episodic", 0)) == 1, "episodic count should be 1")
	_expect(int(counts.get("semantic", 0)) == 1, "semantic count should be 1")
	var index_status: Dictionary = overview_data.get("index_status", {}) as Dictionary
	_expect(String(index_status.get("retrieval_mode", "")) == "hybrid_vector", "retrieval mode should be hybrid vector")
	_expect(bool(index_status.get("vector_enabled", false)), "vector should be enabled")
	_expect(bool(index_status.get("sqlite_vec_event_enabled", false)), "event vector index should be enabled")
	_expect(bool(index_status.get("hnsw_semantic_enabled", false)), "semantic HNSW index should be enabled")

	var record_list: Dictionary = facade.list_bot_memory_records({
		"bot_id": "bot_alpha",
		"memory_type": "episodic",
		"redact_private": false,
	})
	_expect(bool(record_list.get("ok", false)), "record list should succeed")
	var record_items: Array = (record_list.get("data", {}) as Dictionary).get("items", []) as Array
	_expect(record_items.size() == 1, "episodic list should contain one record")
	var record_id := String((record_items[0] as Dictionary).get("memory_id", ""))
	_expect(record_id != "", "record id should exist")
	var detail_result: Dictionary = facade.get_bot_memory_record_detail({
		"bot_id": "bot_alpha",
		"memory_id": record_id,
	})
	_expect(bool(detail_result.get("ok", false)), "record detail should succeed")
	var detail_record: Dictionary = (detail_result.get("data", {}) as Dictionary).get("record", {}) as Dictionary
	_expect(String(detail_record.get("content", "")) == "[private]", "detail should redact private content by default")

	var context_result: Dictionary = facade.build_bot_context({
		"bot_id": "bot_alpha",
		"task_type": "analyze_entity",
		"visible_context": {
			"current_task": {"instruction": "分析1号玩家是否可信。"},
			"visible_entities": [{"id": "player_1", "name": "1号玩家"}],
			"public_events": [{"text": "1号玩家连续两轮发言立场摇摆。"}],
		},
		"memory_options": {"final_max_items": 8, "max_token_budget": 2048},
	})
	_expect(bool(context_result.get("ok", false)), "context build should succeed")
	var reasoning_context: Dictionary = (context_result.get("data", {}) as Dictionary).get("reasoning_context", {}) as Dictionary
	_expect(String(reasoning_context.get("bot_id", "")) == "bot_alpha", "reasoning context should include bot id")
	_expect(not (reasoning_context.get("memory_context", {}) as Dictionary).is_empty(), "reasoning context should include memory")
	_expect(int(reasoning_context.get("context_schema_version", 0)) == 1, "reasoning context should expose schema version")
	_expect(not (reasoning_context.get("token_budget", {}) as Dictionary).is_empty(), "reasoning context should include token budget")

	var mismatch_result: Dictionary = facade.build_bot_context({
		"bot_id": "bot_alpha",
		"visible_context": {"bot_id": "bot_other"},
	})
	_expect(not bool(mismatch_result.get("ok", true)), "mismatched visible_context bot_id should fail")
	_expect(String(mismatch_result.get("code", "")) == "visible_context_bot_mismatch", "mismatch should return stable code")

	var preview_result: Dictionary = facade.preview_bot_memory_context({
		"bot_id": "bot_alpha",
		"query": "1号玩家 立场 摇摆",
		"visible_context": {"visible_entities": [{"id": "player_1"}]},
	})
	_expect(bool(preview_result.get("ok", false)), "memory preview should succeed")
	var preview_report: Dictionary = (preview_result.get("data", {}) as Dictionary).get("retrieval_report", {}) as Dictionary
	_expect(String(preview_report.get("retrieval_mode", "")) == "hybrid_vector", "preview should expose hybrid mode")

	var reports_result: Dictionary = facade.get_bot_memory_reports({
		"bot_id": "bot_alpha",
		"report_types": ["context_build", "memory_update", "maintenance", "index"],
	})
	_expect(bool(reports_result.get("ok", false)), "reports should succeed")
	var latest_reports: Dictionary = ((reports_result.get("data", {}) as Dictionary).get("latest", {}) as Dictionary)
	_expect(not (latest_reports.get("context_build", {}) as Dictionary).is_empty(), "context report should exist")
	_expect(not (latest_reports.get("memory_update", {}) as Dictionary).is_empty(), "memory update report should exist")
	_expect(not (latest_reports.get("index", {}) as Dictionary).is_empty(), "index report should exist")

	var maintenance_result: Dictionary = facade.request_bot_memory_maintenance({
		"bot_id": "bot_alpha",
		"maintenance_type": "manual",
		"options": {"clear_working_memory": true},
	})
	_expect(bool(maintenance_result.get("ok", false)), "maintenance should succeed")
	var after_maintenance: Dictionary = facade.get_bot_memory_overview({"bot_id": "bot_alpha"})
	var after_counts: Dictionary = ((after_maintenance.get("data", {}) as Dictionary).get("layer_counts", {}) as Dictionary)
	_expect(int(after_counts.get("working", 0)) == 0, "maintenance should clear working memory")

	var delete_result: Dictionary = facade.delete_bot_profile({"bot_id": "bot_alpha"})
	_expect(bool(delete_result.get("ok", false)), "delete profile should succeed")
	var after_delete_list: Dictionary = facade.list_bot_profiles({})
	_expect(int((after_delete_list.get("data", {}) as Dictionary).get("total", 0)) == 0, "profile list should be empty after delete")
	_expect(memory_manager.list_scopes("bot_alpha").is_empty(), "delete should clear owned memory scopes")
	quit(0)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
