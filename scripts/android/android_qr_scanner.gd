extends RefCounted
class_name AndroidQrScanner

signal scan_succeeded(payload: String)
signal scan_failed(error: String)
signal scan_cancelled()

const DEFAULT_SINGLETON := "PlayWithMeAndroid"
const START_METHODS := ["start_qr_scan", "scan_join_qr", "startScan", "scanQr"]

var singleton_name := DEFAULT_SINGLETON
var _bound_plugin = null
var _scan_request_id := 0


func is_available() -> bool:
	var plugin = _plugin()
	return plugin != null and _scan_method(plugin) != ""


func start_scan() -> Dictionary:
	_scan_request_id += 1
	var plugin = _plugin()
	if plugin == null:
		_scanner_debug("start id=%d failed plugin=missing singleton=%s" % [_scan_request_id, singleton_name])
		return _error("Android 扫码插件未接入：缺少 singleton %s" % singleton_name)
	var method := _scan_method(plugin)
	if method == "":
		_scanner_debug("start id=%d failed method=missing" % _scan_request_id)
		return _error("Android 扫码插件缺少 start_qr_scan 方法")
	_bind_plugin_signals(plugin)
	_scanner_debug("start id=%d method=%s plugin=%s" % [_scan_request_id, method, singleton_name])
	var result = plugin.call(method)
	_scanner_debug("start id=%d returned type=%s" % [_scan_request_id, type_string(typeof(result))])
	if result is bool and not bool(result):
		return _error("Android 扫码插件启动失败")
	if result is String and String(result).strip_edges() != "":
		submit_scan_result(String(result))
	elif result is Dictionary:
		var data: Dictionary = result
		if bool(data.get("ok", true)) and String(data.get("payload", "")).strip_edges() != "":
			submit_scan_result(String(data.get("payload", "")))
		elif not bool(data.get("ok", true)):
			return _error(String(data.get("error", "Android 扫码插件启动失败")))
	return {"ok": true}


func submit_scan_result(payload: String) -> void:
	var value := payload.strip_edges()
	if value == "":
		_scanner_debug("result id=%d empty" % _scan_request_id)
		scan_failed.emit("扫码结果为空")
		return
	_scanner_debug("result id=%d chars=%d" % [_scan_request_id, value.length()])
	scan_succeeded.emit(value)


func submit_scan_error(error: String) -> void:
	var message := error.strip_edges()
	_scanner_debug("failed id=%d error=%s" % [_scan_request_id, "扫码失败" if message == "" else message])
	scan_failed.emit("扫码失败" if message == "" else message)


func submit_scan_cancelled() -> void:
	_scanner_debug("cancelled id=%d" % _scan_request_id)
	scan_cancelled.emit()


func _plugin():
	if Engine.has_singleton(singleton_name):
		return Engine.get_singleton(singleton_name)
	return null


func _scan_method(plugin) -> String:
	for method in START_METHODS:
		if plugin.has_method(method):
			return method
	if OS.get_name() == "Android" and not START_METHODS.is_empty():
		return String(START_METHODS[0])
	return ""


func _bind_plugin_signals(plugin) -> void:
	if _bound_plugin == plugin:
		return
	_bound_plugin = plugin
	var success := _connect_first_present(plugin, ["qr_scan_succeeded", "scan_succeeded"], Callable(self, "_on_plugin_scan_succeeded"))
	var failed := _connect_first_present(plugin, ["qr_scan_failed", "scan_failed"], Callable(self, "_on_plugin_scan_failed"))
	var cancelled := _connect_first_present(plugin, ["qr_scan_cancelled", "scan_cancelled"], Callable(self, "_on_plugin_scan_cancelled"))
	_scanner_debug("signals success=%s failed=%s cancelled=%s" % [success, failed, cancelled])


func _connect_first_present(plugin, signal_names: Array, callback: Callable) -> String:
	for signal_name in signal_names:
		var name := String(signal_name)
		if plugin.has_signal(name):
			if not plugin.is_connected(name, callback):
				plugin.connect(name, callback)
			return name
	return ""


func _on_plugin_scan_succeeded(payload: String) -> void:
	_scanner_debug("signal succeeded id=%d chars=%d" % [_scan_request_id, payload.strip_edges().length()])
	submit_scan_result(payload)


func _on_plugin_scan_failed(error: String = "") -> void:
	_scanner_debug("signal failed id=%d" % _scan_request_id)
	submit_scan_error(error)


func _on_plugin_scan_cancelled() -> void:
	_scanner_debug("signal cancelled id=%d" % _scan_request_id)
	submit_scan_cancelled()


func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}


func _scanner_debug(message: String) -> void:
	if OS.is_debug_build():
		print("[AndroidQrScanner][debug] %s" % message)
