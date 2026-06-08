# 模型管理模块

更新时间：2026-05-19

模型管理模块是模型配置管理和基础模型推理能力模块，负责模型配置、模型列表获取、配置测试和一次模型调用。它回答“用哪个模型配置、如何按统一协议调用、调用结果是什么”。

模型推理能力像一个业务无关的 I/O 黑盒：调用方提供完整模型配置、消息、输出类型、结构兼容、思考兼容和传输模式，模块负责组装不同供应商请求并返回文本、诊断事件、用量和结构化错误。它不理解机器人记忆、具体游戏房间玩法、AI 机器人玩家策略或 TTS 播放。

跨模块对象 `ModelGenerationRequest` 和 `ModelGenerationResult` 的字段权威见 [跨模块契约](../../contracts/README.md)。强制 JSON 输出的多协议适配细节见 [强制 JSON 多协议兼容策略](forced-json-compatibility.md)。本文保留模型配置、供应商调用和模块内部流程说明。

## 模块定位

```text
配置页面
  -> 模型管理模块
       -> 保存 / 删除 / 选择 ModelProfile
       -> 拉取供应商模型列表
       -> 测试模型配置

AI 机器人玩家适配层 / 机器人上下文处理模块 / 其它调用方
  -> 模型管理模块
       -> complete_request(profile + messages + options)
       -> 返回文本、诊断事件或结构化错误
```

模型管理模块只处理模型供应商差异、配置持久化、兼容适配和一次模型调用。调用方负责决定何时调用模型、传入什么上下文、需要 `text` 还是 `json`、如何解释输出。

## 能力边界

模型管理模块负责：

- 保存、读取、删除和选择模型配置。
- 保存供应商、Endpoint、API Key、模型 ID、上下文预算、输出上限、温度、思考开关、结构兼容和思考兼容等配置。
- 拉取供应商模型列表，用于配置页批量新增。
- 测试某个模型配置是否可用，并自动检测可保存的结构兼容和思考兼容值。
- 按供应商差异组装请求和解析响应。
- 提供统一的模型推理接口，支持同步、流式、文本、JSON schema、思考输出事件和供应商诊断。
- 返回文本、思考文本、流式片段、原始响应摘要、token 用量、耗时、warning 和结构化错误。
- 提供配置校验、敏感字段脱敏和只读调试能力。

模型管理模块不负责：

- 机器人记忆检索、记忆更新或长期记忆存储。
- AI 机器人玩家策略、提示词业务模板、狼人杀行动选择。
- 房间状态修改、具体游戏房间推进或胜负判断。
- TTS 播报、玩家发言确认或历史消息写入。
- 二维码、扫码、加密、认证或设备私钥管理。
- 失败后的游戏行为生成。

## 生命周期契约

| 生命周期 | 触发方 | 建议调用 | 作用 |
| --- | --- | --- | --- |
| `config_loaded` | 应用启动 / 配置页打开 | `list_model_profiles()` | 读取可用模型配置。 |
| `profile_saved` | 模型配置页 | `save_model_profile()` | 保存单个模型配置。 |
| `profile_deleted` | 模型配置页 | `delete_model_profile()` | 删除模型配置。 |
| `profile_selected` | 模型配置页 / 玩家配置页 | `select_model_profile()` | 记录默认或当前模型配置。 |
| `catalog_requested` | 模型配置页 | `list_remote_models()` | 拉取供应商模型列表。 |
| `profile_tested` | 模型配置页 | `test_model_profile()` | 发起一次小请求验证配置。 |
| `before_model_call` | 运行时调用方 | `complete_request()` | 发起业务无关的模型输入输出调用。 |
| `model_call_completed` | 模型管理模块 | 返回 `ModelGenerationResult` | 返回文本、用量、耗时或错误。 |
| `profile_invalid` | 配置读取 | `discard_invalid_model_profile()` | 丢弃不符合当前结构的模型配置。 |

## 核心对象

### ModelProfile

`ModelProfile` 是模型配置的归一化结构。

| 字段 | 说明 |
| --- | --- |
| `schema_version` | 模型配置结构版本。 |
| `name` | 配置名，通常用于业务调用方引用。 |
| `provider` | 供应商类型，例如 `openai_api`、`ollama`、`anthropic`、`gemini`。 |
| `endpoint` | API 地址。 |
| `api_key_ref` | 指向安全存储中的 API Key。 |
| `model` | 模型 ID。 |
| `max_context` | 模型最大上下文 token。 |
| `context_window_tokens` | 运行时可用上下文预算，可由 `max_context` 派生。 |
| `max_output` | 最大输出 token。 |
| `temperature` | 默认采样温度。 |
| `reasoning` | 是否启用思考模式。 |
| `formt_adapter` | JSON/结构化输出兼容方式，必须是测试通过的可保存值。 |
| `reason_adapter` | 思考输出兼容方式，必须是测试通过的可保存值。 |
| `timeout_ms` | 请求超时时间。 |
| `enabled` | 是否启用。 |
| `created_at` | 创建时间。 |
| `updated_at` | 最近更新时间。 |
| `metadata` | 扩展字段，只保存模型配置元数据。 |

字段约定：

- `name` 是稳定引用，不应随 UI 展示名随意变化。
- `api_key_ref` 不应解析成普通日志、错误弹窗、调试报告和房间广播里的明文。
- `max_context`、`context_window_tokens` 和 `max_output` 是当前 token 预算字段；配置缺少这些字段时直接视为无效。
- `formt_adapter` 不能保存为 `auto` 或 `none`；`auto` 只用于测试时枚举候选。
- `reason_adapter` 不能保存为 `auto`；开启思考时也不能保存为 `native`，必须保存测试检测出的具体兼容方式。

### 兼容枚举

结构兼容字段使用历史字段名 `formt_adapter`，语义是“当业务要求 JSON 输出时，如何把 schema 传给当前模型 API”。

| 值 | UI 标签 | 用途 |
| --- | --- | --- |
| `auto` | 自动 | 只允许测试时使用，保存前必须替换成检测结果。 |
| `none` | 无 | 仅文本调用内部使用，不能作为模型配置保存值。 |
| `openai_json_schema` | `json_schema` | OpenAI 兼容接口的 `json_schema` response_format。 |
| `openai_json_object` | `json_object` | DeepSeek、Kimi 等 OpenAI 兼容接口的 `json_object` response_format。 |
| `openai_tool_forced` | `tool` | OpenAI 兼容工具调用强制模式。 |
| `openai_tool_optional` | `tool_v2` | OpenAI 兼容工具调用可选模式。 |
| `openai_mimo_tool` | `mimo_tool` | 小米 Mimo 类模型的工具兼容模式。 |
| `gemini_json_schema` | `gemini_schema` | Gemini 原生 schema。 |
| `anthropic_tool` | `claude_tool` | Anthropic tool schema。 |
| `ollama_format_schema` | `ollama_schema` | Ollama `format` schema。 |

思考兼容字段 `reason_adapter` 描述“如何开启或关闭当前模型的思考输出，以及如何识别思考事件”。

| 值 | UI 标签 | 用途 |
| --- | --- | --- |
| `auto` | 自动 | 只允许测试时使用，保存前必须替换成检测结果。 |
| `native` | 端点名 | 端点原生文本输出，不注入特殊思考控制。 |
| `openai_reasoning_effort` | `reasoning_effort` | OpenAI reasoning effort 兼容。 |
| `deepseek_thinking` | `deepseek_thinking` | DeepSeek 类模型思考控制。 |
| `glm_thinking` | `glm_thinking` | GLM 类模型思考控制。 |
| `ark_thinking` | `ark_thinking` | 火山 Ark / 豆包类模型思考控制。 |
| `minimax_reasoning_split` | `minimax_split` | MiniMax 思考与正文分离兼容。 |
| `mimo_chat_template` | `mimo_chat_template` | 小米 Mimo chat template 思考兼容。 |
| `kimi_thinking_control` | `kimi_thinking_control` | Kimi / Moonshot 思考控制。 |

### ModelGenerationRequest

`ModelGenerationRequest` 是一次模型调用的输入。

| 字段 | 说明 |
| --- | --- |
| `schema_version` | 请求结构版本。 |
| `request_id` | 请求 ID，用于去重和调试。 |
| `profile_name` | 模型配置名。 |
| `profile_override` | 可选，临时模型配置覆盖。 |
| `messages` | 归一化消息列表。 |
| `output_type` | `text` 或 `json`。 |
| `transport_mode` | `sync` 或 `stream`。 |
| `reasoning_mode` | `off` 或 `on`，通常由 profile 的 `reasoning` 派生。 |
| `output_adapter` | 本次调用使用的结构兼容方式；文本调用默认 `none`。 |
| `reason_adapter` | 本次调用使用的思考兼容方式。 |
| `response_schema` | `output_type = json` 时必填的 JSON Schema。 |
| `generation_options` | 温度、top_p、输出上限、停止词、供应商额外参数等生成参数。 |
| `request_context` | 调用方上下文元数据，例如来源模块和 trace ID。 |
| `metadata` | 扩展字段。 |

约定：

- `messages` 是调用方已经组装好的输入，模型管理模块不理解其业务含义。
- `generation_options` 可以覆盖 profile 中的运行时参数，但不能修改已保存配置。
- `output_type = json` 时必须提供 `response_schema`，模型管理模块按 `output_adapter` 转换成供应商协议。
- `output_type = text` 时默认使用 `output_adapter = none`，不注入 JSON 输出要求。
- 开启思考模式时不传最大输出 token 限制，避免思考内容占用业务输出预算。
- `request_context` 只用于日志、追踪和调试，不参与业务判断。

### ModelGenerationResult

`ModelGenerationResult` 是一次模型调用的输出。

| 字段 | 说明 |
| --- | --- |
| `ok` | 是否成功。 |
| `request_id` | 请求 ID。 |
| `profile_name` | 使用的模型配置名。 |
| `text` | 成功时返回的模型文本。 |
| `reasoning_text` | 可选，模型返回的思考文本或思考事件聚合。 |
| `has_reasoning_output` | 是否检测到思考输出。 |
| `has_stream_output` | 是否检测到流式输出。 |
| `raw_response_summary` | 原始响应摘要，必须脱敏。 |
| `usage` | token 用量、耗时等统计。 |
| `warnings` | 非致命问题。 |
| `error` | 失败时的结构化错误。 |

错误建议包含：

| 字段 | 说明 |
| --- | --- |
| `code` | 错误码，例如 `profile_not_found`、`auth_failed`、`timeout`、`network_error`、`invalid_response`。 |
| `message` | 可展示错误摘要。 |
| `transient` | 是否建议再次发起。 |
| `provider_status` | 可选，供应商 HTTP 状态码或错误类型。 |

### ModelCatalogResult

`ModelCatalogResult` 是供应商模型列表结果。

| 字段 | 说明 |
| --- | --- |
| `provider` | 供应商类型。 |
| `endpoint` | API 地址。 |
| `models` | 模型 ID 列表。 |
| `warnings` | 非致命问题。 |
| `error` | 失败时的结构化错误。 |

## 对外接口

以下接口是设计契约，不要求当前代码函数名完全一致。

```text
list_model_profiles(request) -> ModelProfileListResult
get_model_profile(request) -> ModelProfileResult
save_model_profile(request) -> ModelProfileResult
delete_model_profile(request) -> ModelProfileMutationResult
select_model_profile(request) -> ModelProfileSelectionResult
list_remote_models(request) -> ModelCatalogResult
test_model_profile(request) -> ModelGenerationResult
complete_request(request) -> ModelGenerationResult
complete_stream(request) -> ModelGenerationResult / events
get_model_debug_state(request) -> ModelDebugResult
```

### save_model_profile

```text
save_model_profile(request) -> ModelProfileResult
```

`request`：

| 字段 | 说明 |
| --- | --- |
| `profile` | 要保存的 `ModelProfile`。 |
| `allow_overwrite` | 是否允许覆盖同名配置。 |
| `validate_only` | 是否只校验不保存。 |

校验规则：

- `name`、`provider`、`endpoint`、`model` 必填。
- `max_context`、`context_window_tokens`、`max_output` 必须为正数。
- `context_window_tokens` 不应大于 `max_context`。
- API Key 是否必填由 provider 决定。
- `formt_adapter` 必须是测试通过的可保存结构兼容值，不能是 `auto` 或 `none`。
- `reason_adapter` 必须是测试通过的可保存思考兼容值，不能是 `auto`。

### list_remote_models

```text
list_remote_models(request) -> ModelCatalogResult
```

`request`：

| 字段 | 说明 |
| --- | --- |
| `provider` | 供应商类型。 |
| `endpoint` | API 地址。 |
| `api_key_ref` | 鉴权信息引用。 |
| `timeout_ms` | 超时时间。 |

约定：

- 只返回模型 ID 和必要元数据。
- 不自动保存模型配置。
- 批量新增由配置页根据返回结果再调用 `save_model_profile()`。

### test_model_profile

```text
test_model_profile(request) -> ModelGenerationResult
```

约定：

- 测试分为结构化输出测试、文本输出测试和思考检测。
- 结构化输出测试使用短 JSON schema；如果 `formt_adapter = auto`，按 provider 和 model 枚举候选，直到找到可用结构兼容值。
- 文本输出测试使用 `output_type = text` 和 `output_adapter = none`，确认模型可以返回普通文本。
- 思考检测根据页面思考开关进行：开启时必须检测到符合兼容策略的思考事件；关闭时不能出现思考输出。如果 `reason_adapter = auto`，按 provider 和 model 枚举候选，直到检测结果符合期望。
- 流式输出暂时只作为基础接口能力保留，配置页测试不要求业务启用流式。
- 测试通过后，UI 自动选中检测出的 `formt_adapter` 和 `reason_adapter`，保存按钮才可用。
- 测试失败只返回结构化错误，不修改 profile，不把测试输出写入机器人记忆、房间历史或玩家发言。

### complete_request

```text
complete_request(request) -> ModelGenerationResult
```

流程：

```text
调用方
  -> 组装 messages、output_type、transport_mode、reasoning_mode、response_schema 和 generation_options
  -> complete_request()
  -> 模型管理模块读取完整 profile
  -> 按 provider、output_adapter、reason_adapter 构造 HTTP 请求
  -> 解析模型响应、流式片段和思考事件
  -> 返回文本 / 思考文本 / 用量 / 错误
```

约定：

- 模型管理模块不重写业务提示词。
- 模型管理模块不判断输出是否是合法游戏行动。
- 模型管理模块不把输出自动提交给玩家、房间、规则、TTS 或机器人记忆。
- 调用失败时只返回错误，不在模块内部生成业务结果。
- `text`、`json`、同步、流式和思考模式都通过同一个请求协议表达；模块内部按协议拆成不同供应商 payload 和不同响应解析路径。
- 如果模型调用失败，需要在错误日志里打印脱敏后的请求参数、prompt、schema、payload 结构、原始输出和解析错误；普通日志不得打印 API Key 明文。

## 持久化策略

Android 真机优先写 SQLite，桌面和编辑器可以写 JSON。

当前归属：

```text
Android: SQLite model_configs
Editor/Desktop: user://play_with_me_state.json
```

持久化约定：

- 保存前使用归一化 `ModelProfile`。
- 只读取当前结构；结构不匹配的配置直接丢弃。
- 调试导出和错误日志必须脱敏 API Key。
- 如果未来引入系统安全存储，应优先保存 `api_key_ref`，减少明文落盘。

## 版本与无效数据

模型配置是运行时关键基础数据，只接受当前结构。

处理规则：

- 缺少必填字段、字段名不匹配或 `schema_version` 不匹配时，直接丢弃该配置。
- 缺少 `context_window_tokens` 时，可在新建配置时由 `max_context * 0.7` 派生。
- 缺少 `timeout_ms` 时，新建配置使用模块默认值。
- 默认选择状态由 `select_model_profile()` 管理，不写入单个 profile 的业务语义。
- API Key 只通过 `api_key_ref` 引用；调试和错误输出不得打印明文。

## 失败处理

| 场景 | 策略 |
| --- | --- |
| profile 不存在 | 返回 `profile_not_found`。 |
| provider 不支持 | 返回 `unsupported_provider`。 |
| Endpoint 无效 | 返回 validation error。 |
| 鉴权失败 | 返回 `auth_failed`，不打印 API Key。 |
| 网络不可达 | 返回 `network_error`，标记是否可再次发起。 |
| 请求超时 | 返回 `timeout`，调用方决定是否再次发起。 |
| 响应无法解析 | 返回 `invalid_response`，附脱敏摘要。 |
| 上下文超过预算 | 返回 `context_too_large` 或截断 warning；截断策略应由调用方明确选择。 |

## 只读调试

```text
get_model_debug_state(request) -> ModelDebugResult
```

只读调试信息建议包含：

- 当前可用 profile 列表。
- 每个 profile 的 provider、endpoint、model、上下文预算和启用状态。
- API Key 是否存在，不返回明文。
- 最近一次模型调用的 request ID、provider、model、transport_mode、output_type、output_adapter、reason_adapter、reasoning_mode、耗时、token 用量和错误码。
- 最近一次模型列表拉取结果。

约定：

- 调试接口不得发起模型调用。
- 调试接口不得修改 profile。
- API Key、完整请求正文和完整响应正文默认不返回。

## 与其它模块的关系

| 模块 | 模型管理模块如何交互 |
| --- | --- |
| 机器人/RAG 模块 | 机器人档案保存模型配置引用；机器人上下文处理模块提供推理上下文；模型模块只按调用方传入的配置执行输入输出，不读取或更新记忆。 |
| 玩家模块 | 玩家资料只保存机器人引用；模型模块不创建玩家。 |
| 狼人杀玩家模块 | 控制 AI 玩家的设备从机器人档案取得模型配置引用，再从本机模型数据库读取完整 `ModelProfile`，负责组装业务上下文和解释输出。 |
| TTS 语音模块 | 无直接依赖；模型输出必须先被上层确认，才能进入 TTS。 |
| 房间模块 | 无直接依赖；模型调用不修改房间状态。 |
| 偏好设置模块 | 不交叉；用户昵称、头像、播放声音配置引用和设备私钥不属于模型配置。 |
| 基础能力 | 不交叉；二维码、扫码、加密和认证不属于模型配置。 |

## 文档和代码归属

```text
scenes/model_config.tscn
scripts/pages/config/model_config_page.gd
scripts/pages/config/config_page_base.gd
scripts/pages/base/page_model_ui_base.gd
scripts/core/model/
  model_catalog_client.gd
  model_chat_client.gd
  model_profile_selector.gd
scripts/core/config/config_repository.gd
scripts/android/android_model_config_store.gd
android_plugins/play_with_me_android/.../MemoryDatabase.kt
```

## 维护规则

- 模型模块的核心接口保持为 `profile + messages + output_type + adapters + options -> text/events / structured error`。
- Provider、结构兼容、思考兼容和流式解析差异只放在模型请求、模型列表客户端和 adapter registry 里。
- UI、Godot store、Android SQLite、profile selector、测试和文档必须同步。
- API Key 必须脱敏，不进入普通日志、调试导出、房间快照或机器人记忆。
- 模型模块不写机器人行为规则、记忆检索规则、狼人杀房间玩法或 TTS 播放逻辑。
- 运行时调用失败必须返回可处理的错误，不在模型模块内部做游戏行为生成。
