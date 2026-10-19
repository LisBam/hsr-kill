# 调研 05 · 组合技能效果池 → 端口映射

调研范围：把「进程」24 项与「缺陷」18 项效果逐条映射到项目里**真实存在**的端口/机制，并列出必须新建的端口。
只读调研，全部带文件与行号。

---

## 0. 端口机制前提

- `host.call("<name>", args...)` 就是 GDScript 的 `Object.call` —— **按方法名调用 `MatchController` 的公开 `func`**。项目里**没有**端口注册表、没有 `call()` 重写、没有端口清单常量。
- 因此「端口」== `scripts/core/match_controller.gd` 的公开 `func`。**私有 `_` 前缀函数技能不可调用**（这一条直接决定 A8 的结论）。
- `SkillDefinition`（`game_data/skill_definition.gd`）经 `bind(match_host, player_id)`（`:157`）拿到 `host`。
- `SkillPlayer`（`game_data/skill_player.gd`，77 行）只有七个方法：`get_state / shield / loseShield / loseHp / damage / addPhase / addPlayPhase`。
- **纯查询钩子 ≠ 端口**：`modify_distance_to_target`、`get_play_count_limit_bonus`、`ignores_card_distance_limit(_to_target)`、`does_not_count_toward_hand_limit`、`validate_card_action_permission` 等是 **`SkillDefinition` 的虚函数覆写点**，由控制器聚合器反向调用。
- 订阅守卫：`skill_definition.gd:623` 有 `RuleTimingCatalog.has_timing(event_name)` 检查，**只有登记过的事件名可订阅**。
- 持久效果载体：`PlayerEffect`（`game_data/player_effect.gd`）+ `PlayerEffectService`（`scripts/core/player_effect_service.gd`），状态写在**承载角色**的 `PlayerState.character_form_state`（不进公开快照）。`game_data/effects/` 目前只有两个：`xiongxingshanghai.gd`、`yousi_pressure.gd`。

---

## 1. 「进程」24 项

| id | 原文 | 状态 | 端口 / 机制 | 证据 |
|---|---|---|---|---|
| A1 | 你摸一张牌 | EXISTS | `draw(player_id, count, announce=true, allow_out_of_game=false)` | `match_controller.gd:4477`；用例 `bahu.gd:26` |
| A2 | 从牌堆中获得一张锦囊牌 | EXISTS | `gain_top_draw_card_matching(player_id, {"type":"trick"}, reason) -> CardInstance`；或 `gain_group_cards_from_draw_or_discard(player_id, "type", ["trick"], 1, reason)` | `:7713`、`:7583`；过滤器 `_does_draw_card_match_filter` `:7737` |
| A3 | …基本牌 | EXISTS | 同上，`{"type":"basic"}` | `:7713`；技能侧同类 `haoxi.gd:120-142` |
| A4 | …装备牌 | EXISTS | 同上，`{"type":"equipment"}` | `:7713`；`docs/内容制作指南.md:4041` |
| A5 | …“以太”牌 | EXISTS（需按实例牌名检索） | 按牌名/实例牌名从牌堆取得；`gain_top_named_card_from_draw_or_discard(player_id, definition_id, reason) -> CardInstance` 只按定义 ID。**项目内不存在「以太」内容**（全文搜索 0 命中） | `:7552`；`docs/` 无「以太」 |
| A6 | …【闪】 | EXISTS | `gain_top_draw_card_matching(player_id, {"effect_id":"dodge"}, reason)` | `:7713`；`cards/shan.gd:14` |
| A7 | …【杀】 | EXISTS | `gain_top_draw_card_matching(player_id, {"effect_id":"slash"}, reason)` | `:7713`；**真实用例** `mingxian.gd:103` |
| A8 | 你随机使用牌堆中的一张装备牌 | **MISSING** | 无「使用牌堆里的实体牌」公开端口。最近的 `_equip_conquest_enemy_from_piles`（`:15631`）是**私有**且经 `equip_from_processing`（`:6728`）**绕过 useCard 时机/次数/距离校验**；两个虚拟牌入口只吃「虚拟牌定义」 | `:15631`、`:6728`；参考 `opportunity_effect_resolver.gd:439-463` |
| A9 | 你将武将牌重置 | EXISTS | `set_player_linked(target_id, linked=false, source_id=-1, reason="") -> bool` | `:4990`；用例 `bingfeng.gd:95`、`tianzhui.gd:92` |
| A10 | 你弃置一名角色区域内的一张牌 | EXISTS | `get_player_zone_candidates(viewer_id, target_id)` + `discard_selected_player_card(source_id, target_id, card_uid) -> bool` | `:7949`、`:8062`；用例 `tongpao.gd:261`/`:205` |
| A11 | 你获得一名角色装备区内的一张牌 | EXISTS | `get_equipment_candidates(viewer_id, target_id, slots)` + `take_selected_player_card(source_id, target_id, card_uid) -> bool` | `:8778`、`:6830`（实现 `:6924-6953`，装备分支 `:6934-6940`） |
| A12 | 你获得不为你的当前回合角色的一张手牌 | EXISTS | `get_hand_candidates(viewer_id, target_id)` + `take_selected_player_card(...)` | `:8067`、`:6830`；用例 `fengkou.gd:303`、`yousi.gd:205` |
| A13 | 手牌上限+2直到回合结束 | **PARTIAL** | `add_hand_limit_bonus(player_id, amount, reason, allow_out_of_game) -> int` 是**永久**累加，控制器**不在回合末清零**；技能须自己在 `phaseAfter` 反向调用 `change_hand_limit_bonus` | `:4581`、`:4593`；`player_state.gd:413`；**无回合末重置**（仅 `:15487` 阵亡清零）；用例 `jvkou.gd:75`、`chouma.gd:59`、`huanri.gd:72` |
| A14 | 出牌阶段使用【杀】的次数上限+1直到回合结束 | **PARTIAL（实时查询，核心零改动）** | 覆写 `get_play_count_limit_bonus(card_definition) -> int` + 自管 turn flag | 钩子 `skill_definition.gd:900`；聚合器 `match_controller.gd:9997`；判定点 `card_rule_service.gd:122`；用例 `bahu.gd:30`（永久版）；flag 范式 `mingchen.gd:21/58-59` |
| A15 | 你使用攻击范围+2直到回合结束 | **MISSING** | `get_attack_range()` **只读武器卡静态 `attack_range`**，无加成钩子、无聚合器 | `card_rule_service.gd:60-71`（`:71`）；`get_players_in_attack_range` `match_controller.gd:8181` 同源 |
| A16 | 你计算与其他角色距离-1直到回合结束 | **PARTIAL（实时查询）** | 覆写 `modify_distance_to_target(target_id, current) -> int` 返回 `current-1` + 自管 turn flag | 钩子 `skill_definition.gd:918`；聚合器 `match_controller.gd:10103-10113`；调用点 `card_rule_service.gd:54-55`；用例 `lvexi.gd:39`、`zhufeng.gd:58` |
| A17 | 防止你受到伤害直到回合结束 | EXISTS | 订阅 `damageBegin4`（role `target`）+ `event.cancel(reason)` | 模板 `yuezhi.gd:72`（订阅）、`:150`/`:162`（cancel）、常量 `:13` |
| A18 | 你视为使用一张【杀】 | EXISTS | `execute_cardless_virtual_card_use(actor_id, definition_id, target_ids, log_message, rule_overrides, virtual_storage) -> bool` | `:13804`；用例 `zimo.gd:385`、`qingli.gd:84`、`zhidong.gd:129` |
| A19 | 你视为使用一张【决斗】 | EXISTS | 同上，`definition_id="juedou"` | `:13804`；用例 `baizhe.gd:118` |
| A20 | 你视为使用一张【顺手牵羊】 | EXISTS | 同上，`definition_id="shunshou"` | `:13804`；有材料版 `chuanchong.gd:91` |
| A21 | 你摸两张牌并失去本技能 | EXISTS | `draw(pid, 2)` + `remove_skill(player_id, skill_id, reason) -> bool` | `:4477`、`:11041`；用例 `fengkou.gd:311` |
| A22 | 你回复1点体力并失去本技能 | EXISTS | `recover(source_id, target_id, amount, reason, allow_out_of_game)` + `remove_skill` | `:4486`、`:11041`；用例 `lingfu.gd:242-243` |
| A23 | 你增加1点体力上限并失去本技能 | EXISTS | `change_max_hp(target_id, delta, source_id, reason, allow_out_of_game, resolve_dying)` + `remove_skill` | `:4545`、`:11041`；用例 `lingfu.gd:241` |
| A24 | 你获得1点护盾并失去本技能 | EXISTS | `shield(target_id, amount, source_id, reason) -> int` + `remove_skill` | `:4495`、`:11041`；用例 `tongpao.gd:181` |

## 2. 「缺陷」18 项

| id | 原文 | 状态 | 端口 / 机制 | 证据 |
|---|---|---|---|---|
| B1 | 你弃置一张手牌 | EXISTS | `get_hand_candidates` + `discard_selected_hand_cards(player_id, selected_uids) -> int` | `:8067`、`:8103`；用例 `duyi.gd:76` |
| B2 | 你随机弃置一张牌 | EXISTS | `pick_random_candidate_index(candidate_count, history_kind, history_data)` + `get_player_zone_candidates` + `discard_selected_player_cards(target_id, uids, source_id)` | `:7301`、`:7949`、`:6817`；用例 `haoxi.gd:98-106` |
| B3 | 你随机弃置一张装备牌 | EXISTS | `get_equipment_candidates(viewer, target, slots)` + `pick_random_candidate_index` + `discard_selected_player_cards` | `:8778`、`:7301`、`:6817`；`docs/内容制作指南.md:1096` |
| B4 | 你随机弃置一张基本牌 | EXISTS | `get_hand_equipment_candidates` + 筛 `type=="basic"` + `pick_random_candidate_index` + `discard_selected_hand_equipment` | `:7944`、`:9063`、`:7301`；类型判据 `haoxi.gd:141-142` |
| B5 | 你随机弃置一张锦囊牌 | EXISTS | 同 B4，筛 `type=="trick"` | 同上 |
| B6 | 手牌上限-1直到回合结束 | **PARTIAL** | `change_hand_limit_bonus(player_id, -1, reason)`（**永久**），须在 `phaseAfter` 反向加回 | `:4593`；`player_state.gd:413`；用例 `huanri.gd:72`；回滚范式 `mingchen.gd:39/58-59` |
| B7 | 你将武将牌调整至横置 | EXISTS | `set_player_linked(target_id, linked=true, source_id, reason) -> bool` | `:4990`；用例 `jiahu.gd:68`、`jiyu.gd:78`、`xinghuo.gd:39` |
| B8 | 你交给不为你的当前回合角色一张牌 | EXISTS | `get_hand_equipment_candidates` + `gain_card_to_hand_by_uid(receiver_id, card_uid, reason) -> bool`（`:7126` 明确拒绝 `hand→同一人`，天然满足「不为你的角色」） | `:7944`、`:7115`；用例 `fuchen.gd:63` |
| B9 | 你不可响应其他角色使用的牌直到回合结束 | **MISSING（持续性）** | 现有机制是**逐牌、仅当前结算内有效**：`add_card_direct_hit_target(card_uid, target_id, reason)`，被 `is_response_blocked_by_direct_hit` 读取。**无持续到回合结束的状态**。替代钩子 `validate_card_action_permission` 只过滤**手牌响应候选**，**装备响应入口 `_get_immediate_equipment_response_candidate`（`:5364-5385`）与响应转化技能不过该钩子** | 写入 `:8865`；读取 `:14569`（唯一调用点 `:5281`）；用例 `lvexi.gd:51`；装备旁路 `:5364-5385`；文档 `docs/内容制作指南.md:1151`、`:1154` |
| B10 | 你计算与其他角色的距离+1直到回合结束 | **PARTIAL（实时查询）** | 覆写 `modify_distance_to_target` 返回 `current+1` + 自管 turn flag | 同 A16 |
| B11 | 本回合内你下次受到的伤害+1 | EXISTS | `damageBegin3`（role `target`）里 `event.data["amount"] += N`；`damage` 消费、`damageCancelled`/`damageZero` 释放；防重复用预留事件 ID | 模板 `zhuijian.gd:39`（订阅）、`:82`（加值）、`:40-42`（消费/释放）；持久版 `game_data/effects/xiongxingshanghai.gd:52`、`:120` |
| B12 | 本回合内你下次受到的属性伤害+1 | EXISTS | 同 B11，加 `nature ∈ {fire, thunder}` 过滤 | 同上；窗口位于 `_modify_armor` 之前 |
| B13 | 你下次回复的体力-1直到回合结束 | **PARTIAL（机制在，无内容先例）** | 订阅 `recoverBegin`（role `target`）后改 `event.data["amount"] -= 1`；恢复服务 `_commit` 读最终值。现有唯一 `recoverBegin` 订阅者只 `cancel()`，**从未有内容改小恢复量** | 时机 `rule_timing_catalog.gd:42`；唯一订阅者 `yuezhi.gd:73`（只 cancel `:162`）；管线 `scripts/core/recovery_resolution_service.gd` |
| B14 | 你失去1点体力并失去本技能 | EXISTS | `lose_hp(source_id, target_id, amount, reason, allow_out_of_game) -> int` + `remove_skill` | `:5050`、`:11041` |
| B15 | 你受到1点伤害并失去本技能 | EXISTS | `damage(source_id, target_id, amount, nature="normal", card_id, chain_transfer, ignore_armor, source_context)` + `remove_skill` | `:5127`、`:11041` |
| B16 | 你受到1点雷电伤害并失去本技能 | EXISTS | 同上，`nature="thunder"` | `:5127`；用例 `mingchen.gd:78` |
| B17 | 你受到1点火焰伤害并失去本技能 | EXISTS | 同上，`nature="fire"` | `:5127` |
| B18 | 你减少1点体力上限并失去本技能 | EXISTS | `change_max_hp(target_id, -1, ...)`（内部夹到 `max_hp ≥ 1`，可能压低当前体力触发 `changeHp`）+ `remove_skill` | `:4545`（夹取 `:4565`、`changeHp` 派发 `:4573-4574`）、`:11041`；用例 `hongyun.gd:138`、`xvechou.gd:51` |

**统计**：EXISTS 30 / PARTIAL 7 / MISSING 3（A8、A15、B9）。

---

## 3. 关键语义陷阱

| 陷阱 | 事实 | 证据 |
|---|---|---|
| 横置 ≠ 翻面 | `set_player_linked`（`:4990`）改 `PlayerState.chained`（`player_state.gd:58`）；`turn_over_player`（`:5021`）改 `face_down`（`:61`） | `:4990`、`:5021` |
| `hand_limit_bonus` 是永久的 | 控制器**不在回合末清零**；技能被 `remove_skill`/换将/非锁定技失效压制后会留下**永久残留** | `player_state.gd:413`；`match_controller.gd:4581/4593`；仅 `:15487` 阵亡清零 |
| `shield_after` 不可订阅 | 它经 `_dispatch_rule_event` 派发到 `event_bus`，但**未登记进 `RuleTimingCatalog`** → `subscribe_timing("shield_after", …)` 静默返回 `-1`；只能用 `host.event_bus.subscribe(...)` | `match_controller.gd:4515`；`skill_definition.gd:623`；测试 `tests/health_mechanics_test.gd:74` |
| 次数/距离是**实时纯查询** | 不是累加状态 →「直到回合结束」只需技能自管 flag 在 `phaseAfter` 复位，核心层零改动 | `:9997`、`:10103` |
| 不存在通用伤害修正注册表 | 只有两种形态：①技能实例内一次性修正器（`zhuijian.gd:39/82`）②`PlayerEffect` 持久叠加（`xiongxingshanghai.gd:52/120`）。选择依据 = **受益者是否等于施放者** | 同上 |
| `add_card_target_damage_bonus` 不是「下次受伤」 | 它是**逐目标牌内增伤**（`:8882`）；技能不得自行改写同一字段否则重复累加 | `docs/内容制作指南.md:4181`、`docs/卡牌系统.md:298` |
| 随机必须走端口 | `pick_random_candidate_index(candidate_count, history_kind, history_data)`（`:7301`）保证回放/联机可复现；不得直接用 `randi()` | `:7301`；用例 `haoxi.gd:98-106` |

---

## 4. 需要新建的端口

### N1 · 攻击范围修正（补 A15）

`CardRuleService.get_attack_range()`（`card_rule_service.gd:60-71`）只读武器卡静态 `attack_range`，既无状态字段也无钩子。照抄距离机制（三处改动，**无新增状态字段**）：

```gdscript
# ① game_data/skill_definition.gd —— 纯查询钩子，与 modify_distance_to_target 并列
func modify_attack_range(current_range: int) -> int:
	return current_range

# ② scripts/core/match_controller.gd —— 聚合器，与 modify_skill_distance_to_target 同构
func modify_skill_attack_range(player_id: int, current_range: int) -> int

# ③ scripts/core/card_rule_service.gd:71 之后接上 provider
	return maxi(int(skill_rule_provider.call("modify_skill_attack_range", player_id, final_range)), 1)
```

「直到回合结束」由技能自管 flag 在 `phaseAfter` 复位（范式 `mingchen.gd:21/39/58-59`），核心层不引入 per-turn 状态。

### N2 · 从牌堆「使用」一张实体牌（补 A8）

现有两个入口都不合格：`_equip_conquest_enemy_from_piles` 是**私有**且绕过 `useCard*`；两个虚拟牌入口只吃「虚拟牌定义」。

```gdscript
# scripts/core/match_controller.gd
## 把位于摸牌堆/弃牌堆的实体牌作为一次真实用牌结算：经统一移动端口置入处理区，
## 再走完整 _execute_card_use 管线，因此 useCard* 时机、次数上限、距离与目标校验全部照常生效。
func execute_pile_card_use(actor_id: int, card_uid: int, target_ids: Array[int], rule_overrides: Dictionary = {}, virtual_storage: Dictionary = {}) -> bool

## 随机使用摸牌堆中的一张装备牌；随机下标经 pick_random_candidate_index 以保回放可复现。
func use_random_equipment_card_from_draw_pile(player_id: int, reason: String = "use_random_pile_equipment") -> bool
```

约束：① 牌必须经 `CardMovementService` / `_move_card_with_timings` 进入处理区；② 随机下标必须走 `pick_random_candidate_index`；③ 目标枚举必须走权威查询；④ 复用 `equip_from_processing` 只允许在走完用牌时机之后。

### N3 · 持续「不可响应」状态（补 B9）

`direct_hit_target_ids` 是单张牌结算内的共享上下文，牌一结算完就随 `_card_use_contexts.erase(card_uid)`（`:14557`）消失，**无法表达「直到回合结束」**。

```gdscript
# ① scripts/data/player_state.gd —— 回合域字段（进公开快照与存档）
var response_blocked_until_turn: Dictionary = {}

# ② scripts/core/match_controller.gd —— 端口
func set_response_blocked_until_turn_end(target_id: int, blocked: bool, source_id: int = -1, reason: String = "") -> bool
func is_response_blocked_until_turn_end(player_id: int) -> bool
```

**接入点必须同时改三处**（否则出现「界面没候选但规则仍放行」）：
1. `request_response_card_patterns` 的 `:5281` 旁（与 `is_response_blocked_by_direct_hit` 并列，早于候选构建）；
2. `_build_response_choice_candidates`（`:5389`）开头；
3. `_get_immediate_equipment_response_candidate`（`:5364`）开头（覆盖八卦阵等装备入口）。

**到期**：`_complete_finish_turn`（`:14867`）内、`phaseAfter` 之前清除，照抄 `turn_input_delegation` 的「回合角色 + 回合号」双重匹配（`docs/内容制作指南.md:4233`）。死亡/离场在 `death_resolution_service.gd` 清理。AI 必须读同一端口。

### N4 · 回合域手牌上限加成（补 A13 / B6，推荐）

现状的永久累加在技能被压制/换将时会留下**永久残留**（真实规则漏洞）。照抄 `mode_hand_limit_bonus` 的分层：

```gdscript
# scripts/data/player_state.gd
var turn_hand_limit_bonus: int = 0
# :413 改为 maxi(hp + hand_limit_bonus + mode_hand_limit_bonus + turn_hand_limit_bonus, 0)

# scripts/core/match_controller.gd
func add_turn_hand_limit_bonus(target_id: int, amount: int, source_id: int = -1, reason: String = "") -> int
```

**到期**：`_complete_finish_turn`（`:14867`）内清零；死亡/离场按 `:15487` 同位一并清零。

### 不需要新端口

- **A14 / A16 / B10**：`get_play_count_limit_bonus` / `modify_distance_to_target` 已是完整钩子 + 聚合器，技能自管 turn flag 即可。
- **B13**：`recoverBegin` + `event.data["amount"]` 机制齐备，只需写内容。
- **A21–A24 / B14–B18**：`draw`/`recover`/`change_max_hp`/`shield`/`lose_hp`/`damage` + `remove_skill` 全部齐备。
- **A2–A7、A10–A12、B1–B5、B8**：端口齐备，缺的只是内容用例。

---

## 5. 虚拟牌使用 API（A18–A20）

```gdscript
13736: func execute_virtual_card_use(actor_id, virtual_card_definition_id, material_card_uids, target_ids, log_message, rule_overrides = {}, virtual_storage = {}) -> bool
13804: func execute_cardless_virtual_card_use(actor_id, virtual_card_definition_id, target_ids, log_message = "", rule_overrides = {}, virtual_storage = {}) -> bool
```

- **有材料**版：材料进入处理区作为费用，代理牌继承材料花色/点数/颜色（`VirtualCardDescriptor.resolve_suit_aggregate`，`docs/内容制作指南.md:1218`）。用例 `anda.gd:108`、`gangfeng.gd:109`、`quanlei.gd:130`、`shanqing.gd:155`、`yongjie.gd:144`。
- **无材料**版：代理牌无花色无点数、只存在于本次处理区，**不进牌堆/弃牌堆**（`docs/内容制作指南.md:4191`）。用例 `baizhe.gd:118`、`qingli.gd:84`、`zhidong.gd:129`、`zimo.gd:385`、`lingyan.gd` 等。
- `rule_overrides` 只做按键合并的 `definition_patch`（`card_rule_service.gd:147-149`），**不放宽目标存活、离场、目标技能限制**。
- `virtual_storage` 只允许写可序列化的来源技能、顺序令牌、去重标记。
- 连续多张：继承 `SequentialVirtualSkillDefinition`，`start_cardless_virtual_card_sequence()` + `continue_settlement()` + `on_virtual_card_sequence_completed()`（`docs/内容制作指南.md:4193`）。
- 归属判定必须用稳定 `source_skill_id`，**不能只凭逻辑牌名**（`docs/内容制作指南.md:4180`）。

---

## 6. 跨角色给牌 / 获得牌（A10–A12、B8）

三条通道，语义不可互换：

1. **任意区域 → 获得者手牌**：`gain_card_to_hand_by_uid(receiver_id, card_uid, reason, allow_out_of_game) -> bool`（`:7115`）。位置由 `_find_card_location_by_uid` 权威重查（`:7121`）；`:7126` 拒绝 `processing` 与 `hand→同一人`；装备离区走 `_on_equipment_lost`（`:7133`）。**这是「交给某角色一张牌」的标准做法**（用例 `fuchen.gd:63`）。
2. **目标区域的一张牌 → 来源手牌**：`take_selected_player_card(source_id, target_id, card_uid) -> bool`（`:6830`，实现 `:6924`）。内部按 UID 依次搜 **手牌 → 装备（触发 `_on_equipment_lost`）→ 判定区**。
3. **带临时牌名的给牌**：`transfer_hand_card_as(from_id, to_id, card_uid, view_as_definition_id, source_skill_id) -> bool`（`:7440`）。

批量：`gain_all_hand_cards(receiver_id, target_id, reason)`（`:7030`）；装备槽级：`transfer_equipment(from_id, to_id, slot)`（`:7839`）。

---

## 7. 失去本技能（A21–A24、B14–B18）

- 唯一通用入口：**`remove_skill(player_id, skill_id, reason="") -> bool`**（`:11041`）。语义：卸载实例（释放订阅与纯查询修正器）→ 从实例表移除 → 清 `acquired_skills`/`temporary_skills` 记录 → `ReincarnationSkillService.clear_skill_state()` → 日志 → 广播。技能本不属于该角色时返回 `false` 且**无副作用**，调用方**不需要前置判空**。
- 批量：`remove_all_skills(player_id, reason)`（`:11078`）。
- 仅限局内获得技能：`remove_acquired_skill(player_id, skill_id)`。
- 权威拥有查询：`has_skill(player_id, skill_id)`（`:10582`）= 实例 ∪ `acquired_skills` ∪ `temporary_skills`，**不做存活过滤**。
- 真实自失用例：`fengkou.gd:311`、`lingfu.gd:243`。
- **若只想「失效直到回合结束」而非永久失去**，不要用 `remove_skill`，用实例 flag + `phaseAfter` 复位（`mingchen.gd:21/58-59`）。
- 界面无需额外处理：公开快照 `installed_skill_ids` 收缩后技能栏自动消失。

> **多实例注意**：`remove_skill(player_id, instance_key)` 只移除被寻址的实例（见 `10-19-skill-instance-multiplicity` 的 design D）。传技能 ID 则移除该技能的全部实例。

---

## 8. 选择请求与续接（需要选择的池内效果）

| 效果 | 需要的请求 | helper |
|---|---|---|
| A10 | ①选角色 ②选该角色区域的牌 | `request_target_selection`（`:1025`）/ `request_card_selection`；两步范式 `tongpao.gd:261` |
| A11 / A12 | 选牌（可能先选角色） | `request_card_selection`；给其他角色选时 `request_card_selection_for_player`（`:975`）；`yousi.gd:243` |
| A18–A20 | 选目标（可合并选牌+选目标） | `request_card_target_selection`（`:1034`）；虚拟手牌版 `request_virtual_hand_card_target_selection`（`:1066`） |
| B1 | 弃置手牌（明确选择） | `request_card_selection` + `discard_selected_hand_cards` |
| B2–B5 | **不需要请求**（随机） | `pick_random_candidate_index` |
| B8 | ①选自己的一张牌 ②（若允许）选交给谁 | `request_card_selection` / `request_card_target_selection` |
| A21–A23、B14–B18 | 不需要 | — |

续接契约（`SkillDefinition`）：

```gdscript
732: func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool
797: func defer_settlement(context: Dictionary) -> void
```

1. 请求与续接必须同属一个技能实例的稳定上下文；`context["kind"]` 作判别键，不匹配就 `return false` 让给别人（`mingchen.gd:63-64`、`jvkou.gd:58-60`）。
2. **同步返回 vs 异步等待**：`request_*` 在 AI 或规则同步完成时直接返回结果；等待人类提交时返回空集合并保留请求。用 `host.has_pending_card_choice()` 区分（`docs/内容制作指南.md:1082`）。
3. **恢复时必须重查权威状态**，逐个剔除已失效目标（死亡/离场/已离区），只有剩余为空才走空节推进（`docs/内容制作指南.md:4195`）。
4. **异步期间的区域移动**：若后续「然后」效果依赖区域移动时机结算完毕，用 `defer_settlement(context)` 挂到 `_rule_continuations`，统一管线先排空再回调 `continue_settlement()`（`docs/游戏机制与玩法内容.md:722`）。
5. AI 侧实现 `score_ai_choice(authoritative_snapshot, choice_request, action, evaluator) -> float`，按 `context.kind` 判别（`mingchen.gd:84-88`、`tongpao.gd:438-440`）。
