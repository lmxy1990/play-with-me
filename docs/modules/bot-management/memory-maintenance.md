# 记忆维护设计

更新时间：2026-05-15

本文描述记忆模块如何执行反思、合并、压缩、衰减、遗忘、冲突处理和索引维护。维护流程决定机器人是否能长期稳定成长，不能简单等同于“摘要压缩”。

## 目标定位

记忆维护负责让记忆系统长期可用。

它负责：

- 会话结束后的工作记忆清理。
- 从事件和结果中生成反思候选。
- 通过 Memory Distillation 把多次事件、反思和关系变化合并成长期语义经验。
- 更新关系记忆的长期趋势。
- 通过 Forgetting 衰减、归档或删除低价值既有记忆。
- 通过 Memory Merge 合并重复或相似记忆。
- 标记冲突记忆并保留证据。
- 维护 sqlite-vec 事件索引、hnswlib 语义索引和 schema 校验。

它不负责：

- 决定业务胜负或业务状态。
- 生成最终游戏复盘权威数据。
- 读取模型草稿。
- 直接把隐藏信息写入当时的工作记忆。

## 维护入口

内部服务接口：

```text
maintain_memory(request) -> MemoryMaintenanceResult
```

核心参数：

| 字段 | 说明 |
| --- | --- |
| `bot_id` | 当前机器人。 |
| `scope` | 当前维护范围。 |
| `maintenance_type` | `session_end`、`startup`、`manual`、`storage_pressure`、`before_context_build`。 |
| `session_end_memory_update` | 会话结束时的分层更新材料。 |
| `options` | 维护强度、预算、是否允许重建索引等。 |

## 维护触发

| 触发 | 说明 | 强度 |
| --- | --- | --- |
| `session_end` | 会话结束，最适合做反思和关系更新。 | 中到高 |
| `startup` | 应用启动，检查 schema、索引和失败任务。 | 低 |
| `manual` | 开发或用户手动触发。 | 可配置 |
| `storage_pressure` | 存储空间紧张。 | 中 |
| `before_context_build` | 构建上下文前发现记忆过大。 | 低 |

## 会话结束维护

```text
session_end
  -> commit session_end_memory_update
  -> MemoryFormation: form confirmed memory candidates
  -> collect key working memory
  -> collect high-value episodic memory
  -> generate reflection candidates
  -> MemoryDistillation: distill semantic candidates
  -> update relationship trends
  -> MemoryMerge: merge duplicate/conflicting candidates
  -> Forgetting: decay/archive low-value memories
  -> clear or archive working memory
  -> enqueue sqlite-vec and hnswlib index jobs
  -> write maintenance report
```

会话结束不是把所有内容都写入长期记忆，而是筛选：

- 哪些事实必须保留。
- 哪些只是当时的临时判断。
- 哪些关系变化有长期价值。
- 哪些经验需要以后召回。
- 哪些信息只能在结束后以 `post_session_reveal` 来源保留。

## Memory Formation

Memory Formation 负责把已确认材料转成分层记忆候选。

输入：

- 已确认事件。
- 已接受输出。
- 已确认对话。
- 会话结果。
- 明确来源的人设模板。

输出：

- `working_update`
- `episodic_events`
- `relationship_updates`
- `semantic_candidates`
- `reflection_candidates`

约束：

- 只能使用当前机器人可见信息。
- 模型草稿、被拒绝输出、未执行动作不得进入。
- 形成的是候选，不是强制写库指令。

## 反思生成

反思记忆应该回答：

- 这次哪里判断对了？
- 哪里判断错了？
- 哪个策略有效？
- 哪个策略造成了损失？
- 下次遇到类似任务时应该优先注意什么？

反思输入：

- 已确认事件。
- 已接受输出。
- 会话结果。
- 高价值工作记忆。
- 关键关系变化。

反思约束：

- 反思必须引用证据。
- 反思不能包含当时机器人不可见的信息，除非标记为 `post_session_reveal`。
- 反思不能保存完整推理链。
- 反思候选可以先 `candidate`，后续再合并成语义经验。

## Memory Distillation

Memory Distillation 负责从事件、反思和关系变化中提炼长期语义记忆。

输入：

- 高价值 `episodic` 事件。
- 关键 `reflection` 候选。
- 多次重复出现的关系变化。
- 会话结果和阶段结果。

输出：

- `semantic_candidates`
- 可合并的反思经验。
- 关系趋势摘要。

约束：

- 蒸馏结果必须保留证据引用。
- 蒸馏结果默认先进入 `candidate` 状态。
- 只有通过维护校验、置信度和重要性阈值后，才能成为 `active semantic memory`。
- 蒸馏不能引入当时机器人不可见的信息。
- 蒸馏不能保存原始推理链。

## 语义合并

语义记忆来自多次事件、关系变化或反思候选。

合并条件：

- 多条事件支持同一经验。
- 反思候选多次重复出现。
- 置信度足够高。
- 对未来任务有可复用价值。

不应合并：

- 单次低置信事件。
- 只是情绪化判断的内容。
- 没有证据的自我设定。
- 与已有高置信记忆冲突但未解决的内容。

## 关系维护

关系记忆应该是演化状态，不是一次性标签。

维护内容：

- 根据关键事件更新信任、亲近、风险、偏好。
- 给关系变化保留证据。
- 对近期事件加更高权重。
- 对长期未互动关系进行轻度衰减。
- 遇到冲突证据时保留冲突，不直接覆盖。

示例：

```text
target_id = player_3
trust +0.12 because confirmed cooperation in session result
risk +0.20 because repeated deception evidence
confidence = 0.78
evidence = [event_123, event_139]
```

## Forgetting

遗忘不是直接删除一切既有记忆，而是降低低价值记忆对上下文的影响。

衰减因素：

- 时间过久。
- 最近很少被召回。
- 重要性低。
- 置信度低。
- 与当前人格或长期经验冲突。
- 重复度高。

处理方式：

| 策略 | 说明 |
| --- | --- |
| `decay` | 降低重要性或召回权重。 |
| `archive` | 归档，不进入普通检索。 |
| `merge` | 合并到更高层语义或反思。 |
| `delete` | 删除明确无价值或用户要求清理的数据。 |

长期记忆不建议频繁硬删除，除非是隐私清理、损坏数据、重复垃圾或用户明确操作。

Forgetting 只在维护流程执行，不在普通检索中静默删除权威记忆。普通检索只能裁剪上下文，不能改变存储状态。

## 冲突处理

机器人可能出现互相冲突的记忆。

冲突来源：

- 不同事件得出不同结论。
- 结束后公开信息推翻当时判断。
- 人设模板与长期行为经验冲突。
- 低置信候选误入长期记忆。

处理策略：

- 不直接覆盖高置信既有记忆。
- 新记忆标记 `conflicts_with`。
- 根据证据、时间、置信度和来源重新计算权重。
- 在上下文中只返回当前最可信结论，并可附带 warning。
- 维护报告记录冲突处理过程。

## Memory Merge

Memory Merge 负责把重复、相似、冲突或可归纳的记忆合并。

合并对象：

- 重复事件。
- 相似语义经验。
- 多条关系证据。
- 多个反思候选。

合并结果必须保留：

- 原始证据引用。
- 可见性。
- 置信度来源。
- 合并原因。
- 被合并记录 ID。

## 压缩策略

压缩要保留结构，不应只生成一段自然语言摘要。

压缩目标：

- 低价值事件压缩为阶段性事件概览。
- 多条关系证据压缩成关系趋势。
- 多个反思候选合并为稳定经验。
- 工作记忆结束后归档关键点。

压缩结果应仍然带：

- 来源。
- 证据引用。
- 可见性。
- 置信度。
- 重要性。
- schema 版本。

## 向量索引维护

向量索引是可重建索引，不是权威数据。

维护任务：

- 为 `embedding_pending` 记录生成 embedding。
- 为 `embedding_failed` 记录再次发起。
- `embedding_version` 变化时批量重建。
- 为事件记忆维护 sqlite-vec 索引。
- 为语义记忆维护 hnswlib HNSW 索引。
- 发现索引缺失时补建。
- 发现孤立向量时清理。

原则：

- 原始 `memory_records` 是权威数据。
- 向量索引损坏时可以删除并重建。
- 索引重建失败不删除原始记忆。
- 检索层必须能切换到文本检索。
- hnswlib 索引 label 必须能映射回 SQLite 中的 `memory_id`。

## 维护报告

```gdscript
{
    "bot_id": "",
    "scope": {},
    "maintenance_type": "session_end",
    "generated_reflections": [],
    "promoted_semantic_memories": [],
    "relationship_changes": [],
    "merged_memories": [],
    "decayed_memories": [],
    "archived_memories": [],
    "deleted_memories": [],
    "embedding_jobs": [],
    "sqlite_vec_jobs": [],
    "hnsw_index_jobs": [],
    "conflicts": [],
    "warnings": []
}
```

报告用途：

- 机器人配置页显示记忆健康概况。
- 开发调试面板查看为什么某条记忆被合并、衰减或拒绝。
- 后续失败再次发起和 schema 校验排查。

## 失败处理

| 场景 | 策略 |
| --- | --- |
| 反思生成失败 | 保留原始事件，下次维护再次发起。 |
| 语义合并失败 | 保留候选，不提升为长期语义。 |
| 关系维护失败 | 保留事件证据，不更新聚合关系。 |
| 压缩失败 | 不删除原始记忆。 |
| 索引维护失败 | 切换文本检索并报告 warning。 |
| schema 不匹配 | 丢弃不符合当前结构的数据，进入只读或阻断写入。 |

## 开发约定

- 维护流程不能静默丢失记忆。
- 会话结束维护可以异步或分阶段执行，不能阻塞关键业务流程太久。
- 维护结果必须可解释。
- 长期语义记忆必须来自证据、反思或多次事件合并。
- 工作记忆清理前要决定是否归档关键内容。
- 可见性规则在维护阶段仍然生效。
