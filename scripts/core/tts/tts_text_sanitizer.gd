extends RefCounted
class_name TtsTextSanitizer

const DIGITS := ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]


func sanitize(text: String, speaker_name: String = "") -> String:
	var working := _strip_leading_speaker(text.strip_edges(), speaker_name)
	if working == "":
		return ""
	working = _replace_numbers(working)
	var result := ""
	var has_playable_text := false
	var last_space := false
	for i in range(working.length()):
		var ch := working.substr(i, 1)
		if _is_chinese(ch):
			has_playable_text = true
			result += ch
			last_space = false
			continue
		if _is_ascii_letter(ch):
			has_playable_text = true
			result += ch
			last_space = false
			continue
		if _is_digit(ch):
			has_playable_text = true
			result += DIGITS[int(ch)]
			last_space = false
			continue
		if _is_ascii_word_mark(ch):
			result += ch
			last_space = false
			continue
		var punctuation := _normalized_punctuation(ch)
		if punctuation != "":
			result += punctuation
			last_space = false
			continue
		if ch.strip_edges() == "" and result != "" and not last_space:
			result += " "
			last_space = true
	if not has_playable_text:
		return ""
	return _cleanup(result)


func kokoro_voices() -> Array:
	var result := []
	for i in range(KOKORO_SPEAKERS.size()):
		var name := String(KOKORO_SPEAKERS[i])
		var female := name.length() > 1 and name[1] == "f"
		result.append({
			"id": name,
			"name": "Kokoro %s %s" % ["女声" if female else "男声", name],
			"engine": "local_kokoro",
			"locale": "zh-CN",
			"gender": "女声" if female else "男声",
		})
	return result


func _strip_leading_speaker(text: String, speaker_name: String) -> String:
	var result := text
	var speaker := speaker_name.strip_edges()
	if speaker != "":
		for separator in ["：", ":"]:
			var prefix := "%s%s" % [speaker, separator]
			if result.begins_with(prefix):
				return result.substr(prefix.length()).strip_edges()
	for prefix in ["系统旁白：", "系统旁白:"]:
		if result.begins_with(prefix):
			return result.substr(prefix.length()).strip_edges()
	return result


func _replace_numbers(text: String) -> String:
	var result := ""
	var i := 0
	while i < text.length():
		var ch := text.substr(i, 1)
		if not _is_digit(ch):
			result += ch
			i += 1
			continue
		var start := i
		while i < text.length() and _is_digit(text.substr(i, 1)):
			i += 1
		result += _number_to_chinese(text.substr(start, i - start))
	return result


func _number_to_chinese(value: String) -> String:
	var digits := []
	for i in range(value.length()):
		var ch := value.substr(i, 1)
		if _is_digit(ch):
			digits.append(int(ch))
	if digits.is_empty():
		return ""
	if digits.size() > 2:
		var parts := []
		for digit in digits:
			parts.append(DIGITS[int(digit)])
		return "".join(parts)
	var number := 0
	for digit in digits:
		number = number * 10 + int(digit)
	if number < 10:
		return DIGITS[number]
	if number == 10:
		return "十"
	if number < 20:
		return "十%s" % DIGITS[number % 10]
	var tens := int(number / 10)
	var ones := number % 10
	return "%s十%s" % [DIGITS[tens], "" if ones == 0 else DIGITS[int(ones)]]


func _is_chinese(ch: String) -> bool:
	if ch == "":
		return false
	var code := ch.unicode_at(0)
	return (code >= 0x3400 and code <= 0x4dbf) or (code >= 0x4e00 and code <= 0x9fff) or (code >= 0xf900 and code <= 0xfaff)


func _is_digit(ch: String) -> bool:
	return ch >= "0" and ch <= "9"


func _is_ascii_letter(ch: String) -> bool:
	return (ch >= "A" and ch <= "Z") or (ch >= "a" and ch <= "z")


func _is_ascii_word_mark(ch: String) -> bool:
	return ["'", "-", "_", "/", "+", "#", "&"].has(ch)


func _normalized_punctuation(ch: String) -> String:
	match ch:
		",", "，":
			return "，"
		".", "。":
			return "。"
		"!", "！":
			return "！"
		"?", "？":
			return "？"
		":", "：":
			return "："
		";", "；":
			return "；"
		"、":
			return "、"
		"(", "（":
			return "（"
		")", "）":
			return "）"
		"[", "【":
			return "【"
		"]", "】":
			return "】"
		_:
			return ""


func _cleanup(text: String) -> String:
	var result := text.strip_edges()
	while result.contains("  "):
		result = result.replace("  ", " ")
	for punctuation in ["，", "。", "！", "？", "：", "；", "、", "）", "】"]:
		result = result.replace(" " + punctuation, punctuation)
	for punctuation in ["（", "【"]:
		result = result.replace(punctuation + " ", punctuation)
	while result.length() > 0 and ["，", "。", "！", "？", "：", "；", "、", " "].has(result.substr(0, 1)):
		result = result.substr(1)
	while result.length() > 0 and ["，", "、", "：", "；", " "].has(result.substr(result.length() - 1, 1)):
		result = result.substr(0, result.length() - 1)
	return result.strip_edges()


const KOKORO_SPEAKERS := [
	"zf_001", "zf_002", "zf_003", "zf_004", "zf_005", "zf_006", "zf_007", "zf_008", "zf_017", "zf_018",
	"zf_019", "zf_021", "zf_022", "zf_023", "zf_024", "zf_026", "zf_027", "zf_028", "zf_032", "zf_036",
	"zf_038", "zf_039", "zf_040", "zf_042", "zf_043", "zf_044", "zf_046", "zf_047", "zf_048", "zf_049",
	"zf_051", "zf_059", "zf_060", "zf_067", "zf_070", "zf_071", "zf_072", "zf_073", "zf_074", "zf_075",
	"zf_076", "zf_077", "zf_078", "zf_079", "zf_083", "zf_084", "zf_085", "zf_086", "zf_087", "zf_088",
	"zf_090", "zf_092", "zf_093", "zf_094", "zf_099", "zm_009", "zm_010",
	"zm_011", "zm_012", "zm_013", "zm_014", "zm_015", "zm_016", "zm_020", "zm_025", "zm_029", "zm_030",
	"zm_031", "zm_033", "zm_034", "zm_035", "zm_037", "zm_041", "zm_045", "zm_050", "zm_052", "zm_053",
	"zm_054", "zm_055", "zm_056", "zm_057", "zm_058", "zm_061", "zm_062", "zm_063", "zm_064", "zm_065",
	"zm_066", "zm_068", "zm_069", "zm_080", "zm_081", "zm_082", "zm_089", "zm_091", "zm_095", "zm_096",
	"zm_097", "zm_098", "zm_100",
]
