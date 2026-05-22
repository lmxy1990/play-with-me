# 狼人杀地图目录

更新时间：2026-05-22

狼人杀房间模块按地图拆分规则包。每张地图对应一个独立文档和一个目标实现目录，规则包负责该地图下的人数、身份、阶段、行动、下发策略和推理上下文。公共狼人杀执行层只做调度，不把所有地图差异堆在一个大文件里。

## 地图索引

| 地图文档 | `map_id` | `rule_text` | 支持人数 | 定位 |
| --- | --- | --- | --- | --- |
| [标准村庄](basic_village.md) | `basic_village` | `标准村庄规则` | 6、7、8、9、10、11、12 | 标准村庄，默认地图。 |
| [猎人压力村](hunter_pressure_village.md) | `hunter_pressure_village` | `猎人压力村规则` | 6、7、8、9、10、11、12 | 提高猎人存在感，强化白天压力。 |
| [快节奏村庄](quick_no_witch_village.md) | `quick_no_witch_village` | `快节奏村庄规则` | 6、7、8、9、10、11、12 | 去掉女巫节奏，缩短夜晚分支。 |
| [守卫村庄](guard_village.md) | `guard_village` | `守卫村庄规则` | 6、7、8、9、10、11、12 | 启用守卫和连续守护限制。 |
| [警长广场](sheriff_square.md) | `sheriff_square` | `警长广场规则` | 7、8、9、10、11、12 | 启用警长竞选、警长发言顺序、警徽处理和警长票权。 |
| [警长守卫广场](sheriff_guard_square.md) | `sheriff_guard_square` | `警长守卫广场规则` | 7、8、9、10、11、12 | 警长发言顺序、警徽处理、警长票权和守卫流程同时启用。 |

## 创建目录规则

- `get_map_list()` 返回 `GameRoomMap[]`，每个地图对象必须包含 `map_id`、`map_background`、`rule_text`、`map_name`、`map_scene`。
- `rule_text` 是地图规则摘要或配置引用，创建房间 UI 只展示，不解释。
- `get_supported_player_counts(map_id)` 返回人数列表，创建房间 UI 只能用这个接口生成可选人数。
- `get_scene_slots(map_id, player_count)` 返回该地图和人数对应的场景与槽位，槽位数量必须等于玩家人数。
- 同一张地图可以在不同人数下返回不同槽位坐标、视角层级、观察者入口和系统展示槽。
- 开局时以 `map_id + player_count` 为准再次解析地图规则配置；创建请求携带的数据不可信，必须重新校验。

## 地图加席位锁定规则

狼人杀创建房间时，具体规则由 `map_id + seat_count` 锁定。`map_id` 决定地图规则包，`seat_count` 决定本局使用的席位列表、身份分布、阶段计划、行动策略、下发策略和复盘策略。

每张地图文档必须包含：

| 内容 | 说明 |
| --- | --- |
| 地图名称 | 给创建房间 UI、房间摘要和复盘回合使用。 |
| 简单描述 | 一句话说明地图定位。 |
| 详细规则 | 说明身份、阶段、行动、投票、胜负、赛后和特殊推理。 |
| 席位列表 | 每个支持人数下的 `seat_1` 到 `seat_n`。 |
| 身份分布 | 每个支持人数下的身份池。默认开局洗牌后绑定到具体席位。 |

约定：

- `seat_count` 必须来自该地图的支持人数列表。
- 6 人局使用屠城胜负条件；超过 6 人局使用屠边胜负条件。
- `seat_list` 是场景槽位和规则席位的统一来源。
- `role_distribution` 是身份池，不表示某个席位固定某个身份。
- 开局时狼人杀房间模块基于身份池洗牌，再把身份绑定到已经占用的席位。
- 如果某张地图需要固定席位身份，必须在该地图文档的详细规则中显式声明。
- 地图和席位锁定后，玩家适配层、UI 和 AI 机器人玩家只能消费行动请求和当前玩家输入数据，不再推导地图规则。

## 地图规则包

地图规则包至少包含：

| 能力 | 说明 |
| --- | --- |
| 地图元数据 | `map_id`、地图名称、背景、默认场景、展示说明。 |
| 人数配置 | 该地图支持的人数列表，以及每个人数对应的身份配置。 |
| 场景槽位 | 该地图在不同人数下的 `GameRoomSceneSlots`。 |
| 阶段编排 | 开局后阶段顺序，例如是否启用警长、是否启用守卫行动。 |
| 行动目录 | 当前地图允许的行动类型、行动者选择规则和目标候选规则。 |
| 行动校验 | 每个行动在该地图下是否合法。 |
| 结算推理 | 夜晚死亡、投票结果、猎人开枪、胜负判断等规则推理。 |
| 下发策略 | 根据身份、座位、阶段和事件类型决定每个接收者收到哪些记录。 |
| 特效映射 | 已接受结果应触发的展示特效请求。 |
| 复盘节点 | 游戏结束后该地图在复盘回合允许公开的材料。 |
| 推理上下文摘要 | 提供给玩家适配层的当前玩家输入提示，例如当前地图重点、可选行动解释、票权说明。 |

每个地图规则包必须明确夜晚结算和死亡信息的下发规则：

- 平安夜公开文案如何生成。
- 死亡公告是否公开死因。
- 死亡玩家本人是否知道死因。
- 女巫救人、毒人和剩余药水状态分别下发给谁。
- 狼人击杀目标、狼人夜聊和狼队目标票分别下发给谁。
- 守卫目标、连续守护限制和守护结果分别下发给谁。
- 猎人开枪资格、开枪行为和开枪结果分别下发给谁。
- 哪些权威事实只能在复盘回合公开。

## 地图规则包接口

```text
map_metadata() -> GameRoomMap
supported_player_counts() -> int[]
build_scene_slots(player_count) -> GameRoomSceneSlots
build_role_config(player_count) -> WerewolfRoleConfig
build_phase_plan(player_count) -> WerewolfPhasePlan
build_initial_rule_state(request) -> WerewolfRuleStatePatch
build_action_request(state, players, actor) -> WerewolfActionRequestPatch
validate_action(state, players, action_result) -> WerewolfActionValidationResult
apply_action(state, players, action_result) -> WerewolfRuleUpdatePatch
resolve_phase(state, players) -> WerewolfPhaseResolution
build_delivery_policy(state, viewer_context) -> WerewolfDeliveryPolicy
build_delivery_records(state, viewer_context, events) -> WerewolfDeliveryRecord[]
build_reasoning_context_summary(state, viewer_context) -> Dictionary
build_effect_requests(update) -> WerewolfEffectRequest[]
build_replay_nodes(state, events) -> WerewolfReplayNode[]
```

约定：

- `WerewolfPhasePlan` 是狼人杀房间模块内部对象，只描述本地图的阶段顺序、自动跳过条件和阶段完成条件。
- `WerewolfRoleConfig` 是本地图本人数下的身份配置，不进入通用房间模块。
- `build_delivery_policy()` 描述当前接收者在当前阶段可收到的数据范围。
- `build_delivery_records()` 根据权威事件生成当前接收者的结构化下发记录；不同身份和座位可以得到不同记录。
- `build_reasoning_context_summary()` 只输出当前玩家本次输入需要的提示材料；隐藏身份、私密夜晚结果和狼队私聊仍由下发策略过滤。
- 规则包返回的是状态补丁、事件材料和策略结果，最终合并仍由狼人杀房间模块对外入口完成。

## 场景槽位约束

狼人杀座位是玩法输入的一部分，座位号会进入发言顺序、投票、夜晚目标和复盘。因此槽位布局必须稳定。

`GameRoomSceneSlots.slot_list` 中的玩家槽位至少需要表达：

| 字段 | 狼人杀含义 |
| --- | --- |
| `slot_id` | 稳定槽位 ID，例如 `seat_1`。 |
| `slot_index` | 从 0 开始的内部索引，用于规则执行。 |
| `slot_type` | 玩家槽位使用 `player`。 |
| `position` | 桌面或场景坐标，由狼人杀房间模块定义。 |
| `default_state` | 初始展示状态，例如空座、等待、准备。 |
| `metadata.seat_number` | 展示座位号，从 1 开始。 |
| `metadata.speech_order` | 发言顺序。 |
| `metadata.targetable` | 是否可作为玩法目标。 |

约定：

- 规则执行使用 `slot_index`，展示使用 `seat_number`。
- 玩家换座只能发生在开局前；开局后座位、身份、行动记录和历史必须绑定。
- 槽位布局只由狼人杀房间模块提供，房间 UI 不维护自己的座位坐标表。
- 地图规则包只能被狼人杀房间模块内部入口引用，不能被房间模块、创建房间模块、玩家适配层或 UI 直接引用。
