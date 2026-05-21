extends RefCounted
class_name BotContextBuilder

const DEFAULT_TOKEN_BUDGET := 4096


func build_memory_context_request(request: Dictionary, bot_profile: Dictionary, scope_data: Dictionary) -> Dictionary:
	var visible_context: Dictionary = _dict_or_empty(request.get("visible_context", {}))
	var validation: Dictionary = validate_visible_context(visible_context, bot_profile)
	if not bool(validation.get("ok", false)):
		return validation
	var memory_request: Dictionary = request.duplicate(true)
	memory_request["bot_id"] = String(bot_profile.get("id", bot_profile.get("bot_id", "")))
	memory_request["scope"] = scope_data.duplicate(true)
	memory_request["task_type"] = String(request.get("task_type", visible_context.get("task_type", "")))
	memory_request["visible_context_facts"] = visible_context_facts(visible_context)
	memory_request["visible_entity_ids"] = visible_entity_ids(visible_context)
	memory_request["query"] = context_query(request, visible_context)
	return _ok({
		"memory_request": memory_request,
		"visible_context": visible_context,
	}, _array_or_empty(validation.get("warnings", [])))


func validate_visible_context(context: Dictionary, bot_profile: Dictionary = {}) -> Dictionary:
	var warnings: Array = []
	var expected_bot_id := String(bot_profile.get("id", bot_profile.get("bot_id", ""))).strip_edges()
	var context_bot_id := String(context.get("bot_id", "")).strip_edges()
	if expected_bot_id != "" and context_bot_id != "" and context_bot_id != expected_bot_id:
		return _error("visible_context_bot_mismatch", "visible_context.bot_id 与当前机器人不一致")
	if not context.has("schema_version"):
		warnings.append("visible_context_missing_schema_version")
	if not context.has("adapter_version"):
		warnings.append("visible_context_missing_adapter_version")
	if context.is_empty():
		warnings.append("empty_visible_context")
	if _array_or_empty(context.get("visible_entities", [])).is_empty():
		warnings.append("empty_visible_entities")
	for key in ["visible_facts", "visible_entities", "public_events", "private_events", "recent_interactions"]:
		for item in _array_or_empty(context.get(key, [])):
			if not (item is Dictionary):
				continue
			var rejection := _visible_item_rejection(item as Dictionary, expected_bot_id, key == "private_events")
			if not rejection.is_empty():
				return _error(String(rejection.get("code", "visible_context_privacy_risk")), String(rejection.get("message", "visible_context 包含不可见或未确认内容")))
	for key in ["current_task", "environment", "constraints"]:
		var block := _dict_or_empty(context.get(key, {}))
		if block.is_empty():
			continue
		var rejection := _visible_item_rejection(block, expected_bot_id, false)
		if not rejection.is_empty():
			return _error(String(rejection.get("code", "visible_context_privacy_risk")), String(rejection.get("message", "visible_context 包含不可见或未确认内容")))
	for item in _array_or_empty(context.get("private_events", [])):
		if not (item is Dictionary):
			continue
		var event: Dictionary = item
		var visible_to := String(event.get("visible_to", event.get("owner_id", ""))).strip_edges()
		if expected_bot_id != "" and visible_to != "" and visible_to != expected_bot_id:
			return _error("private_event_visibility_risk", "private_events 包含不属于当前机器人的私有事件")
	return _ok({}, warnings)


func build_reasoning_context(request: Dictionary, bot_profile: Dictionary, scope_data: Dictionary, visible_context: Dictionary, memory_context: Dictionary, upstream_warnings: Array = []) -> Dictionary:
	var validation: Dictionary = validate_visible_context(visible_context, bot_profile)
	if not bool(validation.get("ok", false)):
		return validation
	var warnings: Array = _array_or_empty(upstream_warnings)
	for warning in _array_or_empty(validation.get("warnings", [])):
		if not warnings.has(warning):
			warnings.append(warning)
	var budget_result: Dictionary = allocate_context_budget({
		"task_type": String(request.get("task_type", visible_context.get("task_type", ""))),
		"max_token_budget": int(request.get("max_token_budget", _dict_or_empty(request.get("memory_options", {})).get("max_token_budget", DEFAULT_TOKEN_BUDGET))),
		"visible_context_size": _estimated_tokens(visible_context),
		"memory_context_size": _estimated_tokens(memory_context),
		"context_options": _dict_or_empty(request.get("context_options", {})),
	})
	var budget_data: Dictionary = _dict_or_empty(budget_result.get("data", {}))
	var token_budget: Dictionary = _dict_or_empty(budget_data.get("token_budget", {}))
	var budget_report: Dictionary = _dict_or_empty(budget_data.get("budget_report", {}))
	var task_type := String(request.get("task_type", visible_context.get("task_type", ""))).strip_edges()
	var reasoning_context := {
		"context_schema_version": int(request.get("context_schema_version", 1)),
		"bot_id": String(bot_profile.get("id", bot_profile.get("bot_id", ""))),
		"scope": scope_data.duplicate(true),
		"task_type": task_type,
		"lifecycle_stage": String(scope_data.get("lifecycle_stage", request.get("lifecycle_stage", ""))),
		"persona": profile_persona_template(bot_profile),
		"business_context": normalize_business_context(visible_context, task_type),
		"memory_context": memory_context.duplicate(true),
		"relationship_context": _array_or_empty(memory_context.get("relationship_context", [])),
		"current_goal": current_goal(memory_context, visible_context),
		"action_constraints": _dict_or_empty(visible_context.get("constraints", request.get("constraints", {}))),
		"output_contract": _dict_or_empty(request.get("output_contract", visible_context.get("output_contract", {}))),
		"token_budget": token_budget,
		"warnings": warnings.duplicate(true),
	}
	return _ok({
		"reasoning_context": reasoning_context,
		"budget_report": budget_report,
	}, warnings)


func normalize_business_context(visible_context: Dictionary, task_type: String = "") -> Dictionary:
	var result: Dictionary = visible_context.duplicate(true)
	if task_type != "" and String(result.get("task_type", "")).strip_edges() == "":
		result["task_type"] = task_type
	if not result.has("visible_entities"):
		result["visible_entities"] = []
	if not result.has("public_events"):
		result["public_events"] = []
	if not result.has("private_events"):
		result["private_events"] = []
	if not result.has("recent_interactions"):
		result["recent_interactions"] = []
	if not result.has("current_task"):
		result["current_task"] = {}
	if not result.has("constraints"):
		result["constraints"] = {}
	return result


func allocate_context_budget(request: Dictionary) -> Dictionary:
	var total := int(request.get("max_token_budget", DEFAULT_TOKEN_BUDGET))
	if total <= 0:
		total = DEFAULT_TOKEN_BUDGET
	var task_type := String(request.get("task_type", "")).strip_edges()
	var ratios: Dictionary = _budget_ratios(task_type)
	var token_budget := {
		"total": total,
		"persona": maxi(64, int(total * float(ratios.get("persona", 0.12)))),
		"business_context": maxi(256, int(total * float(ratios.get("business_context", 0.30)))),
		"memory_context": maxi(256, int(total * float(ratios.get("memory_context", 0.34)))),
		"relationship_context": maxi(128, int(total * float(ratios.get("relationship_context", 0.10)))),
		"output_contract": maxi(128, int(total * float(ratios.get("output_contract", 0.14)))),
	}
	var visible_size := int(request.get("visible_context_size", 0))
	var memory_size := int(request.get("memory_context_size", 0))
	var warnings: Array = []
	if visible_size > int(token_budget.get("business_context", 0)):
		warnings.append("visible_context_over_budget")
	if memory_size > int(token_budget.get("memory_context", 0)):
		warnings.append("memory_context_over_budget")
	return _ok({
		"token_budget": token_budget,
		"budget_report": {
			"task_type": task_type,
			"max_token_budget": total,
			"estimated_visible_context_tokens": visible_size,
			"estimated_memory_context_tokens": memory_size,
			"warnings": warnings,
		},
	}, warnings)


func profile_persona_template(profile: Dictionary) -> Dictionary:
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


func current_goal(memory_context: Dictionary, visible_context: Dictionary) -> String:
	for item in _array_or_empty(memory_context.get("working_memory", [])):
		if item is Dictionary:
			var payload: Dictionary = _dict_or_empty((item as Dictionary).get("structured_payload", {}))
			if String(payload.get("key", "")) == "current_goal":
				return String(payload.get("value", "")).strip_edges()
	var task: Dictionary = _dict_or_empty(visible_context.get("current_task", {}))
	return String(task.get("goal", task.get("instruction", ""))).strip_edges()


func context_query(request: Dictionary, visible_context: Dictionary) -> String:
	var query := String(request.get("query", "")).strip_edges()
	if query != "":
		return query
	var parts: Array = []
	for item in visible_context_facts(visible_context):
		if item is Dictionary:
			var text := String((item as Dictionary).get("text", (item as Dictionary).get("content", ""))).strip_edges()
			if text != "":
				parts.append(text)
	var task: Dictionary = _dict_or_empty(visible_context.get("current_task", {}))
	var instruction := String(task.get("instruction", task.get("goal", ""))).strip_edges()
	if instruction != "":
		parts.append(instruction)
	return "\n".join(parts)


func visible_context_facts(visible_context: Dictionary) -> Array:
	var result: Array = []
	for key in ["visible_facts", "public_events", "private_events", "recent_interactions"]:
		for item in _array_or_empty(visible_context.get(key, [])):
			if item is Dictionary:
				result.append((item as Dictionary).duplicate(true))
			else:
				var text := String(item).strip_edges()
				if text != "":
					result.append({"text": text, "source": key})
	return result


func visible_entity_ids(visible_context: Dictionary) -> Array:
	var result: Array = []
	for item in _array_or_empty(visible_context.get("visible_entities", [])):
		if item is Dictionary:
			var id := String((item as Dictionary).get("id", (item as Dictionary).get("entity_id", ""))).strip_edges()
			if id != "":
				result.append(id)
		else:
			var text := String(item).strip_edges()
			if text != "":
				result.append(text)
	return result


func _budget_ratios(task_type: String) -> Dictionary:
	match task_type:
		"generate_dialogue":
			return {"persona": 0.16, "business_context": 0.28, "memory_context": 0.34, "relationship_context": 0.10, "output_contract": 0.12}
		"choose_action", "choose_target":
			return {"persona": 0.10, "business_context": 0.38, "memory_context": 0.28, "relationship_context": 0.08, "output_contract": 0.16}
		"reflect_session":
			return {"persona": 0.10, "business_context": 0.22, "memory_context": 0.46, "relationship_context": 0.08, "output_contract": 0.14}
		_:
			return {"persona": 0.12, "business_context": 0.30, "memory_context": 0.34, "relationship_context": 0.10, "output_contract": 0.14}


func _estimated_tokens(value) -> int:
	var text := JSON.stringify(value)
	if text == "":
		return 0
	return maxi(1, int(ceil(float(text.length()) / 4.0)))


func _visible_item_rejection(item: Dictionary, expected_bot_id: String, strict_private: bool) -> Dictionary:
	if bool(item.get("hidden", item.get("is_hidden", false))):
		return {"code": "visible_context_privacy_risk", "message": "visible_context 包含隐藏内容"}
	if item.has("visible") and not bool(item.get("visible", true)):
		return {"code": "visible_context_privacy_risk", "message": "visible_context 包含不可见内容"}
	var visibility := String(item.get("visibility", "")).strip_edges().to_lower()
	if visibility in ["hidden", "secret", "not_visible", "raw_private", "unredacted_private"]:
		return {"code": "visible_context_privacy_risk", "message": "visible_context 包含未脱敏私有内容"}
	var status := String(item.get("status", item.get("state", ""))).strip_edges().to_lower()
	if status in ["draft", "model_draft", "unconfirmed", "rejected", "ui_temp", "temporary"]:
		return {"code": "visible_context_unconfirmed_risk", "message": "visible_context 包含未确认或临时内容"}
	if item.has("confirmed") and not bool(item.get("confirmed", true)):
		return {"code": "visible_context_unconfirmed_risk", "message": "visible_context 包含未确认内容"}
	if bool(item.get("rejected", false)) or bool(item.get("model_draft", false)) or bool(item.get("ui_temp", false)):
		return {"code": "visible_context_unconfirmed_risk", "message": "visible_context 包含模型草稿、拒绝输出或 UI 临时输入"}
	if _contains_private_payload_key(item):
		return {"code": "visible_context_privacy_risk", "message": "visible_context 包含未脱敏私有字段"}
	if expected_bot_id != "" and not _item_visible_to_bot(item, expected_bot_id, strict_private):
		return {"code": "visible_context_privacy_risk", "message": "visible_context 包含不属于当前机器人的私有内容"}
	return {}


func _item_visible_to_bot(item: Dictionary, expected_bot_id: String, strict_private: bool) -> bool:
	if item.has("visible_to"):
		return _visibility_target_allows(item.get("visible_to"), expected_bot_id)
	if item.has("viewer_id"):
		return String(item.get("viewer_id", "")).strip_edges() == expected_bot_id
	if item.has("owner_id"):
		var owner_id := String(item.get("owner_id", "")).strip_edges()
		return owner_id == "" or owner_id == expected_bot_id or not strict_private
	return true


func _visibility_target_allows(value, expected_bot_id: String) -> bool:
	if value is Array:
		for item in value:
			var target := String(item).strip_edges()
			if target == expected_bot_id or target == "public" or target == "*":
				return true
		return false
	var target := String(value).strip_edges()
	return target == "" or target == expected_bot_id or target == "public" or target == "*"


func _contains_private_payload_key(value) -> bool:
	if value is Dictionary:
		for key_value in (value as Dictionary).keys():
			var key := String(key_value).strip_edges().to_lower()
			if key in ["hidden_payload", "private_payload", "raw_private_payload", "unredacted_private", "hidden_facts"]:
				return true
			if _contains_private_payload_key((value as Dictionary)[key_value]):
				return true
	elif value is Array:
		for item in value:
			if _contains_private_payload_key(item):
				return true
	return false


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
