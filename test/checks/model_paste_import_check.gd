extends SceneTree


func _initialize() -> void:
	var state = load("res://scripts/core/app_state.gd").new()
	state.persistence_enabled = false
	state.load_or_create()

	var page := (load("res://scenes/model_config.tscn") as PackedScene).instantiate() as Control
	page.set_app_state(state)
	root.add_child(page)
	await process_frame

	var paste_text := "https://api.example.com/v1/chat/completions\nsk-123456789012345678901234567890\ngpt-4o-mini"
	var paste_result: Dictionary = page._recognize_model_paste(paste_text)
	if not _expect(bool(paste_result.get("ok", false)), "line paste should be recognized"): return
	if not _expect(String(paste_result.get("provider", "")) == "openai_api", "line paste provider should be openai_api"): return
	if not _expect(String(paste_result.get("endpoint", "")) == "https://api.example.com/v1", "line paste endpoint should be normalized"): return
	if not _expect(String(paste_result.get("api_key", "")) == "sk-123456789012345678901234567890", "line paste api key should be recognized"): return
	if not _expect((paste_result.get("models", []) as Array).has("gpt-4o-mini"), "line paste model should be recognized"): return

	var ollama_result: Dictionary = page._recognize_model_paste("http://10.0.0.2:11434\nqwen2.5:7b\nllama3.1")
	if not _expect(bool(ollama_result.get("ok", false)), "ollama paste should be recognized"): return
	if not _expect(String(ollama_result.get("provider", "")) == "ollama", "ollama provider should be inferred"): return
	if not _expect(String(ollama_result.get("endpoint", "")) == "http://10.0.0.2:11434/api", "ollama endpoint should use api path"): return
	if not _expect((ollama_result.get("models", []) as Array).has("qwen2.5:7b"), "qwen model should be recognized"): return
	if not _expect((ollama_result.get("models", []) as Array).has("llama3.1"), "llama model should be recognized"): return

	var json_result: Dictionary = page._recognize_model_paste("{\"base_url\":\"https://openrouter.ai/api/v1\",\"api_key\":\"sk-or-123456789012345678901234567890\",\"model\":\"claude-3-5-sonnet\"}")
	if not _expect(bool(json_result.get("ok", false)), "full json paste should be recognized"): return
	if not _expect(String(json_result.get("provider", "")) == "openai_api", "json endpoint should stay openai_api"): return

	var curl_text := "curl https://api.example.com/v1/chat/completions -H \"Authorization: Bearer sk-test-token\" -d '{\"model\":\"gpt-4o-mini\"}'"
	var curl_result: Dictionary = page._recognize_model_paste(curl_text)
	if not _expect(not bool(curl_result.get("ok", false)), "curl paste should not be recognized"): return
	if not _expect(page._extract_endpoint_from_paste(curl_text) == "", "curl should not extract inline endpoint"): return
	if not _expect(String(curl_result.get("api_key", "")) == "", "curl should not extract inline api key"): return
	if not _expect((curl_result.get("models", []) as Array).is_empty(), "curl should not extract inline model"): return

	var assignment_text := "base_url=https://openrouter.ai/api/v1\napi_key=sk-short\nmodel=claude-3-5-sonnet"
	var assignment_result: Dictionary = page._recognize_model_paste(assignment_text)
	if not _expect(not bool(assignment_result.get("ok", false)), "assignment paste should not be recognized"): return
	if not _expect(page._extract_endpoint_from_paste(assignment_text) == "", "assignment endpoint should not be recognized"): return
	if not _expect(page._extract_api_key_from_paste(assignment_text) == "", "short assignment api key should not be recognized by extractor"): return
	if not _expect(String(assignment_result.get("api_key", "")) == "", "short assignment api key should not be recognized"): return
	if not _expect((assignment_result.get("models", []) as Array).is_empty(), "assignment model should not be recognized"): return

	var long_model_result: Dictionary = page._recognize_model_paste("gpt-12345678901234567890123456")
	if not _expect((long_model_result.get("models", []) as Array).is_empty(), "model id longer than 25 chars should not be recognized"): return

	page._model_batch_editor(paste_result)
	await process_frame
	var checkbox := _find_checkbox(page, "gpt-4o-mini")
	if not _expect(checkbox != null, "batch editor should show pasted model checkbox"): return
	if not _expect(checkbox.button_pressed, "pasted model checkbox should be selected"): return

	page.queue_free()
	await process_frame
	quit()


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false


func _find_checkbox(node: Node, text: String) -> CheckBox:
	if node is CheckBox and String((node as CheckBox).text) == text:
		return node as CheckBox
	for child in node.get_children():
		var found := _find_checkbox(child, text)
		if found != null:
			return found
	return null
