# 狼人杀玩家文档迁移说明

更新时间：2026-05-21

狼人杀玩家实现已归入玩家模块，不再以 `docs/modules/room/werewolf/player/` 作为权威文档入口。

新的 5 个玩家模块是：

| 模块 | 文档 |
| --- | --- |
| 玩家模块 | [../../../player/README.md](../../../player/README.md) |
| 真人玩家模块 | [../../../player/human/README.md](../../../player/human/README.md) |
| AI 玩家模块 | [../../../player/ai/README.md](../../../player/ai/README.md) |
| 狼人杀真人玩家模块 | [../../../player/werewolf/human/README.md](../../../player/werewolf/human/README.md) |
| 狼人杀 AI 玩家模块 | [../../../player/werewolf/ai/README.md](../../../player/werewolf/ai/README.md) |

代码归属同步调整为：

```text
scripts/player/
  player_factory.gd
  human/
  ai/
  werewolf/
    human/
    ai/
```

`scripts/room/werewolf/` 只保留狼人杀房间权威状态、地图、阶段推进、行动校验、事件、特效和页面编排。真人玩家输入和 AI 玩家推理属于玩家模块下的具体游戏玩家实现。

