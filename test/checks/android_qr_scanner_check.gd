extends SceneTree


class FakeScannerPlugin:
	extends Node

	signal qr_scan_succeeded(payload: String)
	signal qr_scan_failed(error: String)
	signal qr_scan_cancelled()

	var result = true
	var started := 0

	func start_qr_scan():
		started += 1
		return result


class EmptyScannerPlugin:
	extends Node


class TestScanner:
	extends AndroidQrScanner

	var plugin

	func _init(plugin_ref) -> void:
		plugin = plugin_ref

	func _plugin():
		return plugin


func _initialize() -> void:
	var empty_plugin := EmptyScannerPlugin.new()
	root.add_child(empty_plugin)
	var scanner := TestScanner.new(empty_plugin)
	var missing_result: Dictionary = scanner.start_scan()
	assert(not bool(missing_result.get("ok", false)))

	var string_plugin := FakeScannerPlugin.new()
	string_plugin.result = "{\"app\":\"chat_with_me\",\"version\":1,\"host\":\"192.168.1.2\",\"port\":42871}"
	root.add_child(string_plugin)
	scanner = TestScanner.new(string_plugin)
	var payloads: Array = []
	scanner.scan_succeeded.connect(func(payload: String): payloads.append(payload))
	var string_result: Dictionary = scanner.start_scan()
	assert(bool(string_result.get("ok", false)))
	assert(string_plugin.started == 1)
	assert(payloads.size() == 1)
	assert(String(payloads[0]).contains("chat_with_me"))

	var signal_plugin := FakeScannerPlugin.new()
	root.add_child(signal_plugin)
	scanner = TestScanner.new(signal_plugin)
	var signaled_payloads: Array = []
	var failures: Array = []
	var cancellations: Array = []
	scanner.scan_succeeded.connect(func(payload: String): signaled_payloads.append(payload))
	scanner.scan_failed.connect(func(error: String): failures.append(error))
	scanner.scan_cancelled.connect(func(): cancellations.append(true))
	var signal_result: Dictionary = scanner.start_scan()
	assert(bool(signal_result.get("ok", false)))
	signal_plugin.qr_scan_succeeded.emit("payload_from_signal")
	assert(signaled_payloads.size() == 1)
	assert(String(signaled_payloads[0]) == "payload_from_signal")
	signal_plugin.qr_scan_failed.emit("camera_denied")
	assert(failures.size() == 1)
	assert(String(failures[0]) == "camera_denied")
	signal_plugin.qr_scan_cancelled.emit()
	assert(cancellations.size() == 1)

	scanner.submit_scan_result("  ")
	assert(failures.size() == 2)
	assert(String(failures[1]) == "扫码结果为空")
	quit()
