# 详细设计

更新时间：2026-05-19

本文说明 Play With Me 当前代码中的关键数据结构、页面流程和运行时设计。

## 核心数据结构

### AppState

`scripts/core/app_state.gd` 保存应用共享状态：

- `rooms`：大厅房间列表，包含房名、状态、游戏房间、地图、人数、密码状态、地址和背景图。
- `players`：当前房间座位数组，每个元素表示空座、真人或机器人。
- `active_room_id`：当前进入的房间。
- `werewolf`：当前狼人杀规则状态。
- `history`：房间历史消息。
- `model_configs`、`voice_configs`、`memory_configs`：模型、声音和记忆配置。Android 真机上模型配置会优先从 SQLite 读取，`AppState.model_configs` 作为运行时副本和桌面/编辑器 JSON 路径。
- `local_player_index`、`local_nickname`、`bot_serial`：本机玩家和机器人序号。

状态保存到 `user://play_with_me_state.json`，结构版本由 `STATE_VERSION` 管理。Android 真机第一次发现 SQLite 模型配置为空时，按当前配置入口重新创建模型配置。

### Model Config

模型配置字段：

- `id`：整数自增主键。
- `name`：模型名，也是界面和机器人绑定时使用的展示名。
- `model`：运行时模型 ID。
- `provider`：供应商 ID，例如 `openai_api`、`anthropic`、`gemini`、`ollama`。
- `endpoint`、`api_key`
- `max_context`：界面 `MaxContext` 对应的最大上下文 token，单个新增、编辑和批量新增都可设置，默认 `262144`。
- `context_window_tokens`：运行时上下文预算，保存时由 `max_context * 0.7` 派生。
- `max_output`：最大输出 token，单个新增和编辑界面可设置，默认 `4096`；批量新增不展示该字段，使用默认值。
- `temperature`
- `reasoning`

模型配置不再使用 `active` 字段。机器人优先按玩家绑定的模型名选择配置，未绑定时使用第一个可用配置。

模型配置界面展示 `MaxContext` 时直接显示 token 数，不带单位。保存时 `max_context` 为：

```text
界面输入值
```

运行时 `context_window_tokens` 按 `max_context * 0.7` 派生。Android 真机持久化表位于 `ai_memory.sqlite` 的 `model_configs` 表，桌面/编辑器通过 `user://play_with_me_state.json` 保存当前数据。不符合当前结构的模型配置直接丢弃。

### Room

房间数据由 `AppState.create_room()` 生成，主要字段包括：

- `id`、`name`、`type`
- `state`：等待中、游戏中、已结束等展示状态。
- `players`：大厅卡片人数文本。
- `max_players`：房间席位数，当前狼人杀支持 6 到 9 人。
- `lock`、`password`
- `map_id`、`map_display_name`
- `bg`：大厅卡片和房间桌面背景。
- `allow_observers`、`max_observers`

### Player

玩家座位统一使用字典结构：

- `id`：玩家或机器人 ID。
- `name`：显示名。
- `role_key`、`role`：规则身份和中文身份名。
- `avatar`：头像资源路径。
- `state`：等待、已准备、死亡、复盘等。
- `motion`：`IDLE`、`THINKING`、`SPEAKING`、`DEAD`。
- `alive`、`ready`
- `owner`：空字符串、`self`、`human`、`bot`。
- `participant_id`：网络参与者 ID。
- `controller_participant_id`：机器人所属参与者。
- `model`、`memory`、`voice`：机器人绑定配置名。

### Werewolf State

`scripts/room/werewolf/werewolf_engine.gd` 的 `default_state()` 定义狼人杀规则状态：

- `phase`：`lobby`、`wolf_action`、`guard_action`、`seer_action`、`witch_action`、`day_discussion`、`vote`、`last_words`、`hunter_action`、`game_over` 等。
- `day`：当前天数。
- `started`：是否已开局。
- `current_action`：当前需要选择目标的行动。
- `speech_index`：当前发言座位。
- `night`：夜晚刀口、守护、女巫救毒数据。
- `votes`：投票记录。
- `spoken_indices`：本轮已发言座位。
- `last_words_pending`、`last_words_used`：遗言队列。
- `sheriff_player_index`、`has_sheriff`：警长相关状态。
- `winner`、`post_game`：胜负、赛后总结和 MVP。

## 页面设计

### 大厅页

文件：`scripts/pages/lobby_page.gd`

大厅负责展示本地房间、发现到的局域网房间和可重连房间。顶部工具栏提供刷新、创建房间、扫码加入、模型配置、记忆配置和声音配置入口。房间卡展示封面、游戏房间、地图、人数、密码状态和地址。

创建房间弹层使用书页风格弹层，输入游戏房间、地图、席位和密码。确认后调用 `AppState.create_room()`，启动本机房主网络，发布局域网发现信息，并进入游戏桌。

### 游戏桌页

文件：`scripts/room/werewolf/werewolf_room_page.gd`

游戏桌将房间和对局合并到一个页面：

- `TableSurface` 负责桌面和昼夜氛围。
- `SeatCard` 负责座位头像、身份、名字、状态和动效。
- `EffectLayer` 负责查验、投票、刀人、守护、用药、死亡等全屏反馈。
- 顶部中间显示地图和进程条。
- 左上角显示人数和交互状态。
- 右上角提供二维码、历史、复盘和退出。
- 左下角提供准备/取消准备。

点击空座位时显示落座/切换和添加机器人气泡；点击已占座位时显示座位详情。当前有行动时，点击目标座位会提交规则行动或发送网络请求。

### 配置页

文件：

- `scripts/pages/config/model_config_page.gd`
- `scripts/pages/config/voice_config_page.gd`
- `scripts/pages/config/memory_config_page.gd`
- `scripts/pages/config/config_page_base.gd`

配置页共享列表外壳和右侧抽屉样式。模型配置保存供应商、模型、Endpoint、API Key、MaxContext、MaxOutput 和温度。模型批量新增弹层左侧提供连接参数、MaxContext、获取模型和批量添加操作，右侧只展示可勾选模型列表，并支持触屏拖拽滚动；获取、保存和测试结果通过 toast 展示。声音配置保存引擎、音色、语速、音调、音量、启用状态和主用状态；新增声音默认启用但不设为主用，编辑声音可在同一状态行里切换启用和主用。记忆配置保存名称、范围和摘要。

### 复盘页

文件：`scripts/pages/replay_page.gd`

复盘页读取当前 `AppState` 中的玩家、历史和 `werewolf.post_game`，展示本局结果、地图、最终身份、存活/死亡状态、MVP 和关键时间线。

## 主要运行流程

### 启动流程

1. Godot 打开 `scenes/main.tscn`。
2. `app_router.gd` 创建 `AppState` 和 `RoomNetworkSession`。
3. `AppState.load_or_create()` 读取本地状态。
4. 路由器加载 `lobby` 页面并注入共享状态和网络会话。

### 创建房间流程

1. 大厅打开创建房间弹层。
2. 用户选择席位、地图和密码。
3. `AppState.create_room()` 创建房间和空座位。
4. `RoomNetworkSession.start_host()` 启动 WebSocket 房主。
5. `LanRoomDiscovery.publish()` 广播房间信息。
6. 路由切换到游戏桌。

### 加入房间流程

1. 客户端通过扫码或粘贴加入码得到 `QrJoinPayload`。
2. v2 安全二维码先读取外层 `IP:端口`，再通过 `RoomNetworkSession.connect_to_secure_qr()` 连接房主 WebSocket。
3. 客户端和房主交换设备身份，客户端发送 `qr_secret_request`，房主用临时 RSA 公钥包装二维码 AES 密钥并返回 `qr_secret_response`。
4. 客户端解密得到 `roomId`、加入 token、观战标记、房主身份和协议版本，校验通过后发送加入、观战或重连请求。
5. 房主登记参与者并下发房间快照。
6. 客户端应用快照并显示游戏桌。

扫码加入的格式和失败提示见 `docs/modules/base/qr_scan_join.md`。

### 准备和开局流程

1. 玩家落座后可准备。
2. `RoomRuntime.start_gate()` 判断 6 到 9 人且全部准备。
3. 满足条件时调用 `WerewolfEngine.start_game()`。
4. 引擎按地图规则配置发牌并进入首个阶段。
5. 页面根据 `current_action` 或 `speech_index` 展示交互入口。

### 狼人杀规则流程

规则引擎按阶段推进：

```text
准备
  -> 警长竞选/警长投票（地图规则配置启用时）
  -> 夜晚：狼人、守卫、预言家、女巫
  -> 夜晚结算
  -> 遗言（有死亡且允许时）
  -> 白天发言
  -> 放逐投票
  -> 猎人行动（满足条件时）
  -> 胜负判断
  -> 下一夜或游戏结束
  -> 赛后总结
  -> MVP 投票
```

地图规则配置由 `scripts/room/werewolf/werewolf_map_catalog.gd` 汇总：

- `标准村庄规则`：标准预女猎。
- `猎人压力村规则`：猎人压力局。
- `快节奏村庄规则`：无女巫快节奏。
- `守卫村庄规则`：守卫标准局。
- `警长广场规则`：警长预女猎。
- `警长守卫广场规则`：警长守卫局。

### AI 机器人流程

1. 狼人杀房间模块推进到某个玩家需要发言或行动。
2. 主机创建 `player_speech` 或 `player_action` device task，并路由到该玩家的控制设备。
3. 接收设备根据本机绑定判断该玩家是真人还是 AI 机器人；真人打开 UI，AI 机器人走本机控制器。
4. AI 控制器读取本机机器人档案，使用 `model_profile_name` 从本机模型数据库读取并缓存完整 `ModelProfile`。
5. AI 控制器构造当前玩家视角下的 prompt 和 schema，通过基础模型推理能力 `complete_request()` 调用模型。
6. 返回内容被解析成结构化行动或发言，经玩家模块可信通道回到主机。
7. 行动合法时提交给狼人杀房间模块校验和推进。
8. 模型不可用、返回异常、结构化输出不合法或目标非法时，返回错误并中止当前游戏流程，不生成本地兜底行动。
9. 对局过程写入本局记忆；游戏结束后，赛后发言结束，再按身份 debug 打印历史文本、写入记忆模块并清空上一局数据。

狼人夜聊由 `werewolf_wolf_private_flow.gd` 维护私聊记录、目标意图和目标票。私聊只对狼人视角可见，房间快照会按参与者身份过滤。

### 网络同步流程

房主维护权威状态。客户端不直接改本地规则状态，而是发送 `switch_seat`、`player_ready`、`add_bot`、`game_action`、`chat_message` 等消息。房主处理后通过 `RoomNetworkSnapshotBuilder` 生成面向每个参与者的快照。

快照会根据参与者身份过滤：

- 本人可见自己的身份。
- 狼人可见狼队信息和狼人私聊。
- 观察者只读，不发送改变房间的消息。
- 非狼人不会收到狼人私聊。

### 房主接管流程

房主会广播签名房间副本。客户端保存最新可信副本。房主断线后，客户端根据副本、参与顺序、快照版本和设备身份排序候选主机；胜出的设备恢复房间状态并启动新房主，其他客户端使用重连会话自动连接新房主。

### TTS 播报流程

1. 房间历史新增消息。
2. `TtsHistoryController` 根据声音配置生成播报项。
3. `TtsRuntime` 校验引擎、音色和参数。
4. 桌面/编辑器调用 Godot 系统 TTS。
5. Android 真机调用 `PlayWithMeAndroid` 的系统 TTS、Kokoro/Sherpa 或应用内非系统 TTS。
6. 播报状态回写到座位动效。

## 资源绑定

背景图位于 `assets/images/werewolf/backgrounds/`：

- `lobby.png`
- `day.png`
- `night.png`
- `map_basic.png`
- `map_hunter_pressure.png`
- `map_quick_no_witch.png`
- `map_guard_standard.png`
- `map_sheriff_standard.png`
- `map_sheriff_guard.png`

地图背景绑定同时存在于：

- `scripts/core/app_state.gd`
- `scripts/pages/base/page_navigation_ui_base.gd`

角色头像位于 `assets/images/werewolf/avatars/`，行动图标位于 `assets/images/werewolf/actions/`。

