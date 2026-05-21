# Android Agent Memory System Design

## 1. 项目目标

构建一个面向 Android 本地运行的 AI Agent 系统，支持：

- 长期记忆
- 当前局工作记忆
- 关系演化
- 多 Agent 社交
- 动态人格
- RAG 检索
- 状态推理
- 游戏/社交场景
- 记忆更新维护
- 记忆衰减与合并
- Reflection 反思学习

目标场景包括：

- 狼人杀 NPC
- 社交 Agent
- AI 同伴
- AI 角色扮演
- 多 Agent 博弈系统
- 本地 AI 游戏角色系统

---

## 2. 核心设计思想

本系统不是：

```text
聊天记录 + Prompt
```

而是：

```text
认知状态机 + 独立记忆系统 + 当前推理系统
```

核心思想：

- Memory 分层
- Memory 与 Reasoning 解耦
- Memory System 独立封装
- 外部通过 API 使用记忆系统
- State 驱动
- RAG 检索
- Relationship 演化
- Reflection 强化
- Episodic 学习
- Working Memory 管理当前局势
- Long-term Memory 管理长期人格与经验

---

## 3. 总体架构

```text
                  ┌────────────────────┐
                  │      UI Layer      │
                  └────────────────────┘
                            │
                            ▼
                  ┌────────────────────┐
                  │   Agent Runtime    │
                  └────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        ▼                   ▼                   ▼

┌────────────────┐ ┌────────────────┐ ┌────────────────────┐
│  Game System   │ │ Reasoning Sys.  │ │   Memory System    │
└────────────────┘ └────────────────┘ └────────────────────┘
        │                   │                   │
        │                   │                   ▼
        │                   │         ┌────────────────────┐
        │                   │         │ AgentMemoryService │
        │                   │         └────────────────────┘
        │                   │                   │
        │                   │   ┌───────────────┼───────────────┐
        │                   │   ▼               ▼               ▼
        │                   │ Retrieval      Update        Maintenance
        │                   │ Pipeline       Pipeline       Pipeline
        │                   │   │               │               │
        │                   │   ▼               ▼               ▼
        │                   │ VectorStore   MemoryStores   Decay/Reflection
        │                   │ ObjectBox     sqlite-vector  Consolidation
        │                   │ SQLite        Embedding      Pruning
        │                   │
        ▼                   ▼
┌────────────────┐ ┌────────────────────┐
│  GameContext   │ │  ReasoningContext  │
└────────────────┘ └────────────────────┘
```

---

## 4. 系统边界原则

整个系统分为四个核心边界：

```text
Game System
Reasoning System
Memory System
Agent Runtime
```

### 4.1 Game System

只负责游戏本身：

- 房间状态
- 玩家状态
- 阶段流转
- 投票结果
- 夜间行动
- 死亡信息
- 公开事件
- 具体游戏房间模块校验

Game System 不负责：

- 长期记忆
- 人格演化
- RAG 检索
- 角色反思
- 复杂推理

---

### 4.2 Reasoning System

只负责当前决策：

- 当前局势分析
- 发言生成
- 投票判断
- 身份推测
- 行为规划
- 夜间行动决策
- 结构化输出决策结果

Reasoning System 不应该直接操作数据库。

Reasoning System 的输入是：

```text
ReasoningContext = GameContext + AgentMemoryContext
```

Reasoning System 的输出是：

```text
AgentDecision
```

---

### 4.3 Memory System

只负责记忆：

- 记忆初始化
- 记忆检索
- 记忆上下文构建
- 工作记忆更新
- 事件记忆写入
- 关系记忆更新
- 语义记忆合并
- 反思记忆生成
- 记忆衰减
- 记忆压缩
- 记忆遗忘
- 记忆维护

Memory System 不负责：

- 具体游戏房间模块执行
- 当前行动执行
- UI 展示
- 最终决策

---

### 4.4 Agent Runtime

Agent Runtime 是调度器。

它只负责编排：

```text
Game System -> Memory System -> Reasoning System -> Memory System -> Game System
```

它不应该包含复杂的记忆逻辑。

---

## 5. Memory 与 Reasoning 必须彻底解耦

Memory：

```text
负责“存储与认知积累”
```

Reasoning：

```text
负责“当前局势下的推理与决策”
```

二者是完全不同的问题。

很多 Agent 系统最大的问题是：

```text
把 Prompt 当 Memory
```

这会导致：

- 状态混乱
- 记忆污染
- 人格漂移
- Prompt 爆炸
- 推理不可控

所以系统必须采用：

```text
Memory Layer
+
Reasoning Layer
```

双层解耦架构。

---

## 6. Memory System 独立边界

Memory System 必须作为独立模块存在。

外部系统不能直接访问：

- VectorStore
- ObjectBox
- sqlite-vector
- SemanticMemoryStore
- EpisodicMemoryStore
- RelationshipMemoryStore
- ReflectionMemoryStore
- WorkingMemoryStore

外部只能通过：

```text
AgentMemoryService
```

访问记忆系统。

核心边界是：

```text
外部 -> AgentMemoryService.getMemoryContext() -> 记忆上下文
外部 -> AgentMemoryService.updateMemory() -> 更新记忆
```

外部不关心内部实现。

---

## 7. Memory System 对外 API

### 7.1 AgentMemoryService

```kotlin
interface AgentMemoryService {

    suspend fun initializeAgentMemory(
        request: AgentMemoryInitRequest
    ): AgentMemoryInitResult

    suspend fun getMemoryContext(
        request: MemoryContextRequest
    ): AgentMemoryContext

    suspend fun updateMemory(
        request: MemoryUpdateRequest
    ): MemoryUpdateResult

    suspend fun clearWorkingMemory(
        request: ClearWorkingMemoryRequest
    ): ClearWorkingMemoryResult

    suspend fun maintainMemory(
        request: MemoryMaintenanceRequest
    ): MemoryMaintenanceResult
}
```

---

### 7.2 外部允许调用的能力

外部只能做五件事：

```text
1. 初始化 Agent 记忆
2. 请求当前推理所需的记忆上下文
3. 提交记忆更新请求
4. 清理当前局工作记忆
5. 触发记忆维护
```

外部不能做：

```text
直接写 SemanticMemory
直接写 EpisodicMemory
直接修改 RelationshipMemory
直接操作 VectorStore
直接决定什么进入长期记忆
直接决定记忆如何衰减
```

---

## 8. MemoryContextRequest

推理前，外部向 Memory System 请求记忆上下文。

```kotlin
data class MemoryContextRequest(
    val agentId: String,
    val roomId: String,
    val gameId: String,

    val phase: GamePhase,
    val taskType: ReasoningTaskType,

    val currentInput: String?,
    val gameContextSummary: String,

    val visiblePlayerIds: List<String>,
    val targetPlayerIds: List<String> = emptyList(),

    val maxTokenBudget: Int = 3000,
    val includeWorkingMemory: Boolean = true,
    val includeRelationshipMemory: Boolean = true,
    val includeEpisodicMemory: Boolean = true,
    val includeSemanticMemory: Boolean = true,
    val includeReflectionMemory: Boolean = true
)
```

---

## 9. AgentMemoryContext

Memory System 返回的是推理上下文，不是数据库实体。

```kotlin
data class AgentMemoryContext(
    val agentId: String,

    val personaSnapshot: PersonaSnapshot,

    val workingMemory: WorkingMemorySnapshot?,

    val semanticContext: List<MemorySnippet>,

    val episodicContext: List<MemorySnippet>,

    val relationshipContext: List<RelationshipSnapshot>,

    val reflectionContext: List<MemorySnippet>,

    val memoryWarnings: List<String> = emptyList()
)
```

### 9.1 为什么返回 Snapshot / Snippet

外部不应该拿到内部实体。

也就是说，外部看到的是：

```text
可用于推理的记忆片段
```

而不是：

```text
数据库表结构
```

这样可以保证：

- 内部可替换
- 存储可替换
- 检索策略可替换
- 压缩策略可替换
- 外部代码稳定

---

## 10. MemoryUpdateRequest

推理后，外部向 Memory System 提交记忆更新请求。

注意：外部不是告诉 Memory System “写入哪张表”。

外部只提交：

```text
发生了什么
机器人做了什么判断
机器人执行了什么行为
行为结果如何
```

由 Memory System 内部决定如何更新。

```kotlin
data class MemoryUpdateRequest(
    val agentId: String,
    val roomId: String,
    val gameId: String,
    val phase: GamePhase,

    val events: List<GameEvent> = emptyList(),

    val dialogues: List<Dialogue> = emptyList(),

    val decision: AgentDecision? = null,

    val reasoningSummary: String? = null,

    val outcome: GameOutcome? = null,

    val updateReason: MemoryUpdateReason
)
```

---

## 11. MemoryUpdateReason

```kotlin
enum class MemoryUpdateReason {
    AFTER_DIALOGUE,
    AFTER_DECISION,
    AFTER_GAME_EVENT,
    AFTER_PHASE_CHANGED,
    AFTER_VOTE,
    AFTER_NIGHT_ACTION,
    AFTER_GAME_END,
    MANUAL_MAINTENANCE
}
```

---

## 12. MemoryUpdateResult

```kotlin
data class MemoryUpdateResult(
    val updatedWorkingMemory: Boolean,

    val createdEpisodes: Int,

    val updatedRelationships: Int,

    val createdReflectionCandidates: Int,

    val createdSemanticMemories: Int,

    val ignoredEvents: Int,

    val warnings: List<String> = emptyList()
)
```

---

## 13. Agent 创建与记忆初始化

Agent 在创建时必须初始化：

```text
初始人格
初始关系倾向
初始行为策略
初始世界观
初始背景故事
初始长期记忆
初始 Reflection Seed
```

很多 AI NPC 最大的问题是：

```text
出生时没有“过去”
```

导致：

- NPC 没人格
- NPC 没历史
- NPC 像临时 Prompt
- 每局像重生

所以 Agent 创建时必须写入基础记忆。

---

## 14. Agent Profile

```kotlin
@Entity
data class AgentProfile(
    @Id
    var id: Long = 0,

    var modelName: String,

    var agentName: String,

    var personalityType: String,

    var speakingStyle: String,

    var strategyStyle: String,

    var backgroundStory: String,

    var initialBeliefs: String,

    var createdAt: Long
)
```

---

## 15. AgentMemoryInitRequest

```kotlin
data class AgentMemoryInitRequest(
    val agentId: String,
    val profile: AgentProfile,
    val personaTemplate: PersonaTemplate,
    val initialRelationshipTargets: List<String> = emptyList()
)
```

---

## 16. Persona Template

创建 NPC 时，不要随机 Prompt，而是使用 Persona Template。

例如：

```json
{
  "personality": "谨慎型",
  "strategy": "保守投票",
  "social": "低信任陌生人",
  "emotion": "稳定冷静",
  "speech": "逻辑分析型"
}
```

或者：

```json
{
  "personality": "激进型",
  "strategy": "主动带节奏",
  "social": "快速建立联盟",
  "emotion": "容易愤怒",
  "speech": "强压迫感"
}
```

---

## 17. 初始 Semantic Memory

Agent 创建时直接生成初始长期记忆。

例如：

```text
我倾向于相信发言稳定的人
```

```text
我讨厌情绪化玩家
```

```text
我更喜欢隐藏身份
```

这些会写入：

```text
semantic_memory
```

---

## 18. 初始 Relationship Bias

NPC 不应该对所有人完全中立。

应该存在社交倾向。

例如：

```text
更信任老玩家
更怀疑强势玩家
更容易跟随高发言量玩家
```

这会让 NPC 更像“活人”。

---

## 19. 初始 Reflection Seed

创建 NPC 时可以植入历史经历。

例如：

```text
曾经因为轻信别人导致失败
```

```text
曾经因为过早跳身份被狼人击杀
```

这些不一定是真实发生。

它们属于：

```text
人格塑造记忆
```

类似角色设定。

---

## 20. Agent 初始化流程

```text
Create Agent
    ↓
Load Persona Template
    ↓
Generate Initial Semantic Memory
    ↓
Generate Initial Relationship Bias
    ↓
Generate Initial Reflection Seed
    ↓
Create Working Memory Scope
    ↓
Agent Ready
```

---

## 21. AgentMemoryScope

每个 Agent 必须绑定独立记忆空间。

```kotlin
data class AgentMemoryScope(
    val agentId: String,
    val personaId: String,
    val longTermMemoryNamespace: String,
    val relationshipNamespace: String,
    val workingMemoryNamespace: String
)
```

所有记忆都必须带：

```text
agentId
memoryType
targetId?
roomId?
gameId?
createdAt
importance
confidence
```

目的：

```text
A 机器人的记忆不能污染 B 机器人
当前局记忆不能直接污染长期人格
```

---

## 22. Memory 分层设计

系统 Memory 分为：

```text
1. Working Memory
2. Episodic Memory
3. Semantic Memory
4. Relationship Memory
5. Reflection Memory
```

---

## 23. Working Memory

### 23.1 作用

Working Memory 维护：

- 当前局势
- 当前状态
- 当前推理
- 当前怀疑链
- 当前目标
- 当前计划
- 当前情绪状态
- 最近对话
- 角色宣称
- 投票意图
- 已知事实

Working Memory 只在当前房间/当前局存在。

退出即销毁或归档。

它不直接进入长期人格。

---

### 23.2 Working Memory 数据结构

```kotlin
data class WorkingMemory(
    val roomId: String,
    val gameId: String,
    val agentId: String,

    val currentPhase: GamePhase,

    val recentDialogues: List<Dialogue>,

    val suspectScores: Map<String, Float>,

    val trustScores: Map<String, Float>,

    val roleClaims: Map<String, RoleClaim>,

    val voteIntentions: Map<String, String>,

    val knownFacts: List<GameFact>,

    val currentGoal: String,

    val currentPlan: String,

    val emotionalState: String,

    val lastDecision: AgentDecision?,

    val updatedAt: Long
)
```

---

### 23.3 Working Memory Snapshot

对外返回 Snapshot。

```kotlin
data class WorkingMemorySnapshot(
    val currentPhase: GamePhase,
    val suspectScores: Map<String, Float>,
    val trustScores: Map<String, Float>,
    val roleClaims: Map<String, RoleClaim>,
    val voteIntentions: Map<String, String>,
    val knownFacts: List<GameFact>,
    val currentGoal: String,
    val currentPlan: String,
    val emotionalState: String,
    val recentDialogueSummary: String
)
```

---

## 24. Working Memory 更新原则

Working Memory 的更新不是简单追加聊天记录。

错误做法：

```kotlin
recentDialogues += userMessage
recentDialogues += agentReply
```

正确做法：

```text
根据当前游戏事件 + 机器人推理结果 + 行为结果
更新当前局的临时认知状态
```

Working Memory 更新分三类：

```text
1. 事件驱动更新
2. 推理驱动更新
3. 阶段切换更新
```

---

## 25. WorkingMemoryPatch

LLM 不应该直接输出完整 WorkingMemory。

LLM 或 ReasoningEngine 应该输出结构化 Patch。

```kotlin
data class WorkingMemoryPatch(
    val suspectDelta: Map<String, Float> = emptyMap(),

    val trustDelta: Map<String, Float> = emptyMap(),

    val newFacts: List<GameFact> = emptyList(),

    val roleClaims: List<RoleClaim> = emptyList(),

    val voteIntentions: Map<String, String> = emptyMap(),

    val nextGoal: String? = null,

    val nextPlan: String? = null,

    val emotionalState: String? = null
)
```

这样可以做到：

```text
LLM 负责判断变化
代码负责安全合并
```

---

## 26. WorkingMemoryPatchApplier

```kotlin
class WorkingMemoryPatchApplier {

    fun apply(
        memory: WorkingMemory,
        patch: WorkingMemoryPatch
    ): WorkingMemory {

        return memory.copy(
            suspectScores = applyScoreDelta(
                memory.suspectScores,
                patch.suspectDelta
            ),
            trustScores = applyScoreDelta(
                memory.trustScores,
                patch.trustDelta
            ),
            knownFacts = mergeFacts(
                memory.knownFacts,
                patch.newFacts
            ),
            roleClaims = mergeRoleClaims(
                memory.roleClaims,
                patch.roleClaims
            ),
            voteIntentions = memory.voteIntentions + patch.voteIntentions,
            currentGoal = patch.nextGoal ?: memory.currentGoal,
            currentPlan = patch.nextPlan ?: memory.currentPlan,
            emotionalState = patch.emotionalState ?: memory.emotionalState,
            updatedAt = System.currentTimeMillis()
        )
    }

    private fun applyScoreDelta(
        current: Map<String, Float>,
        delta: Map<String, Float>
    ): Map<String, Float> {
        return current.toMutableMap().apply {
            delta.forEach { (playerId, d) ->
                val next = ((this[playerId] ?: 0.5f) + d)
                    .coerceIn(0f, 1f)

                this[playerId] = next
            }
        }
    }

    private fun mergeFacts(
        current: List<GameFact>,
        newFacts: List<GameFact>
    ): List<GameFact> {
        return (current + newFacts).distinctBy { it.id }
    }

    private fun mergeRoleClaims(
        current: Map<String, RoleClaim>,
        claims: List<RoleClaim>
    ): Map<String, RoleClaim> {
        return current.toMutableMap().apply {
            claims.forEach { claim ->
                this[claim.playerId] = claim
            }
        }
    }
}
```

---

## 27. 事件驱动更新

游戏系统确定发生的事，可以直接写入 Working Memory。

例如：

```text
天亮了
5号死亡
3号投票给7号
2号跳预言家
7号强势带票3号
```

接口：

```kotlin
fun updateByGameEvent(
    memory: WorkingMemory,
    event: GameEvent
): WorkingMemory
```

示例：

```kotlin
class GameEventWorkingMemoryUpdater {

    fun updateByGameEvent(
        memory: WorkingMemory,
        event: GameEvent
    ): WorkingMemory {
        return when (event.type) {
            GameEventType.PLAYER_CLAIM_ROLE -> {
                memory.copy(
                    roleClaims = memory.roleClaims + (
                        event.actorId to RoleClaim(
                            playerId = event.actorId,
                            claimedRole = event.payload["role"] ?: "unknown",
                            phase = memory.currentPhase,
                            confidence = 0.6f
                        )
                    )
                )
            }

            GameEventType.PLAYER_VOTED -> {
                memory.copy(
                    voteIntentions = memory.voteIntentions + (
                        event.actorId to (event.targetId ?: "")
                    )
                )
            }

            else -> {
                memory.copy(
                    knownFacts = memory.knownFacts + GameFact.fromEvent(event)
                )
            }
        }
    }
}
```

---

## 28. 推理驱动更新

机器人根据发言产生怀疑、信任、计划。

例如：

```text
7号带票太急，怀疑 +0.15
4号发言稳定，信任 +0.1
暂时不要快速站边
```

这些来自 AgentDecision 中的 WorkingMemoryPatch。

---

## 29. 阶段切换更新

阶段切换时，需要保留一部分信息，清理一部分信息。

```kotlin
fun updateOnPhaseChanged(
    memory: WorkingMemory,
    newPhase: GamePhase
): WorkingMemory {
    return when (newPhase) {
        GamePhase.DayDiscussion -> memory.copy(
            currentPhase = newPhase,
            voteIntentions = emptyMap(),
            currentGoal = "分析昨夜死亡信息，判断白天发言策略",
            currentPlan = "观察发言，不急于站边"
        )

        GamePhase.Vote -> memory.copy(
            currentPhase = newPhase,
            currentGoal = "根据当前怀疑链选择投票对象",
            currentPlan = "优先投当前嫌疑最高且逻辑矛盾最多的玩家"
        )

        GamePhase.NightAction -> memory.copy(
            currentPhase = newPhase,
            currentGoal = "根据身份执行夜间行动",
            currentPlan = "结合白天发言和投票结果选择目标"
        )

        GamePhase.Reflection -> memory.copy(
            currentPhase = newPhase,
            currentGoal = "总结本局关键判断与错误",
            currentPlan = "提炼长期可复用经验"
        )

        else -> memory.copy(
            currentPhase = newPhase
        )
    }
}
```

---

## 30. Episodic Memory

### 30.1 作用

Episodic Memory 记录：

```text
发生过什么
```

而不是：

```text
总结了什么
```

例如：

```text
第2天白天，7号连续三轮推动大家投3号。
```

---

### 30.2 数据结构

```kotlin
data class EpisodicMemory(
    val id: Long,

    val gameId: String,
    val roomId: String,
    val agentId: String,

    val eventType: String,

    val content: String,

    val participants: List<String>,

    val importance: Float,

    val confidence: Float,

    val embedding: FloatArray,

    val createdAt: Long
)
```

---

## 31. Semantic Memory

### 31.1 作用

Semantic Memory 维护：

- 人格
- 策略
- 偏好
- 行为模式
- 长期信念
- 长期经验

例如：

```text
我倾向于怀疑过度强势带票的人。
```

---

### 31.2 数据结构

```kotlin
data class SemanticMemory(
    val id: Long,

    val agentId: String,

    val type: String,

    val content: String,

    val confidence: Float,

    val importance: Float,

    val source: String,

    val embedding: FloatArray,

    val createdAt: Long,

    val updatedAt: Long
)
```

---

## 32. Relationship Memory

### 32.1 作用

Relationship Memory 维护：

```text
Agent 与其他 Agent 的长期关系
```

这是 NPC 是否像“活人”的关键。

---

### 32.2 数据结构

```kotlin
data class RelationshipMemory(
    val agentId: String,

    val targetAgentId: String,

    val trustScore: Float,

    val deceptionScore: Float,

    val cooperationScore: Float,

    val intimacyScore: Float,

    val conflictScore: Float,

    val evidenceCount: Int,

    val lastUpdated: Long
)
```

---

## 33. Reflection Memory

### 33.1 作用

Reflection Memory 记录 Agent 对某局或某段经历的反思。

它是：

```text
Reasoning -> Long-term Memory
```

的桥梁。

不是所有推理都应该进入长期记忆。

Reflection 负责提炼长期价值。

---

### 33.2 示例

```text
本局过早暴露身份导致被集火。
忽视了7号连续带票行为。
之后遇到强势带票者，需要观察其动机和收益对象。
```

---

## 34. Memory Update Pipeline

MemoryUpdateRequest 进入 Memory System 后，由内部 Pipeline 处理。

```text
MemoryUpdateRequest
    ↓
WorkingMemoryUpdater
    ↓
EpisodeExtractor
    ↓
RelationshipSignalExtractor
    ↓
ReflectionCandidateCollector
    ↓
MemoryWritePolicy
    ↓
MemoryStoreWriter
    ↓
MemoryUpdateResult
```

---

## 35. MemoryUpdatePipeline 代码结构

```kotlin
class MemoryUpdatePipeline(
    private val workingMemoryUpdater: WorkingMemoryUpdater,
    private val episodeExtractor: EpisodeExtractor,
    private val relationshipSignalExtractor: RelationshipSignalExtractor,
    private val reflectionCollector: ReflectionCandidateCollector,
    private val writePolicy: MemoryWritePolicy,
    private val memoryWriter: MemoryWriter
) {

    suspend fun update(
        request: MemoryUpdateRequest
    ): MemoryUpdateResult {

        val workingUpdated = workingMemoryUpdater.update(request)

        val episodes = episodeExtractor.extract(request)
            .filter { writePolicy.shouldWriteEpisode(it) }

        val relationshipSignals = relationshipSignalExtractor.extract(request)
            .filter { writePolicy.shouldUpdateRelationship(it) }

        val reflectionCandidates = reflectionCollector.collect(request)
            .filter { writePolicy.shouldCreateReflectionCandidate(it) }

        memoryWriter.writeEpisodes(episodes)

        memoryWriter.updateRelationships(
            agentId = request.agentId,
            signals = relationshipSignals
        )

        memoryWriter.writeReflectionCandidates(reflectionCandidates)

        return MemoryUpdateResult(
            updatedWorkingMemory = workingUpdated,
            createdEpisodes = episodes.size,
            updatedRelationships = relationshipSignals.size,
            createdReflectionCandidates = reflectionCandidates.size,
            createdSemanticMemories = 0,
            ignoredEvents = 0
        )
    }
}
```

---

## 36. MemoryWritePolicy

MemoryWritePolicy 决定什么值得写入。

```kotlin
class MemoryWritePolicy {

    fun shouldWriteEpisode(
        episode: EpisodicMemoryCandidate
    ): Boolean {
        return episode.importance >= 0.55f &&
               episode.content.isNotBlank()
    }

    fun shouldUpdateRelationship(
        signal: RelationshipSignal
    ): Boolean {
        return kotlin.math.abs(signal.deltaTrust) >= 0.08f ||
               kotlin.math.abs(signal.deltaDeception) >= 0.08f ||
               kotlin.math.abs(signal.deltaCooperation) >= 0.08f
    }

    fun shouldCreateReflectionCandidate(
        candidate: ReflectionCandidate
    ): Boolean {
        return candidate.importance >= 0.65f
    }

    fun shouldCreateSemanticMemory(
        reflection: ReflectionResult
    ): Boolean {
        return reflection.confidence >= 0.75f &&
               reflection.longTermValue >= 0.7f
    }
}
```

---

## 37. 为什么需要 MemoryWritePolicy

如果没有写入策略，就会出现：

```text
本局临时怀疑 7 号是狼
结果永久记住：7 号不可信
```

这会造成：

- 长期人格污染
- 错误关系固化
- 误判被永久化
- 记忆质量下降
- Agent 越玩越偏

所以：

```text
当前推理不等于长期记忆
```

只有经过 Reflection 或高质量证据验证的内容，才能进入长期记忆。

---

## 38. Relationship 更新机制

Relationship Memory 不应该直接由一句话决定。

应该由多种信号累计更新。

```kotlin
data class RelationshipSignal(
    val agentId: String,
    val targetAgentId: String,

    val deltaTrust: Float = 0f,
    val deltaDeception: Float = 0f,
    val deltaCooperation: Float = 0f,
    val deltaConflict: Float = 0f,

    val evidence: String,
    val confidence: Float,
    val sourceGameId: String,
    val createdAt: Long
)
```

---

## 39. RelationshipUpdater

```kotlin
class RelationshipUpdater {

    fun applySignal(
        current: RelationshipMemory,
        signal: RelationshipSignal
    ): RelationshipMemory {

        return current.copy(
            trustScore = (current.trustScore + signal.deltaTrust)
                .coerceIn(0f, 1f),

            deceptionScore = (current.deceptionScore + signal.deltaDeception)
                .coerceIn(0f, 1f),

            cooperationScore = (current.cooperationScore + signal.deltaCooperation)
                .coerceIn(0f, 1f),

            conflictScore = (current.conflictScore + signal.deltaConflict)
                .coerceIn(0f, 1f),

            evidenceCount = current.evidenceCount + 1,

            lastUpdated = System.currentTimeMillis()
        )
    }
}
```

---

## 40. Relationship 更新示例

游戏中发生：

```text
4号连续两轮替我解释，并且投票方向和我一致。
```

RelationshipSignal：

```json
{
  "targetAgentId": "player_4",
  "deltaTrust": 0.08,
  "deltaCooperation": 0.12,
  "deltaConflict": -0.03,
  "evidence": "4号在白天发言中替我解释，并投票方向一致",
  "confidence": 0.75
}
```

Memory System 内部更新 RelationshipMemory。

---

## 41. Episodic 写入机制

不是所有事件都写入 Episodic Memory。

适合写入：

- 关键发言
- 跳身份
- 强势带票
- 投票反转
- 夜间行动结果
- 自己被欺骗
- 自己成功欺骗别人
- 对局胜负关键节点
- 高重要度情绪事件

不适合写入：

- 普通寒暄
- 低价值重复发言
- 无关 UI 操作
- 低置信度噪声
- 临时无意义猜测

---

## 42. EpisodeExtractor

```kotlin
class EpisodeExtractor {

    fun extract(
        request: MemoryUpdateRequest
    ): List<EpisodicMemoryCandidate> {

        val fromEvents = request.events.mapNotNull { event ->
            if (isImportantEvent(event)) {
                EpisodicMemoryCandidate.fromEvent(
                    agentId = request.agentId,
                    roomId = request.roomId,
                    gameId = request.gameId,
                    event = event
                )
            } else {
                null
            }
        }

        val fromDecision = request.decision?.let {
            extractFromDecision(request, it)
        } ?: emptyList()

        return fromEvents + fromDecision
    }

    private fun isImportantEvent(event: GameEvent): Boolean {
        return event.importance >= 0.55f ||
               event.type in setOf(
                   GameEventType.PLAYER_CLAIM_ROLE,
                   GameEventType.PLAYER_VOTED,
                   GameEventType.PLAYER_DIED,
                   GameEventType.ROLE_REVEALED
               )
    }
}
```

---

## 43. Reflection Pipeline

游戏结束后触发 Reflection。

```text
Game End
    ↓
Load Game Summary
    ↓
Load Working Memory
    ↓
Load Important Episodes
    ↓
Generate Reflection
    ↓
Extract Long-term Lessons
    ↓
Write Reflection Memory
    ↓
Maybe Create Semantic Memory
    ↓
Update Relationship Memory
    ↓
Clear Working Memory
```

---

## 44. ReflectionGenerator

```kotlin
class ReflectionGenerator(
    private val llm: LlmRuntime
) {

    suspend fun generateReflection(
        agentId: String,
        gameSummary: String,
        workingMemory: WorkingMemorySnapshot,
        importantEpisodes: List<MemorySnippet>
    ): ReflectionResult {

        val prompt = """
        你是一个狼人杀 AI Agent 的自我反思模块。

        请根据本局游戏总结、当前局工作记忆、关键事件，分析：

        1. 本局为什么成功或失败
        2. 哪些判断是正确的
        3. 哪些判断是错误的
        4. 哪些玩家表现出可信/欺骗/合作/敌对倾向
        5. 哪些经验值得进入长期记忆
        6. 哪些只是本局偶然情况，不应该进入长期记忆

        输出结构化 JSON。
        """.trimIndent()

        return llm.chatStructured(
            prompt = prompt,
            input = mapOf(
                "gameSummary" to gameSummary,
                "workingMemory" to workingMemory,
                "importantEpisodes" to importantEpisodes
            )
        )
    }
}
```

---

## 45. ReflectionResult

```kotlin
data class ReflectionResult(
    val summary: String,

    val correctJudgements: List<String>,

    val wrongJudgements: List<String>,

    val relationshipSignals: List<RelationshipSignal>,

    val semanticLessons: List<SemanticMemoryCandidate>,

    val confidence: Float,

    val longTermValue: Float
)
```

---

## 46. Semantic Memory Consolidation

Semantic Memory 不应该由单个事件直接生成。

更推荐：

```text
多个 Episode / Reflection 反复出现
    ↓
形成 Pattern
    ↓
生成 Semantic Memory
```

例如：

```text
多局中发现：
强势带票且不给理由的玩家，经常是狼人或搅局者。
```

最终形成：

```text
我应该警惕没有充分逻辑支撑的强势带票行为。
```

---

## 47. MemoryConsolidationService

```kotlin
class MemoryConsolidationService(
    private val episodeStore: EpisodicMemoryStore,
    private val reflectionStore: ReflectionMemoryStore,
    private val semanticStore: SemanticMemoryStore
) {

    suspend fun consolidate(
        agentId: String
    ): Int {

        val patterns = findRepeatedPatterns(agentId)

        val candidates = patterns.map {
            SemanticMemoryCandidate(
                agentId = agentId,
                type = "strategy_lesson",
                content = it.summary,
                confidence = it.confidence,
                importance = it.importance,
                source = "consolidation"
            )
        }

        val filtered = candidates.filter {
            it.confidence >= 0.75f && it.importance >= 0.65f
        }

        semanticStore.saveAll(filtered)

        return filtered.size
    }

    private suspend fun findRepeatedPatterns(
        agentId: String
    ): List<MemoryPattern> {
        // 从 Episode / Reflection 中挖掘重复模式
        return emptyList()
    }
}
```

---

## 48. Memory Decay

记忆不是永久有效。

需要衰减机制。

应该考虑：

- 时间
- 重要性
- 置信度
- 使用频率
- 是否被后续事件证伪
- 是否被 Reflection 强化
- 是否与当前人格核心相关

---

## 49. MemoryDecayPolicy

```kotlin
class MemoryDecayPolicy {

    fun calculateDecay(
        memory: MemoryMetadata,
        now: Long
    ): Float {

        val ageDays = (now - memory.updatedAt) / (1000f * 60f * 60f * 24f)

        val timeDecay = ageDays * 0.01f

        val importanceProtection = memory.importance * 0.4f

        val usageProtection = memory.accessCount * 0.02f

        val confidenceProtection = memory.confidence * 0.2f

        return (timeDecay - importanceProtection - usageProtection - confidenceProtection)
            .coerceAtLeast(0f)
    }
}
```

---

## 50. MemoryMaintenanceService

```kotlin
class MemoryMaintenanceService(
    private val decayService: MemoryDecayService,
    private val consolidationService: MemoryConsolidationService,
    private val pruningService: MemoryPruningService
) {

    suspend fun maintain(
        request: MemoryMaintenanceRequest
    ): MemoryMaintenanceResult {

        val decayed = decayService.decay(request.agentId)

        val consolidated = consolidationService.consolidate(request.agentId)

        val pruned = pruningService.prune(request.agentId)

        return MemoryMaintenanceResult(
            decayedMemories = decayed,
            consolidatedMemories = consolidated,
            prunedMemories = pruned
        )
    }
}
```

---

## 51. MemoryMaintenanceRequest

```kotlin
data class MemoryMaintenanceRequest(
    val agentId: String,
    val reason: MemoryMaintenanceReason
)

enum class MemoryMaintenanceReason {
    AFTER_GAME_END,
    DAILY_SCHEDULED,
    MANUAL,
    LOW_STORAGE,
    BEFORE_CONTEXT_BUILD
}
```

---

## 52. Retrieval Pipeline

推理前，Memory System 构建 AgentMemoryContext。

```text
MemoryContextRequest
    ↓
Query Rewrite
    ↓
Multi Retrieval
    ↓
Relationship Load
    ↓
Working Memory Load
    ↓
Rerank
    ↓
Context Compression
    ↓
AgentMemoryContext
```

---

## 53. Multi Retrieval

同时检索：

- Working Memory
- Episodic Memory
- Semantic Memory
- Relationship Memory
- Reflection Memory

但注意：

```text
外部不直接调用这些 Retriever
```

外部只调用：

```text
AgentMemoryService.getMemoryContext()
```

---

## 54. Retrieval 内部模块

```text
MemoryContextProvider
MemoryQueryBuilder
WorkingMemoryRetriever
SemanticRetriever
EpisodicRetriever
RelationshipRetriever
ReflectionRetriever
MemoryReranker
MemoryContextCompressor
```

---

## 55. MemoryContextProvider

```kotlin
class MemoryContextProvider(
    private val queryBuilder: MemoryQueryBuilder,
    private val workingRetriever: WorkingMemoryRetriever,
    private val semanticRetriever: SemanticRetriever,
    private val episodicRetriever: EpisodicRetriever,
    private val relationshipRetriever: RelationshipRetriever,
    private val reflectionRetriever: ReflectionRetriever,
    private val reranker: MemoryReranker,
    private val compressor: MemoryContextCompressor
) {

    suspend fun buildContext(
        request: MemoryContextRequest
    ): AgentMemoryContext {

        val query = queryBuilder.build(request)

        val working = if (request.includeWorkingMemory) {
            workingRetriever.loadSnapshot(
                roomId = request.roomId,
                gameId = request.gameId,
                agentId = request.agentId
            )
        } else null

        val semantic = if (request.includeSemanticMemory) {
            semanticRetriever.retrieve(request.agentId, query)
        } else emptyList()

        val episodic = if (request.includeEpisodicMemory) {
            episodicRetriever.retrieve(request.agentId, query)
        } else emptyList()

        val relationship = if (request.includeRelationshipMemory) {
            relationshipRetriever.retrieve(
                agentId = request.agentId,
                targetIds = request.visiblePlayerIds
            )
        } else emptyList()

        val reflection = if (request.includeReflectionMemory) {
            reflectionRetriever.retrieve(request.agentId, query)
        } else emptyList()

        val reranked = reranker.rank(
            query = query,
            memories = semantic + episodic + reflection
        )

        return compressor.compress(
            request = request,
            working = working,
            semantic = semantic,
            episodic = episodic,
            relationship = relationship,
            reflection = reflection,
            reranked = reranked
        )
    }
}
```

---

## 56. Context Compression

不能把所有记忆都塞给 LLM。

需要压缩。

压缩目标：

```text
在 token 预算内，保留最有价值的信息。
```

优先级建议：

```text
1. 当前局 Working Memory
2. 与当前玩家相关的 Relationship Memory
3. 高相关 Semantic Memory
4. 高相关 Episodic Memory
5. 最近 Reflection Memory
```

---

## 57. ReasoningContext

Reasoning 时使用：

```text
ReasoningContext = GameContext + AgentMemoryContext
```

```kotlin
data class ReasoningContext(
    val gameContext: GameContext,
    val memoryContext: AgentMemoryContext,
    val taskType: ReasoningTaskType
)
```

---

## 58. Prompt Assembly

推荐 Prompt 结构：

```text
[System Persona]

[Current Game Context]

[Current Goal]

[Working Memory]

[Relationship Knowledge]

[Relevant Semantic Memory]

[Relevant Past Events]

[Reflection Lessons]

[Recent Dialogue]

[Current Task]

[Output Format]
```

---

## 59. PromptBuilder

```kotlin
class PromptBuilder {

    fun build(
        context: ReasoningContext
    ): String {
        return buildString {

            appendLine("# System Persona")
            appendLine(context.memoryContext.personaSnapshot.toPromptText())

            appendLine("# Current Game Context")
            appendLine(context.gameContext.toPromptText())

            appendLine("# Working Memory")
            appendLine(context.memoryContext.workingMemory?.toPromptText() ?: "无")

            appendLine("# Relationship Knowledge")
            appendLine(context.memoryContext.relationshipContext.toPromptText())

            appendLine("# Semantic Memory")
            appendLine(context.memoryContext.semanticContext.toPromptText())

            appendLine("# Relevant Past Events")
            appendLine(context.memoryContext.episodicContext.toPromptText())

            appendLine("# Reflection Lessons")
            appendLine(context.memoryContext.reflectionContext.toPromptText())

            appendLine("# Current Task")
            appendLine(context.taskType.name)

            appendLine("# Output Format")
            appendLine("请输出结构化 AgentDecision JSON。")
        }
    }
}
```

---

## 60. State Machine

狼人杀状态：

```text
Lobby
RoleAssign
DayDiscussion
Vote
NightAction
Reflection
Summary
```

每个状态拥有：

- 独立 Prompt
- 独立 Retrieval 策略
- 独立 Working Memory 更新策略
- 独立行为策略

---

## 61. GameState

```kotlin
sealed class GameState {

    object Lobby : GameState()

    object RoleAssign : GameState()

    object DayDiscussion : GameState()

    object Vote : GameState()

    object NightAction : GameState()

    object Reflection : GameState()

    object Summary : GameState()
}
```

---

## 62. AgentRuntime 最终推荐结构

```kotlin
class AgentRuntime(
    private val gameContextProvider: GameContextProvider,
    private val agentMemoryService: AgentMemoryService,
    private val reasoningContextAssembler: ReasoningContextAssembler,
    private val reasoningEngine: ReasoningEngine,
    private val gameActionExecutor: GameActionExecutor
) {

    suspend fun onTurn(
        roomId: String,
        gameId: String,
        agentId: String,
        input: GameInput
    ): AgentDecision {

        val gameContext = gameContextProvider.build(
            roomId = roomId,
            gameId = gameId,
            agentId = agentId,
            input = input
        )

        val memoryContext = agentMemoryService.getMemoryContext(
            MemoryContextRequest(
                agentId = agentId,
                roomId = roomId,
                gameId = gameId,
                phase = gameContext.phase,
                taskType = input.taskType,
                currentInput = input.text,
                gameContextSummary = gameContext.summary,
                visiblePlayerIds = gameContext.visiblePlayerIds
            )
        )

        val reasoningContext = reasoningContextAssembler.assemble(
            gameContext = gameContext,
            memoryContext = memoryContext,
            taskType = input.taskType
        )

        val decision = reasoningEngine.reason(reasoningContext)

        gameActionExecutor.execute(
            gameContext = gameContext,
            decision = decision
        )

        agentMemoryService.updateMemory(
            MemoryUpdateRequest(
                agentId = agentId,
                roomId = roomId,
                gameId = gameId,
                phase = gameContext.phase,
                events = gameContext.newEvents,
                dialogues = decision.dialogues,
                decision = decision,
                reasoningSummary = decision.reasoningSummary,
                updateReason = MemoryUpdateReason.AFTER_DECISION
            )
        )

        return decision
    }
}
```

---

## 63. AgentDecision

```kotlin
data class AgentDecision(
    val actionType: AgentActionType,

    val speech: String? = null,

    val voteTargetId: String? = null,

    val nightActionTargetId: String? = null,

    val reasoningSummary: String,

    val confidence: Float,

    val workingMemoryPatch: WorkingMemoryPatch,

    val dialogues: List<Dialogue> = emptyList()
)
```

---

## 64. ReasoningEngine

```kotlin
class ReasoningEngine(
    private val promptBuilder: PromptBuilder,
    private val llmRuntime: LlmRuntime,
    private val decisionParser: DecisionParser
) {

    suspend fun reason(
        context: ReasoningContext
    ): AgentDecision {

        val prompt = promptBuilder.build(context)

        val raw = llmRuntime.chat(prompt)

        return decisionParser.parse(raw)
    }
}
```

---

## 65. Memory System 内部实现

推荐内部结构：

```text
memory/
  AgentMemoryService
  DefaultAgentMemoryService

memory/context/
  MemoryContextProvider
  MemoryQueryBuilder
  MemoryContextCompressor
  MemoryReranker

memory/update/
  MemoryUpdatePipeline
  WorkingMemoryUpdater
  WorkingMemoryPatchApplier
  EpisodeExtractor
  RelationshipSignalExtractor
  ReflectionCandidateCollector
  MemoryWritePolicy

memory/maintenance/
  MemoryMaintenanceService
  MemoryDecayService
  MemoryConsolidationService
  MemoryPruningService

memory/store/
  WorkingMemoryStore
  EpisodicMemoryStore
  SemanticMemoryStore
  RelationshipMemoryStore
  ReflectionMemoryStore

memory/model/
  WorkingMemory
  EpisodicMemory
  SemanticMemory
  RelationshipMemory
  ReflectionMemory
  AgentMemoryContext
  MemorySnippet
```

---

## 66. 数据库存储建议

### 66.1 ObjectBox

负责：

- AgentProfile
- Agent Runtime State
- Working Memory
- Relationship Memory
- State Cache

### 66.2 sqlite-vector

负责：

- Semantic Memory 向量检索
- Episodic Memory 向量检索
- Reflection Memory 向量检索
- Hybrid Search

### 66.3 普通 SQLite / ObjectBox

负责：

- Memory Metadata
- Access Count
- Confidence
- Importance
- Decay Score
- Last Access Time

---

## 67. Android 推荐技术栈

### 核心框架

```text
Kotlin
Coroutines
Flow
```

### 本地数据库

```text
ObjectBox
SQLite
sqlite-vector
```

### AI Runtime

```text
llama.cpp
ONNX Runtime
```

### AI 子模块

```text
Local LLM
Embedding Model
Rerank Model
Classification Model
```

---

## 68. Memory Lifecycle

完整生命周期：

```text
Create
    ↓
Retrieve
    ↓
Use
    ↓
Update Access Metadata
    ↓
Reinforce / Decay
    ↓
Reflect
    ↓
Consolidate
    ↓
Prune / Forget
```

---

## 69. 什么时候写入长期记忆

适合写入长期记忆：

- 多次重复出现的行为模式
- 对 Agent 人格有影响的事件
- 被 Reflection 确认为长期有效的经验
- 与某个 Agent 长期关系相关的证据
- 高置信度的策略经验
- 游戏胜负的关键原因

不适合写入长期记忆：

- 本局临时猜测
- 低置信度推理
- 未验证怀疑
- 噪声对话
- 普通寒暄
- 只在当前局有效的信息
- 与长期人格无关的细节

---

## 70. Working Memory 清理策略

游戏结束后：

```text
Working Memory 不直接变成长期记忆
```

正确流程：

```text
Working Memory
    ↓
Reflection
    ↓
筛选长期经验
    ↓
写入 Reflection / Semantic / Relationship
    ↓
清理 Working Memory
```

接口：

```kotlin
suspend fun clearWorkingMemory(
    request: ClearWorkingMemoryRequest
): ClearWorkingMemoryResult
```

---

## 71. ClearWorkingMemoryRequest

```kotlin
data class ClearWorkingMemoryRequest(
    val agentId: String,
    val roomId: String,
    val gameId: String,
    val archiveBeforeClear: Boolean = true
)
```

---

## 72. 关键反例

错误设计：

```text
ReasoningEngine 直接查数据库
ReasoningEngine 直接写 SemanticMemory
AgentRuntime 直接操作 VectorStore
GameSystem 直接修改 RelationshipMemory
LLM 直接输出完整 WorkingMemory
每轮对话都写入长期记忆
当前局误判直接变成长期认知
```

正确设计：

```text
外部只调用 AgentMemoryService
推理前请求 AgentMemoryContext
推理后提交 MemoryUpdateRequest
Memory System 内部决定如何检索、压缩、写入、反思、维护
Working Memory 用 Patch 更新
长期记忆由 Reflection / Consolidation 生成
```

---

## 73. 最终原则

整个系统最重要的原则：

```text
机器人记忆绑定 Agent，不绑定游戏。
游戏上下文绑定 Room/Game，不进入长期人格。
推理时临时合并：
ReasoningContext = GameContext + AgentMemoryContext。
推理结束后，由 Memory System 决定如何更新记忆。
外部不关心 Memory System 内部实现。
```

---

## 74. 最终目标

构建：

```text
具有持续人格演化能力的 AI Agent
```

而不是：

```text
只会聊天的 Prompt Bot
```

真正重要的不是：

```text
向量检索速度
```

而是：

```text
什么值得记住
什么应该遗忘
什么形成长期人格
什么只服务当前局
什么应该通过 Reflection 进入长期认知
```

---

## 75. 最终推荐代码调用模型

```text
AgentRuntime.onTurn()
    ↓
GameContextProvider.build()
    ↓
AgentMemoryService.getMemoryContext()
    ↓
ReasoningContextAssembler.assemble()
    ↓
ReasoningEngine.reason()
    ↓
GameActionExecutor.execute()
    ↓
AgentMemoryService.updateMemory()
    ↓
MemoryUpdatePipeline
    ↓
WorkingMemory / Episodic / Relationship / Reflection
```

这样系统边界清晰，后续可以自由替换：

- 向量数据库
- 本地 LLM
- Embedding 模型
- Rerank 模型
- 记忆压缩策略
- 关系更新算法
- Reflection 策略
- Decay 策略
- 存储方案

外部系统不需要跟着改。

---

# 附录 A：核心数据模型汇总

## A.1 MemorySnippet

```kotlin
data class MemorySnippet(
    val id: String,
    val type: MemoryType,
    val content: String,
    val relevanceScore: Float,
    val importance: Float,
    val confidence: Float,
    val createdAt: Long
)
```

## A.2 MemoryType

```kotlin
enum class MemoryType {
    WORKING,
    EPISODIC,
    SEMANTIC,
    RELATIONSHIP,
    REFLECTION
}
```

## A.3 ReasoningTaskType

```kotlin
enum class ReasoningTaskType {
    GENERATE_SPEECH,
    CHOOSE_VOTE_TARGET,
    NIGHT_ACTION,
    ANALYZE_PLAYER,
    RESPOND_TO_ACCUSATION,
    FORM_ALLIANCE,
    REFLECT_GAME
}
```

## A.4 GamePhase

```kotlin
enum class GamePhase {
    Lobby,
    RoleAssign,
    DayDiscussion,
    Vote,
    NightAction,
    Reflection,
    Summary
}
```

---

# 附录 B：一句话架构总结

```text
Game System 提供当前事实。
Memory System 提供机器人认知。
Reasoning System 生成当前决策。
Memory System 再吸收新经验。
Agent Runtime 只负责编排。
```
