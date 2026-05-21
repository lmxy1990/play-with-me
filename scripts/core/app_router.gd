extends Control

const PAGE_SCENES := {
	"lobby": "res://scenes/lobby.tscn",
	"table": "res://scenes/werewolf_room.tscn",
	"preferences": "res://scenes/preferences.tscn",
	"model_config": "res://scenes/model_config.tscn",
	"voice_config": "res://scenes/voice_config.tscn",
	"bot_config": "res://scenes/bot_config.tscn",
	"replay": "res://scenes/replay.tscn",
}
const RoomNetworkSessionScript := preload("res://scripts/room/network/room_network_session.gd")
const PreferenceRepositoryScript := preload("res://scripts/core/preferences/preference_repository.gd")

var _current_page: Control
var _current_route := ""
var _state = preload("res://scripts/core/app_state.gd").new()
var _network_session = RoomNetworkSessionScript.new()
var _preferences = PreferenceRepositoryScript.new()


func current_page() -> Control:
	return _current_page


func current_route() -> String:
	return _current_route


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_network_session)
	var preferences_result: Dictionary = _preferences.ensure_preferences()
	if not bool(preferences_result.get("ok", false)):
		push_warning("偏好设置初始化失败：%s" % String(preferences_result.get("error", "")))
	_state.load_or_create()
	navigate("lobby")


func navigate(route: String, payload: Dictionary = {}) -> void:
	var scene_path := String(PAGE_SCENES.get(route, PAGE_SCENES["lobby"]))
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return
	if _current_page != null:
		_current_page.queue_free()
	_current_route = route
	_current_page = packed.instantiate() as Control
	_current_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	if _current_page.has_method("set_preference_repository"):
		_current_page.call("set_preference_repository", _preferences)
	if _current_page.has_method("set_app_state"):
		_current_page.call("set_app_state", _state)
	if _current_page.has_method("set_network_session"):
		_current_page.call("set_network_session", _network_session)
	add_child(_current_page)
	if _current_page.has_signal("navigate_requested"):
		_current_page.navigate_requested.connect(_on_page_navigate_requested)
	if _current_page.has_method("apply_route_payload"):
		_current_page.call("apply_route_payload", payload)


func _on_page_navigate_requested(route: String, payload: Dictionary) -> void:
	if route == _current_route:
		return
	navigate(route, payload)
