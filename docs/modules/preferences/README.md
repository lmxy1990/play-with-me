# 偏好设置模块

更新时间：2026-05-16

偏好设置模块是基础模块，负责本机用户偏好的持久化和编辑。它回答“这个设备上的我是谁，以及本机播放历史时用哪个声音”，对外提供昵称、头像、播放声音配置引用和设备私钥读取能力。

偏好设置模块像一个本机偏好黑盒：应用启动时确保偏好 JSON 存在；其它模块通过接口读取昵称、头像、播放声音配置引用和设备私钥；页面允许修改昵称、头像和播放声音配置，设备私钥只读可查看。

## 模块定位

```text
应用启动
  -> 偏好设置模块
       -> ensure_preferences()
       -> 检查 / 创建 / 校验本机 preferences JSON
       -> 返回 PreferenceState

偏好设置页面
  -> 修改昵称
  -> 修改头像
  -> 选择播放声音配置
  -> 查看设备私钥
```

偏好设置模块只负责本机偏好数据的持久化和编辑。它可以保存设备私钥和播放声音配置引用，但不执行设备认证、房间加入策略、具体游戏房间校验、模型调用、记忆管理或 TTS 播放。

## 能力边界

偏好设置模块负责：

- 应用启动时确保本机偏好 JSON 存在。
- 当偏好 JSON 不存在时自动创建默认数据。
- 自动生成默认昵称。
- 自动选择默认头像。
- 自动选择默认播放声音配置。
- 自动生成设备私钥，并持久化到本机 JSON。
- 提供 24 个内置默认头像供选择。
- 支持修改昵称。
- 支持修改头像。
- 支持修改播放声音配置引用。
- 支持只读查看设备私钥。
- 提供偏好读取、字段校验、保存和只读调试能力。

偏好设置模块不负责：

- 上传头像、裁剪头像、相册权限或远程头像。
- 修改、重置或轮换设备私钥。
- 执行设备认证、签名校验或房间认证。
- 保存模型供应商、Endpoint、API Key、声音配置详情或机器人记忆。
- 保存房间密码、二维码 secret、重连 token 或房间权威状态。
- 任何具体游戏房间玩法、玩家行动或胜负判断。

## 持久化文件

偏好设置保存为本机 JSON 文件。具体路径可以由配置仓库决定，但语义上它是应用启动时必须存在的本机身份文件。

建议路径：

```text
user://preferences.json
```

业务字段只包含：

| 字段 | 说明 | 是否自动生成 | 是否可修改 |
| --- | --- | --- | --- |
| `nickname` | 用户昵称，默认用于大厅、房间和玩家展示。 | 是 | 是 |
| `avatar_id` | 当前选择的内置头像 ID。 | 是 | 是 |
| `playback_voice_config_id` | 当前选择的播放声音配置引用。默认指向声音配置里的系统 TTS 默认记录。 | 是 | 是 |
| `device_private_key` | 本机设备私钥，用于基础认证能力派生设备身份和签名。 | 是 | 否，仅可查看 |

元数据字段建议：

| 字段 | 说明 |
| --- | --- |
| `schema_version` | 偏好 JSON 结构版本。 |
| `created_at` | 首次生成时间。 |
| `updated_at` | 最近更新时间。 |

示例：

```json
{
  "schema_version": 2,
  "nickname": "玩家7421",
  "avatar_id": "animal_fox_01",
  "playback_voice_config_id": "voice_system_default",
  "device_private_key": "base64-or-pem-private-key",
  "created_at": "2026-05-15T00:00:00Z",
  "updated_at": "2026-05-15T00:00:00Z"
}
```

## 生命周期契约

| 生命周期 | 触发方 | 建议调用 | 作用 |
| --- | --- | --- | --- |
| `app_startup` | 应用路由 / 启动服务 | `ensure_preferences()` | 确保偏好文件存在且符合当前结构。 |
| `preferences_opened` | 大厅 / 设置入口 | `get_preferences()`、`list_avatars()` | 展示当前昵称、头像、播放声音配置和私钥只读状态。 |
| `nickname_changed` | 偏好设置页面 | `update_nickname()` | 校验并保存昵称。 |
| `avatar_changed` | 偏好设置页面 | `update_avatar()` | 校验并保存头像 ID。 |
| `playback_voice_changed` | 偏好设置页面 | `update_playback_voice_config()` | 校验并保存播放声音配置引用。 |
| `device_key_viewed` | 偏好设置页面 | `get_device_private_key_view()` | 只读查看设备私钥，不写入文件。 |
| `preferences_invalid` | 启动读取 | `discard_invalid_preferences()` | 丢弃不符合当前结构的偏好文件并重建。 |

## 核心对象

### PreferenceState

| 字段 | 说明 |
| --- | --- |
| `schema_version` | 偏好数据结构版本。 |
| `nickname` | 当前本机昵称。 |
| `avatar_id` | 当前本机头像 ID。 |
| `playback_voice_config_id` | 当前本机播放声音配置引用。默认值为 `voice_system_default`。 |
| `device_private_key` | 本机设备私钥。只允许生成、读取和查看，不允许用户修改。 |
| `created_at` | 首次生成时间。 |
| `updated_at` | 最近更新时间。 |

### AvatarCatalog

头像目录是内置静态资源，不保存在偏好 JSON 里。偏好 JSON 只保存 `avatar_id`。

约定：

- 共 24 个默认头像。
- 不支持上传头像。
- 不支持从相册选择头像。
- 不保存外部图片路径。
- 头像风格包括卡通动物和卡通人物。
- 头像 ID 必须稳定，例如 `animal_fox_01`、`animal_cat_01`、`person_boy_01`、`person_girl_01`。

后续替换头像资源时，必须同步头像目录和默认值；不存在于当前目录的 `avatar_id` 直接视为无效。

### PlaybackVoiceConfig

播放声音配置引用用于本机播放历史消息。偏好 JSON 只保存引用 ID，不保存引擎、音色、语速、音调、音量等声音配置详情。

约定：

- 默认值是 `voice_system_default`。
- `voice_system_default` 指向声音配置模块预置的“系统默认”TTS 记录。
- 用户在偏好设置页选择播放声音配置；声音配置详情仍在声音配置页维护。
- 历史消息播报时，房间页面读取该引用，再交给 TTS 语音模块解析成具体声音配置。
- 机器人声音、模型配置和玩家发言文本不写入该字段。

### DevicePrivateKey

设备私钥是本机身份的根凭据。

约定：

- 首次启动且 JSON 不存在时自动生成。
- JSON 存在但缺少私钥时自动补齐。
- 用户不能编辑、替换或删除私钥。
- 页面只能以只读方式查看私钥。
- 日志、错误提示和大厅卡片不得输出私钥。
- 基础能力模块可以读取私钥，用于派生设备 ID、公钥和签名能力。
- 偏好设置模块只保存私钥，不决定认证是否通过。

## 对外接口

以下接口是设计契约，不要求当前代码函数名完全一致。

```text
ensure_preferences() -> PreferenceResult
get_preferences() -> PreferenceResult
update_nickname(request) -> PreferenceUpdateResult
update_avatar(request) -> PreferenceUpdateResult
update_playback_voice_config(request) -> PreferenceUpdateResult
list_avatars(request) -> AvatarCatalogResult
get_device_private_key_view(request) -> ReadonlySecretResult
get_preferences_debug_state(request) -> PreferenceDebugResult
```

### ensure_preferences

```text
ensure_preferences() -> PreferenceResult
```

流程：

```text
应用启动
  -> 检查 preferences JSON 是否存在
  -> 不存在则生成 nickname、avatar_id、device_private_key
  -> 存在则读取 JSON
  -> 校验 nickname、avatar_id、device_private_key
  -> 结构不匹配则丢弃并重新生成
  -> 写回当前结构 JSON
  -> 返回 PreferenceState
```

约定：

- 应在应用启动早期执行。
- 如果 JSON 损坏或结构不匹配，应直接生成新的默认偏好。
- 生成私钥后必须尽快落盘，避免后续认证使用临时身份。

### update_nickname

```text
update_nickname(request) -> PreferenceUpdateResult
```

`request`：

| 字段 | 说明 |
| --- | --- |
| `nickname` | 新昵称。 |
| `schema_version` | 请求结构版本，可选。 |

校验规则：

- 去掉首尾空白。
- 不能为空。
- 限制最大长度，避免房间座位和大厅卡片溢出。
- 不允许控制字符和换行。

### update_avatar

```text
update_avatar(request) -> PreferenceUpdateResult
```

`request`：

| 字段 | 说明 |
| --- | --- |
| `avatar_id` | 内置头像 ID。 |
| `schema_version` | 请求结构版本，可选。 |

校验规则：

- `avatar_id` 必须存在于 24 个内置头像目录。
- 不接受外部文件路径、URL 或上传结果。

### update_playback_voice_config

```text
update_playback_voice_config(request) -> PreferenceUpdateResult
```

`request`：

| 字段 | 说明 |
| --- | --- |
| `playback_voice_config_id` | 播放声音配置引用。 |
| `schema_version` | 请求结构版本，可选。 |

校验规则：

- 去掉首尾空白。
- 不能为空。
- 只接受字母、数字、下划线和短横线。
- 不保存声音配置详情。

### get_device_private_key_view

```text
get_device_private_key_view(request) -> ReadonlySecretResult
```

约定：

- 页面可以展示私钥，但不能提供编辑输入框。
- 默认可以使用折叠或遮罩展示，用户主动查看时再显示完整内容。
- 查看私钥不改变 JSON。
- 不提供“重新生成私钥”按钮；私钥只在偏好文件重建时重新生成。

## 版本与无效数据

偏好设置是启动必读基础数据，只接受当前结构。

处理规则：

- 新增字段必须有默认值。
- 缺少 `nickname`、`avatar_id`、`playback_voice_config_id` 或 `device_private_key` 时，当前偏好文件无效并重建。
- 损坏 JSON 或 `schema_version` 不匹配时，直接生成新文件。
- 头像 ID 不存在于当前头像目录时，当前偏好文件无效并重建。

## 失败与降级

| 场景 | 策略 |
| --- | --- |
| 文件不存在 | 自动生成完整默认偏好。 |
| 文件损坏 | 生成新偏好，返回 warning。 |
| 私钥缺失 | 生成新偏好，返回 warning。 |
| 播放声音配置引用缺失 | 生成新偏好，返回 warning。 |
| 头像 ID 无效 | 生成新偏好，返回 warning。 |
| 昵称无效 | 拒绝保存，返回可展示错误。 |
| 播放声音配置引用格式无效 | 拒绝保存，返回可展示错误。 |
| 写入失败 | 返回 error，不更新内存状态为已保存。 |

## 只读调试

```text
get_preferences_debug_state(request) -> PreferenceDebugResult
```

只读调试信息建议包含：

- 偏好文件是否存在。
- 当前 `schema_version`。
- 当前昵称和头像 ID。
- 当前播放声音配置引用。
- 私钥是否存在、格式是否可解析。
- 最近一次无效数据处理结果。

约定：

- 默认不返回私钥明文。
- 调试接口不得修改偏好文件。
- release 包可以禁用或只返回健康状态。

## 与其它模块的关系

| 模块 | 偏好设置如何交互 |
| --- | --- |
| 基础能力 | 读取 `device_private_key`，派生设备身份、公钥和签名能力；认证判断仍属于基础能力。 |
| 大厅模块 | 提供偏好设置入口，可展示当前昵称和头像。 |
| 创建房间模块 | 可读取昵称和头像作为房主默认展示信息。 |
| 房间模块 | 可读取昵称和头像作为参与者默认展示信息；不读取私钥明文做业务判断。 |
| 玩家模块 | 使用昵称和头像作为玩家基础展示字段。 |
| 模型管理模块 | 不交叉；模型配置独立维护。 |
| 机器人/RAG 模块 | 不交叉；机器人配置和记忆存储独立维护。 |
| TTS 语音模块 | 声音配置独立维护；偏好设置只保存本机播放声音配置引用。 |

## 文档和代码归属

目标归属：

```text
scenes/preferences.tscn
scripts/pages/config/preferences_page.gd
scripts/core/preferences/
  preference_repository.gd
  preference_schema.gd
  preference_defaults.gd
  avatar_catalog.gd
```

设备身份的签名、验签、公钥派生和认证流程归基础能力；偏好设置只负责 JSON 持久化和页面编辑。

## 维护规则

- 偏好 JSON 的业务字段保持简洁：昵称、头像 ID、播放声音配置引用、设备私钥。
- 应用启动时必须确保偏好 JSON 存在。
- 昵称自动生成后允许修改。
- 头像只能从 24 个内置头像中选择，不支持上传。
- 播放声音配置只保存引用 ID，不保存声音配置详情。
- 设备私钥自动生成，只读可查看，不支持修改。
- 私钥不得出现在普通日志、网络广播、房间摘要、二维码明文或大厅卡片里。
- 新增头像时同步头像目录、头像资源、头像选择页面和默认头像配置。
- 新增偏好字段前先确认它是否真属于本机偏好；模型配置详情、声音配置详情、记忆、房间和规则字段不要放进偏好设置。
