# play_with_me_android

这个目录是 `PlayWithMeAndroid` 的 Android 插件工程，负责把 QR 扫描、TTS、AI 内存等 Android 能力编译成 Godot 可用的 AAR。

目录结构：
- `build.gradle.kts`、`settings.gradle.kts`、`gradle.properties`：根构建配置
- `play-with-me-android/`：实际的 Android library module
- `play-with-me-android/src/main/java`：Kotlin 源码
- `play-with-me-android/src/main/cpp`：JNI 和原生实现
- `play-with-me-android/src/main/res`：Android 资源
- `play-with-me-android/src/main/assets`：TTS 模型、词典和其他随包资源
- `play-with-me-android/src/main/jniLibs`：原生 `.so` 依赖
- `play-with-me-android/src/androidTest`：仪器测试

保留内容：
- 源码、资源、测试、Gradle 脚本和必要的本地依赖
- `README.md` 只描述目录用途和构建边界

可删除内容：
- `.gradle/`
- `.kotlin/`
- `.cxx/`
- `play-with-me-android/build/`
- `java_pid*.hprof`

说明：
- 这是一个构建工程，不是运行时临时目录。
- 产物会输出到 `play-with-me-android/build/outputs/aar/`，需要时重新编译即可。
