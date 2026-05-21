# 机器人记忆页面设计

更新时间：2026-05-15

本文定义机器人记忆系统在 UI 中的正式承载方式。结论先定死：完整记忆展示不是弹窗、不是机器人配置页里的附属面板，而是一个独立页面。

记忆模块决定机器人模块的质量，页面需要能承载分层记忆、检索解释、更新报告、维护状态和索引状态。弹窗只能做轻量确认或短提示，不能承载完整记忆系统。

## 页面定位

```text
机器人配置页
  -> 管理机器人档案
  -> 展示记忆概况
  -> 进入机器人记忆页

机器人记忆页
  -> 查看机器人记忆系统
  -> 查看记忆健康和维护状态
  -> 查看只读调试报告
  -> 触发受控维护操作
```

机器人配置页关注“这个机器人是谁”。机器人记忆页关注“这个机器人记住了什么、为什么这样召回、记忆系统是否健康”。

## 硬性约定

- 完整记忆展示必须是页面，不使用 Dialog、Popup、临时浮层或头像编辑弹层承载。
- 机器人配置页只放记忆概况和入口。
- 记忆页默认只读，不直接编辑底层记忆记录。
- UI 不直接访问数据库表、JSON 文件、sqlite-vec 或 hnswlib。
- UI 只能调用机器人模块门面接口，由机器人模块转交记忆模块。
- 维护操作必须走记忆模块接口，不允许 UI 绕过 Memory Formation、Memory Merge 或 Forgetting。
- release 默认隐藏开发调试明细，最多展示健康摘要和维护提示。
- 向量索引可用时，页面显示 `retrieval_mode = hybrid_vector` 和 `vector_enabled = true`；native 后端状态用 `native_sqlite_vec_enabled`、`native_hnswlib_enabled` 单独展示。

## 入口

### 机器人配置页入口

机器人配置页的记忆区域只展示：

- 记忆健康状态。
- 最近更新时间。
- 各层记忆数量。
- 最近几条只读摘要。
- 进入 `机器人记忆页` 的按钮。

不在配置页展示：

- 完整记忆列表。
- 检索 query。
- score 和裁剪原因。
- embedding 维度。
- sqlite-vec / hnswlib 细节。
- 底层 scope key。

### 路由参数

页面入口建议携带：

| 参数 | 说明 |
| --- | --- |
| `bot_id` | 必填，当前机器人。 |
| `scope` | 可选，当前会话或业务范围。 |
| `initial_tab` | 可选，默认 `overview`。 |
| `debug` | 可选，是否进入开发视图。 |

## 页面布局

建议使用顶部标题 + 左侧分区导航或顶部 tabs。页面应能在横屏移动端展示，不依赖弹窗高度。

```text
Header
  -> 返回
  -> 机器人头像、名称、模型、声音
  -> 记忆健康状态
  -> 最近更新时间

Tabs / Sections
  1. overview
  2. memory_layers
  3. retrieval
  4. updates
  5. maintenance
  6. indexes
```

普通模式默认显示 `overview` 和 `memory_layers`。debug 构建或开发模式显示 `retrieval`、`updates`、`maintenance`、`indexes` 的详细字段。

## overview

概览区回答：这个机器人的记忆系统现在是否可用。

展示内容：

| 区域 | 内容 |
| --- | --- |
| 机器人摘要 | 名称、头像、人格是否设置、默认模型、默认声音。 |
| 记忆健康 | `healthy`、`degraded`、`needs_maintenance`、`read_only`、`error`。 |
| 层级数量 | `working`、`relationship`、`episodic`、`semantic`、`reflection` 数量。 |
| 最近活动 | 最近写入时间、最近检索时间、最近维护时间。 |
| 当前模式 | `hybrid_vector`、`text_retrieval`、`none`。 |
| 维护建议 | 是否需要整理、索引重建、结构重建或清理。 |

Android 真机 native 向量索引可用时，概览区应显示：

```text
retrieval_mode = hybrid_vector
vector_enabled = true
sqlite_vec_event_enabled = true
hnsw_semantic_enabled = true
native_sqlite_vec_enabled = true
native_hnswlib_enabled = true
embedding_enabled = true
```

桌面/编辑器或 native 后端不可用但 Godot 本地索引可用时，`retrieval_mode` 仍可为 `hybrid_vector`，但 `native_sqlite_vec_enabled` / `native_hnswlib_enabled` 必须为 false，并在 backend/warnings 中说明使用 text_retrieval。

如果索引不可用或待重建，则切换显示 `retrieval_mode = text_retrieval`、`vector_enabled = false`，并在 warning 中给出 `embedding_pending`、`embedding_stale` 或 `vector_unavailable_text_retrieval`。

## memory_layers

分层记忆区回答：这个机器人具体记住了什么。

### 人设快照

展示机器人当前人格、表达风格、长期稳定特征和初始模板来源。

约定：

- `persona_snapshot` 不是普通 `MemoryRecord.memory_type`。
- 不能因为一次会话直接改写人格。
- 人设为空时，展示“由记忆自进化”，不需要强制补人设。

### 工作记忆

展示当前会话或当前实例的短期状态。

建议字段：

- 当前目标。
- 当前计划。
- 待验证问题。
- 临时判断。
- 情绪或表达状态。
- 过期时间或所属会话。

工作记忆应明显标记为短期，不和长期记忆混在一起。

### 关系记忆

按对象分组展示关系状态。

建议字段：

- 对象名称或脱敏 ID。
- 信任、亲近、风险等聚合状态。
- 最近证据。
- 最近变化时间。

关系记忆优先按对象直取，不应让用户误以为完全由向量相似度决定。

### 事件记忆

按时间线展示已确认事件。

建议过滤：

- 时间范围。
- 来源。
- 可见性。
- 重要性。
- 当前会话 / 历史会话。

事件记忆必须有证据来源。低价值流水事件可以归档或只保留近期，不应长期污染上下文。

### 语义记忆

展示长期经验、稳定偏好和抽象认知。

约定：

- 语义记忆通常来自 Memory Distillation 或 Memory Merge。
- 单次事件不能轻易成为 active 语义记忆。
- 每条语义记忆需要能追溯证据。

### 反思记忆

展示会话后或关键阶段后的反思。

内容包括：

- 判断错误。
- 成功经验。
- 策略失败原因。
- 下次注意事项。

反思记忆不得展示原始推理链，只展示已确认事件支持的结论。

## 记录展示格式

每条记忆记录建议展示：

| 字段 | 普通模式 | debug 模式 |
| --- | --- | --- |
| `content` | 显示 | 显示，可展开结构化 payload |
| `memory_type` | 显示为层级名称 | 显示原始枚举 |
| `source` | 显示为来源标签 | 显示原始来源 |
| `visibility` | 脱敏标签 | 原始可见性枚举，仍需权限过滤 |
| `importance` | 高/中/低 | 数值 |
| `confidence` | 高/中/低 | 数值 |
| `status` | 正常/候选/归档 | 原始状态 |
| `created_at` / `updated_at` | 显示 | 显示 |
| `evidence_count` | 显示 | 可展开证据引用 |
| `retrieval_source` | 不显示 | 显示 |
| `score` | 不显示 | 显示 |
| `drop_reason` | 不显示 | 显示 |

## retrieval

检索区回答：为什么这次上下文使用了这些记忆。

release 默认隐藏详细内容，debug 构建或开发模式显示。

展示内容：

- 最近一次 `get_memory_context()` 请求摘要。
- Memory Query Router 生成的 Query Plan。
- 生成的 query。
- 结构化过滤条件。
- Candidate Pool Builder 的硬过滤、去重和证据合并结果。
- sqlite-vec 事件召回状态。
- hnswlib 语义召回状态。
- 文本 text_retrieval 状态。
- 候选数量。
- Policy Reranker Engine 的 score 和解释。
- Memory Selection + Fusion 的 selected / dropped / fused。
- token budget 裁剪报告。
- warning 和切换原因。

这里显示的是报告，不是可编辑数据。

## updates

更新区回答：哪些已确认材料进入了记忆系统，哪些被跳过、合并、降权或拒绝。

展示最近一次或最近 N 次：

- `commit_reason`
- `update_reason`
- `memory_update` 分层统计。
- 写入记录数。
- 跳过记录数。
- 合并记录数。
- 降权记录数。
- 拒绝记录数。
- embedding 任务数。
- warning。

重点要能定位：

- 为什么某条没有进入长期记忆。
- 为什么某条只进入工作记忆。
- 为什么关系状态发生变化。
- 为什么某条被判定为污染风险。

## maintenance

维护区回答：记忆系统如何自我整理。

展示内容：

- 最近维护时间。
- 维护类型：`startup`、`session_end`、`manual`、`storage_pressure`、`before_context_build`。
- Memory Distillation 结果。
- Memory Merge 结果。
- Forgetting 结果。
- 工作记忆清理结果。
- schema 校验结果。
- 索引重建或失败再次发起结果。

可预留受控操作：

| 操作 | 说明 |
| --- | --- |
| `run_light_maintenance` | 轻量整理，适合启动或空闲时。 |
| `run_session_end_maintenance` | 会话结束整理。 |
| `rebuild_missing_embeddings` | 补建缺失 embedding。 |
| `rebuild_indexes` | 重建可重建索引，不删除权威记忆。 |

这些操作不能直接修改单条记忆，只能触发记忆模块维护流程。

## indexes

索引区回答：向量和 text_retrieval 是否可用。

普通模式只显示摘要：

- 当前是否启用向量。
- 是否有待索引内容。
- 是否需要重建。
- 是否处于 text_retrieval。

debug 模式显示：

| 字段 | 说明 |
| --- | --- |
| `vector_enabled` | 是否启用向量检索。 |
| `embedding_enabled` | 是否启用 embedding 生成。 |
| `sqlite_vec_event_enabled` | 事件记忆 sqlite-vec 是否可用。 |
| `hnsw_semantic_enabled` | 语义记忆 HNSW 是否可用。 |
| `embedding_provider` | 当前 embedding provider。 |
| `embedding_version` | 当前 embedding 版本。 |
| `pending_embedding_count` | 待生成 embedding 数量。 |
| `failed_embedding_count` | embedding 失败数量。 |
| `stale_index_count` | 过期索引数量。 |

## 页面数据接口

机器人记忆页需要通过机器人模块门面拿数据。建议增加或预留以下只读接口，具体字段见 [interfaces.md](interfaces.md)。

```text
get_bot_memory_overview(request) -> BotMemoryOverviewResult
list_bot_memory_records(request) -> BotMemoryRecordListResult
get_bot_memory_record_detail(request) -> BotMemoryRecordDetailResult
get_bot_memory_reports(request) -> BotMemoryReportsResult
preview_bot_memory_context(request) -> BotMemoryContextPreviewResult
request_bot_memory_maintenance(request) -> BotMaintenanceResult
```

当前代码已经落地机器人模块门面。UI 调用 `BotCapabilityFacade.get_bot_*` 接口；门面内部再转交 `MemoryManager` 的只读查询接口。

| 页面能力 | 机器人门面接口 | 记忆模块内部接口 | 当前状态 |
| --- | --- | --- | --- |
| 记忆概览 | `get_bot_memory_overview(request)` | `MemoryManager.get_memory_overview(request)` | 已落地。返回机器人摘要、健康状态、分层数量、索引状态、人设快照摘要和最近样本。 |
| 分层列表 | `list_bot_memory_records(request)` | `MemoryManager.list_memory_records(request)` | 已落地。只读取 `memory_records`，支持 `memory_type`、`status`、`subject_id`、`query`、分页和脱敏。 |
| 报告查看 | `get_bot_memory_reports(request)` | `MemoryManager.get_memory_reports(request)` | 已落地。返回最近一次上下文构建、记忆更新、维护和索引状态报告。 |
| 索引状态 | `get_bot_memory_index_status(request)` | `MemoryManager.get_memory_index_status(request)` | 已落地。显示本地向量、native 后端、embedding 队列、HNSW 图和 text_retrieval 状态。 |
| 单条详情 | `get_bot_memory_record_detail(request)` | `MemoryManager.load_state()` 只读查找 | 已落地。详情默认脱敏，可按请求返回 evidence 和 debug 字段。 |
| 上下文预览 | `preview_bot_memory_context(request)` | `MemoryManager.get_memory_context(request)` | 已落地。复用检索报告和 items。 |

接口边界：

- `get_bot_memory_overview()` 给配置页和记忆页头部使用。
- `list_bot_memory_records()` 给分层记忆列表使用。
- `get_bot_memory_record_detail()` 给页面内详情区域使用，不使用弹窗承载复杂内容。
- `get_bot_memory_reports()` 给检索、更新、维护和索引报告使用。
- `preview_bot_memory_context()` 仅 debug 或开发模式使用，用于模拟某次任务会召回哪些记忆。
- `request_bot_memory_maintenance()` 只触发受控维护，不提供直接改表。
- 内部页面接口以 `persona_snapshot` 和 `memory_records` 为主路径，不把开发期临时字段当作机器人记忆页的数据源。
- 当前 `get_memory_reports()` 返回最近一次内存报告，不是历史报告库；如果页面需要历史追踪，后续由维护/调试日志系统补充。

## 空状态和切换状态

页面必须明确区分：

| 状态 | 呈现 |
| --- | --- |
| 无记忆 | 机器人还没有可展示记忆。 |
| 只有工作记忆 | 当前会话已有短期状态，但长期记忆为空。 |
| text_retrieval | 当前使用文本 text_retrieval，向量未启用或不可用。 |
| degraded | 可用但部分索引、embedding 或报告异常。 |
| read_only | 存储或 schema 校验异常，只允许读取。 |
| error | 记忆系统不可用。 |

不能把 `text_retrieval` 伪装成完整向量检索完成。

## 与调试文档的关系

本文定义页面形态和用户可见结构。[记忆调试与呈现设计](memory-debug.md) 定义 debug 报告中要展示哪些检索、更新、维护和索引细节。
