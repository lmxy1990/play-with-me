# 机器人/RAG 模块

更新时间：2026-05-16

机器人/RAG 模块是基础模块，提供通用机器人能力。它不绑定狼人杀、房间、规则或任何具体业务；外部业务模块只通过通用上下文和通用记忆更新载荷与它交互。

模块内部按职责拆成三层：

1. [记忆模块](memory-module.md)：负责机器人自身记忆的存储、检索、更新、维护和防污染。
2. [机器人上下文处理模块](bot-context-module.md)：负责把业务可见上下文和记忆上下文整理成结构化推理上下文。
3. [机器人模块](bot-module.md)：负责机器人档案和生命周期，对外组装记忆模块与上下文处理模块，提供统一机器人能力。

对外函数、参数和返回结构见 [interfaces.md](interfaces.md)。其中部分接口是设计期预设，后续整体模块编织和代码重构时可以继续调整。

跨模块对象 `BotProfile`、`BotVisibleContext`、`BotReasoningContext` 和 `memory_update` 的字段权威见 [跨模块契约](../../contracts/README.md)。本模块文档聚焦机器人/RAG 内部职责和对外门面。

详细的 Android Agent Memory System 推演见 [android_agent_memory_system_design_complete.md](android_agent_memory_system_design_complete.md)。长文档保留完整设计推导；本文和各子文档作为当前工程的模块契约入口。

## 当前记忆实现状态

当前代码已经有结构化记忆、Godot 本地 embedding、事件向量索引、语义 HNSW 图、混合检索、排序、蒸馏、合并和遗忘维护。Android 插件端已接入 native `sqlite-vec` 事件索引和 hnswlib 语义/反思索引；桌面/编辑器继续使用 Godot 本地索引作为同接口 text_retrieval。

当前状态：

- 桌面/编辑器使用 `user://play_with_me_memory.json`。
- Android 真机优先使用 native SQLite 插件。
- 当前检索是 Hybrid Retrieval：结构化直取 + native/Godot 向量召回 + 文本 text_retrieval。
- 当前 embedding 是 Godot 本地 `token_hash_v1`，不是外部模型 embedding。
- Android 真机上事件记忆以 `sqlite_vec_event` 召回源呈现，底层优先使用插件端 `sqlite-vec`；不可用时切换到 Godot 本地向量槽。
- Android 真机上语义/反思记忆以 `hnsw_semantic` 召回源呈现，底层优先使用插件端 hnswlib；不可用时切换到 Godot 本地 HNSW 风格邻接图或文本 text_retrieval。
- Android bridge 保存结构化状态，并暴露 native rebuild/search 接口；最终候选仍回到 `memory_records` 做可见性、状态和预算过滤。

目标状态：

- 底层存储支持结构化多层记忆。
- 事件记忆使用 native sqlite-vec 做向量召回。
- 语义记忆使用 native HNSW/hnswlib 做长期语义近邻召回。
- 检索层支持 Memory Query Router、Hybrid Retrieval、Candidate Pool Builder、Policy Reranker Engine、Memory Selection + Fusion 和文本 text_retrieval。
- 更新层支持 Memory Formation、分层写入、防污染、去重、降权和报告。
- 维护层支持 Memory Distillation、Memory Merge、Forgetting、冲突处理和索引重建。
- 机器人配置页只展示记忆概况和进入记忆页入口；完整记忆展示使用独立机器人记忆页，不使用弹窗。
- 机器人记忆页展示分层记忆、健康状态、维护状态、索引状态和只读报告；开发视图展示 query、score、召回、裁剪和维护报告。

## 总体定位

```text
外部业务适配层 / 具体业务 AI 玩家模块
  -> 机器人模块门面
       -> 记忆模块
       -> 机器人上下文处理模块
  -> 返回 BotReasoningContext

具体业务 AI 玩家模块
  -> 组合 BotReasoningContext
  -> 在控制设备本机读取完整 ModelProfile
  -> 调用基础模型推理能力
  -> 解析模型输出
  -> 提交输出给外部业务模块校验
  -> 外部业务确认后提交 memory_update 给机器人模块
```

机器人/RAG 模块对外表达的是“机器人能力”，不是业务规则、数据库表，也不是 prompt 拼接器。对调用方而言，它应该像黑盒子：输入可见上下文和已确认的记忆更新材料，输出可用于推理的机器人上下文，并维护机器人自己的多层记忆。机器人档案保存默认模型配置引用和声音配置引用，具体游戏 AI 玩家模块在控制设备本机读取这些引用；完整模型配置和 API Key 只从本机模型数据库读取，声音引用传给玩家/TTS 链路。

## 拆分原则

### 记忆模块

记忆模块只回答：

- 这个机器人记住了什么？
- 当前场景下哪些记忆相关？
- 已确认事件之后哪些记忆层需要更新？
- 哪些记忆应该被反思、合并、衰减或遗忘？

它不关心具体业务，不调用模型，不读取业务权威状态，不判断业务动作是否合法。

### 机器人上下文处理模块

上下文处理模块只回答：

- 当前机器人能看到什么？
- 当前任务需要哪些上下文块？
- 业务可见上下文和记忆上下文如何合并？
- 如何在 token 预算内输出稳定结构？

它不存储记忆，不更新记忆，不调用模型，不执行业务规则。

### 机器人模块

机器人模块只回答：

- 机器人是谁？
- 机器人如何初始化？
- 如何拿到这个机器人当前可用于推理的上下文？
- 外部业务确认结果后如何提交给记忆系统？

它是外部入口，负责组装记忆模块和上下文处理模块。

## 能力边界

机器人/RAG 模块负责：

- 机器人档案和人格模板引用。
- 机器人默认模型配置引用和声音配置引用。
- 记忆空间初始化。
- 记忆检索、更新、维护和防污染。
- 机器人推理上下文的结构化组装。
- 已确认结果的记忆提交。

机器人/RAG 模块不负责：

- 模型供应商配置、API Key、Endpoint、模型请求体和模型调用。
- 任何具体业务的行动策略、目标选择、发言生成或模型输出解析。
- 业务规则执行、生命周期推进、胜负判断或业务复盘权威数据。
- 业务网络、认证、重连、主机选举或快照同步。
- TTS 文本转语音、声音播放或播报队列。
- UI 展示和用户交互。

具体业务 AI 玩家模块需要推理时，组合本模块的机器人上下文和 [模型管理模块](../model-management/README.md) 的基础模型推理能力。具体业务如何从业务状态生成 `BotVisibleContext`、如何读取本机 `ModelProfile`、如何把业务确认结果转换成 `memory_update`，由具体业务 AI 玩家模块负责。

## 对外能力

外部模块原则上只调用机器人模块门面：

```text
list_bot_profiles(request) -> BotProfileListResult
create_or_get_bot_profile(request) -> BotProfileResult
get_bot_profile(request) -> BotProfileResult
update_bot_profile(request) -> BotProfileResult
delete_bot_profile(request) -> BotProfileDeleteResult
initialize_bot(request) -> BotInitResult
build_bot_context(request) -> BotContextResult
commit_bot_result(request) -> BotMemoryCommitResult
maintain_bot(request) -> BotMaintenanceResult
get_bot_debug_state(request) -> BotDebugStateResult
get_bot_memory_overview(request) -> BotMemoryOverviewResult
list_bot_memory_records(request) -> BotMemoryRecordListResult
get_bot_memory_record_detail(request) -> BotMemoryRecordDetailResult
get_bot_memory_reports(request) -> BotMemoryReportsResult
preview_bot_memory_context(request) -> BotMemoryContextPreviewResult
request_bot_memory_maintenance(request) -> BotMaintenanceResult
get_last_context_report(request) -> BotContextReportResult
get_last_memory_update_report(request) -> BotMemoryUpdateReportResult
get_last_maintenance_report(request) -> BotMaintenanceReportResult
```

其中：

- `build_bot_context()` 内部调用记忆模块获取 `AgentMemoryContext`，再调用上下文处理模块生成 `BotReasoningContext`。
- `commit_bot_result()` 只接收外部业务已经确认的事件、对话、输出和结果。
- 机器人记忆页接口只读，默认脱敏，不提供直接改记忆能力；维护只能通过受控维护接口触发。
- 记忆模块的底层存储接口不直接暴露给具体业务模块或 UI。

## 基础模块契约

作为基础模块，机器人/RAG 还需要遵守这些通用契约：

- 生命周期：外部在 `bot_created`、`session_started`、`before_task`、`after_confirmed_result`、`session_end`、`maintenance` 等节点调用对应门面接口。
- 可见性：外部业务适配层必须先脱敏，机器人模块只接收当前机器人可见的 `BotVisibleContext` 和 `memory_update`。
- 防污染：模型草稿、未确认输出、被拒绝输出、UI 临时输入不得进入记忆。
- 版本校验：跨模块请求建议携带 `schema_version`、`adapter_version`、`memory_schema_version`、`context_schema_version`；版本不匹配时拒绝或丢弃。
- 失败处理：记忆读取失败可以切换为无记忆上下文；记忆写入失败不撤销外部业务结果；维护失败允许后续再次发起。
- 只读调试：允许提供机器人档案、工作记忆概况、上下文裁剪报告和记忆更新报告；不得提供直接修改记忆表的接口。

详细字段见 [interfaces.md](interfaces.md)。

## 关键数据流

### 创建 AI 角色

```text
外部业务模块创建 AI 角色基础数据
  -> 机器人模块 create_or_get_bot_profile()
  -> 机器人模块 initialize_bot()
  -> 记忆模块 init_memory()
  -> 外部业务模块保存 bot_id 引用
```

### AI 角色推理前

```text
业务适配层接到任务请求
  -> 构建通用 BotVisibleContext
  -> 机器人模块 build_bot_context()
     -> 记忆模块 get_memory_context()
     -> 机器人上下文处理模块 build_reasoning_context()
  -> 返回 BotReasoningContext
  -> 具体业务 AI 玩家模块使用本机 ModelProfile 调用基础模型推理能力
```

### 输出被业务接受后

```text
外部业务模块接受输出、对话、事件或结果
  -> 业务适配层构建通用 BotResultCommitRequest
  -> 机器人模块 commit_bot_result()
     -> 记忆模块 update_memory()
```

### 会话结束

```text
外部业务模块生成已确认事件、结果和可公开材料
  -> 业务适配层提交 session_end_memory_update
  -> 机器人模块 commit_bot_result()
  -> 机器人模块 maintain_bot()
     -> 记忆模块生成 reflection / semantic lessons / relationship update
     -> 清理当前会话 working memory
```

## 子文档

| 文档 | 内容 |
| --- | --- |
| [memory-module.md](memory-module.md) | 记忆空间、记忆类型、记忆服务接口、更新和维护规则。 |
| [memory-defaults.md](memory-defaults.md) | 记忆系统第一版默认决策：向量库、检索参数、提取上限、记忆层级和最大输出。 |
| [memory-storage.md](memory-storage.md) | 记忆存储、当前实现状态、目标表结构、向量索引和无效数据处理规则。 |
| [memory-retrieval.md](memory-retrieval.md) | 记忆检索、query 生成、分层召回、rerank、预算裁剪和切换。 |
| [memory-update.md](memory-update.md) | 分层记忆更新、可写入来源、防污染、去重、合并和更新报告。 |
| [memory-maintenance.md](memory-maintenance.md) | 反思、长期语义合并、关系维护、衰减、遗忘、冲突和索引维护。 |
| [memory-ui.md](memory-ui.md) | 独立机器人记忆页、配置页入口、分层记忆展示和页面数据接口。 |
| [memory-debug.md](memory-debug.md) | 记忆检索、更新、维护和索引报告的开发调试呈现方式。 |
| [bot-context-module.md](bot-context-module.md) | 可见上下文、记忆上下文合并、token 预算、`BotReasoningContext`。 |
| [bot-module.md](bot-module.md) | 机器人档案、生命周期、门面接口、内部编排流程。 |
| [interfaces.md](interfaces.md) | 面向模块开发的对外函数接口、参数草案和内部服务接口。 |
| [android_agent_memory_system_design_complete.md](android_agent_memory_system_design_complete.md) | Android Agent Memory System 的完整设计推导和扩展方向。 |

## 当前代码归属

当前实现分散在：

```text
scripts/core/memory/
  memory_manager.gd

scripts/core/bot/
  bot_capability_facade.gd
  bot_context_builder.gd
  bot_profile_repository.gd
  bot_profile_schema.gd
  werewolf_bot_runtime.gd

scripts/android/
  android_memory_store.gd

scripts/room/werewolf/
  werewolf_memory.gd
  werewolf_memory_context.gd
  werewolf_memory_model_summarizer.gd

android_plugins/play_with_me_android/.../MemoryDatabase.kt
```

设计归属：

- 通用记忆存储、初始化、检索、上下文组装和更新接口归 [记忆模块](memory-module.md)。
- 第一版默认参数和取舍归 [记忆系统默认决策](memory-defaults.md)。
- 存储结构和向量索引归 [记忆存储设计](memory-storage.md)。
- query、召回、rerank 和预算裁剪归 [记忆检索设计](memory-retrieval.md)。
- 分层写入、防污染和更新报告归 [记忆更新设计](memory-update.md)。
- 反思、合并、衰减和索引维护归 [记忆维护设计](memory-maintenance.md)。
- 机器人记忆页和配置页入口归 [机器人记忆页面设计](memory-ui.md)。
- 调试报告如何呈现归 [记忆调试与呈现设计](memory-debug.md)。
- 业务可见上下文和记忆上下文合并归 [机器人上下文处理模块](bot-context-module.md)。
- 机器人档案、生命周期和对外门面归 [机器人模块](bot-module.md)。
- 狼人杀状态提取、模型调用编排、输出解析、行动错误和业务合法性判断归 [狼人杀 AI 玩家模块](../player/werewolf/ai/README.md)。

## 维护规则

- 外部只通过机器人模块门面使用机器人能力。
- 记忆模块不向外暴露存储表或向量索引。
- 上下文处理模块只处理已脱敏的通用可见上下文。
- 机器人/RAG 模块不调用模型，不生成最终输出，不提交业务结果。
- 外部业务确认之前的模型草稿、UI 临时输入和非法输出不得进入记忆。
- 记忆结构变更时，同步桌面 JSON、Android SQLite、Godot bridge、测试和相关子文档。
- 记忆系统 UI 复杂度按独立页面处理，不把完整记忆视图塞进弹窗。
