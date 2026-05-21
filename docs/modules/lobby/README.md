# 大厅模块

更新时间：2026-05-16

大厅模块是小编织模块，负责把本机房间摘要、局域网发现结果、重连入口和配置入口编排成首屏视图。它回答“用户从哪里进入下一步”，但不拥有房间权威状态，也不承载二维码、扫码、加密、认证、创建、重连或规则执行本身。

大厅模块像一个入口编排黑盒：它只消费摘要、归一化卡片、排序入口，并把用户动作转换成路由命令或交给其它模块的业务命令。

## 模块定位

```text
应用启动 / 返回大厅
  -> 大厅模块
       -> 读取本机房间摘要
       -> 读取局域网发现摘要
       -> 读取重连摘要
       -> 组织创建 / 扫码 / 偏好 / 配置入口
       -> 输出统一大厅视图
       -> 把用户动作分发给路由或其它模块
```

大厅是组合层，不是权威层。它不决定房间能否加入，也不决定重连是否成功；它只展示可用入口并发起对应动作。

## 能力边界

大厅模块负责：

- 聚合本机房间、局域网发现房间和重连会话摘要。
- 统一生成房间卡片、工具栏、空状态、错误状态和过期提示。
- 展示创建房间、扫码加入、模型配置、机器人配置、声音配置和偏好设置入口。
- 根据摘要新鲜度、协议版本匹配结果和会话状态决定卡片动作。
- 把点击事件转成路由命令或模块命令。
- 提供刷新、归一化、合并、排序和只读调试能力。

大厅模块不负责：

- 创建 `RoomState` 或初始化房间权威状态。
- 二维码生成、扫码、加密、认证实现。
- 房间密码、加入 token、观战、容量、重连和主机选举校验。
- 网络同步、快照恢复和房主接管。
- 狼人杀房间玩法、玩家行动、胜负判断或复盘。
- 偏好字段保存、模型配置保存、TTS 播报或机器人记忆更新。

## 内部实现

大厅内部可以拆成四个稳定部分：

1. 摘要归一化器：把 `RoomSummary`、`DiscoveryRoomAdvert`、`ReconnectEntry` 和入口元信息转换为统一卡片。
2. 卡片聚合器：按 `room_id` 去重，处理本机房间、发现房间和重连会话的优先级。
3. 视图装配器：生成工具栏、空状态、错误状态和房间卡片。
4. 动作分发器：把 UI 点击转换成路由命令或外部模块命令。

当前实现入口是 `scripts/pages/lobby_page.gd`，大厅主渲染、工具栏、重连卡片和房间卡片落在 `scripts/pages/lobby/lobby_page_flow.gd`，并通过 `AppState`、房间会话存储、局域网发现和路由服务完成编排。扫码加入流程落在基础扫码页面层 `scripts/pages/base/page_scan_join_flow_base.gd`，大厅只发起入口动作。

## 对外接口

以下接口是设计契约，不要求当前代码函数名完全一致。

```text
build_lobby_view(context) -> LobbyViewState
refresh_lobby(reason) -> LobbyRefreshResult
normalize_room_card(source, payload) -> LobbyRoomCard
merge_room_cards(cards) -> LobbyRoomCard[]
handle_lobby_action(action) -> LobbyActionResult
get_lobby_debug_state(request) -> LobbyDebugResult
```

### build_lobby_view

```text
build_lobby_view(context) -> LobbyViewState
```

`LobbyContext` 建议包含：

| 字段 | 说明 |
| --- | --- |
| `viewer` | 当前本机用户和设备身份摘要。 |
| `local_room_summaries` | 本机房间摘要列表。 |
| `discovery_adverts` | 局域网发现结果。 |
| `reconnect_entries` | 本地可重连会话。 |
| `entry_metadata` | 偏好、配置入口的可见性元信息。 |
| `now` | 当前时间，用于 TTL 和过期判断。 |

约定：

- 构建视图时只做归一化、排序和展示判断。
- 不在这里发起加入、重连、创建或认证。
- 某个数据源失败时，尽量保留其它来源的可展示卡片。

### refresh_lobby

```text
refresh_lobby(reason) -> LobbyRefreshResult
```

`reason` 可为：

- `enter_lobby`
- `manual_refresh`
- `discovery_tick`
- `return_from_room`
- `session_changed`

返回结果建议包含：

| 字段 | 说明 |
| --- | --- |
| `ok` | 是否刷新成功。 |
| `view_state` | 新大厅状态。 |
| `warnings` | 某些来源失败但整体可展示的警告。 |
| `error` | 完全失败时的错误。 |

### handle_lobby_action

```text
handle_lobby_action(action) -> LobbyActionResult
```

`LobbyAction` 建议包含：

| 动作 | 说明 | 目标 |
| --- | --- | --- |
| `open_create_room` | 打开创建房间入口。 | 创建房间模块 |
| `start_scan_join` | 启动扫码加入。 | 基础扫码能力 + 房间加入编排 |
| `enter_local_room` | 进入本机房间。 | 房间模块 |
| `join_discovered_room` | 加入局域网发现房间。 | 房间模块 |
| `reconnect_room` | 使用重连卡片恢复房间。 | 房间模块 |
| `open_preferences` | 打开偏好设置。 | 偏好设置模块 |
| `open_model_config` | 打开模型配置。 | 模型管理模块 |
| `open_voice_config` | 打开声音配置。 | TTS 语音模块 |
| `open_bot_config` | 打开机器人配置。 | 机器人/RAG 模块 |
| `refresh` | 刷新大厅数据。 | 大厅模块 |

`LobbyActionResult` 建议包含：

| 字段 | 说明 |
| --- | --- |
| `ok` | 动作是否被接受。 |
| `route` | 需要路由到的页面。 |
| `module_command` | 需要交给其它模块执行的命令。 |
| `message` | 可展示状态或错误。 |

## 核心对象

### LobbyViewState

大厅页面当前展示状态。

| 字段 | 说明 |
| --- | --- |
| `local_cards` | 本机房间卡片。 |
| `discovered_cards` | 局域网发现房间卡片。 |
| `reconnect_cards` | 可重连房间卡片。 |
| `toolbar_actions` | 创建、扫码、刷新、配置等工具栏入口。 |
| `refresh_state` | `idle`、`refreshing`、`failed`。 |
| `empty_state` | 当前空状态文案和推荐动作。 |
| `last_refresh_at` | 最近刷新时间。 |
| `active_route_intent` | 当前正在发起的路由意图。 |

### LobbyRoomCard

统一房间卡片，不区分原始来源。

| 字段 | 说明 |
| --- | --- |
| `card_id` | 卡片唯一 ID。 |
| `source` | `local`、`discovered`、`reconnect`。 |
| `room_id` | 房间 ID。 |
| `room_name` | 房间名。 |
| `game_room_id` | 游戏房间模块 ID。 |
| `game_room_display_name` | 游戏房间模块展示名。 |
| `map_id` | 地图 ID。 |
| `map_display_name` | 地图展示名。 |
| `background` | 卡片背景。 |
| `host_name` | 房主名。 |
| `player_count` / `seat_count` | 玩家人数和总座位。 |
| `observer_count` / `observer_limit` | 观战人数和上限。 |
| `lifecycle` | 房间生命周期。 |
| `action` | `enter`、`join`、`reconnect`、`disabled`。 |
| `disabled_reason` | 不可操作原因。 |
| `endpoint` | 远端连接地址；本地房间可为空。 |
| `freshness` | `fresh`、`stale`、`expired`。 |
| `updated_at` | 摘要更新时间。 |

### DiscoveryRoomAdvert

局域网发现广播摘要。

| 字段 | 说明 |
| --- | --- |
| `room_id` | 房间 ID。 |
| `room_summary` | 房间基础展示信息。 |
| `host_endpoint` | 房主地址。 |
| `host_device_id` | 房主设备 ID。 |
| `protocol_version` | 房间协议版本。 |
| `last_seen_at` | 最近发现时间。 |
| `ttl` | 发现记录有效期。 |

### ReconnectEntry

重连卡片数据。

| 字段 | 说明 |
| --- | --- |
| `room_id` | 房间 ID。 |
| `participant_id` | 原参与者 ID。 |
| `device_id` | 原设备身份。 |
| `reconnect_token_ref` | 重连 token 引用或安全存储句柄。 |
| `room_summary` | 最近一次房间摘要。 |
| `last_snapshot_version` | 本地最后快照版本。 |
| `host_epoch` | 本地记录的主机任期。 |
| `last_host_endpoint` | 最近房主地址。 |
| `expires_at` | 重连过期时间。 |
| `status` | `available`、`expired`、`host_handover`、`unknown`。 |

## 主要流程

### 进入大厅

```text
应用启动或返回大厅
  -> refresh_lobby(enter_lobby)
  -> 读取本机房间摘要
  -> 读取重连会话摘要
  -> 启动或刷新局域网发现
  -> normalize_room_card()
  -> merge_room_cards()
  -> 渲染工具栏、重连卡片、房间列表和空状态
```

### 点击创建房间

```text
点击创建入口
  -> handle_lobby_action(open_create_room)
  -> 路由到创建房间模块
  -> 创建房间模块提交 RoomCreateRequest
  -> 房间模块创建 RoomState
  -> 成功后进入房间
```

大厅不创建房间状态，只负责打开入口。

### 点击扫码加入

```text
点击扫码入口
  -> handle_lobby_action(start_scan_join)
  -> 调用基础扫码能力打开 Android 相机或调试输入
  -> 基础能力返回扫码、解密和认证结果
  -> 房间模块消费基础结果并执行加入策略校验
  -> 成功后路由到房间
```

大厅不解析二维码，不处理密钥协商，也不保存扫描结果。

### 点击重连卡片

```text
点击重连卡片
  -> handle_lobby_action(reconnect_room)
  -> 生成 ReconnectRequest 所需引用
  -> 房间模块校验 device_id、reconnect_token、host_epoch
  -> 成功后下发最新快照并进入房间
  -> 失败则更新卡片状态或移除过期卡片
```

大厅不校验重连 token，只判断卡片是否过期和是否有可用摘要。

## 失败与降级

| 场景 | 策略 |
| --- | --- |
| 局域网发现不可用 | 仍展示本机房间和重连卡片。 |
| 重连会话失效 | 标记 `expired` 或移除。 |
| 协议版本不匹配 | 保留卡片但禁用动作。 |
| 路由不可用 | 返回错误并保持当前页面。 |
| 摘要为空 | 展示空状态和推荐动作。 |
| 某个来源读取失败 | 继续展示其它来源。 |

## 与其它模块的关系

| 模块 | 大厅模块如何交互 |
| --- | --- |
| 基础能力 | 使用路由、局域网发现、二维码扫码、加密、设备认证和通用 UI。 |
| 创建房间模块 | 打开创建入口，等待创建成功后进入房间。 |
| 房间模块 | 消费 `RoomSummary`、发现摘要和重连摘要；把加入策略、观战策略、重连和房间恢复交给房间模块。 |
| 玩家模块 | 不直接交互。 |
| 狼人杀房间模块 | 不直接交互，只展示游戏房间名、地图名和房间摘要。 |
| 偏好设置模块 | 提供偏好设置入口；可读取昵称和头像用于展示。 |
| 模型管理模块 | 提供模型配置入口。 |
| 机器人/RAG 模块 | 提供机器人配置入口。 |
| TTS 语音模块 | 提供声音配置入口。 |

## 文件归属

当前相关代码主要在：

```text
scripts/pages/lobby_page.gd
scripts/pages/lobby/lobby_page_flow.gd
scripts/pages/base/page_scan_join_flow_base.gd
scripts/pages/base/page_room_discovery_ui_base.gd
scripts/pages/base/page_identity_ui_base.gd
scripts/pages/base/page_room_network_ui_base.gd
scripts/pages/base/page_room_participant_ui_base.gd
scripts/pages/base/page_room_replica_ui_base.gd
scripts/pages/base/page_room_join_ui_base.gd
scripts/pages/base/page_room_host_peer_ui_base.gd
scripts/core/app_state.gd
scripts/core/app_router.gd
scripts/network/lan_room_discovery.gd
scripts/room/room_session_store.gd
scripts/room/network/room_replica.gd
```

后续如果调整代码，优先保持大厅“只聚合展示和发起动作”的边界，不把创建、二维码、扫码、加密、认证、重连或规则执行塞回大厅。

## 维护规则

- 大厅只消费摘要数据，不读取完整房间权威状态。
- 大厅只做路由和模块命令分发，不直接执行二维码解析、设备认证、房间加入策略、重连或创建状态初始化。
- 房间卡片必须先归一化再渲染，避免本机房间、发现房间和重连卡片各自复制展示逻辑。
- 新增入口时，先明确目标模块，再增加大厅动作。
- 新增房间摘要字段时，同步房间模块的 `RoomSummary` 契约和大厅卡片归一化。
- 偏好设置入口只打开偏好设置模块；大厅消费偏好时只读取昵称和头像等展示字段。
- 扫码失败提示、二维码字段、加密协商和设备认证不写在大厅模块，归基础能力；房间密码、加入 token、容量和观战策略不写在大厅模块，归房间模块。
