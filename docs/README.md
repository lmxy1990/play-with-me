# Play With Me 文档索引

本目录记录 Play With Me 的架构、模块、功能、维护方式和构建部署方式。当前文档主线分两层：工程目录结构用于说明文件系统归属，程序模块结构用于说明业务逻辑解耦边界。

工程顶层目录保持现有 Godot 项目结构；承载业务内容的目录内部按模块归属组织文件，例如 `scripts/`、`scenes/`、`assets/` 和 `test/` 内部优先按模块建子目录。

## 推荐阅读顺序

1. [根 README](../README.md)：项目定位、技术栈、目录和常用命令。
2. [工程目录结构](project-structure/README.md)：Godot、Android、构建、测试、资源和生成物目录。
3. [整体架构](architecture.md)：系统分层、技术栈、模块边界和运行时结构。
4. [程序模块结构](modules/README.md)：按模块进入架构设计和逻辑流程。
5. [跨模块契约](contracts/README.md)：模块之间的数据对象、可见性、调用结果和变更规则。
6. [构建部署](build_deployment.md)：Android 插件构建、APK 导出和设备安装。
7. [维护指南](maintenance.md)：常见改动位置和维护约定。

## 模块文档

模块文档按“一个模块一个文件夹”组织。每个模块目录只描述自己的能力边界、外部接口、内部文件归属、架构设计和逻辑流程；具体游戏房间模块和玩家适配作为房间模块的子目录维护。

基础能力：

- [基础能力](modules/base/README.md)：应用路由、共享状态、通用网络、二维码生成、扫码、加密、认证、设备身份、Android 桥接和持久化基础。

基础模块：

- [偏好设置模块](modules/preferences/README.md)：本机偏好黑盒，负责偏好 JSON、昵称、头像、播放声音配置引用和设备私钥只读能力。
- [玩家模块](modules/player/README.md)：通用玩家运行黑盒，负责玩家基础资料、运行时绑定、玩家级可信通道、玩家临时数据、断联恢复、玩家控制器入口和公共 TTS 文本转语音接口。
- [模型管理模块](modules/model-management/README.md)：模型配置和基础推理能力黑盒，负责模型配置、供应商列表、配置测试、结构兼容、思考兼容和一次模型调用。
- [机器人/RAG 模块](modules/bot-management/README.md)：通用机器人能力黑盒；内部拆分记忆模块和机器人上下文处理模块，对外提供机器人创建、上下文构建和分层记忆更新能力。
- [TTS 语音模块](modules/tts-voice/README.md)：语音输出黑盒，负责声音配置、文本转语音、播放队列和播放事件。

小编织模块：

- [大厅模块](modules/lobby/README.md)：入口编排黑盒，聚合房间摘要、发现、重连和配置入口。
- [创建房间模块](modules/create-room/README.md)：统一创建 UI 编排，读取可创建游戏房间模块、地图、支持人数和场景槽位，并提交房间创建请求。
- [玩家模块](modules/player/README.md)：由父级玩家模块、真人玩家模块、AI 玩家模块、狼人杀真人玩家模块、狼人杀 AI 玩家模块共同组成；统一玩家资料、通道、请求投递、真人输入和 AI 玩家响应。

大编织模块：

- [房间模块](modules/room/README.md)：通用房间运行容器，负责参与者、席位、玩家交互、事件广播、玩家 inbox、可见历史下载、重连、真人副本、主机重选、主机接管和具体游戏房间模块接入点。
- [狼人杀房间模块](modules/room/werewolf/README.md)：当前具体游戏房间实现，负责狼人杀地图、支持人数、场景槽位、内部编排、状态机、行动校验、特效请求、阶段推进、事件 payload、可见性语义、胜负和复盘。
- [象棋房间模块](modules/room/xiangqi/README.md)：新增具体游戏房间设计，负责象棋两方座位、竖版棋盘布局、权威局面、走法校验、回合推进、胜负与和棋、AI 聊天触发和复盘。
- [三国杀房间模块](modules/room/sanguosha/README.md)：后续具体游戏房间设计，负责 2 人对决、4-8 人身份局、规则包、武将包、牌堆和手牌权威状态、响应窗口、伤害濒死结算、胜负与复盘。

## 专题文档

专题文档用于深入描述单一能力。模块文档是主入口，专题文档放在所属模块目录内。

- [二维码、扫码、加密与认证](modules/base/qr_scan_join.md)：二维码格式、扫码交互、加密协商、认证基础、入房前检查、失败提示和代码视图。
- [声音配置](modules/tts-voice/voice_config.md)：声音配置表字段、页面行为、TTS 引擎、音色和播放进度规则。
- [跨模块契约](contracts/README.md)：`RoomSummary`、`RoomSnapshot`、`WerewolfActionRequest`、`BotVisibleContext`、`memory_update`、模型和 TTS 等跨模块对象。
- [功能清单](program_features.md)：面向使用者的软件功能清单和交互入口。
- [Android 记忆系统设计](modules/bot-management/android_agent_memory_system_design_complete.md)：AI 记忆和 Android SQLite 专题。

## 历史文档

- [详细设计](archive/detailed_design.md)：历史详细设计，保留核心数据结构和页面流程说明。
- [软件架构归档](archive/software_architecture.md)：归档架构说明，后续内容应优先同步到 `architecture.md` 和 `modules/`。

## 主入口文件

- Godot 项目配置：`project.godot`
- 应用主场景：`scenes/main.tscn`
- 页面路由：`scripts/core/app_router.gd`
- 共享状态：`scripts/core/app_state.gd`
- 页面共享基类链：`scripts/pages/base/page_werewolf_asset_ui_base.gd`、`scripts/pages/base/page_scan_join_flow_base.gd`、`scripts/pages/base/page_book_ui_base.gd`、`scripts/pages/base/page_route_ui_base.gd`、`scripts/pages/base/page_audio_ui_base.gd`、`scripts/pages/base/page_tts_ui_base.gd`、`scripts/pages/base/page_model_ui_base.gd`、`scripts/pages/base/page_room_discovery_ui_base.gd`、`scripts/pages/base/page_identity_ui_base.gd`、`scripts/pages/base/page_room_network_ui_base.gd`、`scripts/pages/base/page_room_participant_ui_base.gd`、`scripts/pages/base/page_room_replica_ui_base.gd`、`scripts/pages/base/page_room_join_ui_base.gd`、`scripts/pages/base/page_room_host_peer_ui_base.gd`、`scripts/pages/base/page_tts_history_ui_base.gd`、`scripts/pages/base/page_bot_profile_ui_base.gd`、`scripts/room/werewolf/werewolf_room_page_state.gd`、`scripts/player/werewolf/ai/ai_werewolf_player_page_flow.gd`、`scripts/pages/base/page_navigation_ui_base.gd`

## 文档维护规则

- 新增模块或跨模块能力时，先更新 `architecture.md` 的模块介绍，再增加或更新 `modules/<module>/README.md`。
- 修改某个模块时，同步更新该模块文档的文件夹、架构设计和逻辑流程。
- 修改跨模块数据对象、可见性、错误码或生命周期时，同步更新 [跨模块契约](contracts/README.md)。
- 新增脚本、场景、资源或测试时，外层工程目录保持现有结构，目录内部按模块归属落位。
- 专题文档可以保留更细的协议、字段和调试细节，但应放在所属模块目录内，不要替代模块文档入口。
- 根目录 `README.md` 只保留项目入口、技术栈、目录和常用命令，不放过长设计细节。

