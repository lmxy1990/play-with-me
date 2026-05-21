# 记忆系统默认决策

更新时间：2026-05-15

本文固定记忆模块第一版落地时的默认选择。后续可以调参，但代码实现、UI 呈现和模块联调先按本文收口，避免“向量库、检索、提取、层级、最大输出”各自发散。

## 总结

当前定版：

| 项 | 默认决策 |
| --- | --- |
| 权威存储 | Android 使用 SQLite，桌面/编辑器保留 JSON text_retrieval。 |
| 向量库 | 当前代码使用 Godot 本地 `token_hash_v1` embedding；Android 真机优先使用 native `sqlite-vec` 事件索引和 hnswlib 语义索引，桌面/不可用时切换到 Godot 本地事件向量槽和语义 HNSW 风格图；ObjectBox 不作为第一期默认实现。 |
| 向量索引状态 | 有结构化记忆且索引完成时显示 `vector_enabled = true`、`retrieval_mode = hybrid_vector`；native 后端可用且有对应向量时显示 `native_sqlite_vec_enabled = true` / `native_hnswlib_enabled = true`，不可用时显示 false 并给出 warning。 |
| 检索方式 | Hybrid Retrieval：Memory Query Router -> 多源召回 -> Candidate Pool Builder -> Policy Reranker Engine -> Memory Selection + Fusion。 |
| 记忆提取 | Memory Formation 只从已确认事件、已确认对话、已接受输出和会话结果提取；模型草稿不进入记忆。 |
| 记忆层级 | `persona_snapshot`、`working`、`relationship`、`semantic`、`episodic`、`reflection`。 |
| 记忆蒸馏 | Memory Distillation 从事件、反思和关系变化中提炼语义记忆。 |
| 记忆维护 | Memory Merge、Forgetting、索引重建和冲突处理归维护流程。 |
| 默认记忆上下文预算 | 2048 estimated tokens。 |
| 记忆上下文硬上限 | 4096 estimated tokens。 |
| 默认最终记忆条目数 | 最多 24 条，其中普通任务建议 18 条以内。 |
| 普通 UI | 机器人配置页只展示记忆概况和进入记忆页入口，不用弹窗承载完整记忆。 |
| 记忆页面 | 独立机器人记忆页展示分层记忆、健康状态、维护状态、索引状态和只读报告。 |
| 调试 UI | 机器人记忆页中的开发视图展示 query、召回、score、裁剪、写入和维护报告。 |

## 向量库选择

第一版采用“双索引抽象”。Android 真机优先走 native sqlite-vec / hnswlib，桌面和 native 不可用时走同接口的 Godot 本地索引：

```text
episodic/event memory
  -> memory_records 权威记录
  -> Android：native sqlite-vec 事件向量索引
  -> text_retrieval：Godot 本地事件向量槽

semantic memory
  -> memory_records 保存语义记录和元数据
  -> Android：native hnswlib HNSW 语义向量索引
  -> text_retrieval：Godot 本地 HNSW 风格语义图
```

ObjectBox 不作为第一期默认实现。

原因：

- 项目当前 Android 记忆和模型配置已经使用 SQLite。
- Godot bridge 当前已经围绕 Android native 插件暴露 SQLite 能力。
- 事件记忆数量增长快、过滤条件多，适合留在结构化权威存储中，并用事件向量索引做召回。
- 语义记忆来自蒸馏和合并，数量相对少但需要高质量近邻召回，适合用 HNSW 类索引。
- SQLite 仍保存权威元数据、可见性、证据、报告和索引版本。

约定：

- 文档和接口层使用 `Memory Query Router`、`EpisodicVectorIndex`、`SemanticHnswIndex`、`Candidate Pool Builder`、`Policy Reranker Engine` 和 `Memory Selection + Fusion` 这些内部抽象。
- 外部业务只看到 `AgentMemoryService`，不感知 sqlite-vec 或 hnswlib。
- `memory_records` 是权威数据，本地向量槽、语义图、sqlite-vec 和 hnswlib 都只是可重建索引。
- native hnswlib 索引文件只保存向量图和内部向量 ID，元数据仍以 SQLite / `memory_records` 为准。
- 如果向量索引不可用，切换到 SQLite FTS / token index 或 Godot 文本 text_retrieval。
- ObjectBox 只作为后续替代方案，不进入第一版实现基线。

## 内部引擎分工

```text
MemoryFormation
  -> 从已确认事实形成分层记忆候选

MemoryRecordStore
  -> SQLite 权威存储 memory_records / relationship state / reports

Memory Query Router
  -> 判断检索意图
  -> 提取 scope / entity / goal / risk / budget
  -> 生成 Query Plan

EpisodicVectorIndex
  -> sqlite-vec
  -> 事件记忆向量召回

SemanticHnswIndex
  -> hnswlib HNSW
  -> 蒸馏后的语义记忆召回

MemoryDistillation
  -> 从事件、反思、关系变化中提炼语义记忆

HybridRetrieval
  -> profile / working / relationship 结构化直取
  -> semantic HNSW + episodic sqlite-vec + reflection + text text_retrieval

Candidate Pool Builder
  -> 统一候选格式
  -> bot_id / scope / visibility / status 硬过滤
  -> 去重和证据合并

Policy Reranker Engine
  -> 统一打分、策略排序和解释
  -> Policy Reranker Engine

Memory Selection + Fusion
  -> 分层选择、token 预算裁剪、相似片段融合和上下文输出

MemoryMerge / Forgetting
  -> 合并、归档、衰减、删除和冲突处理
```

## Embedding 决策

embedding 生成器不绑定具体模型供应商。

默认约定：

- embedding 由记忆模块内部的 `EmbeddingProvider` 生成。
- `dimension` 从实际 provider 返回，不在跨模块契约里写死。
- 每条向量必须记录 `provider`、`model`、`dimension`、`content_hash`、`embedding_version`。
- `embedding_version` 变化时重建索引，不重写原始记忆。
- embedding 生成失败时，记忆仍写入结构化存储，并标记 `embedding_pending` 或 `embedding_failed`。

第一版当前状态：

- 已接入 Godot 本地 `token_hash_v1` embedding，作为开发期和单机运行期的可用向量实现。
- 有可检索结构化记忆且本地索引完成时，检索模式是 `hybrid_vector`。
- 没有可索引记录、记录待索引、索引失败或 query 为空时，检索模式可以切换为 `text_retrieval` 或 `none`，并写入 warning。
- native sqlite-vec 可用但 native hnswlib 不可用时，事件召回继续工作，语义召回切换为本地 HNSW 图或文本 text_retrieval。
- native hnswlib 可用但 native sqlite-vec 不可用时，语义召回继续工作，事件召回切换为本地事件向量槽或文本 text_retrieval。

## 记忆层级

### persona_snapshot

人格快照不是普通记忆记录主层，而是机器人档案、人设模板和长期稳定特征合成后的上下文块。

用途：

- 机器人是谁。
- 表达风格。
- 长期倾向。
- 初始人设。

限制：

- 不保存具体业务权威状态。
- 不能因为一次会话直接重写人格。
- 可以被长期语义和反思逐渐影响，但需要维护流程确认。

### working

当前会话工作记忆。

包含：

- 当前目标。
- 短期计划。
- 临时判断。
- 待验证问题。
- 当前表达状态。

生命周期：

- 默认只在当前会话有效。
- 会话结束后清理、归档或转成反思候选。
- 不直接进入长期人格。

### relationship

与实体相关的关系记忆。

包含：

- 信任。
- 亲近。
- 风险。
- 合作或冲突倾向。
- 偏好和互动习惯。

检索方式：

- 优先按 `target_entity_id` 直取。
- 可附带少量证据事件。
- 不依赖纯向量相似度决定是否返回。

### semantic

长期语义经验。

包含：

- 多次事件提炼出的稳定经验。
- 长期策略偏好。
- 对任务模式的抽象认知。

写入限制：

- 默认来自 Memory Distillation 和维护流程。
- 单次事件不能轻易提升为 active semantic memory。
- 需要证据、置信度和重要性。

索引：

- 语义记忆进入 `SemanticHnswIndex`。
- hnswlib 索引只保存向量，语义文本、证据和可见性仍在 SQLite。

### episodic

具体事件记忆。

包含：

- 某次对话。
- 某个已确认行动。
- 某个外部反馈。
- 某个流程结果。

写入限制：

- 必须有明确来源。
- 低价值流水事件可以只保留近期，不进入长期。
- 重复事件要合并或跳过。

索引：

- 事件记忆进入 `EpisodicVectorIndex`。
- Android 真机优先使用 native sqlite-vec 做事件召回；桌面或 native 不可用时使用 Godot 本地事件向量槽。

### reflection

反思记忆。

包含：

- 判断错误。
- 成功经验。
- 策略失败原因。
- 下次应注意事项。

写入限制：

- 通常在会话结束或关键阶段维护时生成。
- 必须引用已确认事件或结果。
- 不保存原始推理链。

## 检索默认参数

### 输入

默认检索输入：

| 字段 | 默认 |
| --- | --- |
| `include_types` | `working`、`relationship`、`semantic`、`episodic`、`reflection` |
| `max_token_budget` | 2048 |
| `hard_token_limit` | 4096 |
| `raw_vector_top_k_per_query` | 24 |
| `raw_text_top_k_per_query` | 24 |
| `raw_semantic_hnsw_top_k_per_query` | 24 |
| `raw_episodic_vec_top_k_per_query` | 24 |
| `rerank_top_k` | 32 |
| `final_max_items` | 24 |

### 输出条目上限

普通任务默认：

| 上下文块 | 默认上限 |
| --- | --- |
| `persona_snapshot` | 1 块 |
| `working_memory` | 6 条 |
| `relationship_context` | 6 个目标，每个目标最多 2 条证据 |
| `semantic_context` | 6 条 |
| `episodic_context` | 6 条 |
| `reflection_context` | 4 条 |
| 总记忆记录 | 最多 24 条，建议普通任务控制在 18 条以内 |

维护任务默认：

| 上下文块 | 默认上限 |
| --- | --- |
| `working_memory` | 12 条 |
| `relationship_context` | 12 个目标 |
| `semantic_context` | 12 条 |
| `episodic_context` | 24 条 |
| `reflection_context` | 12 条 |
| 总记忆记录 | 最多 64 条 |

### 单条内容长度

第一版以字符数做硬保护，token 估算作为预算报告。

| 类型 | 单条最大字符数 |
| --- | --- |
| `persona_snapshot` | 600 |
| `working` | 240 |
| `relationship` | 220 |
| `semantic` | 260 |
| `episodic` | 300 |
| `reflection` | 260 |

超出时先结构化压缩，再截断。截断必须在调试报告中记录。

### Token 预算分配

默认 `max_token_budget = 2048` 时：

| 块 | 预算 |
| --- | --- |
| `persona_snapshot` | 300 |
| `working_memory` | 350 |
| `relationship_context` | 400 |
| `semantic_context` | 400 |
| `episodic_context` | 350 |
| `reflection_context` | 200 |
| `warnings/metadata` | 48 |

规则：

- 预算不足时，优先保留 `persona_snapshot`、`working`、`relationship`。
- `episodic` 和 `reflection` 优先被裁剪。
- `semantic` 只保留高相关、高置信、高重要性的条目。
- 调试报告必须记录裁剪数量和原因。

## Policy Reranker 默认权重

`Policy Reranker Engine` 是候选排序核心。文档和代码统一使用这个名称。

普通任务默认：

```text
final_score =
  vector_similarity * 0.40
  + lexical_score * 0.10
  + importance * 0.20
  + confidence * 0.15
  + recency_score * 0.10
  + relationship_priority * 0.05
```

文本 text_retrieval 模式：

```text
final_score =
  lexical_score * 0.45
  + importance * 0.20
  + confidence * 0.15
  + recency_score * 0.10
  + relationship_priority * 0.10
```

Policy Reranker Engine 必须输出每条候选的解释字段：

| 字段 | 说明 |
| --- | --- |
| `retrieval_source` | `structured`、`sqlite_vec_event`、`hnsw_semantic`、`text_retrieval`。 |
| `vector_score` | 向量召回分，可为空。 |
| `lexical_score` | 文本召回分。 |
| `importance` | 重要性。 |
| `confidence` | 置信度。 |
| `recency_score` | 时效分。 |
| `final_score` | 最终分。 |
| `drop_reason` | 被裁剪或拒绝原因。 |

硬规则优先于分数：

- 当前机器人不可见的记录直接剔除。
- 当前任务目标实体的关系记忆优先保留。
- 工作记忆优先保留。
- `candidate` 状态默认不进入普通任务上下文。
- 重复或高度相似记录只保留最高质量版本。

硬规则应在 Candidate Pool Builder 阶段完成，Reranker 不负责把不可见或错误 scope 的候选“降分通过”。

## 记忆提取默认规则

记忆提取只从已确认材料产生。

这个流程命名为 Memory Formation。

输入来源：

- `confirmed_events`
- `accepted_dialogues`
- `accepted_outputs`
- `outcome`
- `session_end_memory_update`
- 明确标记来源的人设模板

禁止来源：

- 模型草稿。
- 被拒绝输出。
- 未执行动作。
- UI 临时输入。
- 当前机器人不可见的信息。
- 原始推理过程全文。

### 单次提交提取上限

普通 `accepted_output` / `confirmed_event`：

| 层 | 上限 |
| --- | --- |
| `working_update` | 最多 4 个字段 |
| `episodic_events` | 最多 4 条 |
| `relationship_updates` | 最多 4 条 |
| `semantic_candidates` | 默认 0 条，除非调用方明确给出高价值候选 |
| `reflection_candidates` | 默认 0 条 |

`session_end`：

| 层 | 上限 |
| --- | --- |
| `working_update` | 最多 8 个字段，用于收尾归档 |
| `episodic_events` | 最多 16 条关键事件 |
| `relationship_updates` | 最多 12 条 |
| `semantic_candidates` | 最多 5 条 |
| `reflection_candidates` | 最多 5 条 |

维护流程可以继续合并、降权或拒绝这些候选。

## Memory Distillation

Memory Distillation 是从原始事件、反思和关系变化中提炼长期语义记忆的过程。

输入：

- 高价值 `episodic` 事件。
- 会话结束 `reflection` 候选。
- 多次出现的 `relationship` 变化。
- 关键 `outcome`。

输出：

- `semantic_candidates`
- 合并后的 `reflection`
- 关系趋势摘要

约束：

- 蒸馏结果必须保留证据引用。
- 蒸馏结果默认先是 `candidate`，通过维护确认后才变成 `active`。
- 蒸馏不能引入当前机器人不可见的信息。
- 蒸馏不能保存模型推理链。

## Memory Merge

Memory Merge 负责把重复、相似、冲突或可归纳的记忆合并。

合并对象：

- 重复事件。
- 相似语义经验。
- 多条关系证据。
- 多个反思候选。

合并后必须保留：

- 原始证据引用。
- 可见性。
- 置信度来源。
- 合并原因。
- 被合并记录 ID。

## Forgetting

Forgetting 不是简单删除，而是按价值降低记忆对上下文的影响。

默认策略：

- `decay`：降低重要性和召回权重。
- `archive`：归档，不进入普通检索。
- `merge`：合并进语义或反思。
- `delete`：仅用于隐私清理、损坏数据、重复垃圾或用户明确操作。

Forgetting 由维护流程执行，不能在普通检索时偷偷删除权威记忆。

## 最大输出约定

这里的“最大输出”指记忆模块对外返回的 `AgentMemoryContext`，不是模型最终生成文本。

默认：

- 普通推理任务：最多 2048 estimated tokens。
- 普通推理任务硬上限：4096 estimated tokens。
- 维护任务：最多 8192 estimated tokens，仅内部使用，不直接进入普通模型 prompt。
- 单次 `get_memory_context()` 默认最多返回 24 条记忆记录。
- 单次调试报告最多展示 100 条候选，超过只显示统计和前后截断样本。

AI 模型最终输出长度由模型管理模块和具体业务 AI 机器人玩家适配层控制，不由记忆模块控制。

## UI 呈现默认

详细页面结构见 [机器人记忆页面设计](memory-ui.md)。这里固定默认取舍。

机器人配置页：

- 展示记忆健康状态。
- 展示各层数量。
- 展示最近更新时间。
- 展示进入机器人记忆页的入口。
- 不使用弹窗展示完整记忆系统。
- 不展示向量维度、embedding 模型、score、内部 scope key。

机器人记忆页：

- 独立页面承载完整记忆展示。
- 展示 `overview`、`memory_layers`、`retrieval`、`updates`、`maintenance`、`indexes` 等页面区域。
- 普通用户默认看到概况和分层只读记忆。
- debug 构建或开发模式显示检索、更新、维护和索引报告。
- 页面默认只读；维护操作只能触发记忆模块流程，不允许直接编辑底层记忆记录。

开发调试视图：

- 展示 `retrieval_mode`。
- 展示 query。
- 展示召回候选、score、来源、可见性、裁剪原因。
- 展示 `memory_update_report`。
- 展示 `maintenance_report`。
- 展示 `vector_enabled`、`embedding_model`、`embedding_version`、事件向量数量、语义图节点/边数量。
- 展示 `native_sqlite_vec_enabled` 和 `native_hnswlib_enabled`；native 后端不可用或没有对应向量时必须为 false，并展示 warning/text_retrieval。

## 变更规则

- 默认参数调整需要更新本文。
- 跨模块字段变化需要同步 [跨模块契约](../../contracts/README.md)。
- 向量库实现替换不能影响机器人模块门面接口。
- 最大输出、单条长度、top_k 变更需要同步测试和调试面板。
