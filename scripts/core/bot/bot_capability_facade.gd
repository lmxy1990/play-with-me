extends RefCounted
class_name BotCapabilityFacade

const BotProfileRepositoryScript := preload("res://scripts/core/bot/bot_profile_repository.gd")
const MemoryManagerScript := preload("res://scripts/core/memory/memory_manager.gd")
const BotContextBuilderScript := preload("res://scripts/core/bot/bot_context_builder.gd")

var _profile_repository = BotProfileRepositoryScript.new()
var _memory_manager = MemoryManagerScript.new()
var _context_builder = BotContextBuilderScript.new()
var _last_context_report: Dictionary = {}
var _last_maintenance_report: Dictionary = {}
var _last_context_reports_by_scope: Dictionary = {}
var _last_maintenance_reports_by_scope: Dictionary = {}


func configure(profile_repository = null, memory_manager = null, context_builder = null) -> void:
	if profile_repository != null:
		_profile_repository = profile_repository
	if memory_manager != null:
		_memory_manager = memory_manager
	if context_builder != null:
		_context_builder = context_builder


func list_bot_profiles(request: Dictionary = {}) -> Dictionary:
	var profiles: Array = _profile_repository.list_profiles()
	var enabled_only := bool(request.get("enabled_only", false))
	var query := String(request.get("query", "")).strip_edges().to_lower()
	var limit := maxi(1, int(request.get("limit", profiles.size() if profiles.size() > 0 else 50)))
	var offset := maxi(0, int(request.get("offset", 0)))
	var filtered: Array = []
	for item in profiles:
		if not (item is Dictionary):
			continue
		var profile: Dictionary = item
		if enabled_only and not bool(profile.get("enabled", true)):
			continue
		if query != "" and not _profile_matches_query(profile, query):
			continue
		filtered.append(_public_profile(profile))
	var total := filtered.size()
	var items: Array = []
	for i in range(offset, mini(total, offset + limit)):
		items.append(filtered[i])
	return _ok({
		"items": items,
		"total": total,
		"page_report": {
			"offset": offset,
			"limit": limit,
			"returned": items.size(),
			"enabled_only": enabled_only,
			"query": query,
		},
	})


func create_or_get_bot_profile(request: Dictionary) -> Dictionary:
	var requested_id := String(request.get("bot_id", request.get("id", ""))).strip_edges()
	if requested_id != "":
		var existing: Dictionary = _profile_repository.profile_by_key(requested_id)
		if not existing.is_empty():
			return _ok({"bot_profile": _public_profile(existing), "created": false})
	var requested_name := String(request.get("display_name", request.get("name", ""))).strip_edges()
	if requested_name != "":
		var by_name: Dictionary = _profile_repository.profile_by_key(requested_name)
		if not by_name.is_empty():
			return _ok({"bot_profile": _public_profile(by_name), "created": false})
	if requested_name == "":
		requested_name = _profile_repository.next_default_name()
	var save_request := {
		"id": requested_id,
		"name": requested_name,
		"avatar_id": String(request.get("avatar_id", "")),
		"description": String(request.get("description", "")),
		"persona": _persona_text(request.get("initial_persona", request.get("persona", request.get("persona_template", "")))),
		"persona_id": String(request.get("persona_id", "")),
		"personality": _dict_or_empty(request.get("personality", {})),
		"speaking_style": String(request.get("speaking_style", "")),
		"strategy_style": String(request.get("strategy_style", "")),
		"background_story": String(request.get("background_story", "")),
		"model": String(request.get("model", "")),
		"voice": String(request.get("voice", "")),
		"enabled": bool(request.get("enabled", true)),
		"memory": _dict_or_empty(request.get("memory", {})),
	}
	var saved: Dictionary = _profile_repository.save_profile(-1, save_request)
	if not bool(saved.get("ok", false)):
		return _error("bot_profile_save_failed", String(saved.get("error", "机器人档案保存失败")))
	var profile := _dict_or_empty(saved.get("profile", {}))
	return _ok({"bot_profile": _public_profile(profile), "created": true})


func get_bot_profile(request: Dictionary) -> Dictionary:
	var profile := _require_profile(request)
	if profile.is_empty():
		return _bot_not_found(request)
	var data := {"bot_profile": _public_profile(profile)}
	if bool(request.get("include_runtime_state", false)):
		var overview := get_bot_memory_overview({
			"bot_id": String(profile.get("id", "")),
			"scope": _memory_scope_for_request(request, String(profile.get("id", ""))),
			"redact_private": true,
		})
		data["runtime_state"] = _dict_or_empty(overview.get("data", {}))
	return _ok(data)


func update_bot_profile(request: Dictionary) -> Dictionary:
	var bot_id := String(request.get("bot_id", request.get("id", ""))).strip_edges()
	var index := _profile_index(bot_id)
	if index < 0:
		return _bot_not_found(request)
	var existing: Dictionary = _profile_repository.profile_at(index)
	var save_request := {
		"id": bot_id,
		"name": String(request.get("name", request.get("display_name", existing.get("name", "")))),
		"avatar_id": String(request.get("avatar_id", existing.get("avatar_id", ""))),
		"description": String(request.get("description", existing.get("description", ""))),
		"persona": _persona_text(request.get("initial_persona", request.get("persona", existing.get("persona", "")))),
		"persona_id": String(request.get("persona_id", existing.get("persona_id", ""))),
		"personality": _dict_or_empty(request.get("personality", existing.get("personality", {}))),
		"speaking_style": String(request.get("speaking_style", existing.get("speaking_style", ""))),
		"strategy_style": String(request.get("strategy_style", existing.get("strategy_style", ""))),
		"background_story": String(request.get("background_story", existing.get("background_story", ""))),
		"model": String(request.get("model", existing.get("model", ""))),
		"voice": String(request.get("voice", existing.get("voice", ""))),
		"enabled": bool(request.get("enabled", existing.get("enabled", true))),
		"memory": _dict_or_empty(request.get("memory", existing.get("memory", {}))),
		"created_at": int(existing.get("created_at", 0)),
	}
	var saved: Dictionary = _profile_repository.save_profile(index, save_request)
	if not bool(saved.get("ok", false)):
		return _error("bot_profile_save_failed", String(saved.get("error", "机器人档案保存失败")))
	var profile := _dict_or_empty(saved.get("profile", {}))
	var seed_updated := false
	if request.has("initial_persona") or request.has("persona"):
		var initialized := initialize_bot({
			"bot_id": bot_id,
			"scope": _memory_scope_for_request(request, bot_id),
			"persona_template": {"content": String(profile.get("persona", ""))},
			"reason": String(request.get("reason", "bot_profile_updated")),
		})
		seed_updated = bool(initialized.get("ok", false))
	return _ok({
		"bot_profile": _public_profile(profile),
		"memory_seed_updated": seed_updated,
	})


func delete_bot_profile(request: Dictionary) -> Dictionary:
	var profile := _require_profile(request)
	if profile.is_empty():
		return _bot_not_found(request)
	var bot_id := String(profile.get("id", "")).strip_edges()
	var index := _profile_index(bot_id)
	if index < 0:
		return _bot_not_found(request)
	var profile_copy: Dictionary = profile.duplicate(true)
	var result: Dictionary = _profile_repository.delete_profile(index)
	if not bool(result.get("ok", false)):
		return _error("bot_profile_delete_failed", String(result.get("error", "机器人档案删除失败")))
	var delete_memory := bool(request.get("delete_memory", true))
	var deleted_scopes: Array = []
	if delete_memory:
		for item in _memory_manager.list_scopes(bot_id):
			if not (item is Dictionary):
				continue
			var scope_data: Dictionary = item
			_memory_manager.delete_scope(scope_data)
			deleted_scopes.append(scope_data.duplicate(true))
	return _ok({
		"deleted": true,
		"bot_profile": _public_profile(profile_copy),
		"delete_memory": delete_memory,
		"deleted_memory_scopes": deleted_scopes,
	})


func initialize_bot(request: Dictionary) -> Dictionary:
	var profile := _require_profile(request)
	if profile.is_empty():
		return _bot_not_found(request)
	var bot_id := String(profile.get("id", ""))
	var scope_data := _memory_scope_for_request(request, bot_id)
	var persona_template = request.get("persona_template", {})
	if _persona_text(persona_template) == "":
		persona_template = _profile_persona_template(profile)
	var init_request := request.duplicate(true)
	init_request["bot_id"] = bot_id
	init_request["scope"] = scope_data
	init_request["persona_template"] = persona_template
	if request.has("relationship_targets") and not request.has("initial_relationship_targets"):
		init_request["initial_relationship_targets"] = _array_or_empty(request.get("relationship_targets", []))
	if not init_request.has("reason"):
		init_request["reason"] = "manual"
	var result: Dictionary = _memory_manager.init_memory(init_request)
	if not bool(result.get("ok", false)):
		return result
	var data := _dict_or_empty(result.get("data", {}))
	data["bot_id"] = bot_id
	data["bot_profile"] = _public_profile(profile)
	data["memory_scope"] = scope_data.duplicate(true)
	data["initialized_parts"] = _initialized_parts(init_request)
	return _ok(data, _array_or_empty(result.get("warnings", [])))


func build_bot_context(request: Dictionary) -> Dictionary:
	var profile := _require_profile(request)
	if profile.is_empty():
		return _bot_not_found(request)
	var bot_id := String(profile.get("id", ""))
	var scope_data := _memory_scope_for_request(request, bot_id)
	var context_request_result: Dictionary = _context_builder.build_memory_context_request(request, profile, scope_data)
	if not bool(context_request_result.get("ok", false)):
		return context_request_result
	var context_request_data := _dict_or_empty(context_request_result.get("data", {}))
	var visible_context := _dict_or_empty(context_request_data.get("visible_context", {}))
	var memory_request := _dict_or_empty(context_request_data.get("memory_request", {}))
	var memory_result: Dictionary = _memory_manager.get_memory_context(memory_request)
	var memory_data := _dict_or_empty(memory_result.get("data", {}))
	var memory_context := _dict_or_empty(memory_data.get("memory_context", {}))
	var retrieval_report := _dict_or_empty(memory_data.get("retrieval_report", {}))
	var warnings := _array_or_empty(context_request_result.get("warnings", []))
	for warning in _array_or_empty(memory_result.get("warnings", [])):
		if not warnings.has(warning):
			warnings.append(warning)
	var build_result: Dictionary = _context_builder.build_reasoning_context(request, profile, scope_data, visible_context, memory_context, warnings)
	if not bool(build_result.get("ok", false)):
		return build_result
	var build_data := _dict_or_empty(build_result.get("data", {}))
	var reasoning_context := _dict_or_empty(build_data.get("reasoning_context", {}))
	var budget_report := _dict_or_empty(build_data.get("budget_report", {}))
	_last_context_report = {
		"bot_id": bot_id,
		"scope": scope_data.duplicate(true),
		"task_type": String(reasoning_context.get("task_type", "")),
		"retrieval_report": retrieval_report,
		"budget_report": budget_report,
		"warnings": warnings,
		"created_at": Time.get_unix_time_from_system(),
	}
	_remember_context_report(scope_data, _last_context_report)
	return _ok({
		"bot_profile": _public_profile(profile),
		"reasoning_context": reasoning_context,
		"memory_context_used": memory_context,
		"budget_report": budget_report,
		"context_report": _last_context_report.duplicate(true),
	}, warnings)


func commit_bot_result(request: Dictionary) -> Dictionary:
	var profile := _require_profile(request)
	if profile.is_empty():
		return _bot_not_found(request)
	var bot_id := String(profile.get("id", ""))
	var scope_data := _memory_scope_for_request(request, bot_id)
	var commit_reason := String(request.get("commit_reason", request.get("update_reason", "confirmed_result"))).strip_edges()
	var memory_update := _dict_or_empty(request.get("memory_update", {}))
	if memory_update.is_empty():
		memory_update = _memory_update_from_confirmed_material(request, commit_reason)
	var update_request := request.duplicate(true)
	update_request["bot_id"] = bot_id
	update_request["scope"] = scope_data
	update_request["update_reason"] = commit_reason
	update_request["memory_update"] = memory_update
	var result: Dictionary = _memory_manager.update_memory(update_request)
	if not bool(result.get("ok", false)):
		return result
	var data := _dict_or_empty(result.get("data", {}))
	var report := _dict_or_empty(data.get("memory_update_report", {}))
	var updated_layers := _array_or_empty(report.get("updated_layers", []))
	return _ok({
		"updated": not updated_layers.is_empty(),
		"updated_layers": updated_layers,
		"memory_update_report": report,
		"maintenance_suggested": commit_reason == "session_end",
	}, _array_or_empty(result.get("warnings", [])))


func maintain_bot(request: Dictionary) -> Dictionary:
	var profile := _require_profile(request)
	if profile.is_empty():
		return _bot_not_found(request)
	var bot_id := String(profile.get("id", ""))
	var scope_data := _memory_scope_for_request(request, bot_id)
	var maintenance_type := String(request.get("maintenance_type", "manual")).strip_edges()
	var update_report: Dictionary = {}
	var clear_report: Dictionary = {}
	var generated_reflections := 0
	if request.get("session_end_memory_update", null) is Dictionary:
		var commit_result := commit_bot_result({
			"bot_id": bot_id,
			"scope": scope_data,
			"commit_reason": "session_end",
			"memory_update": request.get("session_end_memory_update", {}),
		})
		update_report = _dict_or_empty((_dict_or_empty(commit_result.get("data", {}))).get("memory_update_report", {}))
		generated_reflections = int((_dict_or_empty(update_report.get("layer_counts", {}))).get("reflection", 0))
	var options := _dict_or_empty(request.get("options", {}))
	var should_clear_working := bool(options.get("clear_working_memory", maintenance_type == "session_end"))
	var maintenance_result: Dictionary = _memory_manager.maintain_memory({
		"bot_id": bot_id,
		"scope": scope_data,
		"maintenance_type": maintenance_type,
		"operation": String(request.get("operation", "run_light_maintenance")),
		"options": options,
	})
	var maintenance_data := _dict_or_empty(maintenance_result.get("data", {}))
	var memory_maintenance_report := _dict_or_empty(maintenance_data.get("maintenance_report", {}))
	if should_clear_working:
		clear_report = _memory_manager.clear_working_memory({"scope": scope_data})
	_last_maintenance_report = {
		"bot_id": bot_id,
		"scope": scope_data.duplicate(true),
		"maintenance_type": maintenance_type,
		"operation": String(request.get("operation", "run_light_maintenance")),
		"maintained": true,
		"generated_reflections": generated_reflections,
		"distilled_memories": _array_or_empty(memory_maintenance_report.get("distilled_memories", [])),
		"relationship_updates": _array_or_empty(memory_maintenance_report.get("relationship_updates", [])),
		"conflict_records": _array_or_empty(memory_maintenance_report.get("conflict_records", [])),
		"merged_memories": _array_or_empty(memory_maintenance_report.get("merged_memories", [])),
		"archived_memories": _array_or_empty(memory_maintenance_report.get("archived_memories", [])),
		"distilled_count": int(memory_maintenance_report.get("distilled_count", 0)),
		"relationship_update_count": int(memory_maintenance_report.get("relationship_update_count", 0)),
		"conflict_count": int(memory_maintenance_report.get("conflict_count", 0)),
		"merged_count": int(memory_maintenance_report.get("merged_count", 0)),
		"archived_count": int(memory_maintenance_report.get("archived_count", 0)),
		"cleared_working_memory": should_clear_working,
		"memory_update_report": update_report,
		"memory_maintenance_report": memory_maintenance_report,
		"clear_working_report": clear_report,
		"warnings": _array_or_empty(maintenance_result.get("warnings", [])),
		"created_at": Time.get_unix_time_from_system(),
	}
	_remember_maintenance_report(scope_data, _last_maintenance_report)
	return _ok({
		"maintained": true,
		"generated_reflections": generated_reflections,
		"distilled_memories": int(memory_maintenance_report.get("distilled_count", 0)),
		"relationship_updates": int(memory_maintenance_report.get("relationship_update_count", 0)),
		"conflict_records": int(memory_maintenance_report.get("conflict_count", 0)),
		"merged_memories": int(memory_maintenance_report.get("merged_count", 0)),
		"archived_memories": int(memory_maintenance_report.get("archived_count", 0)),
		"cleared_working_memory": should_clear_working,
		"maintenance_report": _last_maintenance_report.duplicate(true),
	}, _array_or_empty(maintenance_result.get("warnings", [])))


func get_bot_debug_state(request: Dictionary) -> Dictionary:
	var profile := _require_profile(request)
	if profile.is_empty():
		return _bot_not_found(request)
	var overview := get_bot_memory_overview(request)
	var overview_data := _dict_or_empty(overview.get("data", {}))
	var reports := get_bot_memory_reports({
		"bot_id": String(profile.get("id", "")),
		"scope": _memory_scope_for_request(request, String(profile.get("id", ""))),
		"redact_private": bool(request.get("redact_private", true)),
	})
	var latest := _dict_or_empty((_dict_or_empty(reports.get("data", {}))).get("latest", {}))
	return _ok({
		"bot_profile": _public_profile(profile),
		"memory_health": _dict_or_empty(overview_data.get("memory_health", {})),
		"working_memory_overview": _working_memory_overview(request) if bool(request.get("include_working_memory", false)) else {},
		"last_context_report": _dict_or_empty(latest.get("context_build", {})) if bool(request.get("include_reports", false)) else {},
		"last_memory_update_report": _dict_or_empty(latest.get("memory_update", {})) if bool(request.get("include_reports", false)) else {},
		"last_maintenance_report": _dict_or_empty(latest.get("maintenance", {})) if bool(request.get("include_reports", false)) else {},
	})


func get_bot_memory_overview(request: Dictionary) -> Dictionary:
	var profile := _require_profile(request)
	if profile.is_empty():
		return _bot_not_found(request)
	var bot_id := String(profile.get("id", ""))
	var memory_request := request.duplicate(true)
	memory_request["bot_id"] = bot_id
	memory_request["scope"] = _memory_scope_for_request(request, bot_id)
	var result: Dictionary = _memory_manager.get_memory_overview(memory_request)
	if not bool(result.get("ok", false)):
		return result
	var data := _dict_or_empty(result.get("data", {}))
	data["bot_profile_summary"] = _profile_summary(profile)
	return _ok(data, _array_or_empty(result.get("warnings", [])))


func list_bot_memory_records(request: Dictionary) -> Dictionary:
	var profile := _require_profile(request)
	if profile.is_empty():
		return _bot_not_found(request)
	var memory_request := request.duplicate(true)
	memory_request["bot_id"] = String(profile.get("id", ""))
	memory_request["scope"] = _memory_scope_for_request(request, String(profile.get("id", "")))
	return _memory_manager.list_memory_records(memory_request)


func get_bot_memory_record_detail(request: Dictionary) -> Dictionary:
	var profile := _require_profile(request)
	if profile.is_empty():
		return _bot_not_found(request)
	var memory_id := String(request.get("memory_id", "")).strip_edges()
	if memory_id == "":
		return _error("memory_id_required", "memory_id 不能为空")
	var bot_id := String(profile.get("id", ""))
	var scope_data := _memory_scope_for_request(request, bot_id)
	var state: Dictionary = _memory_manager.load_state(scope_data)
	var redact_private := bool(request.get("redact_private", true))
	var record := _find_memory_record(state, memory_id)
	if record.is_empty():
		return _error("memory_record_not_found", "未找到记忆记录")
	var visible_record := _redacted_record(record, redact_private)
	var include_evidence := bool(request.get("include_evidence", false))
	var include_debug_fields := bool(request.get("include_debug_fields", false))
	return _ok({
		"record": visible_record,
		"evidence": _array_or_empty(record.get("evidence", [])) if include_evidence else [],
		"debug_fields": _debug_fields(record) if include_debug_fields else {},
	})


func get_bot_memory_reports(request: Dictionary) -> Dictionary:
	var profile := _require_profile(request)
	if profile.is_empty():
		return _bot_not_found(request)
	var memory_request := request.duplicate(true)
	memory_request["bot_id"] = String(profile.get("id", ""))
	memory_request["scope"] = _memory_scope_for_request(request, String(profile.get("id", "")))
	var result: Dictionary = _memory_manager.get_memory_reports(memory_request)
	if not bool(result.get("ok", false)):
		return result
	var data := _dict_or_empty(result.get("data", {}))
	var latest := _dict_or_empty(data.get("latest", {}))
	var scope_data := _memory_scope_for_request(request, String(profile.get("id", "")))
	var context_report := _context_report_for_scope(scope_data)
	if not context_report.is_empty():
		latest["context_build"] = context_report
	var maintenance_report := _maintenance_report_for_scope(scope_data)
	if not maintenance_report.is_empty():
		latest["maintenance"] = maintenance_report
	data["latest"] = latest
	data["reports"] = _reports_from_latest(latest, _array_or_empty(memory_request.get("report_types", ["context_build", "memory_update", "maintenance", "index"])), int(memory_request.get("limit", 20)))
	return _ok(data, _array_or_empty(result.get("warnings", [])))


func get_bot_memory_index_status(request: Dictionary) -> Dictionary:
	var profile := _require_profile(request)
	if profile.is_empty():
		return _bot_not_found(request)
	var memory_request := request.duplicate(true)
	memory_request["bot_id"] = String(profile.get("id", ""))
	memory_request["scope"] = _memory_scope_for_request(request, String(profile.get("id", "")))
	return _memory_manager.get_memory_index_status(memory_request)


func preview_bot_memory_context(request: Dictionary) -> Dictionary:
	var profile := _require_profile(request)
	if profile.is_empty():
		return _bot_not_found(request)
	var bot_id := String(profile.get("id", ""))
	var scope_data := _memory_scope_for_request(request, bot_id)
	var context_request_result: Dictionary = _context_builder.build_memory_context_request(request, profile, scope_data)
	if not bool(context_request_result.get("ok", false)):
		return context_request_result
	var context_request_data := _dict_or_empty(context_request_result.get("data", {}))
	var memory_request := _dict_or_empty(context_request_data.get("memory_request", {}))
	var result: Dictionary = _memory_manager.get_memory_context(memory_request)
	if not bool(result.get("ok", false)):
		return result
	var data := _dict_or_empty(result.get("data", {}))
	var report := _dict_or_empty(data.get("retrieval_report", {}))
	return _ok({
		"memory_context": _dict_or_empty(data.get("memory_context", {})),
		"items": _array_or_empty(data.get("items", [])),
		"retrieval_report": report,
		"budget_report": _dict_or_empty(report.get("budget_report", {})),
	}, _array_or_empty(result.get("warnings", [])))


func request_bot_memory_maintenance(request: Dictionary) -> Dictionary:
	var result := maintain_bot(request)
	if not bool(result.get("ok", false)):
		return result
	var data := _dict_or_empty(result.get("data", {}))
	return _ok({
		"maintenance_started": true,
		"maintenance_report": _dict_or_empty(data.get("maintenance_report", {})),
		"job_id": "",
	})


func get_last_context_report(request: Dictionary = {}) -> Dictionary:
	var report := _last_context_report.duplicate(true)
	var scope_data := _scope_from_last_report_request(request)
	if not scope_data.is_empty():
		report = _context_report_for_scope(scope_data)
	return _ok({"context_report": report})


func get_last_memory_update_report(request: Dictionary = {}) -> Dictionary:
	var memory_request := request.duplicate(true)
	var scope_data := _scope_from_last_report_request(request)
	if not scope_data.is_empty():
		memory_request["scope"] = scope_data
	return _ok({"memory_update_report": _memory_manager.get_last_update_report(memory_request)})


func get_last_maintenance_report(request: Dictionary = {}) -> Dictionary:
	var report := _last_maintenance_report.duplicate(true)
	var scope_data := _scope_from_last_report_request(request)
	if not scope_data.is_empty():
		report = _maintenance_report_for_scope(scope_data)
	return _ok({"maintenance_report": report})


func _require_profile(request: Dictionary) -> Dictionary:
	var bot_id := String(request.get("bot_id", request.get("id", ""))).strip_edges()
	if bot_id == "":
		return {}
	return _profile_repository.profile_by_key(bot_id)


func _bot_not_found(request: Dictionary) -> Dictionary:
	var bot_id := String(request.get("bot_id", request.get("id", ""))).strip_edges()
	return _error("bot_not_found", "未找到机器人：%s" % bot_id)


func _profile_index(bot_id: String) -> int:
	var key := bot_id.strip_edges()
	if key == "":
		return -1
	var profiles: Array = _profile_repository.list_profiles()
	for i in range(profiles.size()):
		if profiles[i] is Dictionary and String((profiles[i] as Dictionary).get("id", "")) == key:
			return i
	return -1


func _profile_matches_query(profile: Dictionary, query: String) -> bool:
	return (
		String(profile.get("name", "")).to_lower().contains(query)
		or String(profile.get("id", "")).to_lower().contains(query)
		or String(profile.get("description", "")).to_lower().contains(query)
		or String(profile.get("persona", "")).to_lower().contains(query)
		or String(profile.get("persona_id", "")).to_lower().contains(query)
		or String(profile.get("speaking_style", "")).to_lower().contains(query)
		or String(profile.get("strategy_style", "")).to_lower().contains(query)
		or String(profile.get("background_story", "")).to_lower().contains(query)
	)


func _public_profile(profile: Dictionary) -> Dictionary:
	var id := String(profile.get("id", ""))
	return {
		"id": id,
		"bot_id": id,
		"name": String(profile.get("name", "")),
		"display_name": String(profile.get("name", "")),
		"avatar_id": String(profile.get("avatar_id", "")),
		"persona_id": String(profile.get("persona_id", "")),
		"description": String(profile.get("description", "")),
		"persona": String(profile.get("persona", "")),
		"personality": _dict_or_empty(profile.get("personality", {})),
		"speaking_style": String(profile.get("speaking_style", "")),
		"strategy_style": String(profile.get("strategy_style", "")),
		"background_story": String(profile.get("background_story", "")),
		"model": String(profile.get("model", "")),
		"voice": String(profile.get("voice", "")),
		"enabled": bool(profile.get("enabled", true)),
		"memory": _dict_or_empty(profile.get("memory", {})),
		"schema_version": int(profile.get("schema_version", 1)),
		"created_at": int(profile.get("created_at", 0)),
		"updated_at": int(profile.get("updated_at", 0)),
	}


func _profile_summary(profile: Dictionary) -> Dictionary:
	return {
		"bot_id": String(profile.get("id", "")),
		"display_name": String(profile.get("name", "")),
		"avatar_id": String(profile.get("avatar_id", "")),
		"persona_id": String(profile.get("persona_id", "")),
		"model": String(profile.get("model", "")),
		"voice": String(profile.get("voice", "")),
		"enabled": bool(profile.get("enabled", true)),
		"has_persona": String(profile.get("persona", "")).strip_edges() != "",
		"has_background_story": String(profile.get("background_story", "")).strip_edges() != "",
		"schema_version": int(profile.get("schema_version", 1)),
	}


func _profile_persona_template(profile: Dictionary) -> Dictionary:
	var parts: Array = []
	var persona := String(profile.get("persona", "")).strip_edges()
	var description := String(profile.get("description", "")).strip_edges()
	var background_story := String(profile.get("background_story", "")).strip_edges()
	var speaking_style := String(profile.get("speaking_style", "")).strip_edges()
	var strategy_style := String(profile.get("strategy_style", "")).strip_edges()
	var memory := _dict_or_empty(profile.get("memory", {}))
	var profile_memory := String(memory.get("profile", "")).strip_edges()
	if persona != "":
		parts.append(persona)
	if description != "":
		parts.append(description)
	if background_story != "":
		parts.append(background_story)
	if speaking_style != "":
		parts.append("表达风格：%s" % speaking_style)
	if strategy_style != "":
		parts.append("长期策略偏好：%s" % strategy_style)
	if profile_memory != "":
		parts.append(profile_memory)
	return {"content": "\n".join(parts)}


func _memory_scope_for_request(request: Dictionary, bot_id: String) -> Dictionary:
	var raw_scope := _dict_or_empty(request.get("scope", {}))
	var owner_id := String(raw_scope.get("owner_id", bot_id)).strip_edges()
	if owner_id == "":
		owner_id = bot_id
	var game_id := String(raw_scope.get("game_id", raw_scope.get("domain_id", request.get("domain_id", "bot")))).strip_edges()
	if game_id == "":
		game_id = "bot"
	var memory_namespace := String(raw_scope.get("namespace", request.get("memory_namespace", bot_id))).strip_edges()
	if memory_namespace == "":
		memory_namespace = bot_id
	var map_id := String(raw_scope.get("map_id", raw_scope.get("instance_id", request.get("instance_id", "profile")))).strip_edges()
	if map_id == "":
		map_id = "profile"
	var room_id := String(raw_scope.get("room_id", raw_scope.get("session_id", request.get("session_id", "")))).strip_edges()
	var scope_data: Dictionary = _memory_manager.scope(owner_id, game_id, memory_namespace, map_id, room_id)
	scope_data["domain_id"] = game_id
	scope_data["session_id"] = room_id
	scope_data["instance_id"] = map_id
	scope_data["lifecycle_stage"] = String(raw_scope.get("lifecycle_stage", request.get("lifecycle_stage", ""))).strip_edges()
	scope_data["visibility_mode"] = String(raw_scope.get("visibility_mode", request.get("visibility_mode", ""))).strip_edges()
	scope_data["metadata"] = _dict_or_empty(raw_scope.get("metadata", request.get("scope_metadata", {})))
	return scope_data


func _initialized_parts(request: Dictionary) -> Array:
	var result: Array = []
	if _persona_text(request.get("persona_template", {})) != "":
		result.append("persona_snapshot")
	if not _array_or_empty(request.get("initial_relationship_targets", [])).is_empty():
		result.append("relationship_memory")
	return result


func _memory_update_from_confirmed_material(request: Dictionary, commit_reason: String) -> Dictionary:
	var events: Array = []
	var evidence: Array = []
	for key in ["accepted_outputs", "accepted_dialogues", "confirmed_events"]:
		for item in _array_or_empty(request.get(key, [])):
			var entry := _event_from_material(item, key, commit_reason)
			if entry.is_empty():
				continue
			events.append(entry)
			evidence.append({
				"source": key,
				"content": String(entry.get("content", "")),
			})
	var outcome := _dict_or_empty(request.get("outcome", {}))
	if not outcome.is_empty():
		var outcome_text := _material_content(outcome)
		if outcome_text != "":
			events.append({"content": outcome_text, "source": commit_reason, "importance": 0.64, "confidence": 0.74})
			evidence.append({"source": "outcome", "content": outcome_text})
	return {
		"visibility": String(request.get("visibility", "self_private")),
		"episodic_events": events,
		"evidence": evidence,
	}


func _event_from_material(item, source: String, commit_reason: String) -> Dictionary:
	var content := _material_content(item)
	if content == "":
		return {}
	var result := {
		"content": content,
		"source": source if source != "" else commit_reason,
		"importance": 0.58,
		"confidence": 0.72,
	}
	if item is Dictionary:
		var data: Dictionary = item
		result["subject_id"] = String(data.get("subject_id", data.get("target_id", data.get("actor_id", ""))))
		result["subject_type"] = String(data.get("subject_type", data.get("target_type", "")))
		result["structured_payload"] = data.duplicate(true)
	return result


func _material_content(item) -> String:
	if item is Dictionary:
		var data: Dictionary = item
		for key in ["content", "text", "summary", "message", "result", "action"]:
			var value := String(data.get(key, "")).strip_edges()
			if value != "":
				return value
		return JSON.stringify(data)
	return String(item).strip_edges()


func _working_memory_overview(request: Dictionary) -> Dictionary:
	var list_result := list_bot_memory_records({
		"bot_id": String(request.get("bot_id", "")),
		"scope": request.get("scope", {}),
		"memory_type": "working",
		"limit": 8,
		"redact_private": bool(request.get("redact_private", true)),
	})
	return _dict_or_empty(list_result.get("data", {}))


func _find_memory_record(state: Dictionary, memory_id: String) -> Dictionary:
	var persona := _dict_or_empty(state.get("persona_snapshot", {}))
	if String(persona.get("memory_id", "")) == memory_id:
		var profile_record := persona.duplicate(true)
		profile_record["memory_type"] = "profile"
		return profile_record
	for item in _array_or_empty(state.get("memory_records", [])):
		if item is Dictionary and String((item as Dictionary).get("memory_id", "")) == memory_id:
			return (item as Dictionary).duplicate(true)
	return {}


func _redacted_record(record: Dictionary, redact_private: bool) -> Dictionary:
	var copy := record.duplicate(true)
	var visibility := String(copy.get("visibility", "self_private"))
	if redact_private and visibility != "public" and visibility != "observer_safe":
		copy["content"] = "[private]"
		copy.erase("structured_payload")
	return copy


func _debug_fields(record: Dictionary) -> Dictionary:
	return {
		"memory_id": String(record.get("memory_id", "")),
		"memory_type": String(record.get("memory_type", "")),
		"embedding_status": String(record.get("embedding_status", "")),
		"importance": float(record.get("importance", 0.0)),
		"confidence": float(record.get("confidence", 0.0)),
		"source": String(record.get("source", "")),
		"created_at": float(record.get("created_at", 0.0)),
		"updated_at": float(record.get("updated_at", 0.0)),
	}


func _reports_from_latest(latest: Dictionary, requested_types: Array, limit: int) -> Array:
	var reports: Array = []
	var capped_limit := maxi(1, limit)
	for item in requested_types:
		var report_type := String(item).strip_edges()
		var payload := _dict_or_empty(latest.get(report_type, {}))
		if payload.is_empty():
			continue
		reports.append({
			"report_type": report_type,
			"payload": payload,
			"created_at": float(payload.get("created_at", 0.0)),
		})
		if reports.size() >= capped_limit:
			break
	return reports


func _remember_context_report(scope_data: Dictionary, report: Dictionary) -> void:
	_last_context_reports_by_scope[_report_scope_key(scope_data)] = report.duplicate(true)


func _remember_maintenance_report(scope_data: Dictionary, report: Dictionary) -> void:
	_last_maintenance_reports_by_scope[_report_scope_key(scope_data)] = report.duplicate(true)


func _context_report_for_scope(scope_data: Dictionary) -> Dictionary:
	return _dict_or_empty(_last_context_reports_by_scope.get(_report_scope_key(scope_data), {}))


func _maintenance_report_for_scope(scope_data: Dictionary) -> Dictionary:
	return _dict_or_empty(_last_maintenance_reports_by_scope.get(_report_scope_key(scope_data), {}))


func _scope_from_last_report_request(request: Dictionary) -> Dictionary:
	var bot_id := String(request.get("bot_id", request.get("id", ""))).strip_edges()
	if bot_id == "":
		return {}
	var profile: Dictionary = _profile_repository.profile_by_key(bot_id)
	if profile.is_empty():
		return {}
	return _memory_scope_for_request(request, String(profile.get("id", "")))


func _report_scope_key(scope_data: Dictionary) -> String:
	return "|".join([
		String(scope_data.get("owner_id", "")),
		String(scope_data.get("game_id", "")),
		String(scope_data.get("map_id", "")),
		String(scope_data.get("room_id", "")),
		String(scope_data.get("namespace", "")),
	])


func _persona_text(value) -> String:
	if value is Dictionary:
		var data: Dictionary = value
		for key in ["content", "persona", "description", "profile"]:
			var text := String(data.get(key, "")).strip_edges()
			if text != "":
				return text
		return ""
	return String(value).strip_edges()


func _ok(data: Dictionary = {}, warnings: Array = []) -> Dictionary:
	return {
		"ok": true,
		"data": data.duplicate(true),
		"warnings": warnings.duplicate(true),
		"error": "",
	}


func _error(code: String, message: String, warnings: Array = []) -> Dictionary:
	return {
		"ok": false,
		"data": {},
		"warnings": warnings.duplicate(true),
		"error": message,
		"code": code,
	}


func _dict_or_empty(value) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}


func _array_or_empty(value) -> Array:
	if value is Array:
		return (value as Array).duplicate(true)
	return []
