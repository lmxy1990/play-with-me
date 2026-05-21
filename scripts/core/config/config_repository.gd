extends RefCounted
class_name ConfigRepository

const ModelAdapterRegistryScript := preload("res://scripts/core/model/model_adapter_registry.gd")
const REASON_ADAPTER_AUTO := "auto"

var _adapter_registry = ModelAdapterRegistryScript.new()


func save_model(configs: Array, index: int, model: String, provider: String, endpoint: String, memory: String, api_key: String = "", context_window_tokens: int = 8192, max_context: int = 262144, max_output: int = 4096, temperature: float = 0.6, reasoning: bool = false, formt_adapter: String = "auto", reason_adapter: String = REASON_ADAPTER_AUTO) -> Array:
	var next := configs.duplicate(true)
	var adapter := _adapter_registry.normalize_formt_adapter(formt_adapter)
	if not _formt_adapter_can_save(adapter):
		push_warning("[ConfigRepository] save_model blocked: invalid formt_adapter=%s model=%s endpoint=%s" % [formt_adapter, model.strip_edges(), endpoint.strip_edges()])
		return next
	var thinking_adapter := _normalize_reason_adapter(reason_adapter)
	if not _reason_adapter_can_save(reasoning, thinking_adapter):
		push_warning("[ConfigRepository] save_model blocked: invalid reason_adapter=%s reasoning=%s model=%s endpoint=%s" % [reason_adapter, reasoning, model.strip_edges(), endpoint.strip_edges()])
		return next
	var model_name := _default_text(model, "未命名模型")
	var item := {
		"id": _existing_model_id(next, index),
		"provider": provider.strip_edges(),
		"model": model_name,
		"endpoint": endpoint.strip_edges(),
		"memory": memory.strip_edges(),
		"api_key": api_key.strip_edges(),
		"context_window_tokens": maxi(1, context_window_tokens),
		"max_context": maxi(1, max_context),
		"max_output": maxi(1, max_output),
		"temperature": clampf(temperature, 0.0, 2.0),
		"reasoning": reasoning,
		"formt_adapter": adapter,
		"reason_adapter": thinking_adapter,
	}
	return _upsert(next, index, item)


func delete_at(configs: Array, index: int) -> Array:
	var next := configs.duplicate(true)
	if index >= 0 and index < next.size():
		next.remove_at(index)
	return next


func _upsert(configs: Array, index: int, item: Dictionary) -> Array:
	if index >= 0 and index < configs.size():
		configs[index] = item
	else:
		configs.append(item)
	return configs


func _existing_id(configs: Array, index: int, prefix: String) -> String:
	if index >= 0 and index < configs.size() and configs[index] is Dictionary:
		var id := String(configs[index].get("id", ""))
		if id != "":
			return id
	return "%s_%d" % [prefix, Time.get_ticks_usec()]


func _existing_model_id(configs: Array, index: int) -> int:
	if index >= 0 and index < configs.size() and configs[index] is Dictionary:
		var id := int(configs[index].get("id", 0))
		if id > 0:
			return id
	var max_id := 0
	for item in configs:
		if item is Dictionary:
			max_id = maxi(max_id, int((item as Dictionary).get("id", 0)))
	return max_id + 1


func _default_text(value: String, default_value: String) -> String:
	var trimmed := value.strip_edges()
	return trimmed if trimmed != "" else default_value


func _formt_adapter_can_save(formt_adapter: String) -> bool:
	return _adapter_registry.formt_adapter_can_save(formt_adapter)


func _normalize_reason_adapter(reason_adapter: String) -> String:
	return _adapter_registry.normalize_reason_adapter(reason_adapter)


func _reason_adapter_can_save(reasoning: bool, reason_adapter: String) -> bool:
	return _adapter_registry.reason_adapter_can_save(reasoning, reason_adapter)
