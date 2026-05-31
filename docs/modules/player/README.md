# 玩家模块

更新时间：2026-05-21

玩家模块是基础模块，负责“玩家”这一通用对象的基础资料、运行时绑定、可信通信通道、临时数据存储、数据生命周期和行为控制器抽象。它回答“这个玩家是谁、当前绑定在哪里、由谁控制、如何接收房间或游戏发来的请求，如何临时保存玩家侧数据，并如何在断联恢复后重新投递玩家可见数据和返回统一玩家行为结果”。

玩家模块像一个玩家行为黑盒：它不判断具体游戏房间玩法，不理解狼人杀、三国杀、围棋、象棋或麻将的业务语义，不维护机器人记忆，也不实现 TTS 引擎；它维护玩家共性数据、运行时绑定、玩家级可信通道、玩家临时数据队列、控制器入口和恢复材料，并提供公共 TTS 文本转语音接口。调用方提交已确认文本时必须同时传入音色 ID，玩家模块再调用语音能力完成播报。

跨模块对象 `PlayerProfile`、`PlayerRuntimeBinding`、`PlayerTrustedChannel`、`PlayerTemporaryDataEnvelope`、`PlayerRecoveryFrame`、`PlayerActionRequest`、`PlayerActionResult`、`PlayerSpeechRequest`、`TtsPlaybackRequest` 的字段权威见 [跨模块契约](../../contracts/README.md)。本文保留玩家模块的资料、绑定、可信通道、临时数据、行为控制和已确认输出流程说明。

## 模块定位

```text
偏好设置 / 创建房间 / 房间 / 具体游戏房间模块
  -> 玩家模块
       -> 创建 PlayerProfile
       -> 绑定运行时座位或控制来源
       -> 建立玩家级可信通信通道
       -> 记录可展示的玩家基础状态
       -> 临时保存玩家可见数据、待处理请求和投递游标
       -> 提供 PlayerController 行为入口
       -> 真人玩家模块
            -> 狼人杀真人玩家模块
       -> AI 玩家模块
            -> 狼人杀 AI 玩家模块
       -> 托管玩家统一返回 PlayerActionResult
       -> 断联恢复后重新投递玩家可见数据
       -> 接收已确认发言
       -> 接收调用方传入的音色 ID
       -> 请求 TTS 语音模块播报
```

当前玩家模块由父级玩家、通用真人/AI 控制器和具体游戏玩家适配模块共同组成：

| 模块 | 文档 | 职责 |
| --- | --- | --- |
| 玩家模块 | 本文 | 父级模块；维护通用玩家资料、运行时绑定、玩家级可信通道、玩家临时数据、恢复材料、控制器分发和输出能力。 |
| 真人玩家模块 | [human](human/README.md) | 通用真人控制器；处理本机真人、远程真人的请求投递、ACK、结果回收和断联恢复。 |
| AI 玩家模块 | [ai](ai/README.md) | 通用 AI 控制器；定义 AI 玩家控制器入口、机器人引用和统一玩家行为结果包装。 |
| 狼人杀真人玩家模块 | [werewolf/human](werewolf/human/README.md) | 具体游戏真人玩家实现；把狼人杀行动、发言、目标选择请求转成人能操作的 UI 输入。 |
| 狼人杀 AI 玩家模块 | [werewolf/ai](werewolf/ai/README.md) | 具体游戏 AI 玩家实现；构建狼人杀 AI 上下文、prompt/schema，调用模型并解析输出。 |
| 象棋真人玩家模块 | [xiangqi/human](xiangqi/human/README.md) | 具体游戏真人玩家实现；把象棋走棋、求和、悔棋、认输和聊天请求转成人能操作的 UI 输入。 |
| 象棋 AI 玩家模块 | [xiangqi/ai](xiangqi/ai/README.md) | 具体游戏 AI 玩家实现；构建象棋行棋上下文和聊天上下文，调用模型并解析输出。 |

旧的 `docs/modules/room/werewolf/player/` 只保留历史迁移指针；狼人杀玩家实现的权威文档归入本目录下的 `werewolf/human` 和 `werewolf/ai`。

## 能力边界

玩家模块负责：

- 创建真人玩家或 AI 机器人玩家基础资料。
- 保存玩家展示名、头像、玩家类型、控制来源等共性字段。
- 保存玩家与运行时上下文的绑定关系，例如座位、连接、是否准备、在线状态。
- 基于基础能力和房间认证结果建立玩家级可信通信通道。
- 为玩家行为请求、玩家可见通知、玩家本地 UI 状态和待投递结果维护临时数据队列。
- 维护玩家任务通道，保存待玩家响应的通用任务、投递状态、控制设备归属和自动推进阻塞状态。
- 维护展示 ACK 的通用状态、presentation ID、待本机 ACK、文本等待时间和 gate 打开判断。
- 维护玩家数据生命周期：创建、绑定、在线、离线、恢复、解绑、退出、清理。
- 在房间重连完成后，按玩家可见性、投递游标和 ack 状态重新投递玩家数据。
- 维护 AI 机器人玩家可引用的机器人 ID。
- 提供通用玩家行为请求入口，把带指令类型的请求分发给真人、远程真人、AI 机器人或托管控制器。
- 返回统一 `PlayerActionResult`，供具体游戏玩家适配层转换成游戏行动结果。
- 接收上层已经确认的公开文本。
- 提供公共 TTS 文本转语音接口，接收调用方传入的音色 ID，并把已确认文本转成语音播放请求、历史播报队列项和发言人静音状态。
- 提供玩家读取、更新、绑定、解绑和只读调试能力。

玩家模块不负责：

- 房间创建、加入、房间级认证、主机选举和房间级断线重连策略。
- Socket / WebSocket 底层传输、证书校验、二维码、扫码、加密、签名或设备认证实现。
- 狼人杀房间模块的阶段推进、身份分配、胜负判断、行动合法性判断。
- 三国杀、围棋、象棋、麻将等具体游戏的行动解释和合法性判断。
- 具体游戏真人 UI 交互流程。
- AI 机器人玩家策略、提示词组装、模型调用、记忆检索或记忆更新；这些由具体游戏玩家适配层组合机器人/RAG 和模型管理完成。
- TTS 引擎实现、声音合成、播放队列细节。

玩家模块提供的是“玩家级可信通道”：它消费基础能力和房间模块已经确认的连接、身份和授权结果，负责玩家请求投递、ack、去重、补发和恢复；它不直接实现底层 socket、证书链、二维码解密或设备签名算法。

## 内部实现

玩家模块内部建议拆成五个模块和十一个通用子系统。五个模块是父级玩家模块、真人玩家模块、AI 玩家模块、狼人杀真人玩家模块、狼人杀 AI 玩家模块；十一个通用子系统归父级玩家模块维护：

1. 玩家资料仓库：维护 `PlayerProfile` 的当前结构、默认值、读取、更新和无效数据丢弃。
2. 运行时绑定表：维护 `PlayerRuntimeBinding`，记录玩家所在房间、座位、连接、控制器和在线状态。
3. 玩家可信通道管理器：建立 `PlayerTrustedChannel`，绑定参与者、设备、连接和玩家控制器。
4. 玩家临时数据仓库：保存 `PlayerTemporaryDataEnvelope`，按玩家、作用域、序号、可见性和 TTL 管理临时数据。
5. 玩家投递游标管理器：维护已投递、已确认和待补发序号，支持断联后重放。
6. 玩家恢复帧构建器：生成 `PlayerRecoveryFrame`，用于房间重连成功后的玩家侧数据恢复。
7. 玩家控制器分发器：按指令类型把行为请求交给本机真人、远程真人、AI 机器人或托管控制器，并统一收集 `PlayerActionResult`。
8. 玩家任务通道：维护通用 `player_action`、`player_speech` 等待响应任务，记录控制 participant、投递状态、失败原因、pending 快照和自动推进阻塞状态。
9. 玩家展示 ACK 控制器：维护 presentation ID、expected/acked 集合、本机 ACK 待发送状态、文本等待时间和断联参与者清理。
10. 玩家语音输出适配器：对外提供公共 TTS 文本转语音接口，把已确认文本、音色 ID 和播放参数交给 TTS，并维护历史播报队列查询和发言人静音键。
11. 玩家结果适配器：把玩家行为结果交回具体游戏玩家适配层。

## 生命周期契约

| 生命周期 | 触发方 | 建议调用 | 作用 |
| --- | --- | --- | --- |
| `player_created` | 大厅 / 创建房间 / 房间 / 玩法适配层 | `create_player_profile()` | 创建通用玩家基础资料。 |
| `player_bound` | 房间模块 / 玩法适配层 | `bind_player_to_runtime()` | 把玩家绑定到运行时作用域、座位和连接。 |
| `player_updated` | 偏好设置 / 配置页 / 房间 UI | `update_player_profile()` | 更新展示名、头像、机器人引用等基础字段。 |
| `action_requested` | 房间模块 / 具体游戏玩家适配层 | `request_player_action()` | 把通用行为请求交给对应玩家控制器。 |
| `player_message_sent` | 房间模块 / 玩法适配层 / 玩家模块 | `send_player_message()` | 通过玩家级可信通道投递玩家可见数据。 |
| `player_message_acked` | 玩家客户端 / 玩家控制器 | `ack_player_message()` | 确认玩家数据已处理，推进投递游标。 |
| `player_data_stored` | 玩家模块 / 玩家控制器 | `save_player_temporary_data()` | 临时保存玩家侧请求、通知、UI 状态或待提交结果。 |
| `action_completed` | 玩家控制器 | `complete_player_action()` | 返回统一玩家行为结果，交回上层适配层。 |
| `player_disconnected` | 房间模块 / 基础能力 | `mark_player_offline()` | 标记玩家离线，保留恢复窗口内的临时数据和投递游标。 |
| `player_recovered` | 房间模块 / 玩家模块 | `restore_player_runtime_data()` | 在房间重连完成后恢复玩家通道并重新投递可见数据。 |
| `speech_accepted` | 房间模块 / 具体游戏房间模块 / 玩法玩家适配层 | `submit_accepted_speech()` | 提交已被上层接受的文本和音色 ID，交给 TTS 播放。 |
| `player_unbound` | 房间模块 / 会话结束 / 玩家离开 | `unbind_player_from_runtime()` | 解除座位、连接或临时运行时绑定。 |
| `profile_invalid` | 读取玩家资料 | `discard_invalid_player_profile()` | 丢弃不符合当前结构的玩家资料。 |

## 核心对象

### PlayerProfile

`PlayerProfile` 是玩家基础资料，不绑定具体游戏房间玩法。

| 字段 | 说明 |
| --- | --- |
| `schema_version` | 玩家资料结构版本。 |
| `player_id` | 玩家唯一 ID。 |
| `display_name` | 展示名，默认可来自偏好设置昵称。 |
| `avatar_id` | 头像 ID，默认可来自偏好设置头像。 |
| `player_type` | 玩家类型，例如 `human`、`ai`。 |
| `owner_type` | 控制来源，例如 `self`、`local_human`、`remote_human`、`bot`。 |
| `controller_type` | 行为控制器类型，例如 `local_human`、`remote_human`、`ai`、`autoplay`。 |
| `bot_id` | AI 机器人玩家可选，引用机器人/RAG 模块中的机器人。 |
| `created_at` | 创建时间。 |
| `updated_at` | 最近更新时间。 |
| `metadata` | 扩展字段，只保存通用玩家元数据。 |

约定：

- `player_type` 只描述玩家类别，不表达狼人、预言家、主公、黑棋、红方或庄家等玩法身份。
- `owner_type` 和 `controller_type` 只表达控制来源和行为入口，不表达游戏阵营或权限。
- `bot_id` 是引用，不代表玩家模块拥有机器人档案、模型配置、声音配置或记忆数据。
- AI 机器人使用的模型配置引用和声音引用从机器人档案读取；完整模型配置只由具体游戏 AI 机器人玩家适配层在控制设备本机读取，声音引用在调用玩家/TTS 链路时传入。
- 播放时使用的音色 ID 不写入 `PlayerProfile`，由调用 `submit_accepted_speech()` 的实现传入。

### PlayerRuntimeBinding

`PlayerRuntimeBinding` 是玩家在某个运行时作用域里的临时绑定。

| 字段 | 说明 |
| --- | --- |
| `player_id` | 玩家 ID。 |
| `scope` | 运行时作用域，通常由房间或玩法适配层传入。 |
| `seat_id` | 座位 ID，可选。 |
| `connection_id` | 网络连接 ID，可选。 |
| `ready` | 是否准备。 |
| `online_state` | 在线状态，例如 `online`、`offline`、`reconnecting`。 |
| `visibility` | 当前绑定是否对本机可见。 |
| `metadata` | 扩展字段，只保存通用绑定信息。 |

约定：

- 绑定状态是临时状态，不应替代房间权威状态。
- 房间模块仍然负责最终房间快照、断线重连和主机选举。
- 具体游戏房间模块仍然负责游戏内身份、行动和胜负。

### PlayerTrustedChannel

`PlayerTrustedChannel` 是玩家模块提供的玩家级可信通信通道。它建立在基础能力和房间模块已确认的连接、身份和授权结果之上，用来投递玩家请求、通知、控制器输入和恢复数据。

| 字段 | 说明 |
| --- | --- |
| `schema_version` | 结构版本。 |
| `channel_id` | 玩家通道 ID。 |
| `player_id` | 玩家 ID。 |
| `participant_id` | 房间参与者 ID，可选。 |
| `room_id` | 房间 ID，可选。 |
| `device_id` | 已认证设备身份。 |
| `controller_type` | 控制器类型。 |
| `connection_ref` | 基础能力或房间模块提供的连接引用。 |
| `trust_state` | `trusted`、`pending`、`revoked`、`closed`。 |
| `last_delivered_sequence` | 已投递给玩家侧的最新序号。 |
| `last_ack_sequence` | 玩家侧已确认处理的最新序号。 |
| `opened_at` / `updated_at` | 打开和更新时间。 |
| `metadata` | 扩展字段，不保存底层 secret 明文。 |

约定：

- 玩家模块只消费认证结果，不生成证书、不保存设备私钥、不校验证书链。
- `connection_ref` 只是对基础能力或房间连接的引用，不代表玩家模块拥有底层 socket。
- 可信通道必须支持去重、ack、补发和关闭。
- `trust_state` 变为 `revoked` 或 `closed` 后，不再投递新的玩家数据。

### PlayerTemporaryDataEnvelope

`PlayerTemporaryDataEnvelope` 是玩家模块临时保存的玩家侧数据外壳。

| 字段 | 说明 |
| --- | --- |
| `schema_version` | 结构版本。 |
| `player_id` | 玩家 ID。 |
| `channel_id` | 玩家通道 ID，可选。 |
| `scope` | 作用域，例如房间、局、回合或页面。 |
| `sequence` | 玩家通道内单调递增序号。 |
| `data_id` | 数据 ID，用于去重。 |
| `data_kind` | `action_request`、`action_result`、`notice`、`ui_state`、`speech_request` 等。 |
| `visibility` | `player_private`、`private_local`、`public` 等。 |
| `payload` | 上层模块或玩家控制器生成的数据。 |
| `ttl` | 可选过期策略。 |
| `created_at` / `expires_at` | 创建和过期时间。 |
| `metadata` | 扩展字段。 |

约定：

- 玩家模块只维护外壳、序号、TTL、ack 和生命周期，不解释具体游戏 payload。
- 具体游戏玩家适配层负责确保 `payload` 已按玩家视角脱敏。
- 玩家退出、恢复窗口结束、房间关闭或数据过期时必须清理。

### PlayerRecoveryFrame

`PlayerRecoveryFrame` 是玩家断联后恢复用的玩家侧数据帧。

| 字段 | 说明 |
| --- | --- |
| `schema_version` | 结构版本。 |
| `player_id` | 玩家 ID。 |
| `participant_id` | 房间参与者 ID，可选。 |
| `room_id` | 房间 ID，可选。 |
| `channel_id` | 原玩家通道 ID。 |
| `last_ack_sequence` | 玩家侧最后确认序号。 |
| `pending_data` | 需要重新投递的 `PlayerTemporaryDataEnvelope`。 |
| `runtime_binding` | 当前玩家运行时绑定摘要。 |
| `controller_state` | 可选控制器恢复状态。 |
| `created_at` | 恢复帧生成时间。 |
| `expires_at` | 恢复帧过期时间。 |
| `metadata` | 扩展字段。 |

约定：

- 恢复帧只保存当前玩家可见的数据。
- 房间重连认证成功后，玩家模块按 `last_ack_sequence` 重新投递未确认数据。
- 恢复帧过期、玩家明确退出或房间关闭后必须清理。

### PlayerController

`PlayerController` 是玩家行为入口，不包含具体游戏房间玩法。

| 控制器 | 说明 |
| --- | --- |
| `local_human` | 本机真人，通过本机 UI 返回行为。 |
| `remote_human` | 远程真人，通过房间网络请求和 inbox 返回行为。 |
| `ai` | AI 机器人玩家，由具体游戏玩家适配层组合机器人/RAG 和模型管理产生行为。 |
| `autoplay` | 托管或超时响应，由上层策略生成最小合法响应。 |

约定：

- 控制器只负责“如何取得玩家响应”，不负责判断具体游戏行动是否合法。
- 具体游戏玩家适配层负责把 `PlayerActionResult` 转成 `WerewolfPlayerActionResult` 或后续其它游戏行动结果。

### PlayerActionRequest

通用玩家行为请求，通常由房间模块或具体游戏玩家适配层发起。

| 字段 | 说明 |
| --- | --- |
| `schema_version` | 请求结构版本。 |
| `request_id` | 行为请求 ID。 |
| `room_id` | 房间 ID。 |
| `player_id` | 目标玩家 ID。 |
| `controller_type` | 目标控制器类型。 |
| `game_id` | 当前游戏，例如 `werewolf`、`go`、`chess`。 |
| `instruction_type` | 指令类型，例如 `dialog`、`action_ui`、`speech_input`、`target_select`、`confirm`。 |
| `action_prompt` | 上层已经脱敏后的行为提示。 |
| `options` | 可选动作、目标或输入约束，格式由上层适配层决定。 |
| `visible_context` | 当前玩家可见上下文，不包含不该看到的私有信息。 |
| `timeout_ms` | 可选超时。 |
| `metadata` | 扩展字段。 |

约定：

- 玩家模块不解释 `options` 和 `visible_context` 的具体游戏语义。
- `instruction_type` 只用于控制器选择交互承载方式，例如打开对话框、行动交互 UI、文本输入或目标选择；玩家模块不根据它判断玩法是否合法。
- 真人控制器产生的输入必须转成 `PlayerActionResult`，并通过玩家模块的可信通道、临时数据和 ack 机制交回主机端房间程序。
- 本机真人和远程真人使用同一玩家模块结果链路；本机可以不经过物理网络，但不能绕过玩家模块的投递、去重、ack 和恢复语义。
- 具体游戏玩家适配层必须先完成可见性过滤，再调用玩家模块。

### PlayerActionResult

通用玩家行为结果。

| 字段 | 说明 |
| --- | --- |
| `schema_version` | 结果结构版本。 |
| `request_id` | 对应行为请求 ID。 |
| `player_id` | 行为玩家 ID。 |
| `source` | `local_human`、`remote_human`、`ai`、`autoplay`。 |
| `action_payload` | 玩家返回的原始行为数据。 |
| `submitted_at` | 提交时间。 |
| `metadata` | 扩展字段。 |
| `error` | 失败时的结构化错误。 |

约定：

- `action_payload` 仍需交给具体游戏玩家适配层转换，再交给具体游戏房间模块校验。
- AI 机器人或托管结果不能绕过具体游戏房间模块直接修改状态。
- 真人 UI 输入只是玩家响应，不决定特效、阶段推进或具体游戏房间状态变更。

### PlayerSpeechRequest

`PlayerSpeechRequest` 是已确认文本的播报请求。

| 字段 | 说明 |
| --- | --- |
| `schema_version` | 请求结构版本。 |
| `request_id` | 请求 ID，用于去重和调试。 |
| `player_id` | 发言玩家 ID。 |
| `scope` | 发言所属作用域。 |
| `text` | 已确认要播报的文本。 |
| `voice_profile_id` | 必填，调用方传入的音色 ID 或声音配置 ID。 |
| `source` | 文本来源，例如 `rule_accepted`、`room_history`、`manual_confirmed`。 |
| `visibility` | 可见性，例如 `public`、`private_local`。 |
| `accepted_at` | 上层确认时间。 |
| `metadata` | 扩展字段。 |

约定：

- 玩家模块只接收已经被上层确认的文本。
- 玩家模块不自行选择音色，不从玩家资料推断音色；具体音色 ID 由调用实现传入。
- 未通过房间或具体游戏房间模块校验的临时输入，不应进入 `submit_accepted_speech()`。
- 文本清洗只属于 TTS 输出链路，不应反向修改玩家资料或历史原文。

## 对外接口

以下接口是设计契约，不要求当前代码函数名完全一致。

```text
create_player_profile(request) -> PlayerProfileResult
get_player_profile(request) -> PlayerProfileResult
update_player_profile(request) -> PlayerProfileResult
bind_player_to_runtime(request) -> PlayerBindingResult
unbind_player_from_runtime(request) -> PlayerBindingResult
open_player_channel(request) -> PlayerChannelResult
close_player_channel(request) -> PlayerChannelResult
send_player_message(request) -> PlayerMessageSendResult
ack_player_message(request) -> PlayerMessageAckResult
save_player_temporary_data(request) -> PlayerTemporaryDataResult
build_player_recovery_frame(request) -> PlayerRecoveryFrameResult
restore_player_runtime_data(request) -> PlayerRecoveryResult
request_player_action(request) -> PlayerActionRequestResult
complete_player_action(request) -> PlayerActionResult
submit_accepted_speech(request) -> PlayerSpeechResult
get_player_debug_state(request) -> PlayerDebugResult
```

### create_player_profile

```text
create_player_profile(request) -> PlayerProfileResult
```

`request`：

| 字段 | 说明 |
| --- | --- |
| `display_name` | 可选，玩家展示名。缺省时可使用偏好设置昵称或自动生成。 |
| `avatar_id` | 可选，头像 ID。缺省时可使用偏好设置头像或默认头像。 |
| `player_type` | `human` 或 `ai`。 |
| `owner_type` | 控制来源。 |
| `controller_type` | 行为控制器类型。 |
| `bot_id` | AI 机器人玩家可选。 |
| `metadata` | 扩展字段。 |

约定：

- 创建时只校验通用玩家字段。
- 不在这里创建机器人记忆，不测试模型可用性，不分配玩法身份。
- 如果引用的 `bot_id` 不存在，可以返回 warning 或 validation error，由调用方决定是否继续。

### bind_player_to_runtime

```text
bind_player_to_runtime(request) -> PlayerBindingResult
```

`request`：

| 字段 | 说明 |
| --- | --- |
| `player_id` | 玩家 ID。 |
| `scope` | 运行时作用域。 |
| `seat_id` | 可选座位。 |
| `connection_id` | 可选连接。 |
| `ready` | 可选准备状态。 |
| `online_state` | 可选在线状态。 |
| `metadata` | 扩展字段。 |

约定：

- 绑定成功不代表玩家已经通过房间认证；认证结果由房间或基础能力决定。
- 同一玩家是否允许绑定多个作用域，由房间或上层编织模块决定。
- 玩家模块可以保存绑定快照，但不抢占房间权威。

### open_player_channel

```text
open_player_channel(request) -> PlayerChannelResult
close_player_channel(request) -> PlayerChannelResult
```

`request`：

| 字段 | 说明 |
| --- | --- |
| `player_id` | 玩家 ID。 |
| `participant_id` | 房间参与者 ID，可选。 |
| `room_id` | 房间 ID，可选。 |
| `device_id` | 已通过基础能力认证的设备身份。 |
| `connection_ref` | 房间模块或基础能力提供的连接引用。 |
| `controller_type` | 控制器类型。 |
| `auth_context` | 房间模块确认后的授权摘要，不包含 secret 明文。 |
| `metadata` | 扩展字段。 |

约定：

- 打开玩家通道前，调用方必须已经完成基础认证和房间加入或重连校验。
- 玩家模块校验玩家、绑定、控制器和授权摘要是否匹配。
- 关闭通道只停止玩家级投递，不直接关闭底层 socket。
- 通道关闭后，未过期临时数据可以保留到恢复窗口结束。

### send_player_message

```text
send_player_message(request) -> PlayerMessageSendResult
ack_player_message(request) -> PlayerMessageAckResult
```

`request`：

| 字段 | 说明 |
| --- | --- |
| `channel_id` | 玩家通道 ID。 |
| `player_id` | 玩家 ID。 |
| `data_kind` | 数据类型。 |
| `payload` | 待投递数据。 |
| `visibility` | 玩家可见性。 |
| `ttl` | 可选过期策略。 |
| `request_id` | 可选请求 ID，用于去重。 |
| `ack_sequence` | ack 时传入，表示玩家侧已处理到的序号。 |

约定：

- `send_player_message()` 先写入 `PlayerTemporaryDataEnvelope`，再通过可信通道投递。
- 离线玩家不丢弃未过期数据，只标记为待补发。
- `ack_player_message()` 推进 `last_ack_sequence`，并允许清理已确认的临时数据。
- 玩家模块不解释 `payload` 的游戏语义。

### restore_player_runtime_data

```text
build_player_recovery_frame(request) -> PlayerRecoveryFrameResult
restore_player_runtime_data(request) -> PlayerRecoveryResult
```

流程：

```text
玩家断联
  -> 玩家模块标记通道离线
  -> 保留未过期 PlayerTemporaryDataEnvelope 和投递游标
  -> 房间模块完成重连认证
  -> 玩家模块重新打开 PlayerTrustedChannel
  -> restore_player_runtime_data()
  -> 按 last_ack_sequence 重新投递玩家可见数据
  -> 玩家侧 ack 后清理已确认数据
```

约定：

- 断联恢复的身份校验由基础能力和房间模块完成，玩家模块只消费结果。
- 恢复只返回该玩家可见的数据。
- 恢复成功不代表具体游戏行动被接受，行动结果仍由具体游戏玩家适配层和具体游戏房间模块校验。
- 恢复窗口结束、玩家退出或房间关闭时，玩家临时数据和恢复帧必须清理。

### request_player_action

```text
request_player_action(request) -> PlayerActionRequestResult
complete_player_action(request) -> PlayerActionResult
```

流程：

```text
房间模块 / 具体游戏玩家适配层
  -> 构造 PlayerActionRequest(instruction_type)
  -> 玩家模块按 controller_type 分发
       -> 本机真人 UI 按 instruction_type 打开交互
       -> 远程真人请求经 PlayerTrustedChannel 投递
       -> AI 机器人玩家适配入口
       -> 托管响应
  -> 真人输入经 PlayerTrustedChannel / PlayerTemporaryDataEnvelope 回到主机端房间程序
  -> 返回 PlayerActionResult
  -> 具体游戏玩家适配层转换成游戏行动结果
  -> 具体游戏房间模块最终校验
```

约定：

- 玩家模块只做控制器分发和结果归一化，不判断游戏合法性。
- 真人玩家请求应通过玩家级可信通道、玩家临时数据和房间可见历史机制恢复，不直接依赖某个页面还在。
- AI 机器人玩家请求必须由具体游戏玩家适配层先完成上下文脱敏，再在控制设备本机调用机器人/RAG 和基础模型推理能力。

### submit_accepted_speech

```text
submit_accepted_speech(request) -> PlayerSpeechResult
```

流程：

```text
玩法玩家适配层 / 具体游戏房间模块 / 房间模块
  -> 确认文本可以公开或本地播报，并选择音色 ID
  -> submit_accepted_speech(text + voice_profile_id + visibility + playback_options)
  -> 玩家模块构造 TtsPlaybackRequest
  -> 调用 TTS 语音模块 speak_text()
  -> 返回播报请求结果
```

约定：

- 该接口不接受“待审核草稿”。
- `voice_profile_id` 由调用实现传入，玩家模块不从 `PlayerProfile`、偏好设置或声音配置中自行选择音色。
- TTS 失败不应撤销游戏房间状态或房间历史。
- 对私密文本，调用方必须明确传入 `visibility`，并保证 TTS 输出不泄露给错误设备。

## 版本与无效数据

玩家模块数据会被房间快照、重连恢复和玩法适配层引用，只接受当前结构。

处理规则：

- 新增玩家字段必须提供默认值。
- 缺少必填字段、字段名不匹配或 `schema_version` 不匹配时，直接丢弃该玩家资料。
- 丢弃后由创建房间、房间或玩家适配层按当前字段重新创建 `PlayerProfile`。
- 玩法身份、阵营、行动记录不要写进通用玩家资料，应留在具体游戏房间模块或具体游戏玩家适配层。

## 失败处理

| 场景 | 策略 |
| --- | --- |
| 玩家 ID 不存在 | 返回 `not_found`，不创建隐式玩家。 |
| 昵称或头像无效 | 返回 validation error 或返回 validation error。 |
| 引用的机器人不存在 | 返回 warning，由具体游戏 AI 机器人玩家适配层决定是否禁用该机器人玩家。 |
| 引用的模型不存在 | 返回 warning，不在玩家模块内代选模型。 |
| 调用方传入的音色 ID 不存在 | 返回 validation error 或 TTS 模块的结构化错误。 |
| TTS 播放失败 | 返回 structured error，不撤销文本接受状态。 |
| 运行时绑定冲突 | 返回 conflict，由房间模块决定换座、踢出或拒绝。 |
| 玩家通道不可用 | 标记离线，保留恢复窗口内未确认临时数据。 |
| 玩家通道授权不匹配 | 拒绝打开通道，不投递玩家数据。 |
| 临时数据过期 | 清理数据，返回 `data_expired` 或跳过补发。 |
| 恢复帧过期 | 拒绝恢复，要求调用方重新进入房间流程。 |
| 控制器不可用 | 返回 `controller_unavailable`，由房间或具体游戏适配层决定等待、托管或拒绝。 |
| 玩家行为超时 | 返回 timeout，由具体游戏房间模块或房间策略决定是否托管。 |

## 只读调试

```text
get_player_debug_state(request) -> PlayerDebugResult
```

只读调试信息建议包含：

- 玩家资料是否存在。
- 玩家类型和控制来源。
- 当前绑定的作用域、座位、连接和在线状态。
- 玩家可信通道状态、认证摘要、连接引用和关闭原因。
- 玩家临时数据数量、待 ack 序号、待补发序号和最近清理结果。
- 玩家恢复帧是否存在、过期时间和可恢复数据摘要。
- 当前控制器类型、待处理行为请求和最近一次行为结果。
- 引用的 `bot_id` 是否可解析。
- 最近一次播报请求 ID 和播报结果。

约定：

- 调试接口不得修改玩家资料或运行时绑定。
- 不返回机器人记忆内容、模型 API Key、设备私钥或房间认证 secret。
- release 包可以禁用或只返回健康状态。

## 与其它模块的关系

| 模块 | 玩家模块如何交互 |
| --- | --- |
| 偏好设置模块 | 可用昵称和头像作为本机玩家默认资料。 |
| 房间模块 | 房间传入座位、连接、认证摘要和在线状态；通过玩家模块向玩家发起行为请求；玩家模块维护玩家侧通道、临时数据和恢复材料，但不接管房间权威。 |
| 狼人杀真人玩家模块 | 使用真人玩家模块的请求投递和结果回收能力，把狼人杀请求转成人能操作的 UI 输入。 |
| 狼人杀 AI 玩家模块 | 使用 AI 玩家模块的控制器入口，组合机器人/RAG、模型管理和狼人杀上下文，生成狼人杀行动结果。 |
| 机器人/RAG 模块 | AI 机器人玩家资料只保存 `bot_id` 引用；机器人档案、记忆读取和更新由具体游戏 AI 机器人玩家适配层调用。 |
| 模型管理模块 | 模型配置引用来自机器人档案；完整模型配置只在控制设备本机读取，模型输入输出由具体游戏 AI 机器人玩家适配层调用。 |
| TTS 语音模块 | 玩家模块提供公共文本转语音接口，把调用方传入的已确认文本、音色 ID 和播放参数交给 TTS 播报。 |
| 基础能力 | 玩家模块消费基础能力生成的设备身份、认证结果和连接能力；不实现认证、加密、二维码或签名。 |

## 文档和代码归属

玩家模块的代码归属为：

```text
scripts/player/
  player_factory.gd
  player_presentation_ack_controller.gd
  player_presentation_ack_participant_resolver.gd
  player_presentation_ack_runtime.gd
  player_task_channel.gd
  player_speech_output.gd
  human/
    human_player_controller.gd
  ai/
    ai_player_controller.gd
  werewolf/
    human/
      werewolf_human_player_factory.gd
      werewolf_human_player_interaction_controller.gd
      werewolf_human_player_state_controller.gd
      werewolf_human_player_task_controller.gd
    ai/
      werewolf_ai_player_factory.gd
      ai_werewolf_*.gd
  xiangqi/
    human/
      xiangqi_human_player_factory.gd
      xiangqi_human_player_interaction_controller.gd
      xiangqi_human_player_task_controller.gd
    ai/
      xiangqi_ai_player_factory.gd
      ai_xiangqi_*.gd
```

`scripts/room/room_runtime.gd` 仍属于房间模块，因为它维护房间人数、准备、换座、加机器人等房间级规则，不归玩家模块。当前狼人杀真人行动任务状态、结果 payload、目标确认、发言编辑、名字编辑、座位详情、头像旁白开关视图和真人玩家本地状态结果已收敛到 `scripts/player/werewolf/human/`；房间页面保留座位点击、网络请求、房间状态刷新和游戏推进桥接。

## 维护规则

- 玩家模块只保存通用玩家资料、运行时绑定、玩家侧通道状态、玩家临时数据和恢复材料，不写玩法身份、阵营和行动记录。
- 玩家级可信通道只处理玩家请求投递、ack、去重、补发和恢复，不实现底层传输或认证。
- 玩家临时数据只保存玩家可见数据和恢复所需材料，过期、退出、房间关闭时必须清理。
- `owner_type` 和 `controller_type` 表达控制来源和行为入口，不承载房间权限或玩法身份。
- `bot_id` 是引用，不把机器人档案、模型配置、声音配置或记忆数据复制进玩家资料。
- 玩家行为结果必须交给具体游戏玩家适配层和具体游戏房间模块校验，不能直接修改房间或游戏状态。
- 公开文本进入 TTS 前必须已经被房间、具体游戏房间模块或玩法适配层接受，并且调用方必须传入音色 ID。
- TTS 播放失败不应影响具体游戏房间推进、房间历史或机器人记忆更新。
- 玩家基础字段、通道字段或恢复字段变更时，同步房间快照、重连恢复、狼人杀真人/AI 玩家模块和 UI 展示。
