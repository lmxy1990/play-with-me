# 程序模块结构

更新时间：2026-05-21

本文描述 Play With Me 的程序设计模块，也就是逻辑解耦边界。工程物理目录见 [工程目录结构](../project-structure/README.md)。

## 设计主线

模块结构回答“这个能力属于谁、对外暴露什么、内部流程怎么走”。工程目录回答“文件放在哪里”。两者不要求一一对应。

工程顶层目录保持现有 Godot 项目结构，但目录内部要按模块归属组织文件。也就是说，不为每个业务模块新建顶层目录；而是在 `scripts/`、`scenes/`、`assets/`、`test/` 等目录内部按模块建子目录。具体约定见 [工程目录结构的目录内模块化约定](../project-structure/README.md)。

当前目标结构按下面的方向收敛：

```text
基础能力
  -> 路由 / 共享状态 / 通用网络 / 二维码 / 扫码 / 加密 / 认证 / Android 桥接 / 持久化
  -> 被大厅 / 创建房间 / 偏好设置 / 房间消费

大厅模块
  -> 编排房间摘要、发现房间、重连卡片、扫码入口、偏好入口和配置入口

房间模块
  -> 通用 RoomSession 运行容器
  -> 参与者 / 席位 / 生命周期 / 加入策略 / 快照同步 / 玩家 inbox / 可见历史 / 真人副本 / 重连 / 主机重选 / 主机接管
  -> 委派具体游戏房间模块
       -> 狼人杀房间模块
       -> 象棋房间模块
       -> 后续三国杀房间 / 围棋房间 / 麻将房间

玩家模块
  -> 通用玩家资料 / 运行时绑定 / 玩家级可信通道
  -> 玩家临时数据 / 玩家任务通道 / 投递游标 / 生命周期 / 断联恢复
  -> 通用 PlayerController 行为抽象
  -> 公共 TTS 文本转语音接口，调用方传入音色 ID
  -> 真人玩家模块
       -> 狼人杀真人玩家模块
       -> 象棋真人玩家模块
  -> AI 玩家模块
       -> 狼人杀 AI 玩家模块
       -> 象棋 AI 玩家模块
  -> 真人、远程真人、AI 和托管玩家统一返回 PlayerActionResult

狼人杀真人玩家模块
  -> 把 WerewolfActionRequest 转成真人 UI 输入
  -> 把真人操作转成 PlayerActionResult / WerewolfPlayerActionResult

狼人杀 AI 玩家模块
  -> 从机器人档案读取 model_profile_name / voice_profile_id
  -> 控制设备从本机模型数据库读取完整 ModelProfile
  -> 构建狼人杀输入上下文、prompt、schema 和 memory_update
  -> 组合机器人/RAG 模块和模型管理模块
  -> 解析模型输出为 PlayerActionResult / WerewolfPlayerActionResult

象棋真人玩家模块
  -> 把 XiangqiActionRequest 转成棋子选择、目标格选择、求和、悔棋、认输和聊天输入
  -> 把真人操作转成 PlayerActionResult / XiangqiPlayerActionResult

象棋 AI 玩家模块
  -> 从机器人档案读取 model_profile_name / voice_profile_id
  -> 控制设备从本机模型数据库读取完整 ModelProfile
  -> 分离构建象棋行棋上下文和聊天上下文
  -> 解析模型输出为 PlayerActionResult / XiangqiPlayerActionResult 或聊天文本

玩家发言
  -> TTS 语音模块：文本转语音
```

核心原则是：通用房间模块负责承载参与者、席位、同步数据、历史、重连、副本、主机重选和主机接管；具体游戏房间模块负责地图、人数、场景槽位、内部编排、玩法状态、事件 payload、特效请求和下发语义；玩家模块负责玩家基础资料、运行时绑定、玩家级可信通道、玩家临时数据、断联恢复、行为控制器入口和公共 TTS 文本转语音接口。新增具体游戏时，新增对应游戏房间模块、真人玩家模块和 AI 玩家模块，复用父级玩家、真人玩家和 AI 玩家通用能力。

## 模块代码铁律

模块代码必须以“公开接口 + 模块内实现”的方式组织，这是项目长期可维护的硬边界。

- 每个模块都要有独立的代码归属目录或清晰的目标目录，模块实现文件必须放在该模块内部。
- 模块对外只暴露接口能力，例如 facade、service、runtime、repository、adapter 或明确写入契约文档的数据对象。
- 其他模块编织能力时，只能引用被调用模块暴露出来的公开接口，不能直接引用、实例化或复制对方模块内部实现文件。
- 模块内部可以继续拆分实现文件，例如状态机、校验器、构建器、解析器、存储器和适配器；这些实现文件默认是 internal，不作为跨模块调用入口。
- 需要新增跨模块能力时，先设计公开接口和数据契约，再把实现落回模块内部；不要为了调用方便把实现搬到 `core`、`ui`、`common` 或编织层。
- 编织模块只负责组合接口和传递契约对象，不拥有被组合模块的内部算法、字段拼装和持久化细节。

## 模块列表

模块列表按职责层级排序：基础能力 -> 基础模块 -> 小编织模块 -> 大编织模块。

分类口径：

- 基础能力：跨模块复用的底座能力，不表达具体业务。
- 基础模块：提供单一领域能力，对外暴露清晰接口，不主动编排复杂业务流程。
- 小编织模块：围绕一个较小业务入口或适配流程，组合少量基础能力和基础模块。
- 大编织模块：承载核心运行时或完整业务执行层，编排多个模块并维护较大的业务状态。

### 基础能力

| 模块 | 文档 | 职责摘要 |
| --- | --- | --- |
| 基础能力 | [base](base/README.md) | 应用路由、共享状态、通用网络、二维码生成、扫码、加密、认证、设备身份、Android 桥接和持久化基础。 |

### 基础模块

| 模块 | 文档 | 职责摘要 |
| --- | --- | --- |
| 偏好设置模块 | [preferences](preferences/README.md) | 本机偏好黑盒；启动时确保偏好 JSON 存在，对外提供昵称、头像、播放声音配置引用和设备私钥只读读取能力。 |
| 玩家模块 | [player](player/README.md) | 通用玩家运行黑盒；由父级玩家模块、[真人玩家模块](player/human/README.md)、[AI 玩家模块](player/ai/README.md)、[狼人杀真人玩家模块](player/werewolf/human/README.md)、[狼人杀 AI 玩家模块](player/werewolf/ai/README.md)、[象棋真人玩家模块](player/xiangqi/human/README.md)、[象棋 AI 玩家模块](player/xiangqi/ai/README.md) 共同组成，统一真人、远程真人、AI 和托管玩家响应。 |
| 模型管理模块 | [model-management](model-management/README.md) | 模型配置和基础推理能力黑盒；负责模型配置、供应商列表、配置测试、结构兼容、思考兼容和一次模型调用。 |
| 机器人/RAG 模块 | [bot-management](bot-management/README.md) | 通用机器人能力黑盒；内部拆分记忆模块和机器人上下文处理模块，对外提供机器人创建、上下文构建和分层记忆更新能力；接口契约见 [interfaces](bot-management/interfaces.md)。 |
| TTS 语音模块 | [tts-voice](tts-voice/README.md) | 语音输出黑盒；负责声音配置、文本转语音、播放队列和播放事件。 |

### 小编织模块

| 模块 | 文档 | 职责摘要 |
| --- | --- | --- |
| 大厅模块 | [lobby](lobby/README.md) | 入口编排黑盒；聚合本机房间、局域网发现、重连和配置入口，并把用户动作转成路由或模块命令。 |
| 创建房间模块 | [create-room](create-room/README.md) | 统一创建 UI 编排；读取可创建游戏房间模块、地图、支持人数和场景槽位，采集创建输入并提交 `RoomCreateRequest`。不启动网络、不发布发现。 |

### 大编织模块

| 模块 | 文档 | 职责摘要 |
| --- | --- | --- |
| 房间模块 | [room](room/README.md) | 通用房间运行容器；维护参与者、席位、玩家交互、事件广播、玩家 inbox、可见历史下载、重连、真人副本、主机重选、主机接管和具体游戏房间模块接入点。 |
| 狼人杀房间模块 | [room/werewolf](room/werewolf/README.md) | 当前具体游戏房间实现；维护狼人杀地图、支持人数、场景槽位、内部编排、状态机、行动请求、行动校验、特效请求、阶段推进、事件 payload、下发语义、胜负判断和复盘回合。 |
| 象棋房间模块 | [room/xiangqi](room/xiangqi/README.md) | 新增具体游戏房间设计；维护象棋地图、两方座位、竖版棋盘布局、权威局面、走法校验、回合推进、胜负与和棋判定、聊天触发和复盘。 |

## 调用关系

```text
大厅
  -> 创建房间 / 扫码加入 / 重连 / 偏好设置
  -> 调用基础扫码能力，不解析二维码
  -> 房间模块

偏好设置
  -> 启动时确保本机偏好 JSON 存在
  -> 提供昵称、头像、播放声音配置引用和设备私钥持久化
  -> 设备私钥由基础能力消费，用于设备身份和签名
  -> 不拥有认证判断、房间、规则、模型配置详情、声音配置详情、TTS 播放或 RAG 权威状态

房间模块
  -> 消费基础二维码、扫码、加密和认证结果
  -> 提供 room context、席位、加入策略、网络同步、基础信息
  -> 向创建房间模块提供可创建游戏房间模块 / 地图 / 支持人数 / 场景槽位目录
  -> 通过玩家模块投递玩家行为请求和玩家可见数据
  -> 调用具体游戏房间模块公开接口

玩家模块
  -> 消费房间传入的座位、连接、认证摘要和在线状态
  -> 建立 PlayerTrustedChannel
  -> 保存 PlayerTemporaryDataEnvelope 和投递游标
  -> 构建 PlayerRecoveryFrame 并在断联恢复后重新投递玩家可见数据
  -> 分发带指令类型的 PlayerActionRequest 给真人、远程真人、AI 机器人或托管控制器
  -> 真人玩家模块按指令类型投递和回收真人输入
  -> AI 玩家模块统一 AI 控制器入口和结果包装
  -> 返回 PlayerActionResult 给对应具体游戏真人/AI 玩家模块
  -> 接收已确认文本和调用方传入的音色 ID，调用 TTS 文本转语音能力

狼人杀房间模块
  -> 提供狼人杀地图、支持人数和场景槽位
  -> 根据地图 ID 和人数选择内部编排
  -> 维护权威游戏状态
  -> 生成玩家行动请求
  -> 接收玩家行动结果
  -> 校验并输出特效请求、推进阶段和下一步行动请求

狼人杀真人玩家模块
  -> 接收指令并按指令类型打开对话框或行动交互 UI
  -> 通过 UI 把用户操作转成行动结果
  -> 经玩家模块可信通道提交给主机端房间程序
  -> 最终由狼人杀房间模块校验

狼人杀 AI 玩家模块
  -> 从机器人档案读取模型配置引用和声音配置引用
  -> 控制设备从本机模型数据库读取完整 ModelProfile
  -> 读取狼人杀房间模块提供的当前玩家输入数据
  -> 构建输入上下文和 records 字符串队列
  -> 调用机器人模块 build_bot_context()
  -> 获得 BotReasoningContext
  -> 使用本机 ModelProfile 调用基础模型推理能力完成输入输出
  -> 解析模型输出为行动结果
  -> 通过玩家模块结果链路提交给狼人杀房间模块
  -> 狼人杀房间模块接受后映射成通用 memory_update
  -> 调用机器人模块 commit_bot_result() 更新记忆

象棋房间模块
  -> 提供象棋地图、2 人座位和竖版棋盘场景槽位
  -> 维护权威棋盘、行棋方、棋谱、求和、悔棋、计时和结果
  -> 生成走棋、求和、悔棋、认输和聊天请求
  -> 接收玩家行动结果
  -> 校验走法、将军、将死、困毙、和棋、认输和超时
  -> 输出棋局事件、特效请求、下一步行动请求和复盘材料

象棋真人玩家模块
  -> 接收象棋行动请求并打开棋子选择、目标格选择或确认弹窗
  -> 把真人操作转成行动结果
  -> 经玩家模块可信通道提交给主机端房间程序
  -> 最终由象棋房间模块校验

象棋 AI 玩家模块
  -> 到 AI 回合时构建行棋上下文并调用模型输出结构化走法
  -> 真人公开发言被接受后才构建聊天上下文并生成回应
  -> 行棋 prompt 和聊天 prompt 分离
  -> 模型输出解析后通过玩家模块结果链路提交给象棋房间模块

玩家发言
  -> 进入房间历史或游戏房间结果
  -> 调用 TTS 文本转语音能力
```

## 边界规则

- 基础能力提供通用底座，包括二维码生成、扫码、加密、设备身份和认证；不写房间加入策略、重连策略或狼人杀房间玩法。
- 大厅只做房间展示和子模块入口，不复制创建房间、扫码入房或重连校验逻辑。
- 偏好设置只保存本机偏好：昵称、头像 ID、播放声音配置引用和设备私钥；不保存模型配置详情、声音配置详情、机器人配置、房间 secret 或重连 token 明文。
- 大厅和房间都是能力编排模块，本身不承载二维码、扫码、加密或通用认证基础能力的提供。
- 房间模块负责房间级生命周期、加入策略和网络权威，不写具体狼人杀阶段判断，不复制二维码、扫码、加密或设备身份实现。
- 狼人杀房间模块是当前具体游戏房间执行层，只有它维护狼人杀权威状态、地图配置、场景槽位和阶段推进。
- 狼人杀房间模块按地图 ID、人数和内部编排决定下一步行动请求、特效请求和阶段推进。
- 玩家模块只保存通用玩家资料、运行时绑定、玩家级可信通道、玩家临时数据、恢复材料和行为控制器入口，不写玩法身份、玩家策略、游戏状态或音色选择结果。
- AI 机器人使用的模型配置引用和声音配置引用归机器人档案；玩家资料只保存机器人引用。完整模型配置、API Key 和兼容适配参数只存在于控制设备本机。
- 具体游戏真人玩家模块和具体游戏 AI 玩家模块负责把游戏房间模块的行动请求转换成玩家响应，最终结果仍由对应具体游戏房间模块校验。
- 真人玩家 UI 只负责接收指令、收集输入和回传结果，不决定特效或阶段推进。
- 真人玩家、远程真人玩家、AI 机器人玩家和托管玩家必须提交同一种行动结果，最终由具体游戏房间模块校验。
- 新增具体游戏时，核心增量应限制在具体游戏房间模块、具体游戏真人玩家实现模块和具体游戏 AI 机器人玩家实现模块；公共房间、玩家、机器人/RAG、模型、TTS 和基础能力只通过公开接口复用。
- 模型管理只管模型配置、结构兼容、思考兼容和基础模型输入输出能力，不写机器人记忆、玩家策略或具体游戏房间玩法。
- 机器人/RAG 内部分为机器人模块、记忆模块和机器人上下文处理模块；只提供通用机器人身份、上下文构建和分层记忆能力，不理解狼人杀字段，不直接做狼人杀行动裁决。
- TTS 只做文本转语音，不判断文本来源，不修改历史、游戏房间结果、模型输出或机器人记忆。
- 玩家模块对外提供公共 TTS 文本转语音接口，调用方必须传入本次播报使用的音色 ID。

## 当前重构状态

重构已经形成部分模块脚本和模块文档，但代码还没有完全按目标边界收敛：

- `scripts/core/app_router.gd` 已经作为主路由入口，页面通过场景加载。
- `scripts/pages/lobby_page.gd` 只保留大厅入口配置，大厅主渲染、工具栏、重连卡片和房间卡片已放到 `scripts/pages/lobby/lobby_page_flow.gd`。
- `scripts/pages/config/*`、`scripts/pages/replay_page.gd`、`scripts/room/werewolf/werewolf_room_page.gd` 已经按现有渲染入口拆出。
- `scripts/ui/` 当前只保留 `base/`、`common/` 和 `qr/`，用于通用 UI 基类、通用弹层、二维码生成和扫码处理 UI。
- `scripts/pages/base/page_werewolf_asset_ui_base.gd` 提供页面层对狼人杀资源目录的访问，包括大厅、日夜、地图背景、头像和行动图标路径。
- `scripts/pages/base/page_scan_join_flow_base.gd` 承载扫码加入流程状态、Android 扫码信号绑定、手动加入提交和加入处理页同步。
- `scripts/pages/base/page_book_ui_base.gd` 承载书页弹层、覆盖层、toast、二维码图片和书页表单 helper。
- `scripts/pages/base/page_route_ui_base.gd` 承载页面路由信号和配置页、复盘页跳转 helper。
- `scripts/pages/base/page_audio_ui_base.gd` 承载页面点击音效。
- `scripts/pages/base/page_tts_ui_base.gd` 承载声音配置仓库、预置系统 TTS 默认记录、TTS 运行时、声音目录和声音配置页试听 helper。
- `scripts/pages/base/page_model_ui_base.gd` 承载模型配置仓库、模型调用 client、模型目录 client、模型配置列表和玩家模型配置选择 helper。
- `scripts/pages/base/page_room_discovery_ui_base.gd` 承载局域网房间发现、房间列表合并、房间列表刷新和当前房间查找 helper。
- `scripts/pages/base/page_identity_ui_base.gd` 承载偏好仓库接入、本机昵称、设备身份加载和网络身份注入 helper。
- `scripts/pages/base/page_room_network_ui_base.gd` 承载房间网络会话创建、信号绑定、网络角色判断和通用拒绝发送 helper。
- `scripts/pages/base/page_room_participant_ui_base.gd` 承载参与者认证材料、观察者、重连令牌和网络 nonce/base64 包装 helper。
- `scripts/pages/base/page_room_replica_ui_base.gd` 承载房间快照应用、房间副本接收、主机候选排序、主机接管和主机切换后的重连编排 helper。
- `scripts/pages/base/page_room_join_ui_base.gd` 承载二维码入房、加密二维码密钥协商、重连会话保存、房主加入处理和网络消息分发 helper。
- `scripts/pages/base/page_room_host_peer_ui_base.gd` 承载房主端 peer 准备、换座、旁观、加机器人、改名、离线和参与者控制权 helper。
- `scripts/pages/base/page_tts_history_ui_base.gd` 承载历史消息入队、播放声音偏好读取、历史播报队列提交和桌面席位播报动效状态。
- `scripts/pages/base/page_bot_profile_ui_base.gd` 承载机器人资料仓库、机器人门面和通用记忆管理器页面接入。
- `scripts/room/werewolf/werewolf_room_page_state.gd` 承载狼人杀页面共享状态、房间规则运行时、席位状态和页面钩子接口。
- `scripts/player/player_factory.gd` 是玩家模块当前公开工厂入口；`scripts/player/player_task_channel.gd` 维护通用玩家任务通道；`scripts/player/player_presentation_ack_controller.gd` 维护通用展示 ACK gate 状态，`scripts/player/player_presentation_ack_participant_resolver.gd` 维护 ACK participant / peer 归一化，`scripts/player/player_presentation_ack_runtime.gd` 维护本机 ACK 定时、发送、host apply/drop 运行包装，`scripts/player/player_speech_output.gd` 维护玩家到 TTS 的历史播报适配。狼人杀真人玩家工厂在 `scripts/player/werewolf/human/`，狼人杀 AI 玩家工厂和 AI 回合实现位于 `scripts/player/werewolf/ai/`。
- `scripts/room/werewolf/werewolf_room_lifecycle_page_flow.gd` 承载房间发布、退出、销毁、主机网络、远端行动/发言应用和玩家数据工厂。
- `scripts/room/werewolf/werewolf_room_table_page_flow.gd` 承载桌面布局、中心面板、席位刷新、行动提示和发言输入。
- `scripts/room/werewolf/werewolf_room_create_page_flow.gd` 承载创建房间弹层、地图选择、支持人数读取、角色分布展示和创建后入桌。
- `scripts/pages/base/page_app_shell_base.gd` 承载基础场景节点、清屏、弹层清理、路由占位和特效层。
- `scripts/pages/base/page_app_state_bridge_base.gd` 承载 `AppState` 读写、配置仓库绑定、机器人资料仓库绑定和状态提交。
- `scripts/pages/base/page_navigation_ui_base.gd` 只保留页面生命周期、初始路由、退出清理和帧循环。
- `scripts/room/werewolf/werewolf_room_progress_page_flow.gd` 承载狼人杀桌面 HUD 和阶段进度条。
- `scripts/room/werewolf/werewolf_room_bot_page_flow.gd` 承载狼人杀房间内机器人加入弹层和机器人资料选择。
- `scripts/room/werewolf/werewolf_room_overlay_page_flow.gd` 承载狼人杀房间二维码、历史面板和复盘入口。
- `scripts/room/werewolf/werewolf_room_interaction_page_flow.gd` 承载狼人杀座位点击、落座、准备、改名和座位详情。
- `scripts/room/werewolf/werewolf_asset_catalog.gd` 是狼人杀资源公开目录，`AppState`、房间玩家工厂和页面层通过它读取背景、头像和行动图标路径。
- `scripts/network/` 当前只保留二维码 payload、UDP 发现和网络信封；房间会话、快照、副本、参与者注册和主机选举已放到 `scripts/room/network/`。
- `scripts/player/werewolf/ai/ai_werewolf_player_runtime.gd` 是狼人杀 AI 玩家运行时门面；`ai_werewolf_prompt_renderer.gd` 负责 system/user prompt 和模型 payload，`ai_werewolf_output_parser.gd` 负责文本和 JSON 输出解析；`ai_werewolf_player_page_flow.gd` 负责页面流接入。
- `scripts/core/memory/` 和 `scripts/player/werewolf/ai/ai_werewolf_memory*.gd` 当前共同承载记忆能力；目标归属上，记忆存储和更新收敛到 [记忆模块](bot-management/memory-module.md)，输入上下文与记忆上下文合并收敛到 [机器人上下文处理模块](bot-management/bot-context-module.md)，机器人档案和对外门面收敛到 [机器人模块](bot-management/bot-module.md)。

继续拆分时，优先从 `scripts/pages/base/page_navigation_ui_base.gd` 中拆出剩余模块专属流程，不要新增跨模块业务规则到该页面共享入口。

新增脚本、场景、资源或测试时，按“工程目录外层不变、目录内部按模块归档”的原则落位。只有真正跨模块复用的运行时能力才放 `scripts/core/`、`scripts/ui/`、`scenes/common/` 或类似公共目录；模块专属流程应进入对应模块目录。

## 文档放置规则

- 模块边界、接口、文件归属、流程：写到 `docs/modules/<module>/README.md`。
- 模块内专题细节：放到模块目录内，例如 [base/qr_scan_join.md](base/qr_scan_join.md)、[tts-voice/voice_config.md](tts-voice/voice_config.md)。
- 偏好设置写到 `docs/modules/preferences/README.md`，不要混入模型、声音或机器人配置文档。
- 狼人杀房间模块写到 `docs/modules/room/werewolf/README.md`。
- 玩家模块父级写到 `docs/modules/player/README.md`。
- 真人玩家模块写到 `docs/modules/player/human/README.md`。
- AI 玩家模块写到 `docs/modules/player/ai/README.md`。
- 狼人杀真人玩家模块写到 `docs/modules/player/werewolf/human/README.md`。
- 狼人杀 AI 玩家模块写到 `docs/modules/player/werewolf/ai/README.md`。
- 跨模块总览：写到 `docs/architecture.md`。
- 跨模块数据对象、下发范围、错误码和调用结果：写到 [跨模块契约](../contracts/README.md)。
- 工程物理目录：写到 `docs/project-structure/README.md`。
- 构建、导出、安装：写到 `docs/build_deployment.md`。
- 归档设计：放到 `docs/archive/`。

## 跨模块契约

模块边界之外的数据对象统一在 [跨模块契约](../contracts/README.md) 维护。当前已经固定这些主契约：

1. 基础能力到房间：`QrJoinPayload`、`RoomJoinAuthBundle`。
2. 房间到大厅和客户端：`RoomSummary`、`LobbyRoomEntry`、`RoomSnapshot`、`TemporaryGameDataEnvelope`。
3. 房间事件和恢复：`RoomEventEnvelope`、`PlayerMessageInbox`、`RoomReplicaFrame`。
4. 狼人杀房间模块到玩家适配层：`WerewolfActionRequest`、`WerewolfPlayerActionResult`、`WerewolfRuleUpdateResult`。
5. 玩家侧通道和恢复：`PlayerTrustedChannel`、`PlayerTemporaryDataEnvelope`、`PlayerRecoveryFrame`。
6. 通用玩家行为：`PlayerActionRequest`、`PlayerActionResult`。
7. 玩家适配层到机器人/RAG：输入上下文、`BotReasoningContext`、`memory_update`。
8. 具体游戏 AI 机器人玩家适配层到模型管理：`ModelGenerationRequest`、`ModelGenerationResult`。
9. 玩家到 TTS：`PlayerSpeechRequest`、`TtsPlaybackRequest`、`TtsPlaybackResult`。

后续新增字段或调整语义时，先更新跨模块契约，再回填对应生产者和消费者模块文档。

