# 记忆更新设计

更新时间：2026-05-15

本文描述记忆模块如何接收外部已确认事实，并把它们更新到工作记忆、事件记忆、关系记忆、语义记忆和反思候选中。记忆更新不是“写摘要”，而是对多层记忆的受控写入、合并、降权和拒绝。

## 目标定位

记忆更新只处理“当前机器人可以记住什么”。其中从已确认材料形成分层候选的过程称为 Memory Formation。

它负责：

- 校验 `memory_update` 的结构和可见性。
- 判断哪些内容可写入工作记忆。
- 判断哪些内容可成为事件记忆。
- 判断哪些内容会影响关系记忆。
- 接收语义和反思候选，但不盲目长期化。
- 记录写入、跳过、降权、合并和拒绝原因。

它不负责：

- 解析具体业务规则。
- 判断某个业务动作是否合法。
- 写入模型草稿。
- 把未确认 UI 输入变成记忆。
- 把推理过程原文写入长期记忆。

## 更新入口

内部服务接口：

```text
update_memory(request) -> MemoryUpdateResult
```

`MemoryUpdateRequest` 核心字段：

| 字段 | 说明 |
| --- | --- |
| `bot_id` | 当前机器人。 |
| `scope` | 当前业务域、会话和实例范围。 |
| `events` | 已确认事件。 |
| `dialogues` | 已确认对话。 |
| `accepted_outputs` | 已被业务接受的机器人输出。 |
| `memory_update` | 分层记忆更新载荷。 |
| `outcome` | 阶段、任务或会话结果。 |
| `update_reason` | `accepted_output`、`confirmed_event`、`session_end` 等。 |

## memory_update 结构

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

约定：

- `memory_update` 是更新材料，不是写库指令。
- 调用方可以按层提交候选，但最终写入哪一层由记忆模块决定。
- 没有证据的长期语义候选默认降权或暂存。
- 当前机器人不可见的内容必须拒绝。

默认提取层级、单次提交上限和最大输出见 [记忆系统默认决策](memory-defaults.md)。如果本文描述与默认决策冲突，以默认决策为当前实现基线。

## 更新流程

```text
MemoryUpdateRequest
  -> validate_request()
  -> validate_visibility()
  -> normalize_evidence()
  -> MemoryFormation.extract_update_candidates()
  -> apply_working_update()
  -> write_episodic_events()
  -> update_relationship_state()
  -> stage_semantic_candidates()
  -> stage_reflection_candidates()
  -> merge_or_dedupe()
  -> refresh local vector indexes / enqueue native index jobs
  -> write update report
```

默认上限：

- 普通 `accepted_output` / `confirmed_event`：`working_update` 最多 4 个字段，`episodic_events` 最多 4 条，`relationship_updates` 最多 4 条，默认不产生 `semantic_candidates` 和 `reflection_candidates`。
- `session_end`：`episodic_events` 最多 16 条，`relationship_updates` 最多 12 条，`semantic_candidates` 最多 5 条，`reflection_candidates` 最多 5 条。

## 可写入来源

允许写入：

- 外部业务确认发生的事件。
- 已公开或当前机器人私有可见的对话。
- 已被业务接受的机器人输出。
- 会话结束后的公开结果。
- 明确标记为设定来源的人格模板和背景。
- 维护流程生成并通过校验的反思和长期经验。

禁止写入：

- 模型草稿。
- 被拒绝输出。
- 业务未执行的候选动作。
- UI 临时输入。
- 当前机器人不可见的隐藏事实。
- 其它机器人或玩家的私有信息。
- 原始推理过程全文。

## 分层写入策略

### working_update

写入当前会话工作记忆。

适合内容：

- 当前目标。
- 短期计划。
- 临时判断。
- 待验证假设。
- 当前情绪或表达倾向。

约束：

- 工作记忆默认不跨会话长期保留。
- 工作记忆结束后需要清理、归档或转成反思候选。
- 工作记忆不能直接变成人格。

### episodic_events

写入具体事件记忆。

适合内容：

- 发生了什么。
- 谁参与。
- 机器人做了什么。
- 对方如何回应。
- 最终结果是什么。

字段建议：

| 字段 | 说明 |
| --- | --- |
| `event_id` | 外部事件 ID，可为空。 |
| `time` | 发生时间。 |
| `actor_ids` | 参与主体。 |
| `content` | 事件描述。 |
| `outcome` | 结果。 |
| `visibility` | 可见性。 |
| `importance` | 重要性提示。 |
| `confidence` | 置信度提示。 |

约束：

- 事件记忆必须有明确来源。
- 重复事件应合并或跳过。
- 低价值流水事件可以只保留在工作记忆或近期缓存。

### relationship_updates

更新关系记忆。

适合内容：

- 信任变化。
- 偏好变化。
- 合作、冲突、欺骗、帮助等互动结果。
- 对特定实体的长期倾向。

字段建议：

| 字段 | 说明 |
| --- | --- |
| `target_id` | 关系对象。 |
| `target_type` | 用户、角色、机器人或实体。 |
| `delta` | 关系变化。 |
| `reason` | 变化原因。 |
| `evidence` | 支撑事件引用。 |
| `confidence` | 置信度。 |

约束：

- 关系变化不能只由一次低置信事件永久决定。
- 高影响关系变化需要证据。
- 关系记忆应保留演化轨迹，不只保存最新结论。

### semantic_candidates

语义候选是长期经验候选。

适合内容：

- 多次事件提炼出的稳定经验。
- 任务策略上的长期偏好。
- 对环境规律的抽象认知。

约束：

- 默认先作为 `candidate`。
- 通常由维护流程合并、确认后才变成 `active`。
- 单次事件直接变成长久经验要非常谨慎。

### reflection_candidates

反思候选通常在关键阶段或会话结束后写入。

适合内容：

- 哪个判断错了。
- 哪个策略成功了。
- 哪个风险没有提前识别。
- 下次遇到类似情况要注意什么。

约束：

- 反思不能伪造未发生事实。
- 反思必须引用已确认事件或结果。
- 反思可以影响未来策略，但不替代事件记忆。

## 重要性和置信度

调用方可以给 hints，最终值由记忆模块决定。

重要性参考：

| 值域 | 含义 |
| --- | --- |
| `0.0 - 0.3` | 低价值流水信息。 |
| `0.3 - 0.6` | 有局部价值的事件。 |
| `0.6 - 0.8` | 影响当前或后续任务的重要事件。 |
| `0.8 - 1.0` | 人格、关系或长期策略强相关事件。 |

置信度参考：

| 值域 | 含义 |
| --- | --- |
| `0.0 - 0.4` | 未充分确认，只可作为候选。 |
| `0.4 - 0.7` | 有一定证据，需要保守使用。 |
| `0.7 - 0.9` | 已确认，正常写入。 |
| `0.9 - 1.0` | 权威事实或明确结果。 |

## 防污染

记忆更新的硬规则：

- 当前机器人不可见的信息不得写入。
- 隐藏身份、秘密状态、其它主体私有信息不得提前写入。
- 结束后公开的信息必须标记 `post_session_reveal`。
- 模型推理过程不得原样写入。
- 被业务拒绝的输出不得写入。
- 业务适配层必须先脱敏，记忆模块再做防线式校验。

## 去重和合并

写入前应检查：

- 是否与已有事件重复。
- 是否与现有关系状态冲突。
- 是否是低价值重复对话。
- 是否应该更新已有记忆而不是新增。

合并策略：

- 同一事件多次提交，只更新证据和置信度。
- 同一关系对象多次变化，保留趋势和关键证据。
- 语义候选相似时合并为更稳定表达。
- 冲突记忆不直接覆盖，标记冲突并等待维护处理。

## 更新报告

每次更新建议生成报告。

```gdscript
{
    "bot_id": "",
    "scope": {},
    "update_reason": "",
    "updated_layers": [],
    "written": [],
    "skipped": [],
    "merged": [],
    "downgraded": [],
    "rejected": [],
    "embedding_jobs": [],
    "warnings": []
}
```

跳过或拒绝原因建议标准化：

| 原因 | 说明 |
| --- | --- |
| `not_visible_to_bot` | 当前机器人不可见。 |
| `unconfirmed_output` | 输出未被业务确认。 |
| `duplicate_event` | 重复事件。 |
| `low_importance` | 重要性过低。 |
| `missing_evidence` | 缺少证据。 |
| `schema_invalid` | 结构不合法。 |
| `privacy_risk` | 可见性或隐私风险。 |

## 与向量索引的关系

记忆写入成功后，不要求同步阻塞生成 embedding。

推荐策略：

```text
write memory_record
  -> mark embedding_status = pending
  -> enqueue embedding job
  -> episodic memory enters native sqlite-vec on Android or local event vector slot text_retrieval
  -> semantic/reflection memory enters native hnswlib on Android or local HNSW-style graph text_retrieval
```

如果 embedding 失败：

- 原始记忆仍然存在。
- 检索可以使用文本 text_retrieval。
- 调试报告标记 `embedding_pending` 或 `embedding_failed`。
- 本地索引或 native sqlite-vec / hnswlib 任一索引失败，都不能删除原始 `memory_records`。

## 开发约定

- `update_memory()` 不承诺照单全收。
- 长期记忆必须能解释来源。
- 工作记忆、事件记忆、关系记忆、语义记忆、反思记忆不能混写。
- 更新失败不撤销外部业务结果，但必须返回可记录的错误或 warning。
- 对外 UI 不提供直接编辑底层记忆记录的能力，除非后续增加明确的维护工具。
