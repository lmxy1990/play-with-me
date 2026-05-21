# 记忆模块

更新时间：2026-05-15

记忆模块是机器人/RAG 系统的底层能力，负责机器人自身记忆的存储、检索、更新、维护和防污染。它不理解具体业务，不调用模型，也不直接拼业务 prompt。

对外看，记忆模块是黑盒子：外部只提交通用运行范围、可见事实和分层 `memory_update`，记忆模块自己决定如何写入、合并、衰减或忽略不同层的记忆。

## 模块定位

```text
机器人模块
  -> 记忆模块
       -> 初始化记忆空间
       -> 检索记忆片段
       -> 更新记忆
       -> 维护、压缩、衰减和清理记忆

记忆模块
  -> 返回结构化 AgentMemoryContext
  -> 不生成 BotReasoningContext
  -> 不调用模型
  -> 不执行业务规则
```

记忆模块作为机器人模块的内部服务存在。外部业务模块原则上不直接操作记忆存储，而是通过机器人模块暴露的门面接口使用。

## 当前实现与目标状态

当前代码已经完成记忆系统第一版闭环：结构化多层记忆、本地 embedding、Android native sqlite-vec 事件索引、Android native hnswlib 语义索引、Godot 本地 text_retrieval、混合检索、排序、蒸馏、合并、遗忘和报告。

当前实现：

- 桌面/编辑器使用 JSON 文件保存记忆状态。
- Android 使用 native SQLite 插件保存记忆状态，并在插件端维护 native 向量索引。
- 检索使用 Hybrid Retrieval：profile / working / relationship 结构化直取、native/Godot 事件向量、native/Godot 语义图和文本 text_retrieval。
- 记忆内容使用 `persona_snapshot` + `memory_records`，分为 `working`、`episodic`、`semantic`、`relationship`、`reflection`。
- embedding 使用 Godot 本地 `token_hash_v1`，用于当前阶段的可运行向量索引。
- native sqlite-vec 与 hnswlib 已接入 Android 插件；ObjectBox 不进入当前实现。报告会区分本地后端和 native 后端。

目标实现：

- 结构化保存 `working`、`episodic`、`semantic`、`relationship`、`reflection` 多层记忆。
- `episodic` 事件记忆在 Android 真机优先使用 native sqlite-vec 做召回，不可用时切换到本地事件向量槽。
- `semantic` 语义记忆在 Android 真机优先使用 native hnswlib 做召回，不可用时切换到本地 HNSW 风格图或文本 text_retrieval。
- 使用 Memory Query Router、Hybrid Retrieval、Candidate Pool Builder、Policy Reranker Engine、Memory Selection + Fusion 和文本 text_retrieval 共同构建记忆上下文。
- 将记忆更新设计成分层 `memory_update`，由 Memory Formation 和记忆模块决定写入、跳过、合并、降权或拒绝。
- 维护流程负责 Memory Distillation、Memory Merge、Forgetting、关系演化、冲突处理和索引重建。
- 机器人配置页只展示记忆概况和进入记忆页入口；完整记忆展示使用独立机器人记忆页，不使用弹窗；开发视图展示 query、召回 score、裁剪和维护报告。

细节拆分：

- [记忆系统默认决策](memory-defaults.md)
- [记忆存储设计](memory-storage.md)
- [记忆检索设计](memory-retrieval.md)
- [记忆更新设计](memory-update.md)
- [记忆维护设计](memory-maintenance.md)
- [机器人记忆页面设计](memory-ui.md)
- [记忆调试与呈现设计](memory-debug.md)

## 复杂度约定

记忆模块不是一个 `BotProfile.memory` 字段，也不是一段长期摘要。它是机器人/RAG 模块里最核心的独立子系统，需要能回答“记住什么、何时召回、如何更新、如何避免污染、如何自我整理、如何解释结果”。

第一版实现可以分阶段落地，但文档和接口需要按完整系统设计，避免后续再次整体推倒。

硬约定：

- 记忆系统内部必须分存储、形成、检索、排序、更新、维护和报告。
- 记忆系统对外只暴露 `AgentMemoryService` 语义，不暴露底层表和索引。
- `memory_update` 是通用分层更新材料，不绑定狼人杀或其它具体业务。
- 记忆页面是独立页面，不是弹窗，也不是机器人配置页里的复杂面板。
- 当本地或 native 向量索引不可用时，必须明确标记为 text_retrieval；当使用 Godot 本地向量索引时，报告必须显示本地后端，不能伪装成 native sqlite-vec/hnswlib。

## 内部子系统

| 子系统 | 责任 |
| --- | --- |
| `MemoryRecordStore` | 权威保存多层记忆、证据、可见性、状态、版本和报告引用。 |
| `MemoryFormation` | 从已确认事件、对话、输出和结果形成分层候选。 |
| `Memory Query Router` | 判断检索意图，生成 Query Plan，分配来源、query、过滤条件和预算。 |
| `HybridRetrieval` | 组合 profile、working、relationship 结构化直取，sqlite-vec 事件召回、HNSW 语义召回、reflection 和文本 text_retrieval。 |
| `Candidate Pool Builder` | 统一候选格式，执行 bot、scope、visibility、status 硬过滤，合并重复来源和证据。 |
| `Policy Reranker Engine` | 对允许进入候选池的记忆统一打分、策略排序和解释。 |
| `Memory Selection + Fusion` | 按 token 预算分层选择、融合相似片段并输出 `AgentMemoryContext`。 |
| `MemoryDistillation` | 从事件、反思和关系变化中提炼长期语义记忆。 |
| `MemoryMerge` | 合并重复、相似、冲突或可归纳的记忆，并保留证据链。 |
| `Forgetting` | 衰减、归档、合并或删除低价值记忆。删除只用于隐私清理、损坏数据或明确操作。 |
| `MemoryReportStore` | 保存检索、更新、维护、结构拒绝和索引报告，供独立记忆页只读展示。 |

这些子系统已在 Godot 侧按较小类拆开；Android SQLite、sqlite-vec、hnswlib 和本地 embedding 已通过同一记忆门面接入。外部接口不应因为底层阶段变化而频繁变动。

## 能力边界

记忆模块负责：

- 创建和校验内部记忆存储范围。
- 保存、读取和校验记忆数据。
- 维护当前会话工作记忆。
- 检索长期语义记忆、事件记忆、关系记忆和反思记忆。
- 在预算内返回结构化记忆上下文。
- 根据已确认事件更新工作记忆、事件记忆和关系记忆。
- 会话结束后生成反思候选和长期经验。
- 执行记忆维护：合并、衰减、压缩、剪枝和清理。

记忆模块不负责：

- 机器人档案展示、头像、人格选择 UI。
- 可见业务上下文脱敏和业务上下文整理。
- 模型调用、输出解析和切换。
- 具体游戏房间模块校验、网络同步或 TTS。

## 记忆空间

### AgentMemoryScope

| 字段 | 说明 |
| --- | --- |
| `bot_id` | 机器人 ID。 |
| `persona_id` | 人格模板 ID。 |
| `domain_id` | 业务域 ID，只作为命名空间隔离和检索条件，不解析业务含义。 |
| `session_id` | 当前会话 ID，可为空。 |
| `instance_id` | 当前运行实例 ID，可为空。 |
| `long_term_key` | 长期记忆内部存储键，默认由机器人 ID 派生。 |
| `working_key` | 当前会话工作记忆内部存储键。 |
| `relationship_key` | 关系记忆内部存储键。 |

约定：

- A 机器人的记忆不能污染 B 机器人。
- 这些存储键是内部实现细节，不作为机器人配置页里的可命名对象。
- 当前会话工作记忆不能直接变成长期人格。
- 跨会话长期记忆必须经过反思、合并或高价值证据确认。
- `domain_id`、`session_id`、`instance_id` 都是隔离和检索键，不代表记忆模块理解具体业务。

## 记忆类型

| 类型 | 作用 | 生命周期 |
| --- | --- | --- |
| `working` | 当前会话认知状态，例如近期判断、当前目标、计划、情绪。 | 当前会话/当前运行实例，结束后归档或清理。 |
| `episodic` | 具体发生过的事件，例如某次对话、某次输出、某个确认结果。 | 可跨会话保留，但需要重要性和置信度。 |
| `semantic` | 长期经验和抽象认知，例如“遇到某类模式时需要先验证证据”。 | 长期保留，通常来自反思或多次事件合并。 |
| `relationship` | 与用户、玩家、角色、机器人或实体相关的信任、合作、欺骗、偏好、敌对倾向。 | 跨会话演化，受近期事件和反思影响。 |
| `reflection` | 会话后反思、失败原因、正确判断和错误判断。 | 会话结束后生成，可继续合并成语义记忆。 |

默认层级、预算和输出上限见 [记忆系统默认决策](memory-defaults.md)。其中 `persona_snapshot` 是上下文块，不作为普通 `MemoryRecord.memory_type` 主层处理。

## 内部数据

### MemoryRecord

`MemoryRecord` 是内部存储实体，不直接暴露给外部模块。

| 字段 | 说明 |
| --- | --- |
| `memory_id` | 记忆 ID。 |
| `bot_id` | 归属机器人。 |
| `memory_type` | `working`、`episodic`、`semantic`、`relationship`、`reflection`。 |
| `scope` | 会话、运行实例或长期命名空间。 |
| `subject_id` | 记忆关联对象，可为用户、角色、机器人、业务实体、事件或主题。 |
| `content` | 记忆内容。 |
| `visibility` | `public`、`self_private`、`post_session_reveal` 等可见性标记。 |
| `importance` | 重要性。 |
| `confidence` | 置信度。 |
| `source` | 事件、输出、对话、反思、合并或初始化。 |
| `created_at` / `updated_at` | 创建和更新时间。 |

## 对外服务

记忆模块对机器人模块提供 `AgentMemoryService`。

```text
init_memory(request) -> MemoryInitResult
get_memory_context(request) -> AgentMemoryContext
update_memory(request) -> MemoryUpdateResult
clear_working_memory(request) -> ClearWorkingMemoryResult
maintain_memory(request) -> MemoryMaintenanceResult
```

这些接口是内部服务接口。外部业务模块应通过 [机器人模块](bot-module.md) 的门面接口间接使用。

### 初始化记忆

`MemoryInitRequest`：

| 字段 | 说明 |
| --- | --- |
| `bot_id` | 机器人 ID。 |
| `scope` | 记忆空间。 |
| `persona_template` | 人格模板。 |
| `initial_relationship_targets` | 初始关系对象，可为空。 |
| `reason` | `bot_created`、`session_started`、`manual`。 |

初始化内容：

- 初始人格。
- 初始长期语义记忆。
- 初始关系倾向。
- 当前会话工作记忆空间。
- 反思种子或背景经历，必须标记为设定来源。

### 获取记忆上下文

`MemoryContextRequest`：

| 字段 | 说明 |
| --- | --- |
| `bot_id` | 机器人 ID。 |
| `scope` | 当前运行范围。 |
| `task_type` | 当前任务类型。 |
| `lifecycle_stage` | 当前生命周期阶段。 |
| `visible_context_facts` | 机器人模块传入的当前可见关键事实。 |
| `visible_entity_ids` | 当前机器人可见或可互动的实体。 |
| `target_entity_ids` | 当前任务相关目标，可为空。 |
| `max_token_budget` | 记忆上下文预算。 |
| `include_types` | 需要包含的记忆类型。 |

返回 `AgentMemoryContext`：

| 字段 | 说明 |
| --- | --- |
| `bot_id` | 机器人 ID。 |
| `persona_snapshot` | 当前人格快照。 |
| `working_memory` | 当前会话工作记忆快照。 |
| `semantic_context` | 长期语义记忆片段。 |
| `episodic_context` | 相关事件记忆片段。 |
| `relationship_context` | 与可见实体相关的关系记忆。 |
| `reflection_context` | 反思和长期经验片段。 |
| `token_budget_used` | 组装后估算 token 用量。 |
| `warnings` | 记忆缺失、检索失败、预算裁剪等提示。 |

检索优先级：

1. 当前会话 `working` 记忆。
2. 与可见实体相关的 `relationship` 记忆。
3. 与任务强相关的 `semantic` 记忆。
4. 高相关、高重要性的 `episodic` 记忆。
5. 最近或高价值的 `reflection` 记忆。

### 更新记忆

`MemoryUpdateRequest`：

| 字段 | 说明 |
| --- | --- |
| `bot_id` | 机器人 ID。 |
| `scope` | 当前运行范围。 |
| `events` | 外部业务已确认的事件。 |
| `dialogues` | 已确认对话。 |
| `accepted_outputs` | 已被外部业务接受的输出。 |
| `memory_update` | 分层记忆更新载荷，包含 working、episodic、relationship、semantic、reflection 等更新候选。 |
| `outcome` | 输出、流程或会话结果。 |
| `update_reason` | 更新原因。 |

约定：

- 调用方提交“发生了什么”，不要指定写哪张表。
- 调用方可以提供分层候选，但记忆模块内部决定更新工作记忆、事件记忆、关系记忆、反思候选或长期语义记忆。
- 被外部业务拒绝的输出、模型草稿、UI 临时输入不能写入记忆。

### 分层记忆更新

`memory_update` 不是摘要，而是“本次可以进入记忆系统的更新材料”。建议按下面的层次组织：

| 层 | 字段 | 说明 |
| --- | --- | --- |
| 工作记忆 | `working_update` | 当前会话短期状态，例如当前目标、近期计划、临时判断、当前情绪。 |
| 事件记忆 | `episodic_events` | 已确认的具体事件，例如对话、输出、外部反馈、流程结果。 |
| 关系记忆 | `relationship_updates` | 与用户、角色、机器人或实体相关的信任、合作、偏好、欺骗、敌对变化。 |
| 语义记忆 | `semantic_candidates` | 长期经验候选，通常需要维护流程合并或确认。 |
| 反思记忆 | `reflection_candidates` | 会话后或关键阶段后的策略反思候选。 |
| 证据 | `evidence` | 支撑本次更新的输出、对话、事件和结果引用。 |

记忆模块会根据可见性、来源、重要性、置信度和当前维护策略，决定：

- 写入哪一层记忆。
- 是否只更新当前会话工作记忆。
- 是否把事件记为长期事件。
- 是否更新某个实体关系。
- 是否暂存为反思或语义候选。
- 是否因为证据不足、不可见或重复而跳过。

## 维护流程

```text
会话结束或维护触发
  -> 读取 working memory 和关键 episodic memory
  -> 生成 reflection candidate
  -> 提炼 semantic lessons
  -> 更新 relationship memory
  -> 衰减低价值既有记忆
  -> 合并重复事件
  -> 剪枝低置信度、低重要性和长期未使用记忆
  -> 清理过期 working memory
```

维护触发场景：

- 会话结束。
- 应用启动后的轻量检查。
- 低存储空间。
- 手动触发。
- 构建上下文前发现记忆过大。

## 防污染规则

- 只能写入当前机器人可见的信息。
- 公共事件可以写入公共来源记忆。
- 私有事件只能写入当前机器人自己的私有记忆。
- 当前机器人不知道的隐藏事实或其它主体私有信息不能写入。
- 模型草稿、被拒绝输出、未提交 UI 输入不能写入。
- 推理过程不能直接以“摘要”写入记忆。若要沉淀，只能转换为已脱敏的 `memory_update` 候选，并由记忆模块按分层规则处理。
- 结束后如果包含此前不可见、之后才公开的信息，需要标记来源为 `post_session_reveal`。

## 持久化

当前实现分散在：

```text
scripts/core/memory/
  memory_manager.gd

scripts/android/
  android_memory_store.gd

scripts/room/werewolf/
  werewolf_memory.gd
  werewolf_memory_context.gd
  werewolf_memory_model_summarizer.gd

android_plugins/play_with_me_android/.../MemoryDatabase.kt
```

存储策略：

- 桌面/编辑器可以使用 `user://` JSON 路径。
- Android 真机优先使用 SQLite。
- Android 插件端同时承担结构化持久化、sqlite-vec 事件索引和 hnswlib 语义/反思索引。
- 第一版已落地 sqlite-vec 事件索引 + hnswlib 语义索引，ObjectBox 只作为后续替代方案；外部接口保持 `AgentMemoryService` 形态。
- 具体目标结构见 [记忆存储设计](memory-storage.md)，检索流程见 [记忆检索设计](memory-retrieval.md)。

## 版本与无效数据

记忆模块需要独立维护 schema 版本。版本不匹配的数据直接拒绝或丢弃。

建议版本字段：

| 字段 | 说明 |
| --- | --- |
| `memory_schema_version` | 记忆存储结构版本。 |
| `record_schema_version` | 单条 `MemoryRecord` 结构版本。 |
| `context_schema_version` | `AgentMemoryContext` 输出结构版本。 |
| `adapter_version` | 业务适配层写入数据的版本。 |

处理规则：

- 新字段必须有默认值。
- 字段删除或改名时同步更新 SQLite、JSON、向量索引、生产者、消费者和文档。
- SQLite、JSON 和向量索引只读取当前结构版本。
- 版本不匹配或字段不完整的记忆数据直接拒绝或丢弃，并返回结构化 warning 或 error。

## 失败处理

记忆模块失败不应直接破坏外部业务流程。

| 场景 | 策略 |
| --- | --- |
| 读取失败 | 返回空 `AgentMemoryContext` 和 warning，允许具体业务 AI 机器人玩家适配层无记忆继续。 |
| 写入失败 | 返回失败报告，不撤销外部业务结果。 |
| 维护失败 | 保留原记忆状态，下次启动、空闲或手动维护时再次发起。 |
| 预算过小 | 优先保留工作记忆和关系记忆，裁剪低优先级事件和反思。 |
| 可见性风险 | 拒绝写入或切换为 warning，不写入长期记忆。 |

## 维护规则

- 记忆模块不向外暴露存储表或向量索引。
- 记忆结构变更时，同步桌面 JSON、Android SQLite、Godot bridge、测试和本文档。
- `MemoryDatabase.kt` 同时维护记忆表和模型配置表，改 schema 时要同步确认 `SCHEMA_VERSION`、建表语句、索引和 Godot 桥接字段。
- 工作记忆、事件记忆、关系记忆、语义记忆和反思记忆不能混写。
- 长期记忆需要反思、合并或明确高价值证据，不能每轮交互都写入长期记忆。
- 记忆展示使用独立机器人记忆页，不使用弹窗承载完整记忆系统。
