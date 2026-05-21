# android

这个目录是 Godot Android 导出工程的本地工作区。真正的 Android 工程在 `android/build/` 下，里面放的是导出模板、Gradle 配置和打包所需资源。

保留内容：
- `android/build/build.gradle`
- `android/build/config.gradle`
- `android/build/settings.gradle`
- `android/build/gradle.properties`
- `android/build/gradlew` 和 `android/build/gradlew.bat`
- `android/build/src/`
- `android/build/res/`
- `android/build/libs/`
- `android/build/assetPackInstallTime/`
- `android/.build_version`

可清理内容：
- `android/build/.gradle/`
- `android/build/build/`

说明：
- 这里主要用于 Android 导出、打包和调试。
- 不放游戏业务源码，业务逻辑应保留在项目主代码目录。
