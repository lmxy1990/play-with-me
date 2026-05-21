extends "res://scripts/pages/base/page_werewolf_asset_ui_base.gd"

const QrJoinPayloadScript := preload("res://scripts/network/qr_join_payload.gd")
const QrScanJoinUiScript := preload("res://scripts/ui/qr/qr_scan_join_ui.gd")
const AndroidQrScannerScript := preload("res://scripts/android/android_qr_scanner.gd")

var _qr_join_payload = QrJoinPayloadScript.new()
var _scan_join_ui = QrScanJoinUiScript.new()
var _android_qr_scanner = AndroidQrScannerScript.new()
var _scan_join_active := false
var _scan_join_waiting_network := false
var _scan_payload_input: LineEdit
var _scan_status_label: Label


func _disconnect_android_qr_scanner() -> void:
	if _android_qr_scanner == null:
		return
	var scan_succeeded := Callable(self, "_on_android_qr_scan_succeeded")
	var scan_failed := Callable(self, "_on_android_qr_scan_failed")
	var scan_cancelled := Callable(self, "_on_android_qr_scan_cancelled")
	if _android_qr_scanner.scan_succeeded.is_connected(scan_succeeded):
		_android_qr_scanner.scan_succeeded.disconnect(scan_succeeded)
	if _android_qr_scanner.scan_failed.is_connected(scan_failed):
		_android_qr_scanner.scan_failed.disconnect(scan_failed)
	if _android_qr_scanner.scan_cancelled.is_connected(scan_cancelled):
		_android_qr_scanner.scan_cancelled.disconnect(scan_cancelled)


func _ensure_scan_join_ui() -> void:
	if _scan_join_ui == null:
		_scan_join_ui = QrScanJoinUiScript.new()
	_scan_join_ui.setup(self)


func _sync_scan_join_ui_state() -> void:
	_ensure_scan_join_ui()
	_scan_join_active = _scan_join_ui.is_active()
	_scan_join_waiting_network = _scan_join_ui.is_waiting_network()
	_scan_payload_input = _scan_join_ui.payload_input()
	_scan_status_label = _scan_join_ui.status_label()


func _activate_scan_join(payload_input: LineEdit, status_label: Label) -> void:
	_ensure_scan_join_ui()
	_scan_join_ui.activate(payload_input, status_label)
	_sync_scan_join_ui_state()


func _stop_scan_join_waiting() -> void:
	_ensure_scan_join_ui()
	_scan_join_ui.stop_waiting()
	_sync_scan_join_ui_state()


func _setup_android_qr_scanner() -> void:
	if _android_qr_scanner == null:
		_android_qr_scanner = AndroidQrScannerScript.new()
	if not _android_qr_scanner.scan_succeeded.is_connected(_on_android_qr_scan_succeeded):
		_android_qr_scanner.scan_succeeded.connect(_on_android_qr_scan_succeeded)
	if not _android_qr_scanner.scan_failed.is_connected(_on_android_qr_scan_failed):
		_android_qr_scanner.scan_failed.connect(_on_android_qr_scan_failed)
	if not _android_qr_scanner.scan_cancelled.is_connected(_on_android_qr_scan_cancelled):
		_android_qr_scanner.scan_cancelled.connect(_on_android_qr_scan_cancelled)


func _begin_android_qr_scan(payload_input: LineEdit, status_label: Label) -> void:
	_setup_android_qr_scanner()
	_activate_scan_join(payload_input, status_label)
	_scan_debug("begin camera status_label=%s payload_input=%s" % [str(status_label != null), str(payload_input != null)])
	_set_scan_status("正在启动相机扫码", TEAL)
	var result: Dictionary = _android_qr_scanner.start_scan()
	_scan_debug("camera start result ok=%s error=%s" % [str(bool(result.get("ok", false))), String(result.get("error", ""))])
	if not bool(result.get("ok", false)):
		var error := String(result.get("error", "Android 扫码启动失败"))
		if _has_scan_status_label():
			_set_scan_status(error, RED)
		else:
			call("_show_toast", error, RED)
			_clear_scan_overlay_refs()
		return
	if not _scan_join_active:
		return
	if _scan_status_label == status_label and _has_scan_status_label() and _scan_status_label.text == "正在启动相机扫码":
		_set_scan_status("等待扫码结果", TEAL)


func _on_android_qr_scan_succeeded(payload: String) -> void:
	if not _scan_join_active:
		_scan_debug("scan result ignored inactive chars=%d" % payload.strip_edges().length())
		return
	var parsed := _qr_join_payload.parse(payload)
	_scan_debug("scan result chars=%d ok=%s code=%s secure=%s address=%s" % [
		payload.strip_edges().length(),
		str(bool(parsed.get("ok", false))),
		String(parsed.get("code", "")),
		str(bool(parsed.get("secure", false))),
		_scan_payload_address(parsed),
	])
	if not bool(parsed.get("ok", false)):
		_stop_scan_join_waiting()
		var message := "不是有效的房间二维码：%s" % String(parsed.get("error", "格式不匹配"))
		if _has_scan_status_label():
			_set_scan_status(message, RED)
		else:
			call("_show_toast", message, RED)
			_clear_scan_overlay_refs()
		return
	if not _has_scan_status_label():
		_open_scan_join_processing_page()
	_scan_join_ui.set_payload_text(payload)
	_sync_scan_join_ui_state()
	_set_scan_join_waiting("正在加入")
	var accepted := bool(call("_join_room_from_payload", payload, true))
	if not accepted:
		_stop_scan_join_waiting()
		_set_scan_status(String(get("_system_message")), RED)
		_scan_debug("join request rejected before network wait message=%s" % String(get("_system_message")))


func _on_android_qr_scan_failed(error: String) -> void:
	if not _scan_join_active:
		_scan_debug("scan failure ignored inactive error=%s" % error)
		return
	_scan_debug("scan failure error=%s" % error)
	_stop_scan_join_waiting()
	if _has_scan_status_label():
		_set_scan_status(error, RED)
	else:
		call("_show_toast", error, RED)
		_clear_scan_overlay_refs()


func _on_android_qr_scan_cancelled() -> void:
	if not _scan_join_active:
		_scan_debug("scan cancel ignored inactive")
		return
	_scan_debug("scan cancelled")
	_stop_scan_join_waiting()
	if _has_scan_status_label():
		_set_scan_status("已取消扫码", MUTED)
	else:
		call("_show_toast", "已取消扫码", MUTED)
		_clear_scan_overlay_refs()


func _submit_manual_scan_join(payload_input: LineEdit, status_label: Label) -> void:
	_activate_scan_join(payload_input, status_label)
	_set_scan_join_waiting("正在加入")
	var accepted := bool(call("_join_room_from_payload", payload_input.text, true))
	if not accepted:
		_stop_scan_join_waiting()
		_set_scan_status(String(get("_system_message")), RED)


func _open_scan_join(auto_start: bool = false) -> void:
	if auto_start:
		_start_auto_scan_join()
		return
	_ensure_scan_join_ui()
	_scan_join_ui.open_manual_join(
		Callable(self, "_begin_android_qr_scan"),
		Callable(self, "_submit_manual_scan_join"),
		func(): call("_clear_modal")
	)
	_sync_scan_join_ui_state()


func _start_auto_scan_join() -> void:
	call("_clear_modal")
	_begin_android_qr_scan(null, null)


func _open_scan_join_processing_page() -> void:
	_scan_debug("open processing page")
	_ensure_scan_join_ui()
	_scan_join_ui.open_processing_page(
		func(): call("_clear_modal"),
		func():
			call("_clear_modal")
			_begin_android_qr_scan(null, null)
	)
	_sync_scan_join_ui_state()


func _set_scan_status(text: String, color: Color) -> void:
	_ensure_scan_join_ui()
	if not _scan_join_ui.set_status(text, color):
		return
	_scan_debug("status=%s" % text)
	_sync_scan_join_ui_state()


func _has_scan_status_label() -> bool:
	_ensure_scan_join_ui()
	return _scan_join_ui.has_status_label()


func _scan_payload_address(parsed: Dictionary) -> String:
	var address := String(parsed.get("address", "")).strip_edges()
	if address != "":
		return address
	var host := String(parsed.get("host", "")).strip_edges()
	var port := int(parsed.get("port", 0))
	if host != "" and port > 0:
		return "%s:%d" % [host, port]
	return ""


func _scan_debug(message: String) -> void:
	if OS.is_debug_build():
		print("[QrScanJoin][debug] %s" % message)


func _set_scan_join_waiting(text: String) -> void:
	_ensure_scan_join_ui()
	_scan_join_ui.set_waiting(text)
	_scan_debug("status=%s" % text)
	_sync_scan_join_ui_state()


func _tick_scan_join_animation(delta: float) -> void:
	_ensure_scan_join_ui()
	_scan_join_ui.tick(delta)
	_sync_scan_join_ui_state()


func _clear_scan_overlay_refs() -> void:
	if _scan_join_ui != null:
		_scan_join_ui.clear()
	_sync_scan_join_ui_state()
