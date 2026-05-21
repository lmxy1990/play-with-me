# 狼人杀实现边界

更新时间：2026-05-21

本文描述狼人杀房间模块的文件归属和目标拆分。模块代码必须独立文件，具体实现必须放在模块内，对外只暴露接口能力。

## 当前相关文件

```text
scripts/room/werewolf/
  werewolf_room_module.gd
  werewolf_map_catalog.gd
  werewolf_scene_slots.gd
  werewolf_rule_state.gd
  werewolf_phase_orchestrator.gd
  werewolf_action_request_builder.gd
  werewolf_action_executor.gd
  werewolf_delivery_builder.gd
  werewolf_event_builder.gd
  werewolf_replay_builder.gd
  werewolf_recovery_builder.gd
  werewolf_asset_catalog.gd
  werewolf_device_task_channel.gd  兼容入口，实际实现归玩家模块
  werewolf_engine.gd
  werewolf_room_page_state.gd
  werewolf_room_lifecycle_page_flow.gd
  werewolf_room_table_page_flow.gd
  werewolf_room_create_page_flow.gd
  werewolf_room_progress_page_flow.gd
  werewolf_room_bot_page_flow.gd
  werewolf_room_overlay_page_flow.gd
  werewolf_room_interaction_page_flow.gd
  werewolf_room_page.gd
  table_surface.gd
  seat_card.gd
  effect_layer.gd
  maps/<map_id>/map.gd
  maps/<map_id>/role_config.gd
```

当前玩家模块相关实现已归到：

```text
scripts/player/player_factory.gd
scripts/player/player_presentation_ack_controller.gd
scripts/player/player_presentation_ack_participant_resolver.gd
scripts/player/player_presentation_ack_runtime.gd
scripts/player/player_task_channel.gd
scripts/player/player_speech_output.gd
scripts/player/human/human_player_controller.gd
scripts/player/ai/ai_player_controller.gd
scripts/player/werewolf/human/werewolf_human_player_factory.gd
scripts/player/werewolf/ai/ai_werewolf_player_runtime.gd
scripts/player/werewolf/ai/ai_werewolf_prompt_renderer.gd
scripts/player/werewolf/ai/ai_werewolf_response_schema_builder.gd
scripts/player/werewolf/ai/ai_werewolf_output_parser.gd
scripts/player/werewolf/ai/ai_werewolf_record_formatter.gd
scripts/player/werewolf/ai/ai_werewolf_turn_context_builder.gd
scripts/player/werewolf/ai/ai_werewolf_wolf_private_flow.gd
scripts/player/werewolf/ai/ai_werewolf_player_page_flow.gd
scripts/player/werewolf/ai/ai_werewolf_memory*.gd
```

目标归属：

- 规则执行留在 `scripts/room/werewolf/` 内部规则文件。
- 狼人杀真人玩家流程归 [狼人杀真人玩家模块](../../player/werewolf/human/README.md)。
- 狼人杀 AI 玩家流程归 [狼人杀 AI 玩家模块](../../player/werewolf/ai/README.md)。
- 记忆存储收敛到 [记忆模块](../../bot-management/memory-module.md)。
- 机器人上下文组装收敛到 [机器人上下文处理模块](../../bot-management/bot-context-module.md)。
- 对外机器人能力由 [机器人模块](../../bot-management/bot-module.md) 编排。

## 目标结构

```text
scripts/room/werewolf/
  werewolf_room_module.gd
  werewolf_map_catalog.gd
  werewolf_scene_slots.gd
  werewolf_rule_state.gd
  werewolf_phase_orchestrator.gd
  werewolf_action_request_builder.gd
  werewolf_action_executor.gd
  werewolf_delivery_builder.gd
  werewolf_event_builder.gd
  werewolf_replay_builder.gd
  werewolf_recovery_builder.gd
  maps/
    basic_village/
      map.gd
      role_config.gd
      phase_plan.gd
      scene_slots.gd
      action_policy.gd
      delivery_policy.gd
      replay_policy.gd
    hunter_pressure_village/
      map.gd
      role_config.gd
      phase_plan.gd
      scene_slots.gd
      action_policy.gd
      delivery_policy.gd
      replay_policy.gd
    quick_no_witch_village/
      map.gd
      role_config.gd
      phase_plan.gd
      scene_slots.gd
      action_policy.gd
      delivery_policy.gd
      replay_policy.gd
    guard_village/
      map.gd
      role_config.gd
      phase_plan.gd
      scene_slots.gd
      action_policy.gd
      delivery_policy.gd
      replay_policy.gd
    sheriff_square/
      map.gd
      role_config.gd
      phase_plan.gd
      scene_slots.gd
      action_policy.gd
      delivery_policy.gd
      replay_policy.gd
    sheriff_guard_square/
      map.gd
      role_config.gd
      phase_plan.gd
      scene_slots.gd
      action_policy.gd
      delivery_policy.gd
      replay_policy.gd
```

## 边界规则

- `werewolf_room_module.gd` 是对外入口，暴露地图、人数、槽位、开局、输入、快照、复盘和恢复接口。
- 地图目录由 `werewolf_map_catalog.gd` 汇总，具体地图数据和地图规则推理由 `maps/<map_id>/` 内部文件维护。
- 场景槽位由各地图规则包提供，公共 `werewolf_scene_slots.gd` 只放可复用布局算法。
- 阶段推进只通过 `werewolf_phase_orchestrator.gd`，页面、真人玩家和 AI 机器人玩家不直接判断下一阶段。
- 行动合法性只通过 `werewolf_action_executor.gd`，任何玩家输入都必须走这里。
- 下发数据生成只通过 `werewolf_delivery_builder.gd`，不能在 UI 中补做业务过滤。
- 事件 payload 只通过 `werewolf_event_builder.gd` 生成，房间模块只包装和分发。
- 复盘和恢复分别由 `werewolf_replay_builder.gd`、`werewolf_recovery_builder.gd` 生成，不与页面展示代码混在一起。
- 地图规则包只能被狼人杀房间模块内部入口引用，不能被房间模块、创建房间模块、玩家适配层或 UI 直接引用。
- 页面流程按 `lifecycle`、`table`、`create`、`progress`、`bot`、`overlay`、`interaction` 拆分，页面入口 `werewolf_room_page.gd` 只负责初始路由和桌面搭建。

## 运行闸门

当前页面运行层有三个会阻塞自动推进的闸门：

- 展示 ACK gate：`scripts/player/player_presentation_ack_controller.gd` 维护 gate、presentation ID、本机待 ACK 和文本等待时间；`scripts/player/player_presentation_ack_participant_resolver.gd` 维护 participant / peer 到 ACK id 的归一化和 debug 设备列表；`scripts/player/player_presentation_ack_runtime.gd` 维护本机 ACK 定时、客户端发送、host apply/drop 运行包装；`werewolf_room_page_state.gd` 只负责按狼人杀可见性和当前房间网络会话标记设备是否可见，并提供 timer、network 和 gate-open callback。中心发言面板追加主持人消息、玩家发言或行动描述后，房主按可见范围创建 gate。设备开启语音时在语音播放完成后 ACK；未开启语音时按文本长度等待，最低 5 秒后 ACK。所有应答到齐后才继续推进。
- 设备任务 gate：`scripts/player/player_task_channel.gd` 维护 `_device_task_channel` 的 pending 任务、控制 participant、投递状态、失败原因和自动推进阻塞状态；`scripts/room/werewolf/werewolf_device_task_channel.gd` 只保留旧路径兼容入口。所有需要玩家输入的发言和行动都必须经主机创建 `player_speech` 或 `player_action` 任务，路由到该玩家的控制 participant，再由该 participant 返回 `device_task_result`。狼人杀房间只负责按当前规则构造 payload、选择控制设备、路由消息和应用结果；接收设备内部再区分真人 UI 或 AI 逻辑；主机不直接调用 AI 模型。过期任务、设备不匹配和暂停中的结果必须被丢弃。
- 暂停 gate：`_werewolf.paused`。真人玩家非主动断线时设置暂停，清理展示 ACK、设备任务、机器人请求跟踪和自动推进等待态。重连后如果没有离线真人，恢复暂停并重新调度自动推进。

这三个闸门属于房间运行层，不改变狼人杀规则模块的阶段定义。规则模块仍只接受已经完成路由、已经完成展示确认并且未暂停时提交的统一行动结果。

## 断线与销毁

- 真人玩家设备断线且不是主动离开时，席位保留，玩家状态标记为“离线”，游戏暂停。
- 断线期间收到的旧 ACK、旧设备任务结果或本机 AI 模型回调不能推进游戏。
- 真人玩家重连后恢复席位状态；当所有真人玩家都在线时，清除暂停并继续调度自动推进。
- 真人玩家主动离开时清空席位；如果房间已没有真实参与者，房间模块销毁当前房间。
- AI 机器人玩家不计入设备数量，不参与展示 ACK；它依赖控制它的真人设备接收通用设备任务并在本机执行行动。

## 网络私有数据边界

- 房间快照和设备任务 payload 不得包含 `api_key`、`endpoint`、`provider`、`model`、`modelName`、`modelConfig`、`messages`、`response_schema`、`schema`、`voice`、`formt_adapter`、`format_adapter`、`output_adapter`、`reason_adapter`、`reasoning_adapter`、`temperature`、`max_output`、`max_output_tokens`、`max_context` 等模型或声音私有字段。
- 主机端只保存房间权威、玩家座位、控制设备和任务状态；模型配置、声音配置、机器人 prompt、schema 和 API Key 只存在于控制设备本机。
- AI 玩家加入房间或重连初始化时，控制设备从本机数据库读取并缓存该 AI 玩家需要的模型配置。后续行动只使用这份本机缓存；缓存缺失、数据库不可用或配置无效时，返回结构化错误并中止当前游戏流程。
- 设备任务结果只能携带本次行动结果和必要调试摘要，不得把完整模型配置或 API Key 回传给主机。

## 维护规则

- 所有规则变化先改对应地图规则包，再同步玩家适配、UI、快照、复盘和测试。
- 页面按钮、真人玩家和 AI 机器人玩家只提交行动结果，不复制规则判断。
- 新身份或阶段必须同步行动请求、输出 schema、下发策略、网络快照、TTS 触发、复盘和测试。
- 下发数据必须由地图规则包按接收者生成，不能把隐藏身份或私密行动泄露给不该知道的玩家。
- 狼人杀房间模块接受前的草稿、模型输出和临时 UI 输入不能写入历史、记忆或 TTS。
