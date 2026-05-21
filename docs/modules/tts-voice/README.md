# TTS 语音模块

更新时间：2026-05-16

TTS 语音模块是基础模块，负责声音配置管理和文本转语音播放。它回答“这段已确认文本用哪个声音播报，播报状态是什么”。

TTS 语音模块像一个语音输出黑盒：调用方提交文本、声音配置和播放选项，模块返回排队、开始、进度、完成、失败或停止等播放结果。它不判断文本来源，不改变历史原文，不理解房间规则、玩家策略、模型输出或机器人记忆。

跨模块对象 `TtsPlaybackRequest` 和 `TtsPlaybackResult` 的字段权威见 [跨模块契约](../../contracts/README.md)。本文保留声音配置、播放队列和 TTS 引擎流程说明。

## 模块定位

```text
声音配置页面
  -> TTS 语音模块
       -> 保存 / 删除 / 选择 VoiceProfile
       -> 管理主用声音和可用声音目录

玩家模块 / 房间模块 / 其它已确认输出调用方
  -> TTS 语音模块
       -> speak_text(text + voice profile + options)
       -> 返回播放事件或结构化错误
```

TTS 只消费调用方已经确认可以播报的文本。文本能不能公开、是否属于某个玩家、是否应该写入历史，都由调用方或上层编织模块决定。

## 能力边界

TTS 语音模块负责：

- 保存、读取、删除和选择声音配置。
- 管理声音引擎、声音 ID、语速、音调、音量、启用状态和默认状态。
- 清洗播报文本，保证语音输出更稳定。
- 将文本加入播放队列。
- 调用 Android TTS、本地 TTS 或 Godot 可用 TTS 能力。
- 提供播放开始、进度、完成、失败、停止等事件。
- 提供停止播放、清空队列、读取队列状态和只读调试能力。
- 提供声音配置校验能力。

TTS 语音模块不负责：

- 判断文本是否可以公开。
- 生成玩家发言、系统旁白或历史消息。
- 调用模型、解析模型输出或修正 AI 行为。
- 读取、更新或总结机器人记忆。
- 修改房间历史、游戏房间状态或玩家状态。
- 实现房间认证、二维码、扫码、加密或设备签名。
- 保存用户昵称、头像、设备私钥或模型 API Key。

## 生命周期契约

| 生命周期 | 触发方 | 建议调用 | 作用 |
| --- | --- | --- | --- |
| `config_loaded` | 应用启动 / 声音配置页打开 | `list_voice_profiles()` | 读取可用声音配置。 |
| `voice_saved` | 声音配置页 | `save_voice_profile()` | 保存单个声音配置。 |
| `voice_deleted` | 声音配置页 | `delete_voice_profile()` | 删除声音配置。 |
| `voice_selected` | 声音配置页 | `select_active_voice()` | 选择声音配置页的主用声音。 |
| `playback_voice_selected` | 偏好设置页 | `update_playback_voice_config()` | 选择本机历史消息播放使用的声音配置引用。 |
| `before_speak` | 玩家模块 / 房间模块 / 调用方 | `speak_text()` | 提交已确认文本。 |
| `speech_queued` | TTS 语音模块 | 返回 `queued` 事件 | 文本进入播放队列。 |
| `speech_started` | TTS 引擎 | 播放事件 | 开始播放。 |
| `speech_completed` | TTS 引擎 | 播放事件 | 播放完成。 |
| `speech_failed` | TTS 引擎 | 播放事件 | 播放失败。 |
| `speech_stopped` | 调用方 / 页面关闭 | `stop_speech()` | 停止当前播放。 |
| `profile_invalid` | 配置读取 | `discard_invalid_voice_profile()` | 丢弃不符合当前结构的声音配置。 |

## 核心对象

### VoiceProfile

`VoiceProfile` 是声音配置的归一化结构。

| 字段 | 说明 |
| --- | --- |
| `schema_version` | 声音配置结构版本。 |
| `voice_profile_id` | 声音配置 ID。 |
| `key` | Godot 运行时稳定引用；系统默认 TTS 记录固定为 `voice_system_default`。 |
| `name` | 展示名。 |
| `engine` | 语音引擎，例如 `android_system`、`kokoro_local`、`godot_display_server`。 |
| `voice_id` | 引擎内声音 ID。 |
| `speed` | 语速。 |
| `pitch` | 音调。 |
| `volume` | 音量。 |
| `enabled` | 是否启用。 |
| `active` | 是否为声音配置页主用声音。全局主用应唯一。 |
| `created_at` | 创建时间。 |
| `updated_at` | 最近更新时间。 |
| `metadata` | 扩展字段，只保存声音配置元数据。 |

约定：

- `voice_profile_id` 是稳定引用，不应随展示名变化。
- `key` 是 Godot 层跨模块引用；Android SQLite 自增 `id` 是存储内部字段。
- `active` 只代表声音配置页主用声音，不代表某个玩家一定使用它。
- 偏好设置模块保存 `playback_voice_config_id`，历史消息播报优先按该引用选取声音配置。
- 调用方通过 `TtsPlaybackRequest.voice_profile_id` 指定本次播报使用的声音；通过玩家模块进入 TTS 的请求必须显式传入。

### TtsPlaybackRequest

`TtsPlaybackRequest` 是一次播报请求。

| 字段 | 说明 |
| --- | --- |
| `schema_version` | 请求结构版本。 |
| `request_id` | 请求 ID，用于去重和调试。 |
| `text` | 已确认要播报的文本。 |
| `voice_profile_id` | 必填，指定声音配置或音色引用。 |
| `playback_options` | 播放选项，例如是否插队、是否允许队列、最大长度。 |
| `source` | 调用来源，例如 `player_speech`、`room_notice`、`system_prompt`。 |
| `visibility` | 可见性，例如 `public`、`private_local`。 |
| `metadata` | 扩展字段。 |

约定：

- `text` 必须是调用方已经确认的文本。
- TTS 可以清洗播报副本，但不能修改调用方持有的原文。
- 通过玩家模块进入 TTS 的请求必须带 `voice_profile_id`。
- `source` 只用于调试和策略，不让 TTS 推断业务规则。

### TtsPlaybackEvent

`TtsPlaybackEvent` 描述播放状态变化。

| 字段 | 说明 |
| --- | --- |
| `request_id` | 请求 ID。 |
| `status` | `queued`、`started`、`progress`、`completed`、`failed`、`stopped`。 |
| `voice_profile_id` | 使用的声音配置。 |
| `position_ms` | 当前播放位置，可选。 |
| `duration_ms` | 预计或实际时长，可选。 |
| `error` | 失败时的结构化错误。 |
| `warnings` | 非致命问题。 |

### TtsQueueState

`TtsQueueState` 是当前播放队列的只读快照。

| 字段 | 说明 |
| --- | --- |
| `current_request_id` | 当前播放请求 ID。 |
| `queued_count` | 等待播放数量。 |
| `engine_state` | 引擎状态，例如 `idle`、`speaking`、`paused`、`unavailable`。 |
| `last_error` | 最近一次错误。 |

## 对外接口

以下接口是设计契约，不要求当前代码函数名完全一致。

```text
list_voice_profiles(request) -> VoiceProfileListResult
get_voice_profile(request) -> VoiceProfileResult
save_voice_profile(request) -> VoiceProfileResult
delete_voice_profile(request) -> VoiceProfileMutationResult
select_active_voice(request) -> VoiceProfileSelectionResult
speak_text(request) -> TtsPlaybackResult
stop_speech(request) -> TtsPlaybackResult
clear_queue(request) -> TtsQueueResult
get_tts_state(request) -> TtsQueueStateResult
get_tts_debug_state(request) -> TtsDebugResult
```

### save_voice_profile

```text
save_voice_profile(request) -> VoiceProfileResult
```

`request`：

| 字段 | 说明 |
| --- | --- |
| `profile` | 要保存的 `VoiceProfile`。 |
| `allow_overwrite` | 是否允许覆盖同 ID 配置。 |
| `validate_only` | 是否只校验不保存。 |

校验规则：

- `voice_profile_id`、`engine`、`voice_id` 必填。
- `speed`、`pitch`、`volume` 必须在引擎支持范围内。
- 同一时间只允许一个全局 `active` 声音；保存新的 active 时应取消已有 active。
- 本机历史消息播放使用偏好设置模块的 `playback_voice_config_id`，不直接由 `active` 决定。

### speak_text

```text
speak_text(request) -> TtsPlaybackResult
```

流程：

```text
调用方
  -> 确认文本可以播报
  -> speak_text(text + voice_profile_id + options)
  -> TTS 清洗播报副本
  -> 选择声音引擎
  -> 加入队列或立即播放
  -> 返回 queued / started / failed
```

约定：

- 空文本直接返回 validation error。
- 缺少 `voice_profile_id` 时返回 validation error。
- 指定声音不可用时，返回 `voice_not_found` 或 `engine_unavailable`。
- 如果队列满，返回 `queue_full`，不丢弃当前播放，除非 `playback_options` 明确要求插队。

### stop_speech

```text
stop_speech(request) -> TtsPlaybackResult
```

约定：

- 可以停止当前请求，也可以按 `request_id` 停止指定请求。
- 停止播放不修改房间历史、玩家状态或游戏房间状态。
- 停止失败返回结构化错误。

### clear_queue

```text
clear_queue(request) -> TtsQueueResult
```

约定：

- 清空等待队列不一定停止当前播放，是否停止由 request 参数决定。
- 返回被清理的请求数量和当前队列状态。

## 文本清洗边界

`TtsTextSanitizer` 只影响语音输出副本。

允许做：

- 去除不适合朗读的控制字符。
- 把过长空白压缩为单个停顿。
- 对明显不适合朗读的标记做替换，例如 Markdown 代码围栏。
- 限制单次播报长度，超长文本返回 warning 或分段。

不允许做：

- 修改房间历史原文。
- 修改玩家已确认发言。
- 修改机器人记忆输入。
- 根据狼人杀房间模块的玩法语义删改文本含义。
- 把私密文本改成公开文本。

## 持久化策略

Android 真机优先写 SQLite，桌面和编辑器可以写 JSON。

当前归属：

```text
Android: SQLite voice_configs
Editor/Desktop: user://play_with_me_state.json
```

声音配置字段和页面说明见 [voice_config.md](voice_config.md)。

## 版本与无效数据

声音配置由播放请求引用，只接受当前结构；通用玩家资料不保存声音配置引用。

处理规则：

- 新增字段必须提供默认值。
- 缺少必填字段、字段名不匹配或 `schema_version` 不匹配时，直接丢弃该声音配置。
- 缺少 `active` 时，新建配置选择第一个可用声音或系统默认声音作为声音配置页主用项。
- 缺少 `speed`、`pitch`、`volume` 时，新建配置使用引擎默认值。
- Android 引擎目录变化时，同步当前配置写入和读取逻辑；不保留原字段读取路径。

## 失败处理

| 场景 | 策略 |
| --- | --- |
| 文本为空 | 返回 validation error。 |
| 声音配置不存在 | 返回 `voice_not_found`。 |
| 指定声音不可用 | 返回 `voice_not_found` 或 `engine_unavailable`。 |
| Android bridge 不可用 | 返回 `engine_unavailable`。 |
| 本地 TTS 模型不可用 | 返回 `engine_unavailable` 或返回 engine_unavailable。 |
| 队列已满 | 返回 `queue_full`，调用方决定是否再次发起。 |
| 播放中断 | 返回 `stopped` 或 `interrupted` 事件。 |
| 引擎异常 | 返回 structured error，不修改上层业务状态。 |

## 只读调试

```text
get_tts_debug_state(request) -> TtsDebugResult
```

只读调试信息建议包含：

- 当前可用声音配置列表。
- active 声音配置和偏好设置中的播放声音配置引用。
- 当前引擎状态。
- 当前播放请求 ID。
- 队列长度。
- 最近一次播报的状态和错误码。
- Android bridge、本地 TTS 和 Godot TTS 的可用性。

约定：

- 调试接口不得开始或停止播放。
- 调试接口不得修改声音配置。
- 默认不返回完整私密文本，可返回长度、摘要或 request ID。

## 与其它模块的关系

| 模块 | TTS 语音模块如何交互 |
| --- | --- |
| 玩家模块 | 玩家模块通过 `player_speech_output.gd` 提交已确认文本和调用方传入的音色 ID，TTS 负责播报和播放事件。 |
| 房间模块 | 房间可以提交系统提示或已接受历史文本，TTS 不修改房间状态。 |
| 狼人杀真人/AI 玩家模块 | 狼人杀房间模块接受文本后可通过玩家模块或直接调用 TTS。 |
| 模型管理模块 | 无直接依赖；模型输出必须先被上层确认。 |
| 机器人/RAG 模块 | 无直接依赖；TTS 不读取或更新记忆。 |
| 偏好设置模块 | 偏好设置保存本机播放声音配置引用；声音配置详情仍由 TTS 语音模块维护。 |
| 基础能力 | 不交叉；二维码、扫码、加密和认证不属于 TTS。 |

## 文档和代码归属

```text
scenes/voice_config.tscn
scripts/pages/config/voice_config_page.gd
scripts/player/player_speech_output.gd
scripts/core/tts/
  voice_profile_schema.gd
  voice_profile_repository.gd
  voice_catalog.gd
  voice_preview_controller.gd
  tts_runtime.gd
  tts_history_controller.gd
  tts_text_sanitizer.gd
  adapters/android_tts_bridge.gd
  adapters/android_voice_config_store.gd
android_plugins/play_with_me_android/
  LocalAndroidTtsEngine.kt
  KokoroTtsEngine.kt
  KokoroNative.kt
  LocalTtsCatalog.kt
  MemoryDatabase.kt
```

## 维护规则

- TTS 核心接口保持为 `text + voice profile + playback options -> playback events / structured error`。
- 调用方必须先确认文本可播报，再提交给 TTS。
- 文本清洗只影响播报副本，不改历史原文。
- 新 TTS 引擎必须同时更新 Godot 可用性判断、Android catalog、配置页和文档。
- 字段变化同步 SQLite schema、store、测试和 [voice_config.md](voice_config.md)。
- 播放失败不应撤销玩家发言、房间历史、游戏房间状态或机器人记忆。
