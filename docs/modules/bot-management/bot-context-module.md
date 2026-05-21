# 机器人上下文处理模块

更新时间：2026-05-16

机器人上下文处理模块负责把“当前机器人可见的业务信息”和“记忆模块返回的记忆上下文”整理成可供具体业务 AI 机器人玩家适配层推理使用的结构化上下文。它不存储记忆，不调用模型，也不决定最终输出。

它不绑定具体业务。调用方必须先把具体业务状态转换成通用 `BotVisibleContext`，本模块只处理通用结构。

当前代码入口是 `scripts/core/bot/bot_context_builder.gd`。该内部模块由 `BotCapabilityFacade.build_bot_context()` 和 `preview_bot_memory_context()` 调用，负责校验可见上下文、生成记忆检索请求、组装 `BotReasoningContext` 和分配上下文预算。

## 模块定位

```text
机器人模块
  -> 传入 BotVisibleContext
  -> 传入 AgentMemoryContext
  -> 机器人上下文处理模块
       -> 校验可见性
       -> 标准化当前任务
       -> 合并业务上下文和记忆上下文
       -> 分配 token 预算
       -> 输出 BotReasoningContext
```

机器人上下文处理模块是“整理输入”的模块，不是“做决策”的模块。

## 能力边界

本模块负责：

- 接收调用方提供的通用可见上下文。
- 校验上下文只包含当前机器人可见的信息。
- 将业务上下文归一化成稳定结构。
- 合并 `AgentMemoryContext`。
- 按任务类型分配上下文优先级和 token 预算。
- 生成结构化 `BotReasoningContext`。
- 输出上下文警告，例如缺少记忆、上下文过大、可见实体为空。

本模块不负责：

- 从具体业务模块直接读取权威状态。
- 判断具体业务动作是否合法。
- 调用模型管理模块。
- 拼接某个模型供应商的请求体。
- 解析模型输出。
- 更新记忆。

## 输入对象

### BotVisibleContext

`BotVisibleContext` 由调用方提供。具体业务适配层负责把业务状态转换成这个通用结构。

| 字段 | 说明 |
| --- | --- |
| `bot_id` | 机器人 ID。 |
| `scope` | `BotRuntimeScope`，描述业务域、会话、运行实例和生命周期阶段。 |
| `task_type` | 当前任务类型。 |
| `self_actor_id` | 当前机器人绑定的业务主体 ID，可为空。 |
| `visible_entities` | 当前机器人可见的用户、角色、机器人、对象或业务实体。 |
| `public_events` | 当前可见的公开事件。 |
| `private_events` | 当前机器人自己的私有可见事件。 |
| `current_task` | 外部业务交给当前机器人的任务请求。 |
| `recent_interactions` | 当前可见的近期交互。 |
| `environment` | 场景、界面或运行环境信息。 |
| `constraints` | 输出约束，例如候选目标、允许动作、字数、时间限制。 |

约定：

- `BotVisibleContext` 必须已经脱敏。
- 本模块可以做防线式校验，但不能依赖自己修复上游泄漏。
- 其它主体私有信息、当前机器人不可见事实、未公开真相不能进入该对象。

### AgentMemoryContext

`AgentMemoryContext` 由 [记忆模块](memory-module.md) 返回。

它包含：

- 人格快照。
- 当前会话工作记忆。
- 长期语义记忆片段。
- 事件记忆片段。
- 关系记忆片段。
- 反思记忆片段。
- 记忆警告和预算信息。

## 输出对象

### BotReasoningContext

`BotReasoningContext` 是机器人模块对具体业务 AI 机器人玩家适配层暴露的主要上下文结果。

| 字段 | 说明 |
| --- | --- |
| `bot_id` | 机器人 ID。 |
| `scope` | 当前运行范围。 |
| `task_type` | 当前任务类型。 |
| `lifecycle_stage` | 当前生命周期阶段。 |
| `persona` | 人格和表达风格。 |
| `business_context` | 标准化后的通用业务可见上下文。 |
| `memory_context` | 已筛选和压缩后的记忆上下文。 |
| `relationship_context` | 与当前可见实体相关的关系视图。 |
| `current_goal` | 从工作记忆或任务约束中整理出的当前目标。 |
| `action_constraints` | 可执行动作、候选目标、输出限制。 |
| `output_contract` | 具体业务 AI 机器人玩家适配层期望模型返回的结构化结果要求。 |
| `token_budget` | 各上下文块预算。 |
| `warnings` | 上下文缺失、裁剪和可见性提示。 |

约定：

- `BotReasoningContext` 不是最终 prompt。
- 具体业务 AI 机器人玩家适配层可以根据目标模型和具体业务任务继续转成 prompt 或结构化 messages。
- 本模块输出的是稳定结构，不绑定 OpenAI、Ollama、Anthropic 或 Gemini 具体请求格式。

## 任务类型

任务类型是通用标签，由具体业务适配层定义。建议先保留以下通用类型：

| 类型 | 说明 |
| --- | --- |
| `generate_dialogue` | 生成对话或公开文本。 |
| `choose_action` | 在候选动作中选择行动。 |
| `choose_target` | 在候选对象中选择目标。 |
| `respond_to_event` | 回应外部事件。 |
| `analyze_entity` | 分析用户、角色、对象或业务实体。 |
| `plan_next_step` | 形成短期计划。 |
| `reflect_session` | 会话结束反思。 |

任务类型只影响上下文排序和输出契约，不直接产生行动。

## 上下文组装流程

```text
BotVisibleContext
  -> validate_visibility()
  -> normalize_business_context()
  -> merge AgentMemoryContext
  -> prioritize_context_blocks(task_type)
  -> allocate_token_budget()
  -> build_output_contract()
  -> BotReasoningContext
```

### 可见性校验

校验项：

- `bot_id` 必须和当前机器人一致。
- `visible_entities` 不包含当前视角不可见的私有属性。
- `private_events` 只能包含当前机器人自己的私有信息。
- `current_task` 的候选目标或候选动作不能超出外部业务给出的可选范围。
- 结束后才公开的信息如果进入上下文，需要标记来源为 `post_session_reveal`。

### 上下文优先级

默认优先级：

1. 当前任务请求和输出约束。
2. 当前机器人自己的可见状态。
3. 当前生命周期阶段的公开事实。
4. 当前会话工作记忆。
5. 目标实体关系记忆。
6. 任务相关长期语义记忆。
7. 高价值事件记忆。
8. 反思经验。
9. 近期交互。

不同任务可以调整优先级。例如选择动作时优先候选动作和约束，生成对话时优先近期交互和表达风格。

## 与记忆模块的关系

机器人上下文处理模块不直接检索数据库。它接收记忆模块返回的 `AgentMemoryContext`，并负责把它放到合适的上下文位置。

```text
机器人模块
  -> 记忆模块 get_memory_context()
  -> 机器人上下文处理模块 build_reasoning_context()
```

这样可以避免上下文处理模块同时承担存储检索职责。

## 与具体业务 AI 机器人玩家适配层的关系

具体业务 AI 机器人玩家适配层消费 `BotReasoningContext`，然后：

```text
BotReasoningContext
  -> 构建模型 messages 或 prompt
  -> 调用模型管理模块
  -> 解析模型输出
  -> 形成候选输出
  -> 提交给外部业务模块校验
```

具体业务 AI 机器人玩家适配层仍负责：

- 针对模型供应商选择 prompt/messages 形态。
- 定义模型输出 schema。
- 解析失败处理。
- 将候选输出提交给具体业务模块校验。
- 在业务确认后调用机器人模块更新记忆。

## 业务适配说明

具体业务需要在自己的模块里完成映射。例如狼人杀 AI 玩家模块可以把房间、对局、阶段、行动请求、公开事件、私有事件映射成通用 `BotVisibleContext`。上下文处理模块不读取狼人杀房间模块内部状态，也不判断狼人杀行动是否合法。

## 维护规则

- 上下文处理只能处理调用方传入的通用可见数据，不直接读业务权威状态。
- 输出必须结构化，不能只返回拼接好的自然语言 prompt。
- 不把模型草稿、未确认输出或隐藏信息放入记忆更新。
- 任务类型新增时，同步上下文优先级、输出契约和具体业务 AI 机器人玩家适配层。
- 如果发现上游传入不可见信息，应返回 warning 或 error，不能默默写入记忆。
