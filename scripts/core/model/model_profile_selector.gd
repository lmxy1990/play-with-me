extends RefCounted


func profile_for_player(player: Dictionary, model_configs: Array) -> Dictionary:
	var model_name := String(player.get("model", "")).strip_edges()
	return profile_for_model_name(model_name, model_configs)


func profile_for_model_name(model_name: String, model_configs: Array) -> Dictionary:
	var clean_name := model_name.strip_edges()
	if clean_name == "":
		return {}
	for item in model_configs:
		if item is Dictionary and String((item as Dictionary).get("model", (item as Dictionary).get("name", ""))).strip_edges() == clean_name:
			var named_profile: Dictionary = usable_profile(item as Dictionary)
			if not named_profile.is_empty():
				return named_profile
	return {}


func usable_profile(profile: Dictionary) -> Dictionary:
	var model := String(profile.get("model", "")).strip_edges()
	if model == "":
		model = String(profile.get("name", "")).strip_edges()
	var endpoint := String(profile.get("endpoint", "")).strip_edges()
	if model == "" or endpoint == "":
		return {}
	var normalized := profile.duplicate(true)
	normalized["model"] = model
	normalized["max_context"] = max_context(normalized, 262144)
	normalized["max_output"] = max_output(normalized, 4096)
	var context_default := maxi(1, roundi(float(int(normalized["max_context"])) * 0.7))
	normalized["context_window_tokens"] = maxi(1, int(normalized.get("context_window_tokens", context_default)))
	normalized.erase("max_token")
	normalized.erase("max_output_tokens")
	normalized.erase("name")
	normalized["temperature"] = clampf(float(normalized.get("temperature", 0.6)), 0.0, 2.0)
	normalized["reasoning"] = bool(normalized.get("reasoning", false))
	normalized["formt_adapter"] = String(normalized.get("formt_adapter", "auto")).strip_edges().to_lower()
	normalized["reason_adapter"] = String(normalized.get("reason_adapter", "auto")).strip_edges().to_lower()
	return normalized


func temperature(profile: Dictionary, default_value: float) -> float:
	if profile.has("temperature"):
		return clampf(float(profile.get("temperature", default_value)), 0.0, 2.0)
	return default_value


func max_token(profile: Dictionary, default_value: int) -> int:
	return max_output(profile, default_value)


func max_context(profile: Dictionary, default_value: int) -> int:
	if profile.has("max_context"):
		return maxi(1, int(profile.get("max_context", default_value)))
	if profile.has("max_token"):
		return maxi(1, int(profile.get("max_token", default_value)))
	return default_value


func max_output(profile: Dictionary, default_value: int) -> int:
	if profile.has("max_output"):
		return maxi(1, int(profile.get("max_output", default_value)))
	return maxi(1, default_value)


func context_window_tokens(profile: Dictionary, default_value: int = 8192) -> int:
	if profile.has("context_window_tokens"):
		return maxi(1, int(profile.get("context_window_tokens", default_value)))
	return maxi(1, default_value)
