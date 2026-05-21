# 工程目录结构

更新时间：2026-05-21

本文描述仓库的物理目录，也就是 Godot 工程、Android 原生插件、构建脚本、测试和生成物分别放在哪里。它不直接表达业务模块边界；业务模块边界见 [程序模块结构](../modules/README.md)。

## 两层结构

项目文档按两层理解：

- 工程目录结构：文件系统层面的目录归属，例如 `scenes/`、`scripts/`、`android_plugins/`、`tools/`。
- 程序模块结构：业务逻辑层面的职责边界，按基础能力、基础模块、小编织模块和大编织模块组织。

二者不是一一对应关系。一个业务模块可能横跨多个工程目录，例如房间模块同时涉及 `scripts/room/` 和 `scripts/room/network/`；基础二维码、扫码和认证能力同时涉及 `scripts/network/`、`scripts/ui/`、`scripts/android/` 和 Android 插件。一个工程目录也可能承载多个模块的脚本，例如 `scripts/pages/base/page_navigation_ui_base.gd` 当前仍是多个页面共享的装配入口。

## 目录内模块化约定

顶层工程目录保持现有 Godot / Android / 构建工具语义，不按业务模块重新拆顶层目录。也就是说，仍然使用 `scenes/`、`scripts/`、`assets/`、`android_plugins/`、`addons/`、`tools/`、`test/`、`docs/` 这些外层目录。

但在承载业务内容的工程目录内部，应优先按模块归属建子目录或文件。判断顺序：

1. 先判断文件是否有明确模块归属。
2. 有模块归属时，放到该工程目录下的模块路径。
3. 没有明确模块归属、确实被多个模块复用时，才放公共目录。
4. 已有文件一旦被修改，应同步判断归属并向对应模块目录落位；新文件必须按模块目录落位。

推荐口径：

| 工程目录 | 内部归档方式 |
| --- | --- |
| `scripts/` | 按运行时代码模块归档，例如 `core/model/`、`core/bot/`、`core/memory/`、`core/tts/`、`core/preferences/`、`pages/lobby/`、`player/`、`player/human/`、`player/ai/`、`player/werewolf/human/`、`player/werewolf/ai/`、`room/`、`room/werewolf/`。 |
| `scenes/` | 按页面或模块归档，例如 `lobby/`、`preferences/`、`config/model/`、`config/voice/`、`room/werewolf/`、`common/`。主入口 `main.tscn` 可以保留在根部。 |
| `assets/` | 按资源所属模块归档，例如 `images/avatars/`、`images/werewolf/backgrounds/`、`images/ui/`。跨模块资源放 `common/` 或 `ui/`。 |
| `test/` | 按测试类型和模块归档，例如 `checks/room/`、`checks/werewolf/`、`checks/model-management/`、`checks/tts-voice/`；Android 调试脚本继续放 `android/`。 |
| `docs/` | 按文档类型归档；模块设计放 `modules/<module>/`，跨模块对象放 `contracts/`，工程目录放 `project-structure/`。 |

公共目录使用要克制。`common`、`shared`、`ui`、`core` 这类目录只能放真正跨模块的基础能力或纯展示组件，不应成为业务逻辑的临时堆放点。某段逻辑一旦开始理解房间、狼人杀、机器人、模型或 TTS 的业务语义，就应放到对应模块目录。

模块代码必须按公开接口和内部实现分层落位。公开接口文件负责给其他模块调用，内部实现文件留在模块目录内；其他模块只能引用公开接口，不能直接引用对方模块的内部状态机、校验器、构建器、解析器、存储器或适配器。

## 根目录

```text
play-with-me/
  project.godot
  export_presets.cfg
  scenes/
  scripts/
  assets/
  android_plugins/
  addons/
  android/
  tools/
  test/
  builds/
  docs/
```

## Godot 工程

| 目录 | 归属 | 说明 |
| --- | --- | --- |
| `project.godot` | Godot 项目配置 | 主场景、窗口、渲染、插件启用等配置。 |
| `export_presets.cfg` | Godot 导出配置 | Android debug/release 导出预设。 |
| `scenes/` | Godot 场景 | 应用主场景、页面场景和通用弹层场景。 |
| `scripts/` | GDScript 源码 | 运行时逻辑、页面、网络、房间、Android 桥接、UI helper。 |
| `assets/` | 运行时资源 | 背景、头像、动作图标、UI 位图和 Godot `.import` 资源。 |

主入口是 `scenes/main.tscn`，挂载 `scripts/core/app_router.gd`。路由器创建页面，并注入共享 `AppState` 和 `RoomNetworkSession`。

## GDScript 目录

```text
scripts/core/          路由、共享状态、配置、模型、机器人、记忆、TTS
scripts/network/       UDP 发现、网络信封、二维码 payload
scripts/pages/         大厅、配置页、复盘页
scripts/player/        玩家模块：父级玩家、真人玩家、AI 玩家和具体游戏玩家实现
scripts/room/          房间通用运行时和房间网络编排
scripts/room/network/  WebSocket 会话、快照、重连副本、参与者注册、房主接管
scripts/room/werewolf/ 狼人杀房间模块、当前房间页面和玩法表现
scripts/android/       Godot 到 Android 插件的桥接
scripts/ui/            通用 UI 基类、通用弹层、二维码生成、扫码处理 UI
```

当前归档状态：页面脚本已经放到 `scripts/pages/` 和 `scripts/room/werewolf/`，通用 UI 放到 `scripts/ui/base/`、`scripts/ui/common/` 和 `scripts/ui/qr/`，房间网络编排已放到 `scripts/room/network/`，玩家模块已落到 `scripts/player/`。大厅主渲染在 `scripts/pages/lobby/lobby_page_flow.gd`；狼人杀房间桌面拆为 `werewolf_room_progress_page_flow.gd`、`werewolf_room_bot_page_flow.gd`、`werewolf_room_overlay_page_flow.gd` 和 `werewolf_room_interaction_page_flow.gd`。玩家层已承载玩家工厂、玩家任务通道、展示 ACK 控制器、ACK 运行包装和玩家语音输出适配；狼人杀 AI 玩家的上下文构建、记录格式化、狼队夜聊、prompt/schema、模型输出解析、设备任务响应和记忆写入流程归到 `scripts/player/werewolf/ai/`；狼人杀真人玩家能力逐步向 `scripts/player/werewolf/human/` 收敛。基础模型请求、结构兼容、思考兼容和 provider 差异归到 `scripts/core/model/`。`scripts/pages/base/page_navigation_ui_base.gd` 只保留页面生命周期、初始路由、退出清理和帧循环；继续拆分时，应把业务规则和模块专属流程放回对应模块目录，只在 `scripts/ui/` 保留纯展示和基础 UI 能力。

## Android 工程

| 目录 | 归属 | 说明 |
| --- | --- | --- |
| `android_plugins/play_with_me_android/` | Android 原生插件源码 | Kotlin、CameraX、ML Kit、SQLite、系统 TTS、Kokoro/Sherpa、本地 native。 |
| `addons/play_with_me_android/` | Godot Android 插件产物 | Godot export plugin、debug/release AAR。 |
| `android/` | Godot Android 构建工作目录 | Godot 导出和 Gradle 构建生成内容，不作为业务源码维护。 |
| `classes.jar` | Android/Godot 依赖产物 | 构建相关文件，不承载业务逻辑。 |

新增 Android 能力时，Kotlin 插件源码放在 `android_plugins/play_with_me_android/`，Godot 桥接放在 `scripts/android/`，AAR 同步到 `addons/play_with_me_android/bin/`。

## 工具、测试和产物

| 目录 | 归属 | 说明 |
| --- | --- | --- |
| `tools/` | 开发脚本 | Godot 检查、Android 插件构建、APK 导出、安装等 PowerShell 脚本。 |
| `test/checks/` | Godot 检查脚本 | 单元/集成检查入口，通过 `tools/run_godot_check.ps1` 执行。 |
| `test/android/` | Android 调试脚本 | adb 调试、TTS debug broadcast 等。 |
| `test/demo/` | demo 截图和验证素材 | 只用于验证和展示，不进入运行时逻辑。 |
| `builds/` | 构建输出和日志 | APK、导出日志、设备截图、临时 sqlite 等生成物。 |

测试、demo、调试脚本只放在 `test/`。运行时目录不应混入测试 fixture、测试按钮或 demo 数据。

## 生成目录

以下目录由 Godot、Gradle 或设备调试流程生成，通常不作为设计文档和业务源码的入口：

```text
.godot/
.godot_user/
android/build/
android_plugins/play_with_me_android/play-with-me-android/build/
builds/
play-with-me-debug/
```

需要排查构建或设备问题时可以查看这些目录；业务设计、模块边界和源代码维护不要依赖其中的生成文件。

## 文档归属

```text
docs/
  README.md                    文档总入口
  project-structure/README.md  工程目录结构
  architecture.md              运行时整体架构
  modules/README.md            程序模块结构
  modules/<module>/README.md   模块内部设计
  build_deployment.md          构建部署
  maintenance.md               维护规则
  archive/                     归档设计
```

新增文档时先判断它描述的是工程目录、模块逻辑、专题细节还是历史资料，再放入对应目录。不要把模块细节直接堆在 `docs/` 根目录。

