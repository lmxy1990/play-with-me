# 维护

更新时间：2026-05-21

本文记录 Play With Me 当前代码维护时最常用的文件位置和改动规则。

## 维护原则

- 以当前 Godot 项目为准，围绕软件本身更新文档和代码。
- 顶层工程目录保持现有结构；`scripts/`、`scenes/`、`assets/`、`test/` 等目录内部按模块归属建子目录或文件。
- 页面展示逻辑放在对应页面脚本，通用 UI helper 放在 `scripts/ui/`。
- 二维码生成、扫码、加密、设备身份和认证基础放在基础能力维护；房间参与者、席位、交互请求、事件分发、玩家 inbox、可见历史、真人副本、重连、主机选举和生命周期放在房间模块维护。
- 具体游戏房间模块接入通用房间模块。狼人杀地图、支持人数、场景槽位、游戏状态、玩法执行和进度推进放在 `scripts/room/werewolf/`。
- 玩家模块按 `docs/modules/player/` 维护，由父级玩家模块、真人玩家模块、AI 玩家模块、狼人杀真人玩家模块、狼人杀 AI 玩家模块共同组成；具体代码归属为 `scripts/player/`、`scripts/player/human/`、`scripts/player/ai/`、`scripts/player/werewolf/human/`、`scripts/player/werewolf/ai/`。
- 偏好设置按 `docs/modules/preferences/` 维护，只保存本机偏好 JSON：昵称、头像 ID、播放声音配置引用和设备私钥。
- 跨模块数据对象、下发范围、错误码和调用结果按 `docs/contracts/README.md` 维护；字段变更时先更新契约，再同步生产者和消费者模块。
- 通用网络信封、二维码 payload 和局域网发现放在 `scripts/network/`；房间 WebSocket 会话、快照、重连副本、参与者注册和房主接管放在 `scripts/room/network/`。
- 模型输入输出放在 `scripts/core/model/`；机器人/RAG 记忆放在 `scripts/core/memory/` 和玩法记忆适配；TTS 放在 `scripts/core/tts/`。
- Android 原生能力通过 `scripts/android/` 桥接到 `android_plugins/play_with_me_android/`。
- 单元测试、测试数据和 demo 资产放在 `test/`，不要混入运行时 `scripts/`、`scenes/` 或业务资源目录。
- 后续不要为了单元测试在程序逻辑里写测试分支、测试数据、测试按钮或 demo 流程。
- 如果需要测试业务功能点，可以新增调试接口远程调用正常业务逻辑；接口只做参数校验、鉴权、调用和结果返回，不复制业务规则，不内置测试专用逻辑。
- 调试接口必须只允许 debug 包开启，运行时还要二次判断 debug build；release 包即使配置项打开也必须拒绝启动或拒绝访问。
- 不要手工维护 `.godot/`、`.godot_user/` 和 `android/build/` 生成内容。

## 模块代码铁律

- 模块必须有独立代码文件归属；实现文件放在模块目录内，不放到调用方、页面层或临时公共目录里。
- 模块对外提供公开接口能力，接口可以是 facade、service、runtime、repository、adapter 或契约对象；调用方只能依赖这些接口。
- 其他模块需要编织能力时，只引用被调用模块公开接口，不直接引用其 internal 实现文件，不复制其字段拼装、校验算法或持久化细节。
- 模块内部实现要继续拆成独立文件，例如状态、校验、构建、解析、存储和适配；不要把所有实现塞进一个巨型入口文件。
- 新增跨模块调用前，先补接口和契约，再写实现；如果只能通过直接访问内部文件才能完成调用，说明模块接口还缺失。
- `core`、`ui`、`common` 只放真正跨模块基础能力或纯展示组件，不能作为模块内部实现的逃生目录。

## 新文件落位规则

新增文件时先判断模块归属：

1. 能归到明确模块的，放到对应工程目录下的模块路径。
2. 模块对外入口放公开接口文件，模块内部算法、状态、存储和适配拆成模块内实现文件。
3. 确实跨模块复用的，才放 `core`、`ui`、`common` 等公共目录。
4. 只服务测试、demo 或调试的，放到 `test/`，不要放进运行时目录。
5. 不因为单个文件方便就新增顶层业务目录。

示例：

- 新增模型调用逻辑：`scripts/core/model/`。
- 新增机器人记忆逻辑：`scripts/core/memory/` 或机器人/RAG 目标目录。
- 新增大厅页面逻辑：`scripts/pages/` 内按大厅模块组织。
- 新增玩家资料、玩家级可信通道、玩家临时数据或恢复帧：目标归属 `scripts/player/`。
- 新增通用玩家能力：`scripts/player/`。
- 新增真人玩家通用能力：`scripts/player/human/`。
- 新增 AI 玩家通用能力：`scripts/player/ai/`。
- 新增狼人杀真人玩家能力：`scripts/player/werewolf/human/`。
- 新增狼人杀 AI 玩家能力：`scripts/player/werewolf/ai/`。
- 新增狼人杀场景：`scenes/room/werewolf/` 或当前狼人杀房间模块约定的对应场景目录。
- 新增偏好设置头像资源：`assets/images/avatars/`。
- 新增模块检查脚本：`test/checks/<module>/`。

## 测试和调试接口边界

- 单元测试入口、假对象、fixture、demo 截图和验证脚本统一放在 `test/`。
- 运行时目录只保留真实功能。为了可测试性暴露的业务方法必须是产品本身合理的领域接口，不要出现 `for_test`、`demo`、`mock` 等测试语义。
- 业务功能需要远程验证时，可以新增 debug-only 调试服务，例如本机 HTTP/WebSocket/RPC 入口。该入口必须调用现有页面、规则引擎、网络、记忆、TTS 等正常业务 API。
- 调试服务不得写入内置测试数据、不得绕过正常校验、不得替代真实业务路径；需要准备状态时由测试端通过公开调试接口按正常动作创建。
- 调试服务默认关闭，必须显式启用，并且只能在 debug 包中生效。建议实现上同时检查导出/运行环境的 debug 标记。
- release 包不得暴露调试端口、测试命令、测试路由或测试数据导入入口。

## 常见改动位置

### 新增或修改页面

1. 在 `scenes/` 下添加或调整页面场景。
2. 在 `scripts/pages/` 或 `scripts/room/` 下添加页面脚本。
3. 在 `scripts/core/app_router.gd::PAGE_SCENES` 注册 route。
4. 页面需要状态时实现 `set_app_state(state)`。
5. 页面需要网络时实现 `set_network_session(session)`。
6. 页面切换通过 `navigate_requested(route, payload)` 发出。

### 修改大厅

- 大厅入口：`scripts/pages/lobby_page.gd`。
- 大厅主渲染、工具栏和房间卡片：`scripts/pages/lobby/lobby_page_flow.gd`。
- 工具栏：`_lobby_toolbar()`。
- 房间卡片：`_room_card(room)`。
- 局域网房间发现和列表刷新：`scripts/pages/base/page_room_discovery_ui_base.gd`。
- 本机昵称、设备身份和网络身份注入：`scripts/pages/base/page_identity_ui_base.gd`。
- 房间网络会话外壳：`scripts/pages/base/page_room_network_ui_base.gd`。
- 参与者注册、观察者和认证材料包装：`scripts/pages/base/page_room_participant_ui_base.gd`。
- 房间快照、副本和主机接管页面编排：`scripts/pages/base/page_room_replica_ui_base.gd`。
- 二维码入房、重连和房主加入处理：`scripts/pages/base/page_room_join_ui_base.gd`。
- 房主端 peer 准备、换座、旁观、加机器人、改名和离线处理：`scripts/pages/base/page_room_host_peer_ui_base.gd`。
- 历史消息播报、播放声音偏好读取和桌面席位播报动效：`scripts/pages/base/page_tts_history_ui_base.gd`。
- 机器人资料仓库、机器人门面和通用记忆管理器页面接入：`scripts/pages/base/page_bot_profile_ui_base.gd`。
- 创建房间：`_open_create_room()`、`_create_room_and_enter()`。
- 扫码加入流程：`scripts/pages/base/page_scan_join_flow_base.gd::_open_scan_join()`。
- 房间背景读取：`scripts/room/werewolf/werewolf_asset_catalog.gd`，页面通过 `scripts/pages/base/page_werewolf_asset_ui_base.gd::_room_background_path(room)` 访问。

### 修改偏好设置

- 设计文档：`docs/modules/preferences/README.md`。
- 目标页面：`scenes/preferences.tscn`、`scripts/pages/config/preferences_page.gd`。
- 目标核心：`scripts/core/preferences/`。

偏好设置只保存本机偏好：用户昵称、内置头像 ID、播放声音配置引用和设备私钥。应用启动时如果 JSON 不存在必须自动生成；昵称、头像和播放声音配置可修改，设备私钥自动生成、只读查看、不支持修改。新增偏好字段时，要同步 schema、默认值、页面展示、消费模块和无效数据丢弃策略；不要把模型配置详情、声音配置详情、机器人配置、房间 secret 或重连 token 明文放进偏好设置。

### 修改游戏桌

- 主桌面渲染：`scripts/room/werewolf/werewolf_room_page.gd::_show_table()`。
- 狼人杀页面共享状态、房间规则运行时、席位状态和页面钩子接口：`scripts/room/werewolf/werewolf_room_page_state.gd`。
- 桌面布局、中心面板、行动提示和发言输入：`scripts/room/werewolf/werewolf_room_table_page_flow.gd`。
- 房间生命周期、发布、退出、销毁、主机网络和玩家数据工厂：`scripts/room/werewolf/werewolf_room_lifecycle_page_flow.gd`。
- 顶部进度条和桌面 HUD：`scripts/room/werewolf/werewolf_room_progress_page_flow.gd`。
- 机器人加入弹层、机器人资料选择和本机机器人落座：`scripts/room/werewolf/werewolf_room_bot_page_flow.gd`。
- 二维码、历史面板和复盘入口：`scripts/room/werewolf/werewolf_room_overlay_page_flow.gd`。
- 座位点击、空座位气泡、准备和玩家交互桥接：`scripts/room/werewolf/werewolf_room_interaction_page_flow.gd`。
- 真人狼人杀目标确认、发言输入、改名、座位详情、头像旁白开关视图和真人玩家本地状态结果：`scripts/player/werewolf/human/`。
- 创建房间弹层、地图选择、人数选择和创建后入桌：`scripts/room/werewolf/werewolf_room_create_page_flow.gd`。

### 修改狼人杀房间模块

核心文件：`scripts/room/werewolf/werewolf_engine.gd`

常用入口：

- 玩法状态：`default_state()`。
- 地图规则配置目录：`map_rule_catalog()`。
- 地图规则配置数据：`_map_rule_data()`。
- 发牌开局：`start_game()`。
- 目标行动：`apply_target()`。
- 发言：`submit_speech()`。
- 跳过行动：`skip_current_action()`。
- 阶段展示：`phase_label()`。
- 胜负判断：规则引擎内部的胜负判断函数。

新增狼人杀地图或地图规则配置时同步更新：

1. `werewolf_engine.gd` 的地图和地图规则常量、`map_rule_catalog()` 和 `_map_rule_data()`。
2. 狼人杀房间模块暴露给房间模块和创建房间模块的 `GameRoomMap`、支持人数和 `GameRoomSceneSlots` 元数据。
3. `scripts/room/werewolf/werewolf_asset_catalog.gd` 的资源目录。
4. `assets/images/werewolf/backgrounds/` 下的地图背景图和 `.import` 文件。

创建房间 UI 不能手写狼人杀地图配置、背景、人数、场景或槽位列表，只能读取房间模块公开目录接口。

### 修改房间基础规则

房间模块是通用运行容器，不写具体玩法规则。修改时先判断变更属于房间机制、具体游戏房间模块，还是玩家行为适配。

- 可创建游戏房间模块、地图、支持人数、场景和槽位目录：由房间模块公开接口提供给创建房间模块，具体数据来自对应具体游戏房间模块。
- 参与者、席位、生命周期、准备门槛和基础房间校验：`scripts/room/room_runtime.gd`。
- 开局后能否换座、添加机器人、改名等房间策略：`can_change_seat()`、`can_add_bot()`、`can_rename()`。
- 玩家数据构造和房间内玩家绑定：`scripts/player/player_factory.gd`。房间级人数、准备、换座、加机器人和改名规则仍在 `scripts/room/room_runtime.gd`。
- 玩家交互请求、事件广播、玩家 inbox、可见历史下载、断线补发和清理策略：归 `docs/modules/room/README.md` 的房间机制维护。
- 玩家级可信通道、玩家临时数据、玩家投递游标和玩家恢复帧：归 `docs/modules/player/README.md` 的玩家模块维护；房间只传入座位、连接、认证摘要和在线状态。
- 真人副本、主机重选、主机接管和原玩家重连恢复：归 `scripts/room/network/` 与 `docs/modules/room/README.md` 维护。
- 游戏结束或所有真人参与者退出时，房间应清理临时历史、inbox、副本和重连材料；复盘数据由具体游戏房间模块显式生成。

房间层只保存机制数据和临时队列。事件 payload、下发语义、完整游戏恢复数据是否允许进入副本，由具体游戏房间模块和安全策略决定。

### 修改玩家模块

- 设计文档：`docs/modules/player/README.md`。
- 跨模块对象：`PlayerProfile`、`PlayerRuntimeBinding`、`PlayerTrustedChannel`、`PlayerTemporaryDataEnvelope`、`PlayerRecoveryFrame`、`PlayerActionRequest`、`PlayerActionResult`、`PlayerSpeechRequest`。
- 当前玩家资料和绑定构造：`scripts/player/player_factory.gd`。
- 玩家任务通道、pending 任务、控制设备、投递状态和自动推进阻塞状态：`scripts/player/player_task_channel.gd`。
- 展示 ACK 状态、presentation ID、本机 ACK 和文本等待时间：`scripts/player/player_presentation_ack_controller.gd`。
- 展示 ACK participant / peer 归一化和 debug 设备列表：`scripts/player/player_presentation_ack_participant_resolver.gd`。
- 展示 ACK 定时、客户端发送、host apply/drop 运行包装：`scripts/player/player_presentation_ack_runtime.gd`。
- 玩家到 TTS 的历史播报适配、队列查询和发言人静音键：`scripts/player/player_speech_output.gd`。
- 房间人数、准备、换座、加机器人和改名规则：`scripts/room/room_runtime.gd`。
- 代码目录：`scripts/player/`。

玩家模块是玩家侧公共运行层，不写具体游戏状态。修改时先判断变更属于通用玩家能力还是具体游戏玩家适配：

- 玩家展示名、头像、玩家类型、控制来源和控制器入口：归玩家模块。
- 玩家级可信通道、玩家任务通道、玩家临时数据、ack、补发、恢复帧和清理策略：归玩家模块。
- 玩家模块对外提供公共 TTS 文本转语音接口、已确认历史播报适配和发言人静音状态；具体音色 ID 由调用实现传入，不写进通用玩家资料。
- 座位权威、参与者权威、房间重连认证和房间快照：归房间模块。
- 狼人杀真人玩家请求、真人 UI 输入、本地状态结果和结果转换：归 `scripts/player/werewolf/human/`。
- 狼人杀真人玩家设备任务展示状态和 `player_action` / `player_speech` 结果 payload 包装：`scripts/player/werewolf/human/werewolf_human_player_task_controller.gd`。
- 狼人杀 AI 输入上下文、prompt/schema、模型输出解析和行动结果转换：归 `scripts/player/werewolf/ai/`。
- 狼人杀 AI 玩家回合推进、模型请求登记、模型回包提交、狼队私聊和记忆写入：`scripts/player/werewolf/ai/ai_werewolf_player_page_flow.gd`。
- 玩家通道字段或恢复字段变化时，同步跨模块契约、房间模块、具体游戏玩家适配层和 UI 展示。

### 修改网络同步

- WebSocket 会话：`scripts/room/network/room_network_session.gd`。
- 消息类型和信封：`scripts/network/room_network_codec.gd`。
- 加入码字段：`scripts/network/qr_join_payload.gd`。
- 局域网发现字段：`scripts/network/lan_room_discovery.gd`。
- 参与者和观察者策略：`scripts/room/network/room_participant_registry.gd`。
- 快照内容：`scripts/room/network/room_network_snapshot_builder.gd`。
- 房间副本和接管：`scripts/room/network/room_replica.gd`、`scripts/room/network/host_election.gd`。

网络字段变更时，需要同时考虑加入码、局域网发现、房间快照、重连会话和 Android 扫码返回的 payload。
扫码二维码的加密格式、协商流程和失败提示见 `docs/modules/base/qr_scan_join.md`；房间密码、加入 token、观战和容量策略见房间模块文档。

### 修改模型管理

- 模型请求：`scripts/core/model/model_chat_client.gd`。
- 模型列表：`scripts/core/model/model_catalog_client.gd`。
- 模型配置选择：`scripts/core/model/model_profile_selector.gd`。
- 页面层模型配置仓库和模型请求连接：`scripts/pages/base/page_model_ui_base.gd`。
- 模型配置页：`scripts/pages/config/model_config_page.gd`。
- 模型配置 JSON 保存：`scripts/core/config/config_repository.gd`。
- Android SQLite 模型配置桥接：`scripts/android/android_model_config_store.gd`。
- Android SQLite 表实现：`android_plugins/play_with_me_android/play-with-me-android/src/main/java/com/playwithme/godot/MemoryDatabase.kt`。

新增模型供应商或兼容方式时，优先改基础模型推理能力：在 adapter registry 中补充 provider、结构输出兼容、思考兼容、请求体、鉴权头和响应/事件解析，再同步模型配置页的供应商与兼容选项。业务模块只能通过 `complete_request()` 或 `complete_stream()` 调用模型，不直接拼供应商 HTTP 请求，也不绕过模型配置测试。

模型配置维护规则：

- `name` 就是模型名，也是配置列表、机器人绑定和数据库唯一性的一部分。
- 模型配置不再使用 `active` 字段；业务模块必须使用显式绑定的模型配置引用。狼人杀 AI 机器人在加入房间或重连初始化时，由控制设备本机从机器人档案读取 `model_profile_name`，再从本机模型数据库读取完整 `ModelProfile`。
- 界面 `MaxContext` 直接填写 token 数，不显示单位；数据库字段 `max_context` 使用同一 token 数；运行时字段 `context_window_tokens` 由 `max_context * 0.7` 派生。
- `max_output` 是最大输出 token，默认 `4096`；单个新增/编辑展示，批量新增不展示并使用默认值。
- 默认 `max_context` 为 `262144`，默认运行时上下文预算为 `183501`。
- Android 真机优先保存到 SQLite `model_configs` 表；桌面/编辑器保存在 `user://play_with_me_state.json` 的 `model_configs` 字段。

模型管理只提供模型配置、配置测试和输入输出能力，不写机器人记忆、狼人杀阶段策略或错误处理策略。模型调用失败时，基础能力返回结构化错误并打印脱敏后的 prompt、schema、请求参数和原始输出；是否中止业务流程由调用方决定，狼人杀 AI 机器人必须中止当前游戏流程。

### 修改机器人/RAG 记忆

- 通用记忆管理：`scripts/core/memory/memory_manager.gd`。
- 狼人杀记忆适配实现：`scripts/player/werewolf/ai/ai_werewolf_memory.gd`。
- 狼人杀输入状态到通用上下文的实现：`scripts/player/werewolf/ai/ai_werewolf_memory_context.gd`。
- 对局内记忆直接写入 session scope；对局结束只做本地收束，不调用模型压缩记忆。
- Android SQLite 桥接：`scripts/android/android_memory_store.gd`。
- Android SQLite 实现：`android_plugins/play_with_me_android/play-with-me-android/src/main/java/com/playwithme/godot/MemoryDatabase.kt`。

记忆结构变更时，需要保持桌面 JSON 和 Android SQLite 两条存储路径字段一致。`MemoryDatabase.kt` 同时维护记忆表和模型配置表，改 schema 时要同步确认 `SCHEMA_VERSION`、建表语句、索引和 Godot 桥接字段。
机器人/RAG 模块内部拆分为机器人模块、记忆模块和机器人上下文处理模块；对外只暴露机器人创建、机器人上下文构建、分层记忆提交和维护能力。它是通用机器人能力黑盒，不理解狼人杀字段，也不直接提交狼人杀行动。

### 修改狼人杀 AI 玩家

- 狼人杀 AI 玩家目标目录：`scripts/player/werewolf/ai/`。
- 当前 AI 玩家运行时门面：`scripts/player/werewolf/ai/ai_werewolf_player_runtime.gd`。
- AI 玩家 system/user prompt 与模型 payload：`scripts/player/werewolf/ai/ai_werewolf_prompt_renderer.gd`。
- AI 玩家文本和 JSON 输出解析：`scripts/player/werewolf/ai/ai_werewolf_output_parser.gd`。
- 狼人杀 AI 回合上下文、视角裁剪、目标合法性和记忆摘要上下文：`scripts/player/werewolf/ai/ai_werewolf_turn_context_builder.gd`。
- 狼人杀房间历史和狼队私有记录格式化：`scripts/player/werewolf/ai/ai_werewolf_record_formatter.gd`。
- 请求状态：`scripts/core/bot/bot_model_request_tracker.gd`。
- 狼人夜聊和目标票：`scripts/player/werewolf/ai/ai_werewolf_wolf_private_flow.gd`。
- 目标意图解析：`scripts/player/werewolf/ai/ai_werewolf_target_intent.gd`。
- 狼人杀 AI 玩家设计文档：`docs/modules/player/werewolf/ai/README.md`。

狼人杀真人玩家模块先把 `WerewolfActionRequest` 转成带 `instruction_type` 的通用 `PlayerActionRequest`，主机端再创建 `player_action` 或 `player_speech` 设备任务并路由到该玩家的控制设备。真人玩家根据指令类型打开对话框或行动交互 UI，人的输入转成 `PlayerActionResult` 后，经玩家模块可信通道和临时数据队列回到主机端房间程序；断联恢复后玩家模块重新投递玩家数据。狼人杀 AI 玩家只在控制设备本机执行：读取 `BotProfile`，取得 `model_profile_name` 和 `voice_profile_id`，再从本机模型数据库读取完整 `ModelProfile`，随后读取狼人杀房间模块提供的当前玩家输入数据，构建 `scene`、`seats`、`records`、`player_information`、`memory`、`current_question`，并把结构化记录压缩成 `records` 字符串队列；之后调用基础模型推理能力生成 `PlayerActionResult`。具体游戏玩家模块把玩家行为结果转成 `WerewolfPlayerActionResult` 后，最终必须交给狼人杀房间模块校验；只有狼人杀房间模块接受后的事件、发言、行动和结果才会被适配成通用 `memory_update`，再提交给机器人模块。特效请求、阶段推进和下一步行动请求由狼人杀房间模块按地图 ID、人数和内部编排决定。

### 修改 TTS

- 播报文本清洗：`scripts/core/tts/tts_text_sanitizer.gd`。
- 历史消息到播报项：`scripts/core/tts/tts_history_controller.gd`。
- 声音配置 Schema/仓库/音色目录：`scripts/core/tts/voice_profile_schema.gd`、`scripts/core/tts/voice_profile_repository.gd`、`scripts/core/tts/voice_catalog.gd`。
- 播放队列和状态：`scripts/core/tts/tts_runtime.gd`。
- 页面层声音配置仓库、TTS 运行时和试听：`scripts/pages/base/page_tts_ui_base.gd`。
- 页面层历史消息播报和席位播报动效：`scripts/pages/base/page_tts_history_ui_base.gd`。
- Android Godot 桥接：`scripts/core/tts/adapters/android_tts_bridge.gd`。
- Android Kotlin 插件：`android_plugins/play_with_me_android/play-with-me-android/src/main/java/com/playwithme/godot/PlayWithMeAndroid.kt`。
- Kokoro native：`android_plugins/play_with_me_android/play-with-me-android/src/main/cpp/kokoro_jni.cpp`。
- 声音配置说明：`docs/modules/tts-voice/voice_config.md`。

新增声音引擎时，需要覆盖可用性判断、音色列表、播放、停止、开始/进度/完成/失败回调、配置页展示和 `voice_configs` 字段校验。

### 修改 Android 插件

Android 插件源码位于 `android_plugins/play_with_me_android/`。Godot 导出使用的 AAR 位于：

- `addons/play_with_me_android/bin/debug/play-with-me-android-debug.aar`
- `addons/play_with_me_android/bin/release/play-with-me-android-release.aar`

构建和同步 AAR 使用：

```powershell
.\tools\build_android_plugin.ps1
.\tools\sync_android_plugin_aar.ps1
```

新增 singleton 方法时，需要同步修改：

1. Kotlin 插件方法和信号。
2. `scripts/android/` 下对应 Godot 桥接。
3. `addons/play_with_me_android/export_plugin.gd` 中的导出依赖。
4. 需要使用该能力的页面或运行时。

当前模型配置 singleton 方法为 `model_config_available`、`model_config_list`、`model_config_save`、`model_config_delete`，对应 Godot 桥接为 `scripts/android/android_model_config_store.gd`。

Android 插件会在 Godot 主循环启动后主动打开一次 `ai_memory.sqlite`，用于提前创建记忆表和模型配置表；不要把表创建依赖放到首次保存按钮上。

## 资源维护

### 背景图

背景图路径：

- `assets/images/werewolf/backgrounds/lobby.png`
- `assets/images/werewolf/backgrounds/day.png`
- `assets/images/werewolf/backgrounds/night.png`
- `assets/images/werewolf/backgrounds/map_*.png`

地图背景绑定位置：

- `scripts/room/werewolf/werewolf_asset_catalog.gd` 的狼人杀资源目录
- `scripts/room/werewolf/werewolf_map_catalog.gd` 的地图背景字段

### 头像和行动图标

- 角色头像：`assets/images/werewolf/avatars/`
- 行动图标：`assets/images/werewolf/actions/`
- 通用 UI 位图：`assets/images/werewolf/ui/`

替换资源后，用 Godot 重新导入资源；业务资源和对应 `.import` 文件需要保留。

## 状态结构

- `AppState.STATE_VERSION` 用于标识当前本地状态结构。
- 修改 `rooms`、`players`、`werewolf`、配置字段时，只读取当前结构；不符合当前结构的数据直接丢弃并重建。
- 修改玩家通道、临时数据或恢复字段时，需要同步当前 JSON 写入、房间快照、重连恢复、玩家模块契约和具体游戏玩家适配层。
- 修改模型配置字段时，需要同时确认当前 JSON 写入、Android SQLite 空表初始化和 `model_configs(provider, endpoint, model)` 唯一索引。
- 设备身份和重连会话影响联机恢复，不要随意改字段名。
- 游戏实现 ID 和地图 ID 会出现在房间、背景图、加入码、局域网发现和快照里，改名会影响当前房间识别。

## 代码风格

- 优先沿用现有 GDScript 字典结构和页面 helper。
- 新增功能要先放入对应领域目录，避免继续扩大无关脚本职责。
- UI 文字保持短句，移动端横屏优先，长文本默认单行截断。
- 网络 payload 使用明确字段名，并同步当前 join、snapshot 和 reconnect 流程。
- Android 桥接方法要返回结构化结果，失败时提供可展示的错误信息。

