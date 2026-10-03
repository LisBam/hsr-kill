# 武将卡芙卡 + 技能【言灵】【游丝】· 设计

父任务：[`10-02-kafuka-new-mechanics`](../../../10-02-kafuka-new-mechanics/prd.md) ｜ PRD：[`prd.md`](./prd.md)

---

## 1. 落点总表

| 关注点 | 落点 | 备注 |
|---|---|---|
| 武将元数据 | `game_data/characters/kafuka.gd` | 星核猎手 / 女 / 体力上限 3 / 技能顺序【言灵】【游丝】 |
| 【言灵】规则 | `game_data/skills/yanling.gd` | 两段都无选择窗口 |
| 【言灵】配套 AI | `game_data/cards/yanling.gd::modify_ai_action_score()` | 随卡牌交付（同级子任务） |
| 【游丝】规则 | `game_data/skills/yousi.gd` | 两段都由时机驱动 |
| 【游丝】配套 AI | 同上 `score_ai_choice()` | 两段共用同一入口，按 `context.kind` 分流 |
| 被发动者的通用压力 | `game_data/effects/yousi_pressure.gd` | `PlayerEffect` 子类，效果 ID `yousi_pressure` |

技能不直接写 `GameState`：入堆走 `create_and_insert_card_into_draw_pile()`，置牌走 `place_hand_card_on_draw_pile_top()`，事实走 `set/get/clear_private_pile_placement()`，主演走 `set_starring_role()`。

---

## 2. 【言灵】两段

### 2.1 第一段 · `gameStart` 布牌

| 项 | 值 |
|---|---|
| 时机 | `gameStart`，`role = "global"` |
| 调用次数 | `INSERT_COUNT = 3` |
| 每次参数 | `("yanling", "", 0, MatchController.DRAW_PILE_POSITION_RANDOM)` |
| 位次取值域 | `1..当前牌堆张数 + 1`（均匀） |
| 牌面 | 定义自带梅花K |
| 随机历史 | 每次一条 `kind = "exclusive_card_insert"` |

`role` 必须是 `global`：`gameStart` 由 `_emit_rule_timing("gameStart", -1, -1, -1, {...})` 派发，事件的 `player_id` 恒为 `-1`，按持有者比对的 `player` 角色永远匹配不上。

### 2.2 第二段 · 延时锦囊触发

| 项 | 值 |
|---|---|
| 时机 | 整牌 `useCard`，`role = "global"` |
| 条件 | 定义 `type == "trick"` 且 `delayed == true` |
| 效果 | 先 `draw(持有者, 1)`，再 `set_starring_role(持有者)` |
| 失效 | 持有者死亡或离场 |

- 判定只读定义元数据，**不读牌名**，因此【乐不思蜀】【兵粮寸断】【闪电】【言灵】与未来新增的延时锦囊都自动纳入。
- 顺序固定：先摸牌再写主演。摸牌可能引发濒死等流程，而「成为主演」是本次触发的结果，不应被中途状态影响。

---

## 3. 【游丝】两段

### 3.1 第一段 · 其他角色回合开始

```text
phaseBefore(role=global)
  ├─ turn_player_id == owner_player_id → 直接返回（只服务其他角色）
  ├─ 持有者不存活 / 离场 / 手牌为空 → 不创建任何窗口
  └─ request_hand_card_pile_position("游丝", <原文提示>, true, {kind:"yousi_placement", turn_player_id, turn_number})
        ├─ confirmed=false → 零副作用返回
        └─ confirmed=true：
             ① place_hand_card_on_draw_pile_top(owner, card_uid, position)
             ② set_private_pile_placement(owner, card_uid, position, turn_player_id, turn_number)
             ③ install_player_effect(turn_player_id, "yousi_pressure")
             ④ announce_activation()
```

- 「其他角色不可知」由端口保证：不写日志、不产生公开表现事件、不派发 `lose*` 类时机、清除牌面知识残留。

### 3.2 第二段 · 同一个回合结束

```text
phaseAfter(role=global)
  ├─ 读取私有事实；turn_player_id / turn_number 与本次事件不匹配 → 直接返回（不误触发、不误清除）
  ├─ 无条件 clear_private_pile_placement(owner)
  └─ 该 card_uid 此刻仍在该回合角色手牌中？
        ├─ 否 → 结束（事实已清除）
        └─ 是 → get_private_hand_and_equipment_candidates(owner, turn_player_id)
                 → request_card_selection(min=max=1)
                 → take_selected_player_card(owner, turn_player_id, card_uid)
```

- 双重匹配是必需的：私有事实跨回合存活，只按「回合结束」触发会被无关角色的回合吃掉。
- 候选口径为**明示手牌 + 装备区**，不含判定区（原文「获得其一张牌」）。

---

## 4. 「其他AI」提示的落地方式

需求原文的「被发动游丝的 AI 会尽量把牌堆顶前两张用掉」**不能**字面实现：

1. 牌堆顶两张对非使用者是隐藏信息，读取它直接违反同一需求里的「其他角色不可知」；
2. `NonameAIEvaluator` 是**纯函数、不持有宿主引用**的快照评分器，快照里根本没有牌堆牌面（只发 `draw_pile_count`）。

因此实现为一条**公开信息门槛下的标量倾向**：

```text
yousi_pressure(3.0)  →  PlayerEffectService 求和  →  MatchController.get_ai_hand_pressure()
   →  AICoordinator.request_action(..., hand_pressure)
   →  BasicAIPolicy.set_hand_pressure() → _get_hand_pressure_bonus()
   →  只给消耗自己手牌的动作加分，一次决策后清零
```

门槛由 `NonameAIEvaluator.should_dump_hand_against_starring()` 提供，只用公开信息：主演存在（公开角标 `zhuyan`）、不是自己、且态度低于明确队友门槛。语义上等价于「知道『主演』这个公开身份后，倾向于本回合把牌用掉」，不伪装成知道牌面。

---

## 5. 与既有机制的关系

| 既有机制 | 本任务的使用方式 |
|---|---|
| 专属牌字段 + 入堆端口 | 【言灵】第一段直接调用；不新增核心分支 |
| 私有置牌事实 | 【游丝】两段共用；可见性条件 `reveal_private and viewer_id == player_id` |
| 位次询问协议 | 【游丝】第一段的唯一交互；「只有选了一张手牌才能选位次」由面板与权威端双重保证 |
| 「主演」 | 【言灵】第二段写入、卡牌【言灵】读取；不改动其唯一性与清理口径 |
| 回合操控 | 卡牌【言灵】判定成立时登记；技能层不参与 |
| `PlayerEffect` | 【游丝】的通用压力载体，随承载角色本回合结束自行移除 |
