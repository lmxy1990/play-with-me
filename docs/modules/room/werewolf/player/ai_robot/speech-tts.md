# 狼人杀 AI 机器人玩家语音输出

更新时间：2026-05-16

语音输出只处理已经被狼人杀房间模块接受的文本。本模块选择本次调用使用的 `voice_profile_id`，玩家模块提供公共 TTS 文本转语音接口，TTS 语音模块负责实际播报。

## 触发条件

可以进入语音输出链路的文本：

- 狼人杀房间模块接受的公开发言。
- 狼人杀房间模块接受的遗言。
- 狼人杀房间模块接受的赛后总结。
- 规则允许本机私密播报的玩家私有提示。

不能进入语音输出链路的文本：

- 模型草稿。
- 未通过狼人杀房间模块校验的发言。
- 被拒绝的行动结果。
- 当前设备不应听到的私有文本。

## 流程

```text
狼人杀房间模块接受发言
  -> 狼人杀 AI 机器人玩家模块读取 voice_profile_id
  -> 构造 PlayerSpeechRequest
  -> 玩家模块 submit_accepted_speech()
  -> TTS 语音模块 speak_text()
  -> 返回播报请求结果
```

## PlayerSpeechRequest

建议字段：

| 字段 | 说明 |
| --- | --- |
| `player_id` | 发言玩家。 |
| `scope` | 房间、局、阶段或行动作用域。 |
| `text` | 已确认文本。 |
| `voice_profile_id` | 本次播报使用的音色 ID。 |
| `source` | `rule_accepted`。 |
| `visibility` | `public` 或 `private_local`。 |
| `accepted_at` | 狼人杀房间模块接受时间。 |
| `metadata` | `room_id`、`turn_id`、`action_type` 等调试信息。 |

## 音色来源

- 默认从 `BotProfile.voice_profile_id` 读取。
- 如果调用上下文指定本次音色 ID，以调用上下文为准。
- 玩家模块不自行选择音色。
- TTS 模块只消费调用方传入的 `voice_profile_id`。

## 失败策略

- TTS 失败不回滚狼人杀房间状态。
- TTS 失败不删除房间历史。
- TTS 失败不影响记忆更新。
- 私密播报失败只返回结构化错误，不改公开事件。

