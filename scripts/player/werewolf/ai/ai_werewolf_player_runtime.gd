extends RefCounted

const PromptRendererScript := preload("res://scripts/player/werewolf/ai/ai_werewolf_prompt_renderer.gd")
const OutputParserScript := preload("res://scripts/player/werewolf/ai/ai_werewolf_output_parser.gd")
const ResponseSchemaBuilderScript := preload("res://scripts/player/werewolf/ai/ai_werewolf_response_schema_builder.gd")

var _prompt_renderer = PromptRendererScript.new()
var _output_parser = OutputParserScript.new()
var _response_schema_builder = ResponseSchemaBuilderScript.new()


func build_messages(context: Dictionary) -> Array:
	return _prompt_renderer.build_messages(context)


func system_prompt(context: Dictionary = {}) -> String:
	return _prompt_renderer.system_prompt(context)


func user_prompt(context: Dictionary) -> String:
	return _prompt_renderer.user_prompt(context)


func to_model_payload(context: Dictionary) -> Dictionary:
	return _prompt_renderer.to_model_payload(context)


func target_options_for_context(context: Dictionary) -> Array:
	return _prompt_renderer.target_options_for_context(context)


func response_schema_for_context(context: Dictionary) -> Dictionary:
	var schema_context := context.duplicate(true)
	schema_context["targetOptions"] = _prompt_renderer.target_options_for_context(context)
	return _response_schema_builder.response_schema_for_context(schema_context)


func request_options_for_context(context: Dictionary) -> Dictionary:
	var schema_context := context.duplicate(true)
	schema_context["targetOptions"] = _prompt_renderer.target_options_for_context(context)
	return _response_schema_builder.request_options_for_context(schema_context)


func parse_decision(content: String, context: Dictionary) -> Dictionary:
	var parse_context := context.duplicate(true)
	parse_context["targetOptions"] = _prompt_renderer.target_options_for_context(context)
	return _output_parser.parse_decision(content, parse_context)
