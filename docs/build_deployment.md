# 构建部署

更新时间：2026-05-14

本文记录 Play With Me 的本地运行、Android 插件构建、APK 导出和安装方式。构建、导出和推送优先使用 `tools/` 下的脚本，不再手写一长串 Godot 或 adb 命令。

## 本地环境

项目根目录：当前仓库根目录。

Godot 可执行文件：

```powershell
D:\ProgramData\Godot_v4.6.2\Godot_v4.6.2-stable_win64.exe
D:\ProgramData\Godot_v4.6.2\Godot_v4.6.2-stable_win64_console.exe
```

Android 相关路径：

```powershell
D:\android
D:\android\gradle\gradle-8.10.2\bin
D:\android\platform-tools
C:\Program Files\Java\jdk-21.0.10
```

Debug keystore：

```powershell
C:\Users\Administrator\AppData\Roaming\Godot\keystores\debug.keystore
```

打开 Godot 项目：

```powershell
& "D:\ProgramData\Godot_v4.6.2\Godot_v4.6.2-stable_win64.exe" --path .
```

## 脚本入口

常用脚本：

- `tools/build_android_plugin.ps1`：构建 Android 原生插件 AAR，并默认同步到 Godot 插件目录。
- `tools/sync_android_plugin_aar.ps1`：只同步已有 AAR 到 `addons/play_with_me_android/bin/`。
- `tools/export_android_debug_fast.ps1`：快速导出 debug APK。
- `tools/export_android_release.ps1`：导出 release APK。
- `tools/publish_android_release.ps1`：构建 release AAR、导出 3 个 release APK，并创建/更新 GitHub release。
- `tools/install_android_apk.ps1`：安装已有 APK 到 adb 当前在线设备。
- `tools/push_android_fast.ps1`：快速导出 debug APK 并安装到 adb 当前在线设备。
- `tools/export_werewolf_prompt_logs.ps1`：从 Android debug 包导出狼人杀 AI prompt 原始日志，可顺便解析。
- `tools/parse_werewolf_prompt_logs.ps1`：离线解析狼人杀 AI prompt JSONL，按座位、身份和玩家拆分上下文并生成告警报告。
- `tools/replay_werewolf_model_request.ps1`：复放某一次狼人杀 AI 模型请求，定位供应商响应问题。

## Android 插件 AAR

构建 debug 和 release AAR：

```powershell
.\tools\build_android_plugin.ps1
```

只构建 debug AAR：

```powershell
.\tools\build_android_plugin.ps1 -Configuration Debug
```

只同步已有 AAR：

```powershell
.\tools\sync_android_plugin_aar.ps1
```

AAR 源输出：

```text
android_plugins\play_with_me_android\play-with-me-android\build\outputs\aar\play-with-me-android-debug.aar
android_plugins\play_with_me_android\play-with-me-android\build\outputs\aar\play-with-me-android-release.aar
```

Godot 导出使用的 AAR：

```text
addons\play_with_me_android\bin\debug\play-with-me-android-debug.aar
addons\play_with_me_android\bin\release\play-with-me-android-release.aar
```

## Debug 快速导出

快速导出当前设备常用的 arm64 debug 包：

```powershell
.\tools\export_android_debug_fast.ps1
```

指定 ABI：

```powershell
.\tools\export_android_debug_fast.ps1 -Abi x86_64
.\tools\export_android_debug_fast.ps1 -Abi universal
```

导出前顺便构建 debug AAR：

```powershell
.\tools\export_android_debug_fast.ps1 -BuildPlugin
```

debug-fast 脚本会临时修改 `export_presets.cfg` 后自动还原。debug 包策略：

- 保留 Android ETC2/ASTC 纹理导入能力，配置来自 `project.godot` 的 `textures/vram_compression/import_etc2_astc=true`。
- 不压缩 native libraries：`gradle_build/compress_native_libraries=false`。
- 不预编译 shader：`shader_baker/enabled=false`。
- APK 文件稳定后会提前结束 Godot 导出进程，减少等待时间。

默认输出：

```text
builds\android\play-with-me-debug-arm64-v8a.apk
```

## Release 导出

release 包走慢但完整的导出路径：

```powershell
.\tools\export_android_release.ps1
```

指定 ABI：

```powershell
.\tools\export_android_release.ps1 -Abi universal
```

导出前构建 release AAR：

```powershell
.\tools\export_android_release.ps1 -BuildPlugin
```

release 脚本会临时开启：

- `gradle_build/compress_native_libraries=true`
- `shader_baker/enabled=true`

正式发版前需要在 `export_presets.cfg` 中补齐 release keystore、版本号和目标 ABI。

## 发布 1.3.0

现成的发版脚本会先构建 release AAR，再导出下面 3 个安装包：

- `builds\android\play-with-me-release-arm64-v8a.apk`
- `builds\android\play-with-me-release-x86_64.apk`
- `builds\android\play-with-me-release-universal.apk`

一键构建并发布 GitHub release：

```powershell
临时设置 release 签名密码，不要写入仓库：
$env:PLAY_WITH_ME_RELEASE_KEYSTORE_PASSWORD = "<release-keystore-password>"

.\tools\publish_android_release.ps1
```

脚本会复用现有的 `gh` 登录态创建或更新 `v1.3.0` release，不会把账号 token 或本地 git 敏感信息写进仓库。

## 安装和推送

先查看当前在线设备：

```powershell
& "D:\android\platform-tools\adb.exe" devices -l
```

Wi-Fi 调试设备需要先用设备当前显示的地址连接。不要把设备地址写死进脚本或文档：

```powershell
& "D:\android\platform-tools\adb.exe" connect <device-current-address>
```

也可以让推送脚本在开始时先尝试连接设备当前地址：

```powershell
.\tools\push_android_fast.ps1 -Connect <device-current-address>
```

安装已有 APK 到所有当前在线设备：

```powershell
.\tools\install_android_apk.ps1 -Apk builds\android\play-with-me-debug-arm64-v8a.apk
```

只安装到某一台设备：

```powershell
.\tools\install_android_apk.ps1 -Device <serial> -Apk builds\android\play-with-me-debug-arm64-v8a.apk
```

快速导出并推送到所有当前在线设备：

```powershell
.\tools\push_android_fast.ps1
```

常用参数：

```powershell
.\tools\push_android_fast.ps1 -BuildPlugin
.\tools\push_android_fast.ps1 -Connect <host:port>
.\tools\push_android_fast.ps1 -Device <serial>
.\tools\push_android_fast.ps1 -Abi universal
.\tools\push_android_fast.ps1 -NoExport
.\tools\push_android_fast.ps1 -NoLaunch
```

`push_android_fast.ps1` 默认读取 `adb devices -l` 的当前在线设备；未指定 `-Device` 时会安装到全部在线设备。`-Connect` 可以传一个或多个当前地址，脚本会先尝试 `adb connect` 再读取设备列表。列表中已有但处于 `offline` 状态的网络调试设备，脚本也会尝试重新 `adb connect`。`-Abi auto` 会按设备 ABI 分组导出，避免每次都导 universal 包。多设备推送时，某一台安装失败不会中断其它设备，脚本会继续安装剩余设备并在最后汇总失败。

如果安装返回 `INSTALL_FAILED_ABORTED: User rejected permissions`，是设备侧拒绝了 USB 安装或权限确认；需要在设备上允许当前调试会话的安装请求后重跑同一脚本。

## Android 导出配置

Android 预设文件：`export_presets.cfg`

关键配置：

- 预设名称：`Android`
- 包名：`com.playwithme.godot`
- 版本名：`1.3.0`
- Gradle build：启用
- 相机、网络、Wi-Fi 状态和多播权限：启用
- Debug keystore：`C:/Users/Administrator/AppData/Roaming/Godot/keystores/debug.keystore`

`addons/play_with_me_android/export_plugin.gd` 会在 Android 导出时注册 AAR、本地 so 和 Maven 依赖。

## Debug-only 调试接口

业务功能需要远程测试时，只允许在 debug 包开启调试接口。release 包不得暴露调试端口、测试命令、测试路由或测试数据导入能力。

实现调试接口时必须遵守：

- 运行时必须二次判断 debug build，非 debug 包直接拒绝启动或拒绝访问。
- 默认关闭，需要显式配置或启动参数开启。
- 只调用正常业务逻辑，不在程序内写测试逻辑、测试分支、fixture 或 demo 数据。
- 测试数据由 `test/` 下的测试脚本或外部测试端发送，不打进发布包。

TTS debug-only 诊断接口：

- Android 插件：`tts_debug_available`、`tts_debug_snapshot`。
- adb 广播：`com.playwithme.godot.TTS_DEBUG_SNAPSHOT`，脚本入口 `test/android/tts_debug_snapshot.ps1`。
- adb 播放：`com.playwithme.godot.TTS_DEBUG_SPEAK`，脚本入口 `test/android/tts_debug_speak.ps1`。
- Godot bridge：`AndroidTtsBridge.debug_available()`、`AndroidTtsBridge.debug_snapshot()`。
- 运行时：`TtsRuntime.debug_snapshot()`。

声音配置和非系统 TTS 修改后，至少运行：

```powershell
.\tools\run_godot_check.ps1 -Check test\checks\voice_config_page_check.gd,test\checks\android_tts_bridge_check.gd,test\checks\tts_runtime_check.gd
```

部署 debug 包到设备后，还要用 debug-only 播放 API 验证本地 TTS 链路，测试文本应覆盖中文、年份、座位号、小数和英文混合输入：

```powershell
.\test\android\tts_debug_speak.ps1 -Device <serial> -Engine neko_tts -Voice zf_023 -Text "试听开始。你好，今天是 2026 年，座位 3 号。数值 3.14，21 个苹果。字母 A B C，单词 wolf village game。" -WarmUp
.\test\android\tts_debug_speak.ps1 -Device <serial> -Engine voxsherpa_tts -Voice zf_024 -Text "这是 VoxSherpa 的调试播放测试，座位 12 号，数值 3.14。" -WarmUp
.\test\android\tts_debug_speak.ps1 -Device <serial> -Engine multi_tts -Voice zm_010 -Text "这是 MultiTTS 的调试播放测试，二十一 个苹果，2026 年。" -WarmUp
& "D:\android\platform-tools\adb.exe" -s <serial> logcat -b crash -d -v time
```

狼人杀 AI prompt 调试：

```powershell
.\tools\export_werewolf_prompt_logs.ps1 -Device <serial> -Parse
```

常用输出位于 `exports\werewolf_prompt_logs_<timestamp>\`：

- `raw_werewolf_bot_prompts.jsonl`：设备内原始模型请求上下文日志。
- `actual_model_prompts_by_seat.txt`：按记录顺序汇总后的完整 prompt 文本。
- `actual_model_prompts_by_identity.txt`：按身份汇总后的完整 prompt 文本，兼容旧导出入口。
- `by_seat\`：按座位和身份拆分后的上下文，适合逐座位检查。
- `by_identity\`：按身份拆分后的上下文。
- `by_player\`：按玩家标题和身份拆分后的上下文。
- `prompt_summary.csv`：每条请求的座位、身份、阶段、模型配置和上下文摘要。
- `prompt_warnings.csv`：静态分析告警，例如首夜前发言声称查验、prompt 缺少公开发言约束、身份可见性异常。
- `prompt_analysis.md`：面向人工排查的 Markdown 摘要。

只解析已有导出：

```powershell
.\tools\parse_werewolf_prompt_logs.ps1 -InputDir exports\werewolf_prompt_logs_<timestamp>
.\tools\parse_werewolf_prompt_logs.ps1 -RawJsonl exports\werewolf_prompt_logs_<timestamp>\raw_werewolf_bot_prompts.jsonl
```

兼容旧入口仍可用：

```powershell
.\tools\export_werewolf_prompt_logs_by_identity.ps1 -Device <serial>
```

需要复放某条模型请求时，先看 `prompt_summary.csv` 或 `prompt_analysis.md` 的 `sequence`，再执行：

```powershell
.\tools\replay_werewolf_model_request.ps1 -Device <serial> -Sequence <sequence>
```

## Android 插件能力

Singleton 名称：

```text
PlayWithMeAndroid
```

主要能力：

- 二维码扫描：`start_qr_scan`、`scan_join_qr`、`startScan`、`scanQr`。
- 系统 TTS：`tts_list_voices`、`tts_speak`、`tts_stop`。
- Kokoro TTS：`tts_kokoro_available`、`tts_kokoro_warm_up`、`tts_list_kokoro_voices`、`tts_speak_kokoro`。
- 本地非系统 TTS：`tts_local_available`、`tts_local_warm_up`、`tts_list_local_voices`、`tts_speak_local`。
- TTS 调试：`tts_debug_available`、`tts_debug_snapshot`；debug 包可用 `test/android/tts_debug_speak.ps1` 通过 adb 播放测试文本。
- 记忆存储：`memory_load_state`、`memory_append`、`memory_compact`、`memory_save_long_term`、`memory_delete_scope`、`memory_discard_session`、`memory_list_scopes`、`memory_delete_owner`。
- 模型配置存储：`model_config_available`、`model_config_list`、`model_config_save`、`model_config_delete`。
- 声音配置存储：`voice_config_available`、`voice_config_list`、`voice_config_save`、`voice_config_delete`。
- 设备身份：设备私钥由偏好设置 JSON 持久化；基础能力负责派生设备身份、签名和校验，Android 原生能力可作为平台桥接辅助。

TTS 信号：

- `tts_ready`
- `kokoro_tts_ready`
- `external_tts_ready`
- `tts_voices_updated`
- `tts_speech_started`
- `tts_speech_progress`
- `tts_speech_done`
- `tts_speech_failed`
