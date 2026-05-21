# 声音配置

更新时间：2026-05-14

本文记录声音配置的数据结构、页面行为、TTS 引擎接入和播放进度约定。

## 数据表字段

Android 真机声音配置存储在 SQLite 表 `voice_configs`。建表代码在 `android_plugins/play_with_me_android/play-with-me-android/src/main/java/com/playwithme/godot/MemoryDatabase.kt`。

字段：

| 字段 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `id` | `INTEGER PRIMARY KEY AUTOINCREMENT` | 自动生成 | 配置 ID |
| `name` | `TEXT NOT NULL` | 无 | 展示名称 |
| `engine` | `TEXT NOT NULL` | 无 | 引擎 ID |
| `gender` | `TEXT NOT NULL` | `女声` | 性别筛选 |
| `voice` | `TEXT NOT NULL` | 空字符串 | 音色 ID，空表示引擎默认音色 |
| `speed` | `TEXT NOT NULL` | `0.90` | 语速 |
| `pitch` | `TEXT NOT NULL` | `1.00` | 音调 |
| `volume` | `TEXT NOT NULL` | `1.00` | 音量 |
| `enabled` | `INTEGER NOT NULL` | `1` | 是否启用 |
| `active` | `INTEGER NOT NULL` | `0` | 是否主用 |
| `created_at_ms` | `INTEGER NOT NULL` | 当前时间 | 创建时间 |
| `updated_at_ms` | `INTEGER NOT NULL` | 当前时间 | 更新时间 |

Godot 运行时归一化后会额外提供 `key` 字段，用于跨模块引用。预置系统 TTS 默认记录的 `key` 固定为 `voice_system_default`；Android SQLite 的自增 `id` 只作为存储内部 ID。

索引：

- `idx_voice_configs_engine_enabled ON voice_configs(engine, enabled)`

`active` 全局唯一。保存某条配置为 `active=true` 时，数据库会将其它配置的 `active` 置为 `0`；如果 active 配置被停用或删除，会切换到第一条启用配置。

## 页面行为

页面入口：`scripts/pages/config/voice_config_page.gd`

新增弹窗：

- 不展示 `enabled` 和 `active` 两个字段。
- 默认保存为 `enabled=true`、`active=false`。
- 引擎下拉只显示当前环境可用的引擎。

编辑弹窗：

- 展示并可编辑状态行。
- 状态行在一行内展示为 `状态  启用  设为默认`。
- 关闭 `启用` 时会自动关闭 `设为默认`。
- 开启 `设为默认` 时会自动确保 `启用=true`。

列表卡片：

- 主用配置显示 `主用` 标记。
- 停用配置显示 `停用` 标记。
- 引擎不可用时提示 `引擎不可用`。

## 引擎 ID

当前支持：

| 引擎 | ID | 说明 |
| --- | --- | --- |
| 系统 TTS | `system` | Android 系统 TTS 或桌面 DisplayServer TTS |
| Kokoro | `local_kokoro` | 本地 Kokoro/Sherpa |
| NekoTTS | `neko_tts` | 应用内本地 TTS 引擎 |
| VoxSherpa-TTS | `voxsherpa_tts` | 应用内本地 TTS 引擎 |
| MultiTTS | `multi_tts` | 应用内本地 TTS 引擎 |

引擎名称会做归一化，例如 `NekoTTS`、`NekoSpeak`、`neko`、`neko_tts` 都归一为 `neko_tts`；`MultiTTS`、`tts_server_android` 都归一为 `multi_tts`。

## 可用性规则

配置页调用 `TtsRuntime.is_engine_available(engine)` 判断可用性。不可用引擎会从新增/编辑弹窗的引擎下拉框移除。

判断规则：

- `system`：Android bridge 可用则可用；桌面环境需要 `DisplayServer.tts_get_voices()` 有音色。
- `local_kokoro`：Android 插件返回 Kokoro 可用时可用。
- `neko_tts`、`voxsherpa_tts`、`multi_tts`：Android 插件能加载应用内 native runtime，且包内模型资产完整时可用。

NekoTTS、VoxSherpa-TTS、MultiTTS 在本项目内按应用内推理后端接入，不依赖设备安装其它 APK，也不依赖 Android 系统 `TTS_SERVICE` 暴露。Android 插件检查的是：

- native 库是否可加载：`onnxruntime`、`sherpa-onnx-c-api`、`playwithme_kokoro_jni`。
- 模型资产是否存在：`tts/kokoro-int8-multi-lang-v1_1` 下的模型、voices、tokens、中文 FST 和中英文 lexicon。
- 引擎 ID 是否在应用内 catalog 中登记。

应用内本地 TTS 方法统一使用 `tts_local_*` 命名。

官方 Android 项目可能会额外暴露系统 TTS service 供其它 App 选择，但本项目不通过那个入口调用：

| 引擎 | 官方项目 |
| --- | --- |
| NekoTTS | <https://github.com/siva-sub/NekoSpeak> |
| VoxSherpa-TTS | <https://github.com/CodeBySonu95/VoxSherpa-TTS> |
| MultiTTS | <https://github.com/jing332/tts-server-android> |

## 音色列表

系统 TTS：

- 来自 Android `TextToSpeech.voices` 或桌面 `DisplayServer.tts_get_voices()`。
- 配置页展示系统返回的中英文等可用音色，再按当前性别过滤。

Kokoro：

- 使用内置中英文 lexicon，不强制 `lang_code="z"`，避免英文单词触发 eSpeak-ng voice abort。
- 只展示当前内置模型可用的 `zf_*` 和 `zm_*` 音色。
- `zf_*` 归为女声，`zm_*` 归为男声。
- native 配置挂载中文 FST：`phone-zh.fst,date-zh.fst,number-zh.fst`。
- 进入 native 推理前会清理不可播放字符：保留中文、英文单词/字母、空格和常见标点。
- 阿拉伯数字和小数会先转为中文读法，例如 `3.14` 转为 `三点一四`，避免数字处理触发 native 异常。

应用内本地引擎：

- NekoTTS、VoxSherpa-TTS、MultiTTS 通过应用内 catalog 返回音色，不读取 Android `TextToSpeech.voices`。
- 当前 Android 包内可用 backend 为 `kokoro_sherpa`，音色列表来自内置中文 `zf_*` / `zm_*`。
- 后续接入独立模型资产时，在 Android 插件的本地 catalog 和 backend 中扩展，不走系统 TTS 服务发现。
- 配置页展示引擎返回的中英文等可用音色，再按当前性别过滤。

## 播放和预热

运行时入口：`scripts/core/tts/tts_runtime.gd`

声音配置变化后调用 `configure_voice_configs(configs)`：

- 只处理 `enabled=true` 的配置。
- 按 `engine` 聚合去重。
- 对每个启用引擎调用 `warm_up_engine(engine)`，让 TTS 服务常驻。

后续语音播放走已预热通道：

- 系统 TTS：`tts_speak`
- Kokoro：`tts_speak_kokoro`
- 应用内本地引擎：`tts_speak_local`

## 播放进度

TTS 运行时统一发出：

- `speech_started(item)`
- `speech_progress(item, ratio)`
- `speech_finished(item)`
- `speech_failed(item, error)`

Android 系统 TTS 支持 `UtteranceProgressListener.onRangeStart()` 时会回传真实文本进度。应用内本地 TTS 通过生成音频的播放位置回传进度。运行时统一换算为 `0.0` 到 `1.0` 的比例。

不支持真实进度的引擎会使用估算进度，保证上层业务仍能展示播放状态。

试听弹窗：

- `scripts/pages/base/page_tts_ui_base.gd` 维护声音配置仓库、预置系统 TTS 默认记录、TTS 运行时引用、声音目录和声音试听 helper。
- 始终展示试听文本。
- 支持真实或估算进度时，会按比例高亮已播放文本。
- 弹窗空间有限时使用较小字体。

房间业务：

- `scripts/core/tts/tts_history_controller.gd` 根据偏好设置里的 `playback_voice_config_id` 选择声音配置并生成播报项。
- `scripts/pages/base/page_tts_history_ui_base.gd` 接收 `speech_progress` 后更新上层播放状态和桌面席位播报动效。

## Debug API 和测试

Android 插件提供 TTS debug-only 诊断 API：

- `tts_debug_available()`：只在 debuggable 包中返回 `true`。
- `tts_debug_snapshot()`：只在 debuggable 包中返回 JSON 快照；release 或非 debuggable 包返回 `ok=false`。
- adb `TTS_DEBUG_SPEAK`：只在 debuggable 包中播放外部传入的测试文本，走应用内本地推理链路，并返回 started/progress/done/failed 事件。

快照用于定位非系统引擎不可用原因，包含：

- `mode=in_app_inference`。
- native runtime 是否可加载及失败原因。
- 模型资产目录、缺失文件和可用性。
- `localEngines` 中 NekoTTS、VoxSherpa-TTS、MultiTTS 的 backend、voiceCount、available 和 reason。
- 系统 TTS 初始化状态仅作为补充字段。

Godot 侧入口：

- `scripts/core/tts/adapters/android_tts_bridge.gd`：`debug_available()`、`debug_snapshot()`。
- `scripts/core/tts/tts_runtime.gd`：`debug_snapshot()`，会附带引擎常驻服务状态。

adb 侧可调用 debug-only 广播 API 验证设备上应用内 TTS backend 和模型资产状态：

```powershell
.\test\android\tts_debug_snapshot.ps1 -Device <serial>
.\test\android\tts_debug_speak.ps1 -Device <serial> -Engine voxsherpa_tts -Voice zf_024 -Text "这是调试播放测试文本。"
```

这些脚本调用 `com.playwithme.godot.TTS_DEBUG_SNAPSHOT` 和 `com.playwithme.godot.TTS_DEBUG_SPEAK`，只在 debug 包中返回有效 JSON；release 包会返回拒绝信息。

功能点改动必须补充或更新 `test/checks/` 下的脚本。声音配置和 TTS 至少覆盖：

- 引擎下拉：可用本地引擎出现，不可用本地引擎移除。
- 本地音色：不按语言截断，展示引擎返回的中英文等可用音色并按当前性别过滤。
- 非系统播放：Kokoro、NekoTTS、VoxSherpa-TTS、MultiTTS 能走对应 bridge 方法。
- Debug API：debug 快照能解析应用内 runtime、模型资产和本地引擎可用性；debug 播放 API 能用测试文本验证 NekoTTS、VoxSherpa-TTS、MultiTTS 的 started/progress/done。
- 混合文本：试听文本必须覆盖中文、年份、座位号、小数、英文单词混合输入，确认不会出现 `Failed to set eSpeak-ng voice` native crash。
- 编辑弹窗：状态行、试听文本、底部按钮布局不分散。

本地单元测试通过脚本运行，例如：

```powershell
.\tools\run_godot_check.ps1 -Check test\checks\voice_config_page_check.gd,test\checks\android_tts_bridge_check.gd,test\checks\tts_runtime_check.gd
```

Android debug 包部署后，建议用和 UI 试听一致的混合文本验证本地引擎：

```powershell
.\test\android\tts_debug_speak.ps1 -Device <serial> -Engine neko_tts -Voice zf_023 -Text "试听开始。你好，今天是 2026 年，座位 3 号。数值 3.14，21 个苹果。字母 A B C，单词 wolf village game。" -WarmUp
.\test\android\tts_debug_speak.ps1 -Device <serial> -Engine voxsherpa_tts -Voice zf_024 -Text "这是 VoxSherpa 的调试播放测试，座位 12 号，数值 3.14。" -WarmUp
.\test\android\tts_debug_speak.ps1 -Device <serial> -Engine multi_tts -Voice zm_010 -Text "这是 MultiTTS 的调试播放测试，二十一 个苹果，2026 年。" -WarmUp
```

播放完成后检查 crash buffer：

```powershell
& "D:\android\platform-tools\adb.exe" -s <serial> logcat -b crash -d -v time
```

## 修改清单

常见改动位置：

- 配置页 UI：`scripts/pages/config/voice_config_page.gd`
- 声音配置 Schema：`scripts/core/tts/voice_profile_schema.gd`
- 声音配置仓库：`scripts/core/tts/voice_profile_repository.gd`
- 音色目录：`scripts/core/tts/voice_catalog.gd`
- 试听控制：`scripts/core/tts/voice_preview_controller.gd`
- 播放运行时：`scripts/core/tts/tts_runtime.gd`
- 历史消息转播报：`scripts/core/tts/tts_history_controller.gd`
- Android 桥接：`scripts/core/tts/adapters/android_tts_bridge.gd`
- Android 插件：`android_plugins/play_with_me_android/play-with-me-android/src/main/java/com/playwithme/godot/PlayWithMeAndroid.kt`
- 应用内本地 TTS catalog：`android_plugins/play_with_me_android/play-with-me-android/src/main/java/com/playwithme/godot/LocalTtsCatalog.kt`
- 应用内本地 TTS 封装：`android_plugins/play_with_me_android/play-with-me-android/src/main/java/com/playwithme/godot/LocalAndroidTtsEngine.kt`
- SQLite 表：`android_plugins/play_with_me_android/play-with-me-android/src/main/java/com/playwithme/godot/MemoryDatabase.kt`

