# 机器人模块

更新时间：2026-05-16

机器人模块是机器人/RAG 系统对外暴露能力的门面模块。它负责机器人档案、机器人生命周期和能力编排，内部组合 [记忆模块](memory-module.md) 与 [机器人上下文处理模块](bot-context-module.md)，共同向外部具体业务 AI 机器人玩家适配层提供通用机器人能力。

机器人模块不绑定具体业务。狼人杀、客服、聊天、工具任务或其它业务都只能通过通用 `BotVisibleContext`、`BotRuntimeScope` 和 `memory_update` 与它交互。

## 模块定位

```text
外部业务适配层 / 具体业务 AI 机器人玩家适配层
  -> 机器人模块
       -> 创建或获取机器人
       -> 初始化机器人
       -> 构建机器人推理上下文
       -> 提交已确认结果用于记忆更新
       -> 触发机器人记忆维护

机器人模块
  -> 记忆模块
  -> 机器人上下文处理模块
```

机器人模块是对外入口；记忆模块和上下文处理模块是内部能力。外部不需要知道记忆检索、上下文压缩、工作记忆维护等内部细节。

## 能力边界

机器人模块负责：

- 创建或获取机器人档案。
- 管理机器人 ID、昵称、头像、人格模板、模型配置引用、声音配置引用和综合记忆状态。
- 初始化机器人记忆。
- 调用记忆模块获取 `AgentMemoryContext`。
- 调用上下文处理模块生成 `BotReasoningContext`。
- 接收已被外部业务确认的输出、对话和事件，转交记忆模块更新。
- 触发会话结束反思、清理工作记忆和记忆维护。
- 对外提供稳定接口。

机器人模块不负责：

- 模型供应商配置、模型请求和模型输出解析。
- 具体业务行动策略、目标选择和合法性判断。
- 业务状态、具体游戏房间模块校验、胜负判断或流程推进。
- TTS 播放。
- 直接展示 UI。

UI 约定：

- 机器人配置页只承载机器人档案、模型、声音、人设和记忆概况。
- 完整记忆查看、检索调试、更新报告、维护报告和索引状态进入独立机器人记忆页，页面设计见 [机器人记忆页面设计](memory-ui.md)。
- 记忆系统复杂度高，不使用弹窗作为主要展示容器。

## 核心对象

### BotProfile

机器人档案描述“这个机器人是谁”。它不是业务角色状态，也不是模型配置。

| 字段 | 说明 |
| --- | --- |
| `bot_id` | 机器人唯一 ID。 |
| `display_name` | 机器人展示名。 |
| `avatar_id` | 机器人头像或头像资源 ID。 |
| `persona_id` | 人格模板 ID。 |
| `model_profile_name` | 默认模型配置引用；具体业务 AI 机器人玩家适配层在控制设备本机据此读取完整 `ModelProfile`。 |
| `voice_profile_id` | 默认声音配置或音色引用；具体业务 AI 机器人玩家适配层调用玩家/TTS 输出链路时使用，TTS 模块据此解析实际音色 ID。 |
| `personality` | 性格标签或结构化人格。 |
| `speaking_style` | 表达风格。 |
| `strategy_style` | 倾向性策略，只作为长期行为偏好，不直接决定业务输出。 |
| `background_story` | 初始背景故事，可转成初始记忆。 |
| `memory` | 综合记忆快照，包括基础记忆、工作记忆、长期记忆和备注。 |
| `created_at` / `updated_at` | 创建和更新时间。 |

约定：

- 模型绑定、声音绑定是机器人档案的一部分；机器人模块只保存引用，不读取模型 API 细节，也不调用 TTS。
- AI 机器人玩家需要发言或行动时，由具体游戏 AI 机器人玩家适配层读取 `model_profile_name` 和 `voice_profile_id`；完整模型配置只在控制设备本机读取，音色引用传给玩家模块。
- 记忆属于机器人本身，不提供单独的“记忆命名”配置。底层存储如需分区，使用机器人 ID 派生内部键。
- 人格模板可空；为空时机器人只根据自身记忆自进化，填写后作为初始模板并随记忆继续演化。
- `strategy_style` 只能作为人格和记忆上下文，最终输出仍由具体业务 AI 机器人玩家适配层组合模型输出并交给外部业务校验。

### BotCapabilityFacade

机器人模块对外暴露的是一个门面服务。

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

详细参数见 [interfaces.md](interfaces.md)。

当前代码入口是 `scripts/core/bot/bot_capability_facade.gd`。它已经接入机器人档案仓库、`scripts/core/bot/bot_context_builder.gd` 和记忆模块，覆盖档案列表/创建/读取/更新/删除、初始化、上下文构建、提交记忆更新、维护、记忆页概览、分层列表、详情、报告、索引状态和上下文预览。完整维护引擎仍按记忆模块路线图继续扩展。

## 对外接口

### 创建或获取机器人

```text
create_or_get_bot_profile(request) -> BotProfileResult
```

作用：创建机器人档案，或根据 `bot_id` / 绑定信息获取已有机器人档案。

约定：

- 创建机器人时必须准备机器人 ID；内部记忆存储键由机器人 ID 派生，对外不暴露。
- 初始人格可以生成长期人格种子，但不能伪造当前会话事实。

### 初始化机器人

```text
initialize_bot(request) -> BotInitResult
```

流程：

```text
create_or_get_bot_profile()
  -> 创建 BotRuntimeScope / AgentMemoryScope
  -> 记忆模块 init_memory()
  -> 返回 bot_id、profile 和 memory_scope
```

初始化场景：

- 新建 AI 角色。
- 加载已有机器人。
- 新会话开始，创建当前会话工作记忆空间。
- 丢弃不符合当前结构的数据。

### 构建机器人上下文

```text
build_bot_context(request) -> BotContextResult
```

`BotContextBuildRequest` 核心字段：

| 字段 | 说明 |
| --- | --- |
| `bot_id` | 机器人 ID。 |
| `scope` | 通用运行范围。 |
| `visible_context` | 调用方传入的 `BotVisibleContext`。 |
| `task_type` | 当前任务类型。 |
| `max_token_budget` | 总上下文预算。 |
| `memory_options` | 需要包含的记忆类型和检索限制。 |

内部流程：

```text
BotContextBuildRequest
  -> 读取 BotProfile
  -> 构建 MemoryContextRequest
  -> 记忆模块 get_memory_context()
  -> 上下文处理模块 build_reasoning_context()
  -> 返回 BotReasoningContext
```

返回结果：

| 字段 | 说明 |
| --- | --- |
| `ok` | 是否成功。 |
| `bot_profile` | 机器人档案。 |
| `reasoning_context` | 结构化 `BotReasoningContext`。 |
| `warnings` | 记忆缺失、上下文裁剪、可见性风险等提示。 |
| `error` | 失败原因。 |

### 提交机器人结果

```text
commit_bot_result(request) -> BotMemoryCommitResult
```

`BotResultCommitRequest` 核心字段：

| 字段 | 说明 |
| --- | --- |
| `bot_id` | 机器人 ID。 |
| `scope` | 通用运行范围。 |
| `accepted_outputs` | 已被外部业务接受的机器人输出。 |
| `accepted_dialogues` | 已公开或已确认的对话。 |
| `confirmed_events` | 外部业务已确认事件。 |
| `memory_update` | 分层记忆更新载荷，包含 working、episodic、relationship、semantic、reflection 等更新候选。 |
| `outcome` | 输出、流程或会话结果。 |
| `commit_reason` | 提交原因。 |

约定：

- 只有外部业务已经确认的内容才能提交。
- 被模型生成但未执行、未确认或被拒绝的草稿不能提交。
- 机器人模块把请求转换成 `MemoryUpdateRequest`，交给记忆模块处理。
- `memory_update` 不是自然语言摘要。调用方可以提交分层候选，但实际写入哪一层、是否降权、合并或忽略，由记忆模块决定。

### 维护机器人

```text
maintain_bot(request) -> BotMaintenanceResult
```

触发场景：

- 会话结束。
- 应用启动。
- 低存储空间。
- 手动维护。
- 构建上下文前发现记忆过大。

内部流程：

```text
maintain_bot()
  -> 记忆模块 maintain_memory()
  -> 必要时 clear_working_memory()
  -> 返回维护结果和 warning
```

### 只读调试

```text
get_bot_debug_state(request) -> BotDebugStateResult
get_bot_memory_overview(request) -> BotMemoryOverviewResult
list_bot_memory_records(request) -> BotMemoryRecordListResult
get_bot_memory_record_detail(request) -> BotMemoryRecordDetailResult
get_bot_memory_reports(request) -> BotMemoryReportsResult
preview_bot_memory_context(request) -> BotMemoryContextPreviewResult
get_last_context_report(request) -> BotContextReportResult
get_last_memory_update_report(request) -> BotMemoryUpdateReportResult
get_last_maintenance_report(request) -> BotMaintenanceReportResult
```

用途：

- 查看机器人档案、记忆健康状态和 schema 版本。
- 查看当前工作记忆概况。
- 给独立机器人记忆页提供分层记忆列表、记录详情、索引状态和报告数据。
- 查看最近一次上下文构建的预算、裁剪和 warning。
- 查看最近一次 `memory_update` 的写入、跳过、降权和合并结果。
- 查看最近一次维护的反思、合并、衰减、归档和索引任务结果。

约定：

- 调试接口只读，不提供修改记忆的能力。
- 默认脱敏私有内容。
- release 包可以禁用或只返回极简健康状态。
- 调试报告只服务开发排查，不应成为业务逻辑依赖。
- 记忆页接口仍然只读；需要整理时只能调用 `request_bot_memory_maintenance()` 触发受控维护流程。

## 主要流程

### 创建 AI 角色

```text
外部业务模块创建 AI 角色基础数据
  -> 机器人模块 create_or_get_bot_profile()
  -> 机器人模块 initialize_bot()
  -> 返回 bot_id
  -> 外部业务模块保存 bot_id 引用
```

### AI 角色推理前

```text
业务适配层接到任务请求
  -> 构建通用 BotVisibleContext
  -> 机器人模块 build_bot_context()
     -> 记忆模块 get_memory_context()
     -> 上下文处理模块 build_reasoning_context()
  -> 返回 BotReasoningContext
  -> 具体业务 AI 机器人玩家适配层使用本机 ModelProfile 调用基础模型推理能力
```

### 输出被业务接受后

```text
外部业务模块接受输出
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

## 与其它模块的关系

| 模块 | 机器人模块如何交互 |
| --- | --- |
| 记忆模块 | 内部调用，负责记忆存储、检索、更新和维护。 |
| 机器人上下文处理模块 | 内部调用，负责把通用可见上下文和记忆上下文合成 `BotReasoningContext`。 |
| 玩家/角色模块 | 保存 `bot_id`、记忆引用或机器人绑定关系。 |
| 具体业务 AI 机器人玩家适配层 | 当前主要消费方：构建可见上下文、请求机器人上下文、提交已确认结果。 |
| 模型管理 | 不直接依赖；具体业务 AI 机器人玩家适配层在控制设备本机同时调用模型管理和机器人模块。 |
| TTS 语音 | 不直接交互；TTS 只播报已确认文本。 |
| 具体业务模块 | 不直接操作记忆；只通过业务适配层提交通用对象。 |

## 维护规则

- 对外只暴露机器人模块门面，不让外部绕过门面直接操作记忆存储。
- 机器人模块不生成最终输出，不调用模型，不解析模型输出。
- `build_bot_context()` 返回结构化上下文，不返回供应商专用 prompt。
- `commit_bot_result()` 只接收已确认结果。
- 机器人档案、内部记忆存储键和外部角色绑定字段变化时，同步玩家/角色模块、具体业务 AI 机器人玩家适配层和记忆模块文档。
