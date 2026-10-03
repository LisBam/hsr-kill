# 武将卡芙卡 + 技能【言灵】【游丝】

父任务：[`10-02-kafuka-new-mechanics`](../../../10-02-kafuka-new-mechanics/prd.md)

本任务交付**武将卡芙卡**与她的两张技能（含配套 AI），是父任务「卡芙卡」需求链的最后一环。卡牌【言灵】已由同级子任务 `10-02-yanling-card` 交付。

---

## 来源需求原文（不可变 · 逐字保留）

> 依据 [`项目专属AGENTS.md`](../../../../项目专属AGENTS.md) 铁律：以下描述原文的字段、数值、文字表述、标点符号与语句顺序**一律不得改动**。

```
卡芙卡kafuka 星核猎手 女 体力值3
```

```
言灵yanling
锁定技，游戏开始时，你往牌堆中随机加入三张【言灵】。当一名角色使用延时锦囊牌时，你摸一张牌并成为“主演”。
```

配套 AI 与操作逻辑原文：

```
（AI逻辑：自己或队友判定区有乐不思蜀/兵粮寸断时，优先往牌堆顶第一张牌放红桃/梅花来使判定失效。敌人的回合，可以将价值较低的手牌随机放第一或第二张。
其他AI：被发动“游丝”的AI，若主演不为队友，则本回合内，会尽可能地将牌堆顶的前两张牌使用打出或弃置等一切方法使其不在手牌中，避免被主演获得手牌。）
```

```
（操作逻辑：询问时显示三个按钮，“牌堆顶第一张”“牌堆顶第二张”“取消”，只有选择了一张手牌才能选前两个选项。回合结束时如果触发二段效果，则效果是观看目标角色的手牌，但是选牌界面是有手牌和他装备区，因为描述是“获得其一张牌”，因此是在他明示的手牌以及装备区中选择并获得其中一张。）
```

```
游丝yousi
其他角色的回合开始时，你可以将一张手牌置于牌堆顶的第一张或第二张（其他角色不可知）。若如此做，本回合结束时，若其手牌中有此牌，你观看并获得其一张牌。
```

---

## In Scope

1. `game_data/characters/kafuka.gd`：星核猎手、女、体力上限 `3`、技能顺序【言灵】【游丝】。
2. `game_data/skills/yanling.gd`：锁定技，`gameStart` 逐张随机加入 3 张【言灵】；任意角色使用延时锦囊牌时摸 1 张并成为「主演」。
3. `game_data/skills/yousi.gd`：非锁定技，其他角色回合开始时把一张手牌置于牌堆顶第一/第二张（其他角色不可知）；该回合结束时若那张牌仍在该角色手牌中则观看并获得其一张牌。
4. 配套 AI：卡牌【言灵】的硬门槛（已随卡牌交付）、【游丝】两段评分、以及被发动者的**通用出牌压力**通道。
5. 同步文档与专项回归测试。

## Out of Scope

- 卡牌【言灵】本体（已由 `10-02-yanling-card` 交付）。
- 专属牌字段、运行时入堆端口、私有置牌事实、位次询问协议、回合操控机制、「主演」语义（均为已归档的前置机制，本任务只调用）。
- 新增势力、卡牌插画与音效素材。
- 让 AI 读取「牌堆顶前两张」真实牌面（与「其他角色不可知」直接冲突，见设计 §4）。

---

## Requirements

- **R1 武将元数据**：`id = "kafuka"`、`display_name = "卡芙卡"`、`faction = "xinghelieshou"`、`gender = "female"`、`max_hp = 3`；技能引用顺序为【言灵】→【游丝】。
- **R2 【言灵】静态**：`lock = true`、`ui_enabled = false`、`trigger = "gameStart"`（主要时机名，`trigger` 本身不订阅事件）。
- **R3 【言灵】第一段**：订阅 `gameStart`（`role = "global"`，该时机 `player_id` 恒为 `-1`）；逐张调用 `create_and_insert_card_into_draw_pile("yanling", "", 0, DRAW_PILE_POSITION_RANDOM)` **共 3 次**，不指定牌面、每次独立抽位次。
- **R4 【言灵】第二段**：订阅整牌 `useCard`（`role = "global"`）；判定口径为 `type == "trick"` 且 `delayed == true`（不写牌名白名单）；成立时先 `draw(持有者, 1)` 再 `set_starring_role(持有者)`；持有者死亡或离场时不触发。
- **R5 【游丝】静态**：`lock = false`、`ui_enabled = false`、`trigger = "phaseBefore"`（主要时机名，`trigger` 本身不订阅事件）。
- **R6 【游丝】第一段**：订阅 `phaseBefore`（`role = "global"`，排除自己的回合）；持有者存活、在场、手牌非空时用 `request_hand_card_pile_position()` 创建 `card_position` 询问；确认后依次 `place_hand_card_on_draw_pile_top()` → `set_private_pile_placement()` → 给本回合角色挂 `yousi_pressure` → `announce_activation()`；取消与非法提交零副作用。
- **R7 【游丝】第二段**：订阅 `phaseAfter`（`role = "global"`）；按 `turn_player_id + turn_number` 双重匹配；进入时**无条件**清除私有事实；只有该牌仍在回合角色手牌中时才用 `get_private_hand_and_equipment_candidates()` 建窗并 `take_selected_player_card()` 取 1 张。
- **R8 配套 AI · 【游丝】置牌段**：救援分支（队友判定区第一张是【乐不思蜀】需红桃 / 【兵粮寸断】需梅花，且必须放在牌堆顶第一张）得 `8.0`；常规分支按 `3.0 / (1 + 手牌价值 × 1.0)`；非法组合 `-100.0`；两个位次在常规分支同分。
- **R9 配套 AI · 【游丝】获得段**：确认得 `20.0`，取消 `0.0`。
- **R10 配套 AI · 通用出牌压力**：`PlayerEffect.get_ai_hand_pressure()` 基类默认 `0.0`；`game_data/effects/yousi_pressure.gd` 返回 `3.0`；经 `PlayerEffectService` → `MatchController.get_ai_hand_pressure()` → `AICoordinator.request_action(..., hand_pressure)` → `BasicAIPolicy.set_hand_pressure()` → `_get_hand_pressure_bonus()`，只给消耗自己手牌的动作加分、一次决策后清零；仅在主演存在、不是自己、且态度低于队友门槛时由 `NonameAIEvaluator.should_dump_hand_against_starring()` 放行。
- **R11 文本逐字**：两条技能 `name` 与 `description` 必须与原文逐字一致。
- **R12 文档同步**：`docs/内容制作指南.md`、`docs/游戏机制与玩法内容.md`、`docs/AI模块.md`、`docs/卡牌系统.md`、`README.md`、`README.md` 测试入口、`.trellis/spec/content/` 三条规范、`临时反馈文档.md`。
- **R13 专项测试**：`tests/kafuka_mechanics_test.gd/.tscn`，自带看门狗与阶段标记。

---

## Acceptance Criteria

- [x] AC1 卡芙卡出现在武将池：星核猎手、女、体力上限 `3`、技能顺序【言灵】【游丝】。（R1）
- [x] AC2 两条技能正文与原文逐字一致（含全角引号 `“主演”`、【】与括号）。（R11）
- [x] AC3 `gameStart` 后摸牌堆恰好增加 `3` 张【言灵】，三个 UID 互不相同，随机历史恰好 3 条 `exclusive_card_insert`。（R3）
- [x] AC4 任意角色使用延时锦囊牌时卡芙卡摸 `1` 张并成为「主演」；普通锦囊、基本牌与装备牌都不触发；卡芙卡阵亡后不再摸牌也不再成为主演。（R4）
- [x] AC5 其他角色回合开始时出现三选项询问，候选只含卡芙卡自己的手牌；取消与非法提交不移动任何牌、不写任何事实。（R6）
- [x] AC6 确认后该牌离开卡芙卡手牌进入牌堆，私有事实写入 `card_uid` / `position` / `turn_player_id` / `turn_number`，且对任何观察者的**普通快照**都不可见；AI 快照与权威公开观察快照的可见性契约由已归档的 `10-02-exclusive-card-and-private-placement` 专项用例覆盖。（R6）
- [x] AC7 本回合结束时按双重匹配检查：那张牌仍在回合角色手牌中 → 开启观看并获得窗口（候选含明示手牌与装备区、不含判定区）；不在 → 不开启；两种情况都清除私有事实；无关角色的回合结束不触发。（R7）
- [x] AC8 【游丝】置牌段的救援分支、常规分支与非法组合分数符合 R8，两个位次同分。（R8）
- [x] AC9 被发动者的通用压力在主演为敌人时生效、主演是队友或没有主演时不生效；一次决策后自动清零；默认 `0.0` 时既有行为逐字不变。（R10）
- [x] AC10 `GameDatabase.validation_errors` 为空，`tests/smoke_test.tscn` 通过（技能定义 100 → 102、武将定义 47 → 48）。（R13）
- [x] AC11 文档与规范已同步。（R12）

---

## 关键决策

| ID | 决策 | 采用值 | 理由 |
|---|---|---|---|
| K1 | 延时锦囊的识别口径 | `type == "trick"` 且 `delayed == true` | 原文是类别而非牌名；写牌名白名单会让未来新增的延时锦囊漏触发，也违反内容自包含 |
| K2 | 第一段牌面 | 不指定，用定义自带的梅花K | 专属牌必须有确定牌面，「判定为梅花」才是可设计的条件 |
| K3 | 位次随机性 | 端口传 `DRAW_PILE_POSITION_RANDOM`，由权威随机源抽取并记账 | 原文「随机加入」；存档与回放必须复现 |
| K4 | 【游丝】的私有记忆承载位 | 专用字段 `PlayerState.private_pile_placement` | 复用 `character_form_state` 会被全部 AI 快照读到，违反「其他角色不可知」 |
| K5 | 【游丝】常规分支的位次 | 两个位次同分 | AI 评分必须确定（否则回放不可复现），随机性交给既有枚举顺序 |
| K6 | 「其他AI」提示的实现 | 与快照无关的标量压力 + 公开主演门槛 | 真实牌堆顶两张对非使用者不可知，AI 评估器又是纯快照函数；标量表达真实可用的信息 |
| K7 | 获得段的候选 | 目标的明示手牌 + 装备区，不含判定区 | 原文是「获得其一张牌」，判定区的牌不属于其拥有的牌 |
| K8 | 技能是否提供主动按钮 | 都是被动技，`ui_enabled = false` | 两段都在时机上自动完成，提供按钮只会产生「发动→取消」空转 |

---

## Risks

| # | 风险 | 缓解 |
|---|---|---|
| RK1 | `gameStart` 订阅写成 `role="player"` 而静默收不到 | AC3；`gameStart` 的 `player_id` 恒为 `-1`，已写入技能规范 |
| RK2 | 【游丝】第二段做了「过期也开启窗口」或「条件不成立就保留事实」 | AC7 两个方向都断言，并要求无条件清除 |
| RK3 | 私有置牌事实被日志或表现事件泄露 | AC6 用全量公开快照扫描断言 |
| RK4 | 压力通道影响既有 AI | AC9 断言默认值下的中性，且基类/参数/初值三处默认都是 `0.0` |
| RK5 | 固定种子回归受武将池增加影响而换人 | 已修 `tests/conquest_coop_test.gd` 的座位敏感点（机缘解析期间结算真人窗口），见实施记录 |
| RK6 | 测试挂起而无输出 | 专项测试自带 `SceneTreeTimer` 看门狗与阶段标记，卡住时非零退出 |
