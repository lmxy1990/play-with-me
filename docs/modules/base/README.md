# 基础能力模块

## 能力边界

基础能力模块提供其它模块复用的底座能力：应用路由、共享状态、通用网络通信、Socket / WebSocket 传输、网络信封、二维码生成、扫码、加密、证书认证、设备身份、Android 原生桥接和本地持久化基础。

本模块不负责大厅业务展示、创建房间表单、偏好设置 UI、房间状态编排、房间重连策略、主机选举策略、模型配置 UI、机器人记忆、TTS 配置 UI、房间桌面 UI 或狼人杀房间玩法。

## 对外接口

- `AppRouter`：页面路由和依赖注入。
- `AppState`：全局运行时状态和本地状态读写。
- `SocketTransport` / `WebSocketTransport`：通用连接、监听、发送、接收、断线信号和连接状态基础。
- `CertificateAuth`：证书、签名、公钥链或等价认证材料的通用校验基础。
- `DeviceIdentity`：设备身份、公钥派生、签名和认证基础；设备私钥由偏好设置模块生成并保存，基础能力只读取和消费。
- `RoomNetworkCodec`：房间网络消息信封和编解码基础。
- `LanRoomDiscovery`：UDP 局域网发现基础能力。
- `QrJoinPayload`：二维码 payload 构建、解析、加密和解密。
- `QrCodeGenerator`：二维码图片生成。
- `AndroidQrScanner`：Android 相机扫码桥接。
- `Android*Store` / `Android*TtsBridge`：Godot 到 Android 插件的桥接。
- `PageUiBase` / 通用 UI helper：页面共享 UI 能力。
- `PageScanJoinFlowBase`：页面层扫码加入流程、Android 扫码信号和加入处理页状态。
- `PageBookUiBase`：页面层书页弹层、覆盖层、toast 和二维码图片 helper。
- `PageRouteUiBase`：页面路由信号和跳转 helper。
- `PageAudioUiBase`：页面点击音效。
- `PageTtsUiBase`：页面声音配置仓库、预置系统 TTS 默认记录、TTS 运行时、声音目录和声音试听 helper。
- `PageModelUiBase`：页面模型配置仓库、模型调用 client、模型目录 client、模型配置列表和玩家模型配置选择 helper。
- `PageRoomDiscoveryUiBase`：页面局域网房间发现、房间列表合并、房间列表刷新和当前房间查找 helper。
- `PageIdentityUiBase`：页面偏好仓库、本机昵称、设备身份加载、网络身份注入和 Android 横屏设置 helper。
- `PageRoomNetworkUiBase`：页面房间网络会话创建、信号绑定、网络角色判断和通用拒绝发送 helper。
- `PageRoomParticipantUiBase`：页面参与者认证材料、观察者、重连令牌和网络 nonce/base64 包装 helper。
- `PageRoomReplicaUiBase`：页面房间快照应用、房间副本接收、主机候选排序、主机接管和主机切换后的重连编排 helper。
- `PageRoomJoinUiBase`：页面二维码入房、加密二维码密钥协商、重连会话保存、房主加入处理和网络消息分发 helper。
- `PageRoomHostPeerUiBase`：页面房主端 peer 准备、换座、旁观、加机器人、改名、离线和参与者控制权 helper。
- `PageTtsHistoryUiBase`：页面历史消息播报、播放声音偏好读取和桌面席位播报动效 helper。

二维码格式、扫码流程、加密协商和设备认证见 [qr_scan_join.md](qr_scan_join.md)。大厅和房间模块消费这些能力，不复制实现。房间模块可以决定如何使用连接、二维码和认证结果，但底层 socket、证书认证、扫码、加密和设备身份实现都归基础能力。

## 文件归属

```text
scripts/core/
  app_router.gd
  app_state.gd
  device_identity.gd
  config/

scripts/network/
  lan_room_discovery.gd
  room_network_codec.gd
  qr_join_payload.gd

scripts/android/
  android_qr_scanner.gd
  android_memory_store.gd
  android_model_config_store.gd

scripts/ui/
  base/page_ui_base.gd
  common/book_popup.gd
  common/book_popup_art.gd
  common/book_popup_backdrop.gd
  qr/qr_code_generator.gd
  qr/qr_scan_join_ui.gd

scripts/pages/base/
  page_werewolf_asset_ui_base.gd
  page_scan_join_flow_base.gd
  page_book_ui_base.gd
  page_route_ui_base.gd
  page_audio_ui_base.gd
  page_tts_ui_base.gd
  page_model_ui_base.gd
  page_room_discovery_ui_base.gd
  page_identity_ui_base.gd
  page_room_network_ui_base.gd
  page_room_participant_ui_base.gd
  page_room_replica_ui_base.gd
  page_room_join_ui_base.gd
  page_room_host_peer_ui_base.gd
  page_tts_history_ui_base.gd
  page_bot_profile_ui_base.gd
  page_navigation_ui_base.gd

scripts/room/werewolf/
  werewolf_asset_catalog.gd
  werewolf_room_page_state.gd

scripts/player/werewolf/ai/
  ai_werewolf_player_page_flow.gd

android_plugins/play_with_me_android/
```

房间会话、快照、参与者注册、房间副本和主机选举代码放在 `scripts/room/network/`。设计归属和文档维护以 [房间模块](../room/README.md) 为主。其中用到的 socket / WebSocket 传输、网络信封、证书认证、设备身份、二维码和加密能力归基础能力。

页面基类分层：

```text
page_ui_base.gd
  -> page_werewolf_asset_ui_base.gd
  -> page_scan_join_flow_base.gd
  -> page_book_ui_base.gd
  -> page_route_ui_base.gd
  -> page_audio_ui_base.gd
  -> page_tts_ui_base.gd
  -> page_model_ui_base.gd
  -> page_room_discovery_ui_base.gd
  -> page_identity_ui_base.gd
  -> page_room_network_ui_base.gd
  -> page_room_participant_ui_base.gd
  -> page_room_replica_ui_base.gd
  -> page_room_join_ui_base.gd
  -> page_room_host_peer_ui_base.gd
  -> page_tts_history_ui_base.gd
  -> page_bot_profile_ui_base.gd
  -> werewolf_room_page_state.gd
  -> ai_werewolf_player_page_flow.gd
  -> page_navigation_ui_base.gd
```

`page_werewolf_asset_ui_base.gd` 只包装狼人杀房间模块公开的 `werewolf_asset_catalog.gd`，用于页面层读取背景、头像和行动图标；资源路径清单归狼人杀房间模块维护。`page_scan_join_flow_base.gd` 消费二维码 payload、扫码 UI 和 Android 扫码桥接。`page_book_ui_base.gd` 消费通用弹层和 QR 图片生成能力。`page_route_ui_base.gd` 提供页面跳转信号和配置页入口。`page_audio_ui_base.gd` 提供点击音效。`page_tts_ui_base.gd` 提供声音配置仓库、预置系统 TTS 默认记录、TTS 运行时、声音目录和声音试听。`page_tts_history_ui_base.gd` 提供历史消息入队、播放声音偏好读取、历史播报队列提交和席位播报动效状态。`page_bot_profile_ui_base.gd` 提供机器人资料仓库、机器人门面和通用记忆管理器页面接入。`page_model_ui_base.gd` 提供模型配置仓库、模型配置列表、模型调用 client、模型目录 client 和玩家模型配置选择 helper；AI 玩家如何把模型结果映射成狼人杀行动，在狼人杀 AI 玩家模块。`page_room_discovery_ui_base.gd` 提供局域网房间发现、房间列表合并、房间列表刷新和当前房间查找；当前房间发布仍在导航层组合房间、玩家、设备身份和网络端口。`page_identity_ui_base.gd` 提供偏好仓库接入、本机昵称、设备身份加载、网络身份注入和 Android 横屏设置。`page_room_network_ui_base.gd` 提供房间网络会话创建、信号绑定、网络角色判断和通用拒绝发送。`page_room_participant_ui_base.gd` 包装参与者认证材料、观察者、重连令牌和网络 nonce/base64。`page_room_replica_ui_base.gd` 包装房间快照应用、房间副本接收、主机候选排序、主机接管和主机切换后的重连编排。`page_room_join_ui_base.gd` 包装二维码入房、加密二维码密钥协商、重连会话保存、房主加入处理和网络消息分发。`page_room_host_peer_ui_base.gd` 包装房主端 peer 准备、换座、旁观、加机器人、改名、离线和参与者控制权。`werewolf_room_page_state.gd` 提供狼人杀页面共享状态和房间运行时。`ai_werewolf_player_page_flow.gd` 提供狼人杀 AI 玩家页面流。`page_navigation_ui_base.gd` 继续承载页面共享状态绑定和跨页面流程装配。

## 架构设计

基础能力分为五层：

1. 应用运行时层：`app_router.gd` 创建页面并注入共享状态和运行时服务。
2. 状态和配置层：`app_state.gd`、`config_repository.gd` 提供本地状态和配置读写基础。
3. 通信基础层：socket / WebSocket 传输、网络信封、UDP 发现、消息编解码等通用通信能力。
4. 安全和扫码层：证书认证、设备身份、公私钥、签名、二维码 payload、二维码图片、扫码桥接、加密和解密。
5. 平台层：`scripts/android/` 和 Kotlin 插件处理扫码、SQLite、TTS、Kokoro/Sherpa 等原生能力。

业务模块只能消费这些接口，不直接复制二维码协议、扫码桥接、加密、认证逻辑或 Android 调用。

### 通用网络传输基础能力

```text
业务模块
  -> 基础能力 SocketTransport / WebSocketTransport
  -> 建立连接、监听连接、发送 bytes/json、接收消息、断线通知
  -> 业务模块按自己的协议解释消息
```

约定：

- 基础能力只负责通用连接、监听、发送、接收、关闭、错误和连接状态事件。
- 基础能力可以提供通用网络信封和编解码工具，但不决定房间生命周期、加入策略、广播对象、ack 语义或重连策略。
- 房间模块基于该能力实现房间级 `send`、`broadcast`、`ack`、补发、顺序号、inbox、主机重选和主机接管。
- 具体游戏房间模块决定消息 payload 的业务字段和可见性语义。

## 逻辑流程

### 应用启动

```text
main.tscn
  -> app_router.gd
  -> PreferenceRepository.ensure_preferences()
  -> AppState.load_or_create()
  -> 初始化共享运行时服务
  -> 打开 lobby 页面
```

### 二维码和扫码基础能力

```text
业务模块提供 payload 输入
  -> QrJoinPayload 构建或解析 payload
  -> 加密或解密敏感字段
  -> QrCodeGenerator 生成二维码图片
  -> AndroidQrScanner 打开相机扫码
  -> 返回结构化扫码结果
```

房间模块提供需要编码的房间业务字段，并决定加入成功后如何处理；基础能力负责二维码格式、扫码、加密、解密和认证基础。

### Android 桥接

```text
业务模块
  -> scripts/android/* bridge
  -> Godot Android singleton
  -> Kotlin 插件
  -> 结构化结果或信号
```

### 通用认证基础

```text
设备首次启动
  -> 偏好设置模块确保 preferences JSON 存在
  -> 偏好设置模块生成并保存 device_private_key
  -> DeviceIdentity 读取 device_private_key
  -> CertificateAuth / DeviceIdentity 使用证书、公钥、设备 ID 和签名完成认证基础
  -> 业务模块消费认证结果
```

约定：

- 基础能力负责证书认证、设备身份、签名校验、公钥材料和认证结果结构。
- 房间模块只消费认证结果，用它判断是否允许加入、观战、重连或参与主机候选。
- 基础能力不决定房间密码是否正确、是否满员、是否允许观战或是否可重连。

## 大厅和房间如何消费基础能力

| 模块 | 消费方式 |
| --- | --- |
| 大厅模块 | 调用扫码入口、局域网发现和路由能力；不解析二维码、不做认证。 |
| 房间模块 | 使用基础 socket / WebSocket 传输发送和接收房间消息；提供二维码 payload 需要的业务字段；消费证书和设备认证结果；编排加入策略、重连策略、广播、ack、补发和快照下发；不实现底层传输、扫码、加密、证书认证或设备身份。 |
| 创建房间模块 | 使用基础状态和路由能力，提交创建请求给房间模块。 |
| 偏好设置模块 | 保存本机昵称、头像 ID 和设备私钥；基础能力读取设备私钥用于设备身份和签名。 |

## 维护规则

- 二维码字段、加密协商、扫码 UI、设备认证和失败提示变更时，同步 [qr_scan_join.md](qr_scan_join.md)、相关测试和 Android 预过滤。
- 新网络消息先确认是通用信封能力还是业务编排消息；通用能力写基础模块，房间编排写房间模块。
- 新 Android 能力先加 Kotlin singleton，再加 Godot bridge。
- 基础能力可以提供 socket / WebSocket 传输、二维码扫描、二维码渲染、加密、证书认证和设备认证，但不决定房间能否加入、是否允许观战、是否可重连。
- 基础能力不能引用狼人杀房间模块内部实现、玩家策略或具体页面业务流程。
