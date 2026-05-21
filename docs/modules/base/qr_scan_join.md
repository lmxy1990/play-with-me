# 二维码、扫码、加密与认证专题

本文档记录二维码生成、Android 扫码、Godot 扫码 UI、加密协商、设备认证、入房前检查、失败提示和代码视图。它属于 [基础能力模块](README.md) 的专题文档；大厅和房间只编排这些基础能力完成扫码加入，不拥有二维码、扫码、加密或认证实现。

本文保留端到端扫码加入链路视图。其中房间 ID、密码、加入 token、人数、观战和生命周期等业务校验由 [房间模块](../room/README.md) 执行；本专题只定义基础能力如何承载、传递和展示这些结果。

## 模块目标

- 二维码明文只暴露连接房主所需的 `IP:端口`。
- `room_id`、房间密码或加入 token、观战标记、房主设备身份、游戏房间模块、地图和背景图等房间信息放入加密区。
- 大厅点击扫码按钮后直接打开相机，不先弹窗。
- 相机页持续读取摄像头帧，只识别房间二维码；扫到非房间码时保持扫描。
- 扫到合法房间二维码后进入“加入房间”处理页，显示正在加入动画。
- 加入过程中依次提示网络可达、设备认证、二维码密钥协商、解密、协议版本、房间 ID、密码、人数、观战策略和游戏状态等结果。
- 所有关键失败点都返回明确提示，方便用户处理，也方便通过日志定位。

## 功能范围

当前模块覆盖以下功能：

- 房主生成玩家加入二维码和观战二维码。
- 当前安全二维码：明文地址 + 加密房间信息。
- Android 原生相机扫码，使用 CameraX 连续帧分析和 ML Kit QR Code 识别。
- Godot Android 插件桥接扫码成功、失败、取消事件。
- Godot 扫码处理中 UI、等待动画、手动粘贴加入码调试入口。
- 扫码后的 WebSocket 连接、设备身份认证、RSA 密钥协商、AES 解密，并生成可交给房间模块的玩家加入或观战加入请求。
- 接收房间模块的加入策略结果，并把房间 ID、密码、人数、观战限制和游戏状态等拒绝原因映射为用户提示。
- Debug 日志和自动化检查。

不属于本专题的功能：

- 局域网房间列表发现，见 `scripts/network/lan_room_discovery.gd`。
- 房间状态、断线重连和房主接管，归房间模块主文档维护，见 [room/README.md](../room/README.md)。
- 房间内玩法同步和狼人杀房间模块，见 `scripts/room/werewolf/`。

## 技术架构

扫码加入链路按职责分为 7 层：

```text
房主桌面二维码层
  werewolf_room_page.gd::_open_qr()
  page_navigation_ui_base.gd::_build_join_payload()
  page_book_ui_base.gd::_fake_qr()
  qr_join_payload.gd::build_secure_encoded()
  qr_code_generator.gd

扫码入口层
  lobby_page.gd::_open_scan_join(true)
  lobby_page.gd::_start_auto_scan_join()
  page_scan_join_flow_base.gd::_begin_android_qr_scan()

Android 相机识别层
  PlayWithMeAndroid.kt::scanQr()
  QrScannerActivity.kt::startCamera()
  QrScannerActivity.kt::analyzeImage()
  QrScannerActivity.kt::joinPayloadRejectReason()

Godot 扫码桥层
  android_qr_scanner.gd::start_scan()
  android_qr_scanner.gd::scan_succeeded / scan_failed / scan_cancelled

Godot 扫码 UI 层
  qr_scan_join_ui.gd::open_processing_page()
  qr_scan_join_ui.gd::set_waiting()
  qr_scan_join_ui.gd::tick()

Payload 与加密层
  qr_join_payload.gd::parse()
  qr_join_payload.gd::decrypt_secure_payload()
  qr_join_payload.gd::encrypt_secret()

网络协商与加入编排层
  room_network_session.gd::connect_to_secure_qr()
  room_network_session.gd::_send_pending_join_request()
  room_network_session.gd::_handle_qr_secret_response()
  page_navigation_ui_base.gd::_host_resolve_qr_secret()
  page_navigation_ui_base.gd::_host_accept_network_join()
```

核心数据流：

```text
房主打开二维码
  -> 基础能力生成或复用当前房间的 qr_secrets[player|observer]
  -> 生成 v2 安全 payload
  -> 渲染 QR 图片

客户端点击扫码
  -> Android 相机页持续分析帧
  -> 识别到合法房间二维码
  -> Godot 打开加入处理中页面
  -> 读取明文 IP:端口
  -> 连接房主 WebSocket
  -> hello / hello_ack 设备认证
  -> qr_secret_request 请求二维码 AES 密钥
  -> qr_secret_response 返回 RSA 包装后的 AES 密钥
  -> 客户端解密密文
  -> 校验地址、房主身份、协议版本
  -> join_room 或 join_room_as_observer
  -> join_accepted 进入房间，或 join_rejected 显示错误
```

## 二维码数据格式

当前安全二维码版本为 `version = 2`，格式标记为 `lan_join_secure`。外层是 JSON：

```json
{
  "app": "chat_with_me",
  "version": 2,
  "format": "lan_join_secure",
  "address": "192.168.1.8:42871",
  "host": "192.168.1.8",
  "port": 42871,
  "secretId": "base64url-id",
  "alg": "AES-256-CBC+SHA256",
  "keyExchange": "RSA-2048-WRAP",
  "iv": "base64url-iv",
  "cipher": "base64url-cipher",
  "mac": "base64url-mac"
}
```

明文字段：

- `app`：固定为 `chat_with_me`。
- `version`：当前安全格式为 `2`。
- `format`：固定为 `lan_join_secure`。
- `address`、`host`、`port`：扫码端先用它连接房主，格式是 `IP:端口`。
- `secretId`：房主用它查找本地保存的二维码 AES 密钥。
- `alg`、`keyExchange`、`iv`、`cipher`、`mac`：解密和校验所需元数据。

密文字段：

- `room_id`
- `room_name`
- `join_mode`
- `join_token`
- `host_device_id`
- `host_public_key`
- `game_room_id`
- `game_room_display_name`
- `map_id`
- `map_display_name`
- `game_room_scene`
- `background`
- `host`
- `port`
- `network_protocol_version`

结构规则：

- `version = 2` 是唯一生成和解析格式。
- 不符合当前结构的二维码直接拒绝，不进入连接或加入流程。
- 新字段应优先加入密文区，只有扫码前必须读取的连接信息才能放在明文区。
- 变更 `app`、`version`、`format` 或必要字段时，需要同步 Godot 解析、Android 预过滤和测试。

## 加密与密钥协商

房主生成二维码时，为玩家码和观战码分别维护一组本地 `qr_secrets`：

```text
room.qr_secrets.player   = { id, key }
room.qr_secrets.observer = { id, key }
```

- `id` 写入二维码外层 `secretId`。
- `key` 是 32 字节 AES 密钥，base64url 保存，只存在房主本地房间状态。
- 二维码中不包含 AES 密钥。

加密流程：

1. 房主把密文字段序列化成 JSON。
2. 使用 AES-256-CBC 加密，PKCS#7 padding。
3. 对 `domain + key + iv + cipher` 做 SHA-256 校验，结果写入 `mac`。
4. 外层二维码只保留明文地址、`secretId`、`iv`、`cipher`、`mac`。

协商流程：

1. 扫码端读取外层 `host:port`。
2. 扫码端连接 WebSocket，并完成 `hello` / `hello_ack` 设备身份认证。
3. 扫码端临时生成 RSA-2048 密钥对，发送 `qr_secret_request`，包含 `secretId`、临时公钥和设备认证签名。
4. 房主用 `secretId` 查找 AES 密钥，用扫码端临时公钥加密后返回 `qr_secret_response`。
5. 扫码端用临时私钥解包 AES 密钥，解密二维码密文。
6. 扫码端校验解密出的 `host:port`、`hostDeviceId`、`hostPublicKey`、`networkProtocolVersion`。
7. 校验通过后，扫码端发送 `join_room` 或 `join_room_as_observer`。

时序视图：

```text
Client                                Host
  |                                   |
  | ws://IP:port                      |
  |---------------------------------->|
  | hello + clientChallenge           |
  |---------------------------------->|
  | hello_ack + hostAuth              |
  |<----------------------------------|
  | qr_secret_request                 |
  | secretId + temp RSA publicKey     |
  |---------------------------------->|
  | lookup current room qr_secrets    |
  | wrap AES key with temp publicKey  |
  | qr_secret_response + wrappedKey   |
  |<----------------------------------|
  | unwrap AES key                    |
  | decrypt QR cipher                 |
  | validate address/host/protocol    |
  | join_room / join_room_as_observer |
  |---------------------------------->|
  | validate room/password/capacity   |
  | join_accepted / join_rejected     |
  |<----------------------------------|
```

## 扫码交互流程

大厅顶部的“扫描加入”入口应该直接启动相机。

1. `lobby_page.gd::_open_scan_join(true)` 调用 `_start_auto_scan_join()`。
2. `_start_auto_scan_join()` 清理当前弹层，然后调用 `page_scan_join_flow_base.gd::_begin_android_qr_scan(null, null)`。
3. `_begin_android_qr_scan()` 绑定 Android 扫码信号，并调用 `AndroidQrScanner.start_scan()`。
4. Android 插件 `PlayWithMeAndroid.scanQr()` 检查相机权限，有权限后启动 `QrScannerActivity`。
5. `QrScannerActivity.startCamera()` 使用 CameraX `ImageAnalysis`，`STRATEGY_KEEP_ONLY_LATEST` 持续读取帧。
6. `QrScannerActivity.analyzeImage()` 调用 ML Kit，只识别 QR Code。
7. 每次识别到二维码后，`joinPayloadRejectReason()` 先做轻量格式检查。
8. 不是房间二维码时，相机页提示“不是房间二维码”，继续扫描。
9. 是房间二维码时，Activity 返回 payload，Godot 收到 `scan_succeeded`。
10. Godot 再次调用 `QrJoinPayload.parse()` 做完整格式检查。
11. 检查通过后打开 `qr_scan_join_ui.gd::open_processing_page()`，显示“正在加入”动画。
12. `page_navigation_ui_base.gd::_join_room_from_payload()` 发起网络加入。
13. 网络状态通过 `_on_network_status_changed()` 覆盖处理页状态文案。
14. 加入成功关闭处理页并进入桌面；加入失败保留处理页并显示原因，用户可重新扫码。

非 Android 或调试场景仍保留手动粘贴入口：

- `lobby_page.gd::_open_scan_join(false)`
- `qr_scan_join_ui.gd::open_manual_join()`
- `page_navigation_ui_base.gd::_submit_manual_scan_join()`

## 失败提示模型

扫码加入需要把失败点映射成明确文案：

- 加入码为空、不是 JSON、不是本应用、版本不支持。
- 加密二维码格式不支持、缺少 `secretId`、缺少 `iv/cipher/mac`。
- 地址无效，格式不是 `IP:端口`。
- Android 相机权限失败或相机启动失败。
- 非房间二维码：相机页提示并继续扫描，不返回 Godot。
- 网络连接失败或超时：提示确认双方在同一局域网且房主在线。
- WebSocket 连接后断开：提示房间连接已断开。
- 设备认证失败：房主设备身份或签名不匹配。
- `secretId` 不存在：二维码已失效，需要重新打开房间二维码。
- RSA 公钥无效或 wrap 失败：二维码密钥协商失败。
- MAC 校验失败或 AES 解密失败：二维码解密失败。
- 解密出的地址和外层地址不一致：二维码内容不一致。
- 解密出的房主身份和 `hello_ack` 身份不一致：房主身份与二维码不一致。
- `networkProtocolVersion` 不一致：提示确认双方应用版本一致。
- 房间 ID 不匹配：二维码可能已失效。
- 密码错误：提示密码错误。
- 房间已满：提示房间已满。
- 游戏已开始：提示游戏开始后不能加入房间。
- 观战人数满或观战关闭：使用观察者策略返回的提示。

## 代码视图

| 层级 | 文件 | 关键入口 | 职责 |
|---|---|---|---|
| 房主二维码入口 | `scripts/room/werewolf/werewolf_room_page.gd` | `_open_qr()` | 打开房间二维码弹层，展示 QR 图片、明文网络地址和“房间信息已加密”状态。 |
| 二维码生成流程 | `scripts/pages/base/page_navigation_ui_base.gd` | `_build_join_payload()` | 组装当前房间信息，生成玩家码或观战码。 |
| 二维码密钥状态 | `scripts/pages/base/page_navigation_ui_base.gd` | `_ensure_join_qr_secret()`、`_qr_secret_key_for_id()` | 为 player/observer 维护 `qr_secrets`，按 `secretId` 找回 AES 密钥。 |
| Payload 编解码 | `scripts/network/qr_join_payload.gd` | `build_secure_encoded()`、`parse()` | 定义当前二维码格式，做字段校验。 |
| Payload 加解密 | `scripts/network/qr_join_payload.gd` | `encrypt_secret()`、`decrypt_secure_payload()` | AES-CBC 加解密、PKCS#7 padding、SHA-256 MAC 校验。 |
| QR 图片生成 | `scripts/ui/qr/qr_code_generator.gd` | `generate()` | 把 payload 渲染成 Texture，用于房间二维码展示。 |
| 大厅扫码入口 | `scripts/pages/lobby_page.gd` | `_open_scan_join()`、`_start_auto_scan_join()` | 首页点击扫码时直接启动相机；调试模式可打开手动输入 UI。 |
| 扫码处理 UI | `scripts/ui/qr/qr_scan_join_ui.gd` | `open_processing_page()`、`set_waiting()`、`tick()` | 处理页、状态文本、等待动画、重新扫码按钮。 |
| 手动加入 UI | `scripts/ui/qr/qr_scan_join_ui.gd` | `open_manual_join()` | 手动粘贴加入码和调试扫码入口。 |
| Godot 扫码流程 | `scripts/pages/base/page_scan_join_flow_base.gd` | `_begin_android_qr_scan()`、`_on_android_qr_scan_succeeded()` | 启动扫码、接收扫码结果、打开处理页、发起加入。 |
| Godot Android 桥 | `scripts/android/android_qr_scanner.gd` | `start_scan()`、`submit_scan_result()` | 调用 Android singleton，统一扫码成功、失败、取消信号。 |
| Android 插件入口 | `android_plugins/play_with_me_android/play-with-me-android/src/main/java/com/playwithme/godot/PlayWithMeAndroid.kt` | `scanQr()`、`onMainActivityResult()` | 权限申请、启动扫码 Activity、把结果发回 Godot。 |
| Android 相机识别 | `android_plugins/play_with_me_android/play-with-me-android/src/main/java/com/playwithme/godot/QrScannerActivity.kt` | `startCamera()`、`analyzeImage()`、`joinPayloadRejectReason()` | CameraX 连续帧分析、ML Kit QR 识别、房间二维码预过滤。 |
| 客户端网络协商 | `scripts/room/network/room_network_session.gd` | `connect_to_secure_qr()`、`_send_pending_join_request()`、`_handle_qr_secret_response()` | 连接房主、请求 AES 密钥、解密 payload、发送入房请求。 |
| 房主握手响应 | `scripts/pages/base/page_navigation_ui_base.gd` | `_host_resolve_qr_secret()` | 根据 `secretId` 找 AES 密钥，用客户端 RSA 公钥包装后返回。 |
| 房主入房校验 | `scripts/pages/base/page_navigation_ui_base.gd` | `_host_accept_network_join()` | 当前代码中校验房间 ID、密码、人数、游戏状态和观战策略；设计归属为房间模块加入策略。 |
| 网络消息定义 | `scripts/network/room_network_codec.gd` | `CLIENT_TYPES`、`SERVER_TYPES` | 定义 `qr_secret_request`、`qr_secret_response`、`join_room`、`join_accepted`、`join_rejected` 等消息。 |
| 快照脱敏 | `scripts/room/network/room_network_snapshot_builder.gd` | `build_for_participant()` | 加入成功后按参与者视角返回房间快照。 |

### 房主生成二维码调用链

```text
werewolf_room_page.gd::_open_qr()
  -> page_navigation_ui_base.gd::_start_host_room_network()
  -> page_navigation_ui_base.gd::_refresh_active_room_network_fields()
  -> page_navigation_ui_base.gd::_build_join_payload(as_observer=false)
     -> page_navigation_ui_base.gd::_ensure_join_qr_secret()
     -> qr_join_payload.gd::build_secure_encoded()
        -> qr_join_payload.gd::build_secure()
        -> qr_join_payload.gd::encrypt_secret()
  -> page_book_ui_base.gd::_fake_qr(payload)
     -> qr_code_generator.gd::generate()
```

### 客户端扫码加入调用链

```text
lobby_page.gd::_open_scan_join(auto_start=true)
  -> lobby_page.gd::_start_auto_scan_join()
  -> page_scan_join_flow_base.gd::_begin_android_qr_scan(null, null)
     -> android_qr_scanner.gd::start_scan()
        -> PlayWithMeAndroid.kt::scanQr()
        -> QrScannerActivity.kt::startCamera()
        -> QrScannerActivity.kt::analyzeImage()
        -> QrScannerActivity.kt::finishSuccess(payload)
     -> android_qr_scanner.gd::scan_succeeded(payload)
  -> page_scan_join_flow_base.gd::_on_android_qr_scan_succeeded(payload)
     -> qr_join_payload.gd::parse(payload)
     -> page_scan_join_flow_base.gd::_open_scan_join_processing_page()
     -> qr_scan_join_ui.gd::open_processing_page()
     -> page_navigation_ui_base.gd::_join_room_from_payload(payload, interactive=true)
     -> page_navigation_ui_base.gd::_join_secure_room_from_payload()
     -> room_network_session.gd::connect_to_secure_qr()
```

### 客户端安全协商调用链

```text
room_network_session.gd::connect_to_secure_qr()
  -> WebSocketPeer.connect_to_url(ws://IP:port)
  -> hello / hello_ack
  -> room_network_session.gd::_send_pending_join_request()
     -> send_client("qr_secret_request", { secretId, publicKey, auth })
  -> room_network_session.gd::_handle_qr_secret_response()
     -> Crypto.decrypt(tempPrivateKey, wrappedKey)
     -> qr_join_payload.gd::decrypt_secure_payload()
     -> 校验 host/port、hostDeviceId、hostPublicKey、networkProtocolVersion
     -> send_client("join_room" 或 "join_room_as_observer")
```

### 房主处理安全协商和入房调用链

```text
room_network_session.gd 收到客户端消息
  -> page_navigation_ui_base.gd::_on_network_client_message_received()
     -> "qr_secret_request"
        -> page_navigation_ui_base.gd::_host_resolve_qr_secret()
        -> send_to_peer("qr_secret_response", { wrappedKey })
     -> "join_room" / "join_room_as_observer"
        -> page_navigation_ui_base.gd::_host_accept_network_join()
        -> 校验 roomId / password / game state / capacity / observer policy
        -> send_to_peer("join_accepted" 或 "join_rejected")
```

## UI 状态视图

扫码 UI 状态集中在 `scripts/ui/qr/qr_scan_join_ui.gd`：

```text
_active
  当前是否存在扫码/加入 UI 上下文。

_waiting_network
  是否正在显示动态等待文案。

_status_base
  等待动画基础文案，例如“正在加入”“正在协商二维码密钥”。

_anim_elapsed
  动画计时，tick() 根据时间追加 0 到 3 个点。

_payload_input
  手动加入时是真实输入框；自动扫码处理页中是隐藏输入框，用于保存扫码 payload。

_status_label
  处理页或手动弹层的状态文本。
```

`scripts/pages/base/page_scan_join_flow_base.gd` 当前保留扫码流程状态同步：

- `_ensure_scan_join_ui()`
- `_sync_scan_join_ui_state()`
- `_activate_scan_join()`
- `_stop_scan_join_waiting()`
- `_set_scan_status()`
- `_set_scan_join_waiting()`
- `_tick_scan_join_animation()`
- `_clear_scan_overlay_refs()`

## 调试日志

关键日志 tag：

- Android 原生相机页：`PlayWithMeQrScanner`
- Android 插件桥接：`PlayWithMeAndroid`
- Godot 扫码桥：`[AndroidQrScanner][debug]`
- Godot 入房流程：`[QrScanJoin][debug]`

常用设备调试命令：

```powershell
D:\android\platform-tools\adb.exe -s 192.168.1.104:5555 logcat -c
D:\android\platform-tools\adb.exe -s 192.168.1.104:5555 logcat PlayWithMeQrScanner:D PlayWithMeAndroid:D godot:D *:S
```

扫码无反应时优先看：

- 是否出现 `startCamera requested continuous ImageAnalysis polling`。
- 是否出现周期性 `frame=... no barcode`。
- 是否出现 `room QR rejected reason=...`。
- 是否出现 `room QR accepted chars=... hash=...`。
- Godot 是否收到 `[AndroidQrScanner][debug] signal succeeded`。
- Godot 是否进入 `[QrScanJoin][debug] open processing page`。
- 网络状态是否更新为 `正在连接房间`、`正在协商二维码密钥`、`二维码解密完成，正在加入房间`。

## 测试与验证

相关自动化检查：

- `test/checks/qr_join_payload_secure_check.gd`：验证当前安全二维码外层不泄露 `room_id` 和 `join_token`，正确密钥可解密，错误密钥失败，非当前结构直接拒绝。
- `test/checks/room_network_session_check.gd`：覆盖普通加入、重连、房主身份不匹配拒绝，以及 `qr_secret_request` / `qr_secret_response` 安全扫码握手。
- `test/checks/room_network_ui_check.gd`：覆盖页面层生成安全二维码后客户端入房。
- `test/checks/android_qr_scanner_check.gd`：覆盖 Godot Android 扫码桥信号和当前方法。
- `test/checks/ui_smoke_check.gd`：覆盖主要 UI 构造不崩溃。

本地常用验证命令：

```powershell
tools\run_godot_check.ps1 test\checks\qr_join_payload_secure_check.gd
tools\run_godot_check.ps1 test\checks\room_network_session_check.gd
tools\run_godot_check.ps1 test\checks\room_network_ui_check.gd
tools\run_godot_check.ps1 test\checks\android_qr_scanner_check.gd
tools\run_godot_check.ps1 test\checks\ui_smoke_check.gd
```

Android 设备验收：

1. 房主创建房间，打开“加入二维码”。
2. 另一台设备在大厅点击扫码，必须直接打开相机。
3. 对准非房间二维码，相机页应提示“不是房间二维码”并继续扫描。
4. 对准房间二维码，应退出相机并进入“加入房间”处理页。
5. 正常网络下应进入房间。
6. 断网、跨局域网、二维码失效、密码错误、房间满员、版本不一致时，应显示对应错误。

## 维护约定

- 改二维码字段时，同步 `qr_join_payload.gd`、`QrScannerActivity.kt::joinPayloadRejectReason()`、相关测试和本文档。
- 新增敏感字段时默认放入 v2 密文区，不放明文。
- 新增扫码 UI 元素时优先改 `qr_scan_join_ui.gd`，不要把 UI 放进页面共享入口。
- 新增网络状态文案时优先通过 `RoomNetworkSession.status_changed` 传递，`page_navigation_ui_base.gd::_on_network_status_changed()` 会同步到扫码处理页。
- 新增基础失败原因时同步本文档；新增房间策略拒绝原因时同步 [房间模块](../room/README.md)，并在房主侧返回可展示的 `join_rejected` 消息。
- Android 扫码预过滤只做轻量格式检查，完整安全校验必须仍在 Godot 侧执行。
- 保持扫码按钮自动启动相机；手动输入只作为调试或非自动扫码路径。

