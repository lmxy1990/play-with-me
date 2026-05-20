extends SceneTree


func _initialize() -> void:
	var state = load("res://scripts/core/app_state.gd").new()
	state.persistence_enabled = false
	state.load_or_create()

	var page := (load("res://scenes/model_config.tscn") as PackedScene).instantiate() as Control
	page.set_app_state(state)
	root.add_child(page)
	await process_frame

	var curl_text := "curl https://api.example.com/v1/chat/completions -H \"Authorization: Bearer sk-test-token\" -d '{\"model\":\"gpt-4o-mini\"}'"
	var curl_result: Dictionary = page._recognize_model_paste(curl_text)
	if not _expect(bool(curl_result.get("ok", false)), "curl paste should be recognized"): return
	if not _expect(String(curl_result.get("provider", "")) == "openai_api", "curl provider should be openai_api"): return
	if not _expect(String(curl_result.get("endpoint", "")) == "https://api.example.com/v1", "curl endpoint should be normalized"): return
	if not _expect(String(curl_result.get("api_key", "")) == "sk-test-token", "curl api key should be recognized"): return
	if not _expect((curl_result.get("models", []) as Array).has("gpt-4o-mini"), "curl model should be recognized"): return

	var port_result: Dictionary = page._recognize_model_paste("api端口: 8000\n模型: qwen2.5:7b, deepseek-chat")
	if not _expect(bool(port_result.get("ok", false)), "port paste should be recognized"): return
	if not _expect(String(port_result.get("endpoint", "")) == "http://127.0.0.1:8000/v1", "port endpoint should use localhost v1"): return
	if not _expect((port_result.get("models", []) as Array).has("qwen2.5:7b"), "qwen model should be recognized"): return
	if not _expect((port_result.get("models", []) as Array).has("deepseek-chat"), "deepseek model should be recognized"): return

	var ollama_result: Dictionary = page._recognize_model_paste("OLLAMA_HOST=http://10.0.0.2:11434\nmodels: llama3.1,qwen2.5:7b")
	if not _expect(bool(ollama_result.get("ok", false)), "ollama paste should be recognized"): return
	if not _expect(String(ollama_result.get("provider", "")) == "ollama", "ollama provider should be inferred"): return
	if not _expect(String(ollama_result.get("endpoint", "")) == "http://10.0.0.2:11434/api", "ollama endpoint should use api path"): return

	var openai_compatible_result: Dictionary = page._recognize_model_paste("base_url=https://openrouter.ai/api/v1\napi_key=sk-or-test\nmodel=claude-3-5-sonnet")
	if not _expect(bool(openai_compatible_result.get("ok", false)), "openai-compatible paste should be recognized"): return
	if not _expect(String(openai_compatible_result.get("provider", "")) == "openai_api", "openai-compatible endpoint should stay openai_api"): return

	page._model_batch_editor(curl_result)
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
