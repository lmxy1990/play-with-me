@tool
extends EditorPlugin

var _export_plugin: EditorExportPlugin


func _enter_tree() -> void:
	_export_plugin = PlayWithMeAndroidExportPlugin.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	if _export_plugin != null:
		remove_export_plugin(_export_plugin)
		_export_plugin = null


class PlayWithMeAndroidExportPlugin:
	extends EditorExportPlugin

	const DEBUG_AAR := "play_with_me_android/bin/debug/play-with-me-android-debug.aar"
	const RELEASE_AAR := "play_with_me_android/bin/release/play-with-me-android-release.aar"
	const MAVEN_DEPENDENCIES := [
		"androidx.activity:activity-ktx:1.10.1",
		"androidx.camera:camera-camera2:1.4.2",
		"androidx.camera:camera-lifecycle:1.4.2",
		"androidx.camera:camera-view:1.4.2",
		"com.google.mlkit:barcode-scanning:17.3.0",
	]
	const MAVEN_REPOSITORIES := [
		"https://maven.google.com",
		"https://repo1.maven.org/maven2",
	]

	func _get_name() -> String:
		return "PlayWithMeAndroid"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform.get_os_name() == "Android"

	func _get_android_libraries(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		return PackedStringArray([DEBUG_AAR if debug else RELEASE_AAR])

	func _get_android_dependencies(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		return PackedStringArray(MAVEN_DEPENDENCIES)

	func _get_android_dependencies_maven_repos(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		return PackedStringArray(MAVEN_REPOSITORIES)
