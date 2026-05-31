# 整体架构

更新时间：2026-05-21

本文是项目的主架构文档。工程物理目录见 [工程目录结构](project-structure/README.md)，业务逻辑边界见 [程序模块结构](modules/README.md)，模块之间的数据对象和下发范围规则见 [跨模块契约](contracts/README.md)，模块内部的架构设计和逻辑流程见 `docs/modules/<module>/README.md`。

## 系统定位

Play With Me 是一个 Godot 4.6 Mobile 横屏桌游应用。当前核心玩法是狼人杀，运行时由 Godot 页面、共享状态、偏好设置、房间、玩家、狼人杀房间模块、机器人/RAG、模型服务、TTS、Android 原生插件和本地持久化组成。

总体数据流：

```text
RoomSession
  -> 参与者、席位、生命周期、网络和临时存储
  -> 委派具体游戏房间模块
       -> WerewolfRoom / XiangqiRoom / 后续三国杀房间、围棋房间、麻将房间
       -> 提供地图 / 支持人数 / 场景槽位
       -> 根据地图 ID 和人数选择内部编排
       -> 生成 GameActionRequest
       -> 接收 GameActionResult
       -> 输出 GameEvent / EffectRequest / GameSnapshot / GameOver

PlayerModule
  -> PlayerProfile / PlayerRuntimeBinding
  -> PlayerTrustedChannel / PlayerTemporaryDataEnvelope / PlayerRecoveryFrame
  -> 玩家级投递、ack、补发和断联恢复
  -> 公共 TTS 文本转语音接口，调用方传入音色 ID
  -> 真人玩家模块 / AI 玩家模块

PlayerController
  -> 真人玩家 / 远程真人玩家 / AI 玩家 / 托管玩家
  -> 真人按指令类型打开对话框或行动交互 UI
  -> 经玩家模块可信通道回传输入
  -> AI 玩家从机器人档案读取模型配置引用和声音配置引用
  -> 经对应具体游戏真人/AI 玩家模块生成 GameActionResult
  -> 交回具体游戏房间模块校验和推进
```

`project.godot` 的主场景是 `scenes/main.tscn`。主场景挂载 `scripts/core/app_router.gd`，路由器创建并持有共享 `AppState` 和 `RoomNetworkSession`。页面切换时，状态和网络会话不会重建。

抽象层次约定：

- 房间模块是通用运行容器，负责收集参与者和玩家数据、维护房间生命周期、发送玩家交互请求、按下发范围广播事件、保存临时历史，并支持主机重选和主机接管。
- 具体游戏房间模块是房间委派的玩法和布局实现，负责按地图 ID 和人数选择内部编排，并决定行动接受后的特效请求、阶段推进和下一步行动请求。狼人杀房间是当前实现，象棋房间按同一容器新增；后续三国杀房间、围棋房间和麻将房间应接入同一房间容器。
- 玩家模块是玩家侧公共运行层，由父级玩家模块、真人玩家模块、AI 玩家模块、狼人杀真人玩家模块、狼人杀 AI 玩家模块共同组成；它负责通用玩家资料、运行时绑定、玩家级可信通道、玩家任务通道、玩家临时数据、断联恢复、展示 ACK 状态、行为控制器入口和公共 TTS 文本转语音接口。真人玩家模块处理人类输入投递和结果回收，AI 玩家模块处理 AI 控制器入口和通用结果包装；调用玩家模块播报时，由调用实现传入本次使用的音色 ID。
- 具体游戏玩家实现负责把通用玩家行为和具体游戏房间对象互相转换，例如狼人杀真人玩家模块和狼人杀 AI 玩家模块。新增具体游戏时，主要新增对应游戏房间模块、真人玩家实现模块和 AI 玩家实现模块，其它能力通过公共模块接口复用。

## 技术栈

| 层级 | 技术 | 用途 |
| --- | --- | --- |
| 客户端 | Godot 4.6 Mobile / GDScript | 页面、玩法、网络、AI 调用和运行时逻辑 |
| Android 原生 | Kotlin / Godot Android Plugin | 相机扫码、TTS、SQLite、设备能力 |
| 扫码 | CameraX / ML Kit Barcode Scanning | Android 连续帧二维码识别 |
| 局域网发现 | UDP PacketPeerUDP | 大厅发现房间 |
| 房间通信 | WebSocketPeer | Host 权威状态同步、加入、重连和观战 |
| 数据格式 | JSON | 网络信封、配置、二维码 payload |
| 二维码 | Godot 自研 QR 生成器 | 房主端生成加入码和观战码 |
| 安全协商 | RSA 包装 AES 密钥，AES-256-CBC + SHA256 MAC | 二维码加密区解密 |
| 本地存储 | `user://` JSON / Android SQLite | 状态、偏好 JSON、配置、记忆、声音和模型配置 |
| 模型服务 | OpenAI API 格式 / Ollama / Anthropic / Gemini | 模型输入输出和模型测试 |
| TTS | DisplayServer TTS / Android TTS / Kokoro-Sherpa | 历史消息播报 |
| 构建 | Gradle / Godot Android export | AAR、APK 和设备安装 |

## 运行时分层

```text
scenes/
  main.tscn
  lobby.tscn
  preferences.tscn  目标场景
  werewolf_room.tscn
  model_config.tscn
  voice_config.tscn
  bot_config.tscn
  replay.tscn

scripts/core/
  app_router.gd       路由和页面注入
  app_state.gd        全局状态
  config/             配置仓库
  model/              模型接口和配置选择
  bot/                通用机器人档案和上下文能力
  memory/             AI 记忆
  tts/                TTS 运行时

scripts/network/
  局域网发现、消息编解码和二维码 payload

scripts/pages/
  大厅、配置页、复盘数据渲染入口
  base/page_werewolf_asset_ui_base.gd  页面层狼人杀资源访问
  base/page_scan_join_flow_base.gd     扫码加入流程状态和 Android 扫码信号
  base/page_book_ui_base.gd            书页弹层、toast 和 QR 图片 helper
  base/page_route_ui_base.gd           页面路由信号和跳转 helper
  base/page_audio_ui_base.gd           点击音效
  base/page_tts_ui_base.gd             声音配置仓库、TTS 运行时和声音试听 helper
  base/page_model_ui_base.gd           模型配置仓库、模型调用和模型目录请求 helper
  base/page_room_discovery_ui_base.gd  局域网房间发现和房间列表 helper
  base/page_identity_ui_base.gd        本机偏好身份、设备身份和网络身份注入 helper
  base/page_room_network_ui_base.gd    房间网络会话创建、信号绑定和网络角色 helper
  base/page_room_participant_ui_base.gd 参与者认证、观察者和重连令牌 helper
  base/page_room_replica_ui_base.gd    房间快照、副本和主机接管 helper
  base/page_room_join_ui_base.gd       二维码入房、重连和房主加入处理 helper
  base/page_room_host_peer_ui_base.gd  房主 peer 准备、换座、旁观、加机器人和离线处理 helper
  base/page_tts_history_ui_base.gd     历史消息播报、播放声音偏好和席位播报动效 helper
  base/page_bot_profile_ui_base.gd     机器人资料仓库、机器人门面和通用记忆管理器页面接入
  base/page_navigation_ui_base.gd      页面共享状态绑定和跨页面流程装配

scripts/room/
  房间通用运行时

scripts/player/
  玩家模块：父级玩家、真人玩家、AI 玩家、狼人杀真人玩家、狼人杀 AI 玩家

scripts/room/network/
  WebSocket 会话、快照、重连副本、参与者注册和房主接管

scripts/room/werewolf/
  狼人杀房间模块、资源目录、页面状态、页面、座位、桌面、效果和私聊

scripts/room/xiangqi/
  象棋房间模块、棋盘、规则校验、页面状态、页面、座位、聊天和复盘

scripts/android/
  Godot 到 Android 插件的桥接

scripts/ui/
  通用 UI 基类、通用弹层、二维码生成、扫码处理 UI
```

## 模块介绍

| 层级 | 模块 | 文档 | 主要代码 |
| --- | --- | --- | --- |
| 基础能力 | 基础能力 | [base/README.md](modules/base/README.md) | `scripts/core/app_router.gd`、`scripts/core/app_state.gd`、`scripts/core/device_identity.gd`、`scripts/network/room_network_codec.gd`、`scripts/network/qr_join_payload.gd`、`scripts/android/`、`scripts/ui/base/`、`scripts/ui/common/`、`scripts/ui/qr/qr_code_generator.gd`、`scripts/ui/qr/qr_scan_join_ui.gd` |
| 基础模块 | 偏好设置模块 | [preferences/README.md](modules/preferences/README.md) | 本机偏好黑盒；目标归属：`scenes/preferences.tscn`、`scripts/pages/config/preferences_page.gd`、`scripts/core/preferences/` |
| 基础模块 | 玩家模块 | [player/README.md](modules/player/README.md) | 通用玩家运行黑盒；由父级玩家模块、真人玩家模块、AI 玩家模块、狼人杀真人玩家模块、狼人杀 AI 玩家模块组成；当前代码归属为 `scripts/player/`，房间级人数和准备规则仍在 `scripts/room/room_runtime.gd` |
| 基础模块 | 模型管理模块 | [model-management/README.md](modules/model-management/README.md) | 模型 I/O 黑盒；`scripts/pages/config/model_config_page.gd`、`scripts/core/model/`、`scripts/android/android_model_config_store.gd` |
| 基础模块 | 机器人/RAG 模块 | [bot-management/README.md](modules/bot-management/README.md) | 通用机器人能力黑盒；机器人模块门面 + 记忆模块 + 机器人上下文处理模块；当前代码在 `scripts/core/bot/`、`scripts/core/memory/`、`scripts/pages/config/bot_config_page.gd`、`scripts/android/android_memory_store.gd`、`scripts/player/werewolf/ai/ai_werewolf_memory*.gd` |
| 基础模块 | TTS 语音模块 | [tts-voice/README.md](modules/tts-voice/README.md) | 语音输出黑盒；`scripts/pages/config/voice_config_page.gd`、`scripts/core/tts/`、`scripts/core/tts/adapters/android_tts_bridge.gd` |
| 小编织模块 | 大厅模块 | [lobby/README.md](modules/lobby/README.md) | 入口编排黑盒；`scenes/lobby.tscn`、`scripts/pages/lobby_page.gd` |
| 小编织模块 | 创建房间模块 | [create-room/README.md](modules/create-room/README.md) | 统一创建 UI 编排；读取可创建游戏房间模块、地图、支持人数和场景槽位，提交 `RoomCreateRequest`；当前入口在 `scripts/pages/lobby_page.gd` |
| 大编织模块 | 房间模块 | [room/README.md](modules/room/README.md) | 通用房间运行容器；维护参与者、席位、玩家交互、事件广播、玩家 inbox、可见历史下载、重连、真人副本、主机重选、主机接管和具体游戏房间模块接入点；`scenes/werewolf_room.tscn`、`scripts/room/`、`scripts/room/network/room_network_session.gd`、`scripts/room/network/host_election.gd` |
| 大编织模块 | 狼人杀房间模块 | [room/werewolf/README.md](modules/room/werewolf/README.md) | 当前具体游戏房间实现；按地图 ID 和人数选择内部编排并输出特效请求、阶段推进和下一步行动请求；`scripts/room/werewolf/werewolf_engine.gd`、`scripts/room/werewolf/werewolf_asset_catalog.gd`、`scripts/room/werewolf/` |
| 大编织模块 | 象棋房间模块 | [room/xiangqi/README.md](modules/room/xiangqi/README.md) | 新增具体游戏房间设计；维护 2 人座位、竖版棋盘、权威局面、走法校验、回合推进、胜负与和棋、AI 聊天触发和复盘；目标归属 `scripts/room/xiangqi/` |

## 工程结构和模块结构

工程结构是外层文件系统归属，例如 Godot 场景、GDScript、Android 原生插件、构建脚本、测试和生成物。模块结构是程序设计层的逻辑边界，按基础能力、基础模块、小编织模块和大编织模块组织。

两层结构不要求一一对应。当前模块脚本已经按目录归档了一部分，页面共享基类已经拆出狼人杀资源访问、扫码加入流程、书页弹层 helper、路由 helper、点击音效、声音配置仓库、TTS 运行时、声音试听、模型配置仓库、模型调用、模型目录请求、局域网房间发现、本机身份接入、设备身份注入、房间网络会话外壳、参与者注册包装、房间快照应用、房间副本接收、主机接管编排、二维码入房、房主加入处理、房主 peer 动作编排、历史消息播报、席位播报动效、机器人资料/记忆接入、狼人杀房间页面状态和狼人杀 AI 玩家页面流；`scripts/pages/base/page_navigation_ui_base.gd` 仍承担共享服务装配和部分跨页面流程。继续拆分时，文档按模块归档，代码向对应工程目录收敛。

## 模块归档规则

新代码优先落到对应模块的目录或已有模块文件里，文档则落到对应 `docs/modules/<module>/README.md`。不要把多个模块的内容堆到一个无边界目录里。

模块代码遵循“公开接口 + 模块内实现”的铁律：

- 模块必须有自己的代码文件归属；实现文件放在模块内部，不散落到无关模块。
- 模块对外提供明确接口能力，跨模块调用只引用这些公开接口和跨模块契约对象。
- 模块内部实现文件默认不允许被其他模块直接引用、实例化或复制。
- 编织模块只能组合模块接口，不能把被组合模块的内部实现搬进自己目录。

工程顶层目录不按业务模块重拆，仍保持 Godot 工程目录语义；但 `scripts/`、`scenes/`、`assets/`、`test/` 等目录内部应按模块归属组织。也就是说，模块边界指导目录内部落位，而不是替代工程顶层目录。

- 基础通用能力放 `scripts/core/`、`scripts/android/`、`scripts/ui/` 和通用网络 helper；二维码生成、扫码、加密和认证基础也归基础能力维护。
- 页面业务放 `scripts/pages/`。
- 偏好设置目标归属为 `scripts/core/preferences/` 和 `scripts/pages/config/preferences_page.gd`。
- 房间通用逻辑放 `scripts/room/`。
- 房间会话、快照、重连和主机选举放 `scripts/room/network/`，设计归属按房间模块维护；二维码 payload、加密协商和认证基础在 `scripts/network/`、`scripts/ui/` 和 `scripts/android/` 等路径协作实现，设计归属按基础能力维护。
- 玩家通用逻辑放 `scripts/player/`，包括玩家资料、玩家工厂、真人玩家控制器、AI 玩家控制器和具体游戏玩家实现。`scripts/room/room_runtime.gd` 仍归房间模块，负责人数、准备、换座、加机器人和改名等房间级规则。
- 狼人杀房间模块专属逻辑放 `scripts/room/werewolf/`。
- 象棋房间模块专属逻辑放 `scripts/room/xiangqi/`。
- 狼人杀真人玩家实现归 `scripts/player/werewolf/human/`，狼人杀 AI 玩家实现归 `scripts/player/werewolf/ai/`。
- 象棋真人玩家实现归 `scripts/player/xiangqi/human/`，象棋 AI 玩家实现归 `scripts/player/xiangqi/ai/`。
- Android 原生能力放 `android_plugins/play_with_me_android/`，Godot 桥接放 `scripts/android/`。
- 测试、demo 资产和调试脚本放 `test/`。

不要把某个模块的业务规则散落到无关模块。确实需要跨模块调用时，应通过该模块公开的运行时服务、状态对象、网络会话、桥接对象或契约接口传递，不直接复制逻辑，也不绕过接口访问内部实现。

## 状态和权威端

`AppState` 是本机运行时状态源；房间联机时，当前房主是 `RoomSession` 的权威承载端。客户端提交房间请求，房主执行房间级校验，再交给当前具体游戏房间模块校验和更新游戏状态，最后按下发范围分发事件和快照。观察者只接收安全视角数据，不提交会改变房间状态的消息。

具体游戏房间模块是当前游戏执行层的权威。真人玩家和 AI 玩家都只提交行动结果，不能直接修改游戏状态。真人玩家收到带指令类型的请求后，只打开对应 UI、收集人的输入，并经玩家模块可信通道回到主机端房间程序。AI 玩家需要行动时，由控制它的设备读取 `BotProfile` 中的模型配置引用和声音配置引用，再从本机模型数据库读取完整 `ModelProfile`，随后读取游戏房间模块提供的当前玩家输入数据，构建 `scene`、`seats`、`records`、`player_information`、`memory`、`current_question`，之后调用基础模型推理能力生成行动结果。主机端只路由玩家任务，不读取、不广播、不调用 AI 模型配置。只有行动、发言或阶段结果被具体游戏房间模块接受后，特效请求、阶段推进、下一步行动请求和记忆更新才可以继续发生。

Android 真机优先使用 SQLite 保存模型、声音和运行时记忆；机器人档案随 `AppState.bot_profiles` 保存，桌面/编辑器使用 `user://` JSON 路径。

## 深入文档

- 工程目录结构：[project-structure/README.md](project-structure/README.md)
- 程序模块结构：[modules/README.md](modules/README.md)
- 跨模块契约：[contracts/README.md](contracts/README.md)
- 二维码、扫码、加密协商和认证失败提示：[modules/base/qr_scan_join.md](modules/base/qr_scan_join.md)
- TTS 引擎和声音配置：[modules/tts-voice/voice_config.md](modules/tts-voice/voice_config.md)
- 构建部署：[build_deployment.md](build_deployment.md)
- 维护规则：[maintenance.md](maintenance.md)

