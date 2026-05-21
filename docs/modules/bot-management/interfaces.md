# 机器人/RAG 接口契约

更新时间：2026-05-16

本文面向模块开发，描述机器人/RAG 模块对外暴露的函数接口、预期参数和返回结构。这里的接口是设计期契约，部分函数和字段属于预设方案，后续整体模块编织、代码重构和联调时可以继续调整。

机器人/RAG 模块是通用机器人能力，不绑定狼人杀、房间、规则或任何具体业务。外部业务模块只把“当前机器人可见的信息”和“已经确认可以写入记忆的更新材料”交给它；机器人/RAG 模块像黑盒一样管理机器人档案、上下文和多层记忆。

## 接口分层

```text
外部业务适配层
  -> 机器人模块门面 BotCapabilityFacade
       -> 记忆模块 AgentMemoryService
       -> 机器人上下文处理模块 BotContextBuilder
```

外部模块只应该调用机器人模块门面。记忆模块和上下文处理模块是内部服务，本文也记录它们的函数形态，主要用于模块内部开发和后续拆代码时对齐。

## 通用约定

- 函数参数优先使用结构化 `Dictionary`，避免长参数列表。
- 返回值统一包含 `ok`、`data`、`warnings`、`error`。
- `ok = false` 时，调用方只能读取 `error` 和 `warnings`，不能继续使用 `data`。
- `warnings` 表示可切换继续的风险，例如记忆缺失、上下文被裁剪、无效数据被丢弃。
- 机器人/RAG 模块不调用模型，不生成最终行动，不执行业务规则。
- 外部业务确认之前的模型草稿、非法行动、UI 临时输入不能提交给记忆。
- 提交给记忆系统的内容不是“摘要”，而是结构化 `memory_update`。它描述哪些事实、判断和结果可以进入记忆系统；记忆模块再决定更新哪一层记忆。
- 完整记忆展示使用独立机器人记忆页；页面接口只读或触发受控维护，不提供直接编辑底层记忆的能力。

通用返回结构：

```gdscript
{
    "ok": true,
    "data": {},
    "warnings": [],
    "error": ""
}
```

通用错误字段建议：

| 字段 | 说明 |
| --- | --- |
| `code` | 稳定错误码，例如 `bot_not_found`、`invalid_visible_context`。 |
| `message` | 可记录或展示的短错误信息。 |
| `details` | 调试信息，可选。 |

## 生命周期契约

机器人/RAG 作为基础模块，需要明确外部在什么时机调用它。生命周期只表达机器人能力的调用时机，不表达具体业务流程。

| 生命周期 | 触发方 | 建议调用 | 作用 |
| --- | --- | --- | --- |
| `bot_created` | 外部业务模块 / 角色模块 | `create_or_get_bot_profile()` -> `initialize_bot()` | 创建机器人档案，并基于机器人 ID 初始化自身记忆。 |
| `session_started` | 外部业务适配层 | `initialize_bot()` | 为当前会话或运行实例创建工作记忆空间。 |
| `before_task` | 具体业务 AI 机器人玩家适配层 | `build_bot_context()` | 获取当前任务所需的 `BotReasoningContext`。 |
| `after_confirmed_result` | 外部业务适配层 | `commit_bot_result()` | 把已确认输出、对话、事件和结果转换成 `memory_update` 并提交。 |
| `session_end` | 外部业务适配层 | `commit_bot_result()` -> `maintain_bot()` | 提交会话结束记忆更新，触发反思、合并和工作记忆清理。 |
| `maintenance` | 应用启动、空闲任务或人工入口 | `maintain_bot()` | 执行压缩、衰减、剪枝、索引重建和健康检查。 |

调用约定：

- `before_task` 可以在记忆读取失败时切换为无记忆上下文，但必须返回 warning。
- `after_confirmed_result` 不应撤销外部业务结果；如果记忆写入失败，应记录错误并允许后续再次发起。
- `session_end` 可以分两步执行：先提交 `session_end_memory_update`，再进行较重的维护任务。
- `maintenance` 不应阻塞业务主流程，除非正在做必须完成的当前结构校验或索引重建。

## 可见性和防污染

可见性是机器人/RAG 的硬边界。外部业务适配层负责生成已脱敏的 `BotVisibleContext` 和 `memory_update`，机器人模块负责做防线式校验。

| 可见性 | 说明 | 记忆处理 |
| --- | --- | --- |
| `public` | 当前机器人和其它参与者都可以知道的信息。 | 可进入事件记忆、关系记忆或语义候选。 |
| `self_private` | 只有当前机器人可见的信息。 | 只能写入当前机器人私有记忆。 |
| `observer_safe` | 可给旁观者或调试视图看的脱敏信息。 | 可以用于只读调试，不代表可写入长期记忆。 |
| `post_session_reveal` | 会话结束后才公开的信息。 | 必须保留来源标记，避免污染当时的工作记忆。 |

防污染规则：

- 当前机器人不可见的信息不得进入 `BotVisibleContext`。
- 当前机器人不可见的信息不得进入 `memory_update`。
- 模型草稿、未确认输出、被拒绝输出、UI 临时输入不得写入记忆。
- 推理过程不能直接写入记忆；需要沉淀时，必须转成脱敏后的 `memory_update` 候选。
- 记忆模块可以拒绝、降权或只写入工作记忆，不承诺照单全收。

## 版本与无效数据

所有跨模块请求建议携带版本字段；版本不匹配时直接拒绝或丢弃，不做结构转换。

通用版本字段：

| 字段 | 说明 |
| --- | --- |
| `schema_version` | 当前请求或数据结构版本。 |
| `adapter_version` | 业务适配层版本。 |
| `memory_schema_version` | 记忆存储 schema 版本。 |
| `context_schema_version` | 上下文结构版本。 |

推荐放置位置：

```gdscript
{
    "schema_version": 1,
    "adapter_version": 1,
    "memory_schema_version": 1,
    "context_schema_version": 1,
    "bot_id": "",
    "scope": {}
}
```

处理约定：

- 新增字段必须有默认值。
- 删除字段时同步更新生产者、消费者、SQLite、JSON、向量索引和文档。
- Android SQLite、桌面 JSON 和向量索引只读取当前 schema 版本。
- schema 不匹配的数据直接拒绝读取或丢弃，并返回 warning 或 error。

## 失败处理

机器人/RAG 是基础模块，失败策略必须稳定。

| 场景 | 默认策略 | 调用方影响 |
| --- | --- | --- |
| 机器人档案不存在 | 返回 `bot_not_found`。 | 外部可尝试创建或重新绑定。 |
| 记忆读取失败 | 返回空记忆上下文和 warning。 | 具体业务 AI 机器人玩家适配层可以继续无记忆推理。 |
| 上下文过大 | 按优先级裁剪并返回 `budget_report`。 | 具体业务 AI 机器人玩家适配层继续使用裁剪后的上下文。 |
| 可见性校验失败 | 高风险时 `ok = false`，低风险时 warning。 | 外部适配层需要修正脱敏逻辑。 |
| 记忆写入失败 | 返回 `ok = false` 或 warning，不撤销外部业务结果。 | 外部记录失败，可稍后再次发起。 |
| 维护失败 | 返回维护报告和 warning。 | 下次启动、空闲或手动维护时再次发起。 |
| schema 不匹配 | 阻断相关写入，丢弃不符合当前结构的数据。 | 需要提示开发并重建当前结构数据。 |

## 通用运行范围

`BotRuntimeScope` 用来描述一次机器人记忆和上下文操作发生在哪个业务范围内。机器人模块只把这些字段当作命名空间、隔离范围和检索条件，不理解具体业务含义。

```gdscript
{
    "domain_id": "",
    "session_id": "",
    "instance_id": "",
    "lifecycle_stage": "",
    "visibility_mode": "",
    "metadata": {}
}
```

| 字段 | 说明 |
| --- | --- |
| `domain_id` | 业务域 ID，例如某个游戏、客服场景、聊天场景或工具场景。机器人/RAG 不解析它。 |
| `session_id` | 会话范围 ID，例如一次多人会话、一段对话、一次任务会话。 |
| `instance_id` | 运行实例 ID，例如一局、一轮任务、一次流程。可为空。 |
| `lifecycle_stage` | 当前生命周期阶段，例如 `initializing`、`active`、`review`、`ended`。 |
| `visibility_mode` | 可见性模式，例如 `public`、`self_private`、`post_session_reveal`。 |
| `metadata` | 业务适配层需要携带的非权威元数据。 |

## 记忆更新载荷

`memory_update` 是提交给记忆模块的核心载荷。它不是一段自然语言摘要，也不是模型推理全文，而是按记忆层组织的更新材料。

```gdscript
{
    "schema_version": 1,
    "source": "accepted_output",
    "visibility": "self_private",
    "working_update": {},
    "episodic_events": [],
    "relationship_updates": [],
    "semantic_candidates": [],
    "reflection_candidates": [],
    "importance_hints": {},
    "confidence_hints": {},
    "evidence": []
}
```

| 字段 | 说明 |
| --- | --- |
| `schema_version` | `memory_update` 结构版本。 |
| `source` | 更新来源，例如 `accepted_output`、`accepted_dialogue`、`confirmed_event`、`session_end`。 |
| `visibility` | 可见性，例如 `public`、`self_private`、`post_session_reveal`。 |
| `working_update` | 当前会话短期状态更新，例如当前目标、近期计划、临时判断、情绪倾向。 |
| `episodic_events` | 具体事件记忆候选，例如某个时间点发生了什么、机器人做了什么、对方回应了什么。 |
| `relationship_updates` | 与用户、玩家、角色、机器人或实体相关的关系更新候选。 |
| `semantic_candidates` | 长期经验候选，通常由多次事件或结束后的维护流程提炼。 |
| `reflection_candidates` | 反思候选，例如判断错误、策略失效、成功经验。 |
| `importance_hints` | 调用方给出的重要性提示，最终权重由记忆模块决定。 |
| `confidence_hints` | 调用方给出的置信度提示，最终置信度由记忆模块决定。 |
| `evidence` | 支撑本次更新的已确认事件、对话、输出和结果引用。 |

约定：

- 调用方可以提供分层候选，但不能直接指定底层存储表或绕过记忆模块校验。
- `working_update` 优先服务当前会话，不应直接变成长久人格。
- `semantic_candidates` 和 `reflection_candidates` 是候选，通常需要维护流程确认、合并或降权。
- 如果某次提交只包含事实事件，也可以只填写 `episodic_events` 和 `evidence`。
- 如果某次提交只更新当前会话判断，可以只填写 `working_update`。

## 对外门面接口

### create_or_get_bot_profile

```gdscript
create_or_get_bot_profile(request: Dictionary) -> Dictionary
```

作用：创建机器人档案，或根据 `bot_id` / 绑定信息获取已有机器人档案。

`request`：

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `bot_id` | String | 否 | 指定时优先获取已有机器人。 |
| `display_name` | String | 否 | 机器人展示名，不传时可自动生成。 |
| `avatar_id` | String | 否 | 机器人头像 ID。 |
| `persona_template_id` | String | 否 | 人格模板 ID。 |
| `initial_persona` | Dictionary | 否 | 初始人格、背景、表达风格、行为倾向。 |
| `model_profile_name` | String | 否 | 默认模型配置引用，模型管理模块据此解析实际模型 ID。 |
| `voice_profile_id` | String | 否 | 默认声音配置或音色引用，TTS 模块据此解析实际音色 ID。 |
| `source` | String | 否 | 创建来源，例如 `add_ai_actor`、`load_saved_bot`。 |

`data`：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `bot_profile` | Dictionary | 机器人档案。 |
| `created` | bool | 本次是否新建。 |

约定：

- 机器人档案不是业务角色状态，不保存具体业务权威状态。
- 记忆属于机器人档案本身，不暴露单独的记忆命名配置；底层存储键由机器人 ID 派生。
- 初始人格可以写成设定来源的长期记忆种子，但不能伪造当前会话事实。
- 模型配置引用和声音配置引用只保存稳定 ID；模型调用、TTS 播放和业务输出仍由外部具体业务 AI 机器人玩家适配层编排。

### get_bot_profile

```gdscript
get_bot_profile(request: Dictionary) -> Dictionary
```

作用：读取机器人档案。用于外部模块展示机器人信息、调试绑定关系或配置机器人。

`request`：

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `bot_id` | String | 是 | 机器人 ID。 |
| `include_runtime_state` | bool | 否 | 是否返回当前记忆空间、维护状态等运行时信息。 |

`data`：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `bot_profile` | Dictionary | 机器人档案。 |
| `runtime_state` | Dictionary | 可选运行时状态。 |

### update_bot_profile

```gdscript
update_bot_profile(request: Dictionary) -> Dictionary
```

作用：更新机器人档案的非业务权威字段和人格引用。

`request`：

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `bot_id` | String | 是 | 机器人 ID。 |
| `display_name` | String | 否 | 新展示名。 |
| `avatar_id` | String | 否 | 新头像 ID。 |
| `persona_template_id` | String | 否 | 新人格模板 ID。 |
| `model_profile_name` | String | 否 | 新默认模型配置引用。 |
| `voice_profile_id` | String | 否 | 新默认声音配置或音色引用。 |
| `personality_patch` | Dictionary | 否 | 人格增量调整。 |
| `reason` | String | 否 | 更新原因。 |

`data`：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `bot_profile` | Dictionary | 更新后的机器人档案。 |
| `memory_seed_updated` | bool | 是否同步更新人格种子。 |

约定：

- 修改人格不等于重写历史记忆。
- 如果需要重置记忆，应走单独维护或清理接口，不能在档案更新里隐式删除记忆。

### delete_bot_profile

```gdscript
delete_bot_profile(request: Dictionary) -> Dictionary
```

作用：删除机器人档案，并按策略清理该机器人拥有的记忆范围。配置页和外部业务都不直接调用底层仓库删除机器人。

`request`：

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `bot_id` | String | 是 | 机器人 ID。 |
| `delete_memory` | bool | 否 | 是否同时删除机器人名下记忆，默认 true。 |

`data`：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `deleted` | bool | 是否删除成功。 |
| `bot_profile` | Dictionary | 被删除的机器人档案快照。 |
| `delete_memory` | bool | 本次是否执行记忆清理。 |
| `deleted_memory_scopes` | Array | 已清理的记忆范围。 |

约定：

- 记忆属于机器人自身；删除机器人时默认同步删除该机器人拥有的记忆。
- 调试或导出场景可以显式传入 `delete_memory = false`，但不能让业务层直接操作记忆存储。
- 删除接口不处理具体业务角色解绑，业务模块需要先完成自己的权威状态变更。

### initialize_bot

```gdscript
initialize_bot(request: Dictionary) -> Dictionary
```

作用：初始化机器人运行所需的记忆空间和当前会话工作记忆。

`request`：

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `bot_id` | String | 是 | 机器人 ID。 |
| `scope` | Dictionary | 否 | `BotRuntimeScope`。 |
| `persona_template` | Dictionary | 否 | 初始化人格模板。 |
| `relationship_targets` | Array | 否 | 初始关系对象，例如用户、角色、机器人或业务实体。 |
| `reason` | String | 是 | `bot_created`、`session_started`、`manual`。 |

`data`：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `bot_id` | String | 机器人 ID。 |
| `memory_scope` | Dictionary | 内部记忆存储范围。 |
| `initialized_parts` | Array | 本次初始化的部分。 |

### build_bot_context

```gdscript
build_bot_context(request: Dictionary) -> Dictionary
```

作用：构建当前机器人用于推理的结构化上下文。外部具体业务 AI 机器人玩家适配层在调用模型管理模块前调用该接口。

`request`：

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `bot_id` | String | 是 | 机器人 ID。 |
| `scope` | Dictionary | 否 | `BotRuntimeScope`。 |
| `visible_context` | Dictionary | 是 | 已脱敏的 `BotVisibleContext`。 |
| `task_type` | String | 是 | 当前任务类型。 |
| `max_token_budget` | int | 否 | 总上下文预算。 |
| `memory_options` | Dictionary | 否 | 记忆类型、条数、预算限制。 |
| `context_options` | Dictionary | 否 | 输出结构、裁剪策略、调试选项。 |

`data`：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `bot_profile` | Dictionary | 机器人档案。 |
| `reasoning_context` | Dictionary | `BotReasoningContext`。 |
| `memory_context_used` | Dictionary | 本次使用到的记忆层和条目统计，可用于调试。 |
| `budget_report` | Dictionary | token 预算和裁剪信息。 |

内部流程：

```text
build_bot_context()
  -> 读取 BotProfile
  -> 生成 MemoryContextRequest
  -> AgentMemoryService.get_memory_context()
  -> BotContextBuilder.build_reasoning_context()
  -> 返回 BotReasoningContext
```

约定：

- `visible_context` 必须由调用方按当前机器人视角脱敏。
- 返回的是结构化上下文，不是最终 prompt。
- 如果上下文校验发现不可见信息泄漏，应返回 `ok = false` 或 warning。

### commit_bot_result

```gdscript
commit_bot_result(request: Dictionary) -> Dictionary
```

作用：将已经被外部业务确认的输出、对话、事件和结果提交给机器人模块，由机器人模块转交记忆模块更新。

`request`：

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `bot_id` | String | 是 | 机器人 ID。 |
| `scope` | Dictionary | 否 | `BotRuntimeScope`。 |
| `commit_reason` | String | 是 | `accepted_output`、`accepted_dialogue`、`confirmed_event`、`session_end` 等。 |
| `accepted_outputs` | Array | 否 | 已被外部业务接受的机器人输出，例如行动、文本、工具调用结果。 |
| `accepted_dialogues` | Array | 否 | 已公开或已确认的对话。 |
| `confirmed_events` | Array | 否 | 外部业务已确认事件。 |
| `memory_update` | Dictionary | 否 | 分层记忆更新载荷，见“记忆更新载荷”。 |
| `outcome` | Dictionary | 否 | 输出、阶段、流程或会话结果。 |

`data`：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `updated` | bool | 是否更新了记忆。 |
| `updated_layers` | Array | 实际更新的记忆层，例如 `working`、`episodic`、`relationship`。 |
| `memory_update_report` | Dictionary | 各层写入、跳过、降权、合并的结果。 |
| `maintenance_suggested` | bool | 是否建议触发维护。 |

约定：

- 只能提交已经被外部业务确认的事实。
- 模型原始输出、草稿、被拒绝输出和未提交 UI 输入不能进入该接口。
- `memory_update` 必须由调用方按当前机器人视角脱敏，不能包含当前机器人不可见的信息。
- 机器人模块不理解 `accepted_outputs` 的业务语义，只把它作为事件证据和记忆更新材料。

### maintain_bot

```gdscript
maintain_bot(request: Dictionary) -> Dictionary
```

作用：触发机器人记忆维护，包括会话结束反思、工作记忆清理、长期记忆合并、低价值记忆衰减。

`request`：

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `bot_id` | String | 是 | 机器人 ID。 |
| `scope` | Dictionary | 否 | `BotRuntimeScope`。 |
| `maintenance_type` | String | 是 | `session_end`、`startup`、`manual`、`storage_pressure`、`before_context_build`。 |
| `session_end_memory_update` | Dictionary | 否 | 会话结束时基于已确认事件和结果生成的分层记忆更新载荷。 |
| `options` | Dictionary | 否 | 维护强度、是否清理工作记忆等。 |

`data`：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `maintained` | bool | 是否执行维护。 |
| `generated_reflections` | int | 新增反思数量。 |
| `merged_memories` | int | 合并记忆数量。 |
| `cleared_working_memory` | bool | 是否清理当前会话工作记忆。 |

### list_bot_profiles

```gdscript
list_bot_profiles(request: Dictionary) -> Dictionary
```

作用：列出本机可用机器人。主要用于后续机器人配置页、添加 AI 角色时选择已有机器人。

`request`：

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `limit` | int | 否 | 最大返回数量。 |
| `offset` | int | 否 | 分页偏移。 |
| `filters` | Dictionary | 否 | 人格、最近使用、是否归档等过滤条件。 |

`data`：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `items` | Array | 机器人档案列表。 |
| `total` | int | 总数。 |

### get_bot_debug_state

```gdscript
get_bot_debug_state(request: Dictionary) -> Dictionary
```

作用：只读查看机器人运行状态，用于开发、调试和问题定位。该接口不能修改记忆，默认返回脱敏信息。

`request`：

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `bot_id` | String | 是 | 机器人 ID。 |
| `scope` | Dictionary | 否 | 当前运行范围。 |
| `include_working_memory` | bool | 否 | 是否包含工作记忆概况。 |
| `include_reports` | bool | 否 | 是否包含最近一次上下文、记忆更新和维护报告。 |
| `redact_private` | bool | 否 | 是否脱敏私有内容，默认 true。 |

`data`：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `bot_profile` | Dictionary | 机器人档案。 |
| `memory_health` | Dictionary | 记忆数量、schema 版本、维护状态。 |
| `working_memory_overview` | Dictionary | 当前工作记忆概况，默认脱敏。 |
| `last_context_report` | Dictionary | 最近一次上下文构建报告。 |
| `last_memory_update_report` | Dictionary | 最近一次记忆更新报告。 |
| `last_maintenance_report` | Dictionary | 最近一次记忆维护报告。 |

### get_bot_memory_overview

```gdscript
get_bot_memory_overview(request: Dictionary) -> Dictionary
```

作用：读取独立机器人记忆页和机器人配置页需要的记忆概况。该接口只返回页面可展示的聚合状态，不暴露底层表或向量索引文件。

`request`：

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `bot_id` | String | 是 | 机器人 ID。 |
| `scope` | Dictionary | 否 | 当前运行范围，用于统计当前会话工作记忆。 |
| `include_recent_samples` | bool | 否 | 是否返回少量最近只读摘要。 |
| `redact_private` | bool | 否 | 是否脱敏私有内容，默认 true。 |

`data`：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `bot_profile_summary` | Dictionary | 名称、头像、模型、声音、人设是否存在。 |
| `memory_health` | Dictionary | 健康状态、warning、schema 版本、最近维护时间。 |
| `layer_counts` | Dictionary | 各记忆层数量。 |
| `index_status` | Dictionary | 向量、embedding、text_retrieval 和待索引状态摘要。 |
| `recent_samples` | Array | 最近少量只读摘要，可为空。 |

### list_bot_memory_records

```gdscript
list_bot_memory_records(request: Dictionary) -> Dictionary
```

作用：按记忆层、范围和过滤条件列出机器人记忆页中的只读记录。该接口用于页面列表，不允许 UI 直接修改返回记录。

`request`：

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `bot_id` | String | 是 | 机器人 ID。 |
| `scope` | Dictionary | 否 | 当前运行范围。 |
| `memory_type` | String | 否 | `working`、`relationship`、`episodic`、`semantic`、`reflection`。 |
| `status` | String | 否 | `active`、`candidate`、`archived` 等。 |
| `query` | String | 否 | 页面内文本过滤，不等同正式 RAG 检索。 |
| `limit` | int | 否 | 返回数量。 |
| `offset` | int | 否 | 分页偏移。 |
| `redact_private` | bool | 否 | 是否脱敏私有内容，默认 true。 |

`data`：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `items` | Array | 记忆记录只读摘要。 |
| `total` | int | 总数。 |
| `page_report` | Dictionary | 过滤、脱敏和切换说明。 |

### get_bot_memory_record_detail

```gdscript
get_bot_memory_record_detail(request: Dictionary) -> Dictionary
```

作用：读取单条记忆详情，用于机器人记忆页的详情区域。详情仍然只读，且必须按权限脱敏。

`request`：

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `bot_id` | String | 是 | 机器人 ID。 |
| `memory_id` | String | 是 | 记忆 ID。 |
| `scope` | Dictionary | 否 | 当前运行范围。 |
| `include_evidence` | bool | 否 | 是否返回证据引用。 |
| `include_debug_fields` | bool | 否 | 是否返回 debug 字段，仅开发模式。 |
| `redact_private` | bool | 否 | 是否脱敏私有内容，默认 true。 |

`data`：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `record` | Dictionary | 只读记忆详情。 |
| `evidence` | Array | 支撑该记忆的事件、对话、输出或结果引用。 |
| `debug_fields` | Dictionary | score、来源、索引状态等开发字段，可为空。 |

### get_bot_memory_reports

```gdscript
get_bot_memory_reports(request: Dictionary) -> Dictionary
```

作用：读取机器人记忆页的检索、更新、维护和索引报告。该接口用于解释记忆系统行为，不作为业务逻辑依赖。

`request`：

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `bot_id` | String | 是 | 机器人 ID。 |
| `scope` | Dictionary | 否 | 当前运行范围。 |
| `report_types` | Array | 否 | `context_build`、`memory_update`、`maintenance`、`index`、`schema_reject`。 |
| `limit` | int | 否 | 最大返回数量。 |
| `redact_private` | bool | 否 | 是否脱敏私有内容，默认 true。 |

`data`：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `reports` | Array | 报告列表。 |
| `latest` | Dictionary | 各类型最新报告摘要。 |
| `warnings` | Array | 脱敏、缺失或切换提示。 |

### 记忆模块内部页面接口

机器人模块已经通过 `BotCapabilityFacade` 暴露 `get_bot_*` 门面接口；以下 `MemoryManager.*` 是门面内部复用的只读查询接口。它们面向模块开发和页面联调，不允许具体游戏房间模块直接绕过机器人模块改写记忆。

```gdscript
MemoryManager.get_memory_overview(request: Dictionary) -> Dictionary
MemoryManager.list_memory_records(request: Dictionary) -> Dictionary
MemoryManager.get_memory_reports(request: Dictionary) -> Dictionary
MemoryManager.get_memory_index_status(request: Dictionary) -> Dictionary
```

共同约定：

| 字段 | 说明 |
| --- | --- |
| `request.scope` | 推荐显式传入。缺省时可由 `bot_id`、`game_id/domain_id`、`map_id`、`room_id/session_id`、`memory_namespace` 组装。 |
| `redact_private` | 默认 true。私有内容返回 `[private]`，开发调试需要明文时必须显式传 false。 |
| `retrieval_mode` | `hybrid_vector`、`text_retrieval` 或 `none`，由当前索引和 query 状态决定。 |
| `vector_enabled` | 有可索引记忆且本地索引完成时为 true；native 后端状态单独看 `native_sqlite_vec_enabled` / `native_hnswlib_enabled`。 |
| 结构化主路径 | 页面接口只读取 `persona_snapshot` 和 `memory_records`，不读取开发期临时字段。 |

`get_memory_overview()` 返回：

| 字段 | 说明 |
| --- | --- |
| `memory_health` | `empty`、`text_retrieval`、`degraded`、`ok` 之一，并包含 schema 版本、warning 和最近更新时间。 |
| `layer_counts` | `profile`、`working`、`relationship`、`semantic`、`episodic`、`reflection` 数量。 |
| `index_status` | 当前索引/embedding/text_retrieval 状态。 |
| `persona_snapshot` | 人设快照摘要，默认脱敏。 |
| `recent_samples` | 可选最近样本，只读且默认脱敏。 |
| `latest_reports` | 最近报告摘要。 |

`list_memory_records()` 支持：

| 字段 | 说明 |
| --- | --- |
| `memory_type` | 按 `working`、`relationship`、`episodic`、`semantic`、`reflection` 过滤。 |
| `status` | 按 `active`、`candidate`、`archived` 等过滤。 |
| `subject_id` | 按关系对象或记忆主体过滤。 |
| `query` | 页面文本过滤，不等同正式 RAG 检索。 |
| `limit` / `offset` | 分页。 |

`get_memory_reports()` 当前返回最近一次报告快照：`context_build`、`memory_update`、`maintenance`、`index`。`get_memory_index_status()` 用于页面单独刷新索引状态，返回本地向量、embedding、native 后端、HNSW 图和 text_retrieval warning。

当前实现文件：

| 能力 | 代码 |
| --- | --- |
| 机器人门面 | `scripts/core/bot/bot_capability_facade.gd` |
| 记忆模块内部接口 | `scripts/core/memory/memory_manager.gd` |
| 机器人配置/记忆页面 | `scripts/pages/config/bot_config_page.gd` |

### preview_bot_memory_context

```gdscript
preview_bot_memory_context(request: Dictionary) -> Dictionary
```

作用：开发模式下预览某个任务会召回哪些记忆，用于调试 Memory Query Router、Hybrid Retrieval、Candidate Pool Builder、Policy Reranker Engine 和预算裁剪。release 默认禁用或只返回极简摘要。

`request`：

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `bot_id` | String | 是 | 机器人 ID。 |
| `scope` | Dictionary | 否 | 当前运行范围。 |
| `visible_context` | Dictionary | 是 | 已脱敏的可见上下文。 |
| `task_type` | String | 是 | 当前任务类型。 |
| `memory_options` | Dictionary | 否 | 检索类型、预算和条数限制。 |
| `redact_private` | bool | 否 | 是否脱敏私有内容，默认 true。 |

`data`：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `memory_context` | Dictionary | 预览出的 `AgentMemoryContext`。 |
| `retrieval_report` | Dictionary | query、候选、score、裁剪和 warning。 |
| `budget_report` | Dictionary | token 预算和裁剪报告。 |

### request_bot_memory_maintenance

```gdscript
request_bot_memory_maintenance(request: Dictionary) -> Dictionary
```

作用：从机器人记忆页触发受控维护操作。该接口不直接编辑单条记忆，只调用记忆模块的维护流程。

`request`：

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `bot_id` | String | 是 | 机器人 ID。 |
| `scope` | Dictionary | 否 | 当前运行范围。 |
| `maintenance_type` | String | 是 | `manual`、`startup`、`session_end`、`storage_pressure`、`before_context_build`。 |
| `operation` | String | 否 | `run_light_maintenance`、`rebuild_missing_embeddings`、`rebuild_indexes`。 |
| `options` | Dictionary | 否 | 维护强度、预算和是否允许后台执行。 |

`data`：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `maintenance_started` | bool | 是否已开始维护。 |
| `maintenance_report` | Dictionary | 同步完成时返回报告；后台执行时可为空。 |
| `job_id` | String | 后台维护任务 ID，可为空。 |

### get_last_context_report

```gdscript
get_last_context_report(request: Dictionary) -> Dictionary
```

作用：只读查看最近一次上下文构建报告，包括 token 预算、裁剪、缺失记忆和可见性 warning。

`request`：

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `bot_id` | String | 是 | 机器人 ID。 |
| `scope` | Dictionary | 否 | 当前运行范围。 |
| `redact_private` | bool | 否 | 是否脱敏私有内容，默认 true。 |

`data`：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `context_report` | Dictionary | 上下文构建报告。 |

### get_last_memory_update_report

```gdscript
get_last_memory_update_report(request: Dictionary) -> Dictionary
```

作用：只读查看最近一次记忆更新报告，包括哪些层被写入、跳过、合并、降权或拒绝。

`request`：

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `bot_id` | String | 是 | 机器人 ID。 |
| `scope` | Dictionary | 否 | 当前运行范围。 |
| `redact_private` | bool | 否 | 是否脱敏私有内容，默认 true。 |

`data`：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `memory_update_report` | Dictionary | 最近一次记忆更新报告。 |

### get_last_maintenance_report

```gdscript
get_last_maintenance_report(request: Dictionary) -> Dictionary
```

作用：只读查看最近一次记忆维护报告，包括反思、语义合并、关系维护、衰减、归档、删除和索引任务。

`request`：

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `bot_id` | String | 是 | 机器人 ID。 |
| `scope` | Dictionary | 否 | 当前运行范围。 |
| `redact_private` | bool | 否 | 是否脱敏私有内容，默认 true。 |

`data`：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `maintenance_report` | Dictionary | 最近一次维护报告。 |

只读调试约定：

- 调试接口不得提供直接修改记忆的能力。
- release 包可以禁用或只返回极简健康状态。
- 默认必须脱敏私有内容。
- 调试报告可以帮助定位问题，但不能成为业务逻辑依赖。

## 内部记忆服务接口

以下接口由机器人模块内部调用，不建议外部业务模块、UI 或具体业务 AI 机器人玩家适配层直接调用。

### init_memory

```gdscript
init_memory(request: Dictionary) -> Dictionary
```

作用：创建或补齐机器人长期记忆、关系记忆和当前会话工作记忆空间。

核心参数：

| 字段 | 说明 |
| --- | --- |
| `bot_id` | 机器人 ID。 |
| `scope` | `BotRuntimeScope` / `AgentMemoryScope`。 |
| `persona_template` | 人格模板。 |
| `initial_relationship_targets` | 初始关系对象。 |
| `reason` | 初始化原因。 |

### get_memory_context

```gdscript
get_memory_context(request: Dictionary) -> Dictionary
```

作用：根据当前任务和可见上下文事实检索、筛选并压缩记忆，返回 `AgentMemoryContext`。

核心参数：

| 字段 | 说明 |
| --- | --- |
| `bot_id` | 机器人 ID。 |
| `scope` | 当前运行范围。 |
| `task_type` | 当前任务类型。 |
| `lifecycle_stage` | 当前生命周期阶段。 |
| `visible_context_facts` | 当前机器人可见的关键事实。 |
| `visible_entity_ids` | 当前可见或可互动的实体。 |
| `target_entity_ids` | 当前任务相关目标。 |
| `include_types` | 需要包含的记忆类型。 |
| `max_token_budget` | 记忆上下文预算。 |

返回重点：

| 字段 | 说明 |
| --- | --- |
| `persona_snapshot` | 人格快照。 |
| `working_memory` | 当前会话工作记忆。 |
| `semantic_context` | 长期语义记忆。 |
| `episodic_context` | 事件记忆。 |
| `relationship_context` | 关系记忆。 |
| `reflection_context` | 反思记忆。 |

### update_memory

```gdscript
update_memory(request: Dictionary) -> Dictionary
```

作用：根据已经确认的事件、对话、输出和结果更新记忆。调用方只描述发生了什么，不指定写哪种存储表。

核心参数：

| 字段 | 说明 |
| --- | --- |
| `bot_id` | 机器人 ID。 |
| `scope` | 当前运行范围。 |
| `events` | 已确认事件。 |
| `dialogues` | 已确认对话。 |
| `accepted_outputs` | 已接受输出。 |
| `memory_update` | 分层记忆更新载荷。 |
| `outcome` | 结果。 |
| `update_reason` | 更新原因。 |

### clear_working_memory

```gdscript
clear_working_memory(request: Dictionary) -> Dictionary
```

作用：清理当前会话或运行实例的工作记忆。通常由 `maintain_bot()` 在会话结束后间接触发。

核心参数：

| 字段 | 说明 |
| --- | --- |
| `bot_id` | 机器人 ID。 |
| `scope` | 清理范围。 |
| `archive_before_clear` | 清理前是否归档关键片段。 |

### maintain_memory

```gdscript
maintain_memory(request: Dictionary) -> Dictionary
```

作用：执行记忆反思、合并、衰减、剪枝、索引重建和压缩。

核心参数：

| 字段 | 说明 |
| --- | --- |
| `bot_id` | 机器人 ID。 |
| `scope` | 维护范围。 |
| `maintenance_type` | 维护类型。 |
| `session_end_memory_update` | 会话结束时的分层记忆更新载荷。 |
| `options` | 维护强度、预算和清理策略。 |

## 内部上下文处理接口

以下接口由机器人模块内部调用，主要服务 `build_bot_context()`。

当前代码入口是 `scripts/core/bot/bot_context_builder.gd`。外部业务不直接调用该文件，而是通过 `BotCapabilityFacade.build_bot_context()` 获取结果。

### validate_visible_context

```gdscript
validate_visible_context(context: Dictionary) -> Dictionary
```

作用：校验 `BotVisibleContext` 的基本结构和可见性约束。

返回：

| 字段 | 说明 |
| --- | --- |
| `ok` | 是否通过。 |
| `warnings` | 可继续但需要记录的问题。 |
| `error` | 不可继续的问题。 |

### build_reasoning_context

```gdscript
build_reasoning_context(request: Dictionary) -> Dictionary
```

作用：把 `BotVisibleContext` 和 `AgentMemoryContext` 合并为 `BotReasoningContext`。

`request`：

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `bot_profile` | Dictionary | 是 | 机器人档案。 |
| `scope` | Dictionary | 否 | 当前运行范围。 |
| `visible_context` | Dictionary | 是 | 已脱敏可见上下文。 |
| `memory_context` | Dictionary | 是 | 记忆模块返回的上下文。 |
| `task_type` | String | 是 | 当前任务类型。 |
| `max_token_budget` | int | 否 | 总预算。 |
| `context_options` | Dictionary | 否 | 裁剪和输出选项。 |

`data`：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `reasoning_context` | Dictionary | 结构化推理上下文。 |
| `budget_report` | Dictionary | 预算分配和裁剪说明。 |

### allocate_context_budget

```gdscript
allocate_context_budget(request: Dictionary) -> Dictionary
```

作用：根据任务类型和总 token 预算分配业务上下文、记忆上下文、关系上下文和输出契约的预算。

核心参数：

| 字段 | 说明 |
| --- | --- |
| `task_type` | 当前任务类型。 |
| `max_token_budget` | 总预算。 |
| `visible_context_size` | 可见上下文估算大小。 |
| `memory_context_size` | 记忆上下文估算大小。 |

## 核心数据结构草案

### BotProfile

```gdscript
{
    "bot_id": "",
    "display_name": "",
    "avatar_id": "",
    "persona_id": "",
    "model_profile_name": "",
    "voice_profile_id": "",
    "personality": {},
    "speaking_style": "",
    "strategy_style": "",
    "background_story": "",
    "memory": {},
    "enabled": true,
    "created_at": 0,
    "updated_at": 0
}
```

### BotVisibleContext

```gdscript
{
    "schema_version": 1,
    "adapter_version": 1,
    "bot_id": "",
    "scope": {},
    "task_type": "",
    "self_actor_id": "",
    "visible_entities": [],
    "public_events": [],
    "private_events": [],
    "current_task": {},
    "recent_interactions": [],
    "environment": {},
    "constraints": {}
}
```

### BotReasoningContext

```gdscript
{
    "context_schema_version": 1,
    "bot_id": "",
    "scope": {},
    "task_type": "",
    "lifecycle_stage": "",
    "persona": {},
    "business_context": {},
    "memory_context": {},
    "relationship_context": {},
    "current_goal": "",
    "action_constraints": {},
    "output_contract": {},
    "token_budget": {},
    "warnings": []
}
```

### BotResultCommitRequest

```gdscript
{
    "schema_version": 1,
    "adapter_version": 1,
    "bot_id": "",
    "scope": {},
    "commit_reason": "",
    "accepted_outputs": [],
    "accepted_dialogues": [],
    "confirmed_events": [],
    "memory_update": {
        "schema_version": 1,
        "source": "",
        "visibility": "",
        "working_update": {},
        "episodic_events": [],
        "relationship_updates": [],
        "semantic_candidates": [],
        "reflection_candidates": [],
        "importance_hints": {},
        "confidence_hints": {},
        "evidence": []
    },
    "outcome": {}
}
```

### MemoryOptions

```gdscript
{
    "include_types": ["working", "relationship", "semantic", "episodic", "reflection"],
    "max_items_per_type": 6,
    "max_token_budget": 2048,
    "hard_token_limit": 4096,
    "final_max_items": 24,
    "target_entity_ids": [],
    "require_current_session_working_memory": true
}
```

默认参数以 [记忆系统默认决策](memory-defaults.md) 为准。普通推理任务默认最多返回 2048 estimated tokens，硬上限为 4096 estimated tokens；维护任务可以使用更大的内部预算，但不得直接进入普通模型 prompt。

## 模块调用示例

### 具体业务 AI 机器人玩家适配层推理前

```text
外部业务适配层
  -> 从业务状态生成通用 BotVisibleContext
  -> BotCapabilityFacade.build_bot_context()
  -> 得到 BotReasoningContext
  -> 具体业务 AI 机器人玩家适配层转换为模型 messages / prompt
  -> 模型管理模块完成输入输出
  -> 具体业务 AI 机器人玩家适配层解析模型输出
  -> 外部业务模块校验和接受输出
```

### 输出或事件被确认后

```text
外部业务模块
  -> 确认输出、对话、事件或流程结果
  -> 业务适配层构造通用 BotResultCommitRequest
  -> BotCapabilityFacade.commit_bot_result()
  -> AgentMemoryService.update_memory()
```

### 会话结束后

```text
外部业务模块
  -> 生成已确认事件、结果和可公开材料
  -> 业务适配层组装 session_end_memory_update
  -> BotCapabilityFacade.commit_bot_result(commit_reason = session_end)
  -> BotCapabilityFacade.maintain_bot(maintenance_type = session_end)
  -> 记忆模块生成反思、关系更新和长期经验
  -> 清理当前会话工作记忆
```

## 业务适配说明

具体业务需要在自己的模块内完成映射。例如狼人杀 AI 玩家模块可以把房间、对局、阶段、行动请求、公开事件、私有事件映射成：

- `BotRuntimeScope`
- `BotVisibleContext`
- `BotResultCommitRequest`
- `memory_update`

机器人/RAG 模块只消费这些通用对象，不读取狼人杀房间模块内部状态，也不判断某个行动是否合法。

## 联调关注点

- 玩家模块只保存 `bot_id` 引用；`BotProfile` 由机器人/RAG 模块维护，具体游戏 AI 机器人玩家适配层按需读取。
- `BotVisibleContext` 的通用字段和可见性硬边界以 [跨模块契约](../../contracts/README.md) 为准；各业务适配层负责在本模块文档内补充自己的映射规则。
- `BotReasoningContext` 的 `output_contract` 是否由上下文模块生成，还是由具体业务 AI 机器人玩家适配层生成。
- `memory_update` 的分层字段以 [跨模块契约](../../contracts/README.md) 为准；具体业务只补充“哪些已确认事件映射到哪些层”。
- Android SQLite、桌面 JSON 和未来向量索引的字段命名需要在实现阶段统一。
