extends RefCounted

var _patterns: Array = []


func infer(text: String) -> Dictionary:
	var normalized := text.strip_edges()
	if normalized == "":
		return {}
	_ensure_patterns()
	for pattern in _patterns:
		var latest := {}
		for match_result in (pattern as RegEx).search_all(normalized):
			var start := (match_result as RegExMatch).get_start(0)
			if _has_negation_before(normalized, start):
				continue
			var token := (match_result as RegExMatch).get_string(1)
			var seat_number := _parse_seat_number(token)
			if seat_number <= 0:
				continue
			latest = {
				"seat_number": seat_number,
				"phrase": (match_result as RegExMatch).get_string(0),
			}
		if not latest.is_empty():
			return latest
	return {}


func _ensure_patterns() -> void:
	if not _patterns.is_empty():
		return
	for source in [
		"(?:改刀|刀|击杀|杀|处理|带走|噶|砍|干掉|解决|目标|人选|对象|选)\\s*(?:换到|改成|改为|是|为|成|到|一下|先|就)?\\s*([0-9一二三四五六七八九十两]{1,3})\\s*号(?:位)?",
		"([0-9一二三四五六七八九十两]{1,3})\\s*号(?:位)?\\s*(?:可以|能|适合|值得)?\\s*(?:刀|击杀|杀|处理|带走|噶|砍|干掉|解决)",
	]:
		var regex := RegEx.new()
		if regex.compile(source) == OK:
			_patterns.append(regex)


func _has_negation_before(text: String, start: int) -> bool:
	var prefix_start: int = maxi(0, start - 5)
	var prefix := text.substr(prefix_start, start - prefix_start).strip_edges()
	for negation in ["不要", "不能", "先别", "别再", "别刀", "别杀", "不", "别"]:
		if prefix.ends_with(negation):
			return true
	return false


func _parse_seat_number(token: String) -> int:
	var clean := token.strip_edges()
	if clean.is_valid_int():
		return int(clean.to_int())
	var digits := {
		"零": 0,
		"一": 1,
		"二": 2,
		"两": 2,
		"三": 3,
		"四": 4,
		"五": 5,
		"六": 6,
		"七": 7,
		"八": 8,
		"九": 9,
	}
	if digits.has(clean):
		return int(digits[clean])
	if clean == "十":
		return 10
	var ten_index := clean.find("十")
	if ten_index < 0:
		return -1
	var left := clean.substr(0, ten_index)
	var right := clean.substr(ten_index + 1)
	if left != "" and not digits.has(left):
		return -1
	if right != "" and not digits.has(right):
		return -1
	var tens := 1 if left == "" else int(digits[left])
	var ones := 0 if right == "" else int(digits[right])
	return tens * 10 + ones
