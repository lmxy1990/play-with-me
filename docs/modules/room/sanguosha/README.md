# 三国杀房间模块

更新时间：2026-06-06

三国杀房间模块是通用房间模块委派的具体游戏房间模块，负责三国杀地图、对决/身份局座位、规则包、武将包、牌堆和手牌权威状态、阶段推进、响应窗口、行动校验、伤害和濒死结算、胜负判断、事件下发和复盘。它回答“当前这局三国杀轮到谁做什么、玩家能打哪些牌、谁需要响应、结算如何串行推进、什么时候结束”。

房间模块提供房间上下文、参与者、座位、玩家通道、网络同步、可见历史、重连和主机接管。三国杀房间模块只生产三国杀公开状态、玩家私有视角、行动请求、事件 payload、特效请求和恢复材料；它不关心玩家响应来自真人 UI 还是 AI。

玩家响应由后续 [三国杀真人玩家模块](../../player/sanguosha/human/README.md) 和 [三国杀 AI 玩家模块](../../player/sanguosha/ai/README.md) 通过通用玩家模块收集。主机程序持有唯一权威牌局状态，负责规则推进和胜负判定。

跨模块对象建议新增 `SanguoshaActionRequest`、`SanguoshaPlayerActionResult`、`SanguoshaRuleUpdateResult`、`SanguoshaVisibleSnapshot` 和 `SanguoshaResponseWindow`，字段权威后续同步到 [跨模块契约](../../../contracts/README.md)。

## 模块定位

```text
房间模块
       -> 三国杀房间模块
       -> 提供三国杀地图和模式列表
       -> 提供 2 人对决、4-8 人身份局人数和座位布局
       -> 初始化身份、武将、牌堆、手牌和出牌顺序
       -> 生成回合阶段行动请求
       -> 生成插入式响应窗口请求
       -> 接收真人或 AI 行动结果
       -> 校验出牌、弃牌、响应、目标、距离和结算顺序
       -> 结算摸牌、出牌、弃牌、伤害、濒死、死亡和胜负
       -> 输出公开事件、私有视角、特效请求、复盘和恢复材料
  -> 房间模块包装成快照并同步
```

三国杀是隐藏信息游戏：手牌、身份、部分响应选择和 AI prompt 都不能直接广播。2 人对决没有暗身份，但仍然有私有手牌和响应选择；房间模块可以同步房间外壳和可见历史，三国杀房间模块必须按接收者座位生成脱敏快照。

## 规则包确认

三国杀不能只按“先做几个基础牌”开工；人数、身份分布、武将池、卡牌包和装备/锦囊范围要先锁定成版本化规则包。第一版实现可以分期，但目录、状态、快照、AI 请求和测试必须从一开始按规则包设计。

先锁定的项目规则包：

| 项 | 第一版结论 | 后续扩展 |
| --- | --- | --- |
| 支持人数 | 支持 2 人对决、4-8 人身份局。 | 3 人变体、9-10 人、国战、斗地主等以后单独建地图。 |
| 身份局 | 4-8 人使用主公、忠臣、反贼、内奸。主公明身份，其他身份暗置。 | 8 人以外的特殊身份分布必须走单独 map 配置。 |
| 2 人局 | 使用 `sanguosha_duel_2p` 对决模式，不使用隐藏身份胜利条件。 | 后续可增加 1v1 选将轮换、禁将、换将等规则。 |
| 武将包 | 第一版锁定 `standard_core_adult_female`：25 名标准核心武将，视觉统一为成年女性武将，规则性别仍按技能结算保留。 | 后续增加标准外武将、扩展武将或原创武将时单独建包。 |
| 游戏牌包 | 第一版锁定 `standard_108`：108 张标准游戏牌，建模基本牌、装备牌、锦囊牌三类，不允许只建杀闪桃。 | 军争、国战、属性伤害、酒、铁索等放到扩展包。 |
| 启用牌 | 第一阶段启用基础牌、装备区/距离类装备、第一批非延时锦囊；未实现效果的牌不进入牌堆。 | 牌名、数量、花色、点数全部由 `card_pack_manifest` 锁定。 |
| 武将技能 | 第一版先按标准核心武将建立 `skill_key`、触发时机和 `effect_key`，规则引擎按技能逐个实现。 | 未实现技能必须标记为 disabled 或 fallback，不允许靠 AI prompt 口头执行。 |
| AI 行动 | AI 只在规则引擎给出的 `legal_actions` 中选择，不允许编造牌、目标或响应。 | 智能程度通过合法动作评分、局势摘要和策略提示增强。 |

规则包文件建议：

```text
scripts/room/sanguosha/rules/
  sanguosha_rule_pack_catalog.gd
  packs/
    duel_2p.json
    identity_4p.json
    identity_5p.json
    identity_6p.json
    identity_7p.json
    identity_8p.json
    standard_core_adult_female_generals.json
    standard_108_card_pack.json
```

约定：

- `map_id` 只决定玩法入口；实际人数、身份、武将包、卡牌包、启用技能和禁用列表都从 `rule_pack` 读取。
- 不同版本和盒装合集数量差异很大，代码不能把“25 名武将”“108 张游戏牌”“268 张”或“384 张”写死；只能读取 manifest。
- 第一版如果为了进度关闭部分装备/锦囊，必须在房间创建页展示“当前规则包启用牌”，不能让玩家误以为是完整标准版。

## 能力边界

三国杀房间模块负责：

- 提供三国杀可创建目录、地图列表、支持人数和场景槽位。
- 维护牌局权威状态：牌堆、弃牌堆、身份、武将、血量、手牌、装备区、判定区、当前阶段、当前行动者和响应窗口。
- 生成玩家行动请求：选身份可选项、选武将可选项、出牌、弃牌、响应、濒死求桃、托管或超时行动。
- 生成每个玩家视角下的合法动作列表。
- 接收玩家行动结果并做最终校验。
- 串行结算摸牌、出牌、目标响应、伤害、濒死、死亡、阶段切换和胜负。
- 输出公开事件、私有事件、特效请求、历史候选、复盘数据和恢复材料。
- 按接收者座位生成脱敏快照。
- 管理 AI fallback 的合法动作来源，例如默认弃牌、默认不出闪、默认不出桃。

三国杀房间模块不负责：

- 房间创建、加入、认证、二维码、扫码、加密、网络同步和主机选举。
- 真人 UI 交互细节。
- AI prompt、模型调用、模型配置、API Key 和输出兼容。
- 机器人长期记忆、记忆检索和记忆更新存储。
- TTS 播放和声音配置。
- 通用玩家资料、设备身份、偏好设置和 Android 桥接。

## 目录和文件归属

建议代码结构：

```text
scenes/
  sanguosha_room.tscn

scripts/room/sanguosha/
  sanguosha_room_page.gd
  sanguosha_engine.gd
  sanguosha_map_catalog.gd
  sanguosha_card_catalog.gd
  sanguosha_general_catalog.gd
  sanguosha_role_catalog.gd
  sanguosha_action_window.gd
  sanguosha_snapshot_builder.gd
  sanguosha_asset_catalog.gd

scripts/player/sanguosha/human/
  sanguosha_human_player_factory.gd

scripts/player/sanguosha/ai/
  sanguosha_ai_player_factory.gd
  ai_sanguosha_player_runtime.gd
  ai_sanguosha_turn_context_builder.gd
  ai_sanguosha_prompt_renderer.gd
  ai_sanguosha_response_schema_builder.gd
  ai_sanguosha_output_parser.gd

assets/images/sanguosha/
  backgrounds/
  cards/
    standard_108/
    card_back.png
  generals/
    standard_adult_female/
  roles/
  actions/

test/checks/
  sanguosha_engine_check.gd
  sanguosha_response_window_check.gd
  sanguosha_ai_player_check.gd
  sanguosha_room_page_check.gd
  sanguosha_create_room_check.gd
  sanguosha_resource_catalog_check.gd
```

接入点：

- `scripts/core/app_state.gd` 增加 `sanguosha` 状态槽和 `game_room_id == "sanguosha"` 分发。
- `scripts/core/app_router.gd` 增加 `sanguosha_table -> scenes/sanguosha_room.tscn`。
- 创建房间 UI 增加“三国杀”选项，地图来源改为具体游戏 catalog。
- 扫码加入、房间卡片、路由选择、默认地图名和背景图支持 `sanguosha`。
- `scripts/player/player_factory.gd` 增加三国杀真人和 AI 玩家工厂入口。

## 地图和模式

地图目录第一版先开放 2 人对决和 4-8 人身份局。实现顺序可以先打通 2 人和 4 人，但创建房间目录、规则包字段、座位布局和测试必须为 4-8 人预留。

| `map_id` | 名称 | 人数 | `rule_pack_id` | 说明 |
| --- | --- | --- | --- | --- |
| `sanguosha_duel_2p` | 双人对决 | 2 | `duel_2p` | 不使用隐藏身份；双方以击败对方为目标。 |
| `sanguosha_identity_4p` | 四人身份局 | 4 | `identity_4p` | 主公明身份，其余暗身份。 |
| `sanguosha_identity_5p` | 五人身份局 | 5 | `identity_5p` | 主公明身份，其余暗身份。 |
| `sanguosha_identity_6p` | 六人身份局 | 6 | `identity_6p` | 主公明身份，其余暗身份。 |
| `sanguosha_identity_7p` | 七人身份局 | 7 | `identity_7p` | 主公明身份，其余暗身份。 |
| `sanguosha_identity_8p` | 八人身份局 | 8 | `identity_8p` | 主公明身份，其余暗身份。 |

身份局角色分布按项目规则包先锁定如下：

| 人数 | 主公 | 忠臣 | 反贼 | 内奸 | 备注 |
| --- | --- | --- | --- | --- | --- |
| 2 | 0 | 0 | 0 | 0 | 对决模式，不走身份胜利条件。 |
| 4 | 1 | 1 | 1 | 1 | 最小身份局。 |
| 5 | 1 | 1 | 2 | 1 | 标准小局。 |
| 6 | 1 | 1 | 3 | 1 | 反贼压力更强，AI 需要明确阵营目标。 |
| 7 | 1 | 2 | 3 | 1 | 忠臣增加到 2。 |
| 8 | 1 | 2 | 4 | 1 | 第一版多人身份局上限。 |

胜利条件：

- `duel_2p`：任一方死亡时另一方获胜。
- `identity_*`：主忠阵营消灭所有反贼和内奸获胜；反贼阵营以主公死亡获胜；内奸需要在主公存活时清除其他角色，再击败主公。
- 主公误杀忠臣、反贼死亡摸牌等奖惩要写入身份局规则包，不由 UI 或 AI 决定。

座位布局可以复用狼人杀环形座位思路，但 UI 需要突出手牌区和当前行动区：

```text
上方对手区

左侧玩家区        中央牌桌 / 事件区        右侧玩家区

下方本机手牌区 / 操作区
```

观察者只能看到公开信息：座位、昵称、主公身份、存活、血量、手牌数量、弃牌堆、公开事件和当前阶段。观察者不能看到非公开手牌、暗身份和 AI prompt。

## 权威状态

三国杀房间模块维护的权威状态至少包括：

| 字段 | 说明 |
| --- | --- |
| `game_id` | 固定 `sanguosha`。 |
| `phase` | `lobby`、`setup`、`draw`、`play`、`discard`、`response`、`dying`、`completed`。 |
| `started` | 是否已开局。 |
| `map_id` / `map_name` | 当前地图。 |
| `rule_pack_id` | 当前规则包，例如 `duel_2p`、`identity_8p`。 |
| `general_pack_id` | 当前武将包，例如 `standard_core_adult_female`。 |
| `card_pack_id` | 当前游戏牌包，例如 `standard_108`。 |
| `skill_pack_id` | 当前技能包，例如 `standard_core_skills`。 |
| `round_number` | 当前轮数。 |
| `turn_seat` | 当前回合座位。 |
| `phase_owner` | 当前阶段归属座位。 |
| `players` | 玩家玩法状态摘要，按座位保存身份、武将、血量、存活、手牌数量等。 |
| `hands` | 手牌权威数据，按座位私有保存。 |
| `deck` | 牌堆。 |
| `discard_pile` | 弃牌堆。 |
| `equipment` | 装备区，按座位保存武器、防具、进攻坐骑、防御坐骑等槽位。 |
| `judge_area` | 判定区；延时锦囊启用前可以为空数组，但字段必须存在。 |
| `current_action` | 当前主动行动请求，可空。 |
| `response_window` | 当前响应窗口，可空。 |
| `pending_damage` | 正在结算的伤害上下文，可空。 |
| `dying_context` | 濒死求桃上下文，可空。 |
| `play_limits` | 当前出牌阶段已使用杀次数等限制。 |
| `enabled_card_keys` | 当前规则包启用的牌名键集合。 |
| `enabled_skill_keys` | 当前规则包启用的技能键集合。 |
| `event_log` | 结构化事件，供快照、复盘和 AI 上下文使用。 |
| `winner` | `lord_camp`、`rebel_camp`、`renegade` 或空。 |
| `result_reason` | 胜负原因。 |

约定：

- `hands` 是权威私有数据，不能直接进入通用房间快照。
- 玩家公开手牌只同步数量，不同步具体卡牌。
- 每张牌必须有稳定 `card_id`，出牌、弃牌和响应都引用 `card_id`。
- UI 展示文本不能作为规则校验来源；规则校验只读结构化状态。

## 武将模型

武将数量先按“够 8 人选将”确认，不把具体官方版本写死。若每名玩家 3 选 1，8 人局至少需要 24 名候选武将；当前第一版锁定 `standard_core_adult_female`，包含 25 名标准核心武将。视觉资源统一做 21+ 成年真人女性武将 PNG；规则数据仍保留 `rules_gender`，因为标准技能里存在性别相关结算。

武将包建议：

| `general_pack_id` | 数量 | 用途 | 技能策略 |
| --- | --- | --- | --- |
| `standard_core_adult_female` | 25 | 第一版，覆盖 2 人和 4-8 人身份局，每人 3 选 1 仍有 1 名候补。 | 技能 key、触发时机和 effect key 已建模；引擎逐个实现。 |
| `standard_core` | 以清单为准 | 保留原版视觉或其他视觉风格时使用。常见标准版存在 25/27 等差异，项目必须用 manifest 固定。 | 技能按 `enabled_skill_keys` 分批开启。 |
| `custom_test_pack` | 按测试需要 | 自动化测试、AI 压测、技能回归。 | 可只放少量白板或单技能武将。 |

每名武将建议结构：

| 字段 | 说明 |
| --- | --- |
| `general_id` | 稳定 ID，例如 `shu_liubei`。 |
| `name` | 展示名。 |
| `kingdom` | `wei`、`shu`、`wu`、`qun`、`shen` 等。 |
| `rules_gender` | 规则性别，`male`、`female`、`unknown`。视觉性别不替代规则性别。 |
| `visual_profile` | 美术风格，例如 `adult_female`。 |
| `visual_age_min` | 视觉年龄下限；成年女性资源必须大于等于 21。 |
| `max_hp` | 体力上限。 |
| `lord_candidate` | 是否可作为主公候选。 |
| `skills` | 技能键列表。 |
| `pack_id` | 所属武将包。 |
| `enabled` | 当前规则包是否启用。 |
| `asset_path` | 武将头像或立绘资源路径。 |

选将规则：

- `standard_core_adult_female` 默认每人随机 3 选 1；如果候选不足，开局必须失败并提示规则包配置错误。
- 2 人对决可以使用相同武将包，但可配置更小的候选数，例如每人 5 选 1。
- 主公体力加成、主公技、禁将、换将和双将都属于规则包配置，不写死到 UI。
- AI 只能看到当前玩家可见的武将候选和公开武将信息；暗身份不能通过武将选择泄漏。
- 所有武将视觉必须是明确 21+ 成年角色；允许性感古风战姬写真风格和丝袜、束腰、盔甲等服饰元素，但不允许未成年人、校服、裸露或露骨姿势。

## 卡牌模型

卡牌必须按 `card_pack_manifest` 构建牌堆。即使第一阶段不实现全部效果，也要先建模基本牌、装备牌和锦囊牌三类；未启用的牌不进入牌堆，不能让 AI 或 UI 凭提示词“想象”出不存在的牌。

每张牌建议结构：

| 字段 | 说明 |
| --- | --- |
| `card_id` | 本局唯一 ID，例如 `c_001`。 |
| `card_key` | 牌名键，例如 `slash`、`dodge`、`peach`。 |
| `name` | 展示名，例如 `杀`。 |
| `suit` | 花色。 |
| `rank` | 点数。 |
| `type` | `basic`、`trick`、`equip`。 |
| `subtype` | `weapon`、`armor`、`attack_horse`、`defense_horse`、`non_delay_trick`、`delay_trick` 等。 |
| `pack_id` | 所属游戏牌包。 |
| `enabled` | 当前规则包是否启用。 |
| `target_rule` | 目标选择规则键。 |
| `response_rule` | 响应规则键，例如 `requires_dodge`、`can_wuxie`。 |
| `effect_key` | 结算效果键。 |
| `metadata` | 距离、伤害、可响应牌、装备槽位等扩展字段。 |

游戏牌分类：

| 类型 | 第一版处理 | 说明 |
| --- | --- | --- |
| 基本牌 | 启用 `杀`、`闪`、`桃`。 | `杀`产生闪响应窗口；`桃`支持出牌阶段自救和濒死救援。 |
| 装备牌 | 启用装备区和距离规则，至少支持武器、防具、进攻坐骑、防御坐骑槽位。 | 装备进入装备区，替换同槽位旧装备；距离影响杀、顺手牵羊等目标合法性。 |
| 非延时锦囊 | 第一批启用目标选择和即时结算。 | 建议先做过河拆桥、顺手牵羊、无中生有、决斗、南蛮入侵、万箭齐发、桃园结义、无懈可击。 |
| 延时锦囊 | 第二批启用。 | 乐不思蜀、闪电等需要判定阶段和判定区，先保留字段，不进入第一批牌堆。 |

第一批启用牌建议：

| `card_key` | 名称 | 类型 | 第一阶段效果 |
| --- | --- | --- | --- |
| `slash` | 杀 | 基本牌 | 对距离内一名目标造成闪响应；未闪则 1 点伤害。 |
| `dodge` | 闪 | 基本牌 | 响应杀、万箭齐发等需要闪的效果。 |
| `peach` | 桃 | 基本牌 | 回复 1 点体力，支持濒死救援。 |
| `weapon_*` | 武器 | 装备牌 | 装备到武器槽，至少提供攻击距离。 |
| `armor_*` | 防具 | 装备牌 | 装备到防具槽，第一批可只做通用防具钩子或先启用少量防具效果。 |
| `attack_horse_*` | -1 马 | 装备牌 | 影响到其他玩家的距离。 |
| `defense_horse_*` | +1 马 | 装备牌 | 影响其他玩家到自己的距离。 |
| `dismantle` | 过河拆桥 | 非延时锦囊 | 弃置目标区域一张牌。 |
| `snatch` | 顺手牵羊 | 非延时锦囊 | 距离 1 内获得目标区域一张牌。 |
| `draw_two` | 无中生有 | 非延时锦囊 | 使用者摸两张牌。 |
| `duel` | 决斗 | 非延时锦囊 | 双方轮流出杀，失败者受伤。 |
| `barbarian_assault` | 南蛮入侵 | 非延时锦囊 | 其他玩家依次响应杀，未响应受伤。 |
| `arrow_barrage` | 万箭齐发 | 非延时锦囊 | 其他玩家依次响应闪，未响应受伤。 |
| `peach_garden` | 桃园结义 | 非延时锦囊 | 全体存活玩家回复 1 点体力。 |
| `negate` | 无懈可击 | 非延时锦囊 | 响应锦囊结算，抵消目标锦囊效果。 |

牌包约定：

- `standard_108` 是第一版已锁定游戏牌包，必须在 manifest 里写清楚每张牌的花色、点数、类型、效果和启用状态。
- 如果选择做标准牌堆 + 军争扩展，常见基线是 160 张游戏牌；但项目代码仍不得写死这些数字，必须读取 `card_pack_manifest.cards.size()`。
- 市面上看到的 268、384 这类数字通常是整盒或合集总卡数，可能混有游戏牌、武将牌、身份牌、体力牌、扩展武将、闪卡或收藏卡；不能直接当成一局摸牌牌堆。
- 项目里要拆开配置：`card_pack_manifest` 只放会进入牌堆或可进入区域结算的游戏牌，`general_pack_manifest` 放武将，身份和体力由规则包字段表达。
- 新增装备、锦囊或技能前，先扩展卡牌目录、合法动作生成、响应窗口和规则测试，再改 UI 和 AI。
- UI 展示“当前启用牌”时读取 `enabled_card_keys`，不维护自己的卡牌常量。

数量口径：

| 口径 | 建议实现含义 | 数量示例 |
| --- | --- | --- |
| 标准牌堆 | 一局摸牌、出牌、弃牌用的游戏牌。 | 常见 108 张。 |
| 标准牌堆 + 军争 | 标准游戏牌加军争游戏牌。 | 常见 160 张。 |
| 武将包 | 选将候选，不进摸牌牌堆。 | 第一版 `standard_core_adult_female` 为 25 名。 |
| 身份/体力 | 房间规则和 UI 状态，不按游戏牌处理。 | 身份分布按人数配置；体力用数值/血条表达。 |
| 盒装/合集总卡数 | 商品包装或全套收藏口径。 | 可能出现 268、384 等，不能直接作为 `deck`。 |

## 阶段状态机

基础主流程：

```text
lobby
  -> setup
  -> draw
  -> play
  -> discard
  -> next turn draw
  -> ...
  -> completed
```

阶段职责：

| 阶段 | 职责 |
| --- | --- |
| `setup` | 分配身份、初始化血量、洗牌、发初始手牌、确定主公和首轮行动者。 |
| `draw` | 当前回合玩家摸牌。 |
| `play` | 当前回合玩家出牌或结束出牌。 |
| `discard` | 当前回合玩家弃到手牌上限。 |
| `response` | 目标玩家响应当前牌或效果。 |
| `dying` | 濒死玩家求桃。 |
| `completed` | 胜负已定，进入复盘。 |

自动推进约定：

- 摸牌阶段可自动结算后进入出牌阶段。
- 出牌阶段需要玩家提交 `play_card` 或 `end_play`。
- 弃牌阶段如果不需要弃牌，可以自动结束。
- 响应和濒死必须创建玩家任务，等待目标玩家或救援顺序玩家返回结果。
- 所有自动推进必须满足无展示 ACK 待确认、无设备任务待返回、无暂停状态。

## 响应窗口

响应窗口是三国杀区别于狼人杀和象棋的核心模块。任何需要其他玩家插入响应的结算，都必须先创建 `SanguoshaResponseWindow`，由它决定响应者、可选牌、超时默认行为和结算结果。

建议结构：

| 字段 | 说明 |
| --- | --- |
| `window_id` | 响应窗口 ID。 |
| `kind` | `dodge_slash`、`peach_dying` 等。 |
| `source_seat` | 发起效果座位。 |
| `target_seat` | 当前需要响应的座位。 |
| `responders` | 需要按顺序响应的座位列表。 |
| `cursor` | 当前响应者位置。 |
| `required_card_keys` | 可响应牌，例如 `["dodge"]`。 |
| `context` | 伤害、目标、原始牌等结构化上下文。 |
| `default_action` | 超时或 fallback 时的默认行为，例如 `pass`。 |
| `result` | 响应窗口完成后的结算结果。 |

例子：杀响应流程：

```text
玩家 A 使用杀指定玩家 B
  -> 引擎创建 response_window(kind = dodge_slash, target = B)
  -> B 收到 respond_card 请求，可选 card_key = dodge 或 pass
  -> B 出闪：窗口完成，杀无伤害
  -> B pass：窗口完成，进入伤害结算
```

濒死求桃流程：

```text
玩家 B 受伤后体力 <= 0
  -> 引擎创建 dying_context 和 response_window(kind = peach_dying)
  -> 按座位顺序询问可救援玩家
  -> 任一玩家出桃使 B 体力回到 1：窗口完成，继续原结算
  -> 全部 pass：B 死亡，检查胜负
```

约定：

- 响应窗口只保存当前插入式结算，不替代主阶段。
- 响应窗口完成后必须回到原结算上下文。
- fallback 必须可见：AI 或超时使用默认行为时，toast 或公开历史要能让玩家知道。
- 不允许 AI 在响应窗口外自行决定“现在需要出闪/出桃”；必须由引擎生成请求。

## 行动请求

`SanguoshaActionRequest` 建议字段：

| 字段 | 说明 |
| --- | --- |
| `request_id` | 请求 ID。 |
| `seat_index` | 目标玩家座位。 |
| `request_type` | `play_phase`、`discard_phase`、`respond_card`、`dying_peach`、`choose_option`。 |
| `current_question` | 给真人 UI 和 AI 的当前问题。 |
| `legal_actions` | 当前合法动作列表。 |
| `visible_state` | 当前玩家可见牌局状态。 |
| `timeout_ms` | 可选超时。 |
| `default_action` | fallback 或超时默认动作。 |

`legal_actions` 每项建议包含：

| 字段 | 说明 |
| --- | --- |
| `action_id` | 本次请求内唯一动作 ID。 |
| `action_type` | `play_card`、`discard_cards`、`respond_card`、`pass`、`end_play`。 |
| `card_ids` | 需要使用或弃置的牌 ID。 |
| `target_seats` | 目标座位。 |
| `card_key` | 牌名键。 |
| `label` | 展示文本。 |
| `score_hint` | 简单策略评分，可给 AI 和 fallback 使用。 |
| `tags` | `damage`、`save_self`、`required` 等标签。 |

约定：

- 真人 UI 只能提交 `legal_actions` 中存在的动作，或按 UI 输入转换成其中一个动作。
- AI schema 必须限制返回 `action_id`。
- 引擎收到结果后仍要重新校验，不能信任客户端。
- 非法行动不写入历史、TTS、记忆或复盘。

## 规则校验

三国杀房间模块必须完成最终校验：

- 行动者是否是当前请求指定玩家。
- 请求是否仍然有效，`request_id` 是否匹配。
- 玩家是否存活。
- 牌是否在该玩家当前可用区域。
- 当前阶段是否允许该行动。
- 目标是否有效、存活、数量正确。
- 出杀次数、手牌上限、濒死求桃和响应窗口限制是否满足。
- 结算后是否触发伤害、濒死、死亡和胜负。

校验顺序建议：

1. 校验请求和行动者。
2. 校验行动是否存在于最新 `legal_actions`。
3. 校验卡牌归属和目标。
4. 从手牌或区域移除卡牌。
5. 写入公开或私有事件。
6. 进入响应窗口或直接结算效果。
7. 检查濒死、死亡和胜负。
8. 生成下一步行动请求或自动推进。

## 可见性和快照

三国杀快照必须按接收者座位生成。

公开字段：

- 房间、地图、阶段、当前行动者。
- 座位、昵称、在线状态、存活状态。
- 主公身份；身份局其他暗身份仅本人可见，游戏结束后公开。
- 血量、最大血量、手牌数量。
- 弃牌堆、公开出牌事件、伤害事件、死亡事件。
- 当前公开请求，例如“2号需要出闪”。

私有字段：

- 本人手牌详情。
- 本人暗身份。
- 只发给当前响应者的 `legal_actions`。
- AI 本地 prompt、schema、模型输出、API Key、模型配置。

复盘字段：

- 游戏结束后公开所有身份、完整事件、胜负原因、关键出牌和死亡顺序。
- 可公开最终手牌，但不公开模型 prompt 或 AI 草稿。

## AI 行为

三国杀 AI 复用象棋和狼人杀的 AI 四件套：

```text
ai_sanguosha_turn_context_builder.gd
ai_sanguosha_prompt_renderer.gd
ai_sanguosha_response_schema_builder.gd
ai_sanguosha_output_parser.gd
```

AI 输入上下文必须包括：

- 当前玩家座位、身份视角、血量、手牌。
- 公开座位信息和已知身份。
- 最近公开事件。
- 当前阶段或响应窗口。
- `legal_actions` 和 `default_action`。
- 简短策略提示，例如保命、优先杀敌方阵营、濒死优先救主公或自己。

AI 输出建议：

```json
{
  "action_id": "a_003",
  "reason": "目标是反贼且当前可以造成伤害"
}
```

AI 约束：

- AI 只能返回 `legal_actions` 里的 `action_id`。
- 输出解析失败、动作不存在、模型不可用时，必须使用引擎给出的 `default_action` 或本地评分最高动作。
- fallback 必须弹 toast，不能无感执行。
- fallback 行动进入历史时，要用清晰文本说明是“AI 兜底响应”或“AI 超时默认”。
- 主机端不调用模型；控制 AI 的设备本机调用模型并返回玩家行动结果。

fallback 策略：

| 场景 | 默认动作 |
| --- | --- |
| 出牌阶段模型失败 | 优先使用 `score_hint` 最高动作；没有动作则 `end_play`。 |
| 弃牌阶段模型失败 | 按低价值牌弃到合法数量。 |
| 杀响应模型失败 | 默认 `pass`，除非本地策略明确必须出闪。 |
| 濒死求桃模型失败 | 本人濒死且有桃则出桃；救主公优先；否则 `pass`。 |

## 真人 UI

真人玩家模块只负责把请求变成人能操作的 UI。

基础交互：

- 出牌阶段显示可用手牌、可选目标和结束出牌按钮。
- 需要响应时只显示可响应牌和“不出”按钮。
- 弃牌阶段显示需弃数量和可选手牌。
- 濒死求桃显示救援对象、当前血量和可出桃按钮。

约定：

- UI 可以高亮合法牌和合法目标，但不能绕过引擎。
- UI 提交前可以本地预校验，提交后仍由主机引擎最终校验。
- 当前玩家私有手牌不能在旁观者或其他玩家设备显示。
- 断线重连后恢复当前阶段、手牌、合法动作和待响应窗口。

## 事件和历史

事件分层：

| 类型 | 示例 | 可见性 |
| --- | --- | --- |
| `system` | 游戏开始、进入回合 | 公开 |
| `card_played` | 1号对3号使用杀 | 公开 |
| `card_responded` | 3号打出闪 | 公开 |
| `damage` | 3号受到1点伤害 | 公开 |
| `dying` | 3号濒死，等待桃 | 公开 |
| `death` | 3号死亡 | 公开 |
| `private_hand` | 玩家摸到的具体牌 | 仅本人 |
| `fallback` | AI 使用兜底动作 | 公开或目标可见，按动作决定 |

历史约定：

- 接受后的公开出牌、响应、伤害和死亡进入公开历史。
- 摸牌具体内容只进入本人私有事件；公开历史只显示“摸两张牌”。
- AI prompt、模型原始输出和解析失败详情只进入本机 debug，不进入房间历史。
- 复盘在游戏结束后可公开完整身份和关键事件。

## 重连和主机接管

重连恢复必须包含：

- 当前地图、阶段、回合、行动者。
- 每个玩家公开状态。
- 本人手牌、本人身份和本人待处理请求。
- 当前响应窗口或濒死上下文。
- 弃牌堆、公开事件和本人私有事件游标。

主机接管必须恢复权威状态：

- 牌堆、弃牌堆、手牌、血量和身份。
- 当前阶段、响应窗口、待结算伤害和濒死上下文。
- 已接受事件序号和房间快照版本。

如果接管材料缺失关键私有状态，例如牌堆或手牌，则不能静默继续，应提示房间无法安全接管。

## 实现顺序

建议按这个顺序做：

1. 新增文档、目录、场景和空房间页，能从创建房间进入三国杀房间。
2. 新增 `sanguosha_rule_pack_catalog.gd`、`sanguosha_map_catalog.gd`、`sanguosha_card_catalog.gd`、`sanguosha_general_catalog.gd`，先让创建房间页能展示 2 人、4-8 人、108 张标准牌、25 名标准核心武将和启用技能。
3. 新增 `sanguosha_engine.gd`，打通 `duel_2p` 和 `identity_4p` 的 setup、选将、发牌、摸牌、出牌、弃牌。
4. 新增 `sanguosha_action_window.gd`，完成杀/闪、濒死求桃、无懈可击等响应窗口基础能力。
5. 接入装备区和距离规则，先支持武器、坐骑、同槽位替换和装备弃置。
6. 接入第一批非延时锦囊：过河拆桥、顺手牵羊、无中生有、决斗、南蛮入侵、万箭齐发、桃园结义、无懈可击。
7. 扩展身份局到 5-8 人，验证角色分布、座位布局、胜负和 AI 阵营目标。
8. 新增真人 UI 手牌、装备区、目标选择、响应和濒死交互。
9. 新增 AI runtime，先基于 `legal_actions`、`score_hint`、身份目标和局势摘要选择。
10. 新增网络快照脱敏、重连恢复、复盘和测试覆盖。

不要先写复杂 prompt。三国杀的智能程度主要来自规则引擎给出的合法动作和局势摘要，prompt 只负责在合法动作里做选择。

## 测试建议

最低测试覆盖：

- 2 人对决开局、选将、发牌、胜负正确。
- 4-8 人身份局角色分布、主公公开、暗身份可见性正确。
- `standard_core_adult_female` 能满足 8 人每人 3 选 1，候选不足时开局失败并提示配置错误。
- `standard_108` 生成的牌堆数量、花色、点数、启用牌集合正确。
- 摸牌阶段自动摸牌并进入出牌阶段。
- 出杀会创建闪响应窗口。
- 目标出闪后不受伤害。
- 目标不出闪后受伤害。
- 装备牌进入正确槽位，同槽位替换旧装备。
- 武器和坐骑距离影响目标合法性。
- 过河拆桥、顺手牵羊、无中生有、决斗、南蛮入侵、万箭齐发、桃园结义、无懈可击的目标和基础结算正确。
- 濒死求桃成功后继续游戏。
- 濒死无人救援后死亡并检查胜负。
- 弃牌阶段只允许弃到手牌上限。
- 非法 card_id、非法目标、错误行动者都会被拒绝。
- 玩家快照只包含本人手牌，不泄漏其他玩家手牌。
- AI 输出非法 action_id 时 fallback 并弹 toast。

## 维护规则

- 三国杀规则只写在 `scripts/room/sanguosha/`，不要散落到大厅、通用房间或玩家模块。
- 创建房间 UI 只消费三国杀 map catalog，不维护自己的三国杀人数和地图常量。
- 真人 UI 和 AI 只能提交行动结果，不复制规则判断。
- 所有出牌、弃牌、响应和救援都必须来自引擎生成的 `legal_actions`。
- 只有 `SanguoshaRuleUpdateResult(ok = true)` 可以驱动特效、历史、TTS、复盘和下一步请求。
- AI 模型失败或结构化输出失败时，fallback 必须可见，不能无感执行。
- 新增卡牌或技能前，先扩展卡牌目录、合法动作生成和规则测试，再改 UI 和 AI。
