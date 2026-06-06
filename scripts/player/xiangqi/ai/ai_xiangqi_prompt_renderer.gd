extends RefCounted


func build_messages(context: Dictionary) -> Array:
	return [
		{"role": "system", "content": system_prompt(context)},
		{"role": "user", "content": user_prompt(context)},
	]


func system_prompt(context: Dictionary = {}) -> String:
	return String(context.get("system_prompt", "")).strip_edges()


func user_prompt(context: Dictionary) -> String:
	return JSON.stringify(to_model_payload(context), "\t")


func to_model_payload(context: Dictionary) -> Dictionary:
	var payload := context.duplicate(true)
	payload.erase("system_prompt")
	return payload
