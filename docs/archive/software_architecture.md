# 软件架构

更新时间：2026-05-19

> 维护提示：本文是归档架构说明。当前主架构入口是 `docs/architecture.md`，模块内设计和流程请优先维护 `docs/modules/`。

Play With Me 是 Godot 4.6 Mobile 配置的横屏桌游应用。当前核心玩法是狼人杀，软件由 Godot 页面、共享状态、房间规则、网络同步、AI/模型、TTS、记忆和 Android 原生插件组成。

## 总体结构

```text
用户交互
  -> Godot 页面场景
  -> 页面共享基类和运行时服务
  -> 共享状态 / 房间网络会话
  -> 狼人杀规则、AI、记忆、TTS、Android 桥接
  -> 本地 user:// 持久化、WebSocket/UDP、Android 插件
```

`project.godot` 的 `run/main_scene` 指向 `scenes/main.tscn`。主场景挂载 `scripts/core/app_router.gd`，路由器持有一份共享 `AppState` 和一份共享 `RoomNetworkSession`，页面切换时继续沿用同一份状态和网络连接。

## 运行平台

- Godot 版本配置：4.6 Mobile。
- 主渲染器：`mobile`。
- 视口：`1280x720`，移动端横屏优先。
- 主应用包名：`com.playwithme.godot`。
- Android 导出启用 `arm64-v8a` 和 `x86_64`。
- Android 权限包含网络、Wi-Fi 状态、多播和相机。

## 分层职责

### 启动和路由层

- `scenes/main.tscn`：应用根场景。
- `scripts/core/app_router.gd`：维护 route 到 scene 的映射，负责页面实例化、状态注入和网络会话注入。
- 路由 key：
  - `lobby` -> `scenes/lobby.tscn`
  - `table` -> `scenes/werewolf_room.tscn`
  - `model_config` -> `scenes/model_config.tscn`
  - `voice_config` -> `scenes/voice_config.tscn`
  - `memory_config` -> `scenes/memory_config.tscn`
  - `replay` -> `scenes/replay.tscn`

### 页面层

- `scripts/pages/lobby_page.gd`：大厅、房间卡、创建房间、扫码加入。
- `scripts/room/werewolf/werewolf_room_page.gd`：狼人杀桌面、座位交互、准备、机器人、二维码、历史、复盘入口。
- `scripts/pages/config/model_config_page.gd`：模型配置页。
- `scripts/pages/config/voice_config_page.gd`：声音配置页。
- `scripts/pages/config/memory_config_page.gd`：记忆配置页。
- `scripts/pages/replay_page.gd`：本局复盘页。
- `scripts/pages/base/page_navigation_ui_base.gd`：页面共享基类，承载通用 UI、状态提交、网络联动、AI、TTS 和弹层能力。
- `scripts/ui/base/page_ui_base.gd`：基础 UI helper。

### 状态层

- `scripts/core/app_state.gd` 是本地共享状态源，保存房间、玩家、配置、历史、当前规则状态和本机昵称。
- 主状态文件：`user://play_with_me_state.json`。
- 设备身份：当前设计以 `docs/modules/preferences/README.md` 为准，设备私钥保存在偏好设置 JSON，由基础能力消费。
- 房间重连会话：`scripts/room/room_session_store.gd`，保存到 `user://room_reconnect_session_v1.json`。
- 房间副本：`scripts/network/room_replica.gd`，保存到 `user://room_replicas_v1.json`。
- AI 记忆：`scripts/core/memory/memory_manager.gd`，桌面侧使用 `user://play_with_me_memory.json`，Android 真机优先走 SQLite。
- 模型配置：桌面/编辑器使用 `AppState.model_configs` 随 `user://play_with_me_state.json` 保存；Android 真机优先通过 `scripts/android/android_model_config_store.gd` 读写 SQLite `model_configs` 表。

### 房间和规则层

- `scripts/room/room_runtime.gd`：房间基础规则，包括落座、准备、加机器人、改名和开局门槛。
- `scripts/room/room_player_factory.gd`：真人、机器人和空座位的数据构造。
- `scripts/room/werewolf/werewolf_engine.gd`：狼人杀规则引擎，负责地图规则配置、发牌、夜晚行动、发言、投票、遗言、猎人、警长、胜负和赛后流程。
- `scripts/room/werewolf/player/ai_robot/ai_werewolf_wolf_private_flow.gd`：狼人夜聊和目标票。
- `scripts/room/werewolf/player/ai_robot/ai_werewolf_target_intent.gd`：中文目标意图解析。
- `scripts/room/werewolf/player/ai_robot/ai_werewolf_record_formatter.gd`：历史和私聊事件到结构化时间线的映射。

### 网络层

- `scripts/network/lan_room_discovery.gd`：UDP 局域网发现，默认端口 `42870`。
- `scripts/network/room_network_session.gd`：WebSocket host/client 会话，默认端口 `42871`。
- `scripts/network/room_network_codec.gd`：客户端和服务端消息信封编解码。
- `scripts/network/qr_join_payload.gd`：加入码和观战码 payload，v2 二维码只明文暴露 `IP:端口`，房间 ID 和加入 token 放入加密区。
- `scripts/network/room_participant_registry.gd`：参与者、观察者、重连 token 和只读策略。
- `scripts/network/room_network_snapshot_builder.gd`：面向不同参与者的房间快照。
- `scripts/network/host_election.gd`：房主接管候选排序。

房主是房间状态的权威端。客户端通过网络会话提交请求，房主更新状态后广播快照；观察者只接收快照，不提交改变房间的消息。
扫码加入的安全二维码格式和协商流程见 `docs/modules/base/qr_scan_join.md`。

### AI 和模型层

- `scripts/core/model/model_chat_client.gd`：聊天模型 HTTP 客户端。
- `scripts/core/model/model_catalog_client.gd`：模型列表拉取。
- `scripts/core/model/model_profile_selector.gd`：模型配置选择和参数归一化。
- `scripts/room/werewolf/player/ai_robot/ai_werewolf_player_runtime.gd`：狼人杀机器人输入构造、结构化决策解析和模型错误上报。
- `scripts/core/bot/bot_model_request_tracker.gd`：模型请求分类和待处理状态。
- `scripts/room/werewolf/player/ai_robot/ai_werewolf_memory_context.gd`：机器人回合所需的记忆上下文。

模型供应商支持 Ollama、OpenAI API 格式、Anthropic、Gemini 以及按基础模型推理能力接入的其它兼容端点。完整模型配置、API Key、prompt、schema、声音配置和兼容适配参数只存在于控制 AI 玩家的设备本机；房主只路由通用玩家任务，不发起 AI 模型调用，也不把这些私有数据放进房间快照或 device task payload。AI 玩家加入房间或重连初始化时，控制设备从本机机器人档案和模型数据库读取并缓存 `ModelProfile`，后续行动通过基础模型推理能力 `complete_request()` 生成结果。模型不可用、输出无法解析或目标非法时，直接返回错误并中止当前游戏流程，不生成本地兜底行动。

### TTS 层

- `scripts/core/tts/tts_text_sanitizer.gd`：中文播报文本清洗。
- `scripts/core/tts/tts_history_controller.gd`：从历史消息生成播报项。
- `scripts/core/tts/tts_runtime.gd`：播报队列、播放状态和引擎调用。
- `scripts/core/tts/adapters/android_tts_bridge.gd`：Android 系统 TTS、本地 Kokoro 和应用内非系统 TTS 的 Godot 桥接。

桌面/编辑器使用 Godot `DisplayServer.tts_speak()`；Android 真机通过 `PlayWithMeAndroid` 插件调用系统 TTS、本地 Kokoro/Sherpa 或应用内非系统 TTS 引擎。声音配置表字段、active 唯一规则和引擎可用性见 `docs/modules/tts-voice/voice_config.md`。

### Android 原生层

- Godot 侧桥接：
  - `scripts/android/android_qr_scanner.gd`
  - `scripts/core/tts/adapters/android_tts_bridge.gd`
  - `scripts/android/android_memory_store.gd`
  - `scripts/android/android_model_config_store.gd`
- Kotlin 插件源码：`android_plugins/play_with_me_android/`
- Godot 导出插件：`addons/play_with_me_android/`

Android 插件提供扫码、系统 TTS、Kokoro/Sherpa 播放、应用内非系统 TTS、SQLite 记忆、SQLite 模型配置、SQLite 声音配置和设备身份能力。模型配置存储在 `ai_memory.sqlite` 的 `model_configs` 表，声音配置存储在 `voice_configs` 表。导出时通过 `addons/play_with_me_android/export_plugin.gd` 注册 AAR 与 Maven 依赖。

## 目录边界

```text
play-with-me/
├─ project.godot
├─ export_presets.cfg
├─ scenes/                         # 页面场景
├─ scripts/core/                   # 路由、状态、配置、模型、记忆、TTS、机器人
├─ scripts/pages/                  # 大厅、配置页、复盘页
├─ scripts/room/                   # 房间通用运行时
├─ scripts/room/werewolf/          # 狼人杀规则、桌面组件和玩法运行时
├─ scripts/network/                # 加入码、发现、WebSocket、快照、接管
├─ scripts/android/                # Godot 到 Android 插件的桥接
├─ scripts/ui/                     # 页面共享 UI 基类和通用控件
├─ assets/images/werewolf/         # 背景、头像、动作图标和 UI 位图
├─ test/                           # 单元测试、测试数据和 demo 资产
├─ android_plugins/play_with_me_android/
├─ addons/play_with_me_android/
├─ builds/                         # 导出的 APK
└─ docs/
```

`.godot/`、`.godot_user/`、`android/build/` 是工具生成目录，不作为业务源码维护。测试脚本、测试数据和 demo 资产只放在 `test/`，不要放进运行时 `scripts/` 或业务资源目录。

## 测试和调试架构边界

单元测试不属于运行时程序逻辑。后续新增测试脚本、fixture、demo 资产和假对象时，只放在 `test/`，不要把测试分支、测试按钮、测试数据或 demo 流程写进 `scripts/`、`scenes/`、`assets/` 的业务路径。

需要从外部验证业务功能时，可以提供 debug-only 调试接口。这个接口属于受控调试能力，不属于单元测试代码：它只能远程触发正常业务入口，并返回正常业务结果；不能复制规则逻辑，不能绕过权限和状态校验，不能内置测试专用流程。

调试接口必须满足：

- 默认关闭，需要开发者显式启用。
- 只能在 debug 包中启动；release 包必须拒绝启动或拒绝访问。
- 接口层只负责鉴权、参数校验、调用正常业务 API 和结果序列化。
- 测试端负责组织用例和测试数据，程序端不保存测试 fixture。

