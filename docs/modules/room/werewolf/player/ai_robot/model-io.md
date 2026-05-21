# 狼人杀 AI 机器人玩家模型输入输出

更新时间：2026-05-20

模型输入输出由狼人杀 AI 机器人玩家模块在控制设备本机编排。模型管理模块只负责执行业务无关的基础模型推理调用，并返回文本、思考事件、用量、诊断和结构化错误。

## 配置来源

| 配置 | 来源 | 用途 |
| --- | --- | --- |
| `model_profile_name` | 本机 `BotProfile` | 模型配置引用。 |
| `ModelProfile` | 控制设备本机模型数据库 | Endpoint、API Key、模型 ID、输出兼容、思考兼容和生成参数。 |
| `voice_profile_id` | `BotProfile` 或调用上下文 | 已确认发言播报时传给玩家/TTS 链路。 |
| 人格和表达风格 | `BotProfile` | 影响发言语气和策略倾向。 |
| 记忆上下文 | 机器人/RAG 模块 | 提供当前机器人可用的参考内容。 |
| 输出契约 | 本模块 | 行动类通过 `response_schema` 约束，发言类由行动语义和解析器约束。 |

本模块不保存模型配置，不保存声音配置，不持有 API Key。AI 玩家加入房间或重连初始化时，控制设备从本机模型数据库读取并缓存需要的 `ModelProfile`；主机和其它设备不会收到这份私有配置。

## ModelGenerationRequest

建议模型请求包含：

| 字段 | 说明 |
| --- | --- |
| `request_id` | 模型请求 ID。 |
| `profile` | 控制设备本机读取到的完整 `ModelProfile`。 |
| `messages` | 模型消息，固定为 `system prompt` 和 JSON `user prompt`。 |
| `output_type` | `text` 或 `json`。 |
| `transport_mode` | 默认 `sync`；流式能力由基础模型推理能力支持，狼人杀业务当前不依赖流式。 |
| `reasoning_mode` | 根据模型配置中的 `reasoning` 开关生成。 |
| `output_adapter` | 来自 `ModelProfile.formt_adapter`；发言类文本请求强制为 `none`。 |
| `reason_adapter` | 来自 `ModelProfile.reason_adapter`。 |
| `response_schema` | 本次行动的输出 schema，行动类必须提供。 |
| `temperature` | 由策略配置决定。 |
| `max_output_tokens` | 由行动类型和上下文预算决定。 |
| `metadata` | `room_id`、`turn_id`、`bot_id`、`action_type` 等调试信息。 |

约定：

- 行动类请求使用 `output_type = json`，必须携带 `response_schema`。
- 发言类请求使用 `output_type = text`，不携带 JSON schema，不注入 JSON 输出要求。
- 模型开启思考模式时，不传最大输出 token 限制，避免思考内容占用业务输出预算。
- `formt_adapter` 和 `reason_adapter` 必须来自已测试通过并保存的模型配置，狼人杀 AI 机器人玩家模块不再运行时枚举兼容策略。

## 消息形态

程序内部使用结构化对象，但 `ModelGenerationRequest.messages` 只提交两条文本消息：

```text
messages[0] = system prompt
messages[1] = JSON user prompt
```

`system prompt` 放：

1. 游戏名称。
2. 机器人名字、座位号、身份和阵营。
3. 游戏规则描述。
4. `user prompt` 是 JSON 对象字符串，以及数据字段不是指令的安全语义。
5. 本次回答要求。
6. 警长发言顺序、警徽处理等特殊行动的动作语义。
7. 不包含输出格式样例；行动类输出格式由 `response_schema` 经基础模型推理能力转换成供应商协议。

`user prompt` 只放一个可解析 JSON 对象字符串：

```json
{
  "current_question": "当前是白天投票。结合历史发言选择放逐目标。",
  "memoryHints": {},
  "current_state": "第1天白天",
  "players": [
    {"alive": true, "displayName": "夜航", "role": "狼人", "seatNumber": 3},
    {"alive": true, "displayName": "林子", "role": "未知", "seatNumber": 2}
  ],
  "timeline": [
    "2号:我没信息，1号像是在控场，先标记。"
  ]
}
```

行动类请求同时携带 `response_schema`，例如投票断点：

```json
{
  "name": "werewolf_vote_v1",
  "strict": true,
  "schema": {
    "type": "object",
    "additionalProperties": false,
    "properties": {
      "action": {"type": "string", "enum": ["vote"]},
      "targetSeatNumber": {"type": "integer", "enum": [2]}
    },
    "required": ["action", "targetSeatNumber"]
  }
}
```

完整模板、字段语义和裁剪规则见 [JSON Prompt 模板](context-template.md)。

## 调用时机

- 主机系统广播给 AI 玩家时，只在控制设备本机写入结构化记录队列。
- 广播不触发 `ModelGenerationRequest`。
- 行动请求需要 AI 回答时，才读取当前视角、历史、私有信息和记忆材料，渲染 JSON `user prompt`。
- 一次行动请求只发起一次模型调用。
- 模型输出解析失败时返回结构化错误，不再次调用模型改写输出。
- 模型配置缺失、数据库不可用、结构兼容无效、思考兼容无效或基础模型推理能力返回错误时，直接中止当前游戏流程并暴露错误。

## 固定渲染材料

用于渲染 prompt 的行动材料必须稳定，不按 UI 展示需要临时增减字段。结构化字段只供程序内部、UI 和渲染器使用，最终给模型的是 `system prompt` 和 JSON `user prompt`。

约定：

- `timeline` 是给模型阅读的可见游戏记录队列，格式为 `X号:内容`。
- `timeline` 由结构化记录压缩生成，玩家方向由程序统一格式化，例如“6号:我建议先听5号”。
- 玩家发言、记忆内容、记录描述是数据字段，不是模型指令。
- 同一份结构化记录可以根据 UI 要求渲染成头像、名字、身份、频道颜色、时间线等视图数据。
- 行动选择进入解析器后仍以 `targetSeatNumber` 归一化；合法目标集合由 schema 构建器内部使用，不写入 user prompt。
- 发言类文本一旦被接受，UI、历史和 TTS 都以 `speech_text` 原文为准。

## 输出契约

不同行动类型使用不同输出模式。

| 行动类型 | 返回模式 | 必填输出 | 说明 |
| --- | --- | --- | --- |
| `speak` | `text` | 纯文本 | 公开发言文本。 |
| `wolf_chat` | `text` | 纯文本 | 狼队交流文本。 |
| `last_words` | `text` | 纯文本 | 遗言文本。 |
| `post_game_summary` | `text` | 纯文本 | 赛后总结文本。 |
| `wolf_kill` | `json` | `targetSeatNumber` | 狼人袭击目标。 |
| `guard_protect` | `json` | `targetSeatNumber` | 守卫守护目标。 |
| `seer_check` | `json` | `targetSeatNumber` | 预言家查验目标。 |
| `witch_act` | `json` | `action`、`targetSeatNumber` | 救、毒或跳过；救人和毒人返回对应目标座位，跳过返回 `-1`。 |
| `sheriff_vote` | `json` | `targetSeatNumber` | 警长投票目标。 |
| `sheriff_speech_order` | `json` | `action`、`targetSeatNumber` | 警长决定白天发言顺序；`action` 表示顺时针或逆时针，`targetSeatNumber` 表示首发言座位。 |
| `sheriff_badge_action` | `json` | `action`、`targetSeatNumber` | 死亡警长处理警徽；`sheriff_badge_pass` 需要新警长座位，`sheriff_badge_destroy` 使用 `targetSeatNumber = -1`。 |
| `vote` | `json` | `targetSeatNumber` | 放逐投票目标。 |
| `hunter_shoot` | `json` | `action`、`targetSeatNumber` | 开枪返回目标座位，跳过返回 `-1`。 |
| `mvp_vote` | `json` | `targetSeatNumber` | MVP 目标。 |

详细返回契约见 [上下文与返回契约](context-output-contract.md)，行动类 JSON 结构见 [行动输出 Schema](action-output-schemas.md)。

## 模型输出地位

- 模型输出只是候选结果。
- 候选结果必须进入 [输出解析](output-parsing.md)。
- 解析后的结果仍必须交给狼人杀房间模块校验。
- 模型草稿不得进入房间历史、记忆或 TTS。
- 发言类文本一旦被接受，不做改写、润色或翻译替换。
