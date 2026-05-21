extends RefCounted
class_name QrCodeGenerator

const MIN_VERSION := 1
const MAX_VERSION := 26
const ECC_FORMAT_BITS_LOW := 1
const PENALTY_N1 := 3
const PENALTY_N2 := 3
const PENALTY_N3 := 40
const PENALTY_N4 := 10

const ECC_CODEWORDS_PER_BLOCK_LOW := [
	-1,
	7, 10, 15, 20, 26, 18, 20, 24, 30, 18,
	20, 24, 26, 30, 22, 24, 28, 30, 28, 28,
	28, 28, 30, 30, 26, 28,
]

const NUM_ERROR_CORRECTION_BLOCKS_LOW := [
	-1,
	1, 1, 1, 1, 1, 2, 2, 2, 2, 4,
	4, 4, 4, 4, 6, 6, 6, 6, 7, 8,
	8, 9, 9, 10, 12, 12,
]

var _version := 1
var _size := 21
var _modules: Array = []
var _is_function: Array = []


func make_texture(text: String, pixels_per_module: int = 4, border: int = 4, dark: Color = Color(0.04, 0.04, 0.04), light: Color = Color(0.96, 0.95, 0.90)) -> Texture2D:
	var matrix := encode(text)
	if matrix.is_empty():
		return null
	var module_count := matrix.size()
	var scale: int = maxi(1, pixels_per_module)
	var quiet: int = maxi(0, border)
	var image_size := (module_count + quiet * 2) * scale
	var image := Image.create(image_size, image_size, false, Image.FORMAT_RGBA8)
	image.fill(light)
	for y in range(module_count):
		for x in range(module_count):
			if not bool((matrix[y] as Array)[x]):
				continue
			var px := (x + quiet) * scale
			var py := (y + quiet) * scale
			for yy in range(scale):
				for xx in range(scale):
					image.set_pixel(px + xx, py + yy, dark)
	return ImageTexture.create_from_image(image)


func encode(text: String) -> Array:
	var data := text.to_utf8_buffer()
	_version = _choose_version(data.size())
	if _version < 0:
		return []
	_size = _version * 4 + 17
	_init_modules()
	_draw_function_patterns()
	var data_codewords := _make_data_codewords(data, _version)
	var all_codewords := _add_ecc_and_interleave(data_codewords, _version)
	_draw_codewords(all_codewords)
	var best_mask := 0
	var best_penalty := 1 << 30
	var best_modules: Array = []
	for mask in range(8):
		_apply_mask(mask)
		_draw_format_bits(mask)
		var penalty := _get_penalty_score()
		if penalty < best_penalty:
			best_penalty = penalty
			best_mask = mask
			best_modules = _copy_modules(_modules)
		_apply_mask(mask)
	_modules = best_modules
	_draw_format_bits(best_mask)
	return _to_bool_matrix()


func _choose_version(byte_count: int) -> int:
	for version in range(MIN_VERSION, MAX_VERSION + 1):
		var count_bits := 8 if version <= 9 else 16
		var needed_bits := 4 + count_bits + byte_count * 8
		if needed_bits <= _data_codewords(version) * 8:
			return version
	return -1


func _make_data_codewords(data: PackedByteArray, version: int) -> Array:
	var bits: Array = []
	_append_bits(0x4, 4, bits)
	_append_bits(data.size(), 8 if version <= 9 else 16, bits)
	for byte in data:
		_append_bits(int(byte), 8, bits)
	var capacity_bits := _data_codewords(version) * 8
	_append_bits(0, mini(4, capacity_bits - bits.size()), bits)
	while bits.size() % 8 != 0:
		bits.append(0)
	var pad_byte := 0xEC
	while bits.size() < capacity_bits:
		_append_bits(pad_byte, 8, bits)
		pad_byte = 0x11 if pad_byte == 0xEC else 0xEC
	var result: Array = []
	for i in range(0, bits.size(), 8):
		var value := 0
		for j in range(8):
			value = (value << 1) | int(bits[i + j])
		result.append(value)
	return result


func _append_bits(value: int, length: int, bits: Array) -> void:
	for i in range(length - 1, -1, -1):
		bits.append((value >> i) & 1)


func _init_modules() -> void:
	_modules.clear()
	_is_function.clear()
	for _y in range(_size):
		var row: Array = []
		var function_row: Array = []
		for _x in range(_size):
			row.append(0)
			function_row.append(false)
		_modules.append(row)
		_is_function.append(function_row)


func _draw_function_patterns() -> void:
	for i in range(_size):
		_set_function_module(6, i, i % 2 == 0)
		_set_function_module(i, 6, i % 2 == 0)
	_draw_finder_pattern(3, 3)
	_draw_finder_pattern(_size - 4, 3)
	_draw_finder_pattern(3, _size - 4)
	var align := _alignment_pattern_positions()
	for y in align:
		for x in align:
			if not bool((_is_function[y] as Array)[x]):
				_draw_alignment_pattern(x, y)
	_draw_format_bits(0)
	_draw_version_bits()


func _draw_finder_pattern(cx: int, cy: int) -> void:
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var x := cx + dx
			var y := cy + dy
			if x < 0 or y < 0 or x >= _size or y >= _size:
				continue
			var dist := maxi(absi(dx), absi(dy))
			_set_function_module(x, y, dist != 2 and dist != 4)


func _draw_alignment_pattern(cx: int, cy: int) -> void:
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			_set_function_module(cx + dx, cy + dy, maxi(absi(dx), absi(dy)) != 1)


func _alignment_pattern_positions() -> Array:
	if _version == 1:
		return []
	var num_align := int(_version / 7) + 2
	var step := 26 if _version == 32 else int((_version * 4 + num_align * 2 + 1) / (num_align * 2 - 2)) * 2
	var result: Array = []
	for _i in range(num_align):
		result.append(0)
	result[0] = 6
	var pos := _size - 7
	for i in range(num_align - 1, 0, -1):
		result[i] = pos
		pos -= step
	return result


func _draw_format_bits(mask: int) -> void:
	var data := (ECC_FORMAT_BITS_LOW << 3) | mask
	var rem := data
	for _i in range(10):
		rem = (rem << 1) ^ (((rem >> 9) & 1) * 0x537)
	var bits := ((data << 10) | rem) ^ 0x5412
	for i in range(6):
		_set_function_module(8, i, _get_bit(bits, i))
	_set_function_module(8, 7, _get_bit(bits, 6))
	_set_function_module(8, 8, _get_bit(bits, 7))
	_set_function_module(7, 8, _get_bit(bits, 8))
	for i in range(9, 15):
		_set_function_module(14 - i, 8, _get_bit(bits, i))
	for i in range(8):
		_set_function_module(_size - 1 - i, 8, _get_bit(bits, i))
	for i in range(8, 15):
		_set_function_module(8, _size - 15 + i, _get_bit(bits, i))
	_set_function_module(8, _size - 8, true)


func _draw_version_bits() -> void:
	if _version < 7:
		return
	var rem := _version
	for _i in range(12):
		rem = (rem << 1) ^ (((rem >> 11) & 1) * 0x1F25)
	var bits := (_version << 12) | rem
	for i in range(18):
		var bit := _get_bit(bits, i)
		var a := _size - 11 + i % 3
		var b := int(i / 3)
		_set_function_module(a, b, bit)
		_set_function_module(b, a, bit)


func _draw_codewords(data: Array) -> void:
	var bit_index := 0
	var bit_len := data.size() * 8
	var right := _size - 1
	while right >= 1:
		if right == 6:
			right = 5
		for vert in range(_size):
			for j in range(2):
				var x := right - j
				var upward := ((right + 1) & 2) == 0
				var y := _size - 1 - vert if upward else vert
				if bool((_is_function[y] as Array)[x]):
					continue
				var dark := false
				if bit_index < bit_len:
					dark = _get_bit(int(data[int(bit_index / 8)]), 7 - (bit_index & 7))
					bit_index += 1
				(_modules[y] as Array)[x] = 1 if dark else 0
		right -= 2


func _set_function_module(x: int, y: int, dark: bool) -> void:
	(_modules[y] as Array)[x] = 1 if dark else 0
	(_is_function[y] as Array)[x] = true


func _apply_mask(mask: int) -> void:
	for y in range(_size):
		for x in range(_size):
			if bool((_is_function[y] as Array)[x]):
				continue
			if _mask_bit(mask, x, y):
				(_modules[y] as Array)[x] = 1 - int((_modules[y] as Array)[x])


func _mask_bit(mask: int, x: int, y: int) -> bool:
	match mask:
		0:
			return (x + y) % 2 == 0
		1:
			return y % 2 == 0
		2:
			return x % 3 == 0
		3:
			return (x + y) % 3 == 0
		4:
			return (int(y / 2) + int(x / 3)) % 2 == 0
		5:
			return ((x * y) % 2 + (x * y) % 3) == 0
		6:
			return (((x * y) % 2 + (x * y) % 3) % 2) == 0
		_:
			return (((x + y) % 2 + (x * y) % 3) % 2) == 0


func _add_ecc_and_interleave(data: Array, version: int) -> Array:
	var num_blocks := int(NUM_ERROR_CORRECTION_BLOCKS_LOW[version])
	var block_ecc_len := int(ECC_CODEWORDS_PER_BLOCK_LOW[version])
	var raw_codewords := int(_raw_data_modules(version) / 8)
	var num_short_blocks := num_blocks - raw_codewords % num_blocks
	var short_block_len := int(raw_codewords / num_blocks)
	var blocks: Array = []
	var data_index := 0
	var rs_divisor := _reed_solomon_compute_divisor(block_ecc_len)
	for i in range(num_blocks):
		var data_len := short_block_len - block_ecc_len + (0 if i < num_short_blocks else 1)
		var data_block := data.slice(data_index, data_index + data_len)
		data_index += data_len
		var ecc := _reed_solomon_compute_remainder(data_block, rs_divisor)
		if i < num_short_blocks:
			data_block.append(0)
		data_block.append_array(ecc)
		blocks.append(data_block)
	var result: Array = []
	for i in range(short_block_len + 1):
		for j in range(num_blocks):
			if i == short_block_len - block_ecc_len and j < num_short_blocks:
				continue
			if i < (blocks[j] as Array).size():
				result.append((blocks[j] as Array)[i])
	return result


func _reed_solomon_compute_divisor(degree: int) -> Array:
	var result: Array = []
	for _i in range(degree):
		result.append(0)
	result[degree - 1] = 1
	var root := 1
	for _i in range(degree):
		for j in range(degree):
			result[j] = _reed_solomon_multiply(int(result[j]), root)
			if j + 1 < degree:
				result[j] = int(result[j]) ^ int(result[j + 1])
		root = _reed_solomon_multiply(root, 0x02)
	return result


func _reed_solomon_compute_remainder(data: Array, divisor: Array) -> Array:
	var result: Array = []
	for _i in range(divisor.size()):
		result.append(0)
	for byte in data:
		var factor := int(byte) ^ int(result[0])
		result.remove_at(0)
		result.append(0)
		for i in range(divisor.size()):
			result[i] = int(result[i]) ^ _reed_solomon_multiply(int(divisor[i]), factor)
	return result


func _reed_solomon_multiply(x: int, y: int) -> int:
	var z := 0
	for i in range(8):
		if ((y >> i) & 1) != 0:
			z ^= x << i
	for i in range(14, 7, -1):
		if ((z >> i) & 1) != 0:
			z ^= 0x11D << (i - 8)
	return z & 0xFF


func _raw_data_modules(version: int) -> int:
	var result := (16 * version + 128) * version + 64
	if version >= 2:
		var num_align := int(version / 7) + 2
		result -= (25 * num_align - 10) * num_align - 55
		if version >= 7:
			result -= 36
	return result


func _data_codewords(version: int) -> int:
	return int(_raw_data_modules(version) / 8) - int(ECC_CODEWORDS_PER_BLOCK_LOW[version]) * int(NUM_ERROR_CORRECTION_BLOCKS_LOW[version])


func _get_penalty_score() -> int:
	var result := 0
	for y in range(_size):
		var run_color := int((_modules[y] as Array)[0])
		var run_len := 1
		for x in range(1, _size):
			var color := int((_modules[y] as Array)[x])
			if color == run_color:
				run_len += 1
			else:
				if run_len >= 5:
					result += PENALTY_N1 + run_len - 5
				run_color = color
				run_len = 1
		if run_len >= 5:
			result += PENALTY_N1 + run_len - 5
	for x in range(_size):
		var run_color := int((_modules[0] as Array)[x])
		var run_len := 1
		for y in range(1, _size):
			var color := int((_modules[y] as Array)[x])
			if color == run_color:
				run_len += 1
			else:
				if run_len >= 5:
					result += PENALTY_N1 + run_len - 5
				run_color = color
				run_len = 1
		if run_len >= 5:
			result += PENALTY_N1 + run_len - 5
	for y in range(_size - 1):
		for x in range(_size - 1):
			var color := int((_modules[y] as Array)[x])
			if color == int((_modules[y] as Array)[x + 1]) and color == int((_modules[y + 1] as Array)[x]) and color == int((_modules[y + 1] as Array)[x + 1]):
				result += PENALTY_N2
	result += _finder_penalty_rows()
	result += _finder_penalty_columns()
	var dark := 0
	for y in range(_size):
		for x in range(_size):
			dark += int((_modules[y] as Array)[x])
	var total := _size * _size
	var k := int((absi(dark * 20 - total * 10) + total - 1) / total) - 1
	result += k * PENALTY_N4
	return result


func _finder_penalty_rows() -> int:
	var result := 0
	for y in range(_size):
		for x in range(_size - 6):
			if _has_finder_pattern_row(y, x):
				result += PENALTY_N3
	return result


func _finder_penalty_columns() -> int:
	var result := 0
	for x in range(_size):
		for y in range(_size - 6):
			if _has_finder_pattern_column(x, y):
				result += PENALTY_N3
	return result


func _has_finder_pattern_row(y: int, x: int) -> bool:
	var pattern := [1, 0, 1, 1, 1, 0, 1]
	for i in range(7):
		if int((_modules[y] as Array)[x + i]) != int(pattern[i]):
			return false
	var before := x >= 4
	for i in range(1, 5):
		before = before and int((_modules[y] as Array)[x - i]) == 0
	var after := x + 10 < _size
	for i in range(7, 11):
		after = after and int((_modules[y] as Array)[x + i]) == 0
	return before or after


func _has_finder_pattern_column(x: int, y: int) -> bool:
	var pattern := [1, 0, 1, 1, 1, 0, 1]
	for i in range(7):
		if int((_modules[y + i] as Array)[x]) != int(pattern[i]):
			return false
	var before := y >= 4
	for i in range(1, 5):
		before = before and int((_modules[y - i] as Array)[x]) == 0
	var after := y + 10 < _size
	for i in range(7, 11):
		after = after and int((_modules[y + i] as Array)[x]) == 0
	return before or after


func _copy_modules(source: Array) -> Array:
	var result: Array = []
	for row in source:
		result.append((row as Array).duplicate())
	return result


func _to_bool_matrix() -> Array:
	var result: Array = []
	for y in range(_size):
		var row: Array = []
		for x in range(_size):
			row.append(int((_modules[y] as Array)[x]) != 0)
		result.append(row)
	return result


func _get_bit(value: int, index: int) -> bool:
	return ((value >> index) & 1) != 0
