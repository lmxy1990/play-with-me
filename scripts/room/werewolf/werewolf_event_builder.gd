extends RefCounted
class_name WerewolfEventBuilder


func history_event(speaker: String, text: String) -> Dictionary:
	return {
		"speaker": speaker,
		"text": text,
		"at": Time.get_unix_time_from_system(),
	}
