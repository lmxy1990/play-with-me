extends RefCounted
class_name AvatarCatalog

const AVATARS := [
	{"id": "animal_fox_01", "kind": "animal", "label": "狐狸", "path": "res://assets/images/avatars/animal_fox_01.png"},
	{"id": "animal_cat_01", "kind": "animal", "label": "猫咪", "path": "res://assets/images/avatars/animal_cat_01.png"},
	{"id": "animal_dog_01", "kind": "animal", "label": "小狗", "path": "res://assets/images/avatars/animal_dog_01.png"},
	{"id": "animal_rabbit_01", "kind": "animal", "label": "兔子", "path": "res://assets/images/avatars/animal_rabbit_01.png"},
	{"id": "animal_bear_01", "kind": "animal", "label": "小熊", "path": "res://assets/images/avatars/animal_bear_01.png"},
	{"id": "animal_panda_01", "kind": "animal", "label": "熊猫", "path": "res://assets/images/avatars/animal_panda_01.png"},
	{"id": "animal_deer_01", "kind": "animal", "label": "小鹿", "path": "res://assets/images/avatars/animal_deer_01.png"},
	{"id": "animal_penguin_01", "kind": "animal", "label": "企鹅", "path": "res://assets/images/avatars/animal_penguin_01.png"},
	{"id": "animal_owl_01", "kind": "animal", "label": "猫头鹰", "path": "res://assets/images/avatars/animal_owl_01.png"},
	{"id": "animal_lion_01", "kind": "animal", "label": "狮子", "path": "res://assets/images/avatars/animal_lion_01.png"},
	{"id": "animal_tiger_01", "kind": "animal", "label": "老虎", "path": "res://assets/images/avatars/animal_tiger_01.png"},
	{"id": "animal_koala_01", "kind": "animal", "label": "考拉", "path": "res://assets/images/avatars/animal_koala_01.png"},
	{"id": "person_boy_01", "kind": "person", "label": "男孩 1", "path": "res://assets/images/avatars/person_boy_01.png"},
	{"id": "person_boy_02", "kind": "person", "label": "男孩 2", "path": "res://assets/images/avatars/person_boy_02.png"},
	{"id": "person_boy_03", "kind": "person", "label": "男孩 3", "path": "res://assets/images/avatars/person_boy_03.png"},
	{"id": "person_boy_04", "kind": "person", "label": "男孩 4", "path": "res://assets/images/avatars/person_boy_04.png"},
	{"id": "person_boy_05", "kind": "person", "label": "男孩 5", "path": "res://assets/images/avatars/person_boy_05.png"},
	{"id": "person_boy_06", "kind": "person", "label": "男孩 6", "path": "res://assets/images/avatars/person_boy_06.png"},
	{"id": "person_girl_01", "kind": "person", "label": "女孩 1", "path": "res://assets/images/avatars/person_girl_01.png"},
	{"id": "person_girl_02", "kind": "person", "label": "女孩 2", "path": "res://assets/images/avatars/person_girl_02.png"},
	{"id": "person_girl_03", "kind": "person", "label": "女孩 3", "path": "res://assets/images/avatars/person_girl_03.png"},
	{"id": "person_girl_04", "kind": "person", "label": "女孩 4", "path": "res://assets/images/avatars/person_girl_04.png"},
	{"id": "person_girl_05", "kind": "person", "label": "女孩 5", "path": "res://assets/images/avatars/person_girl_05.png"},
	{"id": "person_girl_06", "kind": "person", "label": "女孩 6", "path": "res://assets/images/avatars/person_girl_06.png"},
]


func list() -> Array:
	return AVATARS.duplicate(true)


func default_avatar_id() -> String:
	return String(AVATARS[0].get("id", ""))


func has_avatar(avatar_id: String) -> bool:
	return not avatar_by_id(avatar_id).is_empty()


func avatar_by_id(avatar_id: String) -> Dictionary:
	var clean := avatar_id.strip_edges()
	for avatar in AVATARS:
		if String(avatar.get("id", "")) == clean:
			return (avatar as Dictionary).duplicate(true)
	return {}
