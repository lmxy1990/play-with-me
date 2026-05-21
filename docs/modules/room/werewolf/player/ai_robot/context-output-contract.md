# 狼人杀 AI 机器人玩家上下文与返回契约

更新时间：2026-05-20

本文固定 AI 机器人玩家的上下文组织方式和模型返回方式。模型调用工具可以替换，但模块契约不能变化。

## 总体结论

- 上下文使用结构化对象组织，最终渲染成 `system prompt` 和 JSON `user prompt` 两个文本。
- `user prompt` 是可解析 JSON 对象字符串，schema 为 `play_with_me.werewolf_ai_turn.v1`。
- `current_question` 是本次唯一需要回答的问题。
- `timeline` 是当前玩家视角下的可见游戏记录。
- 合法目标集合由 schema 构建器内部生成；模型涉及目标时必须返回合法 `targetSeatNumber`。
- AI 玩家接收广播时只追加结构化记录；需要回答时才渲染 JSON `user prompt` 并调用模型。
- UI 展示使用结构化记录，不反向依赖 AI prompt 文本。
- 模型返回按行动类型分两类：发言类返回文本，行动类返回 JSON。
- 模型输出解析失败时返回结构化错误。
- 最终上报给狼人杀房间模块的结果一律归一化成 `WerewolfPlayerActionResult`。
- LangChain 可以作为模型调用层工具，但不作为当前模块契约的依赖。

## 上下文构建格式

AI 机器人玩家上下文先构建为 `WerewolfAiTurnContext`，再合并机器人记忆，最后渲染成 `ModelGenerationRequest.messages`。

```text
WerewolfPlayerTurnRequest
  -> WerewolfAiTurnContext
  -> BotReasoningContext
  -> PromptRenderContext
  -> ModelGenerationRequest
```

`PromptRenderContext` 只作为渲染中间态。最终传给模型的是一个 `system` 文本 prompt 和一个 JSON `user` 文本 prompt。

### WerewolfAiTurnContext

`WerewolfAiTurnContext` 是本模块内部对象，允许保留狼人杀语义。

| 字段 | 说明 |
| --- | --- |
| `turn` | `turn_id`、阶段、天数、行动类型、指令类型。 |
| `actor` | 当前行动者座位号、名字、身份、阵营。 |
| `game` | `game_name`、`game_rule_text`、人数等规则文本。 |
| `scene` | 当前天数、白天或夜晚、阶段、当前行动者。 |
| `seats` | 当前局面的座位、玩家名字和状态。 |
| `records` | 结构化游戏记录队列；最终给模型的是由它派生出的 `visibleState.timeline`。 |
| `player_information` | 与当前机器人决策有关的信息。 |
| `memory_hints` | 机器人/RAG 返回的参考内容。 |
| `task` | 当前问题、目标候选、允许动作、输入约束、超时策略。 |
| `output_mode` | `text` 或 `json`。 |
| `output_schema` | `json` 模式下必须提供。 |

### PromptRenderContext

`PromptRenderContext` 是渲染器使用的扁平材料。

| 字段 | 说明 |
| --- | --- |
| `system_prompt_text` | 按固定模板渲染出的系统文本。 |
| `current_question` | 渲染到 JSON 字段 `current_question`。 |
| `memoryHints` | 近期记忆、长期记忆和检索记忆。 |
| `current_state` | 当前第几天、白天或夜晚。 |
| `players` | 当前玩家视角可见的席位、昵称、存活和身份。 |
| `timeline` | 当前玩家视角可见的文本时间线。 |
| `response_schema` | 行动类请求随模型 API payload 下发，不写入 user prompt。 |

### Records 派生

结构化记录是唯一存储源。它可以派生给模型的 `timeline`，也可以派生给 UI 的展示对象。

广播接收阶段只写入结构化记录。行动回答阶段读取当前 AI 玩家的历史记录队列，按当前玩家视角压缩后写入 `timeline`。

```text
to_model_timeline(records, player_scope) -> Array[Dictionary]
to_ui_record_items(records, render_style) -> Array[RecordViewItem]
```

示例：

```json
[
  {
    "type": "speech",
    "eventKind": "actor_speech",
    "actor": "6号位 石头",
    "description": "我建议先刀4号。"
  },
  {
    "type": "phase",
    "eventKind": "system_instruction",
    "description": "狼人请选择袭击目标。"
  }
]
```

## 返回模式

返回模式由 `action_type` 决定。

| 行动类型 | `output_mode` | 模型返回 | 解析后 |
| --- | --- | --- | --- |
| `speak` | `text` | 纯文本发言。 | `WerewolfPlayerActionResult.speech_text`。 |
| `wolf_chat` | `text` | 纯文本狼队交流。 | 私有 `speech_text`。 |
| `last_words` | `text` | 纯文本遗言。 | `speech_text`。 |
| `post_game_summary` | `text` | 纯文本赛后总结。 | `speech_text`。 |
| `wolf_kill` | `json` | JSON 目标选择。 | `target_seat_number`。 |
| `guard_protect` | `json` | JSON 目标选择。 | `target_seat_number`。 |
| `seer_check` | `json` | JSON 目标选择。 | `target_seat_number`。 |
| `witch_act` | `json` | JSON 救、毒或跳过。 | 女巫行动结果。 |
| `sheriff_vote` | `json` | JSON 投票目标。 | 警长投票结果。 |
| `sheriff_speech_order` | `json` | JSON 发言起点和方向。 | 警长发言顺序结果。 |
| `sheriff_badge_action` | `json` | JSON 飞警徽或撕警徽。 | 警徽处理结果。 |
| `vote` | `json` | JSON 投票目标。 | 放逐投票结果。 |
| `hunter_shoot` | `json` | JSON 开枪目标或跳过。 | 猎人行动结果。 |
| `mvp_vote` | `json` | JSON MVP 目标。 | MVP 投票结果。 |

## JSON 返回基础结构

行动类模型返回必须是 JSON 对象。模型输出字段只允许 `action`、`targetSeatNumber`：

```json
{
  "action": "vote",
  "targetSeatNumber": 3
}
```

字段约定：

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `action` | 是 | 必须来自当前上下文允许的 action，或是当前允许的跳过动作；警长发言顺序时该字段表示顺时针或逆时针，警徽处理时表示飞警徽或撕警徽。 |
| `targetSeatNumber` | 按行动 | 目标座位号，必须是 number，且必须来自本次合法目标集合。 |

无目标 action 使用 `targetSeatNumber = -1`。女巫救人返回今晚倒牌座位，女巫毒人返回毒杀座位。警长发言顺序需要返回 `targetSeatNumber`，表示白天第一位发言玩家。飞警徽需要返回新警长座位；撕警徽返回 `targetSeatNumber = -1`。`reason`、`debugReason`、玩家内部 ID、`target_index`、`target_id` 和其它未知字段都会被解析器拒绝。

解析成功后的模块内部归一化结果可以携带 `target_seat_number` 和 `target_index`，但这两个字段不是模型 JSON 输出字段。

各行动类型的细化字段、枚举和示例见 [行动输出 Schema](action-output-schemas.md)。

## 最终上报格式

无论模型返回文本还是 JSON，最终都必须归一化成：

```text
WerewolfPlayerActionResult
```

发言类结果示例：

```json
{
  "turn_id": "turn_001",
  "actor_seat_number": 3,
  "action_type": "speak",
  "speech_text": "我这轮先听5号的发言，暂时不急着归票。",
  "source": "ai_model",
  "metadata": {
    "output_mode": "text"
  }
}
```

行动类结果示例：

```json
{
  "turn_id": "turn_002",
  "actor_seat_number": 3,
  "action_type": "vote",
  "target_seat_number": 5,
  "source": "ai_model",
  "metadata": {
    "output_mode": "json",
    "parse_status": "ok"
  }
}
```

## LangChain 决策

当前阶段不把 LangChain 放进模块契约。原因：

- 需要先固定 Godot 侧数据结构、输出 schema 和错误处理策略。
- 当前需求主要是一次行动输入、一次模型输出、一次结构化解析，不需要复杂 agent 编排。
- LangChain 的结构化输出能力可以在模型调用层使用，但不能让业务模块依赖它的对象结构。
- 如果后续需要多模型路由、工具调用编排、复杂追踪或统一 structured output 包装，可以在模型管理模块内部引入适配器。

因此本阶段实现建议：

1. 自己定义 `WerewolfAiTurnContext`、`PromptRenderContext` 和 JSON schema。
2. 模型管理模块只接收 `ModelGenerationRequest`。
3. 输出解析器自己校验文本或 JSON。
4. 后续如引入 LangChain，只放到模型管理模块或机器人上下文处理模块内部。
