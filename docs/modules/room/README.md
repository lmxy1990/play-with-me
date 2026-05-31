# 房间模块

更新时间：2026-05-16

房间模块是大编织模块，负责桌游房间运行容器、房间级权威承载和数据同步机制。它回答“多人如何进入同一个游戏容器，房间如何收集参与者和玩家数据，如何向玩家发起交互请求，如何按可见性广播和保存临时历史，并在断线、重连、主机重选、主机接管和销毁期间保持一致状态”。

房间模块是通用 `RoomSession` 运行容器：它消费基础能力、基础模块和小编织模块的结果，维护参与者、席位、生命周期、玩家消息 inbox、可见历史、真人副本和网络同步边界；它不实现底层 socket、二维码、扫码、加密、证书认证、设备身份或通用认证，也不解释具体游戏房间 payload。

当前具体游戏房间模块是 [狼人杀房间模块](werewolf/README.md)。狼人杀房间只是具体游戏房间的一种；后续三国杀房间、围棋房间、象棋房间和麻将房间都应在同一个通用房间框架内实现自己的地图、人数、场景槽位、内部编排、特效请求、事件 payload、可见性语义和玩家适配。Socket / WebSocket 传输、二维码生成、扫码、加密协商、证书认证和设备认证属于 [基础能力模块](../base/README.md)，其中二维码、扫码、加密和认证链路见 [基础能力专题](../base/qr_scan_join.md)；房间模块只消费这些结果来完成加入、观战、消息编排和重连编排。

跨模块对象 `RoomSummary`、`RoomJoinRequest`、`RoomSnapshot`、`RoomEventEnvelope`、`PlayerMessageInbox`、`TemporaryGameDataEnvelope`、`RoomReplicaFrame`、`HostElectionResult` 的字段权威见 [跨模块契约](../../contracts/README.md)。本文只描述房间模块如何生产、消费和编排这些对象。

## 模块定位

```text
基础能力：路由 / 通用网络 / Socket / WebSocket / 二维码 / 扫码 / 加密 / 证书认证 / 设备认证 / 持久化
大厅 / 创建房间 / 扫码入口 / 重连入口
  -> 房间模块
       -> 房间容器状态
       -> 参与者、玩家座位、观察者
       -> 加入和观战策略
       -> 房间快照和临时数据下发
       -> 玩家 inbox 和可见历史下载
       -> 真人玩家副本备份
       -> 断线重连
       -> 主机重新选取
       -> 游戏房间模块接入点
            -> 狼人杀房间模块
            -> 后续三国杀房间 / 围棋房间 / 象棋房间 / 麻将房间
```

房间模块是公共房间能力、玩家交互编排和网络同步边界。具体地图、场景、槽位布局、内部编排、事件 payload、特效请求、玩家行动解释、胜负判断和游戏阶段推进不放在通用房间模块里，而是委派给具体游戏房间模块。

## 功能点锁定

房间模块只拥有“房间容器”和“房间级编排”能力。凡是通用传输、安全、扫码、加密、证书或设备认证能力，都归基础能力；凡是具体玩法、地图、人数、场景槽位、内部编排、特效请求和消息业务内容，都归具体游戏房间模块。

| 功能点 | 权威归属 | 房间模块做什么 | 房间模块不做什么 |
| --- | --- | --- | --- |
| 房间生命周期 | 房间模块 | 维护 `created`、`open`、`playing`、`reconnecting`、`host_handover`、`ended`、`closed` 及转换策略。 | 不用具体游戏阶段替代房间生命周期。 |
| 参与者、座位、观察者 | 房间模块 | 维护参与者注册、座位占用、观察者、在线状态、重连 token 和容量策略。 | 不判断狼人杀身份、三国杀手牌、围棋棋子等玩法状态。 |
| 加入、观战、重连策略 | 房间模块 | 在基础认证成功后，校验密码、加入 token、容量、生命周期、座位和观战策略。 | 不实现设备认证、证书校验、签名校验、二维码解密。 |
| Socket / WebSocket 传输 | 基础能力 | 通过基础能力暴露的传输接口发送请求、广播快照、接收消息和处理断线信号。 | 不自己实现 socket、证书链、TLS、底层连接握手或通用编解码。 |
| 证书认证和设备身份 | 基础能力 | 消费基础能力给出的认证结果，并把结果纳入加入、重连和主机候选策略。 | 不生成证书、不保存私钥、不校验证书链、不实现设备签名算法。 |
| 房间消息发送、广播、应答 | 房间模块 + 基础能力 | 基于基础传输能力实现房间级 `send`、`broadcast`、`ack`、补发、去重、顺序号和 inbox。 | 不绕过基础传输直接操作底层 socket；不解释具体玩法 payload。 |
| 房间消息格式外壳 | 房间模块 | 维护 `RoomEventEnvelope`、`sequence`、`visibility`、`snapshot_version`、`host_epoch`、ack 和历史下载。 | 不把具体游戏 payload 写死到房间通用结构里。 |
| 房间消息业务内容 | 具体游戏房间模块 | 房间只接收并包装具体游戏房间模块返回的 `payload`、可见性和事件类型。 | 不定义狼人杀夜晚结果、麻将吃碰杠胡、象棋将军等业务字段。 |
| 玩家侧通道与临时数据 | 玩家模块 | 房间传入座位、连接、认证摘要和在线状态，调用玩家模块投递玩家行为请求、玩家可见通知和恢复数据。 | 不在房间模块内实现玩家级通道、玩家级 ack、玩家临时数据队列或玩家恢复帧。 |
| 地图、人数、场景槽位和内部编排 | 具体游戏房间模块 | 通过 `get_map_list()`、`get_supported_player_counts()`、`get_scene_slots()` 委派读取并保存展示结果；行动编排和特效请求只消费具体游戏房间模块返回值。 | 不在通用房间层维护某个游戏的地图、人数、布局常量、行动编排或特效判断。 |
| 二维码使用策略 | 房间模块 + 基础能力 | 房间决定二维码承载哪些房间业务字段、玩家码和观战码如何使用；基础能力生成、解析、加密、扫码和认证。 | 不自己生成二维码图片、不实现扫码、不实现二维码密钥协商。 |
| 可见历史、inbox、恢复副本 | 房间模块 | 维护参与者可见事件队列、完整下载、断线补发、真人副本和主机接管材料。 | 不把所有具体游戏私有状态默认下发给所有真人玩家。 |
| 主机重选与接管 | 房间模块 | 基于真人参与者副本、认证结果、版本和任期选主并恢复房间权威端。 | 不改变具体游戏房间模块已经接受的玩法结果。 |

判断规则：

- 如果能力可以被大厅、房间、创建房间、偏好设置或其它业务复用，且不理解房间生命周期和具体玩法，它应放到基础能力。
- 如果能力维护房间容器状态、参与者、座位、生命周期、消息顺序、可见历史、重连或主机重选，它应放到房间模块。
- 如果能力需要理解地图、人数、场景槽位、内部编排、玩家行动、胜负、阶段、特效请求或 payload 业务字段，它应放到具体游戏房间模块。
- 房间模块调用基础能力必须走基础能力公开接口；调用具体游戏房间模块必须走具体游戏房间模块公开接口，不能直接引用对方 internal 实现。

## 能力边界

房间模块负责：

- 创建和维护房间权威状态。
- 管理房间生命周期、房主、房间名、游戏房间模块 ID、座位、参与者和观察者。
- 定义并调用具体游戏房间模块的抽象接口：地图列表、支持人数、场景槽位、游戏输入、特效请求、快照和停止。
- 提供房间基础信息接口：背景图、游戏房间名、地图名、房间人数、观战人数、生命周期、是否可加入。
- 编排加入、观战、扫码加入和重连流程。
- 消费基础能力返回的 socket 连接、扫码、解密、签名、证书认证和设备认证结果。
- 校验房间级策略：协议版本、密码、加入 token、容量、观战策略、生命周期和座位占用。
- 基于基础传输能力实现房间级消息发送、广播、ack、补发、去重和顺序号。
- 为每个参与者构建可见的房间快照。
- 包装并下发具体游戏房间模块产生的临时数据、公开事件和私有视角数据。
- 通过玩家模块建立玩家级可信通道，投递玩家行为请求、玩家可见通知和恢复数据。
- 为每个参与者维护临时消息 inbox，支持断线后按序号补发。
- 提供该参与者可见历史的完整下载能力，用于重连恢复和本地 UI 重建。
- 让真人参与者保存自己可见的房间副本和可参与主机接管的恢复帧。
- 在房主不可达时执行主机重新选取和权威接管。
- 向具体游戏房间模块提供房间上下文、玩家列表和房间事件。
- 在游戏结束或所有真人参与者退出时关闭房间并清理临时历史、副本和恢复数据。

房间模块不负责：

- Socket / WebSocket 底层传输、证书认证、TLS、二维码生成、Android 扫码、加密解密、设备身份和通用认证实现。
- 狼人杀身份、夜晚行动、投票、胜负、阶段推进、地图布局和槽位布局。
- 三国杀出牌结算、围棋提子、象棋将军、麻将吃碰杠胡等具体游戏房间玩法。
- 真人玩家或 AI 机器人玩家如何产生行动结果。
- 玩家级可信通道、玩家临时数据、玩家投递游标和玩家恢复帧的内部实现。
- 机器人记忆、模型调用、模型输出解析。
- TTS 文本转语音实现。
- 大厅列表渲染和创建房间表单 UI。
- 偏好设置、模型配置、声音配置或机器人配置保存。

## 内部实现

房间模块内部建议拆成十一个子系统：

1. 房间状态管理器：维护 `RoomState`、生命周期、展示字段、游戏房间模块引用和快照版本。
2. 参与者注册表：维护参与者、连接、观察者、座位绑定、重连 token 和在线状态。
3. 加入策略处理器：消费基础认证结果，校验密码、token、容量、观战和协议版本。
4. 网络会话编排器：通过基础传输接口启动房主、连接房间、发送请求、广播快照和处理客户端消息；不实现底层 socket 或证书认证。
5. 快照构建器：按参与者、具体玩家、观察者和主机视角构建 `RoomSnapshot`。
6. 房间事件日志：把具体游戏房间模块输出和房间系统事件包装成 `RoomEventEnvelope`，分配单调递增 `sequence` 并去重。
7. 玩家消息 inbox：为每个参与者维护可见事件临时队列，支持 ack、补发和完整下载。
8. 副本备份管理器：把真人参与者可见快照和可接管恢复帧保存为 `RoomReplicaFrame`，用于主机重选和重连。
9. 临时数据分发器：包装具体游戏房间模块事件，按可见性过滤并绑定 `snapshot_version` 和 `host_epoch`。
10. 主机选举器：检测房主不可达，比较副本版本，提升 `host_epoch` 并完成接管。
11. 游戏房间委派器：调用具体游戏房间模块的地图、人数、场景槽位、启动、输入、快照和停止接口。

当前代码仍分散在 `scripts/room/`、`scripts/network/` 和 `scripts/room/werewolf/`。文档先固定设计边界，后续代码可逐步靠近。

## 对外接口

以下接口是设计契约，不要求当前代码函数名完全一致。

```text
get_create_room_catalog(context) -> CreateRoomCatalog
get_game_room_list(context) -> GameRoomOption[]
get_map_list(game_room_id) -> GameRoomMap[]
get_supported_player_counts(game_room_id, map_id) -> int[]
get_scene_slots(game_room_id, map_id, player_count) -> GameRoomSceneSlots
create_room_state(request) -> RoomCreateResult
publish_room(room_id) -> PublishResult
get_room_summary(room_id, viewer_context) -> RoomSummary
join_room(request) -> JoinResult
join_as_observer(request) -> JoinResult
reconnect_room(request) -> ReconnectResult
build_snapshot(room_id, viewer_context) -> RoomSnapshot
append_room_event(room_id, event) -> RoomEventAppendResult
get_player_history(room_id, viewer_context, range) -> PlayerHistoryResult
ack_player_events(room_id, participant_id, sequence) -> PlayerInboxAckResult
publish_temporary_game_data(envelope) -> SnapshotPublishResult
save_room_replica(frame) -> RoomReplicaSaveResult
submit_game_room_input(room_id, input) -> GameRoomUpdateResult
detect_host_unavailable(signal) -> HostHealthResult
elect_host(input) -> HostElectionResult
accept_host_handover(handover) -> HostHandoverResult
close_room(request) -> RoomCloseResult
get_room_debug_state(request) -> RoomDebugResult
```

### get_create_room_catalog

```text
get_create_room_catalog(context) -> CreateRoomCatalog
```

房间模块向创建房间模块提供统一可创建目录。

约定：

- 返回可创建 `GameRoomOption` 列表、每个游戏房间模块的地图列表、每张地图支持的人数列表和展示元数据。
- 创建房间 UI 只能消费该目录，不维护自己的游戏房间、地图、人数、场景或槽位常量。
- 目录不包含具体游戏房间私有状态；地图、人数、场景和槽位含义由对应具体游戏房间模块解释。

### game_room_catalog 接口

```text
get_game_room_list(context) -> GameRoomOption[]
get_map_list(game_room_id) -> GameRoomMap[]
get_supported_player_counts(game_room_id, map_id) -> int[]
get_scene_slots(game_room_id, map_id, player_count) -> GameRoomSceneSlots
```

这些接口是创建房间统一 UI 的数据来源。

约定：

- `get_game_room_list()` 返回可创建的具体游戏房间模块，例如狼人杀房间、三国杀房间、围棋房间、象棋房间和麻将房间。
- `get_map_list(game_room_id)` 返回该游戏房间模块支持的地图；地图对象包含 `map_id`、`map_background`、`rule_text`、`map_name`、`map_scene` 等展示和布局入口数据。
- `get_supported_player_counts(game_room_id, map_id)` 只返回该地图支持的人数列表，不把人数写死在创建房间 UI。
- `get_scene_slots(game_room_id, map_id, player_count)` 返回实际房间场景和槽位列表；通用房间模块只保存和下发结果，不解释具体布局含义。
- 房间模块可以提供默认布局实现，但具体游戏房间模块可以覆盖这些公开接口。

### create_room_state

```text
create_room_state(request) -> RoomCreateResult
```

`RoomCreateRequest`：

| 字段 | 说明 |
| --- | --- |
| `room_name` | 房间名称。 |
| `host_participant` | 房主参与者信息。 |
| `game_room_id` | 游戏房间模块 ID，例如 `werewolf`。 |
| `map_id` | 地图 ID。 |
| `seat_count` | 座位数量。 |
| `password_policy` | 是否需要密码、密码校验材料。 |
| `observer_policy` | 观战开关和人数限制。 |
| `scene_slots` | `GameRoomSceneSlots`，由具体游戏房间模块根据地图和人数生成。 |
| `display_options` | 背景、游戏房间展示名、地图展示名等展示配置。 |
| `game_room_init_options` | 传给具体游戏房间模块的初始化选项。 |

约定：

- 创建后先进入 `created`，网络启动和发布成功后再进入 `open`。
- 房间模块只校验座位数量、观战策略、密码策略、`game_room_id` 是否存在、地图是否属于该游戏房间模块、座位数是否被地图支持，以及 `scene_slots` 是否由同一组 `game_room_id + map_id + seat_count` 得到。
- 具体游戏房间专属参数只透传给对应模块，不在通用房间模块解释。
- `RoomCreateRequest` 只接受本文定义的当前字段；字段不匹配的创建请求直接拒绝。

### get_room_summary

```text
get_room_summary(room_id, viewer_context) -> RoomSummary
```

`RoomSummary` 是大厅、房间顶部栏、二维码编排和重连卡片使用的展示接口。

| 字段 | 说明 |
| --- | --- |
| `room_id` | 房间 ID。 |
| `room_name` | 房间名。 |
| `host_name` | 房主名。 |
| `game_room_id` | 游戏房间模块 ID。 |
| `game_room_display_name` | 游戏房间模块展示名。 |
| `map_id` | 地图 ID。 |
| `map_display_name` | 地图展示名。 |
| `game_room_scene` | 当前地图和人数对应的场景 ID 或路径。 |
| `background` | 背景图或背景 ID。 |
| `lifecycle` | 房间生命周期。 |
| `player_count` / `seat_count` | 玩家人数和总座位。 |
| `observer_count` / `observer_limit` | 观战人数和上限。 |
| `joinable` | 当前是否允许玩家加入。 |
| `observable` | 当前是否允许观战加入。 |
| `requires_password` | 是否需要密码。 |

约定：

- `RoomSummary` 不能包含具体游戏房间私有数据。
- 大厅只消费 `RoomSummary`，不读取完整 `RoomState`。
- 背景图、游戏房间展示名、地图展示名和场景信息可以来自具体游戏房间模块目录元数据，但房间模块只当展示字段处理。
- UI 只使用 `game_room_id`、`game_room_display_name`、`map_id`、`map_display_name` 和 `game_room_scene`。

### join_room

```text
join_room(request) -> JoinResult
join_as_observer(request) -> JoinResult
```

`JoinRequest`：

| 字段 | 说明 |
| --- | --- |
| `room_id` | 目标房间。 |
| `participant` | 加入者设备和展示信息。 |
| `join_mode` | `player` 或 `observer`。 |
| `auth` | 基础能力返回的扫码、连接、解密、证书认证和设备认证结果，以及房间密码或加入 token 等业务凭据。 |
| `client_protocol_version` | 客户端房间协议版本。 |
| `desired_seat_index` | 可选，期望座位。 |

加入校验顺序：

1. 房间存在且未关闭。
2. 协议版本必须匹配当前房间协议。
3. 基础认证结果有效。
4. 房间密码或加入 token 符合策略。
5. 加入来源和房间 ID 匹配。
6. 加入模式符合房间策略。
7. 玩家人数或观战人数未满。
8. 当前生命周期允许加入。
9. 座位可用。
10. 构建并下发参与者视角快照。

常见拒绝码：

| 代码 | 说明 |
| --- | --- |
| `room_not_found` | 房间不存在或已关闭。 |
| `protocol_mismatch` | 房间协议版本不匹配。 |
| `auth_failed` | 基础设备认证失败或签名不匹配。 |
| `qr_expired` | 基础能力返回二维码 secret 失效。 |
| `password_required` | 需要密码但未提供。 |
| `password_invalid` | 密码错误。 |
| `room_full` | 玩家席位已满。 |
| `observer_full` | 观战人数已满。 |
| `observer_disabled` | 房间不允许观战。 |
| `game_already_started` | 当前状态不允许玩家加入。 |
| `seat_unavailable` | 目标座位不可用。 |

### reconnect_room

```text
reconnect_room(request) -> ReconnectResult
```

`ReconnectRequest`：

| 字段 | 说明 |
| --- | --- |
| `room_id` | 房间 ID。 |
| `participant_id` | 原参与者 ID。 |
| `device_id` | 原设备身份。 |
| `reconnect_token` | 加入时发放的重连凭据。 |
| `last_snapshot_version` | 客户端本地最后快照版本。 |
| `client_host_epoch` | 客户端记录的主机任期。 |

约定：

- 重连只能恢复同一设备身份或经过明确授权的设备。
- 重连成功后保留原座位和玩家身份。
- 客户端快照版本落后太多时，下发完整快照。
- 如果房间已经完成主机接管，重连结果必须返回最新 `host_epoch` 和新主机地址。

### build_snapshot

```text
build_snapshot(room_id, viewer_context) -> RoomSnapshot
```

快照必须按接收者视角过滤。

| 字段 | 说明 |
| --- | --- |
| `room` | 房间基础信息。 |
| `participants` | 可见参与者信息。 |
| `players` | 可见座位和玩家基础信息。 |
| `game_room_public_state` | 具体游戏房间公开状态。 |
| `game_room_private_state` | 当前接收者可见的具体游戏房间私有状态。 |
| `history` | 可见历史和公开事件。 |
| `temporary_game_data` | 当前阶段需要下发的临时游戏数据。 |
| `snapshot_version` | 快照版本。 |
| `host_epoch` | 当前主机任期。 |

约定：

- 不把完整游戏房间状态发给所有客户端后依赖 UI 隐藏。
- 玩家私有数据只进入对应玩家快照。
- 观察者只能收到 `observer_safe` 视角。
- 落后 `snapshot_version` 或落后 `host_epoch` 的消息必须丢弃。

### publish_temporary_game_data

```text
publish_temporary_game_data(envelope) -> SnapshotPublishResult
```

`TemporaryGameDataEnvelope`：

| 字段 | 说明 |
| --- | --- |
| `room_id` | 房间 ID。 |
| `game_room_id` | 来源游戏房间模块。 |
| `event_id` | 临时事件 ID，用于去重。 |
| `event_type` | 事件类型，例如阶段提示、可选目标、私有结果、公开公告、展示特效。 |
| `visibility` | `public`、`participants`、`host_only`、`player_private`、`observer_safe`。 |
| `target_participant_ids` | 私有可见目标。 |
| `payload` | 具体游戏房间模块生成的数据，可承载已接受结果对应的特效请求。 |
| `ttl` | 可选，过期策略。 |
| `created_at` | 生成时间。 |

约定：

- 房间模块不解释 `payload` 的玩法语义，只按 `visibility` 过滤。
- 私有数据必须以参与者视角构建，不能先广播再让客户端自行隐藏。
- 可复盘的公开事件应由具体游戏房间模块同时写入历史或复盘数据，不能只存在临时数据里。
- 临时数据只使用 `game_room_id` 标识来源游戏房间模块。

### append_room_event 和 get_player_history

```text
append_room_event(room_id, event) -> RoomEventAppendResult
get_player_history(room_id, viewer_context, range) -> PlayerHistoryResult
ack_player_events(room_id, participant_id, sequence) -> PlayerInboxAckResult
```

`RoomEventEnvelope` 是房间临时历史和同步队列的通用外壳：

| 字段 | 说明 |
| --- | --- |
| `room_id` | 房间 ID。 |
| `game_room_id` | 来源游戏房间模块。 |
| `sequence` | 房间内单调递增序号。 |
| `event_id` | 事件 ID，用于去重。 |
| `event_kind` | 事件类型，由房间或具体游戏房间模块声明。 |
| `visibility` | `public`、`participants`、`player_private`、`host_only`、`observer_safe`。 |
| `target_participant_ids` | 私有可见参与者。 |
| `target_player_ids` | 私有可见玩家。 |
| `payload` | 具体游戏房间模块或房间系统生成的数据，可承载已接受结果对应的特效请求。 |
| `created_at` | 生成时间。 |
| `expires_at` | 临时历史过期时间，可选。 |

约定：

- 房间模块负责 `sequence`、去重、ack、补发、下载、清理和可见性过滤。
- 具体游戏房间模块负责 `payload` 格式和业务语义，房间不解释 `payload`。
- 玩家断线后，重连可通过 `last_seen_sequence` 下载该玩家可见历史。
- 私有事件只进入目标参与者 inbox，不应先广播给所有客户端再隐藏。
- 游戏结束或房间关闭后，临时历史和 inbox 必须清理；复盘数据由具体游戏房间模块显式生成，不等同于房间临时历史。
- 房间事件只使用 `game_room_id` 标识来源游戏房间模块。

### save_room_replica

```text
save_room_replica(frame) -> RoomReplicaSaveResult
```

真人参与者应保存一份房间副本，用于房主不可达时重选主机，也用于原玩家重连恢复。

`RoomReplicaFrame`：

| 字段 | 说明 |
| --- | --- |
| `room_id` | 房间 ID。 |
| `holder_participant_id` | 持有该副本的参与者。 |
| `holder_player_id` | 持有该副本的玩家，可选。 |
| `host_epoch` | 副本对应的房主任期。 |
| `snapshot_version` | 副本对应的快照版本。 |
| `last_event_sequence` | 副本包含的最新事件序号。 |
| `room_summary` | 可用于重连卡片的房间摘要。 |
| `viewer_snapshot` | 持有者可见的快照。 |
| `recovery_payload` | 可选的主机接管恢复数据，由具体游戏房间模块决定内容。 |
| `created_at` | 副本生成时间。 |

约定：

- 普通真人玩家副本默认只保存自己可见的数据和房间恢复所需摘要。
- 是否允许副本包含完整游戏恢复数据，由具体游戏房间模块和安全策略决定。
- 隐藏信息游戏不能把所有私密游戏状态明文下发给所有真人玩家。
- 主机重选选择副本版本最高且参与者仍可信的真人玩家作为候选。

### elect_host

```text
detect_host_unavailable(signal) -> HostHealthResult
elect_host(input) -> HostElectionResult
accept_host_handover(handover) -> HostHandoverResult
```

房主重选只改变房间权威所在设备，不改变具体游戏房间模块状态。

候选排序建议：

1. 在线且有有效基础认证结果。
2. 持有最高 `snapshot_version` 的房间副本。
3. 原本就是玩家而非观察者。
4. 连接质量更稳定。
5. 参与者 ID 或加入顺序作为稳定排序键。

约定：

- 主机重选期间房间进入 `host_handover`。
- 暂停新的加入、观战和具体游戏房间推进。
- 新主机必须提升 `host_epoch`。
- 原主机恢复后如果任期落后，只能作为普通参与者重连。

### 游戏房间模块接口

房间模块只认识具体游戏房间模块的公开接口，不认识狼人杀、三国杀、围棋、象棋或麻将的内部实现。

```text
load_game_room_module(game_room_id) -> GameRoomModule
get_map_list() -> GameRoomMap[]
get_supported_player_counts(map_id) -> int[]
get_scene_slots(map_id, player_count) -> GameRoomSceneSlots
start_game_room(room_context, game_room_options) -> GameRoomStartResult
submit_game_room_input(room_context, input) -> GameRoomUpdateResult
build_game_room_snapshot(room_context, viewer_context) -> GameRoomSnapshot
stop_game_room(room_context, reason) -> GameRoomStopResult
```

具体游戏房间模块返回：

| 字段 | 说明 |
| --- | --- |
| `game_room_state` | 具体游戏房间权威状态或状态补丁。 |
| `public_events` | 公开事件。 |
| `private_events` | 私有事件和可见目标。 |
| `history_entries` | 房间历史文本。 |
| `temporary_game_data` | 需要下发的临时数据。 |
| `effect_requests` | 具体游戏房间模块接受结果后产生的展示特效请求。 |
| `room_display_patch` | 可选，更新房间展示字段。 |
| `game_over` | 是否结束。 |

约定：

- 具体游戏房间模块的实现必须放在自己的模块目录内；对外只暴露上述接口。
- 房间模块编排这些接口，但不能直接引用具体模块的 internal 状态机、校验器、目录常量或场景布局实现。
- 狼人杀房间模块可以覆盖地图、人数、场景槽位、快照、可见性和恢复数据实现；其它游戏房间模块按同一接口接入。

## 核心对象

### RoomState

房间权威状态，描述房间是什么、谁在里面、当前处于什么生命周期。

| 字段 | 说明 |
| --- | --- |
| `room_id` | 房间唯一 ID。 |
| `room_name` | 房间展示名称。 |
| `host_participant_id` | 当前房主参与者 ID。 |
| `host_device_id` | 当前房主设备身份。 |
| `game_room_id` | 游戏房间模块 ID。 |
| `game_room_version` | 游戏房间模块协议版本。 |
| `map_id` | 当前地图 ID。 |
| `scene_slots` | 当前地图和人数对应的场景与槽位布局。 |
| `lifecycle` | 房间生命周期。 |
| `players` | 座位上的玩家基础数据。 |
| `participants` | 参与者注册表。 |
| `observers` | 观察者注册表或计数。 |
| `observer_policy` | 观战策略。 |
| `auth_policy` | 加入策略。 |
| `display` | 背景图、游戏房间名、地图名、人数文案等展示字段。 |
| `game_room_state_ref` | 具体游戏房间模块状态引用或摘要。 |
| `last_event_sequence` | 房间事件日志最新序号。 |
| `snapshot_version` | 房间快照版本，单调递增。 |
| `host_epoch` | 主机任期，主机重选或接管时递增。 |
| `created_at` / `updated_at` | 创建和更新时间。 |

字段规则：

- `RoomState` 只保存当前房间契约字段：`game_room_id`、`game_room_version`、`map_id`、`scene_slots` 和 `game_room_state_ref`。
- 不符合当前结构的房间状态直接丢弃，不进入恢复或创建流程。

### Participant

参与者是连接到房间的人或设备，不等同于座位上的玩家。

| 字段 | 说明 |
| --- | --- |
| `participant_id` | 房间内参与者 ID。 |
| `device_id` | 设备身份。 |
| `display_name` | 展示名。 |
| `role` | `host`、`participant`、`observer`。 |
| `connection_state` | `online`、`offline`、`reconnecting`、`left`。 |
| `seat_index` | 绑定座位；观察者为空。 |
| `reconnect_token` | 重连凭据。 |
| `last_seen_at` | 最近在线时间。 |

### RoomRuntimeState

临时运行时状态，可以重建，不应作为长期业务数据依赖。

| 字段 | 说明 |
| --- | --- |
| `network_endpoint` | 当前房主 WebSocket 地址。 |
| `lan_advertise_state` | 局域网发布状态。 |
| `qr_secrets` | 当前二维码 secret 引用或运行时材料。 |
| `connection_registry` | peer、participant、observer 的连接映射。 |
| `pending_join_requests` | 等待认证或房间策略校验的加入请求。 |
| `reconnect_window` | 可重连窗口和过期时间。 |
| `event_log` | 临时房间事件日志。 |
| `player_inboxes` | 按参与者保存的可见事件队列。 |
| `room_replica` | 客户端保存的最近快照副本。 |
| `replica_frames` | 真人参与者上报或本机保存的恢复帧摘要。 |
| `host_election_state` | 主机选举候选、任期和结果。 |

### PlayerMessageInbox

按参与者保存的临时可见消息队列。

| 字段 | 说明 |
| --- | --- |
| `participant_id` | 队列所属参与者。 |
| `player_id` | 绑定玩家，可选。 |
| `last_delivered_sequence` | 已投递到本地的最新事件序号。 |
| `last_ack_sequence` | 客户端已确认处理的最新事件序号。 |
| `pending_events` | 等待补发或下载的 `RoomEventEnvelope`。 |
| `created_at` / `updated_at` | 创建和更新时间。 |

约定：

- inbox 是房间临时运行数据，不是长期复盘数据。
- 玩家本地 UI 可以从 inbox 或可见历史下载重建历史面板。
- 游戏结束、玩家明确退出且不需要重连、或房间关闭时，应清理对应 inbox。

## 生命周期状态机

房间生命周期只描述房间容器状态，不描述狼人杀阶段。

```text
created
  -> open
  -> playing
  -> ended
  -> closed

open / playing
  -> reconnecting
  -> host_handover
  -> open / playing

任意状态
  -> closed
```

| 状态 | 说明 | 可加入 | 可观战 | 可重连 |
| --- | --- | --- | --- | --- |
| `created` | 房间状态已创建，网络和发布未完成。 | 否 | 否 | 否 |
| `open` | 房间已发布，等待玩家加入或准备。 | 是 | 按策略 | 是 |
| `playing` | 具体游戏房间模块已经开始执行。 | 通常否 | 按策略 | 是 |
| `reconnecting` | 房主仍存在，但参与者正在恢复连接。 | 否 | 否 | 是 |
| `host_handover` | 房主不可达，正在主机重选和接管。 | 否 | 否 | 是 |
| `ended` | 游戏结束，房间仍可查看历史或复盘。 | 否 | 按策略 | 是 |
| `closed` | 房间关闭，不再接受任何请求。 | 否 | 否 | 否 |

销毁规则：

- 游戏结束后，房间可以短暂保留复盘入口，但临时历史、inbox、二维码 secret 和恢复副本应按策略清理。
- 真人玩家可以选择退出或重连；退出后对应参与者状态进入 `left`，并清理其私有 inbox。
- 当所有真人参与者都退出或不可恢复，房间自动进入 `closed`；因为没有真人副本支撑，也没有主机承载该房间。
- AI 机器人玩家不能单独维持房间存在，除非后续明确设计独立服务器或本地托管主机。

## 主要流程

### 创建并发布房间

```text
创建房间模块提交 RoomCreateRequest
  -> 房间模块创建 RoomState(created)
  -> 初始化座位、参与者、加入策略、game_room_id、地图和场景槽位元数据
  -> 启动房主网络
  -> 发布局域网发现
  -> RoomState 进入 open
  -> 返回 RoomSummary 和创建结果
```

### 扫码加入

```text
基础能力生成房间二维码
  -> 客户端在大厅调用基础扫码能力
  -> 基础能力返回扫码、socket 连接、证书认证、设备认证、密钥协商和解密结果
  -> 房间模块消费基础结果并提交 JoinRequest
  -> 房主执行房间策略校验
  -> 成功则创建 Participant、分配座位、发放 reconnect_token
  -> 下发参与者视角 RoomSnapshot
```

### 游戏临时数据下发

```text
具体游戏房间模块产生状态变化
  -> 返回 game_room_state / public_events / private_events / temporary_game_data / effect_requests
  -> 房间模块封装 RoomEventEnvelope 并分配 sequence
  -> 按 visibility 写入各参与者 PlayerMessageInbox
  -> 房间模块更新 snapshot_version
  -> 按 viewer_context 构建 RoomSnapshot
  -> 玩家收到参与者视角
  -> 观察者收到 observer_safe 视角
```

### 可见历史下载

```text
玩家断线或本地 UI 需要恢复历史
  -> 提交 participant_id、last_seen_sequence 和当前 host_epoch
  -> 房间校验参与者身份和重连 token
  -> 从 event_log / PlayerMessageInbox 过滤该参与者可见事件
  -> 返回完整可见历史或增量事件
  -> 客户端 ack 最新 sequence
```

房间模块只保证“该参与者能拿到自己可见的事件序列”。事件里的业务字段、隐藏信息脱敏和复盘公开范围由具体游戏房间模块决定。

### 玩家指令与主机处理

```text
具体游戏房间模块生成行动请求
  -> 具体游戏玩家适配层转换成 PlayerActionRequest
  -> 玩家模块经 PlayerTrustedChannel 投递给真人、AI 或托管控制器
  -> 玩家控制器返回 PlayerActionResult
  -> 主机端房间程序交回具体游戏玩家适配层
  -> 具体游戏房间模块校验并返回更新结果
  -> 房间模块同步事件、临时数据、特效请求和快照
```

房间模块只负责玩家通道编排、主机权威投递、事件同步和快照包装。具体游戏房间模块决定玩家回复是否被接受、播放何种特效、是否推进阶段以及下一步下发什么行动请求。

### 断线重连

```text
参与者断线
  -> 标记 offline，保留座位和 reconnect_token
  -> 客户端回大厅展示重连卡
  -> 客户端提交 ReconnectRequest
  -> 房主校验 device_id、token、host_epoch
  -> 下发最新完整快照或增量恢复
```

### 主机重新选取

```text
参与者检测房主不可达
  -> 冻结房间进入 host_handover
  -> 收集真人参与者候选者和 RoomReplicaFrame
  -> elect_host()
  -> 新主机提升 host_epoch
  -> 基于最高可信副本恢复 RoomState、event_log 和游戏房间恢复数据
  -> 新主机恢复网络监听
  -> 广播 host_handover
  -> 参与者按新地址重连
  -> 房间回到 open 或 playing
```

## 可见性规则

房间模块必须保证服务端过滤优先：

- 公开房间信息可以给所有参与者和观察者。
- 玩家私有数据只给对应玩家。
- 主机内部数据只留在主机，不下发给客户端。
- 观察者只能收到 `observer_safe` 视角。
- 游戏已结束后，具体游戏房间模块可以通过复盘接口公开更多信息，但必须显式返回。

## 失败与降级

| 场景 | 策略 |
| --- | --- |
| 创建后网络启动失败 | 回到 `created` 或关闭房间，返回 error。 |
| 局域网发布失败 | 房间可本机运行，返回 warning。 |
| 加入认证失败 | 拒绝加入，不创建参与者。 |
| 客户端协议版本不匹配 | 拒绝加入或禁用大厅动作。 |
| 快照版本冲突 | 丢弃落后版本，必要时下发完整快照。 |
| 参与者断线 | 标记 `offline`，保留重连窗口。 |
| 房主不可达 | 进入 `host_handover`，执行主机重选。 |
| 无可用主机候选 | 保留本地副本，返回大厅重连入口。 |
| 所有真人参与者退出 | 自动关闭房间并清理临时历史和副本。 |
| 具体游戏房间模块返回错误 | 不提交状态补丁，返回可展示错误。 |

## 只读调试

```text
get_room_debug_state(request) -> RoomDebugResult
```

只读调试信息建议包含：

- 当前 `room_id`、`lifecycle`、`snapshot_version`、`host_epoch`。
- 房主参与者和设备摘要。
- 参与者、观察者和连接状态。
- 加入策略摘要，不包含密码明文、token 明文或二维码 secret。
- 最近一次快照构建结果和临时数据分发结果。
- 最近事件序号、inbox 积压数量和历史清理状态。
- 房间副本持有者、最高副本版本和恢复能力摘要。
- 主机选举状态和候选摘要。
- 当前游戏房间模块 ID、地图 ID、场景槽位摘要和游戏房间状态摘要。

调试接口不得修改房间状态，不得输出认证 secret、重连 token 明文或具体游戏房间私有数据。

## 与其它模块的关系

| 模块 | 房间模块如何交互 |
| --- | --- |
| 基础能力 | 使用路由、通用网络信封、Socket / WebSocket 传输、二维码生成、扫码、加密、证书认证、设备身份、认证和持久化基础；只消费结果，不复制实现。 |
| 大厅模块 | 提供 `RoomSummary`、重连卡片信息和进入房间入口。 |
| 创建房间模块 | 向其提供可创建游戏房间目录、地图、支持人数、场景槽位；接收其提交的 `RoomCreateRequest`，生成房间权威状态并启动运行时。 |
| 玩家模块 | 管理通用玩家资料、运行时绑定、玩家级可信通道、玩家临时数据、恢复材料、玩家行为控制器入口和公共 TTS 文本转语音接口；房间向玩家模块传入座位、连接、认证摘要和在线状态，并通过它向真人、远程真人、AI 或托管玩家发起交互；房间调用玩家模块播报时必须传入音色 ID。 |
| 狼人杀房间模块 | 作为当前具体游戏房间模块接入，负责狼人杀地图、人数、场景槽位、状态、事件 payload、可见性语义、特效请求和玩法执行。 |
| 象棋房间模块 | 作为新增具体游戏房间模块接入，负责象棋地图、2 人座位、竖版棋盘布局、权威局面、走法校验、回合推进、胜负与和棋、聊天触发和复盘。 |
| 狼人杀真人玩家模块 | 狼人杀房间模块需要真人行动时，由该模块把请求转换成人能操作的输入并返回统一行动结果；主机只路由玩家设备任务。 |
| 狼人杀 AI 玩家模块 | 狼人杀房间模块需要 AI 行动时，由控制设备本机读取机器人档案和模型配置，构建上下文并返回统一行动结果。 |
| 象棋真人玩家模块 | 象棋房间模块需要真人行动时，由该模块把走棋、求和、悔棋、认输和聊天请求转换成人能操作的输入并返回统一行动结果。 |
| 象棋 AI 玩家模块 | 象棋房间模块需要 AI 行棋时，由控制设备本机读取机器人档案和模型配置生成结构化走法；真人发言被接受后才生成聊天回应。 |
| 机器人/RAG 模块 | 房间不直接调用；AI 玩家行动时通过具体游戏 AI 玩家模块调用。 |
| 模型管理模块 | 房间不直接调用；控制 AI 玩家的设备在具体游戏 AI 玩家模块内部调用。 |
| TTS 语音模块 | 房间可产生已接受历史文本，播放由玩家/TTS 边界处理。 |

## 文件归属

当前相关代码：

```text
scripts/room/
  room_runtime.gd
  room_session_store.gd

scripts/player/
  player_factory.gd

scripts/room/network/
  room_network_session.gd
  room_network_snapshot_builder.gd
  room_participant_registry.gd
  room_replica.gd
  host_election.gd

scripts/room/werewolf/
  werewolf_room_lifecycle_page_flow.gd
  werewolf_room_table_page_flow.gd
  werewolf_room_create_page_flow.gd
  werewolf_room_progress_page_flow.gd
  werewolf_room_bot_page_flow.gd
  werewolf_room_overlay_page_flow.gd
  werewolf_room_interaction_page_flow.gd
  werewolf_room_page.gd

scripts/room/xiangqi/
  xiangqi_room_page.gd
  xiangqi_room_page_state.gd
  xiangqi_engine.gd
  xiangqi_board.gd
  xiangqi_move_validator.gd
  xiangqi_room_table_page_flow.gd
```

基础能力相关文件被房间编排调用，但设计归属不在房间模块：

```text
scripts/network/qr_join_payload.gd
scripts/ui/qr/qr_code_generator.gd
scripts/ui/qr/qr_scan_join_ui.gd
```

## 维护规则

- 房间通用逻辑不写具体狼人杀阶段判断。
- 房间通用逻辑不写具体三国杀、围棋、象棋或麻将玩法判断。
- 所有会改变房间状态的动作必须经过房主或新主机权威校验。
- 房间快照必须区分参与者、具体玩家、观察者和主机视角。
- 房间事件必须先由房间分配 `sequence`，再进入玩家 inbox、历史下载和副本。
- 玩家历史下载只返回该参与者可见事件，不能泄露其它玩家私有数据。
- 真人玩家副本默认只能保存自己可见数据；完整恢复数据必须由具体游戏房间模块和安全策略显式允许。
- 房间加入策略、重连和主机选举字段变化时，同步网络消息、快照、基础二维码/认证专题和测试。
- 玩家通道、玩家临时数据或玩家恢复材料变化时，同步玩家模块、跨模块契约和具体游戏玩家适配层。
- Socket / WebSocket 传输、二维码字段、扫码 UI、加密协商、证书认证和设备认证本身在基础能力文档维护，房间文档只说明如何消费这些结果。
- 游戏临时数据下发必须绑定 `snapshot_version` 和 `host_epoch`。
- 具体游戏房间模块只能通过房间公开接口影响房间展示、历史和生命周期。
- 主机重选期间暂停新的加入、观战和具体游戏房间推进。
- 房间基础信息接口只暴露展示所需字段，不泄露具体游戏房间私有状态。
- 所有真人参与者退出后，房间应自动关闭并清理临时历史、inbox、副本和重连材料。

