# 创建房间模块

更新时间：2026-05-15

创建房间模块是小编织模块，负责读取可创建的游戏房间模块列表、每个游戏房间模块提供的地图列表，以及每张地图支持的人数列表，并据此提供统一创建 UI。它把用户选择的游戏房间、地图、人数、密码和观战策略整理成创建请求，交给房间模块完成后续建房、开主机和发布发现，再根据返回结果路由进入房间。

创建房间模块像一个创建表单编排黑盒：它只处理可创建目录、表单状态、校验、默认值和提交顺序；不拥有房间权威状态，不保存具体游戏房间实现，也不直接执行玩法逻辑。

## 模块定位

```text
大厅点击创建房间
  -> 创建房间模块
       -> 获取可创建游戏房间模块列表
       -> 获取所选游戏房间模块的地图列表
       -> 根据地图支持人数生成席位选项
       -> 根据地图和人数获取场景与槽位列表
       -> 采集游戏房间、地图、席位、密码、观战策略
       -> 组装创建请求
       -> 提交给房间模块
       -> 接收创建结果
       -> 路由进入房间
```

创建房间模块只负责“创建入口”的统一 UI、表单校验和请求提交，不负责房间后的加入、重连、游戏房间推进或玩家交互。

## 能力边界

创建房间模块负责：

- 展示创建房间弹层和统一创建表单。
- 读取可创建游戏房间模块列表。
- 读取所选游戏房间模块提供的地图列表。
- 读取地图支持的人数列表，并生成席位数选项。
- 根据地图 ID 和人数读取对应场景与槽位列表。
- 采集游戏房间、地图、席位数、密码、观战策略等输入。
- 校验游戏房间是否可创建、地图是否属于该游戏房间、席位数是否被地图支持，以及基础表单字段。
- 生成创建请求和房间预览。
- 调用房间模块公开创建接口。
- 根据房间模块返回结果进入房间页面或保留表单。

创建房间模块不负责：

- 大厅列表渲染、房间摘要展示或重连入口。
- 二维码生成、扫码、加密、认证基础。
- 房间状态工厂、房主网络启动和局域网发现发布。
- 房间加入、重连、主机重选或断线恢复。
- 具体游戏房间的地图定义、场景、槽位布局、玩家行动、胜负判断或复盘。
- 自己维护一份游戏房间列表、地图列表、人数配置、场景或槽位配置。
- 偏好字段保存、模型配置保存、TTS 播报或机器人记忆更新。

## 内部实现

创建房间内部可以拆成五个稳定部分：

1. 可创建目录读取层：从房间模块公开接口读取 `GameRoomOption`、`GameRoomMap` 和 `GameRoomSceneSlots`。
2. 表单状态层：保存当前选择的游戏房间、地图、席位、密码和观战参数。
3. 请求组装层：把表单值转换成 `RoomCreateRequest` 和创建预览。
4. 创建提交层：调用房间模块创建接口并接收结果。
5. 路由结果层：把创建成功结果交给房间页面，失败时保留当前表单。

当前实现主要落在 `scripts/pages/lobby_page.gd::_open_create_room()` 和 `_create_room_and_enter()`，核心房间工厂在 `scripts/core/app_state.gd::create_room()`。

## 对外接口

以下接口是设计契约，不要求当前代码函数名完全一致。

```text
load_create_room_catalog(context) -> CreateRoomCatalog
open_create_room_dialog(context) -> CreateRoomViewState
build_create_room_preview(context) -> CreateRoomPreview
validate_create_room_request(request) -> CreateRoomValidationResult
submit_create_room_request(request) -> CreateRoomResult
get_create_room_debug_state(request) -> CreateRoomDebugResult
```

### load_create_room_catalog

```text
load_create_room_catalog(context) -> CreateRoomCatalog
```

约定：

- 创建房间模块只读取目录，不修改目录。
- 目录来源应是房间模块暴露的公开接口；房间模块再委派具体游戏房间模块提供数据。
- 目录包含可创建 `GameRoomOption` 列表、每个游戏房间模块的地图列表、每张地图支持的人数列表和展示元数据。
- 狼人杀房间模块必须直接提供 `GameRoomMap`，创建房间模块不能依赖狼人杀内部常量。

### open_create_room_dialog

```text
open_create_room_dialog(context) -> CreateRoomViewState
```

约定：

- 入口通常从大厅模块发起。
- 打开弹层时应先加载可创建目录，并带入默认游戏房间、默认地图和该地图默认人数。
- 视图只负责展示和选择，不直接创建房间。

### validate_create_room_request

```text
validate_create_room_request(request) -> CreateRoomValidationResult
```

`RoomCreateRequest` 建议包含：

| 字段 | 说明 |
| --- | --- |
| `game_room_id` | 游戏房间模块 ID，例如 `werewolf`。 |
| `map_id` | 地图 ID。 |
| `seat_count` | 席位数，必须来自地图支持人数列表。 |
| `password` | 房间密码，可空。 |
| `allow_observers` | 是否允许观战。 |
| `max_observers` | 最大观战人数。 |
| `scene_slots` | 根据地图和人数获取的场景与槽位列表。 |
| `display_options` | 游戏房间展示名、地图展示名、背景等展示字段。 |
| `game_room_init_options` | 传给具体游戏房间模块的初始化选项。 |

校验规则：

- `game_room_id`、`map_id` 和 `seat_count` 必填。
- `game_room_id` 必须存在于可创建目录。
- `map_id` 必须属于所选游戏房间模块。
- `seat_count` 必须出现在该地图的 `supported_player_counts` 中。
- `scene_slots` 必须来自房间模块公开接口 `get_scene_slots(game_room_id, map_id, seat_count)`。
- 未选择地图时应切换到所选游戏房间模块的默认地图；未选择人数时应切换到该地图的默认人数。
- `password` 只做格式和长度校验，不在这里做房间认证。
- `allow_observers` 和 `max_observers` 必须彼此一致。

### submit_create_room_request

```text
submit_create_room_request(request) -> CreateRoomResult
```

`CreateRoomResult` 建议包含：

| 字段 | 说明 |
| --- | --- |
| `ok` | 是否创建成功。 |
| `room_id` | 新房间 ID。 |
| `room_summary` | 创建后的房间摘要。 |
| `route` | 成功后应进入的页面。 |
| `warnings` | 非致命警告。 |
| `error` | 失败时的结构化错误。 |

约定：

- 创建成功表示房间模块已经完成必要的房间创建、主机启动和局域网发布编排，或返回了对应 warning。
- 如果创建中途失败，必须明确失败阶段，不要留下半初始化的可进入房间。
- 创建成功不等于具体游戏房间已开始，只代表房间已准备好承接后续流程。

## 核心对象

### CreateRoomCatalog

创建房间 UI 使用的可创建目录。

| 字段 | 说明 |
| --- | --- |
| `schema_version` | 目录结构版本。 |
| `game_rooms` | 可创建 `GameRoomOption` 列表。 |
| `default_game_room_id` | 默认游戏房间模块。 |
| `updated_at` | 目录更新时间。 |

### GameRoomOption

一个可创建的具体游戏房间模块。

| 字段 | 说明 |
| --- | --- |
| `game_room_id` | 稳定 ID，例如 `werewolf`。 |
| `display_name` | 展示名，例如 `狼人杀房间`。 |
| `description` | 简短说明，可选。 |
| `maps` | 该游戏房间模块提供的 `GameRoomMap` 列表。 |
| `default_map_id` | 默认地图。 |
| `icon` | 展示图标，可选。 |
| `metadata` | 扩展展示字段。 |

### GameRoomMap

一个游戏房间模块下可创建的地图。

| 字段 | 说明 |
| --- | --- |
| `map_id` | 稳定地图 ID。 |
| `map_name` | 地图展示名。 |
| `map_background` | 地图背景图 ID 或路径。 |
| `rule_text` | 地图规则摘要或规则配置引用。 |
| `map_scene` | 地图默认场景 ID 或路径。 |
| `description` | 地图说明，可选。 |
| `metadata` | 扩展展示字段。 |

### GameRoomSceneSlots

地图和人数对应的场景与槽位列表。

| 字段 | 说明 |
| --- | --- |
| `game_room_id` | 游戏房间模块 ID。 |
| `map_id` | 地图 ID。 |
| `player_count` | 玩家人数。 |
| `scene_id` | 场景 ID。 |
| `scene_path` | Godot 场景路径或资源路径。 |
| `slot_list` | 槽位列表。 |
| `metadata` | 扩展展示字段。 |

### CreateRoomViewState

创建房间弹层的展示状态。

| 字段 | 说明 |
| --- | --- |
| `catalog` | 当前可创建目录。 |
| `selected_game_room_id` | 当前游戏房间模块。 |
| `selected_game_room_display_name` | 当前游戏房间模块展示名。 |
| `selected_map_id` | 当前地图。 |
| `selected_map_display_name` | 当前地图展示名。 |
| `supported_player_counts` | 当前地图支持的人数列表。 |
| `selected_seat_count` | 当前席位数。 |
| `scene_slots` | 当前地图和人数对应的场景与槽位列表。 |
| `password` | 当前密码输入。 |
| `allow_observers` | 当前观战开关。 |
| `max_observers` | 当前观战上限。 |
| `preview` | 创建预览。 |
| `validation_state` | 当前校验结果。 |
| `confirm_enabled` | 是否允许提交。 |

### CreateRoomPreview

创建前的房间预览。

| 字段 | 说明 |
| --- | --- |
| `room_name` | 默认房间名。 |
| `lock_state` | `公开`、`密码`。 |
| `seat_count` | 总座位数。 |
| `observer_limit` | 观战上限。 |
| `game_room_display_name` | 游戏房间模块展示名。 |
| `map_display_name` | 地图展示名。 |
| `background` | 地图背景或游戏房间默认背景。 |
| `scene_path` | 当前地图和人数对应的场景路径。 |
| `status_text` | 创建提示文案。 |

### CreateRoomResult

创建流程返回值。

| 字段 | 说明 |
| --- | --- |
| `ok` | 是否成功。 |
| `room_id` | 新建房间 ID。 |
| `room_summary` | 房间摘要。 |
| `host_started` | 主机是否已启动。 |
| `published` | 是否已发布局域网发现。 |
| `route` | 进入房间的路由。 |
| `warnings` | 非致命问题。 |
| `error` | 结构化错误。 |

## 主要流程

```text
大厅点击创建房间
  -> 打开创建弹层
  -> load_create_room_catalog()
  -> 选择游戏房间模块
  -> 选择该游戏房间下的地图
  -> 从地图支持人数中选择席位
  -> 读取对应场景和槽位列表
  -> 设置密码和观战策略
  -> validate_create_room_request()
  -> 房间模块 create_room_state()
  -> 房间模块启动主机网络并发布局域网发现
  -> 路由进入房间
```

当前代码仍由 `AppState.create_room()` 承接创建，但设计目标是由房间模块公开接口生成房间基础字段：`id`、`name`、`state`、`players`、`lock`、`address`、`bg`、`password`、`max_players`、`allow_observers`、`max_observers`、`game_room_id`、`map_id`、`scene_slots` 和展示名，并初始化空座位和本机历史。创建请求只接受当前字段，字段不匹配时直接拒绝。

## 失败处理

| 场景 | 策略 |
| --- | --- |
| 可创建目录加载失败 | 保留入口，提示无法创建，允许再次发起。 |
| 游戏房间模块或地图无效 | 阻止提交，保留当前表单。 |
| 席位数不在地图支持人数列表 | 返回 validation error。 |
| 场景槽位获取失败 | 返回 validation error，不提交创建请求。 |
| 密码为空但被要求加密房间 | 返回 validation error。 |
| 房间模块返回主机启动失败 | 保留表单，不进入房间。 |
| 房间模块返回局域网发布 warning | 展示 warning，是否继续由房间模块结果决定。 |
| 保存房间状态失败 | 返回 error，不进入房间。 |

## 与其它模块的关系

| 模块 | 创建房间模块如何交互 |
| --- | --- |
| 大厅模块 | 大厅打开创建入口，创建成功后路由回房间。 |
| 房间模块 | 提供可创建游戏房间目录和房间创建公开接口；负责生成房间状态、启动主机网络、发布发现，并接管后续权威状态。 |
| 基础能力 | 使用路由、共享状态和通用网络桥接；不实现二维码、扫码、加密或认证。 |
| 偏好设置模块 | 可读取昵称和头像作为默认展示，但不修改偏好数据。 |
| 玩家模块 | 创建时可使用玩家工厂生成默认空位和本机玩家数据。 |
| 具体游戏房间模块 | 提供地图、支持人数、场景槽位和展示元数据；创建模块只读取，不执行玩法逻辑。 |
| 模型管理 / TTS / 机器人 | 不直接交互。 |

## 文件归属

当前相关代码主要在：

```text
scripts/pages/lobby_page.gd
```

## 维护规则

- 创建房间只负责可创建目录、统一 UI、表单校验和提交请求，不把房间权威状态、网络启动、发现发布、游戏房间推进或玩家策略塞进来。
- 创建 UI 的游戏房间、地图、支持人数、场景和槽位必须来自可创建目录，不允许在 UI 里手写某个游戏的地图和人数列表。
- 新增创建字段时，同步创建表单、`RoomCreateRequest`、房间模块创建接口、房间摘要和大厅卡片展示。
- 密码和观战字段变化时，确认不会污染二维码明文或偏好设置。
- 创建失败必须保留可用表单状态，方便用户再次发起。
- 地图、支持人数、场景、槽位、背景和房间默认文案变化时，由对应具体游戏房间模块更新目录元数据，创建模块只同步展示和预览消费。
