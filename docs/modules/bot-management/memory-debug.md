# 记忆调试设计

更新时间：2026-05-15

本文描述机器人记忆页里的开发调试视图如何呈现。页面形态、配置页入口和分层记忆浏览以 [机器人记忆页面设计](memory-ui.md) 为准；本文重点固定调试报告需要回答的问题和字段。

记忆系统不是机器人配置里的附属弹窗。记忆决定机器人模块成败，调试信息必须能解释检索、更新、维护和索引为什么这样工作。

## 调试分层

调试呈现跟随独立机器人记忆页。

```text
机器人配置页
  -> 普通只读概况
  -> 进入机器人记忆页
  -> 不用弹窗承载复杂记忆视图

机器人记忆页
  -> 分层记忆浏览
  -> 记忆健康状态
  -> 维护状态
  -> 不暴露数据库表
  -> 不暴露向量索引细节

机器人记忆页的开发调试视图
  -> 检索 query
  -> 召回记录和 score
  -> 记忆更新报告
  -> 维护报告
  -> 切换和可见性 warning
```

普通配置页服务“管理机器人基础档案”，机器人记忆页服务“查看和理解机器人的记忆系统”，开发调试视图服务“定位记忆系统问题”。

## 机器人配置页

机器人配置页只展示机器人自己的档案和记忆概况，并提供进入独立记忆页的入口。它不承载完整记忆系统，不使用弹窗展示复杂记忆。

建议信息：

- 机器人名称。
- 头像。
- 默认模型。
- 默认声音。
- 人设。
- 记忆健康状态。
- 最近记忆更新时间。
- 各层记忆数量。
- 最近几条只读记忆摘要。
- 进入记忆页入口。

不展示：

- 向量维度。
- embedding 模型。
- 向量 score。
- 数据库表名。
- 内部 scope key。
- 未脱敏私有数据。

### 记忆概况卡片

建议字段：

| 字段 | 说明 |
| --- | --- |
| `memory_status` | `healthy`、`degraded`、`needs_maintenance`、`error`。 |
| `last_updated_at` | 最近更新。 |
| `working_count` | 工作记忆数量。 |
| `episodic_count` | 事件记忆数量。 |
| `relationship_count` | 关系记忆数量。 |
| `semantic_count` | 语义记忆数量。 |
| `reflection_count` | 反思记忆数量。 |
| `pending_embedding_count` | 待索引数量，普通页可显示为“待整理”。 |
| `warnings` | 简短提示。 |

### 进入记忆页

配置页中的记忆入口应跳转到独立页面，而不是打开弹窗。

入口建议：

- `查看记忆`
- `记忆系统`
- `调试记忆`，仅 debug 构建可见

## 机器人记忆页

机器人记忆页是完整页面，不是 Dialog、Popup 或临时浮层。它应支持返回机器人配置页，也可以从机器人列表、AI 机器人玩家详情或 debug 入口进入。

页面职责：

- 展示机器人记忆健康状态。
- 展示分层记忆。
- 展示记忆维护状态。
- 展示只读调试报告。
- 为后续维护操作预留入口。

页面不负责：

- 直接编辑底层记忆表。
- 绕过记忆模块写入记忆。
- 展示未脱敏私有内容。
- 展示数据库表名作为用户概念。

### 页面结构

建议使用页面内分区或 tabs：

| 区域 | 内容 |
| --- | --- |
| `overview` | 健康状态、最近更新、各层数量、索引状态摘要。 |
| `memory_layers` | 人设快照、工作记忆、关系记忆、事件记忆、语义记忆、反思记忆。 |
| `retrieval` | 最近一次 Hybrid Retrieval 报告，仅 debug 构建或开发模式显示。 |
| `updates` | 最近一次 Memory Formation / memory_update 写入报告。 |
| `maintenance` | Memory Distillation、Memory Merge、Forgetting 和索引维护报告。 |
| `indexes` | sqlite-vec、hnswlib、embedding 队列状态，普通用户可折叠为“待整理”。 |

### 分层记忆浏览

分层记忆浏览应只读。

建议分组：

- 人设和长期特征。
- 当前工作记忆。
- 关系记忆。
- 重要事件。
- 长期经验。
- 反思经验。

展示规则：

- 默认隐藏技术字段。
- 私有内容按当前用户权限脱敏。
- 只显示内容、来源、时间、重要性等级。
- 不提供直接编辑单条底层记忆。
- 如果需要清理记忆，后续单独设计“维护操作”，不要直接改表。

## 开发调试视图

开发调试视图是机器人记忆页的一部分，用于确认 RAG 是否可靠。它不应以弹窗承载，因为检索、更新、维护和索引状态需要横向对照。

建议入口：

- 机器人记忆页里的开发调试 tab。
- debug 构建中可见。
- release 默认隐藏或只显示健康摘要。

### 检索调试

展示最近一次 `get_memory_context()` 的报告。

字段：

| 字段 | 说明 |
| --- | --- |
| `retrieval_mode` | `hybrid_vector`、`text_retrieval`、`none`。 |
| `query_plan` | Memory Query Router 生成的来源、query、过滤条件和预算计划。 |
| `vector_sources` | sqlite-vec 事件索引和 hnswlib 语义索引是否启用。 |
| `queries` | 本次生成的检索 query。 |
| `filters` | 结构化过滤条件。 |
| `candidate_counts` | 各层候选数量。 |
| `candidate_pool_report` | 候选池构建、硬过滤、去重和证据合并报告。 |
| `rerank_report` | Policy Reranker Engine 的 score 和解释报告。 |
| `fusion_report` | Memory Selection + Fusion 的分层选择和融合报告。 |
| `selected_items` | 被选入上下文的记忆。 |
| `dropped_items` | 被裁剪或拒绝的记忆。 |
| `budget_report` | token 预算报告。 |
| `warnings` | 切换和风险提示。 |

每条召回记录建议显示：

- 记忆类型。
- 来源。
- 可见性。
- 最终 score。
- 向量 score，如果有。
- 重要性。
- 置信度。
- 是否进入上下文。
- 裁剪或拒绝原因。

### 更新调试

展示最近一次 `update_memory()` 或 `commit_bot_result()` 的报告。

字段：

| 字段 | 说明 |
| --- | --- |
| `update_reason` | 更新原因。 |
| `updated_layers` | 实际更新层。 |
| `written` | 写入记录。 |
| `skipped` | 跳过记录。 |
| `merged` | 合并记录。 |
| `downgraded` | 切换记录。 |
| `rejected` | 拒绝记录。 |
| `embedding_jobs` | 后续索引任务。 |
| `warnings` | 风险提示。 |

重点要能回答：

- 为什么这条没有写进长期记忆？
- 为什么这条只进了工作记忆？
- 为什么关系分数变了？
- 为什么某条被拒绝？
- 哪些内容等着生成 embedding？

### 维护调试

展示最近一次 `maintain_memory()` 的报告。

字段：

- 生成了哪些反思。
- 哪些候选提升为语义记忆。
- 哪些关系被更新。
- 哪些记忆被合并。
- 哪些记忆被衰减或归档。
- 哪些向量索引任务失败。
- 是否发生 schema 拒绝。

## 健康状态

建议把复杂内部状态折叠成简单健康状态。

| 状态 | 含义 |
| --- | --- |
| `healthy` | 存储、检索和维护正常。 |
| `degraded` | 可用但有切换，例如向量索引不可用。 |
| `needs_maintenance` | 需要整理、索引重建或清理。 |
| `read_only` | schema 校验失败或存储异常，只允许读取。 |
| `error` | 记忆系统不可用。 |

机器人配置页只显示状态和一句短提示。机器人记忆页显示分层概况。开发调试视图显示具体报告。

## 当前实现呈现

当前代码已经有 Android native sqlite-vec / hnswlib 向量索引，也保留 Godot 本地向量 text_retrieval。调试面板应明确区分“native 后端可用”“本地 text_retrieval 可用”和“文本 text_retrieval”：

```text
retrieval_mode = hybrid_vector 或 text_retrieval
vector_enabled = true 或 false
embedding_enabled = true 或 false
sqlite_vec_event_enabled = true 或 false
hnsw_semantic_enabled = true 或 false
native_sqlite_vec_enabled = true 或 false
native_hnswlib_enabled = true 或 false
vector_backend = godot_local_vector / godot_local_embedding_with_android_native_index
embedding_provider = godot_local
embedding_model = token_hash_v1
embedding_version = local-token-hash-v1
embedding_dimension = 128
```

这可以避免把 native 失败误判为正常，也避免把可运行的本地向量索引误判为纯文本 text_retrieval。

当前可展示：

- `persona_snapshot`
- `memory_records`
- 记忆分层数量
- 事件向量数量
- 语义图节点和边数量
- native 后端状态、warning 和可用索引名
- embedding 版本和待索引数量
- Hybrid Retrieval 召回结果、score 和裁剪报告
- 维护报告中的蒸馏、合并、归档和索引刷新结果

native 字段必须按 `index_status` 和 `native_backend_status` 实际返回展示；后端失败时显示 false 和 warning，本地向量状态同样按实际 `index_status` 展示。

## 脱敏规则

调试信息也要遵守可见性。

规则：

- 默认 `redact_private = true`。
- 私有内容只显示摘要或 hash。
- 不显示其它机器人私有记忆。
- 不显示当前用户无权查看的隐藏事实。
- `post_session_reveal` 内容要标明来源。

## 对外调试接口

机器人模块门面可提供只读调试接口：

```text
get_bot_debug_state(request) -> BotDebugStateResult
get_last_context_report(request) -> BotContextReportResult
get_last_memory_update_report(request) -> BotMemoryUpdateReportResult
get_last_maintenance_report(request) -> BotMaintenanceReportResult
```

这些接口不得修改记忆。

## 开发约定

- 普通配置页不要展示底层数据库和向量技术细节。
- 复杂记忆展示必须使用独立页面，不使用弹窗。
- 机器人配置页只保留记忆概况和进入记忆页的入口。
- 调试面板必须能定位检索、写入和维护问题。
- release 包可以禁用调试明细。
- 任何“向量未启用”的情况都要明确显示为 text_retrieval。
- 任何 native 后端不可用的情况都要显示 native 状态，不能把 Godot 本地向量伪装成 sqlite-vec 或 hnswlib。
- 记忆系统出现切换时，不要静默伪装成正常。
