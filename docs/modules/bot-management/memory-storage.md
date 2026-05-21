# 记忆存储设计

更新时间：2026-05-15

本文描述记忆模块的存储边界、当前实现状态和目标存储结构。记忆存储是机器人/RAG 的内部实现，外部业务模块、UI 和具体游戏房间模块不直接访问底层表、文件或向量索引。

## 当前实现状态

当前代码已经具备本地持久化、结构化记忆记录、本地 embedding、Android native sqlite-vec 事件索引和 hnswlib 语义索引。桌面/编辑器仍使用同接口的 Godot 本地向量实现作为 text_retrieval。

现状：

- 桌面/编辑器使用 `user://play_with_me_memory.json`。
- Android 真机优先使用 native SQLite 插件，数据库为 `ai_memory.sqlite`。
- 结构化主路径使用 `persona_snapshot` 和 `memory_records`。
- Godot 侧 `MemoryVectorIndex` 已提供本地 `token_hash_v1` embedding，维度为 128。
- 事件记忆进入事件向量索引；Android 真机优先使用插件端 `sqlite-vec`，其它环境使用本地事件向量槽。
- 语义/反思记忆进入语义近邻索引；Android 真机优先使用插件端 hnswlib，其他环境使用本地 HNSW 风格语义图。
- `MemoryManager.get_memory_context()` 使用结构化直取、native/Godot 向量召回和文本 text_retrieval 的 Hybrid Retrieval。
- Android bridge 保存完整 state，包括 `vector_index` 和 `semantic_hnsw_graph`，并提供 `memory_native_rebuild_indexes`、`memory_native_vector_search`。

因此，当前实现应视为“第一版可运行 native+text_retrieval 记忆系统”。它可以支撑机器人模块独立开发、调试和页面呈现；native 后端不可用时必须显式报告并切换，不允许伪装成 sqlite-vec/hnswlib。

## 目标定位

记忆存储层负责：

- 保存机器人的多层记忆。
- 保证不同机器人、会话、业务域之间隔离。
- 为检索层提供结构化过滤、全文召回和向量召回能力。
- 保存记忆更新、维护、结构拒绝和调试报告。
- 支持未来 schema 演进和索引重建。

记忆存储层不负责：

- 判断业务规则是否合法。
- 构建最终 prompt。
- 调用模型。
- 决定机器人最终输出。
- 向 UI 暴露数据库表结构。

## 存储抽象

目标上建议拆成三个内部接口。

```text
AgentMemoryService
  -> MemoryRecordStore
       -> 结构化记忆 CRUD
       -> 范围过滤
       -> 可见性过滤
       -> schema 校验
  -> MemoryVectorIndex
       -> embedding 写入
       -> 向量召回
       -> 索引重建
       -> 内部分为 EpisodicVectorIndex 和 SemanticHnswIndex
  -> MemoryReportStore
       -> 最近一次上下文报告
       -> 最近一次记忆更新报告
       -> 维护和结构拒绝报告
```

这些接口只对记忆模块内部开放。机器人模块只调用 `AgentMemoryService`，外部业务只调用机器人模块门面。

## 核心存储实体

### memory_records

`memory_records` 是目标主表，所有长期或可检索记忆都应归一到这张逻辑表。实际实现可以拆表，但模块语义按这个对象理解。

| 字段 | 说明 |
| --- | --- |
| `memory_id` | 记忆记录 ID。 |
| `bot_id` | 归属机器人 ID。 |
| `memory_type` | `working`、`episodic`、`semantic`、`relationship`、`reflection`。 |
| `scope_key` | 内部范围键，由机器人、业务域、会话、实例等字段派生。 |
| `domain_id` | 业务域 ID，只用于隔离和过滤。 |
| `session_id` | 会话 ID，可为空。 |
| `instance_id` | 运行实例 ID，可为空。 |
| `subject_id` | 关联对象 ID，例如用户、角色、机器人、实体、事件或主题。 |
| `subject_type` | `user`、`actor`、`bot`、`entity`、`topic`、`event` 等。 |
| `content` | 可进入上下文的记忆文本。 |
| `structured_payload_json` | 结构化记忆内容，例如关系分数、标签、状态。 |
| `visibility` | `public`、`self_private`、`observer_safe`、`post_session_reveal`。 |
| `source` | `persona_seed`、`confirmed_event`、`accepted_output`、`reflection`、`merge` 等。 |
| `importance` | 重要性，建议 0.0 到 1.0。 |
| `confidence` | 置信度，建议 0.0 到 1.0。 |
| `status` | `active`、`candidate`、`archived`、`deleted`、`rejected`。 |
| `created_at` / `updated_at` | 创建和更新时间。 |
| `last_accessed_at` | 最近被检索使用时间。 |
| `expires_at` | 过期时间，可为空。 |
| `evidence_json` | 支撑该记忆的已确认事件、对话、输出引用。 |
| `metadata_json` | 内部调试、版本和业务适配元数据。 |
| `embedding_id` | 对应向量记录 ID，可为空。 |
| `embedding_version` | 生成 embedding 的模型和算法版本。 |

### memory_embeddings

第一版目标采用双索引：

- `episodic` 事件记忆使用 sqlite-vec。
- `semantic` 语义记忆使用 HNSW/hnswlib。

ObjectBox 只作为后续替代方案，不进入第一版实现基线。无论底层如何，模块内应抽象成 `EpisodicVectorIndex`、`SemanticHnswIndex` 和 `memory_embeddings` 逻辑对象，外部模块不感知具体向量库。

| 字段 | 说明 |
| --- | --- |
| `embedding_id` | 向量 ID。 |
| `memory_id` | 对应记忆 ID。 |
| `bot_id` | 冗余机器人 ID，用于过滤和重建。 |
| `memory_type` | 冗余记忆类型，用于过滤。 |
| `content_hash` | 生成向量时的文本 hash。 |
| `provider` | embedding 生成器来源。 |
| `model` | embedding 模型名。 |
| `dimension` | 向量维度。 |
| `vector` | 向量数据，实际格式由底层决定。 |
| `created_at` | 创建时间。 |

约定：

- `content_hash` 不一致时必须重建 embedding。
- `embedding_version` 变化时允许批量重建索引。
- 向量索引缺失时可以切换为文本检索，但需要返回 warning。
- sqlite-vec 事件索引可随 SQLite 权威记录一起重建。
- hnswlib 语义索引文件是可重建索引，不能成为权威数据来源。

### semantic_hnsw_index

hnswlib 索引用于长期语义记忆召回。

建议元数据仍保存在 SQLite：

| 字段 | 说明 |
| --- | --- |
| `index_id` | 索引 ID。 |
| `bot_id` | 机器人 ID。 |
| `memory_id` | 对应 `semantic` 记忆 ID。 |
| `hnsw_label` | hnswlib 内部 label。 |
| `index_file` | 本地索引文件路径或引用。 |
| `embedding_version` | embedding 版本。 |
| `index_version` | HNSW 参数版本。 |
| `status` | `active`、`pending`、`stale`、`deleted`。 |
| `updated_at` | 更新时间。 |

HNSW 参数作为内部实现版本管理，不进入跨模块接口。第一版可以先固定参数，后续再通过 `index_version` 触发索引重建。

### memory_relationship_state

关系记忆可以直接存成 `memory_records(memory_type = relationship)`，也可以额外维护聚合状态表。

建议保留聚合状态：

| 字段 | 说明 |
| --- | --- |
| `bot_id` | 当前机器人。 |
| `target_id` | 关系对象。 |
| `target_type` | 用户、角色、机器人或实体。 |
| `trust` | 信任倾向。 |
| `affinity` | 亲近倾向。 |
| `risk` | 风险或警惕倾向。 |
| `preference_json` | 偏好、互动风格和称呼习惯。 |
| `evidence_ids_json` | 支撑关系变化的事件记忆 ID。 |
| `updated_at` | 更新时间。 |

关系记忆在检索时通常优先按 `target_id` 直取，不依赖纯向量召回。

### memory_reports

用于开发和调试，release 可裁剪或只保留摘要。

| 字段 | 说明 |
| --- | --- |
| `report_id` | 报告 ID。 |
| `bot_id` | 机器人 ID。 |
| `scope_key` | 范围键。 |
| `report_type` | `context_build`、`memory_update`、`maintenance`、`schema_reject`。 |
| `payload_json` | 报告内容。 |
| `created_at` | 创建时间。 |

## 推荐索引

结构化索引：

- `bot_id, memory_type, status`
- `bot_id, domain_id, session_id, instance_id`
- `bot_id, subject_id, subject_type`
- `bot_id, visibility`
- `bot_id, updated_at`
- `bot_id, importance, confidence`

文本索引：

- `content` 可接 SQLite FTS 作为向量检索失败时的召回补充。
- 中文场景如果没有合适分词器，至少保留 n-gram text_retrieval。

向量索引：

- sqlite-vec 事件索引按 `bot_id`、`memory_type = episodic`、`domain_id`、`visibility` 做过滤。
- hnswlib 语义索引召回后必须回 SQLite 做 `bot_id`、`visibility`、`status` 和范围校验。
- 检索时必须先做结构化过滤或召回后强校验，再进入 rerank。
- 不能跨机器人召回向量。

## Android 落地阶段

### 阶段 1：结构化 SQLite

目标：

- 新机器人/RAG 主路径使用 `persona_snapshot` 和 `memory_records`。
- 补齐 `memory_type`、`importance`、`confidence`、`visibility`、`source`、`status`。
- 保留当前 JSON text_retrieval。

当前进度：

- Godot JSON text_retrieval 已保存 `persona_snapshot` 和 `memory_records`。
- Android SQLite 已增加 `memory_persona_snapshots` 和 `memory_records`。
- Godot bridge 已增加 `memory_save_state`，用于保存完整结构化 state。
- 新 `get_memory_context()` 主路径只读取 `persona_snapshot` 和 `memory_records`。
- 开发期临时字段不进入记忆上下文主链路，也不作为机器人记忆页的数据源。

### 阶段 2：文本检索增强

目标：

- 加入 SQLite FTS 或稳定的本地 token index。
- 保留 Godot 侧轻量检索作为 text_retrieval。
- 在向量索引不可用、记录未索引或 query 质量不足时，调试报告明确显示 text_retrieval 原因。

当前进度：

- Godot 侧已具备文本 token / CJK n-gram 召回。
- `retrieve()` 接口返回 `text_retrieval`，只服务开发期轻量查询。
- 新 `get_memory_context()` 主路径在索引可用时使用 `hybrid_vector`。

### 阶段 3：向量索引

目标：

- 接入 sqlite-vec 事件记忆索引。
- 接入 hnswlib 语义记忆索引。
- 增加 embedding 生成和版本管理。
- 增加事件向量召回和语义 HNSW 召回接口。
- 调试报告显示 `vector_enabled`、embedding 版本、召回数量和切换原因。

当前进度：

- 已落地 Godot 本地 `token_hash_v1` embedding。
- 已落地本地事件向量槽和语义 HNSW 风格图。
- 已在报告中区分 `vector_backend = godot_local_vector` 与 native 后端状态。
- native `sqlite-vec` / `hnswlib` 替换时不得改变机器人模块门面接口。

默认选择和参数见 [记忆系统默认决策](memory-defaults.md)。

### 阶段 4：索引维护

目标：

- 支持 embedding 批量重建。
- 支持脏数据检查。
- 支持索引缺失自动补建。
- 支持维护报告和失败再次发起。

## 存储边界

机器人档案可以保存机器人名称、模型、声音、人设和基础设置，但不应直接成为长期记忆主表。

建议边界：

- `BotProfile`：机器人是谁。
- `MemoryRecord`：机器人记住了什么。
- `MemoryEmbedding`：如何高效召回记忆。
- `MemoryReport`：为什么这次召回或更新是这个结果。

## 无效数据规则

- 任何存储结构变化必须增加 schema 版本。
- schema 不匹配的数据直接拒绝读取或丢弃，并写入结构拒绝报告。
- 向量索引可重建，原始 `memory_records` 不可随意丢失。
- `embedding_version` 变化只要求重建 embedding，不要求重写原始记忆。
- Android SQLite、桌面 JSON、Godot bridge 和文档必须同步。

## 失败处理

| 场景 | 策略 |
| --- | --- |
| SQLite 不可用 | 切换到 JSON 或空记忆上下文，返回 warning。 |
| 向量索引不可用 | 切换到文本检索，报告 `vector_unavailable`。 |
| embedding 生成失败 | 记忆仍可写入结构化存储，标记 `embedding_pending`。 |
| schema 不匹配 | 丢弃不符合当前结构的数据，阻断本次写入。 |
| 索引损坏 | 清理并重建向量索引，不删除原始记忆。 |

## 开发约定

- 不把底层表名暴露给外部业务。
- 不让 UI 直接改数据库记录。
- 不把模型草稿写入 `memory_records`。
- 不把当前机器人不可见的信息写入任何记忆表。
- 记忆写入必须能追溯到 `evidence_json` 或明确的初始化来源。
- 调试面板可以查看报告，但默认脱敏私有内容。
