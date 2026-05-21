# 狼人杀 AI 机器人玩家行动输出 Schema

更新时间：2026-05-20

本文定义行动类模型返回的 JSON 结构。发言类行动不使用本文 schema，直接返回纯文本。行动类请求会随模型请求下发 provider 级 JSON Schema，解析器仍会做本地校验。

## 基本规则

- 行动类模型返回必须是一个 JSON 对象，不能包在 Markdown 代码块里。
- `action` 必须来自当前 `allowedActions`。
- 需要选择目标的行动，目标必须来自 schema 构建器生成的合法目标集合。
- 目标只使用 `targetSeatNumber`，它表示房间槽位编号，也就是狼人杀席位编号。
- 解析器只读取 `targetSeatNumber` 作为目标字段。
- `targetSeatNumber` 必须是 JSON number，不接受字符串。
- 行动类 JSON 只允许 `action`、`targetSeatNumber` 两个字段。
- 模型返回只是候选结果，解析后仍必须由狼人杀房间模块校验。
- 不允许返回理由、调试理由、玩家内部 ID 或其它扩展字段。

## 通用字段

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `action` | string | 是 | 当前行动。 |
| `targetSeatNumber` | number | 按行动 | 目标槽位编号，必须来自本次合法目标集合。 |

## 单目标行动

适用行动：

- `wolf_kill`
- `guard_protect`
- `seer_check`
- `sheriff_vote`
- `vote`
- `mvp_vote`

要求：

- `action` 必须等于当前行动类型。
- 必须返回 `targetSeatNumber`。
- `targetSeatNumber` 必须来自本次合法目标集合。
- 解析器不读取重复目标字段。

示例：

```json
{
  "action": "vote",
  "targetSeatNumber": 5
}
```

## 警长发言顺序

警长发言顺序行动从 `allowedActions` 中选择方向：

- `sheriff_speech_order_clockwise`
- `sheriff_speech_order_counterclockwise`

要求：

- `action` 表示发言方向，`sheriff_speech_order_clockwise` 为顺时针，`sheriff_speech_order_counterclockwise` 为逆时针。
- 必须返回 `targetSeatNumber`。
- `targetSeatNumber` 表示白天第一位发言玩家的座位号，必须来自本次合法目标集合。
- 不新增方向字段；解析器只读取 `action` 和 `targetSeatNumber`。

示例：

```json
{
  "action": "sheriff_speech_order_counterclockwise",
  "targetSeatNumber": 2
}
```

## 警徽处理

警徽处理行动从 `allowedActions` 中选择：

- `sheriff_badge_pass`
- `sheriff_badge_destroy`

### 飞警徽

要求：

- `action = sheriff_badge_pass`。
- 必须返回 `targetSeatNumber`。
- `targetSeatNumber` 表示新警长座位，必须来自当前允许飞警徽的存活目标候选。
- 不能选择已经死亡的警长本人。

示例：

```json
{
  "action": "sheriff_badge_pass",
  "targetSeatNumber": 4
}
```

### 撕警徽

要求：

- `action = sheriff_badge_destroy`。
- 必须返回 `targetSeatNumber = -1`。
- 不选择任何玩家；撕毁后本局后续不再有警长、警长票权或警长指定发言顺序。

示例：

```json
{
  "action": "sheriff_badge_destroy",
  "targetSeatNumber": -1
}
```

## 女巫行动

女巫行动从 `allowedActions` 中选择：

- `witch_save`
- `witch_poison`
- `witch_skip`

### 救人

要求：

- `action = witch_save`。
- 必须返回 `targetSeatNumber`。
- `targetSeatNumber` 必须是当前女巫信息里的今晚倒牌座位。

示例：

```json
{
  "action": "witch_save",
  "targetSeatNumber": 2
}
```

### 毒人

要求：

- `action = witch_poison`。
- `targetSeatNumber` 必须来自当前允许毒的目标候选。

示例：

```json
{
  "action": "witch_poison",
  "targetSeatNumber": 7
}
```

### 跳过

要求：

- `action = witch_skip`。
- 必须返回 `targetSeatNumber = -1`。

示例：

```json
{
  "action": "witch_skip",
  "targetSeatNumber": -1
}
```

## 猎人开枪

猎人行动从 `allowedActions` 中选择：

- `hunter_shoot`
- `skip`

### 开枪

要求：

- `action = hunter_shoot`。
- 必须返回 `targetSeatNumber`。
- `targetSeatNumber` 必须来自当前允许开枪的目标候选。

示例：

```json
{
  "action": "hunter_shoot",
  "targetSeatNumber": 2
}
```

### 不开枪

要求：

- `action = skip`。
- 必须返回 `targetSeatNumber = -1`。

示例：

```json
{
  "action": "skip",
  "targetSeatNumber": -1
}
```

## 禁止返回

行动类模型不得返回：

- 多个备选目标。
- 当前行动请求之外的行动类型。
- 不在本次合法目标集合内的目标。
- 字符串形式的 `targetSeatNumber`。
- `targetPlayerId`、`playerId`、`target_index`、`target_id`、玩家内部 ID 或其它程序字段名。
- `reason`、`debugReason` 或其它解释字段。
- 除 `action`、`targetSeatNumber` 之外的任何字段。
- Markdown、自然语言解释包裹 JSON、数组根节点或空对象。

## 解析失败处理

解析失败时进入 [输出解析](output-parsing.md) 的结构化错误流程：

- 不自动选择目标。
- 不自动生成跳过结果。
- 不从自然语言中提取目标。
- 不二次请求模型修正格式。
- 直接返回结构化错误。

结构化错误不得进入房间历史、结构化记录、机器人记忆或 TTS。
