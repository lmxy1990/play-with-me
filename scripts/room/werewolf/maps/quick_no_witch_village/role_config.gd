extends RefCounted


func roles_by_count() -> Dictionary:
	return {
		6: ["wolf", "wolf", "seer", "hunter", "villager", "villager"],
		7: ["wolf", "wolf", "seer", "hunter", "villager", "villager", "villager"],
		8: ["wolf", "wolf", "seer", "hunter", "guard", "villager", "villager", "villager"],
		9: ["wolf", "wolf", "wolf", "seer", "hunter", "guard", "villager", "villager", "villager"],
		10: ["wolf", "wolf", "wolf", "seer", "hunter", "guard", "villager", "villager", "villager", "villager"],
		11: ["wolf", "wolf", "wolf", "seer", "hunter", "guard", "idiot", "villager", "villager", "villager", "villager"],
		12: ["wolf", "wolf", "wolf", "wolf", "seer", "hunter", "guard", "idiot", "villager", "villager", "villager", "villager"],
	}
