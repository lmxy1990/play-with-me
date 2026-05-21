# 狼人杀 AI 机器人玩家失败处理

更新时间：2026-05-16

本文定义模型调用、模型输出解析和结构化错误的处理顺序。失败处理的目标是暴露问题，不能伪造 AI 行动。

## 总体顺序

```text
构建输入上下文
  -> 读取 AI 玩家结构化记录队列
  -> 按当前玩家视角生成 visibleState.timeline
  -> 构建模型请求
  -> 调用模型
  -> 解析输出
  -> 成功则提交狼人杀房间模块校验
  -> 失败则返回结构化错误
```

## 失败分类

| 场景 | 处理方式 |
| --- | --- |
| 输入上下文构建失败 | 不调用模型，返回结构化错误。 |
| 结构化记录队列读取失败 | 不调用模型，返回结构化错误。 |
| 模型调用失败 | 返回结构化错误。 |
| 模型请求超时 | 返回结构化错误。 |
| 发言文本为空 | 返回结构化错误。 |
| 发言文本超长 | 返回结构化错误。 |
| 行动 JSON 无法解析 | 返回结构化错误。 |
| `action_type` 不匹配 | 返回结构化错误。 |
| 缺少必填字段 | 返回结构化错误。 |
| 目标不在合法目标集合 | 返回结构化错误。 |

## 输出解析铁律

- 行动类模型输出必须符合当前 `response_schema`，并通过本地解析器校验。
- 行动类输出必须是可解析 JSON 对象。
- 解析器不得从自由文本中猜测目标。
- 解析器不得自动选择第一个目标。
- 解析器不得自动生成跳过行动。
- 解析器不得二次请求模型修正格式。
- 解析失败说明 prompt、response schema 或模型配置存在问题，必须把错误暴露出来。

## 结构化错误

无法生成可提交结果时，返回：

```json
{
  "turn_id": "turn_042",
  "actor_seat_number": 3,
  "action_type": "vote",
  "source": "ai_model",
  "error": {
    "code": "ai_output_parse_failed",
    "message": "模型输出无法按当前 schema 解析",
    "stage": "output_parsing"
  },
  "metadata": {
    "model_request_id": "model_req_001",
    "raw_output_saved_for_debug": true
  }
}
```

错误码建议：

| 错误码 | 场景 |
| --- | --- |
| `ai_input_context_failed` | 输入上下文构建失败。 |
| `ai_record_queue_failed` | 结构化记录队列读取或压缩失败。 |
| `ai_model_request_failed` | 模型请求失败。 |
| `ai_model_timeout` | 模型请求超时。 |
| `ai_output_parse_failed` | 输出不是当前格式要求。 |
| `ai_output_action_mismatch` | `action_type` 不匹配。 |
| `ai_output_missing_field` | 缺少必填字段。 |
| `ai_output_invalid_target` | 目标不在合法目标集合。 |
| `ai_output_text_invalid` | 发言文本为空或超长。 |

## 失败后禁止事项

- 不把失败模型输出写入房间历史。
- 不把失败模型输出写入机器人记忆。
- 不把失败模型输出交给 TTS。
- 不用失败输出中的目标、身份判断或解释推进阶段。
- 不在 UI 中展示失败模型输出为玩家发言。
- 不把结构化错误伪装成玩家行动。

## 调试要求

结构化错误应保留足够的调试摘要：

- `turn_id`。
- `action_type`。
- `model_request_id`。
- 输出模式。
- 解析阶段。
- 错误码。
- 原始输出是否已保存到调试区。

原始模型输出只能进入调试区，不进入房间历史、结构化记录、记忆或 TTS。
