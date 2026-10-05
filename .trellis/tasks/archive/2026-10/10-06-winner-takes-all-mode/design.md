# Design：新游戏模式「胜者为王」技术设计

## 1. 架构定位

本模式是**规则变体**，不是新玩法系统：复用既有的 `IdentityRules`（规则与数值唯一权威）+ `MatchController`（对局唯一权威）+ `GameState`（状态唯一权威），只新增一条模式分支链。不新增专属服务、不新增专属技能、不新增 `PlayerState` 字段。

```
静态数据         GameSettings（模式 ID、人数槽、座次补偿开关）
                          ↓ 开局锁定
状态与规则       IdentityRules（身份表 / 胜负 / 队友 / 奖惩 / 开局加值 / 座次补偿数值）
                          ↓
事件与运行时     MatchController + GameState（开局座次、发牌、体力上限、终局判定；match_options 为本局唯一权威）
                          ↓
动作协议         PlayerAction（不变）
                          ↓
AI / 网络 / UI   IdentityAIModel（态度口径）· NetworkGateway（模式注册 + 房间开关）· MainMenu / MatchMenu / Lobby / MatchTable
```

### 1.1 关键不变量（沿用既有架构约束）

- **单一权威**：`MatchController` + `GameState` 是唯一可写方；UI / AI / 网络只读快照并提交 `PlayerAction`。座次补偿的数值在**开局时锁定**进 `state.match_options`，此后 UI 的任何改动都不影响进行中的对局。
- **参数前置**：所有新增可调数值（座次补偿档位、获胜 ID、协议版本）提取为脚本顶部常量或 `@export`，不写内联魔法数字。
- **单向分层**：`IdentityRules` 不认识 `GameSettings`（不接受"开关是否开启"）。开关由 `MatchController` 在开局时解析为布尔值，再把布尔值传给规则函数；规则函数只回答"这个模式 + 这个座次 + 是否开启 → 多少"。
- **不重命名、不删除既有注释**：所有对既有函数的改动都是**追加分支**或**追加可选参数**。

## 2. 由仓库证据确定的决策（Decisions Made From Repository Evidence）

这些不是产品选择，而是被现有代码结构唯一确定的实现取值，记录以避免后续被误改。

### D1 复用 `renegade`，不新增身份 ID
`are_identities_teammates("renegade", "renegade")` 在身份局逻辑下已返回 false（内奸互不为队友），`_identity_text()` 与四处 UI 身份映射（`character_selection_panel.gd:95`、`online_lobby_avatar.gd:56`、`match_controller.gd:18347/18360`）已把 `renegade` 映射为「内奸」。新增身份 ID 需要同步 4+ 处映射表且无收益。

### D2 身份开局公开（`is_identity_public_at_start` → true）
全员身份相同，隐藏无意义。收益：绕开整套隐藏身份机制（暴露度、自动标记、身份猜测面板），与斗地主 / 2v2 / 车轮战 / 过关斩将的「公开身份」模式一致。`_update_identity_mark` 在 `identity_revealed == true` 时已提前返回，无需额外改动。

### D3 专属获胜 ID `"last_survivor"`
**不能复用 `"renegade"`**：`match_table.gd:5645` 的 `_is_local_player_victory` 按「获胜 ID + 本地身份」判定，全员身份都是 `renegade` 时会导致**每个客户端都显示游戏胜利**。因此本模式返回独立 ID，终局判定改为「本地玩家是否存活」。
`"draw"` 复用既有平局语义（全员同时阵亡）。

### D4 首回合 = 一号位，且座次索引全程稳定
`get_first_player_identity` 返回 `""` + `starts_from_first_seat` 返回 `true`。
座次稳定性已由代码保证：`_create_players()` 在玩家创建后立即调 `_reorder_players_from_leader()`（`:9556`）把数组排成最终座次，早于选将（`:1594`）与发牌（`:11418`）。本模式下没有 `leader` 身份，`leader_index` 恒为 `-1`，`:11754` 的 `if leader_index > 0` 不成立 → **不发生旋转**，数组下标从创建起就等于最终座次 - 1。发牌后 `:11431` 的第二次调用同样不旋转。
→ 座次补偿可以安全地以 `state.players` 数组下标（1 基座次 = 下标 + 1）为准。`PlayerState` 无座次字段，座次一律**按需派生**（`state.players.find(player) + 1`，沿用 `match_controller.gd:4244` 的既有惯用法），不新增字段。

### D5 击杀摸 3 张无需改结算层
`death_resolution_service.gd:237-238` 已存在 `elif reward == "draw_three" and killer != null and killer.alive: _host.draw(killer.player_id, 3)`。因此只需让 `IdentityRules.get_death_reward` 在本模式返回 `"draw_three"`，**死亡结算服务零改动**，且天然继续经过 `MatchController.resolve_death_reward` 唯一端口（武将技能仍可覆盖）。

### D6 座次补偿数值放在新增函数，不改 `get_opening_max_hp_bonus` 签名
`get_opening_max_hp_bonus(identity, player_count, mode_id)` 被 `tests/doudizhu_mode_test.gd:124` 与 `tests/team2v2_mode_test.gd:111` 以 3 参调用。改签名会波及既有测试；且体力上限补偿是**座次驱动**而该函数是**身份驱动**，语义不同。故新增两个纯函数（见 §4.2），`get_opening_max_hp_bonus` 一行不改。

### D7 开关的两个存储位置 + 一处解析
仓库对「房间级开关」与「本地菜单开关」已有两种泾渭分明的先例：
- `custom_identity_enabled` / `fixed_seat_enabled`：**仅** `NetworkGateway` 房间状态（内存，不持久化，无菜单入口）。
- `custom_character_assignment_enabled` / `conquest_opportunity_choice_mode`：**仅** `GameSettings`（持久化，主菜单 + 局内菜单，无大厅入口）。

座次补偿需要同时覆盖三处，因此采用两者并集，并明确解析规则：

| 场景 | 权威来源 | 说明 |
|---|---|---|
| 单机 / 人机 | `GameSettings.seat_compensation_enabled` | 持久化，主菜单与局内菜单直接读写 |
| 局域网房主 | `NetworkGateway._lobby_seat_compensation_enabled`（房间状态） | 大厅房间设置读写，经房间快照广播给客户端 |
| 局域网客户端 | 房主广播的快照值（只读） | 与 `custom_identity_enabled` 完全同构；客户端也不开局，不参与 `start_match` |

解析发生在 `start_match` 中，结果写入 `state.match_options["seat_compensation_enabled"]`，此后**本局唯一权威**就是该键。主菜单值与房间值不同步是**有意为之**（与既有 `custom_identity_enabled` 不写回 `GameSettings` 的先例一致），已在实现清单中标注。

### D8 不加入机缘系统
`opportunity_enabled_mode_ids` / `opportunity_manual_mode_ids` 均不新增本模式。依据：`docs/内容制作指南.md:3921`「新增模式必须明确选择其触发模型，普通身份模式不应因组件存在而自动获得机缘规则」。

### D9 不放开联机自选身份
`supports_lobby_custom_identity(MODE_WINNER_TAKES_ALL)` → false。只有一种身份，自选无意义；与过关斩将「真人固定红方无可选身份」同类。`get_lobby_slot_identities` 仍会返回全 `renegade`（经由 `get_distribution`），但大厅不会进入自选身份分支。

### D10 AI 只需一处模式分支
- `identity_ai_model.get_attitude` 在目标 `identity_revealed == true` 时直接返回 `get_real_attitude` 的结果（D2 使其必然成立）。
- `get_real_attitude` 末尾 `if to_identity == "renegade": return 0.0`（`:426-427`）是**核心缺陷**：全员内奸时所有对手都被判为中立 0.0。
- `identity_strategy_evaluator` 的内奸分支（`:207-208` / `:214-215` / `:375-381`）在没有主公/忠臣/反贼时会**安全退化**：`_score_renegade_negative_effect` 落到 `:497` 的「压制综合状态更强者」（自由混战下正确），`_score_renegade_positive_effect` 返回 0.0（无队友可扶，正确），`score_rescue` 不产生救助奖励（自由混战下救对手是错的，正确）。`_is_confirmed_ally("renegade","renegade")` 在 `:305` 返回 false → 不产生「误杀同阵营」惩罚；`target_identity == "rebel"` 不存在 → 不产生虚假 +3.0。
→ **只需在 `get_real_attitude` 顶部加一个模式分支**，其余 AI 逻辑保持不变。这是本设计中最省改动、最不容易引回归的选择。

### D11 选将服务必须接入，否则**对局根本无法开始**
这是与「模式注册」并列的第二个 P0 阻断项，已逐行核实：

```
begin() :391 inferred_mode = "identity"          ← 本模式身份既非 landlord/peasant 也非 blue/red
       :400-407 三个显式分支都不匹配 → else: match_mode = "identity"
       :409 uses_leader_priority_selection() → true（= not simultaneous and not conquest）
       :422-428 leader_player_id 三处赋值都不命中（无 leader、无 landlord，:426 只覆盖 2v2/过关斩将）
       :429-431 if leader_player_id < 0: return "身份配置缺少领袖，无法开始选将。"   ← 直接失败
```
即使跳过此处，`match_controller.gd:11478-11481` 也会因 `_find_player_by_identity("leader")` 返回 null 而 `push_error("对局缺少首回合角色，无法开始首回合。")` 并 `return`。

因此 `character_selection_service.gd` 需要 **5 处**改动：
1. 新增 `is_winner_takes_all_mode()` 判定（形态照抄 `is_conquest_mode()`，`:124-125` 的裸字符串风格与本文件保持一致）。
2. `begin()` 模式解析（`:400-407`）加显式分支 `elif requested_match_mode == "winner_takes_all": match_mode = "winner_takes_all"`。**必须先确认调用方确实传入该 ID**（`match_controller.gd:1594` 的 `character_selection.begin(...)` 实参）——若传入的是空串，本模式的 `is_winner_takes_all_mode()` 会为 false，回到 `"identity"`，`get_first_seat_identity()` 又返回 `"leader"`，P0 复现。
3. `get_first_seat_identity()`（`:103-110`）加入返回 `""` 的分支（本模式没有主公，一号位不绑定首任身份）。
4. `leader_player_id` 的"无首任身份则记一号位"回落分支（`:426`）的 `is_team2v2_mode() or is_conquest_mode()` 补上 `or is_winner_takes_all_mode()`，使 `:429` 的领袖校验通过。
5. 跳过领袖技候选注入：`:409` 的 `if uses_leader_priority_selection():` 与 `:439` 的 `_make_candidates(leader_player_id, "", true)` 各加 `and not is_winner_takes_all_mode()`。原因：`_make_candidates`（`:949-975`）会把领袖技武将**前置为锁定候选**（`:959-966`、`:973`），本模式没有主公，主公技武将对任何人都无意义，让一号位额外背一组锁定候选是纯劣势。

**保持不变**：`uses_leader_priority_selection()`（`:167-168`，保持 true ⇒ 复用 PHASE_LEADER 状态机实现"一号位先选、再顺时针"，与 D4 一致）与 `uses_simultaneous_selection()`（`:154-155`，保持 false ⇒ 选将状态机与 AI 等待门禁零改动）。
`character_selection_panel.gd` 的 `selection_mode` 推断（`:865-885`）与 `_get_first_seat_identity_id()`（`:913-932`）各加一条分支。

### D12 主公技/领袖技在本模式全程休眠（接受，不修）
`skill.leader_skill and identity != "leader"` 的多处判定（`match_controller.gd:4722/4761/10845/10891/16014`、`match_table.gd:2159`、`basic_ai_policy.gd:422`、`identity_strategy_evaluator.gd:292`）会让全部主公技失效。
这是**既有模式的同一行为**：`team2v2` / `wheel_duel` / `conquest` 同样没有 `leader` 身份，主公技在这些模式下本来就休眠。本模式与之一致，因此不新增豁免、不改动任何既有判定。
副作用：主公技武将（如依赖领袖身份的角色）在本模式强度偏低，属于可接受的模式特性，不进入本次范围。

### D13 依赖主公/反贼的武将技能静默失效（接受，不修）
`game_data/skills/zhengfu.gd`（只处理 leader/loyalist/rebel）、`lunhui.gd:46`（友方列表为空）、`xifa.gd:153/158`、`yongjie.gd:259`、`game_data/cards/tao.gd:387-401`（`_has_endangered_leader` 要求存在主公）在无主公/无叛军的局面下自然不生效。
与 D12 同属既有非身份模式的共同行为（2v2 / 车轮战 / 过关斩将已有同样情形），本次不逐一改写，只登记在案。

### D14 已核实「无需改动」的清单（防止实现期做多余修改）
| 位置 | 现状 | 结论 |
|---|---|---|
| `match_controller.gd:18314` `_identity_attitude` | `if from_identity == "renegade": return -1` → 全员内奸时对每个目标已是**敌对** | 零改动；`_should_auto_negate`（`:18287`）行为正确 |
| `identity_rules.gd:235-256` `are_identities_teammates` | 已明确"两个内奸之间也不互为队友" → `is_friendly(self)=true` / `is_friendly(others)=false` | 零改动即满足混战语义（T1.8 只是把该结论显式化到模式分支） |
| `card_rule_service.gd` 距离与目标校验 | 全文 grep `identity` / `friendly` / `teammate` **零命中** | 全员非队友既不新增禁选也不解锁任何目标，零改动 |
| `identity_strategy_evaluator.gd:300-305` `_is_confirmed_ally` | 对内奸行动者恒 false（`:305` 兜底 `return false`） | 不产生"误伤队友"惩罚，零改动 |
| `player_state.gd:543` 身份遮罩 + `match_controller.gd:17916/17936/17957` 逐观察者分发 | 单一遮罩点 + 每客户端裁剪 | 反作弊无需新增过滤点 |
| `match_table.gd:847` / `:881` 的身份标记入口 | `:851` 要求 `identity == "hidden"` | 本模式身份开局公开（D2）⇒ 手动标注菜单不可达、自动标注无输入，**零改动**（改为验证项） |
| `match_table.gd:4195` `set_auto_identity_marking_visible(current_match_mode == "identity")` | 本模式已被排除 | 零改动 |
| `rule_timing_catalog.gd:93-96` `MODE_TIMINGS` | 是**规则时机事件名**列表，与模式 ID 无关 | 零改动 |
| `_winner_text` 之外的 `renegade` 文案映射（`match_controller.gd:18347`、`player_target_view.gd:1173/1458`、`character_selection_panel.gd:95/495`、`online_lobby_avatar.gd:56`） | 已具备「内奸」映射 | 零改动 |
| `game_data/cards/yinyueqiang.gd:93`、`game_data/skills/yongyi.gd:163` | 用 `get_identity_attitude(...) < 0` 判敌 | 全员 `-1` ⇒ 行为正确，零改动 |
| `opportunity_system.gd:998/1010/1020-1023/1032-1036`、`opportunity_effect_resolver.gd:641` 敌我统计 | 全员敌对 ⇒ 自动走"敌人多"分支 | 本模式不开启机缘（D8），零改动 |

## 3. 模式注册权威清单（按依赖顺序）

| # | 文件 | 位置 | 改动 |
|---|---|---|---|
| 1 | `scripts/core/identity_rules.gd` | 常量块 `:7-22` | 新增 `MODE_WINNER_TAKES_ALL: String = "winner_takes_all"` |
| 2 | 同上 | `:59-70` `normalize_mode` | 白名单加该 ID（**不做这一步则后续全部分支不可达**） |
| 3 | 同上 | `:110-132` `get_distribution` | 新增分支：对 2—10 返回 n 个 `"renegade"` |
| 4 | 同上 | `:136-137` `supports_lobby_custom_identity` | 返回 false（D9） |
| 5 | 同上 | `:173-178` `get_first_player_identity` | 加入返回 `""` 的分支 |
| 6 | 同上 | `:182-184` `starts_from_first_seat` | 加入返回 true 的分支 |
| 7 | 同上 | `:200-204` `is_identity_public_at_start` | 加入返回 true 的分支 |
| 8 | 同上 | `:235-256` `are_identities_teammates` | 新增分支恒 false（显式，防止未来身份变化时借用领袖/忠臣逻辑） |
| 9 | 同上 | `:278-291` `evaluate_winner` | 新增分支 `_evaluate_winner_takes_all_winner(state)` |
| 10 | 同上 | `:299-315` `get_death_reward` | 新增分支：killer 非空 → `"draw_three"`（D5） |
| 11 | 同上 | 文件末尾新增私有函数 | `_evaluate_winner_takes_all_winner(state)` + 两个座次补偿纯函数（§4.2） |
| 12 | `scripts/autoload/game_settings.gd` | `:263-278` | 新增 `MATCH_MODE_WINNER_TAKES_ALL` 常量 |
| 13 | 同上 | `:280-316` | 新增 `DEFAULT_WINNER_TAKES_ALL_PLAYER_COUNT: int = 8` 与 `DEFAULT_SEAT_COMPENSATION_ENABLED: bool = false` |
| 14 | 同上 | `:346-361` | 新增 `next_match_player_count_winner_takes_all: int = 8` + 逐行注释 |
| 15 | 同上 | `:371` 附近 | 新增 `seat_compensation_enabled: bool = false` + 逐行注释 |
| 16 | 同上 | `:25-59` 信号区 | 新增 `seat_compensation_enabled_changed(enabled: bool)` |
| 17 | 同上 | `:587-598` `normalize_match_mode` | 加入该 ID |
| 18 | 同上 | `:621-651` | `get_stored_player_count_for_mode` / `_store_player_count_for_mode` 加入该模式槽 |
| 19 | 同上 | `:673-678` 附近 | 新增 `set_seat_compensation_enabled(enabled)` setter（发射信号 + 排队保存） |
| 20 | 同上 | `:881-911` 读档、`:993-1029` 存档 | 新增人数槽与开关的读写；**读档缺字段时回落默认值**（R8.2） |
| 21 | `scripts/network/network_gateway.gd` | `:106-113` `LOBBY_GAME_MODE_OPTIONS` | 新增 `{id, display_name: "胜者为王"}` |
| 22 | 同上 | `:1682-1684` `_is_lobby_game_mode_playable` | 字面量白名单加该 ID（**只改 21 会导致局域网开局被拒**） |
| 23 | 同上 | `:61` + `:56-60` | `PROTOCOL_VERSION` 10 → 11 + 变更说明注释（房间快照新增字段） |

> 人数范围无需改动：`get_supported_player_counts` 的 else 分支取 `IDENTITY_DISTRIBUTIONS` 的键（2—10）；`GameSettings.normalize_player_count_for_mode` 与 `NetworkGateway._normalize_lobby_player_count` 的默认分支均已按 2—10 收敛；`online_lobby_panel` / `match_menu` 的人数上下限 else 分支已为 2/10/步长 1。已逐处核对。

## 4. 数据契约

### 4.1 `state.match_options` 新增键

在 `match_controller.gd:1537-1553` 的字典字面量中追加（与既有 `lan_custom_identity_enabled` / `lan_fixed_seat_enabled` 同级、同风格）：

| 键 | 类型 | 语义 |
|---|---|---|
| `seat_compensation_enabled` | `bool` | 本局是否启用座次补偿；开局锁定，进行中不变 |

解析规则（D7）：

```
局域网友机且本端为房主 → network_gateway.is_lan_seat_compensation_enabled()
其他情况（单机 / 人机）→ GameSettings.seat_compensation_enabled
```

必须带空值守卫（`network_gateway != null` / `GameSettings != null`），与相邻键的写法保持一致，保证无头测试环境（测试只挂 `NetworkGateway`，部分测试直接 `IdentityRules.new()`）不报错。

### 4.2 `IdentityRules` 新增纯函数签名

```
## 返回胜者为王模式按开局座次追加的初始手牌数；非本模式或未开启时返回 0。
## seat_number 为 1 起始的规则座次；越界（<1）返回 0。
func get_seat_compensation_hand_bonus(mode_id: String, seat_number: int, enabled: bool) -> int
    # 座次 1、2 → 0；3、4 → 1；5、6 → 2；7、8 → 3；9、10 → 4
    # 等价 floor((seat_number - 1) / 2)，由常量 WINNER_TAKES_ALL_HAND_BONUS_SEAT_PAIR_SIZE = 2 驱动

## 返回胜者为王模式按开局座次追加的体力上限；非本模式或未开启时返回 0。
func get_seat_compensation_max_hp_bonus(mode_id: String, seat_number: int, enabled: bool) -> int
    # 座次 5—8 → +1；9 及以上 → +2；其余 → 0
    # 由常量 WINNER_TAKES_ALL_HP_BONUS_FIRST_SEAT = 5 / SECOND_SEAT = 9 与对应增量常量驱动

## 返回胜者为王模式的获胜方 ID；仅剩一名存活玩家时为其胜出，无人存活时为平局，其余情况为空。
func _evaluate_winner_takes_all_winner(state: GameState) -> String
    # 存活 1 人 → WINNER_TAKES_ALL_WINNER_ID（"last_survivor"）
    # 存活 0 人 → "draw"
    # 存活 ≥2 人 → ""
```

数值全部提取为脚本顶部常量（`@export` 不适用：这是规则服务而非场景节点，沿用 `DISTRIBUTIONS` 等常量的既有风格），满足「参数前置」。

### 4.3 终局文案与本地胜负

| 位置 | 改动 |
|---|---|
| `match_controller.gd:18356-18365` `_winner_text` | 新增映射 `"last_survivor"` → 「最后的胜者」 |
| `match_table.gd:5635-5650` `_is_local_player_victory` | 新增分支：`winner == "last_survivor"` 时，**以本地玩家是否存活**为判定依据（读取本地玩家的 `alive`），而不是比对身份 |
| `match_table.gd:5653-5664` `_resolve_match_result_effect_id` | 走既有胜利/失败音效分支，无需新增 |

`state.winner == "last_survivor"` 时 `end_reason` 沿用既有 `"identity_result"`（非牌堆耗尽的自然终局），与斗地主/2v2 的终局表现路径一致。

**已知取舍**：全员同时阵亡时返回 `"draw"`，`_check_game_over` 会把 `end_reason` 记为 `"identity_result"` 而非 `"deck_empty"`。这是既有代码对"非牌堆终局平局"的统一处理，不在本次改动范围内（改为牌堆语义会污染其他模式）。

### 4.4 房间快照新增字段

`network_gateway.gd` 的 `get_lan_lobby_snapshot()`（`:397-409`）新增 `seat_compensation_enabled`；配套改动：`host_lan`（`:269`，位置参数追加）、`update_lan_lobby_settings`（`:437`，位置参数追加）、`_apply_remote_lobby_state`（`:1377-1398`，读取）、房间状态变量（`:161-167` 附近）与 `_set_offline_state` 重置（`:1740-1743`）、`is_lan_seat_compensation_enabled()` 只读访问器（形态照抄 `:426-427`）。
`host_lan` / `update_lan_lobby_settings` 是**位置参数**函数，实现前必须先 grep 全部调用点（`match_table.gd:946-950`、大厅面板信号、既有局域网测试）再统一更新。

### 4.5 开局数值的两个写入点

| 目标 | 写入点 | 表达式 |
|---|---|---|
| 初始手牌 | `match_controller.gd:11418-11424` 的 `seat_hand_count` | 既有的「基础 + 2v2 四号位 + 机缘」累加串**再追加**`get_seat_compensation_hand_bonus(match_mode, seat_index + 1, 座次补偿开关)` |
| 体力上限 | `match_controller.gd:9647-9669` `_refresh_pre_game_character_stats` | 既有的 `get_opening_max_hp_bonus(...)` 结果**再追加**`get_seat_compensation_max_hp_bonus(match_mode, seat_number, 座次补偿开关)`；`seat_number = state.players.find(player) + 1` |

**为什么座次补偿必须再乘一个"开关"布尔**：开关是局面选项而非模式常量，规则服务不认识设置层（§1.1）。这让"关闭时的开局数值 == 改动前的开局数值"成为可单测的恒等式（AC-4.1 / AC-4.5）。

`_refresh_pre_game_character_stats` 会在**中局**被换将/复活路径重入（车轮战下一名武将、过关斩将替换敌人与复活）。本模式下这些路径不会发生，且两个补偿函数在非本模式返回 0，因此不需要额外守卫；但实现时必须**逐点核对**这 4 个调用点，确认本模式无法进入（见 `implement.md` 验证清单 V6）。

手气卡重发（`_refresh_starting_hand`，`:11651-11685`）使用 `returned_cards.size()` 作为重发张数，因此**零改动**即满足 R4.6；`gameDraw` 运行时事件与开局日志（`:11425` / `:11483`）当前只报基础张数，座次补偿数值在这些诊断记录中不可见（2v2 四号位补偿有专属键 `team2v2_seat4_bonus` 作为先例）。本次**不扩展**该事件结构以免影响回放兼容性，改为在开局日志追加一句座次补偿摘要（见 `implement.md` T4.4）。

## 5. 数据流

### 5.1 开关 → 本局生效

```
主菜单勾选 ──写──> GameSettings.seat_compensation_enabled（持久化，发信号刷新 UI）
大厅房主勾选 ──写──> NetworkGateway._lobby_seat_compensation_enabled（内存）
                              │  lobby_state 快照（PROTOCOL v11）
                              └──> 客户端只读显示
                                          │
start_match ──解析──> state.match_options["seat_compensation_enabled"]  ← 本局唯一权威
                                          │
              ┌───────────────────────────┴───────────────────────────┐
     发牌（:11418）读它决定 seat_hand_count           _refresh_pre_game_character_stats（:9647）读它决定 max_hp
```

### 5.2 胜负判定

```
击杀结算 → death_resolution_service 调用 _host._check_game_over()
        → IdentityRules.evaluate_winner(state)
        → 本模式分支：存活 1 人 → "last_survivor"；0 人 → "draw"；否则 ""
        → state.winner = 结果，add_log("对局结束，获胜方：最后的胜者。")
        → 快照 game_state.to_dict() 带出 winner
        → match_table._is_local_player_victory(winner)：本模式以本地玩家存活为准
```

### 5.3 AI 态度

```
AI 决策 → IdentityAIModel.get_attitude(snapshot, observer, target)
       → 目标 identity_revealed == true（本模式恒真）→ 返回 get_real_attitude(...)
       → 【新增】snapshot.match_mode == "winner_takes_all" → 返回自由混战敌对态度
       → 否则 走既有身份局/斗地主/2v2 逻辑（逐字不变）
```

快照已含 `match_mode`（`game_state.gd:246`），无需扩展快照结构。

## 6. UI 设计

### 6.1 主菜单（`scenes/main.tscn` + `scripts/ui/main_menu.gd`）

- `ModeCardsVBox`（`:1294`）在 `ConquestModeButton` 块（`:1521-1563`）之后插入第 7 张卡，**复用同一 5 节点结构**（`Button` + `<X>ModeContent`(VBoxContainer) + `<X>ModeName`(Label) + `<X>ModePlayerCount`(Label) + `<X>ModeIndicator`(ColorRect)），带全新 `unique_name_in_owner`。卡片内部**不得放 Button**（`tests/main_menu_test.gd:245` 用 `find_children("*","Button",true,false)` 递归计数模式卡数量）。
- 硬性视觉规格不可压缩：卡片高 100 像素、相邻间距 12、正文上下内边距 14、模式名 27 像素、人数提示 16 像素（`docs/内容制作指南.md:4026`）。7 张卡使内容高度 660 → 772，滚动条自然出现。
- 新增 `@onready`：`_winner_takes_all_mode_button`（`%WinnerTakesAllModeButton`）、`_winner_takes_all_mode_indicator`、`_seat_compensation_row`、`_seat_compensation_checkbox`。
- 互斥选中：`main_menu.gd` 无 `ButtonGroup`，靠每个 `_select_*_mode()` 显式把其他按钮 `button_pressed = false`。因此**新增 `_select_winner_takes_all_mode()` 的同时，必须在既有 6 个 `_select_*_mode()` 里各加一行关闭新按钮**，并同步把新指示灯的选中色加进 `refresh_ui_style()` 的两段。
- 设置行 `MainMenuSeatCompensationRow`（含 `MainMenuSeatCompensationCheckBox`）克隆自 `MainMenuConquestOpportunityChoiceRow`（`:1948-1961`），放在 `SettingsVBox`（`:1737`）内，显隐由 `_set_wheel_duel_settings_visible()`（`:1032-1056`，**唯一的按模式显隐网关**）统一控制：仅当选中「胜者为王」时可见。
- `MODE_DETAILS_BY_MODE`（`:84-97`）新增该模式键 → 详情按钮自动出现（`:1132` 以该字典为唯一谓词），详情正文按 R6.2 写入全部数值。
- `STARTING_STATUS_TEXT_*` / `_request_start_game()`（`:1341-1351`）新增该模式的起始状态文案。

### 6.2 局内菜单（`scenes/main.tscn` + `scripts/ui/match_menu.gd`）

- 设置行 `MatchSeatCompensationRow` 克隆自 `MatchConquestOpportunityChoiceRow`（`:472-484`）。
- 显隐接入 `_apply_mode_specific_settings_visibility()`（`:364-384`），并**必须同时更新**该文件里 3 处易漏的并行列表：焦点交还链（`:338`）、标签色覆盖（`:416-417`）、控件样式（`:437-438`）。
- 作用域：与自选武将/难度同语义（写 `GameSettings`，只影响下一局），`set_match_mode()` 后刷新。

### 6.3 联机大厅（`scenes/components/*.tscn` + `online_lobby_panel.gd` / `lan_lobby_panel.gd`）

- 两个面板各新增一个 `CheckBox` 行（克隆 `LanCustomIdentityCheckBox` `:169` / `OnlineLobbyCustomIdentityCheckBox` `:299` 同级结构）。
- `lan_lobby_panel.gd`：读取勾选值并加入 `host_requested` 信号（`:7`、`:208`）。
- `online_lobby_panel.gd`：房主可写；从房间快照回填显示值（`:372-380`）；加入 `settings_update_requested` 信号（`:16`、`:406`）；模式切换时按既有 disable 机制（`:552-566`）处理非本模式的禁用/隐藏。
- 模式下拉由 `_populate_game_mode_options`（`:533-539`）自动纳入新注册项，无需手写。

## 7. 边界与错误处理

| 场景 | 处理 |
|---|---|
| 开局时存活玩家 ≥ 2 | `evaluate_winner` 返回 `""`（对局继续） |
| 仅剩 1 人存活 | 返回 `"last_survivor"`，对局结束 |
| 全员同时阵亡（连锁传导） | 返回 `"draw"`，判平局，不崩溃 |
| 无来源伤害致死 / 自杀 | `get_death_reward` 既有 `killer == null` 早退分支返回 `""`，不发放摸牌 |
| 结束对局的最后一次击杀 | 既有流程在 `game_over` 后跳过奖惩步骤，本模式沿用（R3.4） |
| 座次补偿开启但人数为 2 | 座次 1、2 追加均为 0（数值表天然覆盖），无需特判 |
| 座位数 < 9 / < 5 | 体力上限追加自然为 0（阈值判断），无需特判 |
| 旧存档缺新字段 | 读档回落 `DEFAULT_WINNER_TAKES_ALL_PLAYER_COUNT` / `DEFAULT_SEAT_COMPENSATION_ENABLED`（R8.2） |
| 无头测试环境下 `network_gateway == null` 或 `GameSettings == null` | `match_options` 解析与三处 UI 读写全部带空值守卫 |
| 局域网客户端 | 房间开关只读显示；客户端不开局，`match_options` 由房主快照下发 |

## 8. 备选方案与取舍

| 方案 | 未采用原因 |
|---|---|
| 新增身份 ID（如 `solo`）而非复用 `renegade` | 需同步 4+ 处身份映射表与 AI 身份分支，且 `renegade` 的「无队友」语义本就吻合，收益为负 |
| 复用 `"renegade"` 作为获胜 ID | 会触发 `match_table.gd:5645` 的「本地身份 == 获胜 ID」判定，导致全员显示胜利（AC-2.4 的回归防线） |
| 改 `get_opening_max_hp_bonus` 增加座次参数 | 波及既有 3 参调用点与两个既有模式测试；且身份驱动与座次驱动语义不同，混在一处会让两条规则互相牵制 |
| 在 `IdentityRules` 内直接读 `GameSettings` 判断开关 | 破坏单向分层（规则层依赖设置层），且让"关闭即等于原值"无法纯函数单测 |
| 座次补偿持久化到 `PlayerState` 新字段 | `PlayerState` 无座次字段，座次在序列化时才派生（`game_state.gd:191`）；持久化会在 `state.players` 重建数组后失真 |
| 让房间开关写回 `GameSettings` | 既有两个房间开关都不写回；写回会让"房间设置"与"本地默认"两个语义层互相污染，且客户端会误改本地设置 |
| 为 AI 新增专属策略评估器 | 现有内奸分支在无阵营时会安全退化（D10），只需修正态度层；新增评估器会引入一整条不可复用分支 |

## 9. 风险登记

| 风险 | 触发条件 | 缓解 |
|---|---|---|
| 模式未注册就被引用 | 先改 UI / 先改 `match_options` | implement 顺序强制「`normalize_mode` 注册」为 T1 第一项 |
| `_evaluate_identity_winner` 立即判「反贼」 | `normalize_mode` 未加分支或 `evaluate_winner` 未加分支 | AC-1.5（开局后 `game_over == false`）+ AC-2.3 |
| 第 7 张模式卡打破既有硬断言 | 未同步 `tests/main_menu_test.gd` | implement 列出 6 处精确修改点 |
| 滚动到底部可见性断言指向旧最后一张卡 | 只加卡不改断言 | implement T7.4 明确改为断言新卡 |
| `host_lan` / `update_lan_lobby_settings` 位置参数漏改调用点 | 只改定义 | implement 要求先 grep 全部调用点与测试再改 |
| 协议版本未提升导致字段错位 | 只加快照字段 | AC-5.6 + 检查清单 |
| 中新卡标签未应用主题字体色 | 只复制节点结构 | AC-8.2（`font_color_audit_test` 会自动捕获） |
| 体力上限补偿在中局换将路径重复累加 | 未来把本模式接入换将/复活路径 | `implement.md` V6 逐点核对 4 个 `_refresh_pre_game_character_stats` 调用点 |

## 10. 受影响文件总览

**代码（15 个）**：`scripts/core/identity_rules.gd`、`scripts/autoload/game_settings.gd`、`scripts/network/network_gateway.gd`、`scripts/core/match_controller.gd`、`scripts/core/character_selection_service.gd`、`scripts/ai/identity_ai_model.gd`、`scripts/ui/main_menu.gd`、`scripts/ui/match_menu.gd`、`scripts/ui/match_table.gd`、`scripts/ui/online_lobby_panel.gd`、`scripts/ui/lan_lobby_panel.gd`、`scripts/ui/character_selection_panel.gd`、`scenes/main.tscn`、`scenes/components/lan_lobby_panel.tscn`、`scenes/components/online_lobby_panel.tscn`

**测试（4 个）**：`tests/winner_takes_all_mode_test.gd`（新）、同名 `.tscn`（新）、`tests/main_menu_test.gd`（改）、`tests/game_settings_persistence_test.gd`（改）

**文档（7 个）**：`docs/游戏机制与玩法内容.md`、`docs/架构说明.md`、`docs/界面与交互.md`、`docs/内容制作指南.md`、`docs/AI模块.md`、`docs/网络通信.md`、`README.md`

**交付附加（按 AGENTS.md）**：`临时反馈文档.md` 追加学习反馈摘要 + Git 提交描述（带 `YYYY-MM-DD HH:MM` 时间戳）
