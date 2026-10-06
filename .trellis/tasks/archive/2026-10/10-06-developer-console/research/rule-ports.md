# 调研：规则层公开端口（开发者菜单可用的既有 API）

> 来源：只读代码检索，未修改任何文件。所有签名逐字取自源码。
> 结论用途：确定 9 项数值效果 + 获得牌堆指定牌 + 更换武将各自应调用哪个既有端口，以及哪些能力确实缺失。

---

## 1. 逐项端口对照

| # | 需求项 | 状态 | 端口 |
|---|---|---|---|
| 1 | 摸 N 张牌 | **已存在** | `draw()` |
| 2 | 由玩家自选弃置 N 张 | **已存在（间接）** | `adjust_hand_size()` |
| 3 | 回复体力 | **已存在** | `recover()` |
| 4 | 失去体力 | **已存在** | `lose_hp()` |
| 5 | 无来源伤害 | **已存在** | `damage()` + `source_id = -1` |
| 6 | 增减体力上限 | **已存在** | `change_max_hp()` |
| 7 | 获得 / 失去护盾 | **已存在** | `shield()` / `change_hujia()` |
| 8 | 摸牌堆指定牌入手 | **已存在** | `gain_draw_pile_card_by_uid()` |
| 9 | 局中更换武将 | **已存在** | `replace_player_character_card()` |

**结论：9 项全部无需新增状态写入端口。**

### 1.1 摸牌

`scripts/core/match_controller.gd:4421`
```gdscript
func draw(player_id: int, count: int, announce: bool = true, allow_out_of_game: bool = false) -> void
```
- 公开包装；每次调用新建一个 `DrawResolutionService`，避免嵌套摸牌互相覆盖计数。
- 返回 **void**：只能通过执行前后对比 `state.get_player(pid).hand` 判断实际摸到几张。
- `state == null or state.game_over` 时无事发生；牌堆不足时自动重洗弃牌堆。
- `count` 在 `draw_resolution_service.gd:78` 内部被钳制为 `>= 0`。
- 委托对象 `draw_resolution_service.gd:15` `func draw(...) -> int` 是内部服务，**不要直接调用**。

### 1.2 弃牌（关键约束）

**首选端口**：`scripts/core/match_controller.gd:9323`
```gdscript
## 将角色普通手牌数调整至指定值；不足时摸牌，超出时由该角色选择并弃置差额。
func adjust_hand_size(player_id: int, target_count: int, completion_context: Dictionary = {}) -> bool
```
- 把普通手牌调整到 `target_count`：不足则**摸牌**，超出则建立真实 `request_card_choice` 窗口由**该玩家自选**弃哪些牌。
- 「弃 N 张」→ 传 `target_count = hand.size() - N`。
- 前置条件：`state` 有效、未终局、玩家 `alive` **且** `not out_of_game`。
- 候选由 `_build_player_zone_candidates(player_id, player_id, true, false, false)` 生成 → **只含手牌**，不含装备与判定区。
- `target_count` 内部 `maxi(target_count, 0)` 钳制；手牌不足 N 张时退化为「弃置全部手牌」，提示文案张数也随之变为实际可弃数。
- 返回 `true` 表示请求已建立（**可能仍在等待**），需随后检查 `has_pending_card_choice()`。

**为什么不能自己写 `request_card_choice`**：恢复分派器 `_continue_card_choice`（私有，`match_controller.gd:4135`）按 `context.kind` 分支，只认识
`dying_response` / `trick_negation` / `discard_phase` / `adjust_hand_size` / `extra_discard_phase` / `discard_target` / `steal_target`。
**新 kind 永远不会被恢复 → 请求永久挂起。**

**其它弃牌端口（不满足需求）**

| 端口 | 位置 | 局限 |
|---|---|---|
| `discard_selected_hand_cards(player_id, selected_uids) -> int` | `:8034` | 由调用方给定 UID，非玩家自选 |
| `discard_selected_player_cards(target_id, selected_uids, source_id = -1) -> int` | `:6748` | 手牌+装备+判定，但 UID 由调用方给定 |
| `discard_card_from_hand(player_id, card_uid) -> bool` | `:6922` | 单张、指定 |
| `discard_n_from_player(player_id, count) -> void` | `:7003` | **自动**按手牌→装备→判定顺序弃置；`内容制作指南.md:1240` 明文：*「不让玩家选择。需要自主选择时不要使用。」* |
| `discard_one_from_player(_source_id, target_id, parent_card_uid = -1) -> void` | `:6701` | 来源方从目标区域选**一张** |

**通用选择原语**（公开可复用）：`match_controller.gd:3039`
```gdscript
func request_card_choice(chooser_id: int, title: String, prompt: String, candidates: Array[Dictionary], min_select: int, max_select: int, allow_cancel: bool, context: Dictionary) -> Array[int]
```
需人类作答时返回 `[]` 并留下待办请求。**受上文 kind 白名单限制。**

### 1.3 回复体力

`scripts/core/match_controller.gd:4430`
```gdscript
func recover(source_id: int, target_id: int, amount: int, reason: String = "", allow_out_of_game: bool = false) -> void
```
- 返回 **void**，不返回实际回复量；`source_id = -1` 表示无来源。
- 委托 `recovery_resolution_service.gd:14`（内部）。
- **前置条件（重要）**：`recovery_resolution_service.gd:17` 在 `target == null or not target.alive or (out_of_game and not allow_out_of_game) or amount <= 0 or target.hp >= target.max_hp` 时直接返回。**满体力玩家静默回复 0** → 开发者菜单必须反馈「未生效」。
- 结算顺序：`recoverBefore → recoverBegin → 原子提交 → changeHp → recoverEnd → recoverAfter → recover_after`；等待期间换将/死亡会使请求因代次校验（`recovery_resolution_service.gd:35`）失效。

### 1.4 失去体力

`scripts/core/match_controller.gd:4994`
```gdscript
func lose_hp(source_id: int, target_id: int, amount: int, reason: String = "", allow_out_of_game: bool = false) -> int
```
- 返回**实际失去的体力值**。
- **绕过护盾、装备修正、伤害事件、伤害历史与属性连环——它不是伤害。**
- 前置条件：未终局、目标存在、`alive`、`not (out_of_game and not allow_out_of_game)`、`amount > 0`。
- 体力归零时触发 `_resolve_dying(target_id, -1)`；来源**永不**被记为击杀者。

### 1.5 无来源伤害

`scripts/core/match_controller.gd:5071`
```gdscript
func damage(source_id: int, target_id: int, amount: int, nature: String = "normal", card_id: String = "", chain_transfer: bool = false, ignore_armor: bool = false, source_context: Dictionary = {}) -> void
```
- **`source_id = -1` 即无来源**：`:5084` `var damage_source_player: PlayerState = state.get_player(source_id) if source_id >= 0 else null`，负 ID 被显式视为无来源，`source_character_generation` 记为 `-1`。
- 死亡来源会被自动降级为 `-1`（`:5088–5090`），因此结算中途死亡的角色不再获得击杀记功。
- `nature` ∈ `normal` / `fire` / `thunder`。
- 前置条件：未终局、目标 `alive`、`not out_of_game`、`amount > 0`（否则静默返回）。
- 完整 7 个修改窗口链；`source_context` 用于 `card_user_id` / 父牌 UID。
- 相关：`:5050` `func resolve_card_effect_source_id(actor_id: int) -> int` 在行动者已死亡时返回 `-1`，是「是否应为无来源」的规范助手。

### 1.6 体力上限

`scripts/core/match_controller.gd:4489`
```gdscript
func change_max_hp(target_id: int, delta: int, source_id: int = -1, reason: String = "", allow_out_of_game: bool = false, resolve_dying: bool = true) -> int
```
- `delta` 有符号；返回**实际变化的有符号值**。
- **注意 `target_id` 在第一位**（与 `recover` / `lose_hp` / `damage` 的 source-first 不同）。
- 前置条件：未终局、`delta != 0`、目标 `alive`、`not (out_of_game and not allow_out_of_game)`。
- 减少时钳制到**最小上限 1**，并把 `hp` 拉到新上限（发 `changeHp`），**可能触发濒死**。
- `resolve_dying = false` 文档说明**仅**供已在 `dyingBegin` 内部的调用者使用（避免递归濒死）。
- 发出 `gainMaxHpBefore/Begin/End/After` 或 `loseMaxHpBefore/Begin/End/After`。
- **不存在** `set_hp` / `set_max_hp` 绝对赋值端口。要强制设定体力必须组合 `change_max_hp` + `recover` / `lose_hp`。

### 1.7 护盾

获得：`scripts/core/match_controller.gd:4439`
```gdscript
func shield(target_id: int, amount: int, source_id: int = -1, reason: String = "") -> int
```
- 返回实际获得量。前置条件：未终局、目标 `alive`、**`not out_of_game`**、`amount > 0`。护盾无上限。
- 发出 `changeHujiaBefore` / `shield_after` / `changeHujiaAfter`；触发可在 before 时机取消或削减。

失去与统一变更：`scripts/core/match_controller.gd:4466`
```gdscript
func change_hujia(target_id: int, delta: int, source_id: int = -1, reason: String = "") -> int
```
- 正 `delta` 委托 `shield()`；负 `delta` 递减并钳制到 0，返回**负的应用值**。
- 失去分支前置条件：目标 `alive`、`not out_of_game`、`target.shield > 0`。
- 失去护盾**明确不是体力损失、不是伤害**（无伤害历史 / 无濒死 / 无连环）。`内容制作指南.md:1070`。

### 1.8 摸牌堆指定牌入手

**牌堆专用（本需求首选）**：`scripts/core/match_controller.gd:9051`
```gdscript
func gain_draw_pile_card_by_uid(player_id: int, card_uid: int, reason: String = "gain_viewed_draw_card") -> CardInstance
```
- 把**指定 `CardInstance`**（不必在顶部）从 `state.draw_pile` 移入该玩家手牌，返回该牌或 `null`。
- 前置条件：玩家存在、`alive`、**`not out_of_game`**（更严格，**无**覆盖参数）、牌仍在 `draw_pile`（不重洗、无回退）。
- 经 `_prepare_hidden_pile_gain` + `_move_card_with_timings(..., reset_hand_knowledge = true)` → 这是**获得**而非**摸牌**：不跑 `draw` 批次、不增加 `total_cards_drawn`。

**任意区域通用**：`match_controller.gd:7046`
```gdscript
func gain_card_to_hand_by_uid(receiver_id: int, card_uid: int, reason: String = "gain_card", allow_out_of_game: bool = false) -> bool
```
覆盖摸牌堆 / 弃牌堆 / 手牌 / 装备 / 判定；拒绝 `processing` 区域与同主手牌；处理装备离场效果。

**枚举助手**：`match_controller.gd:9034`
```gdscript
func get_top_draw_card_candidates(viewer_id: int, count: int) -> Array[Dictionary]
```
- 按「数组末尾为牌堆顶」顺序返回 `count` 张私有候选，**牌仍留在牌堆**，不移动、不改变顺序。
- 内部 `mini(count, state.draw_pile.size())` 钳制；重洗条件是 `state.draw_pile.size() < count`，因此 **`count == draw_pile.size()` 时不会重洗**。
- 每项形如 `{"uid", "owner_id", "zone", "slot", "visible", "card_data"}`（`_serialize_choice_candidate`，`:6810`），`card_data` 在 `visible = true` 时含完整牌面（`definition_id` / `suit` / `rank`）。
- **因此「列出摸牌堆全部牌」可直接复用本端口，无需新增查询端口。**

**造牌插入**：`match_controller.gd:9126` `func create_and_insert_card_into_draw_pile(definition_id: String, suit: String = "", rank: int = 0, position: int = DRAW_PILE_POSITION_TOP) -> int`

### 1.9 更换武将

**局中真正换将（本需求最佳匹配）**：`scripts/core/match_controller.gd:4634`
```gdscript
func replace_player_character_card(player_id: int, new_character_id: String, reason: String = "", preserve_runtime_max_hp_delta: bool = true) -> bool
```
- 用任意 `GameDatabase` 武将替换武将牌——**含 `special = true`**，因为它查完整数据库而非 `get_selectable_character_ids()`。
- **无阶段门控**：只要求 `state` 有效、未终局、`new_character_id` 非空、玩家存在、`alive`、**`not out_of_game`**、已有武将、新旧不同。
- 保留身份 / 座次 / 标记 / 局内获得的技能；重算 `max_hp = 新基础值 + 保留的运行时增量`，钳制 `hp`；替换原生技能；递增 `character_generation`；发 `changeSkillsAfter` + （钳制时）`changeHp`。
- 现网调用者：`game_data/skills/lunhui.gd:54`、`game_data/skills/yongjie.gd:265`，以及测试。

**互换两名角色的武将牌**：`match_controller.gd:4584`
```gdscript
func swap_player_character_cards(first_player_id: int, second_player_id: int, reason: String = "") -> bool
```
两者都必须 `alive`、在场、武将已明置。只交换武将 ID + 基础体力上限 + 原生技能（**不交换**体力、身份、座次、手牌、装备、护盾、已获得/临时技能）。唯一现网调用者：`scripts/opportunity/opportunity_effect_resolver.gd:355`。

**赛前专用（有门控，不可用）**
| 端口 | 位置 | 门控 |
|---|---|---|
| `select_character(player_id, character_id, seat_number = -1, identity = "") -> bool` | `:1892` | 硬门控 `state.current_phase == "character_selection"` |
| `replace_character_candidate(player_id, character_id) -> bool` | `:2043` | 门控 `current_phase == "character_selection"`；消耗 1 张换将卡（`character_selection_service.gd:591`） |
| `ai_character_adjustment_service.gd:61` `select_character(actor_id, target_player_id, character_id) -> String` | — | 仅 `ai_character_adjustment` 阶段（门控在 `match_controller.gd:11612`） |

**技能重装助手**：`match_controller.gd:4779` `func restore_character_card_skills(player_id: int, reason: String = "") -> bool`

**`character_form_state` 不是换将端口**：`scripts/data/player_state.gd:25` `var character_form_state: Dictionary = {}` 是供技能使用的**每武将草稿字典**（如 `xiongxing_damage_stacks`），跨存档保留。
`character_generation`（`player_state.gd:19`）是代次计数器，换将会作废该玩家所有待办选择 / 事件——**开发者菜单必须预期自己刚发出的效果在换将后失效**。

---

## 2. 既有调试 / 作弊端口：**无**

对 `scripts/` 全量检索 `debug_console` / `dev_console` / `cheat_` / `developer_mode` / `dev_mode` / `god_mode` / `_test_only` / `debug_port` / `控制台` / `console` → **零命中**。
控制器上唯一的 `force_*` 是 `opportunity_system.force_trigger_*`（`:11583`、`:11585`）与 `enforce_face_down_lock`（`:10075`），都不是作弊端口。
唯一的 `*test*` 命中都在 `tests/` 内。

**结论：开发者菜单必须从零构建。**

---

## 3. 离线 / 局域网判定与玩家枚举

**`MatchController` 没有 `is_lan` / `is_offline` / `network_mode` 访问器。** 判定经公开字段：

- `match_controller.gd:390` `var network_gateway: NetworkGateway`（公开），枚举 `NetworkGateway.Mode { OFFLINE, LAN, REMOTE }`（`scripts/network/network_gateway.gd:43–47`），`var mode: Mode = Mode.OFFLINE`（`:127`）。
- `network_gateway.gd:357` `func is_lan_host() -> bool`、`:362 func is_lan_client() -> bool`、`:367 func is_lan_match_active() -> bool`、`:775 func get_local_lan_player_id() -> int`、`:782 func get_lan_human_player_ids() -> Array[int]`、`:797 func get_peer_id_for_player(player_id: int) -> int`、`:802 func get_remote_player_assignments() -> Dictionary`。
- 全项目惯用法：`network_gateway != null and network_gateway.mode == NetworkGateway.Mode.OFFLINE`（如 `match_controller.gd:15590`）。
- `match_controller.gd:278` `@export_range(-1, 9, 1) var local_human_player_id: int = 0`（公开）。
- 私有权威助手（不可用）：`match_controller.gd:17538 _is_lan_authority_session()`。

**玩家列表**
- `scripts/data/game_state.gd:31` `var players: Array[PlayerState] = []`（经公开的 `match_controller.state`，`:369`）。
- `game_state.gd:102` `func get_player(player_id: int) -> PlayerState`
- `game_state.gd:110` `func get_alive_players() -> Array[PlayerState]` —— `alive` **且** `not out_of_game`，按座次。
- `match_controller.gd:8100` `func get_other_alive_player_ids(excluded_player_id: int) -> Array[int]` —— 存活且在场、排除一人。
- `match_controller.gd:7835` `func get_alive_players_in_action_order(start_player_id: int) -> Array[PlayerState]`
- `match_controller.gd:8112` `func get_players_in_attack_range(source_id: int, excluded_player_ids: Array[int] = []) -> Array[int]`

**UI 面向的快照**
- `match_controller.gd:9` `signal state_changed(snapshot: Dictionary)`；快照 `players` 是**字典数组**（见 `ui/match_table.gd:1732`、`:1913`）。
- 强制重新广播：`match_controller.gd:17926` `func refresh_state_snapshot() -> void`（公开包装，内部 `_emit_state()`）。

---

## 4. 「控制器是否空闲」——无单一标志，需组合

**不存在** `is_busy` / `is_idle`。公开谓词：

| 谓词 | 位置 | 语义 |
|---|---|---|
| `has_pending_card_choice() -> bool` | `:2678` | 有任何选牌 / 无懈窗口（LAN 客户端感知） |
| `has_pending_play_interaction() -> bool` | `:2687` | 待办选择、阻塞中的延后技能结算，或 `game_flow_pacer` 技能间隔 |
| `has_pending_judgment_request() -> bool` | `:6507` | 待办判定请求 |
| `has_nested_settlement_barrier() -> bool` | `:12935` | `has_pending_card_choice() or not _queued_equipment_triggers.is_empty()`；**内容代码在改状态前的门控**（`游戏机制与玩法内容.md:1492`） |
| `is_gameplay_paused() -> bool` | `:976` | UI/日志/详情暂停，非规则推进 |
| `is_waiting_for_human_input() -> bool` | `:1064` | 有真人欠答复 |
| `get_stall_diagnostics() -> Dictionary` | `:1027` | 看门狗唯一输入 |

事件运行时（`event_scheduler` 公开，`match_controller.gd:503`）：`event_scheduler.gd:749 get_live_event_count()`、`:754 has_pending_drain_continuation()`、`:806 get_pending_choice_requests()`、`:710 get_current_event_id()`。

实用「可安全施加效果」判据：
```gdscript
not state.game_over and not has_nested_settlement_barrier() and not has_pending_judgment_request() and event_scheduler.get_live_event_count() == 0
```

---

## 5. 命名与返回值约定

- **无前缀**：都是普通规则动词（`draw` / `recover` / `shield` / `change_hujia` / `change_max_hp` / `lose_hp` / `damage` / `adjust_hand_size` / `gain_*`）。没有 `debug_` / `dev_` / `cheat_` 命名空间，**新端口必须自取命名且不得占用规则动词**。
- **`player_id` 不统一在首位**，两个族：
  - *目标优先*：`shield(target_id, amount, source_id = -1, ...)`、`change_hujia(target_id, delta, ...)`、`change_max_hp(target_id, delta, ...)`、`draw(player_id, count, ...)`、`adjust_hand_size(player_id, target_count, ...)`、`discard_n_from_player(player_id, count)`、`discard_selected_hand_cards(player_id, selected_uids)`、`gain_card_to_hand_by_uid(receiver_id, card_uid, ...)`、`gain_draw_pile_card_by_uid(player_id, card_uid, ...)`
  - *来源优先*（`-1` 表示无来源）：`recover(source_id, target_id, amount, ...)`、`lose_hp(source_id, target_id, amount, ...)`、`damage(source_id, target_id, amount, ...)`
- **返回值**：金额变更类返回**实际应用的有符号 `int`**（`shield` / `change_hujia` / `change_max_hp` / `lose_hp`）；`draw` 与 `recover` 返回 **`void`**；布尔端口返回成功；`gain_draw_pile_card_by_uid` 返回 `CardInstance`。`reason` 一律是末尾 `String = ""`，用于日志与事件。
- **前置条件通过静默早退实现，不报错**——调用方必须校验返回值或重读状态，不能假定成功。

---

## 6. UI 应直接调用这些端口，还是走 `PlayerAction`？

**凡是玩家决策，一律走 `PlayerAction` → `submit_action()`。** 已验证：`scripts/ui/match_table.gd` **只**调用 `submit_action(...)`（30+ 处）与 `start_match(...)`，**从不**调用规则变更端口。

可引用的规范原文：
- `docs/架构说明.md:142` —— *「`MatchController.get_card_use_preview()` 是 UI 使用的只读查询边界。… 只有点击选牌与点击目标才构造 `PlayerAction` 并进入 `submit_action()`；拖拽只处理本地手牌排序。」*
- `docs/界面与交互.md:334` —— *「规则核心仍会在 `submit_action()` 中执行最终校验。UI 预览仅用于引导，不能替代权威规则判断。」*
- `docs/内容制作指南.md:1232` —— *「`submit_action(action)` | `bool` | 权威动作总入口…内容效果不得在结算中递归提交动作。」*
- `docs/内容制作指南.md:12` —— *「…不得把其他角色手牌合并到同一快照，也不得绕过 `PlayerAction.actor_id` 权威校验。该能力必须限制在 `NetworkGateway.Mode.OFFLINE`；联机房主也不能借此提交其他真人角色动作。」*
- `docs/AI模块.md:330` —— *「…但不能直接调用伤害、摸牌、移动牌或阶段推进函数。」*
- `docs/界面与交互.md:193` —— *「…点击确认后仍只提交 `PlayerAction`，不能在客户端直接改写规则状态。」*

**对开发者菜单的含义**：第 1 节的端口是**内容层**端口（`内容制作指南.md:1057–1084` 为 `resolver.host.*` 记录），不是 UI 端口。开发者菜单直接调用它们属于**新的特权表面**，破坏了「UI 只走 PlayerAction」的规则，因此需要：
(a) 显式的离线 / 权威门控（`NetworkGateway.Mode.OFFLINE` 或 `is_lan_host()`）；
(b) 每次变更后调用 `refresh_state_snapshot()`。
合法直接调用的先例已存在：`start_match()` 文档规定为场景入口专用，而 `match_table.gd:3746`、`:3752` 确实调用了它。

---

## 7. 哪些项没有既有端口（需新增）

| # | 项 | 结论 |
|---|---|---|
| 1 | 摸 N | 已有 `draw()` |
| 2 | 自选弃 N | 已有 `adjust_hand_size()`（**无**字面意义的 `discard_n_choice(player_id, count)`） |
| 3 | 回复体力 | 已有 `recover()`（满体力无效） |
| 4 | 失去体力 | 已有 `lose_hp()` |
| 5 | 无来源伤害 | 已有 `damage(-1, ...)` |
| 6 | 增减体力上限 | 已有 `change_max_hp()`。**缺**绝对 `set_hp` / `set_max_hp` |
| 7 | 获得/失去护盾 | 已有 `shield()` / `change_hujia()` |
| 8 | 摸牌堆指定牌入手 | 已有 `gain_draw_pile_card_by_uid()`（+ `gain_card_to_hand_by_uid()`） |
| 9 | 局中换将 | 已有 `replace_player_character_card()` / `swap_player_character_cards()`，均无阶段门控 |

**1–9 均无需新增状态变更端口。** 真正缺的是：
(a) 控制台表面本身（目标列表 UI、离线门控、每次效果后 `refresh_state_snapshot()`）；
(b) 若要「把体力设为 X」而非增量，需要绝对赋值端口；
(c) 字面意义的 `discard N by choice` 便利包装（`adjust_hand_size` 语义是「手牌**数量**」，且低于目标时会**摸牌**，所以纯弃牌要算 `hand.size() - N` 并意识到摸牌分支的存在）。

---

## 8. 两个横切陷阱

1. **代次失效**：任何待办 `request_card_choice` / `request_judgment` / 延后技能结算都以 `PlayerState.character_generation`（`player_state.gd:19`）为键。`replace_player_character_card` 会递增它，因此该玩家的在途选择会被安全丢弃——但开发者菜单**不能假定自己刚发出的效果在换将后仍存活**。
2. **所有变更端口静默早退**：死亡 / 离场 / 错误阶段 / 非正数 / 满体力都不产生错误与日志。开发者菜单必须读取返回值（实际应用的 `int`、`bool`、或 `null` 的 `CardInstance`）并显式呈现「未生效」，否则会出现「看起来坏了，其实什么都没做」。
