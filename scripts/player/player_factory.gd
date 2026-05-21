extends RefCounted

const WerewolfHumanPlayerFactoryScript := preload("res://scripts/player/werewolf/human/werewolf_human_player_factory.gd")
const WerewolfAiPlayerFactoryScript := preload("res://scripts/player/werewolf/ai/werewolf_ai_player_factory.gd")

var _werewolf_human_factory = WerewolfHumanPlayerFactoryScript.new()
var _werewolf_ai_factory = WerewolfAiPlayerFactoryScript.new()


func self_player(participant_id: String, display_name: String, idle_motion: int = 0) -> Dictionary:
	return _werewolf_human_factory.self_player(participant_id, display_name, idle_motion)


func human_player(participant_id: String, display_name: String, idle_motion: int = 0) -> Dictionary:
	return _werewolf_human_factory.human_player(participant_id, display_name, idle_motion)


func bot_player(bot_serial: int, bot_name: String, controller_participant_id: String, idle_motion: int = 0) -> Dictionary:
	return _werewolf_ai_factory.bot_player(bot_serial, bot_name, controller_participant_id, idle_motion)


func empty_seat(index: int, idle_motion: int = 0) -> Dictionary:
	return _werewolf_human_factory.empty_seat(index, idle_motion)


func visible_role_for_player(player: Dictionary) -> String:
	return _werewolf_human_factory.visible_role_for_player(player)

