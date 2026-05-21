# 狼人杀 AI 玩家模块

更新时间：2026-05-21

狼人杀 AI 玩家模块是具体游戏 AI 玩家实现，负责把狼人杀房间模块发出的行动、发言和夜聊请求转换成 AI 可处理的输入，再把模型输出解析成统一狼人杀玩家行动结果。

## 模块定位

```text
玩家模块
  -> AI 玩家模块
       -> 狼人杀 AI 玩家模块
            -> 狼人杀输入上下文
            -> system/user prompt
            -> response schema
            -> 模型输出解析
            -> 狼队夜聊和目标票
            -> 狼人杀记忆材料
            -> AI 页面流接入
```

狼人杀 AI 玩家模块只负责 AI 玩家如何产生一次狼人杀响应。最终行动合法性、阶段推进、特效、胜负和复盘仍由狼人杀房间模块负责。

## 能力边界

狼人杀 AI 玩家模块负责：

- 按当前座位和视角构建狼人杀 AI 输入上下文。
- 渲染 system prompt、user prompt 和 response schema。
- 调用模型管理模块完成一次模型输入输出。
- 解析文本或 JSON 输出，生成统一行动结果。
- 维护狼队夜聊、目标票和目标意图解析。
- 在狼人杀房间模块接受结果后生成记忆更新材料。

狼人杀 AI 玩家模块不负责：

- 通用机器人档案仓库、长期记忆存储和模型配置保存。
- 房间网络、主机选举、重连认证和快照同步。
- 狼人杀权威状态和行动合法性的最终裁决。
- 真人 UI 交互。

## 代码归属

```text
scripts/player/werewolf/ai/
  ai_werewolf_player_page_flow.gd
  ai_werewolf_player_runtime.gd
  ai_werewolf_prompt_renderer.gd
  ai_werewolf_response_schema_builder.gd
  ai_werewolf_output_parser.gd
  ai_werewolf_turn_context_builder.gd
  ai_werewolf_record_formatter.gd
  ai_werewolf_wolf_private_flow.gd
  ai_werewolf_target_intent.gd
  ai_werewolf_memory.gd
  ai_werewolf_memory_context.gd
  werewolf_ai_player_factory.gd
```

