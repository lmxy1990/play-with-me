# 记忆检索设计

更新时间：2026-05-15

本文描述记忆模块如何从多层记忆中检索、筛选、排序并组装 `AgentMemoryContext`。检索是记忆模块内部能力，外部业务模块不直接调用向量数据库或查询底层表。

## 当前实现状态

当前新记忆上下文检索已经走正式 Hybrid Retrieval。Android 插件端提供 native sqlite-vec/hnswlib 向量召回；桌面/编辑器保留 Godot 本地向量和文本 text_retrieval。

现状：

- `MemoryManager.get_memory_context()` 从 `persona_snapshot`、`memory_records` 和向量召回结果组合候选。
- `MemoryManager.retrieve()` 不是当前模块主链路，不允许具体游戏房间模块调用。
- 文本 text_retrieval 使用轻量 token 权重。
- 英文按 ASCII word，中文按单字、bigram、trigram 加权。
- 排序主要是 cosine-like 分数加 substring bonus。
- 新主链路候选最终都回到结构化 `memory_records`，native 只提供 memory_id + distance/score，不绕过可见性、状态和预算过滤。
- Android native SQLite 插件负责存取状态，并暴露 `memory_native_rebuild_indexes`、`memory_native_vector_search` 做独立向量召回。

这套实现是当前机器人长期记忆检索方案；native 后端失败时切换到 Godot 本地向量或文本 text_retrieval。

第一版默认参数、top_k、输出条目上限和 token 预算见 [记忆系统默认决策](memory-defaults.md)。如果本文描述与默认决策冲突，以默认决策为当前实现基线。

## 目标检索入口

内部服务接口：

```text
get_memory_context(request) -> AgentMemoryContext
```

输入核心字段：

| 字段 | 说明 |
| --- | --- |
| `bot_id` | 当前机器人。 |
| `scope` | 当前业务域、会话、实例和生命周期。 |
| `task_type` | 当前任务类型。 |
| `visible_context_facts` | 当前机器人可见的事实。 |
| `visible_entity_ids` | 当前机器人可见实体。 |
| `target_entity_ids` | 当前任务重点对象。 |
| `include_types` | 本次需要的记忆类型。 |
| `max_token_budget` | 记忆上下文预算。 |
| `debug_options` | 是否返回检索报告。 |

默认值：

- `max_token_budget = 2048`
- `hard_token_limit = 4096`
- `raw_vector_top_k_per_query = 24`
- `raw_text_top_k_per_query = 24`
- `rerank_top_k = 32`
- `final_max_items = 24`

输出核心字段：

| 字段 | 说明 |
| --- | --- |
| `persona_snapshot` | 当前人格快照。 |
| `working_memory` | 工作记忆。 |
| `relationship_context` | 关系记忆。 |
| `semantic_context` | 语义记忆。 |
| `episodic_context` | 事件记忆。 |
| `reflection_context` | 反思记忆。 |
| `retrieval_report` | 调试报告，可选。 |
| `warnings` | 切换、裁剪、缺失等提示。 |

## Hybrid Retrieval 主链路

```text
MemoryContextRequest
  -> validate_scope_and_visibility()
  -> Memory Query Router
       -> 判断任务意图
       -> 提取 scope / entity / goal / risk / budget
       -> 生成 Query Plan

  -> Memory Source Fetchers
       -> Profile / Persona Snapshot  结构化直取
       -> Working Memory              当前会话直取
       -> Relationship Memory         按 entity 直取
       -> Semantic Memory             HNSW 语义召回
       -> Episodic Memory             SQLite log + sqlite-vec 事件召回
       -> Reflection Memory           按任务和结果经验召回
       -> Text Retrieval            文本检索模式

  -> Candidate Pool Builder
       -> 统一候选格式
       -> 去重和证据合并
       -> bot_id / scope / visibility / status 硬过滤

  -> Policy Reranker Engine
       -> relevance / importance / confidence / recency
       -> relationship priority / risk policy / decay weight
       -> 输出 score 和解释字段

  -> Memory Selection + Fusion
       -> token budget 裁剪
       -> 分层组装
       -> 合并相似片段
       -> 输出 AgentMemoryContext
       -> 写入 retrieval report
```

这条链路是记忆检索的正式主干。实现可以分阶段落地，但接口和报告应按这个结构组织。

关键约定：

- `Memory Query Router` 不直接查库，它输出 `Query Plan`。
- `Profile / Persona Snapshot`、`Working Memory`、`Relationship Memory` 优先走结构化直取，不依赖向量召回。
- 当前 `Semantic Memory` 在 Android 真机优先使用 native hnswlib 召回，桌面/不可用时使用 Godot 本地 HNSW 风格语义图。
- 当前 `Episodic Memory` 以结构化记录为权威数据，在 Android 真机优先使用 native sqlite-vec 召回，桌面/不可用时使用 Godot 本地事件向量槽。
- `Candidate Pool Builder` 必须先做硬过滤，再进入排序。
- 可见性、归属和状态错误的记录直接剔除，不允许靠 rerank 降分处理。
- `Policy Reranker Engine` 是检索质量核心，负责把相关性、重要性、置信度、时效、关系优先级和遗忘策略统一成可解释分数。
- `Memory Selection + Fusion` 负责最终预算裁剪和上下文融合，不再重新访问底层存储。

Hybrid Retrieval 的固定来源：

| 来源 | 目标 | 默认实现 |
| --- | --- | --- |
| `profile_snapshot` | 人设、长期稳定特征、机器人档案派生人格 | 结构化直取。 |
| `working_memory` | 当前会话短期状态 | SQLite / JSON 结构化直取。 |
| `relationship_memory` | 当前目标实体和可见实体关系 | 按 entity 结构化直取。 |
| `sqlite_vec_event` | 事件记忆召回 | Android 真机为 native sqlite-vec；桌面/不可用时为 Godot 本地事件向量槽。 |
| `hnsw_semantic` | 语义记忆召回 | Android 真机为 native hnswlib；桌面/不可用时为 Godot 本地 HNSW 风格图。 |
| `reflection_memory` | 反思和结果经验召回 | 结构化过滤 + 文本/向量召回。 |
| `text_retrieval` | 事件、语义和反思的切换召回 | SQLite FTS、token index 或 Godot 文本 text_retrieval。 |

除人格快照和必须保留的工作记忆外，其它候选最终都进入 Policy Reranker Engine，不允许某个向量索引绕过可见性、状态过滤和预算裁剪。

## Memory Query Router

`Memory Query Router` 负责把一次 `MemoryContextRequest` 变成可执行的 `Query Plan`。它不理解具体业务规则，但可以根据通用任务类型、可见上下文、目标实体和预算判断应该查哪些记忆源。

Router 输入：

| 字段 | 说明 |
| --- | --- |
| `task_type` | 当前任务类型。 |
| `lifecycle_stage` | 当前生命周期阶段。 |
| `visible_context_facts` | 当前机器人可见事实。 |
| `visible_entity_ids` | 当前可见实体。 |
| `target_entity_ids` | 当前任务重点对象。 |
| `memory_options` | include_types、预算、top_k 等。 |
| `retrieval_hints` | 业务适配层给出的非强制检索提示。 |

Router 输出 `Query Plan`：

| 字段 | 说明 |
| --- | --- |
| `intent` | `decision`、`dialogue`、`relationship_check`、`review`、`maintenance`、`debug_preview` 等。 |
| `required_sources` | 必查来源，例如 profile、working、relationship。 |
| `optional_sources` | 可查来源，例如 semantic、episodic、reflection。 |
| `queries` | `task_query`、`entity_query`、`goal_query`、`risk_query`。 |
| `filters` | bot、scope、visibility、status、entity、time range。 |
| `budget_plan` | 各来源预算和最终最大条数。 |
| `text_retrieval_plan` | 向量不可用、召回不足或预算过小时的模式选择策略。 |
| `debug_flags` | 是否写入 query、候选、score 和裁剪报告。 |

Router 规则：

- 当前机器人不可见的信息不能进入 query。
- `profile_snapshot`、`working_memory`、当前目标实体的 `relationship_memory` 默认是 required source。
- 普通行动或对话任务优先查 `semantic` 和少量高价值 `episodic`。
- 复盘、维护或错误分析任务可以提高 `reflection` 和 `episodic` 的预算。
- 如果向量索引不可用，Query Plan 必须切换到 `text_retrieval`，并写入 warning。

## Query 生成

记忆模块不理解具体业务规则，但可以从通用上下文生成检索 query。

query 来源：

- 当前任务目标。
- 当前任务类型。
- 可见实体名称、ID 和关系。
- 最近公开事件。
- 当前机器人自己的私有事件。
- 工作记忆里的当前目标、计划、疑问。
- 外部业务适配层提供的 `retrieval_hints`。

建议生成多个 query：

| Query | 用途 |
| --- | --- |
| `task_query` | 当前任务整体召回。 |
| `entity_query` | 与目标实体相关的关系和事件召回。 |
| `goal_query` | 当前目标、计划、策略相关召回。 |
| `risk_query` | 风险、失败经验、冲突记忆召回。 |

query 必须只包含当前机器人可见信息，不能把隐藏真相塞进检索条件。

## Candidate Pool Builder

`Candidate Pool Builder` 把各来源召回结果统一成候选池。它是进入 Policy Reranker Engine 前的硬边界。

输入来源：

- Profile / Persona Snapshot。
- Working Memory。
- Relationship Memory。
- Semantic Memory。
- Episodic Memory。
- Reflection Memory。
- Text TextRetrieval。

候选统一字段：

| 字段 | 说明 |
| --- | --- |
| `candidate_id` | 候选 ID。 |
| `memory_id` | 记忆 ID，可为空，例如人格快照。 |
| `memory_type` | `profile`、`working`、`relationship`、`semantic`、`episodic`、`reflection`。 |
| `retrieval_source` | `profile_snapshot`、`working_memory`、`relationship_memory`、`sqlite_vec_event`、`hnsw_semantic`、`reflection_memory`、`text_retrieval`。 |
| `content` | 可进入上下文的文本。 |
| `structured_payload` | 结构化字段。 |
| `evidence` | 已确认来源引用。 |
| `scope` | 记忆范围。 |
| `visibility` | 可见性。 |
| `status` | `active`、`candidate`、`archived` 等。 |
| `raw_scores` | 各召回源的原始分数。 |

硬过滤：

- `bot_id` 不匹配直接剔除。
- `visibility` 不允许直接剔除。
- `status = deleted`、`rejected` 直接剔除。
- 普通任务默认剔除 `candidate`，维护任务可以保留。
- 超出当前 scope 或不满足 post-session 可见规则的记录直接剔除。
- hnswlib 召回必须回 SQLite 校验权威元数据后才能进入候选池。

去重和合并：

- 同一 `memory_id` 多来源召回时合并分数和来源。
- 相同事件的多条重复记录只保留证据更完整、置信度更高的版本。
- 相似语义候选可以先保留到 rerank，再在 Selection + Fusion 阶段合并。

## 分层检索策略

### working

工作记忆优先级最高，通常不走向量召回。

策略：

- 按 `bot_id + scope` 直接读取当前会话工作记忆。
- 保留当前目标、短期计划、近期判断、临时情绪和待验证假设。
- 结束后可以清理、归档或转为反思候选。

### relationship

关系记忆优先按实体直取。

策略：

- 根据 `visible_entity_ids` 和 `target_entity_ids` 读取关系状态。
- 如果实体很多，优先目标实体、最近互动实体和高风险实体。
- 关系状态可附带少量支撑事件。
- 不依赖纯向量相似度决定是否返回关键关系。

### semantic

语义记忆是长期经验和抽象认知，适合向量召回。

策略：

- 使用 `task_query`、`goal_query` 和 `risk_query` 从 hnswlib HNSW 索引召回。
- 过滤 `bot_id`、`domain_id`、`visibility`、`status`。
- 召回后按相关性、重要性、置信度、时效性 rerank。
- 低置信度语义记忆可以返回，但要标记 warning 或降低权重。
- hnswlib 只返回向量 label，必须回 SQLite 读取权威内容、证据和可见性。

### episodic

事件记忆记录具体发生过的事。

策略：

- 使用 `entity_query`、`task_query` 从 sqlite-vec 事件索引召回。
- 优先近期、高重要性、有明确结果的事件。
- 避免把大量流水事件塞进上下文。
- 与当前任务无关的既有事件应被裁剪。
- sqlite-vec 负责事件近邻召回，最终是否进入上下文由 Policy Reranker Engine 和 Memory Selection + Fusion 决定。

### reflection

反思记忆来自会话结束或关键阶段维护。

策略：

- 使用 `risk_query`、`goal_query` 召回。
- 优先失败教训、稳定策略、反复出现的问题。
- 反思不能替代事实事件，只能作为经验参考。

## 向量召回目标

目标向量召回不是“查一段最像的话”，而是为当前任务找到可用记忆。

推荐步骤：

```text
structured_filter
  -> sqlite_vec_event_search top_k
  -> hnsw_semantic_search top_k
  -> text_retrieval top_k
  -> merge
  -> PolicyRerankerEngine.rerank
  -> diversity_filter
  -> budget_cut
```

结构化过滤条件：

- `bot_id`
- `memory_type`
- `domain_id`
- `session_id` 或长期范围
- `visibility`
- `status = active`
- `subject_id`，如果有目标实体

## Policy Reranker Engine

最终排序不应只看向量相似度。

`Policy Reranker Engine` 是记忆检索的核心。它负责统一处理来自结构化读取、sqlite-vec、hnswlib 和文本 text_retrieval 的候选。文档和代码统一使用 `Policy Reranker Engine`。

它不负责硬过滤。`bot_id`、`visibility`、`scope`、`status` 这类规则必须在 Candidate Pool Builder 阶段先完成。Reranker 只处理已经允许进入候选池的记忆。

建议综合分：

```text
final_score =
  vector_similarity * 0.40
  + lexical_score * 0.10
  + importance * 0.20
  + confidence * 0.15
  + recency_score * 0.10
  + relationship_priority * 0.05
```

实际权重可以按任务类型调整。

建议扩展策略项：

| 策略项 | 说明 |
| --- | --- |
| `relevance` | 与当前 query、目标和任务的相关性。 |
| `importance` | 记忆本身重要性。 |
| `confidence` | 记忆置信度和证据质量。 |
| `recency` | 时效和最近访问。 |
| `relationship_priority` | 目标实体关系优先级。 |
| `risk_policy` | 风险、冲突、失败经验在特定任务下的加权。 |
| `decay_weight` | 遗忘和衰减后的影响力。 |
| `diversity_penalty` | 避免同类记忆挤占上下文。 |

排序约束：

- 工作记忆固定优先。
- 当前目标实体的关系记忆固定优先。
- 可见性风险记录直接剔除。
- `candidate` 状态记录默认不进入普通上下文，除非是维护任务。
- 同一事件的重复记忆只保留最高质量版本。

候选解释字段：

| 字段 | 说明 |
| --- | --- |
| `retrieval_source` | `structured`、`sqlite_vec_event`、`hnsw_semantic`、`text_retrieval`。 |
| `raw_rank` | 原召回排名。 |
| `vector_score` | 向量分，可为空。 |
| `lexical_score` | 文本分。 |
| `importance` | 重要性。 |
| `confidence` | 置信度。 |
| `recency_score` | 时效分。 |
| `final_score` | 排序最终分。 |
| `kept` | 是否进入最终上下文。 |
| `drop_reason` | 未进入上下文的原因。 |

## Memory Selection + Fusion

`Memory Selection + Fusion` 负责把 rerank 后的候选变成最终 `AgentMemoryContext`。它不是简单取 top N，而是在 token 预算内按层级、任务和可解释性组装上下文。

职责：

- 按 `budget_plan` 分配各记忆层 token。
- 优先保留人格快照、工作记忆和目标关系记忆。
- 从 semantic、episodic、reflection 候选中选择高价值片段。
- 合并高度相似的语义片段。
- 把事件证据折叠成短引用，避免流水事件挤占上下文。
- 输出分层结构，而不是拼成一段自然语言。
- 写入 selected、dropped、fused 和 truncated 报告。

输出结构：

| 输出块 | 来源 |
| --- | --- |
| `persona_snapshot` | Profile / Persona Snapshot。 |
| `working_memory` | Working Memory。 |
| `relationship_context` | Relationship Memory。 |
| `semantic_context` | Semantic Memory。 |
| `episodic_context` | Episodic Memory。 |
| `reflection_context` | Reflection Memory。 |
| `warnings` | 切换、裁剪、冲突和可见性提示。 |

Fusion 规则：

- 不把不同可见性的内容合并成一条不可追溯记忆。
- 合并后的片段必须保留 evidence 引用。
- 截断必须记录 `drop_reason = token_budget` 或 `truncated`。
- 普通任务不输出维护任务内部材料。
- 输出的是 `AgentMemoryContext`，不是最终 prompt。

## Token 预算

检索结果必须在预算内返回。

普通推理任务默认最大输出为 2048 estimated tokens，硬上限为 4096 estimated tokens。维护任务可以使用 8192 estimated tokens，但不得直接进入普通模型 prompt。

默认预算顺序：

1. 人格快照。
2. 当前任务直接相关的工作记忆。
3. 当前目标实体关系记忆。
4. 高相关语义记忆。
5. 高价值事件记忆。
6. 关键反思记忆。
7. 近期交互补充。

预算报告字段：

| 字段 | 说明 |
| --- | --- |
| `max_token_budget` | 传入预算。 |
| `estimated_used` | 估算使用量。 |
| `kept_counts` | 各层保留数量。 |
| `dropped_counts` | 各层裁剪数量。 |
| `drop_reasons` | 裁剪原因。 |

## 模式选择策略

| 场景 | 策略 |
| --- | --- |
| 向量索引不可用 | 使用文本检索 text_retrieval，返回 warning。 |
| embedding 版本不一致 | 使用可用索引并标记 `embedding_version_mismatch`，后台重建。 |
| 检索为空 | 返回工作记忆和人格快照，不阻断业务。 |
| 预算过小 | 只保留工作记忆和目标关系记忆。 |
| 可见性风险 | 剔除风险条目，并写入调试报告。 |

## 调试报告

每次检索建议生成只读报告。

```gdscript
{
    "retrieval_mode": "hybrid_vector" or "text_retrieval",
    "query_plan": {},
    "vector_sources": {
        "sqlite_vec_event": true,
        "hnsw_semantic": true
    },
    "queries": [],
    "filters": {},
    "candidate_counts": {},
    "source_fetch_report": {},
    "candidate_pool_report": {},
    "rerank_report": {},
    "fusion_report": {},
    "selected_items": [],
    "dropped_items": [],
    "budget_report": {},
    "warnings": []
}
```

每条召回项建议包含：

| 字段 | 说明 |
| --- | --- |
| `memory_id` | 记忆 ID。 |
| `memory_type` | 记忆类型。 |
| `source` | 来源。 |
| `visibility` | 可见性。 |
| `score` | 最终分。 |
| `vector_score` | 向量分，可为空。 |
| `importance` | 重要性。 |
| `confidence` | 置信度。 |
| `drop_reason` | 如果被裁剪，记录原因。 |

## 开发约定

- 检索结果只能来自当前机器人允许访问的记忆。
- 向量召回不能绕过可见性过滤。
- Router 必须输出可记录的 Query Plan，不能让检索来源和预算隐式散落在代码里。
- Candidate Pool Builder 必须先完成硬过滤，再进入 Policy Reranker Engine。
- 召回结果必须可解释，至少能在 debug 面板看到 query、score、来源和裁剪原因。
- 正常机器人配置页不展示向量细节；这些只放开发调试面板。
- 业务适配层可以传 `retrieval_hints`，但不能直接指定底层表或索引。
