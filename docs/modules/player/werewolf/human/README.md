# 狼人杀真人玩家模块

更新时间：2026-05-21

狼人杀真人玩家模块是具体游戏真人玩家实现，负责把狼人杀房间模块发出的行动、发言和目标选择请求转换成真人可操作的 UI 交互，并把真人输入转成统一狼人杀玩家行动结果。

## 模块定位

```text
玩家模块
  -> 真人玩家模块
       -> 狼人杀真人玩家模块
            -> 行动按钮
            -> 目标选择
            -> 发言输入
            -> 跳过 / 不行动
            -> 结果回传
```

狼人杀真人玩家模块不维护狼人杀权威状态。它只消费狼人杀房间模块给出的当前请求、合法目标、可选动作和展示材料，人的选择最终仍由狼人杀房间模块校验。

## 能力边界

狼人杀真人玩家模块负责：

- 根据狼人杀指令类型打开目标确认、发言编辑、行动选择等 UI。
- 展示当前可选目标、可选动作和请求提示。
- 把真人操作转换成 `PlayerActionResult` 或 `WerewolfPlayerActionResult`。
- 把 `player_action` / `player_speech` 任务转换成页面需要的待行动/待发言状态。
- 统一生成真人设备任务结果 payload，页面层不再手写 `player_action` / `player_speech` 字段。
- 组装狼人杀真人目标确认、发言编辑、名字编辑、座位详情和头像旁白开关视图，房间页面只注入通用 UI 工厂和提交回调。
- 生成狼人杀真人准备、改名和头像旁白开关的本地状态结果，房间页面只负责网络请求、状态刷新和提交。
- 通过玩家模块可信通道把结果回传给主机端房间程序。
- 在断联恢复后配合真人玩家模块恢复待处理请求。

狼人杀真人玩家模块不负责：

- 身份分配、夜晚行动结算、白天放逐、警长流程推进和胜负判断。
- AI prompt、模型调用和机器人记忆。
- 未经狼人杀房间模块接受的发言播报或记忆写入。

## 代码归属

```text
scripts/player/werewolf/human/
  werewolf_human_player_factory.gd
  werewolf_human_player_interaction_controller.gd
  werewolf_human_player_state_controller.gd
  werewolf_human_player_task_controller.gd
```

当前设备任务展示状态和提交 payload 已收敛到 `werewolf_human_player_task_controller.gd`；目标选择、发言编辑、名字编辑、座位详情和头像旁白开关视图已收敛到 `werewolf_human_player_interaction_controller.gd`；准备、改名和头像旁白开关的真人玩家本地结果已收敛到 `werewolf_human_player_state_controller.gd`。狼人杀房间页面仍负责座位点击、网络请求、房间状态刷新、设备任务结果发送和最终游戏状态推进。
