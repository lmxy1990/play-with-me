# 狼人杀房间接口

更新时间：2026-05-20

本文固定狼人杀房间模块对外公开的设计接口。具体 Godot 函数名可以调整，但跨模块只能通过这些能力进入狼人杀房间模块。

字段权威见 [跨模块契约](../../../contracts/README.md)。

## 接口列表

```text
default_state() -> WerewolfRuleState
get_map_list() -> GameRoomMap[]
get_supported_player_counts(map_id) -> int[]
get_scene_slots(map_id, player_count) -> GameRoomSceneSlots
start_game(request) -> WerewolfRuleUpdateResult
build_action_request(request) -> WerewolfActionRequest
submit_action_result(request) -> WerewolfRuleUpdateResult
submit_speech(request) -> WerewolfRuleUpdateResult
skip_current_action(request) -> WerewolfRuleUpdateResult
build_rule_snapshot(request) -> WerewolfRuleSnapshot
build_replay_data(request) -> WerewolfReplayData
build_recovery_payload(request) -> WerewolfRecoveryPayload
phase_label(state) -> String
get_werewolf_rule_debug_state(request) -> WerewolfRuleDebugResult
```

## 房间目录接口

```text
get_map_list() -> GameRoomMap[]
get_supported_player_counts(map_id) -> int[]
get_scene_slots(map_id, player_count) -> GameRoomSceneSlots
```

约定：

- `get_map_list()` 返回狼人杀可创建地图。
- 地图对象包含 `map_id`、`map_background`、`rule_text`、`map_name`、`map_scene` 和展示扩展数据。
- `get_supported_player_counts(map_id)` 返回该地图支持的人数列表。
- `get_scene_slots(map_id, player_count)` 返回狼人杀房间使用的具体场景和槽位列表。
- 房间模块只保存和下发这些结果，不解释狼人杀地图或槽位含义。

## start_game

```text
start_game(request) -> WerewolfRuleUpdateResult
```

`StartGameRequest`：

| 字段 | 说明 |
| --- | --- |
| `room_id` | 房间 ID。 |
| `players` | 房间座位上的玩家基础数据。 |
| `occupied_indices` | 参与本局的座位索引。 |
| `map_id` | 地图 ID。 |
| `host_context` | 房主上下文，可选。 |

约定：

- 开局前由房间模块校验人数和 ready；狼人杀房间模块仍要校验地图规则配置是否支持该人数。
- 狼人杀房间模块负责洗牌和发身份。
- 创建房间阶段使用的地图和支持人数来自狼人杀房间模块暴露的目录元数据；创建房间模块不直接读取狼人杀内部地图规则常量。
- 开局成功后返回新的玩法状态、更新后的玩家列表、初始历史和当前行动请求。
- 开局失败不修改房间状态。

## 核心对象

### WerewolfRuleState

狼人杀权威状态，只能由狼人杀房间模块写入。

| 字段 | 说明 |
| --- | --- |
| `phase` | 当前阶段，例如 `lobby`、`sheriff_speech`、`sheriff_vote`、`wolf_action`、`sheriff_badge_action`、`sheriff_speech_order`、`day_discussion`、`vote`、`last_words`、`hunter_action`、`game_over`、`replay_round`、`post_game_summary`、`mvp_vote`、`completed`。 |
| `day` | 当前天数。 |
| `started` | 是否已经开局。 |
| `current_action` | 当前行动描述。 |
| `speech_index` | 当前发言座位索引。 |
| `night` | 当前夜晚行动数据。 |
| `votes` | 当前投票数据。 |
| `spoken_indices` | 已发言玩家。 |
| `day_speech_order` | 当前白天发言顺序；有存活警长决定发言顺序时写入。 |
| `day_speech_order_start_index` / `day_speech_order_direction` / `day_speech_order_day` | 当前白天发言起点、方向和生效天数。 |
| `last_words_pending` | 待遗言玩家。 |
| `last_words_used` | 已使用遗言玩家。 |
| `last_guarded_index` | 上次守护目标。 |
| `seer_check_history` | 预言家查验历史。 |
| `witch_antidote` / `witch_poison` | 女巫药水状态。 |
| `sheriff_player_index` | 当前警长。 |
| `sheriff_badge_dead_index` / `sheriff_badge_return_phase` / `sheriff_badge_candidates` | 警长死亡后的警徽处理上下文，用于在飞警徽或撕警徽后回到触发前结算路径。 |
| `map_id` / `map_name` / `map_scene` / `map_rule_text` | 当前地图信息和规则文本。 |
| `has_sheriff` | 是否启用警长流程，包括警长竞选、警徽处理、发言顺序和票权。 |
| `winner` | 胜利方。 |
| `post_game` | 复盘回合数据、赛后总结和 MVP 投票。 |

### GameRoomMap

狼人杀可创建地图对象。

| 字段 | 说明 |
| --- | --- |
| `id` | 地图 ID。 |
| `name` | 展示名。 |
| `description` | 简短描述。 |
| `scene` | 地图场景。 |
| `background` | 地图背景资源。 |
| `rule_text` | 当前地图规则文本。 |
| `has_sheriff` | 是否启用警长流程。 |
| `supported_player_counts` | 支持人数。 |

### WerewolfRuleUpdateResult

规则更新结果。

| 字段 | 说明 |
| --- | --- |
| `ok` | 是否成功。 |
| `players` | 更新后的玩家列表。 |
| `werewolf` | 更新后的玩法状态。 |
| `history` | 新增下发历史候选；公开、私有和复盘回合材料必须按事件下发范围拆分。 |
| `public_events` | 新增公开事件，可选。 |
| `private_events` | 新增私有事件，可选。 |
| `temporary_game_data` | 需要房间下发的临时数据。 |
| `effect_requests` | 本次接受结果对应的展示特效请求，由房间 UI 或场景层消费。 |
| `death_indices` | 本次死亡座位。 |
| `message` | 可展示状态文案。 |
| `next_action_request` | 下一步行动请求。 |
| `error` | 失败时的结构化错误。 |

## 只读调试

```text
get_werewolf_rule_debug_state(request) -> WerewolfRuleDebugResult
```

只读调试信息建议包含：

- 当前地图规则配置、阶段、天数、当前行动。
- 当前玩家存活状态和公开状态。
- 当前夜晚行动收集进度。
- 当前投票和发言进度。
- 胜负判断输入和结果。
- 最近一次行动结果和狼人杀房间模块拒绝原因。
- 下发范围检查摘要。

调试接口不得推进阶段，不返回机器人记忆、模型请求正文、API Key 或设备私钥。
