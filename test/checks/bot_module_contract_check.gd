extends SceneTree


func _initialize() -> void:
	_check_profile_context_and_report_isolation()
	_check_memory_contracts()
	quit(0)


func _check_profile_context_and_report_isolation() -> void:
	var repository = load("res://scripts/core/bot/bot_profile_repository.gd").new()
	repository.load_or_seed([])
	var memory_manager = load("res://scripts/core/memory/memory_manager.gd").new()
	memory_manager.persistence_enabled = false
	memory_manager.prefer_android_sqlite = false
	memory_manager.load_or_create()
	var facade = load("res://scripts/core/bot/bot_capability_facade.gd").new()
	facade.configure(repository, memory_manager)

	var create_alpha: Dictionary = facade.create_or_get_bot_profile({
		"bot_id": "bot_contract_alpha",
		"display_name": "契约甲",
		"persona_id": "persona_careful",
		"personality": {"risk": "low"},
		"speaking_style": "短句",
		"strategy_style": "先验证后行动",
		"background_story": "长期负责证据复核。",
	})
	_expect(bool(create_alpha.get("ok", false)), "alpha profile should be created")
	var alpha_profile: Dictionary = (create_alpha.get("data", {}) as Dictionary).get("bot_profile", {}) as Dictionary
	_expect(String(alpha_profile.get("persona_id", "")) == "persona_careful", "persona_id should be preserved")
	_expect(String(alpha_profile.get("speaking_style", "")) == "短句", "speaking style should be preserved")
	_expect(int(alpha_profile.get("created_at", 0)) > 0, "profile should expose created_at")

	var create_beta: Dictionary = facade.create_or_get_bot_profile({
		"bot_id": "bot_contract_beta",
		"display_name": "契约乙",
	})
	_expect(bool(create_beta.get("ok", false)), "beta profile should be created")

	var hidden_context: Dictionary = facade.build_bot_context({
		"bot_id": "bot_contract_alpha",
		"visible_context": {
			"schema_version": 1,
			"adapter_version": 1,
			"visible_entities": [{"id": "entity_a"}],
			"public_events": [{"content": "不可见事实", "visibility": "hidden"}],
		},
	})
	_expect(not bool(hidden_context.get("ok", true)), "hidden visible context should be rejected")
	_expect(String(hidden_context.get("code", "")) == "visible_context_privacy_risk", "hidden context should use privacy risk code")

	var alpha_context: Dictionary = facade.build_bot_context({
		"bot_id": "bot_contract_alpha",
		"visible_context": {
			"schema_version": 1,
			"adapter_version": 1,
			"visible_entities": [{"id": "entity_a"}],
			"public_events": [{"content": "甲的公开事实"}],
			"current_task": {"instruction": "分析甲。"},
		},
	})
	_expect(bool(alpha_context.get("ok", false)), "alpha context should build")
	var beta_context: Dictionary = facade.build_bot_context({
		"bot_id": "bot_contract_beta",
		"visible_context": {
			"schema_version": 1,
			"adapter_version": 1,
			"visible_entities": [{"id": "entity_b"}],
			"public_events": [{"content": "乙的公开事实"}],
			"current_task": {"instruction": "分析乙。"},
		},
	})
	_expect(bool(beta_context.get("ok", false)), "beta context should build")

	var alpha_reports: Dictionary = facade.get_bot_memory_reports({"bot_id": "bot_contract_alpha", "report_types": ["context_build"]})
	var alpha_latest: Dictionary = ((alpha_reports.get("data", {}) as Dictionary).get("latest", {}) as Dictionary).get("context_build", {}) as Dictionary
	_expect(String(alpha_latest.get("bot_id", "")) == "bot_contract_alpha", "alpha context report should stay scoped")
	var beta_reports: Dictionary = facade.get_bot_memory_reports({"bot_id": "bot_contract_beta", "report_types": ["context_build"]})
	var beta_latest: Dictionary = ((beta_reports.get("data", {}) as Dictionary).get("latest", {}) as Dictionary).get("context_build", {}) as Dictionary
	_expect(String(beta_latest.get("bot_id", "")) == "bot_contract_beta", "beta context report should stay scoped")


func _check_memory_contracts() -> void:
	var manager = load("res://scripts/core/memory/memory_manager.gd").new()
	manager.persistence_enabled = false
	manager.prefer_android_sqlite = false
	manager.load_or_create()
	var scope: Dictionary = manager.scope("bot_contract", "bot", "bot_contract", "profile")

	var rejected_update: Dictionary = manager.update_memory({
		"bot_id": "bot_contract",
		"scope": scope,
		"memory_update": {
			"visibility": "self_private",
			"episodic_events": [
				{"content": "模型草稿不能写入。", "confirmed": false},
			],
		},
	})
	_expect(bool(rejected_update.get("ok", false)), "rejected update should return a report")
	var rejected_report: Dictionary = (rejected_update.get("data", {}) as Dictionary).get("memory_update_report", {}) as Dictionary
	_expect((rejected_report.get("rejected", []) as Array).size() == 1, "unconfirmed item should be rejected")
	var rejected_counts: Dictionary = (rejected_update.get("data", {}) as Dictionary).get("memory_counts", {}) as Dictionary
	_expect(int(rejected_counts.get("episodic", 0)) == 0, "unconfirmed item should not be written")

	var update_result: Dictionary = manager.update_memory({
		"bot_id": "bot_contract",
		"scope": scope,
		"update_reason": "confirmed_event",
		"memory_update": {
			"visibility": "self_private",
			"relationship_updates": [
				{"target_id": "entity_a", "target_type": "entity", "content": "entity_a 多次合作。", "delta": "trust_up", "confidence": 0.80},
			],
			"semantic_candidates": [
				{"content": "entity_a 当前状态为可信。", "subject_id": "entity_a", "status": "active", "claim_key": "entity_a_state", "claim_value": "trusted", "polarity": "positive"},
				{"content": "entity_a 当前状态为不可信。", "subject_id": "entity_a", "status": "active", "claim_key": "entity_a_state", "claim_value": "untrusted", "polarity": "negative"},
			],
		},
	})
	_expect(bool(update_result.get("ok", false)), "confirmed relationship/conflict update should succeed")
	var maintenance: Dictionary = manager.maintain_memory({
		"bot_id": "bot_contract",
		"scope": scope,
		"maintenance_type": "manual",
		"options": {"enable_distillation": false, "enable_merge": false, "enable_forgetting": false},
	})
	_expect(bool(maintenance.get("ok", false)), "maintenance should succeed")
	var maintenance_report: Dictionary = (maintenance.get("data", {}) as Dictionary).get("maintenance_report", {}) as Dictionary
	_expect(int(maintenance_report.get("relationship_update_count", 0)) >= 1, "relationship evolution should run")
	_expect(int(maintenance_report.get("conflict_count", 0)) >= 1, "conflict detection should run")
	var overview: Dictionary = manager.get_memory_overview({"bot_id": "bot_contract", "scope": scope})
	var overview_data: Dictionary = overview.get("data", {}) as Dictionary
	var relationship_state: Dictionary = overview_data.get("relationship_state", {}) as Dictionary
	_expect(not (relationship_state.get("entity_a", {}) as Dictionary).is_empty(), "relationship state should include entity_a")
	var conflict_records: Array = overview_data.get("conflict_records", []) as Array
	_expect(conflict_records.size() >= 1, "conflict records should be exposed")

	var future_manager = load("res://scripts/core/memory/memory_manager.gd").new()
	future_manager.persistence_enabled = false
	future_manager.prefer_android_sqlite = false
	future_manager.load_or_create()
	var future_scope: Dictionary = future_manager.scope("future_bot", "bot", "future_bot", "profile")
	var future_states := {}
	future_states[future_manager.scope_key(future_scope)] = {
		"scope": future_scope,
		"memory_schema_version": 99,
		"memory_records": [],
	}
	future_manager._apply_json({"states": future_states})
	var future_overview: Dictionary = future_manager.get_memory_overview({"bot_id": "future_bot", "scope": future_scope})
	var future_health: Dictionary = (future_overview.get("data", {}) as Dictionary).get("memory_health", {}) as Dictionary
	_expect(String(future_health.get("status", "")) == "empty", "non-current schema should be discarded")
	var future_write: Dictionary = future_manager.update_memory({
		"bot_id": "future_bot",
		"scope": future_scope,
		"memory_update": {"episodic_events": [{"content": "按当前 schema 写入。"}]},
	})
	_expect(bool(future_write.get("ok", false)), "current schema should accept writes after discard")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
