# 狼人杀行动与校验

更新时间：2026-05-20

本文描述狼人杀房间模块下发行动请求、接收行动结果和校验行动合法性的规则。玩家适配层负责收集真人玩家或 AI 机器人玩家输出；最终接受与否只由狼人杀房间模块决定。

## 行动目录

| 行动类型 | 触发阶段 | 结果要求 |
| --- | --- | --- |
| `speak` | 警长竞选或白天发言 | 提交公开 `speech_text`。 |
| `wolf_chat` | 狼人夜晚沟通 | 提交狼队私有 `speech_text`。 |
| `last_words` | 遗言 | 提交遗言 `speech_text`。 |
| `post_game_summary` | 赛后总结 | 提交赛后总结 `speech_text`。 |
| `wolf_kill` | 狼人行动 | 提交目标玩家。 |
| `guard_protect` | 守卫行动 | 提交守护目标，不能连续两夜守护同一人。 |
| `seer_check` | 预言家行动 | 提交查验目标，返回结果只下发给预言家。 |
| `witch_act` | 女巫行动 | 提交救人或毒人的目标；是否救或毒由当前夜晚目标和药水状态决定。 |
| `sheriff_vote` | 警长投票 | 提交警长候选目标。 |
| `sheriff_speech_order` | 警长决定发言顺序 | 提交白天首发言目标，并用动作表示顺时针或逆时针。 |
| `sheriff_badge_action` | 警徽处理 | 死亡警长选择飞警徽给一名存活玩家，或撕毁警徽。 |
| `vote` | 白天放逐投票 | 提交放逐目标。 |
| `hunter_shoot` | 猎人行动 | 提交开枪目标，或提交跳过。 |
| `mvp_vote` | MVP 投票 | 提交 MVP 目标。 |

模型输出可以有更细的内部动作，例如女巫救、女巫毒、跳过、狼队目标票、警长发言顺序方向、飞警徽和撕警徽；这些属于狼人杀 AI 玩家模块解析细节。提交给狼人杀房间模块时，必须归一化为上表中的行动类型或明确的跳过结果。

## build_action_request

```text
build_action_request(request) -> WerewolfActionRequest
```

狼人杀房间模块给玩家适配层的行动请求。

| 字段 | 说明 |
| --- | --- |
| `turn_id` | 行动请求 ID。 |
| `phase` | 当前阶段。 |
| `day` | 当前天数。 |
| `actor_player_id` | 当前行动玩家。 |
| `actor_seat_number` | 当前行动座位。 |
| `action_type` | 行动类型。 |
| `instruction_type` | 指令类型，例如 `dialog`、`action_ui`、`speech_input`、`target_select`、`confirm`。 |
| `target_options` | 可选目标。 |
| `speech_mode` | 是否允许发言、私聊或遗言。 |
| `visible_state` | 当前玩家可接收的公开状态。 |
| `private_state` | 当前玩家可接收的私有状态。 |
| `metadata` | 规则补充信息。 |

约定：

- 行动请求必须只包含狼人杀房间模块为当前行动者生成的下发数据。
- `instruction_type` 只描述真人控制器的交互承载方式；行动合法性仍由狼人杀房间模块校验。
- 真人和 AI 机器人玩家使用同一种行动请求。
- 目标列表是 UI 和 AI 机器人玩家的候选输入，不替代规则最终校验。

## submit_action_result

```text
submit_action_result(request) -> WerewolfRuleUpdateResult
```

`WerewolfPlayerActionResult` 来自狼人杀真人玩家模块或狼人杀 AI 玩家模块。

| 字段 | 说明 |
| --- | --- |
| `turn_id` | 对应行动请求 ID。 |
| `actor_player_id` | 行动玩家 ID。 |
| `action_type` | 行动类型。 |
| `target_player_id` / `target_seat_number` | 目标。 |
| `speech_text` | 发言文本，可选。 |
| `source` | `human`、`ai_model`。 |
| `metadata` | 输出解析、模型请求等附加信息。 |

校验顺序：

1. 当前阶段允许该行动。
2. 行动者是当前应行动玩家。
3. 行动者具备该身份或行动资格；猎人开枪和警徽处理允许已死亡的资格玩家行动。
4. 目标存在、可作为目标、存活，并符合行动约束；警长发言顺序的目标表示首发言玩家，飞警徽目标表示新警长，撕警徽不需要存活目标。
5. 药水、守护、猎人开枪、警长投票、警长发言顺序、警徽处理等能力或流程仍可使用。
6. 发言文本符合当前 `speech_mode`。
7. 应用玩法状态变更并推进阶段。

## submit_speech

```text
submit_speech(request) -> WerewolfRuleUpdateResult
```

约定：

- 发言是玩法输入，只有狼人杀房间模块接受后才进入房间历史和 TTS。
- 白天发言、警长竞选、遗言、狼人夜聊可以使用不同 `speech_mode`。
- 私聊内容只进入对应下发范围事件，不应作为公开历史广播给所有人。

## 失败策略

| 场景 | 策略 |
| --- | --- |
| 地图规则配置不支持当前人数 | 开局失败，不修改房间状态。 |
| 行动者不是当前玩家 | 拒绝行动。 |
| 目标不存在或不合法 | 拒绝行动或返回可展示错误。 |
| 阶段不匹配 | 拒绝行动。 |
| 文本为空但当前阶段要求发言 | 使用空发言策略或拒绝，按阶段定义。 |
| AI 输出解析失败 | 返回结构化错误，不直接修改状态。 |
| 胜负已产生后收到行动 | 拒绝行动。 |
| 状态字段缺失 | 返回结构化错误，避免继续推进。 |
