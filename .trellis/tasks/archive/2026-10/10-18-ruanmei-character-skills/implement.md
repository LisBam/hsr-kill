# 执行计划 · 阮梅与【梅绽】【灵赋】【阮弦】

> 前置条件：兄弟任务 `10-18-skill-ownership-query-port` 已完成（统一入口可用）。
> 每完成一个步骤就同步对应文档，不允许跨步骤遗留。

## 0. 动手前

- [x] 加载 `trellis-before-dev`，读取 `game_data` 层（技能制作）与 `scripts/ai` 层的 spec 与 Quality Check 清单。
- [x] 确认兄弟任务的统一入口已可用：`MatchController.has_skill()`、`SkillDefinition.snapshot_has_skill()`、`SkillDefinition.collect_snapshot_skill_ids()`。
- [x] 确认 `game_data/characters/ruanmei.gd` 与 `game_data/skills/{meizhan,lingfu,ruanxian}.gd` 均**不存在**（避免误覆盖）。
- [x] 确认 `game_data/factions.json` 中银河学者 ID 为 `yinhexvezhe`。

## 1. 【梅绽】`game_data/skills/meizhan.gd`

- [x] 写常量：`MEIZHAN_SKILL_ID`、`DRAW_COUNT = 1`、`SELL_BLOOD_VALUE = 1.0`。
- [x] `_init()`：`lock:true`、`trigger:["damageAfter"]`、`sell_blood_value:1.0`、无 `enable`、`ui_enabled:false`；`description` 逐字写入原文（**两个引号都是右引号 `”`**）。
- [x] `install()`：`subscribe_timing("damageAfter", _on_owner_damaged, "target")`。
- [x] `_on_owner_damaged()`：`hp_lost <= 0` 直接返回；遍历座次、跳过死亡/离场、用 `has_skill` 判定、命中者 `draw(1)`。
- [x] `modify_ai_incoming_card_effect()`：只对 `ai_profile.damage == true` 生效；跳过 `target_id` 本人；用 `snapshot_has_skill` + `get_attitude` 累计 `+1/−1`；乘 `NonameAIEvaluator.CARD_RESOURCE_VALUE`。

## 2. 【灵赋】`game_data/skills/lingfu.gd`

- [x] 写常量（见 `design.md` 3.3），全部独占一行注释。
- [x] `_init()`：`trigger:"active"`、`enable:"phaseUse"`、`ui_enabled:true`；`description` 逐字写入原文。
- [x] `install()`：`subscribe_timing("phaseUseBegin", _on_phase_use_begin, "player")`；回调里把 `_used_this_play_phase` 置回 `false`。
- [x] `_get_used_categories()` / `_mark_used_category()`：读写 `character_form_state[USED_CATEGORIES_KEY]`，带类型收敛。
- [x] `_get_recast_candidates()`：`get_hand_candidates` → 按 `GameDatabase.get_card(...).type` 过滤 → 排除已用类别 → 保持手牌顺序。
- [x] `_get_target_ids()`：全部存活且未离场角色，**含自己**。
- [x] `can_activate()`：持有者存活在场 + 当前是自己出牌阶段 + `_used_this_play_phase == false` + 候选非空 + 目标非空。
- [x] `activate()`：`request_card_target_selection(...)`，`min/max_cards = 1`、`min/max_targets = 1`、`allow_cancel = true`、`{kind: CHOICE_KIND}`。
- [x] `continue_selection()`：复核目标 → 复核材料 → `recast_hand_card` → 失败即结束 → 记账（类别 + 阶段）→ `announce_activation` → `defer_settlement({kind: SETTLEMENT_KIND, target_id})`。
- [x] `continue_settlement()`：`SETTLEMENT_KIND` 分流 → 复核目标仍存活在场 → 分支一 `grant_acquired_skill` / 分支二 `change_max_hp` + `recover` + `remove_skill`（顺序严格）。
- [x] `append_play_phase_actions()`：`can_activate()` 为真时追加 `use_skill` 动作。
- [x] `score_ai_action()` / `score_ai_choice()`：按 `design.md` 6.2 实现三级优先 + 通用逻辑；两层的费用估算共用同一个 `_get_recast_cost_value()`。
- [x] 自查：无字面量魔法数字、无技能 ID 白名单、每个变量独占一行注释、Tab 缩进。

## 3. 【阮弦】`game_data/skills/ruanxian.gd`

- [x] 写常量（见 `design.md` 4.2）。
- [x] `_init()`：`trigger:"phaseEnd"`、`ui_enabled:false`；`description` 逐字写入原文。
- [x] `install()`：`subscribe_timing("phaseEnd", _on_owner_phase_end, "player")`。
- [x] `_get_used_suits()` / `_mark_used_suit()`：读写 `character_form_state[USED_SUITS_KEY]`，带类型收敛。
- [x] `_get_recast_candidates()`：`get_hand_candidates` → `type == "trick"` → 排除已用花色。
- [x] `_get_other_meizhan_holder_ids()`：排除自己、存活在场、`has_skill(..., "meizhan")`。
- [x] `_can_offer()`：持有者存活在场 + 候选非空 + 其他持有者非空。
- [x] `_on_owner_phase_end()`：复核 → `has_nested_settlement_barrier()` 为真则 `defer_settlement({kind: REBUILD_KIND})` 返回 → 否则 `request_card_selection(...)`。
- [x] `continue_selection()`：复核材料 → `recast_hand_card` → 失败即结束 → 记账（花色）→ `announce_activation` → `defer_settlement({kind: SETTLEMENT_KIND})`。
- [x] `continue_settlement()`：`REBUILD_KIND` 重跑 `_can_offer()` 后重建请求；`SETTLEMENT_KIND` 让**其他**持有者各摸1张。
- [x] `score_ai_action()` / `score_ai_choice()`：按 `design.md` 6.3 实现；严格正分才发动。

## 4. 武将 `game_data/characters/ruanmei.gd`

- [x] 三个 `const X_SKILL: Script = preload(...)` 前置声明。
- [x] `super({...}, [MEIZHAN_SKILL, LINGFU_SKILL, RUANXIAN_SKILL])`，顺序固定。
- [x] `id=ruanmei`、`display_name=阮梅`、`gender=female`、`faction=yinhexvezhe`、`max_hp=3`。

## 5. 回归用例

- [x] 按 `design.md` 第 7 节的表格新增测试（建议落在 `tests/ruanmei_mechanics_test.gd` + 现有场景的入口挂载）。
- [x] 技能拥有查询相关的用例属于兄弟任务，本任务只消费、不重复实现。

## 6. 文档同步

- [x] `docs/游戏机制与玩法内容.md`：阮梅条目 + 三技能机制 + 全部数值。
- [x] `docs/AI模块.md`：梅绽动态卖血口径 + 灵赋/阮弦 AI 决策口径。
- [x] `docs/内容制作指南.md`：全局限次写入 `character_form_state` 的约定、重铸先于后续效果的 `defer_settlement` 用法、动态卖血钩子用法。
- [x] `README.md`：武将 / 技能计数若存在则同步。

## 7. 验证与收尾

- [x] `GameDatabase.validation_errors` 为空；开局选将能看到阮梅。
- [x] 串行跑通：`gameplay_regression_test`、`ai_policy_test`、`new_character_mechanics_test`、`skill_settlement_runtime_test`、`event_runtime_test`、`rule_timing_test`、`health_mechanics_test`、`phase_progression_test`；无 `SCRIPT ERROR` / `FAIL`。
- [x] 加载 `trellis-check` 执行质量门禁。
- [x] 写「学习反馈摘要」（修改思路 / 架构与设计 / Bug 原因与修复方法 / 关键代码解析 / 学习要点提炼）。
- [x] 写编号 Git 提交描述（每项改动独占一行）。
- [x] 把上面两项带 `YYYY-MM-DD HH:MM` 时间戳追加到根目录 `临时反馈文档.md`。

## 8. 回滚点

- 删除 `game_data/characters/ruanmei.gd` 与 `game_data/skills/{meizhan,lingfu,ruanxian}.gd` 即完全退出（内容目录自动扫描，无其他注册点）。
- 【灵赋】顺序问题的回滚点是 `lingfu.gd` 的 `activate` / `continue_selection` / `continue_settlement` 三个函数。
- 全局限次问题的回滚点是两个技能各自的 `_get_used_*` / `_mark_used_*` 四个函数。

## 9. 执行记录（与计划的偏差）

1. **`_get_used_values(key)` / `_mark_used(key, value)` 通用对没有落地**：`design.md` 第 5 节建议抽一对通用读写函数，实际改为按技能各写具体函数（`_get_used_categories` / `_mark_used_category`、`_get_used_suits` / `_mark_used_suit`）。理由：键名与取值域都是每个技能私有的稳定常量，通用对只会多一层参数转发；这也与既有 `xinji.gd` 的 `_get_triggered_ids` / `_mark_triggered` 先例一致。
2. **`_pick_grant_target` 未单独抽出**：最初写成一行包装，随后内联进 `_pick_ai_target`，避免无意义的抽象层。
3. **【灵赋】的目标选择由 `_pick_lowest_hp_target` 升级为 `_pick_best_target`**（先比毛收益、再比体力、最后比座次）。原计划只按体力排序，但升级分支对自己的收益要扣掉 `AI_SKILL_LOSS_COST`，只按体力排序会在“自己与队友同为最低体力”时优先自弃技能；先比毛收益后队友恒胜自己。设计意图不变，取舍规则更严谨。
4. **【梅绽】未加“目标是否拥有梅绽”的前置判定**：通用层调用 `modify_ai_incoming_card_effect()` 时遍历的是**目标角色自己的技能列表**，进入钩子即已保证目标拥有该技能，再加一层判定是死代码。改为在源码注释里写明该前提。
5. **【灵赋】的“二级优先（有卖血技能）”在实际局面上是恒真条件**：因为“梅绽”自身就是卖血技能，二级池的候选必然全部满足该条件，最终由三级规则落到体力最低者。这是锁定设计的直接推论，不是缺陷；已在源码、`docs/AI模块.md` 与 `docs/游戏机制与玩法内容.md` 三处写明。
6. **测试多覆盖了计划外的用例**：`lingfu_cancel_consumed`（取消不消耗额度）、`ruanxian_barrier_rebuild`（重建后的请求与首次请求行为一致）、`ruanxian_ai_expensive_material_not_negative`（高价值材料使 AI 拒绝发动）、以及【灵赋】/【阮弦】全局限次的**存档往返**断言（`PlayerState.from_authoritative_dict(to_dict(-1, true))`），用于锁定 `design.md` 第 7 节“存档往返后同样不复活”一条。
7. **`docs/卡牌系统.md` 无需改动**：该文档第 260 行已经写明“重铸仍严格为弃置1张、随后摸1张；最后手牌触发插入事件时只延后摸牌，不改变数量”，与本次实现完全一致。
8. **额外同步 `.trellis/spec/content/skill-authoring.md`**：新增四节（先重铸后效果的顺序保证、触发时机里创建请求的两段式、全局归属效果与全局限次的存放位置、重铸的口径），把本次学到的约定固化到内容层规范里。

## 10. 验证证据

- `GameDatabase.validation_errors` 为空（`smoke_test` 断言）：`SMOKE_PASS game_over winner=rebels actions=221 frames=795`，EXIT=0。
- 新增 `tests/ruanmei_mechanics_test.tscn`：`RUANMEI_MECHANICS_PASS metadata=1 verbatim=3 meizhan=3 lingfu=5 ruanxian=4 ai=2`，EXIT=0。
- 串行回归全部 EXIT=0 且无 `SCRIPT ERROR` / `FAIL`：`smoke_test`、`skill_ownership_test`、`multi_recast_test`、`ruanmei_mechanics_test`、`gameplay_regression_test`、`ai_policy_test`、`new_character_mechanics_test`、`skill_settlement_runtime_test`、`event_runtime_test`、`rule_timing_test`、`health_mechanics_test`、`phase_progression_test`、`ui_layout_test`、`yinzhi_xunli_lijie_test`。
- 文档同步：`docs/游戏机制与玩法内容.md`（阮梅条目 + 三技能机制与全部数值）、`docs/AI模块.md`（四个 AI 条目）、`docs/内容制作指南.md`（四条内容制作约定）、`README.md`（新增测试说明）、`.trellis/spec/content/skill-authoring.md`（四节规范）。
