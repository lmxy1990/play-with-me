extends RefCounted
class_name ModelAdapterRegistry

const TRANSPORT_MODE_SYNC := "sync"
const TRANSPORT_MODE_STREAM := "stream"
const OUTPUT_TYPE_TEXT := "text"
const OUTPUT_TYPE_JSON := "json"
const REASONING_MODE_OFF := "off"
const REASONING_MODE_ON := "on"

const FORMT_ADAPTER_AUTO := "auto"
const FORMT_ADAPTER_NONE := "none"
const FORMT_ADAPTER_OPENAI_JSON_SCHEMA := "openai_json_schema"
const FORMT_ADAPTER_OPENAI_JSON_OBJECT := "openai_json_object"
const FORMT_ADAPTER_OPENAI_TOOL_FORCED := "openai_tool_forced"
const FORMT_ADAPTER_OPENAI_TOOL_OPTIONAL := "openai_tool_optional"
const FORMT_ADAPTER_OPENAI_MIMO_TOOL := "openai_mimo_tool"
const FORMT_ADAPTER_GEMINI_JSON_SCHEMA := "gemini_json_schema"
const FORMT_ADAPTER_ANTHROPIC_TOOL := "anthropic_tool"
const FORMT_ADAPTER_OLLAMA_FORMAT_SCHEMA := "ollama_format_schema"

const REASON_ADAPTER_AUTO := "auto"
const REASON_ADAPTER_NATIVE := "native"
const REASON_ADAPTER_OPENAI_REASONING_EFFORT := "openai_reasoning_effort"
const REASON_ADAPTER_DEEPSEEK_THINKING := "deepseek_thinking"
const REASON_ADAPTER_GLM_THINKING := "glm_thinking"
const REASON_ADAPTER_ARK_THINKING := "ark_thinking"
const REASON_ADAPTER_MINIMAX_REASONING_SPLIT := "minimax_reasoning_split"
const REASON_ADAPTER_MIMO_CHAT_TEMPLATE := "mimo_chat_template"
const REASON_ADAPTER_KIMI_THINKING_CONTROL := "kimi_thinking_control"

const SAVABLE_FORMT_ADAPTERS := [
	FORMT_ADAPTER_OPENAI_JSON_SCHEMA,
	FORMT_ADAPTER_OPENAI_JSON_OBJECT,
	FORMT_ADAPTER_OPENAI_TOOL_FORCED,
	FORMT_ADAPTER_OPENAI_TOOL_OPTIONAL,
	FORMT_ADAPTER_OPENAI_MIMO_TOOL,
	FORMT_ADAPTER_GEMINI_JSON_SCHEMA,
	FORMT_ADAPTER_ANTHROPIC_TOOL,
	FORMT_ADAPTER_OLLAMA_FORMAT_SCHEMA,
]

const SAVABLE_REASON_ADAPTERS := [
	REASON_ADAPTER_NATIVE,
	REASON_ADAPTER_OPENAI_REASONING_EFFORT,
	REASON_ADAPTER_DEEPSEEK_THINKING,
	REASON_ADAPTER_GLM_THINKING,
	REASON_ADAPTER_ARK_THINKING,
	REASON_ADAPTER_MINIMAX_REASONING_SPLIT,
	REASON_ADAPTER_MIMO_CHAT_TEMPLATE,
	REASON_ADAPTER_KIMI_THINKING_CONTROL,
]


func normalize_provider(provider: String) -> String:
	var lower := provider.strip_edges().to_lower()
	if lower.contains("ollama"):
		return "ollama"
	if lower.contains("anthropic") or lower.contains("claude"):
		return "anthropic"
	if lower.contains("gemini") or lower.contains("google"):
		return "gemini"
	return "openai"


func model_provider_id(provider: String) -> String:
	var lower := provider.strip_edges().to_lower()
	if lower == "openai_api" or lower == "openai" or lower.contains("openai"):
		return "openai_api"
	if lower.contains("anthropic") or lower.contains("claude"):
		return "anthropic"
	if lower.contains("gemini") or lower.contains("google"):
		return "gemini"
	if lower.contains("ollama"):
		return "ollama"
	return "openai_api"


func normalize_output_adapter(value: String) -> String:
	var adapter := value.strip_edges().to_lower()
	match adapter:
		FORMT_ADAPTER_NONE:
			return FORMT_ADAPTER_NONE
		FORMT_ADAPTER_OPENAI_JSON_SCHEMA:
			return FORMT_ADAPTER_OPENAI_JSON_SCHEMA
		FORMT_ADAPTER_OPENAI_JSON_OBJECT:
			return FORMT_ADAPTER_OPENAI_JSON_OBJECT
		FORMT_ADAPTER_OPENAI_TOOL_FORCED:
			return FORMT_ADAPTER_OPENAI_TOOL_FORCED
		FORMT_ADAPTER_OPENAI_TOOL_OPTIONAL:
			return FORMT_ADAPTER_OPENAI_TOOL_OPTIONAL
		FORMT_ADAPTER_OPENAI_MIMO_TOOL:
			return FORMT_ADAPTER_OPENAI_MIMO_TOOL
		FORMT_ADAPTER_GEMINI_JSON_SCHEMA:
			return FORMT_ADAPTER_GEMINI_JSON_SCHEMA
		FORMT_ADAPTER_ANTHROPIC_TOOL:
			return FORMT_ADAPTER_ANTHROPIC_TOOL
		FORMT_ADAPTER_OLLAMA_FORMAT_SCHEMA:
			return FORMT_ADAPTER_OLLAMA_FORMAT_SCHEMA
		_:
			return FORMT_ADAPTER_AUTO


func normalize_formt_adapter(value: String) -> String:
	return normalize_output_adapter(value)


func normalize_reason_adapter(value: String) -> String:
	var adapter := value.strip_edges().to_lower()
	match adapter:
		REASON_ADAPTER_NATIVE:
			return REASON_ADAPTER_NATIVE
		REASON_ADAPTER_OPENAI_REASONING_EFFORT:
			return REASON_ADAPTER_OPENAI_REASONING_EFFORT
		REASON_ADAPTER_DEEPSEEK_THINKING:
			return REASON_ADAPTER_DEEPSEEK_THINKING
		REASON_ADAPTER_GLM_THINKING:
			return REASON_ADAPTER_GLM_THINKING
		REASON_ADAPTER_ARK_THINKING:
			return REASON_ADAPTER_ARK_THINKING
		REASON_ADAPTER_MINIMAX_REASONING_SPLIT:
			return REASON_ADAPTER_MINIMAX_REASONING_SPLIT
		REASON_ADAPTER_MIMO_CHAT_TEMPLATE:
			return REASON_ADAPTER_MIMO_CHAT_TEMPLATE
		REASON_ADAPTER_KIMI_THINKING_CONTROL:
			return REASON_ADAPTER_KIMI_THINKING_CONTROL
		_:
			return REASON_ADAPTER_AUTO


func formt_adapter_can_save(formt_adapter: String) -> bool:
	return SAVABLE_FORMT_ADAPTERS.has(normalize_formt_adapter(formt_adapter))


func reason_adapter_can_save(reasoning: bool, reason_adapter: String) -> bool:
	var adapter := normalize_reason_adapter(reason_adapter)
	if adapter == REASON_ADAPTER_AUTO:
		return false
	if reasoning:
		return adapter != REASON_ADAPTER_NATIVE and SAVABLE_REASON_ADAPTERS.has(adapter)
	return SAVABLE_REASON_ADAPTERS.has(adapter)


func formt_adapter_label(formt_adapter: String) -> String:
	match normalize_formt_adapter(formt_adapter):
		FORMT_ADAPTER_OPENAI_JSON_SCHEMA:
			return "json_schema"
		FORMT_ADAPTER_OPENAI_JSON_OBJECT:
			return "json_object"
		FORMT_ADAPTER_OPENAI_TOOL_FORCED:
			return "tool"
		FORMT_ADAPTER_OPENAI_TOOL_OPTIONAL:
			return "tool_v2"
		FORMT_ADAPTER_OPENAI_MIMO_TOOL:
			return "mimo_tool"
		FORMT_ADAPTER_GEMINI_JSON_SCHEMA:
			return "gemini_schema"
		FORMT_ADAPTER_ANTHROPIC_TOOL:
			return "claude_tool"
		FORMT_ADAPTER_OLLAMA_FORMAT_SCHEMA:
			return "ollama_schema"
		FORMT_ADAPTER_NONE:
			return "无"
		_:
			return "自动"


func reason_adapter_native_label(provider: String) -> String:
	match model_provider_id(provider):
		"anthropic":
			return "anthropic"
		"gemini":
			return "gemini"
		"ollama":
			return "ollama"
		_:
			return "openai"


func reason_adapter_label(reason_adapter: String, provider: String = "") -> String:
	match normalize_reason_adapter(reason_adapter):
		REASON_ADAPTER_OPENAI_REASONING_EFFORT:
			return "reasoning_effort"
		REASON_ADAPTER_DEEPSEEK_THINKING:
			return "deepseek_thinking"
		REASON_ADAPTER_GLM_THINKING:
			return "glm_thinking"
		REASON_ADAPTER_ARK_THINKING:
			return "ark_thinking"
		REASON_ADAPTER_MINIMAX_REASONING_SPLIT:
			return "minimax_split"
		REASON_ADAPTER_MIMO_CHAT_TEMPLATE:
			return "mimo_chat_template"
		REASON_ADAPTER_KIMI_THINKING_CONTROL:
			return "kimi_thinking_control"
		REASON_ADAPTER_NATIVE:
			return reason_adapter_native_label(provider)
		_:
			return "自动"


func formt_adapter_test_candidates(provider: String, model: String, selected_adapter: String = FORMT_ADAPTER_AUTO) -> Array:
	var adapter := normalize_formt_adapter(selected_adapter)
	var provider_candidates := provider_formt_adapter_candidates(provider, model)
	if formt_adapter_can_save(adapter):
		return [adapter] if provider_candidates.has(adapter) else []
	return provider_candidates


func provider_formt_adapter_candidates(provider: String, model: String = "") -> Array:
	var provider_id := model_provider_id(provider)
	if provider_id == "gemini":
		return [FORMT_ADAPTER_GEMINI_JSON_SCHEMA]
	if provider_id == "anthropic":
		return [FORMT_ADAPTER_ANTHROPIC_TOOL]
	if provider_id == "ollama":
		return [FORMT_ADAPTER_OLLAMA_FORMAT_SCHEMA]
	if is_glm_model_name(model):
		return [
			FORMT_ADAPTER_OPENAI_JSON_SCHEMA,
			FORMT_ADAPTER_OPENAI_TOOL_FORCED,
			FORMT_ADAPTER_OPENAI_TOOL_OPTIONAL,
			FORMT_ADAPTER_OPENAI_MIMO_TOOL,
			FORMT_ADAPTER_OPENAI_JSON_OBJECT,
		]
	return [
		FORMT_ADAPTER_OPENAI_JSON_SCHEMA,
		FORMT_ADAPTER_OPENAI_JSON_OBJECT,
		FORMT_ADAPTER_OPENAI_TOOL_FORCED,
		FORMT_ADAPTER_OPENAI_TOOL_OPTIONAL,
		FORMT_ADAPTER_OPENAI_MIMO_TOOL,
	]


func reason_adapter_detected_for_model(provider: String, model: String, formt_adapter: String = FORMT_ADAPTER_AUTO) -> String:
	var candidates := provider_reason_adapter_candidates(provider, model)
	var lower_model := model.strip_edges().to_lower()
	if lower_model.contains("mimo") or normalize_formt_adapter(formt_adapter) == FORMT_ADAPTER_OPENAI_MIMO_TOOL:
		return REASON_ADAPTER_MIMO_CHAT_TEMPLATE if candidates.has(REASON_ADAPTER_MIMO_CHAT_TEMPLATE) else REASON_ADAPTER_AUTO
	if lower_model.contains("minimax"):
		return REASON_ADAPTER_MINIMAX_REASONING_SPLIT if candidates.has(REASON_ADAPTER_MINIMAX_REASONING_SPLIT) else REASON_ADAPTER_AUTO
	if lower_model.contains("glm"):
		return REASON_ADAPTER_GLM_THINKING if candidates.has(REASON_ADAPTER_GLM_THINKING) else REASON_ADAPTER_AUTO
	if lower_model.contains("deepseek"):
		return REASON_ADAPTER_DEEPSEEK_THINKING if candidates.has(REASON_ADAPTER_DEEPSEEK_THINKING) else REASON_ADAPTER_AUTO
	if lower_model.contains("doubao"):
		return REASON_ADAPTER_ARK_THINKING if candidates.has(REASON_ADAPTER_ARK_THINKING) else REASON_ADAPTER_AUTO
	if lower_model.contains("kimi") or lower_model.contains("moonshot"):
		return REASON_ADAPTER_KIMI_THINKING_CONTROL if candidates.has(REASON_ADAPTER_KIMI_THINKING_CONTROL) else REASON_ADAPTER_AUTO
	if candidates.has(REASON_ADAPTER_OPENAI_REASONING_EFFORT):
		return REASON_ADAPTER_OPENAI_REASONING_EFFORT
	return REASON_ADAPTER_AUTO


func reason_adapter_test_candidates(provider: String, model: String, reasoning: bool, formt_adapter: String = FORMT_ADAPTER_AUTO, selected_adapter: String = REASON_ADAPTER_AUTO) -> Array:
	var adapter := normalize_reason_adapter(selected_adapter)
	var provider_candidates := provider_reason_adapter_candidates(provider, model)
	var auto_candidates := auto_reason_adapter_candidates(provider_candidates, model)
	if reason_adapter_can_save(reasoning, adapter):
		return [adapter] if provider_candidates.has(adapter) else []
	if not reasoning:
		var disabled_candidates := []
		if auto_candidates.has(REASON_ADAPTER_NATIVE):
			disabled_candidates.append(REASON_ADAPTER_NATIVE)
		for candidate in auto_candidates:
			if candidate == REASON_ADAPTER_NATIVE:
				continue
			if not disabled_candidates.has(candidate):
				disabled_candidates.append(candidate)
		return disabled_candidates
	var detected := reason_adapter_detected_for_model(provider, model, formt_adapter)
	var result := []
	if reason_adapter_can_save(reasoning, detected) and auto_candidates.has(detected):
		result.append(detected)
	for candidate in auto_candidates:
		if not result.has(candidate):
			result.append(candidate)
	return result


func auto_reason_adapter_candidates(provider_candidates: Array, model: String) -> Array:
	var lower_model := model.strip_edges().to_lower()
	var result := []
	for item in provider_candidates:
		var candidate := normalize_reason_adapter(String(item))
		if candidate == REASON_ADAPTER_GLM_THINKING and not lower_model.contains("glm"):
			continue
		if candidate != REASON_ADAPTER_AUTO and not result.has(candidate):
			result.append(candidate)
	return result


func provider_reason_adapter_candidates(provider: String, model: String = "") -> Array:
	var provider_id := model_provider_id(provider)
	if provider_id != "openai_api":
		return [REASON_ADAPTER_NATIVE]
	var base_candidates := [
		REASON_ADAPTER_DEEPSEEK_THINKING,
		REASON_ADAPTER_GLM_THINKING,
		REASON_ADAPTER_ARK_THINKING,
		REASON_ADAPTER_MINIMAX_REASONING_SPLIT,
		REASON_ADAPTER_OPENAI_REASONING_EFFORT,
		REASON_ADAPTER_MIMO_CHAT_TEMPLATE,
		REASON_ADAPTER_KIMI_THINKING_CONTROL,
		REASON_ADAPTER_NATIVE,
	]
	var lower_model := model.strip_edges().to_lower()
	var preferred := ""
	if lower_model.contains("mimo"):
		preferred = REASON_ADAPTER_MIMO_CHAT_TEMPLATE
	elif lower_model.contains("minimax"):
		preferred = REASON_ADAPTER_MINIMAX_REASONING_SPLIT
	elif lower_model.contains("glm"):
		preferred = REASON_ADAPTER_GLM_THINKING
	elif lower_model.contains("deepseek"):
		preferred = REASON_ADAPTER_DEEPSEEK_THINKING
	elif lower_model.contains("doubao"):
		preferred = REASON_ADAPTER_ARK_THINKING
	elif lower_model.contains("kimi") or lower_model.contains("moonshot"):
		preferred = REASON_ADAPTER_KIMI_THINKING_CONTROL
	if preferred == "" or not base_candidates.has(preferred):
		return base_candidates
	var ordered := [preferred]
	for candidate in base_candidates:
		if candidate != preferred:
			ordered.append(candidate)
	return ordered


func default_openai_formt_adapter(model: String) -> String:
	if is_xiaomi_mimo_model_name(model):
		return FORMT_ADAPTER_OPENAI_MIMO_TOOL
	if is_minimax_model_name(model):
		return FORMT_ADAPTER_OPENAI_TOOL_OPTIONAL
	if is_glm_model_name(model):
		return FORMT_ADAPTER_OPENAI_TOOL_FORCED
	if is_deepseek_model_name(model) or is_kimi_model_name(model):
		return FORMT_ADAPTER_OPENAI_JSON_OBJECT
	return FORMT_ADAPTER_OPENAI_JSON_SCHEMA


func is_xiaomi_mimo_model_name(model_name: String) -> bool:
	return model_family_matches(model_name, "mimo")


func is_deepseek_model_name(model_name: String) -> bool:
	return model_family_matches(model_name, "deepseek")


func is_doubao_model_name(model_name: String) -> bool:
	return model_family_matches(model_name, "doubao")


func is_glm_model_name(model_name: String) -> bool:
	return model_family_matches(model_name, "glm")


func is_minimax_model_name(model_name: String) -> bool:
	return model_family_matches(model_name, "minimax")


func is_kimi_model_name(model_name: String) -> bool:
	return model_family_matches(model_name, "kimi") or model_family_matches(model_name, "moonshot")


func model_family_matches(model_name: String, family: String) -> bool:
	var model := model_name.strip_edges().to_lower()
	var target := family.strip_edges().to_lower()
	if model == "" or target == "":
		return false
	return model.contains(target)
