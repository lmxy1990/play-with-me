# 跨模块契约

更新时间：2026-05-21

本文固定 Play With Me 模块之间的调用契约。模块内部可以继续重构，但跨模块只通过本文定义的数据对象、请求结果和可见性约定交互。

工程目录说明文件放在哪里，模块文档说明能力属于谁，本文说明“模块之间传什么、谁负责生成、谁负责校验、谁不能越界解释”。

## 适用范围

本文覆盖这些跨模块边界：

- 基础能力到大厅、创建房间和房间：二维码、扫码、加密、设备身份、认证结果。
- 房间到大厅：房间摘要、发现摘要、重连入口数据。
- 房间到创建房间：可创建游戏房间目录、地图列表、支持人数列表和场景槽位列表。
- 创建房间到房间：统一房间创建请求。
- 房间到具体游戏房间模块：房间上下文、地图、场景槽位、游戏快照、临时游戏数据。
- 狼人杀房间模块到狼人杀真人/AI 玩家模块：行动请求和行动结果。
- 狼人杀 AI 玩家模块到机器人/RAG：通用可见上下文和通用记忆更新。
- 狼人杀 AI 玩家模块到模型管理：一次模型输入输出请求。
- 房间和玩家模块之间：玩家级可信通道、玩家任务通道、玩家临时数据和断联恢复帧。
- 玩家模块到 TTS：已确认文本播报请求，音色 ID 由调用方传入。
- 房间到网络副本：房间快照、主机任期、主机接管和重连恢复。

不在本文定义的内容：

- 具体 Godot 类名、文件名和函数名。
- Android 插件内部数据库表。
- 狼人杀房间模块内部状态的全部字段。
- 机器人记忆模块内部存储表、索引、合并算法。
- 模型供应商私有请求体。

## 通用约定

### 字段命名

跨模块数据使用 `snake_case`。基础能力接收到的外部协议字段必须先转换为本文定义的字段；不能把外部字段名直接传给业务模块。

稳定 ID 不随展示名变化：

| 字段 | 说明 |
| --- | --- |
| `room_id` | 房间 ID。 |
| `participant_id` | 房间参与者 ID，包含玩家和观察者。 |
| `player_id` | 通用玩家 ID。 |
| `bot_id` | 机器人/RAG 模块中的机器人 ID。 |
| `model_profile_name` | 模型配置稳定引用名。 |
| `voice_profile_id` | 声音配置或音色稳定引用 ID，由播报调用方传入。 |
| `turn_id` | 一次游戏房间行动请求 ID。 |
| `event_id` | 房间、具体游戏房间模块或临时数据事件 ID。 |
| `request_id` | 一次跨模块请求 ID。 |
| `snapshot_version` | 房间快照版本，单调递增。 |
| `host_epoch` | 房主任期，主机重选或接管时递增。 |

### 请求对象

跨模块请求建议包含：

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `schema_version` | 是 | 当前请求结构版本。 |
| `request_id` | 是 | 请求 ID，用于去重、追踪和调试。 |
| `source_module` | 是 | 调用来源，例如 `lobby`、`room`、`werewolf_player`。 |
| `scope` | 否 | 运行时作用域，例如房间、会话、玩家。 |
| `payload` | 否 | 具体业务载荷。 |
| `metadata` | 否 | 调试和扩展字段；不得承载必须被下游理解的核心语义。 |

### 结果对象

跨模块结果建议包含：

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `ok` | 是 | 是否成功。 |
| `request_id` | 否 | 对应请求 ID。 |
| `result` | 否 | 成功结果。 |
| `warnings` | 否 | 非致命问题。 |
| `error` | 否 | 失败时的结构化错误。 |
| `metadata` | 否 | 调试和扩展字段。 |

`error` 结构：

| 字段 | 说明 |
| --- | --- |
| `code` | 稳定错误码，例如 `auth_failed`、`room_full`、`invalid_action`。 |
| `message` | 可展示的简短错误说明。 |
| `transient` | 是否建议调用方再次发起。 |
| `details` | 结构化详情，默认不含敏感字段。 |

### 可见性

可见性是硬边界。上游必须先过滤，下游可以做防线式校验，但不能依赖 UI 隐藏敏感字段。

| 值 | 说明 |
| --- | --- |
| `public` | 所有人可见，可进入公开历史和公开播报。 |
| `participants` | 房间参与者可见，不含观察者。 |
| `observer_safe` | 观察者安全视角，不含隐藏身份和私密结果。 |
| `player_private` | 指定玩家私有。必须带 `target_player_ids` 或等价字段。 |
| `private_local` | 仅本机可见或仅本机播放，例如私密 TTS。 |
| `host_only` | 仅当前房主处理。 |
| `replay` | 复盘视角，必须由规则或房间在允许复盘后生成。 |
| `debug_only` | 调试视角，只允许 debug 环境读取。 |

禁止规则：

- 隐藏身份、私密夜晚结果、未公开私聊不得进入 `public`、`participants` 或 `observer_safe`。
- 当前机器人不可见的信息不得进入 `BotVisibleContext`。
- 当前机器人不可见的信息不得进入 `memory_update`。
- 模型草稿、未确认 UI 输入、具体游戏房间模块拒绝结果不得进入记忆或 TTS。
- TTS 只能消费已确认文本，不负责判断文本能否公开。

## 基础能力契约

基础能力只提供二维码、扫码、加密、设备身份和认证能力。大厅、创建房间和房间消费这些结果，但不复制实现。

### DeviceIdentityView

设备身份的只读公开视图。

| 字段 | 说明 |
| --- | --- |
| `device_id` | 从设备公钥派生出的稳定设备 ID。 |
| `public_key` | 设备公钥。 |
| `key_algorithm` | 例如 `RSA-2048`。 |
| `created_at` | 本机身份首次创建时间，可选。 |
| `fingerprint` | 公钥指纹，用于用户确认。 |

约定：

- `device_private_key` 只存在偏好设置 JSON 和基础能力内部读取路径，不进入 `DeviceIdentityView`。
- 日志、错误提示、房间广播和调试接口不得输出设备私钥。

### QrJoinPayload

二维码加入载荷由基础能力构建和解析。房间模块只提供需要写入二维码的业务字段。

| 字段 | 明文/密文 | 说明 |
| --- | --- | --- |
| `app` | 明文 | 应用标记。 |
| `version` | 明文 | 二维码格式版本。 |
| `format` | 明文 | 例如 `lan_join_secure`。 |
| `host` / `port` | 明文 | 扫码前连接房主所需地址。 |
| `secret_id` | 明文 | 查找二维码 AES 密钥。 |
| `alg` / `key_exchange` | 明文 | 加密和密钥协商算法。 |
| `iv` / `cipher` / `mac` | 明文 | 解密和完整性校验材料。 |
| `room_id` | 密文 | 目标房间 ID。 |
| `room_name` | 密文 | 房间名。 |
| `join_mode` | 密文 | `player` 或 `observer`。 |
| `join_token` | 密文 | 房间加入 token，可选。 |
| `host_device_id` | 密文 | 房主设备 ID。 |
| `host_public_key` | 密文 | 房主设备公钥。 |
| `game_room_id` | 密文 | 游戏房间模块 ID，例如 `werewolf`。 |
| `game_room_display_name` | 密文 | 游戏房间模块展示名。 |
| `map_id` | 密文 | 地图 ID。 |
| `game_room_scene` | 密文 | 当前地图和人数对应的场景 ID 或路径。 |
| `background` | 密文 | 背景图 ID 或路径。 |
| `network_protocol_version` | 密文 | 房间网络协议版本。 |

约定：

- 二维码明文只放扫码前必须读取的信息。
- 密文字段解密和校验完成后，转换成 `RoomJoinAuthBundle` 交给房间模块。
- 房间密码、加入 token 和观战策略是否有效，由房间模块判断。

### RoomJoinAuthBundle

基础能力完成扫码、连接、设备认证和二维码解密后，交给房间模块的认证材料。

| 字段 | 说明 |
| --- | --- |
| `auth_ok` | 基础认证是否通过。 |
| `auth_stage` | 当前阶段，例如 `scanned`、`connected`、`device_verified`、`qr_decrypted`。 |
| `client_identity` | 扫码端 `DeviceIdentityView`。 |
| `host_identity` | 房主 `DeviceIdentityView`。 |
| `room_id` | 解密出的房间 ID。 |
| `join_mode` | `player` 或 `observer`。 |
| `join_token` | 解密出的加入 token，可选。 |
| `network_protocol_version` | 解密出的协议版本。 |
| `address` | 已校验地址。 |
| `signature_verified` | 设备签名是否校验通过。 |
| `qr_secret_verified` | 二维码密钥和 MAC 是否校验通过。 |
| `error` | 基础能力失败时的结构化错误。 |

约定：

- `RoomJoinAuthBundle` 只证明“二维码和设备认证基础有效”，不代表房间允许加入。
- 房间模块仍要校验容量、密码、生命周期、座位和观战策略。

## 房间和大厅契约

### RoomSummary

`RoomSummary` 是大厅、创建结果页、房间顶部栏、扫码处理中页面和重连卡片使用的展示摘要。

| 字段 | 说明 |
| --- | --- |
| `schema_version` | 摘要结构版本。 |
| `room_id` | 房间 ID。 |
| `room_name` | 房间名。 |
| `host_participant_id` | 房主参与者 ID。 |
| `host_name` | 房主展示名。 |
| `game_room_id` | 游戏房间模块 ID。 |
| `game_room_display_name` | 游戏房间模块展示名。 |
| `map_id` | 地图 ID。 |
| `map_display_name` | 地图展示名。 |
| `game_room_scene` | 当前地图和人数对应的场景 ID 或路径。 |
| `background` | 背景图 ID 或路径。 |
| `lifecycle` | `created`、`open`、`in_game`、`closed` 等。 |
| `player_count` | 当前玩家数。 |
| `seat_count` | 座位总数。 |
| `observer_count` | 当前观察者数。 |
| `observer_limit` | 观察者上限。 |
| `joinable` | 当前是否允许玩家加入。 |
| `observable` | 当前是否允许观战。 |
| `requires_password` | 是否需要密码。 |
| `host_epoch` | 当前房主任期。 |
| `snapshot_version` | 摘要对应的快照版本。 |
| `source` | `local_host`、`lan_discovery`、`reconnect_cache`、`joined_room`。 |
| `metadata` | 展示扩展字段。 |

约定：

- 大厅只能消费 `RoomSummary` 或可归一化成 `RoomSummary` 的摘要，不读取完整 `RoomState`。
- `RoomSummary` 不包含具体游戏房间私有状态、玩家隐藏身份、二维码 secret 或重连 token 明文。
- UI 只使用 `game_room_id`、`game_room_display_name`、`map_id`、`map_display_name` 和 `game_room_scene`。

### LobbyRoomEntry

大厅卡片归一化后的入口对象。

| 字段 | 说明 |
| --- | --- |
| `entry_id` | 卡片 ID。 |
| `entry_type` | `local_room`、`lan_room`、`reconnect`、`manual_join`。 |
| `summary` | `RoomSummary`。 |
| `primary_action` | `enter`、`join`、`reconnect`、`scan`。 |
| `secondary_actions` | 可选操作，例如查看、删除重连记录。 |
| `health` | `online`、`stale`、`unreachable`、`unknown`。 |
| `last_seen_at` | 最近发现时间。 |
| `metadata` | 大厅展示扩展。 |

约定：

- 大厅可以合并本机房间、局域网发现和重连缓存，但合并结果必须以 `LobbyRoomEntry` 表示。
- 大厅不执行加入校验，只把动作交给房间或基础能力。

### CreateRoomCatalog

创建房间模块使用的可创建目录，由房间模块通过具体游戏房间模块委派得到。

| 字段 | 说明 |
| --- | --- |
| `schema_version` | 目录结构版本。 |
| `game_rooms` | 可创建 `GameRoomOption` 列表。 |
| `default_game_room_id` | 默认游戏房间模块。 |
| `updated_at` | 目录更新时间。 |
| `metadata` | 扩展字段。 |

约定：

- 创建房间模块只消费目录，不维护游戏房间模块、地图、人数或槽位配置。
- 目录只包含创建 UI 所需的安全展示数据，不包含具体游戏房间私有状态。

### GameRoomOption

一个可创建的具体游戏房间模块，例如狼人杀房间模块、三国杀房间模块、围棋房间模块、象棋房间模块或麻将房间模块。

| 字段 | 说明 |
| --- | --- |
| `game_room_id` | 稳定游戏房间模块 ID，例如 `werewolf`。 |
| `display_name` | 展示名。 |
| `description` | 简短说明，可选。 |
| `maps` | 该游戏房间模块提供的 `GameRoomMap` 列表。 |
| `default_map_id` | 默认地图。 |
| `icon` | 展示图标，可选。 |
| `metadata` | 扩展字段。 |

### GameRoomMap

一个具体游戏房间模块下可创建的地图。狼人杀房间模块必须直接提供 `GameRoomMap`，规则配置只能作为地图内部配置引用。

| 字段 | 说明 |
| --- | --- |
| `map_id` | 稳定地图 ID。 |
| `map_name` | 地图展示名。 |
| `map_background` | 地图背景图 ID 或路径。 |
| `rule_text` | 地图规则摘要或规则配置引用。 |
| `map_scene` | 地图默认场景 ID 或路径。 |
| `description` | 地图说明，可选。 |
| `metadata` | 扩展字段。 |

约定：

- 地图对象只描述地图展示、规则摘要和默认场景；支持人数必须通过 `get_supported_player_counts(game_room_id, map_id)` 获取。
- 创建房间模块不能在 UI 中手写某个游戏的地图、人数或槽位列表。

### GameRoomSceneSlots

具体游戏房间模块根据地图和人数返回的场景与槽位布局。

| 字段 | 说明 |
| --- | --- |
| `game_room_id` | 游戏房间模块 ID。 |
| `map_id` | 地图 ID。 |
| `player_count` | 玩家人数。 |
| `scene_id` | 场景 ID。 |
| `scene_path` | Godot 场景路径或资源路径。 |
| `slot_list` | `GameRoomSlot` 列表。 |
| `metadata` | 扩展字段。 |

### GameRoomSlot

具体游戏房间模块返回的槽位描述。

| 字段 | 说明 |
| --- | --- |
| `slot_id` | 稳定槽位 ID。 |
| `slot_index` | 槽位顺序。 |
| `slot_type` | `player`、`observer`、`system` 或具体游戏自定义类型。 |
| `position` | UI 或场景坐标，结构由具体游戏房间模块定义。 |
| `default_state` | 初始槽位状态。 |
| `metadata` | 扩展字段。 |

约定：

- 具体房间布局、场景和槽位由具体游戏房间模块决定，通用房间模块只保存和下发结果。
- 房间模块可以提供默认布局实现，但具体游戏房间模块可以通过公开接口覆盖。

### 房间目录公开接口

房间模块向创建房间模块暴露统一目录接口，内部再委派具体游戏房间模块。

```text
get_game_room_list(context) -> GameRoomOption[]
get_map_list(game_room_id) -> GameRoomMap[]
get_supported_player_counts(game_room_id, map_id) -> int[]
get_scene_slots(game_room_id, map_id, player_count) -> GameRoomSceneSlots
```

约定：

- 创建房间模块只消费这些接口返回的数据，不维护自己的游戏房间、地图、人数、场景或槽位常量。
- 具体游戏房间模块决定地图对象、支持人数、场景路径和槽位布局。
- 通用房间模块负责校验创建请求是否与接口返回结果一致，并保存结果用于后续快照、重连和主机接管。

### RoomCreateRequest

创建房间模块提交给房间模块的统一创建请求。

| 字段 | 说明 |
| --- | --- |
| `schema_version` | 请求结构版本。 |
| `request_id` | 请求 ID。 |
| `room_name` | 房间名称。 |
| `host_participant` | 房主参与者信息。 |
| `game_room_id` | 游戏房间模块 ID。 |
| `map_id` | 地图 ID。 |
| `seat_count` | 座位数量，必须来自地图支持人数列表。 |
| `password_policy` | 是否需要密码、密码校验材料。 |
| `observer_policy` | 观战开关和人数限制。 |
| `scene_slots` | `GameRoomSceneSlots`，由具体游戏房间模块根据地图和人数生成。 |
| `display_options` | 背景、游戏房间展示名、地图展示名等展示配置。 |
| `game_room_init_options` | 传给具体游戏房间模块的初始化选项。 |
| `metadata` | 扩展字段。 |

约定：

- 房间模块校验 `game_room_id`、`map_id`、`seat_count` 和 `scene_slots` 是否匹配具体游戏房间模块返回的数据。
- 具体游戏房间模块只消费 `game_room_init_options` 中属于自己的参数。
- `RoomCreateRequest` 只接受本文定义的当前字段；字段不匹配的请求直接拒绝。

### RoomJoinRequest

房间模块接收的加入请求。

| 字段 | 说明 |
| --- | --- |
| `schema_version` | 请求结构版本。 |
| `request_id` | 请求 ID。 |
| `room_id` | 目标房间。 |
| `join_mode` | `player` 或 `observer`。 |
| `participant` | 加入者参与者资料。 |
| `auth` | `RoomJoinAuthBundle`。 |
| `password` | 用户输入密码，可选。 |
| `desired_seat_index` | 期望座位，可选。 |
| `client_protocol_version` | 客户端房间协议版本。 |
| `metadata` | 扩展字段。 |

校验顺序：

1. 房间存在且未关闭。
2. 协议版本必须匹配当前房间协议。
3. `RoomJoinAuthBundle` 有效。
4. 密码或加入 token 符合策略。
5. 加入模式符合房间策略。
6. 人数或观战容量未满。
7. 生命周期允许加入。
8. 座位可用。
9. 构建接收者视角 `RoomSnapshot`。

### RoomJoinResult

| 字段 | 说明 |
| --- | --- |
| `ok` | 是否加入成功。 |
| `participant_id` | 加入成功后的参与者 ID。 |
| `player_id` | 玩家加入时绑定的玩家 ID，可选。 |
| `reconnect_token_ref` | 重连凭据引用；不应广播明文。 |
| `room_summary` | 加入后的 `RoomSummary`。 |
| `snapshot` | 接收者视角 `RoomSnapshot`。 |
| `warnings` | 非致命问题。 |
| `error` | 拒绝原因。 |

常见错误码：

| 代码 | 说明 |
| --- | --- |
| `room_not_found` | 房间不存在或已关闭。 |
| `protocol_mismatch` | 协议版本不匹配。 |
| `auth_failed` | 基础设备认证失败。 |
| `qr_expired` | 二维码密钥已失效。 |
| `password_required` | 需要密码。 |
| `password_invalid` | 密码错误。 |
| `room_full` | 玩家席位已满。 |
| `observer_full` | 观察者已满。 |
| `observer_disabled` | 不允许观战。 |
| `game_already_started` | 当前生命周期不允许加入。 |
| `seat_unavailable` | 目标座位不可用。 |

### RoomSnapshot

`RoomSnapshot` 是房间同步和 UI 刷新的基础对象，必须按接收者视角过滤。

| 字段 | 说明 |
| --- | --- |
| `schema_version` | 快照结构版本。 |
| `room` | 房间基础信息，可内嵌 `RoomSummary` 的核心字段。 |
| `viewer` | 接收者视角，例如玩家、观察者、房主。 |
| `participants` | 接收者可见参与者信息。 |
| `players` | 接收者可见玩家和座位信息。 |
| `game_room_public_state` | 具体游戏房间公开状态。 |
| `game_room_private_state` | 当前接收者可见的具体游戏房间私有状态。 |
| `history` | 接收者可见历史。 |
| `temporary_game_data` | 当前阶段临时数据。 |
| `snapshot_version` | 快照版本。 |
| `host_epoch` | 当前房主任期。 |
| `created_at` | 快照生成时间。 |
| `metadata` | 扩展字段。 |

约定：

- 房间不得把完整游戏房间状态广播给所有客户端后依赖 UI 隐藏。
- 玩家私有数据只进入对应玩家快照。
- 观察者只接收 `observer_safe` 数据。
- 客户端必须丢弃落后 `snapshot_version` 或落后 `host_epoch` 消息。

### TemporaryGameDataEnvelope

具体游戏房间模块产生、房间负责分发的临时游戏数据。

| 字段 | 说明 |
| --- | --- |
| `schema_version` | 结构版本。 |
| `room_id` | 房间 ID。 |
| `game_room_id` | 来源游戏房间模块。 |
| `event_id` | 临时事件 ID，用于去重。 |
| `event_type` | 阶段提示、目标选择、私有结果、公开公告、展示特效等。 |
| `visibility` | `public`、`participants`、`host_only`、`player_private`、`observer_safe`。 |
| `target_participant_ids` | 私有可见参与者。 |
| `target_player_ids` | 私有可见玩家。 |
| `payload` | 具体游戏房间模块生成的数据，可承载已接受结果对应的特效请求。 |
| `ttl` | 过期策略，可选。 |
| `snapshot_version` | 对应快照版本。 |
| `host_epoch` | 对应主机任期。 |
| `created_at` | 生成时间。 |

约定：

- 房间只按可见性过滤和下发，不解释 `payload` 的玩法语义。
- 具体游戏房间模块必须保证 `payload` 不包含目标视角不应看到的信息。

### RoomEventEnvelope

房间临时历史、玩家 inbox、断线补发和副本备份使用的通用事件外壳。

| 字段 | 说明 |
| --- | --- |
| `schema_version` | 结构版本。 |
| `room_id` | 房间 ID。 |
| `game_room_id` | 来源游戏房间模块。 |
| `sequence` | 房间内单调递增事件序号。 |
| `event_id` | 事件 ID，用于去重。 |
| `event_kind` | 事件类型，由房间或具体游戏房间模块声明。 |
| `visibility` | `public`、`participants`、`player_private`、`host_only`、`observer_safe`。 |
| `target_participant_ids` | 私有可见参与者。 |
| `target_player_ids` | 私有可见玩家。 |
| `payload` | 房间系统或具体游戏房间模块生成的数据，可承载已接受结果对应的特效请求。 |
| `snapshot_version` | 对应快照版本。 |
| `host_epoch` | 对应主机任期。 |
| `created_at` | 生成时间。 |
| `expires_at` | 临时历史过期时间，可选。 |
| `metadata` | 扩展字段。 |

约定：

- 房间模块负责 `sequence`、ack、补发、下载、清理和按可见性投递。
- 具体游戏房间模块负责 `payload` 的业务格式和语义。
- 私有事件只能进入目标参与者可见队列，不允许全量广播后依赖 UI 隐藏。

### PlayerMessageInbox

房间模块为每个参与者维护的临时可见消息队列。

| 字段 | 说明 |
| --- | --- |
| `schema_version` | 结构版本。 |
| `room_id` | 房间 ID。 |
| `participant_id` | 队列所属参与者。 |
| `player_id` | 绑定玩家，可选。 |
| `last_delivered_sequence` | 已投递到客户端的最新事件序号。 |
| `last_ack_sequence` | 客户端确认处理的最新事件序号。 |
| `pending_events` | 待补发或可下载事件。 |
| `updated_at` | 最近更新时间。 |

约定：

- inbox 是临时运行数据，不是长期复盘数据。
- 重连恢复时，房间按 `last_ack_sequence` 和可见性返回增量或完整可见历史。
- 游戏结束、玩家明确退出或房间关闭后，应清理对应 inbox。

### RoomReplicaFrame

真人参与者保存的房间副本帧，用于主机重选、主机接管和原玩家重连。

| 字段 | 说明 |
| --- | --- |
| `schema_version` | 结构版本。 |
| `room_id` | 房间 ID。 |
| `holder_participant_id` | 副本持有者参与者 ID。 |
| `holder_player_id` | 副本持有者玩家 ID，可选。 |
| `host_epoch` | 副本对应房主任期。 |
| `snapshot_version` | 副本对应快照版本。 |
| `last_event_sequence` | 副本包含的最新事件序号。 |
| `room_summary` | 房间摘要。 |
| `viewer_snapshot` | 持有者可见快照。 |
| `recovery_payload` | 可选恢复数据，由具体游戏房间模块和安全策略决定。 |
| `created_at` | 生成时间。 |

约定：

- 普通真人副本默认只保存持有者可见数据。
- 隐藏信息游戏不得默认把完整私有游戏状态明文保存到所有真人玩家。
- 主机重选以最高可信 `host_epoch`、`snapshot_version` 和 `last_event_sequence` 的副本为恢复候选。

### RoomReconnectRequest

| 字段 | 说明 |
| --- | --- |
| `room_id` | 房间 ID。 |
| `participant_id` | 原参与者 ID。 |
| `device_id` | 原设备身份。 |
| `reconnect_token` | 重连凭据。 |
| `last_snapshot_version` | 客户端本地最后快照版本。 |
| `client_host_epoch` | 客户端记录的主机任期。 |

约定：

- 重连成功后保留原座位、玩家身份和可见性。
- 如果主机已完成接管，结果必须返回最新 `host_epoch` 和新主机地址。

### HostElectionResult

主机选举结果。

| 字段 | 说明 |
| --- | --- |
| `ok` | 是否完成选举。 |
| `room_id` | 房间 ID。 |
| `previous_host_participant_id` | 原房主。 |
| `new_host_participant_id` | 新房主。 |
| `host_epoch` | 新任期。 |
| `base_snapshot_version` | 接管基于的快照版本。 |
| `handover_required` | 是否需要显式交接。 |
| `error` | 失败原因。 |

约定：

- 落后 `host_epoch` 的写入消息必须被拒绝。
- 主机选举不改变具体游戏房间状态，只改变房间权威端。

## 游戏房间和玩家适配契约

### WerewolfActionRequest

狼人杀房间模块下发给狼人杀真人玩家模块或狼人杀 AI 玩家模块的行动请求。真人和 AI 玩家使用同一种请求。

| 字段 | 说明 |
| --- | --- |
| `schema_version` | 结构版本。 |
| `turn_id` | 行动请求 ID。 |
| `room_id` | 房间 ID。 |
| `phase` | 当前阶段。 |
| `day` | 当前天数。 |
| `actor_player_id` | 当前行动玩家 ID。 |
| `actor_seat_number` | 当前行动座位。 |
| `player_type` | `human` 或 `ai`。 |
| `instruction_type` | 指令类型，例如 `dialog`、`action_ui`、`speech_input`、`target_select`、`confirm`。 |
| `allowed_actions` | 当前允许动作列表。 |
| `target_options` | 当前可选目标；给 AI 机器人玩家时固定为槽位编号数组。 |
| `speech_mode` | `none`、`public`、`private`、`last_words` 等。 |
| `visible_state` | 当前玩家可见的公开状态。 |
| `private_state` | 当前玩家可见的私有状态。 |
| `time_limit_ms` | 行动超时，可选。 |
| `metadata` | 狼人杀房间模块补充信息。 |

约定：

- `WerewolfActionRequest` 必须只包含当前行动者可见的信息。
- `instruction_type` 只描述真人控制器应打开何种交互承载方式，不替代狼人杀房间模块的行动合法性判断。
- 目标列表用于 UI 和 AI 候选输入，不替代狼人杀房间模块最终校验。
- AI 机器人玩家只接收目标槽位编号，不接收目标玩家 ID；UI 展示所需名称、头像或解释由 UI 层二次转换。
- `actor_player_id` 等玩家 ID 字段只用于房间模块、玩家模块和可信通道内部路由校验；映射到 `BotVisibleContext`、模型请求和 `memory_update` 时必须移除。
- 玩家适配层可以把它转换成内部 `WerewolfPlayerTurnContext`，但跨模块入口以 `WerewolfActionRequest` 为准。

当前狼人杀行动类型：

| `action_type` | 说明 |
| --- | --- |
| `speak` | 警长竞选或白天发言。 |
| `wolf_chat` | 狼队私有发言。 |
| `last_words` | 遗言。 |
| `post_game_summary` | 赛后总结。 |
| `wolf_kill` | 狼人袭击。 |
| `guard_protect` | 守卫守护。 |
| `seer_check` | 预言家查验。 |
| `witch_act` | 女巫救人或毒人。 |
| `sheriff_vote` | 警长投票。 |
| `sheriff_speech_order` | 警长决定白天发言顺序。 |
| `sheriff_badge_action` | 警长死亡后处理警徽。 |
| `vote` | 白天放逐投票。 |
| `hunter_shoot` | 猎人开枪。 |
| `mvp_vote` | MVP 投票。 |
| `skip` | 当前行动允许跳过时使用。 |

女巫救、女巫毒、狼队目标票、警长发言顺序方向、飞警徽和撕警徽等更细动作可以作为具体游戏 AI 机器人玩家适配层内部决策结果，但跨模块提交给狼人杀房间模块前必须归一化为本文定义的行动类型。`sheriff_speech_order` 的目标表示首发言座位，方向由玩家适配层保留为当前行动结果的动作选择；`sheriff_badge_action` 的飞警徽目标表示新警长，撕警徽不携带存活目标。

### WerewolfPlayerActionResult

真人和 AI 机器人都必须返回同一种行动结果。

| 字段 | 说明 |
| --- | --- |
| `schema_version` | 结构版本。 |
| `turn_id` | 对应行动请求 ID。 |
| `room_id` | 房间 ID。 |
| `actor_seat_number` | 行动者座位编号。 |
| `action_type` | 发言、投票、查验、守护、击杀、跳过等。 |
| `target_seat_number` | 目标槽位编号，可选。 |
| `speech_text` | 公开、私聊或遗言文本，可选。 |
| `source` | `human`、`ai_model`。 |
| `confidence` | AI 置信度，可选。 |
| `model_request_id` | AI 结果对应的模型请求 ID，可选。 |
| `metadata` | 输出解析、错误、模型请求等附加信息。 |
| `error` | 失败时的结构化错误。 |

约定：

- 行动结果不直接修改游戏房间状态，必须提交给狼人杀房间模块校验。
- 行动者和目标都使用座位编号表达；玩家 ID 只用于房间模块、玩家模块和可信通道内部路由校验。
- 目标选择结果只携带 `target_seat_number`，不得同时携带目标玩家 ID、玩家名或其它重复目标字段；警长发言顺序的 `target_seat_number` 表示首发言座位，飞警徽的 `target_seat_number` 表示新警长座位，撕警徽使用跳过/无目标结果。
- `speech_text` 是玩家已提交文本，UI 可以附加解释或标签，但不能替换或改写原文。
- AI 输出解析失败时返回结构化错误，不提交为狼人杀行动。
- 狼人杀房间模块拒绝的行动不得进入记忆、历史或 TTS。
- 私有发言、夜晚行动、查验结果和狼队协调材料必须带明确可见性；不能作为公开历史默认广播。

### WerewolfRuleUpdateResult

狼人杀房间模块接受行动后的更新结果。

| 字段 | 说明 |
| --- | --- |
| `ok` | 是否接受并应用。 |
| `room_id` | 房间 ID。 |
| `accepted_action` | 被接受的 `WerewolfPlayerActionResult`，可脱敏。 |
| `rule_state_patch` | 玩法状态变更摘要。 |
| `public_events` | 公开事件。 |
| `private_events` | 私有事件，必须带目标。 |
| `history_entries` | 可写入可见历史的条目；公开、私有和复盘材料必须按可见性拆分。 |
| `temporary_game_data` | 需要下发的临时数据。 |
| `effect_requests` | 本次接受结果对应的展示特效请求，由房间 UI 或场景层消费。 |
| `next_action_request` | 下一步 `WerewolfActionRequest`，可选。 |
| `game_over` | 是否结束。 |
| `replay_data_ref` | 复盘数据引用，可选。 |
| `error` | 拒绝原因。 |

约定：

- 只有 `ok = true` 的结果可以触发记忆更新和 TTS。
- 只有 `ok = true` 的结果可以驱动 `effect_requests`、阶段推进和下一步行动请求。
- `private_events` 交给房间按可见性下发，不进入公开历史。

## 机器人/RAG 契约

机器人/RAG 模块不理解狼人杀字段。狼人杀 AI 玩家模块负责把业务状态映射成通用上下文，把狼人杀房间模块接受后的结果映射成通用记忆更新。

### BotProfile

机器人档案描述 AI 机器人自身信息。它不是玩家资料，也不是具体游戏房间状态。

| 字段 | 说明 |
| --- | --- |
| `schema_version` | 结构版本。 |
| `bot_id` | 机器人 ID。 |
| `display_name` | 机器人展示名。 |
| `avatar_id` | 头像或头像资源 ID。 |
| `persona_id` | 人格模板 ID。 |
| `model_profile_name` | 默认模型配置引用，模型管理模块据此解析实际模型 ID。 |
| `voice_profile_id` | 默认声音配置或音色引用，TTS 模块据此解析实际音色 ID。 |
| `personality` | 性格标签或结构化人格。 |
| `speaking_style` | 表达风格。 |
| `strategy_style` | 倾向性策略，只作为上下文，不直接决定业务输出。 |
| `memory_summary` | 记忆概况摘要，可选。 |
| `metadata` | 扩展字段。 |

约定：

- `BotProfile` 由机器人/RAG 模块维护，玩家模块只保存 `bot_id` 引用。
- AI 机器人玩家发言或行动时，具体游戏 AI 机器人玩家适配层读取 `model_profile_name` 和 `voice_profile_id`。
- `model_profile_name` 传给模型管理模块；`voice_profile_id` 作为调用方传入的音色 ID 进入玩家/TTS 链路。
- `BotProfile` 不保存狼人杀身份、阵营、夜晚结果、投票记录或房间权威状态。

### BotVisibleContext

业务适配层提交给机器人/RAG 的通用可见上下文。

| 字段 | 说明 |
| --- | --- |
| `schema_version` | 结构版本。 |
| `context_id` | 上下文 ID。 |
| `bot_id` | 当前机器人 ID。 |
| `scope` | 运行时范围，例如房间、会话、阶段。 |
| `actor` | 当前机器人扮演或控制的实体。 |
| `task` | 当前任务，例如选择动作、生成发言、做复盘判断。 |
| `environment` | 当前环境公开状态，例如阶段、轮次、时间、人数。 |
| `entities` | 当前可见实体列表；狼人杀场景使用座位编号和展示名，不使用玩家 ID。 |
| `visible_facts` | 当前可见事实列表。 |
| `recent_events` | 当前可见近期事件。 |
| `available_actions` | 当前允许输出的动作空间。 |
| `output_contract` | 期望输出格式和限制。 |
| `visibility` | 当前上下文整体可见性证明。 |
| `metadata` | 调试扩展；机器人模块不得依赖其中的玩法私有字段。 |

`visible_facts` 建议字段：

| 字段 | 说明 |
| --- | --- |
| `fact_id` | 事实 ID。 |
| `text` | 事实描述。 |
| `source` | 来源，例如规则、房间、玩家公开发言。 |
| `confidence` | 置信度，可选。 |
| `occurred_at` | 发生时间，可选。 |
| `tags` | 通用标签。 |

`available_actions` 建议字段：

| 字段 | 说明 |
| --- | --- |
| `action_type` | 通用动作类型。 |
| `label` | 展示或提示用标签。 |
| `target_options` | 可选目标；狼人杀 AI 场景固定为座位编号数组。 |
| `requires_text` | 是否需要文本。 |
| `constraints` | 长度、可选数量等限制。 |

约定：

- `BotVisibleContext` 只含当前机器人可见内容。
- 业务专用状态必须在适配层转换成通用事实、事件、实体和动作空间。
- 进入模型和记忆的实体引用必须是业务可见引用；狼人杀场景使用座位编号，也就是“X 号”，可以附带展示名，但不得暴露玩家 ID。
- 可见性构建失败时，必须阻止模型调用。

### BotReasoningContext

机器人/RAG 模块返回给具体游戏 AI 机器人玩家适配层的推理上下文。

| 字段 | 说明 |
| --- | --- |
| `schema_version` | 结构版本。 |
| `context_id` | 对应 `BotVisibleContext.context_id`。 |
| `bot_id` | 当前机器人 ID。 |
| `bot_profile` | 机器人档案、模型配置引用、声音配置引用和人格模板引用。 |
| `visible_context` | 已校验的可见上下文。 |
| `memory_context` | 记忆模块返回的相关记忆。 |
| `context_blocks` | 已整理好的上下文块。 |
| `token_budget` | 预算和裁剪结果。 |
| `output_contract` | 透传或增强后的输出约束。 |
| `warnings` | 裁剪、缺记忆、切换等非致命问题。 |

约定：

- `BotReasoningContext` 不是模型请求体，具体游戏 AI 机器人玩家适配层仍负责组装 `ModelGenerationRequest`。
- 记忆读取失败可以返回空记忆和 warning，不阻塞业务流程。

### memory_update

`memory_update` 是分层记忆更新载荷，不是自然语言摘要。它描述哪些已确认材料可以进入记忆系统；记忆模块决定写入、合并、降权、拒绝、衰减、忽略或延后维护。

```gdscript
{
    "schema_version": 1,
    "update_id": "",
    "bot_id": "",
    "scope": {},
    "source_module": "",
    "confirmed_at": 0,
    "source": "confirmed_event",
    "visibility": "self_private",
    "working_update": {},
    "episodic_events": [],
    "relationship_updates": [],
    "semantic_candidates": [],
    "reflection_candidates": [],
    "importance_hints": {},
    "confidence_hints": {},
    "evidence": [],
    "retention_policy": {},
    "metadata": {}
}
```

核心字段：

| 字段 | 说明 |
| --- | --- |
| `schema_version` | 结构版本。 |
| `update_id` | 记忆更新 ID。 |
| `bot_id` | 目标机器人。 |
| `scope` | 记忆作用域，例如业务域、会话和运行实例。 |
| `source_module` | 生成来源，例如 `werewolf_player_adapter`。 |
| `confirmed_at` | 业务确认时间。 |
| `source` | 更新来源，例如 `accepted_output`、`accepted_dialogue`、`confirmed_event`、`session_end`。 |
| `visibility` | 当前机器人可见性证明。 |
| `working_update` | 当前会话工作记忆更新。 |
| `episodic_events` | 具体事件记忆候选。 |
| `relationship_updates` | 关系记忆更新候选。 |
| `semantic_candidates` | 长期语义记忆候选。 |
| `reflection_candidates` | 反思记忆候选。 |
| `importance_hints` | 调用方给出的重要性提示，最终值由记忆模块决定。 |
| `confidence_hints` | 调用方给出的置信度提示，最终值由记忆模块决定。 |
| `evidence` | 支撑本次更新的已确认事件、对话、输出和结果引用。 |
| `retention_policy` | 保留、过期或维护建议。 |
| `metadata` | 扩展字段。 |

`working_update` 建议字段：

| 字段 | 说明 |
| --- | --- |
| `current_goal` | 当前目标。 |
| `short_term_plan` | 短期计划。 |
| `temporary_judgements` | 临时判断。 |
| `open_questions` | 待验证问题。 |
| `mood_or_tone` | 当前情绪或表达倾向。 |
| `ttl` | 过期策略。 |
| `evidence_refs` | 证据事件引用。 |

`episodic_events` 条目建议字段：

| 字段 | 说明 |
| --- | --- |
| `event_ref` | 已确认事件引用。 |
| `event_type` | 通用事件类型。 |
| `description` | 事件描述。 |
| `participants` | 相关实体；狼人杀场景使用座位编号引用。 |
| `result` | 结果。 |
| `importance` | 重要性提示。 |
| `confidence` | 置信度提示。 |
| `tags` | 通用标签。 |
| `occurred_at` | 发生时间。 |

`relationship_updates` 条目建议字段：

| 字段 | 说明 |
| --- | --- |
| `target_entity_id` | 关系目标；狼人杀场景使用 `seat:<座位编号>` 这类业务可见引用。 |
| `target_entity_type` | 目标类型。 |
| `relation_type` | 信任、协作、冲突、熟悉度等。 |
| `delta` | 变化描述或数值。 |
| `reason` | 基于已确认事实的原因。 |
| `confidence` | 置信度。 |
| `evidence_refs` | 证据事件引用。 |

`semantic_candidates` 条目建议字段：

| 字段 | 说明 |
| --- | --- |
| `claim` | 候选稳定知识或长期经验。 |
| `scope` | 适用范围。 |
| `confidence` | 置信度。 |
| `evidence_refs` | 证据事件引用。 |
| `tags` | 通用标签。 |

`reflection_candidates` 条目建议字段：

| 字段 | 说明 |
| --- | --- |
| `insight` | 反思候选。 |
| `trigger` | 触发原因。 |
| `evidence_refs` | 证据事件引用。 |
| `confidence` | 置信度。 |
| `apply_after` | 何时可用于后续上下文。 |

约定：

- `memory_update` 必须来自已确认业务结果。
- 生成方只提交候选，不决定最终写入哪一层。
- 不得包含当前机器人不可见信息。
- 不得包含玩家 ID、连接 ID、设备 ID 等系统内部身份字段；狼人杀记忆引用本局对象时使用座位编号或“座位编号（展示名）”。
- 推理链路、模型草稿、被具体游戏房间模块拒绝的行动不得进入 `memory_update`。
- 长期语义和反思只是候选，通常需要维护流程确认、合并或降权。
- 狼人杀适配层可以在生成时使用狼人杀事件，但提交给机器人模块前必须转成通用字段。

### BotMemoryCommitResult

机器人模块提交记忆更新后的结果。

| 字段 | 说明 |
| --- | --- |
| `ok` | 是否提交成功。 |
| `update_id` | 对应记忆更新 ID。 |
| `bot_id` | 机器人 ID。 |
| `memory_update_report` | 各层写入、跳过、合并、降权结果。 |
| `warnings` | 非致命问题。 |
| `error` | 失败原因。 |

约定：

- 写入失败不撤销外部业务结果。
- 调试报告默认脱敏。

## 模型管理契约

### ModelGenerationRequest

具体游戏 AI 机器人玩家适配层提交给模型管理模块的一次模型调用请求。

| 字段 | 说明 |
| --- | --- |
| `schema_version` | 请求结构版本。 |
| `request_id` | 模型请求 ID。 |
| `profile_name` | 模型配置名。 |
| `profile_override` | 临时配置覆盖，可选。 |
| `messages` | 已组装好的消息列表。 |
| `generation_options` | 温度、top_p、输出上限、停止词等。 |
| `request_context` | 调用方上下文，例如来源模块、房间、玩家、trace。 |
| `metadata` | 扩展字段。 |

约定：

- 模型管理模块不理解 `messages` 的业务语义。
- 模型管理模块不读取机器人记忆、不校验狼人杀房间玩法规则、不生成游戏行动。
- API Key 不进入普通日志、调试报告或房间广播。

### ModelGenerationResult

| 字段 | 说明 |
| --- | --- |
| `ok` | 是否成功。 |
| `request_id` | 模型请求 ID。 |
| `profile_name` | 使用的模型配置。 |
| `text` | 成功时返回文本。 |
| `raw_response_summary` | 脱敏后的响应概况。 |
| `usage` | token、耗时等统计。 |
| `warnings` | 非致命问题。 |
| `error` | 失败原因。 |

约定：

- 模型输出只是草稿，必须由具体游戏 AI 机器人玩家适配层解析成 `WerewolfPlayerActionResult`，再由狼人杀房间模块校验。
- 模型输出不能直接进入 TTS、历史或记忆。

## 玩家和 TTS 契约

### PlayerProfile

通用玩家基础资料。

| 字段 | 说明 |
| --- | --- |
| `schema_version` | 结构版本。 |
| `player_id` | 玩家 ID。 |
| `display_name` | 展示名。 |
| `avatar_id` | 内置头像 ID。 |
| `player_type` | `human` 或 `ai`。 |
| `owner_type` | `self`、`local_human`、`remote_human`、`bot`。 |
| `controller_type` | `local_human`、`remote_human`、`ai`、`autoplay`。 |
| `bot_id` | AI 机器人玩家可选。 |
| `metadata` | 通用扩展字段。 |

约定：

- `PlayerProfile` 不保存狼人杀身份、阵营、夜晚结果或投票记录。
- `bot_id` 是引用，不代表玩家模块拥有机器人档案、模型配置、声音配置或记忆数据。
- AI 机器人使用的模型 ID 和声音 ID 从机器人档案读取，由具体游戏 AI 机器人玩家适配层在调用模型管理和玩家/TTS 链路时传入。
- 播放时使用的音色 ID 不写入 `PlayerProfile`，必须由生成 `PlayerSpeechRequest` 的调用方传入。

### PlayerRuntimeBinding

玩家在某个房间或游戏运行时里的临时绑定。

| 字段 | 说明 |
| --- | --- |
| `schema_version` | 结构版本。 |
| `player_id` | 玩家 ID。 |
| `scope` | 运行时作用域。 |
| `room_id` | 房间 ID，可选。 |
| `seat_id` | 座位 ID，可选。 |
| `connection_id` | 连接 ID，可选。 |
| `ready` | 是否准备。 |
| `online_state` | `online`、`offline`、`reconnecting`、`left`。 |
| `controller_type` | 当前行为控制器类型。 |
| `metadata` | 扩展字段。 |

约定：

- 绑定状态不替代房间权威状态。
- 玩法身份、阵营和行动记录不得写入通用绑定对象。

### PlayerTrustedChannel

玩家模块提供的玩家级可信通信通道。它消费基础能力和房间模块已经确认的连接、身份和授权结果，不拥有底层 socket 或证书认证实现。

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
| `metadata` | 扩展字段，不保存 secret 明文。 |

约定：

- 玩家模块通过该通道投递玩家行为请求、玩家通知、玩家侧 UI 状态和恢复数据。
- 该通道必须支持序号、ack、去重、补发和关闭。
- `trust_state` 不是设备认证结果本身，只是玩家模块对上游认证结果的消费状态。
- 通道关闭不等于底层网络连接关闭。

### PlayerTemporaryDataEnvelope

玩家模块临时保存和投递的玩家侧数据外壳。

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

- 玩家模块负责 `sequence`、ack、补发、清理和生命周期。
- 具体游戏玩家适配层负责 `payload` 的业务语义和可见性脱敏。
- 玩家退出、恢复窗口结束、房间关闭或数据过期时必须清理。

### PlayerRecoveryFrame

玩家断联后恢复用的玩家侧数据帧。

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

### PlayerActionRequest

房间模块或具体游戏玩家适配层发给玩家模块的通用行为请求。

| 字段 | 说明 |
| --- | --- |
| `schema_version` | 结构版本。 |
| `request_id` | 行为请求 ID。 |
| `room_id` | 房间 ID。 |
| `player_id` | 目标玩家 ID。 |
| `controller_type` | 目标控制器类型。 |
| `game_id` | 当前游戏 ID。 |
| `instruction_type` | 指令类型，例如 `dialog`、`action_ui`、`speech_input`、`target_select`、`confirm`。 |
| `action_prompt` | 上层已脱敏的行为提示。 |
| `options` | 可选动作、目标或输入约束。 |
| `visible_context` | 当前玩家可见上下文。 |
| `timeout_ms` | 超时，可选。 |
| `metadata` | 扩展字段。 |

约定：

- 玩家模块不解释 `options` 和 `visible_context` 的具体游戏语义。
- `instruction_type` 只用于玩家控制器选择交互承载方式，不能用于绕过具体游戏房间模块校验。
- 具体游戏玩家适配层负责可见性过滤。

### PlayerActionResult

玩家控制器返回的通用行为结果。

| 字段 | 说明 |
| --- | --- |
| `schema_version` | 结构版本。 |
| `request_id` | 对应行为请求 ID。 |
| `player_id` | 行为玩家 ID。 |
| `source` | `local_human`、`remote_human`、`ai`、`autoplay`。 |
| `action_payload` | 玩家返回的原始行为数据。 |
| `submitted_at` | 提交时间。 |
| `metadata` | 扩展字段。 |
| `error` | 失败时的结构化错误。 |

约定：

- `action_payload` 必须先交给具体游戏玩家适配层转换，再交给具体游戏房间模块校验。
- AI 和托管结果不能绕过具体游戏房间模块直接修改状态。
- 真人 UI 输入不能直接驱动特效、阶段推进或房间状态变更。

### PlayerSpeechRequest

玩家模块接收的已确认文本请求。

| 字段 | 说明 |
| --- | --- |
| `schema_version` | 请求结构版本。 |
| `request_id` | 请求 ID。 |
| `player_id` | 发言玩家 ID。 |
| `scope` | 发言所属作用域。 |
| `text` | 已确认要输出的文本。 |
| `voice_profile_id` | 必填，调用方传入的音色 ID 或声音配置 ID。 |
| `source` | `rule_accepted`、`room_history`、`manual_confirmed` 等。 |
| `visibility` | `public` 或 `private_local` 等。 |
| `accepted_at` | 上层确认时间。 |
| `metadata` | 扩展字段。 |

约定：

- 玩家模块不接收待审核草稿。
- 玩家模块不自行选择音色，不从 `PlayerProfile` 推断音色；它只透传调用方传入的 `voice_profile_id`。
- TTS 失败不撤销游戏房间状态或房间历史。

### TtsPlaybackRequest

TTS 模块接收的一次播报请求。

| 字段 | 说明 |
| --- | --- |
| `schema_version` | 请求结构版本。 |
| `request_id` | 播报请求 ID。 |
| `text` | 已确认要播报的文本。 |
| `voice_profile_id` | 调用方传入的音色 ID 或声音配置 ID。 |
| `playback_options` | 插队、队列、最大长度等。 |
| `source` | `player_speech`、`room_notice`、`system_prompt` 等。 |
| `visibility` | `public`、`private_local`。 |
| `metadata` | 扩展字段。 |

约定：

- TTS 可以清洗播报副本，但不能修改房间历史原文或玩家已确认文本。
- 通过玩家模块进入 TTS 的请求必须带 `voice_profile_id`。
- 私密播报必须由调用方保证只在正确设备播放。

### TtsPlaybackResult

| 字段 | 说明 |
| --- | --- |
| `ok` | 是否接受请求。 |
| `request_id` | 播报请求 ID。 |
| `status` | `queued`、`started`、`failed`、`stopped`。 |
| `voice_profile_id` | 实际使用声音。 |
| `warnings` | 非致命问题。 |
| `error` | 失败原因。 |

## 关键流程

### 大厅展示房间

```text
LAN discovery / local room / reconnect cache
  -> 归一化为 RoomSummary
  -> 大厅生成 LobbyRoomEntry
  -> 用户点击动作
  -> 路由到创建房间、扫码、加入、重连或房间页面
```

约定：

- 大厅不读取 `RoomState`。
- 大厅不解析二维码、不做设备认证、不校验加入策略。

### 扫码加入房间

```text
大厅扫码入口
  -> 基础能力打开相机
  -> QrJoinPayload 解析
  -> WebSocket 连接和设备认证
  -> 二维码密钥协商和解密
  -> RoomJoinAuthBundle
  -> 房间模块 RoomJoinRequest
  -> RoomJoinResult + RoomSnapshot
```

约定：

- 基础能力失败时，不进入房间加入策略。
- 房间策略失败时，不回头修改二维码基础能力。

### 真人玩家行动

```text
狼人杀房间模块 build_action_request()
  -> WerewolfActionRequest(instruction_type)
  -> 狼人杀真人/AI 玩家模块 to_player_action_request()
  -> PlayerActionRequest(instruction_type)
  -> 玩家模块创建 player_action / player_speech 任务并记录控制 participant
  -> 玩家模块写入 PlayerTemporaryDataEnvelope
  -> 玩家模块经 PlayerTrustedChannel 投递给真人控制器
  -> 真人控制器按 instruction_type 打开对话框或行动交互 UI
  -> 真人操作 UI 并产生输入
  -> PlayerActionResult 经 PlayerTrustedChannel 回到主机端房间程序
  -> 狼人杀真人/AI 玩家模块 from_player_action_result()
  -> WerewolfPlayerActionResult
  -> 狼人杀房间模块 submit_action_result()
  -> WerewolfRuleUpdateResult(effect_requests + next_action_request)
```

约定：

- 真人玩家只负责接收指令、打开对应 UI、收集输入和回传结果。
- 主机端房间程序收到真人回复后，必须交给具体游戏房间模块校验。
- 特效请求、阶段推进和下一步行动请求只能来自具体游戏房间模块接受后的结果。

### AI 机器人玩家行动

```text
狼人杀房间模块 build_action_request()
  -> WerewolfActionRequest
  -> 主机通过玩家任务通道创建 player_action / player_speech 任务
  -> 房间网络路由到该 AI 玩家的控制设备
  -> 控制设备读取 BotProfile(model_profile_name + voice_profile_id)
  -> 控制设备从本机模型数据库读取完整 ModelProfile
  -> 狼人杀 AI 玩家模块构建 BotVisibleContext
  -> 机器人模块 build_bot_context()
  -> BotReasoningContext
  -> 具体游戏 AI 机器人玩家适配层使用本机 ModelProfile 组装 ModelGenerationRequest
  -> 基础模型推理能力 complete_request()
  -> ModelGenerationResult
  -> 具体游戏 AI 机器人玩家适配层 parse_ai_output()
  -> 玩家模块 complete_player_action()
  -> WerewolfPlayerActionResult
  -> 狼人杀房间模块 submit_action_result()
  -> WerewolfRuleUpdateResult(effect_requests + next_action_request)
```

约定：

- AI 机器人玩家不直接修改游戏房间状态。
- 主机端只路由玩家任务并等待玩家任务结果，不读取、不缓存、不广播 AI 模型配置、API Key、prompt、schema 或声音配置。
- AI 机器人玩家和真人玩家的输入/输出契约一致，都是行动请求进入玩家模块、统一行动结果交回具体游戏房间模块。
- 可见上下文构建失败时，不调用模型。
- 模型输出解析失败时返回结构化错误，不交给狼人杀房间模块推进阶段。
- 特效请求、阶段推进和下一步行动请求仍由狼人杀房间模块接受结果后产生。

### 游戏房间接受后的记忆更新

```text
WerewolfRuleUpdateResult(ok = true)
  -> 狼人杀 AI 玩家模块提取已确认事件、行动、发言和结果
  -> 映射为通用 memory_update
  -> 机器人模块 commit_bot_result()
  -> 记忆模块 update_memory()
  -> BotMemoryCommitResult
```

约定：

- `memory_update` 不是摘要。
- 记忆模块决定最终写入、合并、降权、忽略或维护。
- 记忆提交失败不撤销游戏房间结果。

### 已确认文本播报

```text
具体游戏房间模块或房间确认文本
  -> PlayerSpeechRequest(text + voice_profile_id + visibility)
  -> 玩家模块 submit_accepted_speech()
  -> TtsPlaybackRequest
  -> TTS speak_text()
  -> TtsPlaybackResult
```

约定：

- 模型草稿、未确认文本、具体游戏房间模块拒绝文本不得播报。
- 音色 ID 由具体游戏房间模块、房间或玩家适配层在调用时传入，玩家模块不自行选择。
- 公开播报和本机私密播报必须带明确 `visibility`。

### 房间事件分发

```text
具体游戏房间模块生成事件 payload 和可见性
  -> RoomSession 包装为 RoomEventEnvelope 并分配 sequence
  -> 按可见性写入目标 PlayerMessageInbox
  -> 下发给在线参与者
  -> 真人参与者保存可见 RoomReplicaFrame
```

约定：

- 私有事件只进入目标参与者或目标玩家的可见队列。
- 房间负责序号、ack、补发、下载和清理；具体游戏房间模块负责 payload 格式和可见性语义。

### 玩家通道投递和恢复

```text
房间模块或具体游戏玩家适配层生成 PlayerActionRequest / 玩家通知
  -> 玩家模块写入 PlayerTemporaryDataEnvelope
  -> 通过 PlayerTrustedChannel 投递给玩家控制器或客户端
  -> 玩家侧处理后 ack
  -> 玩家断联时保留未确认临时数据和 PlayerRecoveryFrame
  -> 房间模块完成重连认证
  -> 玩家模块重新打开 PlayerTrustedChannel
  -> 按 last_ack_sequence 重新投递玩家可见数据
```

约定：

- 玩家模块负责玩家级序号、ack、补发、恢复和临时数据清理。
- 房间模块负责房间级身份、座位、参与者和重连认证。
- 具体游戏玩家适配层负责玩家数据 payload 的业务语义和可见性脱敏。

### 可见历史下载

```text
玩家重连或 UI 重建
  -> RoomReconnectRequest / history request
  -> RoomSession 读取 last_ack_sequence
  -> 按参与者可见性过滤 RoomEventEnvelope
  -> 返回增量事件或完整可见历史
```

约定：

- 历史下载只返回该参与者当前可见的数据。
- 临时历史不是复盘数据；游戏结束后的复盘由具体游戏房间模块显式生成。

### 主机重选与接管

```text
客户端检测 host 不可达
  -> 房间副本比较 host_epoch / snapshot_version / 参与者优先级
  -> HostElectionResult
  -> 新房主接管
  -> 生成新 host_epoch 的 RoomSnapshot
  -> 客户端丢弃落后 epoch 消息
```

约定：

- 主机重选与接管只改变房间权威端，不改变具体游戏房间模块结果。
- 新房主必须基于最新可用快照接管。

### 房间销毁

```text
游戏结束或真人参与者退出
  -> RoomSession 更新参与者状态
  -> 清理已退出玩家私有 inbox
  -> 所有真人参与者均退出或不可恢复
  -> 房间进入 closed
  -> 清理临时历史、inbox、副本和重连材料
```

约定：

- AI 机器人玩家不单独支撑房间存活，除非后续引入专门服务器或托管主机。
- 真人参与者可选择重连或退出；退出后不再保留其私有临时队列。

## 责任矩阵

| 契约 | 生产者 | 消费者 | 权威校验者 |
| --- | --- | --- | --- |
| `QrJoinPayload` | 基础能力 + 房间提供字段 | 基础能力扫码解析 | 基础能力 |
| `RoomJoinAuthBundle` | 基础能力 | 房间模块 | 基础能力校验认证，房间校验加入策略 |
| `RoomSummary` | 房间模块 | 大厅、创建房间、重连、房间 UI | 房间模块 |
| `LobbyRoomEntry` | 大厅模块 | 大厅 UI | 大厅模块 |
| `CreateRoomCatalog` | 房间模块委派具体游戏房间模块生成 | 创建房间模块 | 房间模块 |
| `GameRoomOption` | 具体游戏房间模块 | 创建房间模块、房间模块 | 对应游戏房间模块 |
| `GameRoomMap` | 具体游戏房间模块 | 创建房间模块、房间模块 | 对应游戏房间模块 |
| `GameRoomSceneSlots` | 具体游戏房间模块 | 创建房间模块、房间模块、房间 UI | 对应游戏房间模块 |
| `GameRoomSlot` | 具体游戏房间模块 | 房间模块、房间 UI | 对应游戏房间模块 |
| `RoomCreateRequest` | 创建房间模块 | 房间模块 | 房间模块校验目录匹配，具体游戏房间模块校验初始化参数 |
| `RoomJoinRequest` | 大厅 / 扫码 / 重连入口 | 房间模块 | 房间模块 |
| `RoomSnapshot` | 房间模块 | 房间 UI、客户端副本 | 房间模块 |
| `TemporaryGameDataEnvelope` | 具体游戏房间模块 | 房间模块、客户端 | 具体游戏房间模块负责内容和特效请求，房间负责可见性下发 |
| `RoomEventEnvelope` | 房间模块包装，具体游戏房间模块提供 payload | 玩家 inbox、历史下载、房间副本、客户端 | 房间负责序号和可见性，具体游戏房间模块负责 payload 和特效请求 |
| `PlayerMessageInbox` | 房间模块 | 玩家客户端、重连恢复 | 房间模块 |
| `RoomReplicaFrame` | 房间模块 / 真人参与者客户端 | 主机选举、重连恢复 | 房间模块和具体游戏房间模块共同校验恢复能力 |
| `WerewolfActionRequest` | 狼人杀房间模块 | 狼人杀真人/AI 玩家模块 | 狼人杀房间模块 |
| `WerewolfPlayerActionResult` | 狼人杀真人/AI 玩家模块 | 狼人杀房间模块 | 狼人杀房间模块 |
| `BotProfile` | 机器人/RAG 模块 | 具体游戏 AI 机器人玩家适配层 | 机器人/RAG 模块 |
| `BotVisibleContext` | 业务玩家适配层 | 机器人/RAG 模块 | 适配层负责脱敏，机器人做防线校验 |
| `memory_update` | 业务玩家适配层 | 机器人/RAG 模块 | 适配层负责来源确认，记忆模块负责写入规则 |
| `ModelGenerationRequest` | 具体游戏 AI 机器人玩家适配层 | 模型管理模块 | 模型管理模块校验配置和调用参数 |
| `PlayerActionRequest` | 房间模块 / 具体游戏玩家适配层 | 玩家模块 | 调用方负责可见性和指令类型，玩家模块负责控制器分发 |
| `PlayerActionResult` | 玩家模块 | 具体游戏玩家适配层 | 具体游戏房间模块最终校验 |
| `PlayerTrustedChannel` | 玩家模块 | 玩家控制器、房间模块、具体游戏玩家适配层 | 玩家模块校验玩家绑定和上游认证摘要 |
| `PlayerTemporaryDataEnvelope` | 玩家模块包装，调用方提供 payload | 玩家控制器、玩家恢复流程 | 玩家模块负责序号、ack、补发和生命周期；调用方负责 payload |
| `PlayerRecoveryFrame` | 玩家模块 | 玩家恢复流程、房间模块 | 玩家模块负责玩家侧恢复数据，房间负责重连认证 |
| `PlayerSpeechRequest` | 具体游戏房间模块 / 房间 / 玩家适配层 | 玩家模块 | 调用方负责确认文本、可见性和音色 ID |
| `TtsPlaybackRequest` | 玩家模块 / 已确认输出调用方 | TTS 模块 | TTS 模块校验播放参数 |

## 变更规则

跨模块契约变更必须同步：

1. 本文对应对象。
2. 生产者模块文档。
3. 消费者模块文档。
4. 相关测试或检查脚本。
5. 当前结构的拒绝和丢弃规则。

版本规则：

- 新增可选字段：不需要提升主版本，但要写默认行为。
- 新增必填字段：必须提升 `schema_version`，并写明不符合当前结构时的拒绝或丢弃策略。
- 字段改名：必须同步更新生产者和消费者；不保留原字段读取路径。
- 字段语义改变：视为破坏性变更，必须提升版本。
- 敏感字段可见性变更：必须重新审查基础能力、房间快照、机器人上下文、TTS 和调试接口。

## 开发检查清单

改跨模块数据结构时，至少检查：

- 这个字段的权威生产者是谁？
- 哪些模块消费它？
- 是否会进入网络广播、房间历史、机器人记忆、模型请求、TTS 或调试日志？
- 是否包含设备私钥、API Key、二维码 secret、重连 token、隐藏身份或私密结果？
- 是否需要按玩家、观察者、本机私密或 debug 视角过滤？
- 是否需要加入 `schema_version`、拒绝和丢弃策略？
- 是否需要同步 Android 插件、Godot bridge、桌面 JSON 或 SQLite？
