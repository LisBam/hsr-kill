# 丹恒·饮月与砂金新武将（含批量获得时机机制）

> 本任务是**父任务**，只负责保存来源需求集、子任务地图与跨子任务验收标准，本身不承担实现。
> 实际实现由子任务承担，见「子任务地图」。子任务可以独立规划、实现、验收与归档。

## Goal

新增两名武将与其全部技能：

- **丹恒·饮月**（仙舟联盟 · 男 · 体力值 4）：锁定技【伏辰】、主动技【濯世】
- **砂金**（星际和平公司 · 男 · 体力值 3）：锁定技【筹码】、【盲注】、【风口】

其中【风口】第一段「当你一次性获得至少两张牌时」需要核心层提供**批量获得**的原子语义，而本项目当前只有弃置拥有批次时机（`cardsDiscardedBatchAfter`），获得类时机恒为「一张一次」且载荷不含张数。因此本任务额外包含一个**新核心机制**：与弃置批次对称的**批量获得时机**。

用户价值：补齐两名角色的完整玩法；并把「一次性获得多张牌」建成可复用的核心能力，供后续内容直接订阅。

---

## 来源需求原文（不可变 · 逐字保留）

> 依据项目铁律：以下描述原文的字段、数值、文字表述、标点符号与语句顺序**一律不得改动**。实现必须围绕原文展开。
> 对于**用户在同一轮对话中显式给出的补充与改写**（见「用户补充确认」小节），以补充为准，并在子任务 PRD 中标注该改写的落点。

### 武将一

```
丹恒·饮月danheng_yinyue 仙舟联盟 男 体力值4
```

### 技能一 · 丹恒·饮月

```
伏辰fuchen
锁定技，当其他角色打出一张【杀】后，你获得之。
```

配套强调原文：

```
（注意，是打出）
```

### 技能二 · 丹恒·饮月

```
濯世zhuoshi
出牌阶段限一次，你可以弃置一张基本牌并选择一名其他角色，你弃置其一张手牌，然后你可再次弃置一张基本牌并弃置其一张牌，最后你可再次弃置一张基本牌并对其造成1点雷电伤害。
```

配套强调原文：

```
（注意，第一次是弃置目标手牌，第二次是弃置目标牌。）
```

配套操作逻辑原文：

```
（操作逻辑：点击技能后选择一张基本牌与一名目标然后点击确定，然后选择并弃置目标一张手牌，然后询问是否再次弃置一张基本牌，玩家可以选择一张基本牌再点击确定，然后弃置目标一张牌，然后再次询问是否弃置一张基本牌，然后玩家选择一张基本牌并点击确定，对目标造成伤害。）
```

### 武将二

```
砂金shajin 星际和平公司 男 体力值3
```

### 技能三 · 砂金

```
筹码chouma
锁定技，游戏开始时，你摸X张牌，你的手牌上限+X。（X为你的体力上限）
```

### 技能四 · 砂金

```
盲注mangzhu
摸牌阶段开始时，你可以弃置任意张颜色不同的牌。若如此做，该阶段结束时，若你以此法弃置的牌与你于此阶段内获得的牌有至少一种颜色相同，你获得1点护盾；若有至少两种颜色相同，你摸两张牌。
```

### 技能五 · 砂金

```
风口fengkou
当你一次性获得至少两张牌时，你可以弃置这些牌。出牌阶段，你可以获得一名其他角色的随机一张手牌，你每发动一次该技能便重复一次该流程，然后你失去该技能。
```

配套改写与机制说明原文：

```
（优化描述为“当你一次性获得至少两张牌时，你可以弃置这些牌。出牌阶段，你可以获得一名其他角色的随机一张手牌，你此前每发动一次该技能便重复一次该流程，然后你失去该技能。”发动后，获得其他角色随机手牌1张，然后每发动过一次“当你一次性获得至少两张牌时，你可以弃置这些牌”便重复获得其一张随机手牌，直到其没有手牌或者达到所重复次数，最后失去该技能）
```

---

## 用户补充确认（本轮对话中显式回答，优先级高于模型推断）

| # | 问题 | 用户裁定 |
|---|---|---|
| U1 | 任务与规划流程 | 允许创建 Trellis 任务并进入规划；规划工件审核通过后才动代码 |
| U2 | 【风口】重复次数的口径 | 「发动后，获得其他角色随机手牌 1 张，然后**每发动过一次**『当你一次性获得至少两张牌时，你可以弃置这些牌』**便重复获得其一张随机手牌**，直到其没有手牌或者达到所重复次数，最后失去该技能」 |
| U3 | 【风口】第一段的定位 | 纯独立选项：弃掉即进弃牌堆，**无额外效果**（但仍会正常触发其它「当你弃置牌时」类效果） |
| U4 | 【濯世】弃牌的选择者与可见性 | **由技能持有者暗选**（目标手牌对持有者不可见）；第二段的「一张牌」同样由持有者选择 |
| U5 | 【伏辰】触发范围 | **仅**其他角色「打出」（响应）【杀】时触发，牌进入持有者手牌；其他角色「使用」【杀】不触发 |
| U6 | 【盲注】弃牌口径 | 颜色两两不同 → 受两色限制**最多 2 张**（1 红 + 1 黑）；弃置来源为**手牌 + 装备区** |
| U7 | 批量获得的实现口径 | **新增核心机制「批量获得时机」**（与 `cardsDiscardedBatchAfter` 对称），不在内容层做近似 |

---

## 已确认的仓库事实（证据锚点）

这些是**代码可回答**的问题，已通过只读调研确认，不再作为待问问题。

| # | 事实 | 证据 |
|---|---|---|
| F1 | 势力「仙舟联盟」已登记，ID `xianzhou`、简称「仙」、色 `4f8b62` | `game_data/factions.json:6` |
| F2 | 势力「星际和平公司」已登记，ID `xingjihepinggongsi`、简称「司」、色 `b87333`（「星」已被星间寰宇占用） | `game_data/factions.json:13` |
| F3 | 武将元数据作者可写键仅 `id`/`display_name`/`gender`/`faction`/`max_hp`/`description`（可选 `special`）；`art_path` 与 `skills` 由数据库注入 | `game_data/character_definition.gd:14-33`；`scripts/autoload/game_database.gd:20-33,145` |
| F4 | **「打出」走 `respond`，「使用」走 `useCard`，两者互斥**；`respond` 的 `role` 只能取 `player`/`source`（`target_id` 恒为 `-1`），监听其他角色必须 `role="global"` | `scripts/core/match_controller.gd:5613-5615,5560`；`game_data/skills/zhishi.gd:19-21` |
| F5 | `respond` 载荷含 `card_uid` / `card_id` / `response_pattern` / `response_action`（`"use"`/`"play"`）/ `respond_event_id` | `scripts/core/match_controller.gd:5537,5558` |
| F6 | **响应牌无法在落地前被截走**：`_move_played_card_to_discard()` 在 `respond` 派发**之前**执行，且 `gain_card_to_hand_by_uid` 显式拒绝 `source_zone == "processing"` | `scripts/core/match_controller.gd:5551-5560,6949-6954` |
| F7 | 「你获得之」的通用端口是 `gain_card_to_hand_by_uid(receiver_id, card_uid, reason, allow_out_of_game) -> bool`，覆盖 `discard_pile` | `scripts/core/match_controller.gd:6941-6971` |
| F8 | 手牌上限永久加成端口：`add_hand_limit_bonus(player_id, amount, reason, allow_out_of_game) -> int`；有效上限 = `hp + hand_limit_bonus + mode_hand_limit_bonus`；随权威存档往返、无来源归属 | `scripts/core/match_controller.gd:4439-4447`；`scripts/data/player_state.gd:413-414,193,583` |
| F9 | 摸牌端口 `draw(player_id, count, announce, allow_out_of_game) -> void`，一次调用即批量；`drawEnd`/`drawAfter` 载荷 `{count, requested_count, card_uids, reason}` | `scripts/core/match_controller.gd:4335`；`scripts/core/draw_resolution_service.gd:187-195` |
| F10 | 雷电属性是小写字面量 `"thunder"`（全项目**无** `NATURE_*` 常量）；`damage(...)` 会先扣护盾再扣体力并进入伤害历史 | `scripts/core/match_controller.gd:4973,17935` |
| F11 | 护盾端口名是 `shield(target_id, amount, source_id, reason) -> int`（**不是** `gain_shield`） | `scripts/core/match_controller.gd:4352-4372` |
| F12 | 摸牌阶段时机实有 `phaseDrawBefore/Begin/Begin1/Begin2/End/After/Cancelled/Skipped`，载荷含 `turn_number`；`End`/`After` 的 `draw_count` 为最终已摸数、只读 | `scripts/core/rule_timing_catalog.gd:15`；`scripts/core/match_controller.gd:12069`；`scripts/core/phase_lifecycle_service.gd:124-128,159` |
| F13 | 获得类时机只有 `gainBefore/gainBegin/gainEnd/gainAfter`，**恒为一张一次**（`card_uids` 为单元素数组）且载荷**不含张数** | `scripts/core/rule_timing_catalog.gd:54-64`；`scripts/core/match_controller.gd:15910-15911` |
| F14 | 项目唯一的批次时机 `cardsDiscardedBatchAfter` 由显式 `_begin_discard_batch()`/`_end_discard_batch()` 作用域配合「栈空则自成隐式批次」实现，载荷 `{discard_batch_id, card_uids, source_player_id, reason, batch_size}` | `scripts/core/match_controller.gd:15795-15829,15837-15877` |
| F15 | 摸牌的每张获得走 `DrawResolutionService` 的独立序列与 `emit_sequence_timing`，**不经过** `_move_card_with_timings` | `scripts/core/draw_resolution_service.gd:172-219` |
| F16 | 时机总数由 `tests/rule_timing_test.gd` 按分类断言为 `[58,48,16,35,37,10,14,8,4,6]`（合计 236）；新增时机必须同步该断言 | `tests/rule_timing_test.gd:134`；`scripts/core/rule_timing_catalog.gd:53-64` |
| F17 | 「令目标弃置其手牌」的暗选候选端口是 `get_hand_candidates(viewer_id, target_id)`（他人手牌只发牌背、`card_data` 被抹除）；手牌+装备是 `get_hand_equipment_candidates`；手牌+装备+判定是 `get_player_zone_candidates` | `scripts/core/match_controller.gd:7888,7765,7770,6712` |
| F18 | 随机效果**必须**走权威随机端口 `pick_random_candidate_index(candidate_count, history_kind, history_data) -> int`，禁止自建随机源 | `scripts/core/match_controller.gd:7128`；范例 `game_data/skills/qihe.gd:77-83`、`haoxi.gd:93`、`zhuxv.gd:113-137` |
| F19 | 自移除技能的权威端口是 `remove_skill(player_id, skill_id, reason) -> bool`（`lose_skill` 不存在），会同时清掉 `acquired_skills`/`temporary_skills` 记录 | `scripts/core/match_controller.gd:10618` |
| F20 | `changeSkillsAfter` **不覆盖**技能增删，只在换将/复原武将牌/复原限定技三处派发 | `scripts/core/match_controller.gd:4584,4721,4757` |
| F21 | 跨回合私有记忆必须写 `PlayerState.character_form_state`（随存档往返、不随技能重装丢失），但**所有 AI 快照都能读到**；需要「其他角色不可知」时改用 `private_pile_placement` 这类更严条件的专用字段 | `scripts/data/player_state.gd:25,542,319`；`.trellis/spec/content/skill-authoring.md:70-71` |
| F22 | `request_card_choice` 在**已存在未决选择**时静默返回空数组；在时机回调里建请求前必须先查 `has_nested_settlement_barrier()` 并改走 `defer_settlement()` | `scripts/core/match_controller.gd:2958-2964`；范例 `game_data/skills/zhuijian.gd:126`、`mice.gd:71-74` |
| F23 | 多步主动技的既有范式是「单一 `continue_selection` + `context.kind` 分派 + 『出牌阶段限一次』用 `phaseUseBegin` 复位实例计数」 | `game_data/skills/linggan.gd:106-203`、`zhuxv.gd:63-65`、`chuanchong.gd:29-34` |
| F24 | 基础 AI **必须**与规则同文件维护；正式技能需覆盖 `append_play_phase_actions()` / 专属 `score_ai_choice()` 等钩子；改变牌数或体力的评分必须复用 `NonameAIEvaluator.score_resource_change()` 与公开资源常量 | `.trellis/spec/content/content-ai.md:8-16,104-123` |
| F25 | 可取消选择的「确认」分必须**严格大于 0**，否则 AI 返回 `confirmed=false`；多步链每一步都要给足保底确认分，否则 AI 会「发动→取消」空转 | `.trellis/spec/content/content-ai.md:30-34`；`game_data/skills/linggan.gd:55-63` |
| F26 | `gameStart` 的 `player_id/source_id/target_id` 全为 `-1`，订阅**必须** `role="global"`；它位于起始手牌与手气卡之后、第一轮之前 | `scripts/core/match_controller.gd:11172-11173`；`.trellis/spec/content/skill-authoring.md:73` |
| F27 | 手牌上限加成的既有用例是 `game_data/skills/jvkou.gd:75`；`gameStart` 摸牌的既有范例是 `game_data/skills/yanling.gd:59-80` | `game_data/skills/jvkou.gd:75`；`game_data/skills/yanling.gd:59-80` |
| F28 | 颜色只有两色：红（红桃/方块）与黑（黑桃/梅花），`CardInstance.get_color()` 返回 `"red"`/`"black"`；整批弃置的整批判定先例是【泛音】 | `game_data/skills/fanyin.gd:12-18,137-166`；`game_data/skills/kansha.gd:115-116` |

---

## 子任务地图

父/子结构不是依赖系统；若需顺序，写在子任务自己的 `prd.md` 里。

| 子任务 | 交付物 | 状态 |
|---|---|---|
| [`10-04-batch-gain-timing-mechanism`](../10-04-batch-gain-timing-mechanism/prd.md) | **批量获得时机机制**：与 `cardsDiscardedBatchAfter` 对称的 `cardsGainedBatchAfter` 时机、批量获得作用域端口、移牌管线与摸牌服务接入、时机目录登记、`tests/rule_timing_test.gd` 计数同步、专项测试、文档。**是砂金【风口】的前置**。 | 规划中 |
| [`10-04-danheng-yinyue-character-and-skills`](../10-04-danheng-yinyue-character-and-skills/prd.md) | **武将丹恒·饮月** + 锁定技【伏辰】 + 主动技【濯世】 + 配套 AI + 测试 + 文档。纯内容层，无新机制。 | 规划中 |
| [`10-04-shajin-character-and-skills`](../10-04-shajin-character-and-skills/prd.md) | **武将砂金** + 锁定技【筹码】 + 【盲注】 + 【风口】 + 配套 AI + 测试 + 文档。**依赖批量获得时机机制先行落地**。 | 规划中 |

> **顺序约束**：`10-04-batch-gain-timing-mechanism` 必须先完成并归档，`10-04-shajin-character-and-skills` 才能开始实现【风口】；砂金的另两个技能与丹恒·饮月的全部技能与该机制无依赖，可并行。

---

## 跨子任务验收标准

- [ ] 三个子任务全部归档后，`GameDatabase.validation_errors` 为空，可正常开局。
- [ ] 丹恒·饮月可在选将中出现：仙舟联盟、男、体力上限 4、技能顺序【伏辰】【濯世】。
- [ ] 砂金可在选将中出现：星际和平公司、男、体力上限 3、技能顺序【筹码】【盲注】【风口】。
- [ ] 五个技能的 `name` 与 `description` 与「来源需求原文」及「用户补充确认」的最终文本**逐字一致**（含全角标点与【】）。
- [ ] 【伏辰】只响应其他角色**打出**的【杀】，【杀】实体进入丹恒·饮月手牌；其他角色**使用**【杀】不触发。
- [ ] 【濯世】三段链完整：费用基本牌 → 暗选弃目标手牌 → 可选费用 → 暗选弃目标一张牌 → 可选费用 → 1 点雷电伤害；出牌阶段限一次，取消任一步骤不消耗次数、不产生效果。
- [ ] 【筹码】在 `gameStart` 令砂金摸 3 张牌，并使手牌上限永久 +3（`hand_limit_bonus == 3`）。
- [ ] 【盲注】在摸牌阶段开始可弃置至多 2 张（1 红 1 黑，来源为手牌+装备区）；该阶段结束时按颜色比对分别给出 1 点护盾与摸 2 张牌。
- [ ] 【风口】在一次性获得 ≥2 张牌时提供「弃置这些牌」选项并计入发动次数；出牌阶段发动后按历史发动次数重复获得随机手牌，随后失去【风口】。
- [ ] 新增核心时机后，`tests/rule_timing_test.gd` 的分类计数断言与文档同步更新且通过。
- [ ] `docs/内容制作指南.md`、`docs/游戏机制与玩法内容.md`、`docs/AI模块.md`、`docs/架构说明.md`（机制归属）、`README.md` 已同步。

---

## 全局范围外（本父任务不做）

- 不新增势力（仙舟联盟与星际和平公司均已存在）。
- 不为本次内容制作插画、阵亡语音、技能音效素材（缺失时静默跳过，属既有规范允许状态）。
- 不修改 `游戏机制关键词（AI禁读禁改）` 路径下的任何文件。
- 不重构既有的 `cardsDiscardedBatchAfter` 语义（新机制与它对称，不改它）。
- 不为【风口】单独引入「限定技」语义（用户明确要求「失去该技能」，实现为真实移除）。
