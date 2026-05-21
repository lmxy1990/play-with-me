# 狼人杀快照复盘回合恢复

更新时间：2026-05-16

本文描述狼人杀房间模块如何提供视角快照、复盘回合数据和主机接管恢复材料。房间模块负责包装、分发、保存副本和认证，狼人杀房间模块负责玩法内容和下发策略。

## build_rule_snapshot

```text
build_rule_snapshot(request) -> WerewolfRuleSnapshot
```

`request`：

| 字段 | 说明 |
| --- | --- |
| `state` | 当前规则权威状态。 |
| `players` | 当前玩家列表。 |
| `viewer_context` | 快照接收者。 |
| `visibility` | `public`、`player_private`、`observer_safe`、`replay_round`。 |

约定：

- 公开快照不能包含隐藏身份、夜晚私有结果和狼人私聊。
- 玩家私有快照只包含该玩家应看到的信息。
- 观察者快照按房间观战策略过滤。
- 复盘回合快照必须在游戏结束后由狼人杀房间模块显式生成。

## build_replay_data

```text
build_replay_data(request) -> WerewolfReplayData
```

复盘数据由狼人杀房间模块在 `replay_round` 回合生成，房间模块只保存引用和分发结果。复盘不是页面；页面或场景只能渲染该回合下发的数据。

`WerewolfReplayData` 至少包含：

| 字段 | 说明 |
| --- | --- |
| `room_id` | 房间 ID。 |
| `map_id` | 地图 ID。 |
| `player_count` | 玩家人数。 |
| `players` | 玩家公开资料、座位、最终身份和阵营。 |
| `phase_timeline` | 阶段推进时间线。 |
| `night_timeline` | 夜晚行动时间线。 |
| `speech_timeline` | 公开发言、遗言和赛后总结。 |
| `vote_timeline` | 警长、放逐和 MVP 投票。 |
| `winner` | 胜利方。 |
| `mvp_player_id` | MVP 玩家，可选。 |
| `effect_timeline` | 可重放的展示特效摘要。 |

约定：

- 复盘回合的下发范围不等于游戏过程中的公开范围。
- 复盘数据必须由狼人杀房间模块显式构建，不能由房间模块拼接私有历史得到。
- 复盘回合数据生成失败不回滚已经完成的游戏结果。

## build_recovery_payload

```text
build_recovery_payload(request) -> WerewolfRecoveryPayload
```

主机接管和玩家重连需要恢复材料。狼人杀房间模块提供玩法恢复材料，房间模块负责副本、认证、主机任期和快照包装。

`WerewolfRecoveryPayload` 建议包含：

| 字段 | 说明 |
| --- | --- |
| `map_id` | 当前地图。 |
| `player_count` | 当前人数。 |
| `rule_state` | 当前狼人杀权威状态。 |
| `players_state` | 座位、存活、身份和行动资格。 |
| `pending_action` | 当前未完成行动，可选。 |
| `delivery_index` | 下发范围索引，用于恢复后重新构建快照。 |
| `event_watermark` | 玩法事件水位。 |

约定：

- 恢复材料必须能让新主机重新构建当前玩法状态和下一步行动请求。
- 给普通真人玩家保存的副本默认只包含自己可见数据；完整玩法恢复材料必须由房间安全策略允许后保存。
- 恢复后仍要通过 `build_rule_snapshot()` 重新生成接收者视角，不直接复用任意客户端 UI 状态。
