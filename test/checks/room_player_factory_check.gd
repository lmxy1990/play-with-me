extends SceneTree

const FactoryScript := preload("res://scripts/player/player_factory.gd")
const BOT_AVATAR := "res://assets/images/werewolf/avatars/robot.png"


func _initialize() -> void:
	var factory = FactoryScript.new()

	var empty: Dictionary = factory.empty_seat(2, 0)
	assert(String(empty.get("name", "")) == "3号位")
	assert(String(empty.get("role", "")) == "待加入")
	assert(String(empty.get("owner", "")) == "")
	assert(factory.visible_role_for_player(empty) == "空位")

	var self_player: Dictionary = factory.self_player("host", "阿景", 0)
	assert(String(self_player.get("id", "")) == "self")
	assert(String(self_player.get("participant_id", "")) == "host")
	assert(String(self_player.get("owner", "")) == "self")
	assert(factory.visible_role_for_player(self_player) == "未知")

	var human: Dictionary = factory.human_player("peer_a", "玩家A", 0)
	human["role"] = "狼人"
	human["role_key"] = "wolf"
	assert(String(human.get("id", "")) == "peer_a")
	assert(String(human.get("owner", "")) == "human")
	assert(factory.visible_role_for_player(human) == "未知")
	human["alive"] = false
	assert(factory.visible_role_for_player(human) == "未知")
	human["role_visible"] = true
	assert(factory.visible_role_for_player(human) == "狼人")

	var bot_a: Dictionary = factory.bot_player(1, "机器人1", "host", 0)
	var bot_b: Dictionary = factory.bot_player(2, "机器人2", "peer_a", 0)
	assert(String(bot_a.get("id", "")) == "player_1")
	assert(not bot_a.has("bot_profile_id"))
	assert(not bot_a.has("model"))
	assert(not bot_a.has("voice"))
	assert(not bot_a.has("memory"))
	assert(String(bot_a.get("role", "")) == "未知")
	assert(String(bot_a.get("role_key", "")) == "")
	assert(String(bot_a.get("avatar", "")) == BOT_AVATAR)
	assert(String(bot_a.get("owner", "")) == "human")
	assert(String(bot_a.get("participant_id", "")) == "")
	assert(String(bot_a.get("controller_participant_id", "")) == "host")
	assert(bool(bot_a.get("ready", false)))
	assert(String(bot_b.get("id", "")) == "player_2")
	assert(String(bot_b.get("role", "")) == "未知")
	assert(String(bot_b.get("role_key", "")) == "")
	assert(String(bot_b.get("avatar", "")) == BOT_AVATAR)
	assert(String(bot_b.get("owner", "")) == "human")
	assert(String(bot_b.get("participant_id", "")) == "")
	assert(String(bot_b.get("controller_participant_id", "")) == "peer_a")
	assert(factory.visible_role_for_player(bot_b) == "未知")
	quit()
