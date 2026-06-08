# 强制 JSON 多协议兼容策略

更新时间：2026-06-08

本文说明当前模型调用中“业务强制 JSON 输出”如何跨 OpenAI 兼容接口、Anthropic、Gemini 和 Ollama 工作。这里的强制 JSON 指业务层要求模型返回可解析 JSON object，并通过 `response_schema` 限制字段、类型和枚举。

## 当前代码定位

核心实现集中在以下文件：

| 位置 | 责任 |
| --- | --- |
| `scripts/core/model/model_chat_client.gd` | 统一模型调用入口，组装各 provider HTTP payload，解析同步/流式响应。 |
| `scripts/core/model/model_adapter_registry.gd` | 结构兼容 `formt_adapter/output_adapter` 和思考兼容 `reason_adapter` 的枚举、候选、默认值和保存校验。 |
| `scripts/pages/base/page_model_ui_base.gd` | 页面通用模型请求组装：合并 profile、messages、request options 后调用 `complete_request()`。 |
| `scripts/room/xiangqi/xiangqi_room_page.gd` | 象棋房间本地模型请求组装，逻辑与页面通用模型请求保持一致。 |
| `scripts/player/werewolf/ai/ai_werewolf_response_schema_builder.gd` | 狼人杀行动类 JSON schema 生成；纯发言类返回文本模式。 |
| `scripts/player/xiangqi/ai/ai_xiangqi_response_schema_builder.gd` | 象棋走法 JSON schema 生成；聊天类返回文本模式。 |
| `scripts/pages/config/model_config_page.gd` | 模型配置测试，枚举结构兼容候选并把测试通过值写回配置。 |

一次 JSON 模型调用的主路径：

```text
业务运行时生成 messages + response_schema
  -> request_options = { output_type: "json", response_schema: ... }
  -> _model_completion_request() 合并 ModelProfile.formt_adapter 为 output_adapter
  -> ModelChatClient.complete_request()
  -> _payload() 先按 provider 生成基础 payload
  -> _apply_openai_compat_payload_adjustments() 处理 OpenAI 兼容端点的模型族差异
  -> provider 返回响应
  -> _parse_content() / tool arguments 提取正文
  -> 调用方按业务 schema 再做语义校验
```

## 统一调用契约

业务层只表达“我要文本还是 JSON”，不要在业务 prompt 里手写 provider 专用协议字段。

JSON 调用必须满足：

- `output_type = "json"`。
- `response_schema` 必填；缺失时 `ModelChatClient.complete_request()` 直接失败，错误为 `JSON 输出必须提供 response_schema`。
- `response_schema` 结构为 `{ name, strict, schema }`。`schema` 是实际 JSON Schema body。
- 行动类 schema 应尽量使用 `type: "object"`、`additionalProperties: false`、`required`、字段 `enum` 来压缩模型自由度。
- 纯文本调用应显式或自动使用 `output_adapter = "none"`，避免注入任何结构化输出协议。

当前业务层约定：

- 狼人杀发言、狼队夜聊、遗言、赛后总结是文本模式。
- 狼人杀投票、夜间技能、警长相关、猎人开枪等行动是 JSON 模式。
- 象棋聊天是文本模式。
- 象棋走法选择是 JSON 模式，`move_id` 必须来自 `legal_moves` 生成的枚举。

## 适配字段

`formt_adapter` 是历史字段名，语义是结构化输出协议适配。运行时请求里会归一化为 `output_adapter`。

| 字段 | 作用 |
| --- | --- |
| `formt_adapter` | 保存到 ModelProfile 的结构兼容值。 |
| `output_adapter` | 单次请求实际使用的结构兼容值。优先级高于 `formt_adapter`。 |
| `auto` | 只用于测试枚举和默认推断；保存前应替换为测试通过的具体值。 |
| `none` | 仅文本调用内部使用；不能作为模型配置保存值。 |

保存规则由 `ModelAdapterRegistry.formt_adapter_can_save()` 控制：可保存值不包含 `auto` 和 `none`。配置页会先运行结构化输出测试，按 provider/model 枚举候选，成功后把检测出的具体适配值应用到配置。

## 协议兼容矩阵

| 适配值 | 目标协议 | Payload 注入方式 | 输出提取 |
| --- | --- | --- | --- |
| `openai_json_schema` | OpenAI 兼容 `json_schema` | `response_format.type = "json_schema"`，携带 `json_schema.name/strict/schema`。 | `choices[0].message.content`。 |
| `openai_json_object` | OpenAI 兼容 `json_object` | `response_format.type = "json_object"`，并把 JSON Schema 作为系统指令补入 prompt。DeepSeek/Kimi 有独立指令标签。 | `choices[0].message.content`。 |
| `openai_tool_forced` | OpenAI 兼容强制工具调用 | `tools[0].function.parameters = schema`，`tool_choice` 指定工具，`parallel_tool_calls = false`。 | `tool_calls[].function.arguments`，兼容旧 `function_call.arguments`。 |
| `openai_tool_optional` | OpenAI 兼容工具承载 | 只注入 `tools`，不设置 `tool_choice`，并补系统指令要求只调用指定工具。MiniMax 走专用提示标签。 | 优先提取工具 arguments。 |
| `openai_mimo_tool` | 小米 Mimo 类 OpenAI 兼容 | 强制工具调用；思考兼容为 `mimo_chat_template` 或 `auto` 时额外注入 `chat_template_kwargs.enable_thinking`。 | 优先提取工具 arguments。 |
| `anthropic_tool` | Anthropic Messages tools | `tools[0].input_schema = schema`，`tool_choice = { type: "tool", name }`。 | 从 Anthropic content 中解析工具结果或文本。 |
| `gemini_json_schema` | Gemini 原生 JSON schema | `generationConfig.responseMimeType = "application/json"`，`responseJsonSchema = schema`；对象 schema 自动补 `propertyOrdering`。 | `candidates[0].content.parts[].text`。 |
| `ollama_format_schema` | Ollama chat `format` | `format = schema`。 | `message.content`。 |

### OpenAI 兼容端点默认选择

当 `output_adapter = "auto"` 时，OpenAI 兼容端点按模型名推断默认结构兼容：

| 模型名特征 | 默认适配 |
| --- | --- |
| 包含 `mimo` | `openai_mimo_tool` |
| 包含 `minimax` | `openai_tool_optional` |
| 包含 `glm` | `openai_tool_forced` |
| 包含 `deepseek` 或 `kimi` / `moonshot` | `openai_json_object` |
| 其它 OpenAI 兼容模型 | `openai_json_schema` |

配置页测试不会只依赖默认值。`formt_adapter = auto` 时会按候选列表逐个尝试，测试成功后保存具体适配值；显式选择某个可保存适配时只测试该适配。

## Schema 下沉策略

模型管理模块只做协议转换，不理解业务字段含义：

- `response_schema.name` 用作 OpenAI/Anthropic 工具名来源；非法字符会替换成 `_`，最长 64 字符。
- `response_schema.strict` 会传给 OpenAI `json_schema` 和强制工具模式。
- `_response_schema_body()` 只把 `response_schema.schema` 下沉到 provider payload。
- Gemini 要求属性顺序时，`_gemini_response_schema_body()` 会按 `required` 后接其它属性自动生成 `propertyOrdering`。

因此业务 schema 的正确性必须在 schema builder 和 parser 两端保证。例如狼人杀会限制 `targetSeatNumber` 枚举，象棋会限制 `move_id` 枚举；模型返回后，业务 parser 仍要校验目标是否合法，不能只相信 provider 的结构化输出能力。

## JSON Object 模式兜底

部分 OpenAI 兼容端点只支持 `response_format = { "type": "json_object" }`，不支持完整 schema。当前策略是“双层约束”：

1. 协议层开启 JSON object mode。
2. Prompt 层追加带 schema 的系统指令，要求只返回 JSON object、不要 Markdown、不要解释、不要代码块。

这类适配不能像 `json_schema` 或强制工具调用那样依赖服务端严格校验，所以业务 parser 必须继续校验字段、类型和枚举。

## 响应解析与容错

同步响应解析分两层：

1. HTTP 响应体必须先解析为 provider 的 JSON 响应对象。
2. 模型正文再按 provider 提取：
   - OpenAI 兼容：优先取工具 arguments，再取 `message.content`。
   - Ollama：取 `message.content`。
   - Anthropic/Gemini：走各自 content 结构解析。

当 `output_type = "json"` 时，`_normalize_json_output_content()` 只做很窄的兼容：如果正文是完整的 Markdown JSON 代码块，会抽出其中 JSON object。它不会从任意解释性文本里猜 JSON，避免把错误响应误判为业务行动。

## 流式限制

`transport_mode = "stream"` 支持跨 provider 的文本/思考事件解析，但强制 JSON 行动优先使用同步请求。原因是行动类输出需要完整 JSON object 才能进入业务 parser；流式片段只适合 UI 展示和连接/思考能力测试。新增行动类调用时，除非已经设计完整的流式 JSON 聚合与失败处理，否则保持 `transport_mode = "sync"`。

## 配置检测策略

配置页结构化测试使用固定 schema：

```json
{
  "name": "model_action_schema_test_v1",
  "strict": true,
  "schema": {
    "type": "object",
    "additionalProperties": false,
    "properties": {
      "action": { "type": "string", "enum": ["schema_check"] },
      "targetSeatNumber": { "type": "integer", "enum": [1] }
    },
    "required": ["action", "targetSeatNumber"]
  }
}
```

测试流程：

1. 按 provider/model 获取结构兼容候选。
2. 每个候选发起一次 `output_type=json` 请求。
3. 响应必须解析出 `action = "schema_check"` 且 `targetSeatNumber = 1`。
4. 成功后记录检测结果并允许保存配置。
5. 保存时 `formt_adapter` 必须是测试通过的具体值。

## 新增协议或模型族的维护清单

新增强制 JSON 兼容方式时，需要同时维护：

- `ModelAdapterRegistry`：新增常量、保存白名单、UI 标签、provider 候选、默认推断。
- `ModelChatClient`：新增 payload 注入、必要的 prompt 补强、响应提取或工具 arguments 解析。
- `model_config_page.gd`：确保配置页能枚举、测试并保存新适配。
- 业务 schema builder：确认 schema 使用当前 provider 可支持的 JSON Schema 子集。
- 测试：补 `test/checks/model_chat_client_check.gd` payload 断言和配置页候选断言；涉及业务行动时补对应 runtime/parser 测试。
- 文档：同步更新本文和 `docs/modules/model-management/README.md` 的兼容枚举。

维护原则：业务层只传统一契约，provider 差异只留在模型管理模块；如果某端点只能“尽量 JSON”，必须把风险留在 adapter 名称、配置测试和业务 parser 校验里显式暴露。
