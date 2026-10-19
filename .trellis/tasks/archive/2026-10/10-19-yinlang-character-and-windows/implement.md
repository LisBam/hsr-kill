# 银狼武将、注入/以太技能与 yinlang_windows · 实施计划

前置：`10-19-skill-instance-multiplicity` 与 `10-19-runtime-card-creation` 已完成并通过各自测试。

---

## A1 池数据文件

- [x] A1.1 新增 `game_data/composed_skill_pools.gd`（`class_name ComposedSkillPools extends RefCounted`），顶部集中声明 3 个常量数组：`TIMING_ENTRIES`（23 项）、`JINCHENG_EFFECTS`（24 项）、`QUEXIAN_EFFECTS`（18 项）。
- [x] A1.2 每个条目形如 `{"key":"<稳定键>", "text":"<逐字原文>", "timing":"<时机名>", "role":"<角色>", "condition":"<条件种类>"}`；效果条目为 `{"key":…, "text":…, "needs_choice":bool, "loses_skill":bool}`。
- [x] A1.3 静态查询函数：`get_timing_entry(key)`、`get_effect_entry(kind, key)`、`get_effects(kind)`、`compose_description(timing_text, effect_text)`、`is_valid_timing_key(key)`、`is_valid_effect_key(kind, key)`。
- [x] A1.4 `compose_description` 严格返回 `"锁定技，" + 时机 + "，" + 效果 + "。每回合限一次。"`。

**验证**：新增测试断言 23 / 24 / 18 项数量、顺序、文本逐字等于需求原文；`compose_description` 输出与需求示例一致。
**回滚点**：纯新增文件。

---

## A2 组合技能脚本骨架

- [x] A2.1 新增 `game_data/skills/jincheng.gd`（`id="jincheng"`、`name="进程"`、`lock=true`、`ui_enabled=false`）。
- [x] A2.2 新增 `game_data/skills/quexian.gd`（`id="quexian"`、`name="缺陷"`、`lock=true`、`ui_enabled=false`）。
- [x] A2.3 两者共用一个内部实现（提取 `game_data/skills/composed_skill_base.gd`，`class_name ComposedSkillBase extends SkillDefinition`），子类只覆盖 `_pool_kind()` 与效果池取值；**不得**复制两份效果实现。
- [x] A2.4 `install()`：读 `get_runtime_skill_data(owner_player_id, get_instance_key())` → 取 `timing_key` → 经池表映射 → `subscribe_timing(时机, _on_composed_timing, role, priority, first_do, last_do, condition)`；映射缺失时 `push_error` + `add_log` 且不订阅。
- [x] A2.5 `_on_composed_timing(event)`：条件细化 → `announce_activation({...})` → 分派效果（需要选择的走 `request_*` + `continue_selection`，不需要的直接执行）→ 若 `loses_skill` 则移除本实例。
- [x] A2.6 AI 段：`score_ai_choice` 支持组合窗口与效果内选择；`score_ai_action` 返回 0.0。

**验证**：测试手工注入 `runtime_skill_data` 后 `install()`，断言订阅存在且时机触发进入效果分派。
**回滚点**：纯新增文件。

---

## A3 时机映射验收表（23 项）

每条都必须以真实派发验证：构造该时机 → 断言组合技能被触发、`announce_activation` 记录出现、效果执行。

| # | 池文本（逐字） | 时机名 | role | 额外条件 |
|---|---|---|---|---|
| 1 | 当你受到伤害后 | `damageAfter` | `target` | 无 |
| 2 | 当你失去体力后 | `loseHpAfter` | `target` | 无 |
| 3 | 当你受到属性伤害后 | `damageAfter` | `target` | `nature ∈ {fire, thunder}` |
| 4 | 当你造成伤害后 | `damageAfter` | `source` | 无 |
| 5 | 当你造成属性伤害后 | `damageAfter` | `source` | `nature ∈ {fire, thunder}` |
| 6 | 当你回复体力后 | `recoverAfter` | `target` | 无 |
| 7 | 当你的体力上限发生变化后 | `gainMaxHpAfter` + `loseMaxHpAfter` | `target` | 两个订阅，任一触发即算 |
| 8 | 当你的体力值发生变化后 | `changeHp` | `target` | 无 |
| 9 | 每轮开始时 | `roundStart` | `global` | 无 |
| 10 | 每轮结束时 | `roundEnd` | `global` | 无 |
| 11 | 回合开始时 | `phaseBegin` | `player` | 无 |
| 12 | 回合结束时 | `phaseEnd` | `player` | 无 |
| 13 | 判定阶段开始时 | `phaseJudgeBegin` | `player` | 无 |
| 14 | 出牌阶段开始时 | `phaseUseBegin` | `player` | 无 |
| 15 | 摸牌阶段开始时 | `phaseDrawBegin` | `player` | 无 |
| 16 | 弃牌阶段开始时 | `phaseDiscardBegin` | `player` | 无 |
| 17 | 当你使用【杀】时 | `useCard` | `source` | `effect_id == "slash"` |
| 18 | 当你成为【杀】的目标时 | `useCardToTargeted` | `target` | `effect_id == "slash"` |
| 19 | 当你的武将牌翻面时 | `turnOverAfter` | 以实际事件字段为准 | 实现时读取 `turn_over_player` 的事件字段确定 role |
| 20 | 当你因弃置而失去牌时 | `cardsDiscardedBatchAfter` | `player` | 每次弃置批次触发一次 |
| 21 | 当你于回合外失去牌时 | `loseAfter` | `player` | `state.current_player_id != owner_player_id` |
| 22 | 当一名角色死亡后 | `dieAfter` | `global` | 无 |
| 23 | 当一名角色脱离濒死状态后 | `dyingAfter` | `global` | 无 |

- **注意**：`washCard` 虽在 `RuleTimingCatalog` 中，但只由 `_record_runtime_event` 记录、从不 `_emit_rule_timing`，**不可订阅**；本池不含该项，实现时不得误用。
- 第 19 项的 role 必须在实现时以 `turn_over_player`（`match_controller.gd:5021`）实际派发的 `player_id`/`target_id` 字段确定，不得猜测。

---

## A3.5 新增核心端口（N1–N4）

调研结论：42 项效果中 **30 项可直接拼装**，**7 项需技能自管回合标记**，**3 项必须先补核心端口**。随机相关一律走 `pick_random_candidate_index(candidate_count, history_kind, history_data)`（`match_controller.gd:7301`），**禁止直接 `randi()`**，否则回放与联机不同步。

- [x] A3.5.1 **N1 攻击范围修正**（补 A15）：`SkillDefinition.modify_attack_range(current_range) -> int`（钩子）+ `MatchController.modify_skill_attack_range(player_id, current_range) -> int`（聚合器，与 `modify_skill_distance_to_target` 同构）+ `card_rule_service.gd:71` 之后接上 provider。
- [x] A3.5.2 **N2 从牌堆使用实体牌**（补 A8）：`execute_pile_card_use(actor_id, card_uid, target_ids, rule_overrides, virtual_storage) -> bool` + `use_random_equipment_card_from_draw_pile(player_id, reason) -> bool`。牌必须经 `CardMovementService` / `_move_card_with_timings` 进入处理区并走完整 `_execute_card_use` 管线（**不得**照抄私有 `_equip_conquest_enemy_from_piles` 的绕过做法）。
- [x] A3.5.3 **N3 持续不可响应**（补 B9）：`PlayerState.response_blocked_until_turn: Dictionary` + `set_response_blocked_until_turn_end(...)` / `is_response_blocked_until_turn_end(...)`。**必须同时接入三处**：`request_response_card_patterns` 的 `:5281` 旁、`_build_response_choice_candidates`（`:5389`）开头、`_get_immediate_equipment_response_candidate`（`:5364`）开头。到期在 `_complete_finish_turn`（`:14867`）内、`phaseAfter` 之前，按「回合角色 + 回合号」双重匹配清理。
- [x] A3.5.4 **N4 回合域手牌上限加成**（补 A13/B6）：`PlayerState.turn_hand_limit_bonus: int` + `add_turn_hand_limit_bonus(...)`，`get_hand_limit()` 公式加入该项，回合末清零。**理由**：现有 `add_hand_limit_bonus` 是永久累加，若技能在回合中被压制/换将，负向残留会**永久压低手牌上限**（真实规则漏洞）。

**验证**：N1/N2/N3/N4 各自新增单元断言；`gameplay_regression_test`、`card_timing_sequence_test`、`yuezhi_mechanics_test` 全绿。
**回滚点**：四个端口相互独立，可逐个回滚。

---

## A4 进程效果验收表（24 项）

每项都必须真实结算并断言可观测结果。**端口已全部核实**（详见 `research/05-composed-skill-effect-ports.md`）。

| # | 池文本（逐字） | 端口 / 机制 | 验收断言 |
|---|---|---|---|
| A1 | 你摸一张牌 | `draw(owner, 1)`（`:4477`） | 手牌 +1，牌来自摸牌堆顶 |
| A2 | 你从牌堆中获得一张锦囊牌 | `gain_top_draw_card_matching(owner, {"type":"trick"}, reason)`（`:7713`） | 手牌 +1 且该牌 `type == "trick"`；牌堆 -1 |
| A3 | 你从牌堆中获得一张基本牌 | 同上，`{"type":"basic"}` | 同上 |
| A4 | 你从牌堆中获得一张装备牌 | 同上，`{"type":"equipment"}` | 同上 |
| A5 | 你从牌堆中获得一张“以太”牌 | `gain_top_minted_card_from_draw_or_discard(owner, "yitai", reason)`（child 2 端口 B3.8）。**「以太」牌 = `minted_skill_id == "yitai"` 的牌**，不是按牌名匹配（牌名由玩家自由指定） | 命中时手牌 +1 且该牌 `minted_skill_id == "yitai"`；无命中时无变化且写日志 |
| A6 | 从牌堆中获得一张【闪】 | `gain_top_draw_card_matching(owner, {"effect_id":"dodge"}, reason)` | 手牌 +1 且该牌 `definition_id == "shan"` |
| A7 | 从牌堆中获得一张【杀】 | `gain_top_draw_card_matching(owner, {"effect_id":"slash"}, reason)` | 手牌 +1 且 `effect_id == "slash"` |
| A8 | 你随机使用牌堆中的一张装备牌 | **N2** `use_random_equipment_card_from_draw_pile(owner, reason)` | 牌堆 -1；该牌经处理区完成一次**真实用牌结算**（`useCard*` 时机与次数校验生效）；`random_history` 记录选择 |
| A9 | 你将武将牌重置 | `set_player_linked(owner, false, source, reason)`（`:4990`） | `chained` 为 false；已竖置时不产生副作用 |
| A10 | 你弃置一名角色区域内的一张牌 | `get_player_zone_candidates(viewer, target)`（`:7949`）+ `discard_selected_player_card(source, target, uid)`（`:8062`） | 目标区域 -1，弃牌堆 +1 |
| A11 | 你获得一名角色装备区内的一张牌 | `get_equipment_candidates(...)`（`:8778`）+ `take_selected_player_card(...)`（`:6830`） | 目标装备槽清空（触发 `_on_equipment_lost`），自己手牌 +1 |
| A12 | 你获得不为你的当前回合角色的一张手牌 | `get_hand_candidates(...)`（`:8067`）+ `take_selected_player_card(...)` | 目标手牌 -1，自己手牌 +1；候选不含当前回合角色 |
| A13 | 你的手牌上限+2直到回合结束 | **N4** `add_turn_hand_limit_bonus(owner, 2, source, reason)` | 本回合 `get_hand_limit()` +2；回合结束后自动恢复 |
| A14 | 你的出牌阶段使用【杀】的次数上限+1直到回合结束 | 覆写 `get_play_count_limit_bonus(card_definition)`（`skill_definition.gd:900`）+ 自管 turn flag，`phaseAfter` 复位 | 本回合可多使用 1 张【杀】；回合结束后恢复 |
| A15 | 你使用攻击范围+2直到回合结束 | **N1** 覆写 `modify_attack_range(current)` 返回 `current + 2` + 自管 turn flag | `get_attack_range(owner)` 本回合 +2；回合结束后恢复 |
| A16 | 你计算与其他角色距离-1直到回合结束 | 覆写 `modify_distance_to_target(target_id, current)` 返回 `current - 1` + 自管 turn flag | `calculate_distance` 本回合 -1（最低 1）；回合结束后恢复 |
| A17 | 防止你受到伤害直到回合结束 | 订阅 `damageBegin4`（role `target`），标记有效时 `event.cancel(reason)`（模板 `yuezhi.gd:72/150`） | 本回合内受到的伤害不扣血；回合结束后恢复正常 |
| A18 | 你视为使用一张【杀】 | `execute_cardless_virtual_card_use(owner, "sha", targets, log, overrides, storage)`（`:13804`） | 生成一次【杀】的使用结算，材料为 0 |
| A19 | 你视为使用一张【决斗】 | 同上，`"juedou"` | 决斗流程完整结算 |
| A20 | 你视为使用一张【顺手牵羊】 | 同上，`"shunshou"` | 获得目标一张牌 |
| A21 | 你摸两张牌并失去本技能 | `draw(owner, 2)` + `remove_skill(owner, 实例键, reason)`（`:11041`） | 手牌 +2；技能栏该实例消失；其余同名实例保留 |
| A22 | 你回复1点体力并失去本技能 | `recover(owner, owner, 1, reason)`（`:4486`）+ `remove_skill(实例键)` | 体力 +1（不超上限）；该实例消失 |
| A23 | 你增加1点体力上限并失去本技能 | `change_max_hp(owner, 1, source, reason)`（`:4545`）+ `remove_skill(实例键)` | 体力上限 +1；该实例消失 |
| A24 | 你获得1点护盾并失去本技能 | `shield(owner, 1, source, reason)`（`:4495`）+ `remove_skill(实例键)` | `shield` +1；该实例消失 |

---

## A5 缺陷效果验收表（18 项）

| # | 池文本（逐字） | 端口 / 机制 | 验收断言 |
|---|---|---|---|
| B1 | 你弃置一张手牌 | `get_hand_candidates`（`:8067`）+ `discard_selected_hand_cards(owner, uids)`（`:8103`） | 手牌 -1，弃牌堆 +1；手牌为空时跳过并写日志 |
| B2 | 你随机弃置一张牌 | `get_player_zone_candidates` + `pick_random_candidate_index(...)`（`:7301`）+ `discard_selected_player_cards(...)`（`:6817`） | 总牌数 -1；`random_history` 记录 |
| B3 | 你随机弃置一张装备牌 | `get_equipment_candidates` + `pick_random_candidate_index` + `discard_selected_player_cards` | 装备区 -1；无装备时跳过并写日志 |
| B4 | 你随机弃置一张基本牌 | `get_hand_equipment_candidates`（`:7944`）+ 筛 `type == "basic"` + `pick_random_candidate_index` + `discard_selected_hand_equipment`（`:9063`） | 手牌 -1 且该牌为基本牌 |
| B5 | 你随机弃置一张锦囊牌 | 同 B4，筛 `type == "trick"` | 手牌 -1 且该牌为锦囊牌 |
| B6 | 你的手牌上限-1直到回合结束 | **N4** `add_turn_hand_limit_bonus(owner, -1, source, reason)` | 本回合上限 -1（下限 0）；回合结束后自动恢复 |
| B7 | 你将武将牌调整至横置 | `set_player_linked(owner, true, source, reason)`（`:4990`）——**注意不是 `turn_over_player`（那是翻面）** | `chained` 为 true；已横置时不重复派发 |
| B8 | 你交给不为你的当前回合角色一张牌 | 选牌 `get_hand_equipment_candidates` → 选目标（排除当前回合角色与自己）→ `gain_card_to_hand_by_uid(receiver, uid, reason)`（`:7115`；`:7126` 天然拒绝 `hand→同一人`） | 目标手牌 +1，自己 -1 |
| B9 | 你不可响应其他角色使用的牌直到回合结束 | **N3** `set_response_blocked_until_turn_end(owner, true, source, reason)` | 本回合无法打出【闪】等响应牌（**含装备响应入口**）；回合结束后恢复 |
| B10 | 你计算与其他角色的距离+1直到回合结束 | 覆写 `modify_distance_to_target` 返回 `current + 1` + 自管 turn flag | `calculate_distance` 本回合 +1；回合结束后恢复 |
| B11 | 本回合内你下次受到的伤害+1 | 订阅 `damageBegin3`（role `target`）改 `event.data["amount"]`；`damage` 消费、`damageCancelled`/`damageZero` 释放；预留事件 ID 防重复（模板 `zhuijian.gd:39/82/40-42`） | 下一次伤害 +1；仅生效一次；被取消/归零时不消费 |
| B12 | 本回合内你下次受到的属性伤害+1 | 同 B11，条件增加 `nature ∈ {fire, thunder}` | 下一次属性伤害 +1；非属性伤害不消费 |
| B13 | 你下次回复的体力-1直到回合结束 | 订阅 `recoverBegin`（role `target`）改 `event.data["amount"] -= 1`，一次性消费。**项目内无内容先例，属首次使用该路径，需重点验证** | 下一次回复 -1（最低 0）；仅生效一次 |
| B14 | 你失去1点体力并失去本技能 | `lose_hp(source, owner, 1, reason)`（`:5050`）+ `remove_skill(实例键)` | 体力 -1（可致濒死）；该实例消失 |
| B15 | 你受到1点伤害并失去本技能 | `damage(source, owner, 1, "normal", ...)`（`:5127`）+ `remove_skill(实例键)` | 体力 -1；该实例消失 |
| B16 | 你受到1点雷电伤害并失去本技能 | 同上，`nature = "thunder"` | 伤害性质为 thunder |
| B17 | 你受到1点火焰伤害并失去本技能 | 同上，`nature = "fire"` | 伤害性质为 fire |
| B18 | 你减少1点体力上限并失去本技能 | `change_max_hp(owner, -1, source, reason)`（`:4545`，内部夹到 ≥1）+ `remove_skill(实例键)` | 体力上限 -1（最低 1）；该实例消失 |

**回合末回收的统一机制**：A14/A15/A16/A17/B10/B11/B12/B13 是「直到回合结束」的临时状态，统一在组合技能基类中以 `_turn_scoped_flags` 实现，由 `phaseEnd`（本人回合结束）清空，并把标记写入 `runtime_skill_data` 以支持读档恢复。A13/B6 走 N4 由核心层统一到期，**不**由技能自行回滚（避免技能被压制/换将时的永久残留漏洞）。

**已知语义陷阱（实现时不得踩）**：

1. 横置用 `set_player_linked`，翻面用 `turn_over_player` —— 两者不可互换。
2. `shield_after` **未登记进 `RuleTimingCatalog`**，`subscribe_timing("shield_after", …)` 会静默返回 `-1`；如确需该时机，只能用 `host.event_bus.subscribe(...)`。
3. `add_card_target_damage_bonus`（`:8882`）是逐目标牌内增伤，**不是**「下次受到的伤害」，不得混用。
4. `washCard` 不可订阅（只 `_record_runtime_event`）。
5. 「并失去本技能」用 `remove_skill(owner, 实例键)`（只移除该实例）；不要用 `remove_all_skills`。

---

## A6 银狼武将文件

- [x] A6.1 新增 `game_data/characters/yinlang.gd`：`preload` 两个技能脚本 + `super({id:"yinlang", display_name:"银狼", gender:"female", faction:"xinghelieshou", max_hp:3, description:"<需求原文>"}, [ZHURU_SKILL, YITAI_SKILL])`。
- [ ] A6.2 立绘资源 `game_data/characters/image/yinlang.png` 由用户提供；缺失时记录在交付说明，不阻塞功能。

**验证**：`GameDatabase.get_character("yinlang")` 的 `skills == ["zhuru","yitai"]`；选将列表包含 `yinlang`；`_validate_characters` 无错误。
**回滚点**：删除文件即回滚。

---

## A7 注入（`zhuru.gd`）

- [x] A7.1 `install()`：订阅 `gameStart`（`global`）与 `phaseZhunbeiBegin`（`player`）。
- [x] A7.2 `gameStart`：可取消的「是否发动」询问 → 打开注入窗口（类别 `jincheng`，目标为自己）。
- [x] A7.3 `phaseZhunbeiBegin`：先 `request_target_selection`（候选 = 存活未离场角色含自己，可取消）→ 判定 `is_starring_role(目标)` → 类别 `jincheng` / `quexian` → 打开注入窗口。
- [x] A7.4 组合结果落地：`grant_acquired_skill(目标, 类别ID, 1, 0, "zhuru", false, 0, true)`；随后用「授予前后 `get_installed_skill_keys` 差集」定位新实例键 → `set_runtime_skill_data` + `set_skill_display_description`。
- [x] A7.5 差集为空（异常）时写 `push_error` + 日志，不产生半成品状态。
- [x] A7.6 嵌套屏障：在时机回调内创建选择前按项目约定检查 `has_nested_settlement_barrier()`，必要时 `defer_settlement()` / `continue_settlement()`。

**验证**：见 A13 的注入测试。
**回滚点**：删除文件 + 从武将技能列表移除。

---

## A8 以太（`yitai.gd`）

- [x] A8.1 `install()`：订阅 `phaseAfter`（`global`）；主动入口 `phaseUse`（`ui_enabled = true`，`limited` 由正文自动标记）。
- [x] A8.2 `can_activate`：持有者存活未离场、`has_available_intrinsic_use()`、处于本人出牌阶段。
- [x] A8.3 `activate`：打开造牌窗口 → 收到 `control_id` → `mint_card_for_player(owner, 定义ID, 牌名, 花色, 点数, "yitai")`；返回 `-1` 时不消耗额度并写日志。
- [x] A8.4 `phaseAfter` 回调：`get_discard_pile_card_uids_by_skill("yitai")` 非空 → `set_starring_role(owner)` → 逐张 `shuffle_discard_card_into_draw_pile(uid)`。
  - **口径**：「以太」牌 = `minted_skill_id == "yitai"` 的牌（牌名由玩家自由指定，不能按牌名判定）。
  - **口径**：`phaseAfter` 在翻面跳过回合时**不会派发**（`_complete_face_down_skipped_turn` 绕过 `_complete_finish_turn`），因此该回合不补偿；此口径需写入文档。
- [x] A8.5 记录：`announce_activation` 写入 `{"minted_card_uid":…}` 与 `{"washed_card_uids":[…]}`。

**验证**：见 A13 的以太测试。
**回滚点**：删除文件 + 从武将技能列表移除。

---

## A9 主题语义键（高科技黑蓝）

- [x] A9.1 `ui_style_registry.gd` 三个调色板各新增 `tech_panel` / `tech_border` / `tech_accent` / `tech_grid`，取值统一为黑蓝系（深色面板 + 亮蓝描边/强调 + 暗蓝分隔）。
- [x] A9.2 确认 `BattleUIStyle.get_color("tech_*")` 在三种风格下都返回有效颜色，且 `is_monochrome()` 语义不被破坏。

**验证**：新增断言「三种风格的四个 `tech_*` 键都存在且非 `UNSET_COLOR`」；`font_color_audit_test` 全绿。
**回滚点**：调色板为纯增量键。

---

## A10 `yinlang_windows` 窗口

- [x] A10.1 新增 `scenes/components/yinlang_windows_layer.tscn`（根 `Control` 全屏 + `Shade` + `Frame`），结构参照 `opportunity_choice_panel.tscn`。
- [x] A10.2 新增 `scripts/ui/yinlang_windows_layer.gd`（`class_name YinlangWindowsLayer extends Control`，`MODAL_Z_INDEX = 185`）：`_ready()` 设 `process_mode = PROCESS_MODE_ALWAYS`、`z_index`、`visible = false`、`Shade.mouse_filter = MOUSE_FILTER_STOP`。
- [x] A10.3 新增 `scripts/ui/yinlang_compose_view.gd`（注入窗口：两栏 + 默认 2 候选 + 展开全部 + 实时预览 + 确定/取消）。
- [x] A10.4 新增 `scripts/ui/yinlang_mint_view.gd`（以太窗口：牌名输入 + 花色 + 点数 + 效果类别分组列表 + 预览 + 确定/取消）。
- [x] A10.5 `refresh_ui_style()`：全部颜色经 `BattleUIStyle` / `UIStyleRegistry` 的 `tech_*` 键；每个 `Label`/`CheckBox` 设 `font_color`，`RichTextLabel` 设 `default_color`；`LineEdit` 设 `add_theme_font_override("font", ThemeDB.fallback_font)`。
- [x] A10.6 以太窗口的牌名输入实时调用本地唯一性预校验（数据来自请求 `context["existing_card_names"]`），冲突/为空/超长时显示提示并禁用「确定」。
- [x] A10.7 注入窗口提交 `control_id = "yinlang|compose|<时机键>|<效果键>"`；以太窗口提交 `control_id = "yinlang|mint|<牌名>|<花色>|<点数>|<定义ID>"`。
- [x] A10.8 窗口只接收普通字典、只通过信号回报；不读 `GameState`、不持有 `MatchController` 做规则调用。

**验证**：`ui_layout_test`（含新增层级断言）、`font_color_audit_test` 全绿；`editor_screenshot(source="game")` 目视确认黑蓝风格与两栏/四行布局。
**回滚点**：删除 4 个新文件 + 还原 `match_table` 的分流改动。

---

## A11 协议与分流

- [x] A11.1 `match_controller.gd` 常量区新增 `YINLANG_COMPOSE_CHOICE_TYPE` / `YINLANG_MINT_CHOICE_TYPE`。
- [x] A11.2 `choice_request.gd` 新增 `allow_free_control_id: bool = false`（含 `to_dict` / `from_dict`）与 `validate_response` 分支。
- [x] A11.3 `match_controller.gd:3917` 的自由控制项集合加入两个新类型；`:3937`/`:3944` 旁新增结构校验分支。
- [x] A11.4 `_build_card_choice_actions()` 新增分支：自由控制项类型按 `context["ai_candidate_control_ids"]` 生成确认动作（去重、限长 8）。
- [x] A11.5 `match_table._is_inline_control_choice` 对带 `context["yinlang_window"]` 的请求返回 false。
- [x] A11.6 `match_table._refresh_card_selection_panel` 分流：关闭 `card_selection_panel`，改开 `yinlang_windows_layer`。
- [x] A11.7 `match_table` 顶部 preload + `var yinlang_windows_layer` + `_create_yinlang_windows_layer()` + `_ready()` 调用 + `_on_ui_style_changed` 追加 `refresh_ui_style()`。
- [x] A11.8 窗口提交经 `_on_control_choice_submitted` 的既有形状（`PlayerAction.new("choose_cards", actor)` + `payload.selected_control_id`）。

**验证**：`tests/event_runtime_test.gd` 增加「`allow_free_control_id=false` 时仍拒绝未登记 `control_id`」断言；新增「窗口提交能通过权威校验」断言。
**回滚点**：协议改动集中在 3 个文件，可独立回滚。

---

## A12 AI

- [x] A12.1 注入：`score_ai_choice` 对组合窗口按效果价值 × 时机契合度打分；技能生成 `ai_candidate_control_ids` 短名单（按分数降序前 8 项）。
- [x] A12.2 以太：`score_ai_choice` 按被复制牌的 AI 价值打分；技能生成一个自动唯一牌名（例如 `以太造物<N>`）与预设花色点数，组成短名单。
- [x] A12.3 目标选择（准备阶段选人）AI 偏好：优先主演（获得进程）或按身份态度选择。
- [x] A12.4 组合技能自身无主动发动，`score_ai_action` 返回 0.0；效果内选择按 A4/A5 各行的收益打分。

**验证**：AI 控制银狼时能完成全部窗口作答（测试中把 `local_human_player_id` 设为他人，让银狼由 AI 控制，断言技能被授予）。
**回滚点**：AI 段集中在两个技能文件与池文件。

---

## A13 测试

- [x] A13.1 新增 `tests/yinlang_mechanics_test.gd` + `.tscn`，覆盖：
  - 武将元数据（星核猎手、女、体力 3、技能顺序）。
  - 池数据数量/顺序/逐字文本。
  - `gameStart` 与 `phaseZhunbeiBegin` 两个入口；取消不产生效果。
  - 主演分支：目标为主演 → 进程；非主演 → 缺陷。
  - 连续两轮 → 两个同名组合技能；技能栏各占一项；`per_turn_limit` 分别计算（其一发动后其二仍可发动）。
  - 组合后正文逐字等于 `"锁定技，<时机>，<效果>。每回合限一次。"`。
  - 以太造牌：四项选择 → 新牌入手、牌名/花色/点数正确、类别与效果同被复制牌。
  - 牌名冲突被拒绝且无副作用。
  - 回合结束回流：弃牌堆有「以太」牌 → 银狼成为主演 + 该牌回到摸牌堆。
  - 限定技只能发动一次。
  - 「并失去本技能」只移除该实例。
  - 逐条效果验收（A4 / A5 两张表）。
- [x] A13.2 扩展 `tests/ui_layout_test.gd`：`yinlang_windows` 层级 > 机缘弹窗（180）且 < 结算面板（220）。
- [x] A13.3 运行并确认全绿：`yinzhi_xunli_lijie_test`、`smoke_test`、`new_character_mechanics_test`、`gameplay_regression_test`、`ui_layout_test`、`font_color_audit_test`、`skill_ownership_test`、`skill_instance_multiplicity_test`、`runtime_card_minting_test`、`yuezhi_mechanics_test`（防止伤害与回复口径回归）、`ahha_moment_test`。

**回滚点**：测试为纯增量。

---

## A14 文档

- [x] A14.1 `docs/内容制作指南.md`：新增「运行时组合技能（进程 / 缺陷）」「银狼与 yinlang_windows」「自由文本输入型选择请求（`allow_free_control_id`）」三节。
- [x] A14.2 `docs/游戏机制与玩法内容.md`：完整记录银狼、注入、以太、组合技能池（逐字列出 23 + 24 + 18 项）、造牌规则、回合结束回流、全部数值与全部补全口径。
- [x] A14.3 `docs/界面与交互.md`：新增 `yinlang_windows` 章节 + 更新层级表（插入 `185`）。
- [x] A14.4 `docs/架构说明.md`：记录 `allow_free_control_id` 与 AI 候选短名单机制。
- [x] A14.5 `README.md`：测试场景清单补充 `yinlang_mechanics_test`。
- [x] A14.6 `临时反馈文档.md`：追加学习反馈摘要 + Git 提交描述（带时间戳）。

---

## 依赖与顺序

```
A1 → A2 → A3 → A4 → A5
A1 → A6 → A7 → A8
A9 → A10 → A11 → A12
A3..A12 → A13 → A14
```

A9/A10（主题与窗口）可与 A3-A5（效果实现）并行；A13 必须最后执行。
