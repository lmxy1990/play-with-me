# 狼人杀 AI 机器人玩家输入上下文

更新时间：2026-05-20

输入上下文是 AI 机器人玩家每次行动的资料来源。程序先按当前玩家生成一份结构化数据，再由 prompt 渲染器转换成 `system prompt` 和 `user prompt` 两段文本。模型不负责判断哪些数据该出现，它只处理程序交给它的数据。

AI 机器人玩家接收主机系统广播时，只把数据写入结构化记录队列。只有行动请求需要 AI 回答时，才读取该队列并按当前玩家视角生成 JSON prompt 里的 `visibleState.timeline`。

## 上下文来源

| 来源 | 进入条件 | 说明 |
| --- | --- | --- |
| 行动请求 | 必须 | `turn_id`、阶段、行动类型、目标候选、输入约束。 |
| 游戏规则 | 必须 | 当前人数和本局规则的详细描述。 |
| 席位信息 | 必须 | 座位、玩家名字、状态。 |
| 游戏记录 | 必须 | 主持人消息、玩家发言、行动结果、阵营消息等结构化记录。 |
| 玩家信息 | 按身份 | 本人身份、阵营、队友、技能、行动结果等。 |
| 机器人档案 | 必须 | 人格、说话风格、策略风格。 |
| 机器人记忆 | 可选 | 机器人/RAG 模块返回的参考内容。 |

## 构建顺序

上下文必须按固定顺序构建，避免一边拼 prompt 一边补业务判断。

```text
收集行动请求
  -> 读取游戏规则文本
  -> 读取席位摘要
  -> 读取当前 AI 玩家历史结构化记录队列
  -> 读取当前玩家信息
  -> 生成 WerewolfAiTurnContext
  -> 调用机器人/RAG 构建 BotReasoningContext
  -> 渲染 system prompt 和 user prompt
```

`WerewolfAiTurnContext` 的字段定义见 [上下文与返回契约](context-output-contract.md)。

## BotReasoningContext 映射

`BotReasoningContext` 是提交给机器人/RAG 模块的通用机器人上下文。狼人杀专用内容可以放在结构化摘要里，但机器人/RAG 模块不依赖狼人杀房间内部对象。

建议字段：

| 字段 | 说明 |
| --- | --- |
| `context_id` | 本次上下文 ID。 |
| `bot_id` | 当前机器人 ID。 |
| `scope` | 房间和行动作用域。 |
| `task_type` | `werewolf_turn`。 |
| `actor` | 当前行动者座位号、名字、身份、阵营。 |
| `task` | 当前行动类型、目标候选、输入约束。 |
| `scene` | 当前天数、阶段和行动者。 |
| `seats` | 座位、玩家名字和状态。 |
| `records` | 结构化游戏记录队列；最终给模型的是由它派生出的 `visibleState.timeline`。 |
| `player_information` | 与当前机器人决策有关的信息。 |
| `output_contract` | 本次模型必须返回的结构。 |

## 席位摘要

席位摘要用于让模型知道本局座位和玩家名字，也用于 UI 展示。

固定结构：

```json
[
  {
    "seat_number": 1,
    "name": "阿明",
    "status": "存活"
  },
  {
    "seat_number": 2,
    "name": "小鹿",
    "status": "存活"
  }
]
```

## 结构化记录

游戏记录以结构化形式保存。AI prompt 和 UI 都从结构化记录派生。广播接收阶段只追加记录；行动回答阶段再把当前 AI 玩家的历史队列整体交给压缩器，由压缩器生成给模型的 `visibleState.timeline`。

建议结构：

```json
{
  "record_type": "speech",
  "channel": "werewolf_team",
  "day_index": 1,
  "phase": "night",
  "seat_number": 6,
  "text": "我建议先刀4号。",
  "ui_payload": {
    "avatar_id": "avatar_stone",
    "name": "石头",
    "role_label": "狼人",
    "style": "team_chat"
  }
}
```

派生方法：

```text
to_model_timeline(records, player_scope) -> Array[Dictionary]
to_ui_record_items(records, render_style) -> Array[RecordViewItem]
```

模型时间线示例：

```json
[
  {
    "type": "phase",
    "eventKind": "system_instruction",
    "description": "游戏开始。"
  },
  {
    "type": "speech",
    "eventKind": "actor_speech",
    "actor": "6号位 石头",
    "description": "我建议先刀4号。"
  }
]
```

UI 展示可以根据 `ui_payload` 渲染头像、名字、身份标签、频道样式和时间线样式。

## 游戏规则上下文

AI 机器人玩家不重新推导游戏规则。规则文本只来自狼人杀房间模块和当前地图人数锁定后的规则包输出。

规则文本建议包含：

- 当前人数。
- 身份分布。
- 白天、黑夜、投票、死亡、胜负规则。
- 当前行动允许的目标类型。
- 当前地图特殊规则，例如警长票权、警长死亡后的飞警徽/撕警徽、警长决定白天发言顺序、守卫连续限制、无女巫。

地图背景图、地图场景图、UI 布局等不进入 `game_rule_text`，它们属于房间展示和 UI 渲染。
