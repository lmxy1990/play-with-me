# 狼人杀 AI 机器人玩家输出解析

更新时间：2026-05-20

输出解析负责把模型输出转换成 `WerewolfPlayerActionResult`。解析器只做严格解析、字段校验和结果归一化，不猜测、不补字段、不生成默认行动。

模型返回分为 `text` 和 `json` 两种模式，模式由行动类型决定，见 [上下文与返回契约](context-output-contract.md)。

行动类 JSON 字段定义见 [行动输出 Schema](action-output-schemas.md)。

模型调用失败和解析失败的错误处理见 [失败处理](failure-handling.md)。

## 解析步骤

1. 读取模型返回文本。
2. 根据 `output_mode` 解析为纯文本或 JSON 对象。
3. 校验 `action_type` 是否匹配当前行动请求。
4. 校验必填字段是否存在。
5. 校验模型输出的 `targetSeatNumber` 是否来自本次 schema 构建器生成的合法目标集合。
6. 校验文本字段，不改写发言正文。
7. 把细分动作归一化为狼人杀房间模块接受的行动类型。
8. 生成 `WerewolfPlayerActionResult`。
9. 附带解析报告到 `metadata`。

任一步失败，立即返回结构化错误。

## 行动归一化

| 模型输出 | 归一化结果 |
| --- | --- |
| 公开发言 | `action_type = speak`，写入 `speech_text`。 |
| 狼队交流 | `action_type = wolf_chat`，写入私有 `speech_text` 和内部意图。 |
| 遗言 | `action_type = last_words`，写入 `speech_text`。 |
| 赛后总结 | `action_type = post_game_summary`，写入 `speech_text`。 |
| 狼人目标 | `action_type = wolf_kill`，写入目标。 |
| 守护目标 | `action_type = guard_protect`，写入目标。 |
| 查验目标 | `action_type = seer_check`，写入目标。 |
| 女巫救人 | `action_type = witch_act`，写入救人目标。 |
| 女巫毒人 | `action_type = witch_act`，写入毒人目标。 |
| 女巫跳过 | `action_type = witch_act`，写入跳过结果。 |
| 警长投票 | `action_type = sheriff_vote`，写入目标。 |
| 警长发言顺序 | `action_type = sheriff_speech_order`，写入首发言目标和方向动作。 |
| 飞警徽 | `action_type = sheriff_badge_action`，写入新警长目标。 |
| 撕警徽 | `action_type = sheriff_badge_action`，写入无目标结果。 |
| 放逐投票 | `action_type = vote`，写入目标。 |
| 猎人开枪 | `action_type = hunter_shoot`，写入目标。 |
| 猎人跳过 | `action_type = hunter_shoot`，写入跳过结果。 |
| MVP 投票 | `action_type = mvp_vote`，写入目标。 |

## 行动类 JSON 校验

行动类输出必须满足：

- 根节点必须是 JSON 对象。
- `action` 必须来自当前上下文允许的 action。
- 必填字段必须存在。
- 只允许 `action`、`targetSeatNumber` 两个字段。
- 需要模型选择目标的行动必须返回 `targetSeatNumber`。
- 需要目标的行动必须返回合法 `targetSeatNumber`；无目标 action 必须返回 `targetSeatNumber = -1`。
- `targetSeatNumber` 必须是 JSON number，不接受字符串。
- `targetSeatNumber` 必须来自本次合法目标集合。
- 允许跳过或无目标的行动必须按 schema 返回 `skip`、`sheriff_badge_destroy` 或对应枚举。

解析成功后，内部归一化结果可以携带 `target_seat_number` 和 `target_index`，供狼人杀房间模块适配层使用。

解析器不得做这些事：

- 从自然语言中提取目标。
- 从玩家名字反推目标。
- 自动选择第一个目标。
- 自动生成跳过结果。
- 忽略多余解释文本继续解析。
- 接受 `reason`、`debugReason`、`target_index`、`target_id`、`playerId` 或其它未知字段。

## 文本校验

- 发言类输出必须是纯文本。
- 发言文本为空时返回结构化错误。
- 发言文本不裁剪、不改写、不润色。
- 模型解释和推理过程不得作为发言正文自动提交。
- UI 可以在发言原文之外二次展示解释或标签，但 `speech_text` 原文不能被替换。

## 解析错误

解析失败时返回结构化错误，不生成 `WerewolfPlayerActionResult` 行动内容。

示例：

```json
{
  "turn_id": "turn_042",
  "actor_seat_number": 3,
  "action_type": "vote",
  "source": "ai_model",
  "error": {
    "code": "ai_output_parse_failed",
    "message": "模型输出无法按当前 schema 解析",
    "stage": "output_parsing"
  },
  "metadata": {
    "output_mode": "json",
    "model_request_id": "model_req_001"
  }
}
```

解析错误不得写入房间历史、结构化记录、机器人记忆或 TTS。
