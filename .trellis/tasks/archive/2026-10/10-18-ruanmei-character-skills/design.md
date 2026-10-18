# 技术设计 · 阮梅与【梅绽】【灵赋】【阮弦】

> 共享契约（技能拥有查询入口、全局限次存储位置、梅绽动态卖血估值的框架推导、文档同步清单）见父任务 `../10-18-ruanmei-and-skill-ownership-query/design.md`。
> 本文只写单技能的逐条结算设计、时序、AI 决策与测试计划。

---

## 1. 文件与静态参数

| 文件 | 稳定 ID | 关键元数据 |
|---|---|---|
| `game_data/characters/ruanmei.gd` | `ruanmei` | `display_name=阮梅`、`gender=female`、`faction=yinhexvezhe`、`max_hp=3`、`skills=[梅绽, 灵赋, 阮弦]` |
| `game_data/skills/meizhan.gd` | `meizhan` | `lock:true`、`trigger:["damageAfter"]`、`sell_blood_value:1.0`、无 `enable` |
| `game_data/skills/lingfu.gd` | `lingfu` | `trigger:"active"`、`enable:"phaseUse"`、`ui_enabled:true` |
| `game_data/skills/ruanxian.gd` | `ruanxian` | `trigger:"phaseEnd"`、`ui_enabled:false`（无主动按钮，只在结束阶段询问） |

武将文件模板与同势力同体力先例：`game_data/characters/aisida.gd`。

## 2. 【梅绽】（meizhan.gd）

### 2.1 玩家可见正文（逐字，含原文右引号）

```
锁定技，当你受到伤害后，所有拥有技能”梅绽”的角色各摸一张牌。
```

### 2.2 结算

```
subscribe_timing("damageAfter", _on_owner_damaged, "target")
```

| 步骤 | 内容 |
|---|---|
| 1 | 读 `event.data.hp_lost`；`<= 0`（护盾全额吸收 / 伤害被归零 / 被取消）直接返回，不触发 |
| 2 | 遍历 `host.state.players`，跳过 `not alive` 与 `out_of_game` |
| 3 | 对每名存活在场角色调用 `host.call("has_skill", player.player_id, "meizhan")` |
| 4 | 命中者调用 `host.call("draw", player.player_id, DRAW_COUNT)` |

- **按伤害事件结算一次**，不随 `hp_lost` 点数翻倍（原文是“受到伤害后”而非“每受到1点伤害后”，与【百折】的 `damagePointAfter` 形成对照）。
- 遍历顺序固定为 `host.state.players` 的座次顺序，保证摸牌日志顺序稳定、可回放。
- 不创建任何选择请求，因此无需 `has_nested_settlement_barrier()` 判断。
- 使用统一入口而非读武将固有技能列表：被【灵赋】授予“梅绽”的角色必须能触发，且被【留白】类效果剥夺后必须不再触发。

### 2.3 动态卖血估值

```gdscript
func modify_ai_incoming_card_effect(authoritative_snapshot, actor_id, target_id, definition,
        ai_profile, target_result, expected_damage_amount, current_score, evaluator) -> float
```

| 步骤 | 内容 |
|---|---|
| 1 | `ai_profile.damage != true` → 原样返回 `current_score`（非伤害牌不会造成伤害） |
| 2 | 遍历 `authoritative_snapshot.players`；跳过 `target_id` 本人（已由静态 `sell_blood_value = 1.0` 按态度符号计入）、跳过 `not alive` / `out_of_game` |
| 3 | 用 `SkillDefinition.snapshot_has_skill(player, "meizhan")` 判定持有 |
| 4 | `attitude = evaluator.get_attitude(snapshot, actor_id, player.player_id)`；`> 0` 计 `+1`、`< 0` 计 `−1`、`== 0` 不计 |
| 5 | `current_score + net_count * NonameAIEvaluator.CARD_RESOURCE_VALUE` |

符号正确性推导见父任务 `design.md` 第 3.3 节。`get_attitude` 而非 `get_real_attitude`：后者会泄露隐藏身份。

## 3. 【灵赋】（lingfu.gd）

### 3.1 玩家可见正文（逐字）

```
出牌阶段限一次，你可以重铸一张手牌（每种类别限一次），然后令一名角色获得技能“梅绽”。若其已拥有技能“梅绽”，则改为令其增加1点体力上限并回复1点体力，然后你失去此技能。
```

### 3.2 两个次数限制同时成立（原文解读，写入文档）

| 限制 | 作用域 | 重置时机 |
|---|---|---|
| “出牌阶段限一次” | 每个**出牌阶段**至多发动 1 次 | `phaseUseBegin` 时把 `_used_this_play_phase` 置回 `false`（额外出牌阶段同样重置） |
| “每种类别限一次”（注意：全局） | 整局游戏，`basic` / `trick` / `equipment` 各自至多被重铸 1 次 | **不重置** |

因此整局最多发动 3 次，分布在最多 3 个出牌阶段。这是唯一能同时满足两个限制的解释：若“出牌阶段限一次”是唯一限制，则“每种类别限一次”的全局约束永远不会被触达，原文的注意条款就没有意义。

### 3.3 常量

```gdscript
## 技能稳定 ID；授予与失去都按该 ID 判定。
const LINGFU_SKILL_ID: String = "lingfu"
## 被授予 / 被检查的目标技能稳定 ID。
const MEIZHAN_SKILL_ID: String = "meizhan"
## 本技能选择请求的业务键；continue_selection 按它分流。
const CHOICE_KIND: String = "lingfu_grant_target"
## 续结算业务键；重铸完成后按它恢复后续效果。
const SETTLEMENT_KIND: String = "lingfu_after_recast"
## 全局限次记录在 PlayerState.character_form_state 中的稳定键。
const USED_CATEGORIES_KEY: String = "lingfu_used_card_categories"
## 三种牌类别；与 CardDefinition 的 type 取值一一对应。
const CARD_CATEGORIES: Array[String] = ["basic", "trick", "equipment"]
## 分支二增加的体力上限点数。
const MAX_HP_GAIN: int = 1
## 分支二回复的体力点数。
const RECOVER_AMOUNT: int = 1
## 授予技能时的来源标识；remove_skill 不按它撤销（原文只要求阮梅失去自己的【灵赋】）。
const GRANT_SOURCE: String = "lingfu"
```

### 3.4 操作流时序（用户“操作方式要求”）

```
can_activate()            出牌阶段 + 本阶段未发动 + 有可用材料 + 有合法目标
      ↓
activate()                request_card_target_selection("灵赋", ..., candidates, target_ids, 1, 1, 1, 1, true, {kind: CHOICE_KIND})
      ↓  （人类：选一张牌 + 一名目标 → 确定；AI：同步返回）
continue_selection()      ① 复核目标合法 ② 复核材料仍是手牌且类别仍有全局额度
                          ③ host.recast_hand_card(owner, card_uid)   ← 先重铸
                          ④ 返回 false → 直接结束（不记账、不结算）
                          ⑤ 记账：全局类别 + _used_this_play_phase = true + announce_activation
                          ⑥ defer_settlement({kind: SETTLEMENT_KIND, target_id})
      ↓  （管线先排空 _rule_continuations 中的 recast_draw，摸牌完成）
continue_settlement()     ⑦ 复核目标仍存活在场
                          ⑧ 分支一 / 分支二
```

**为什么 ⑥ 必须存在**：`recast_hand_card()` 内部的摸牌是控制器登记的 `_rule_continuations`（`match_controller.gd:14619` 的 `recast_draw`）。结算管线的优先级是 `_rule_continuations` **先于** `_deferred_skill_settlements`（`match_controller.gd:13195` 与 `13213`）。因此先调用重铸、再 `defer_settlement`，就能严格保证「重铸（含补摸）全部完成 → 后续效果开始」。若省略 ⑥ 而同步执行分支，就会出现“先加体力上限、后摸牌”的顺序错误，违反用户明确的操作顺序要求。

**兜底**：若 `defer_settlement()` 返回 `false`（技能代次失效等），回退为在 `continue_selection` 内同步执行分支，保证效果不丢失。

### 3.5 分支结算

**分支一（目标没有“梅绽”）**

```gdscript
host.call("grant_acquired_skill", target_id, MEIZHAN_SKILL_ID, 0, 0, GRANT_SOURCE)
```

- 无次数限制、无回合限制：原文只说“获得技能”，是永久获得。
- `grant_acquired_skill` 自身拒绝重复授予；因此进入分支一前用 `has_skill` 判定即可，不必再处理返回值失败。
- 先例：【升变】授予【奇袭】、`qixi.gd` 的“视为拥有技能”走同一端口。

**分支二（目标已拥有“梅绽”）**

```gdscript
host.call("change_max_hp", target_id, MAX_HP_GAIN, owner_player_id, LINGFU_SKILL_ID)
host.call("recover", owner_player_id, target_id, RECOVER_AMOUNT, LINGFU_SKILL_ID)
host.call("remove_skill", owner_player_id, LINGFU_SKILL_ID, LINGFU_SKILL_ID)
```

- 顺序严格按原文：先增加体力上限、再回复体力、**然后**阮梅失去【灵赋】。
- `change_max_hp` 的 `delta > 0` 不会触发濒死；`recover` 不超过上限。
- `remove_skill` 是项目内「失去技能」的唯一通用端口；它会连同实例与获得/临时记录一起清理，因此分支二后 `has_skill(阮梅, "lingfu")` 必须为 `false`（有用例锁定）。
- 失去【灵赋】后全局限次记录仍留在 `character_form_state` 中，重新获得技能也不会复活额度。

### 3.6 目标范围

`_get_target_ids()` = `host.state.players` 中 `alive and not out_of_game` 的全部角色，**包含阮梅自己**。

依据：项目对“一名角色”的既有口径包含自己（【升变】注释“升变允许选择自己”）。阮梅自己永远命中分支二（她固有拥有“梅绽”）。

### 3.7 材料候选

`_get_recast_candidates()`：

1. `host.call("get_hand_candidates", owner_player_id, owner_player_id)`
2. 对每个候选读 `card_data.definition_id` → `GameDatabase.get_card(...).type`，得到 `basic`/`trick`/`equipment`
3. 只保留 `type` 属于 `CARD_CATEGORIES` 且**该类别尚未写入全局已用集合**的候选
4. 保持原手牌顺序

`can_activate()` 额外要求 `_get_recast_candidates()` 与 `_get_target_ids()` 均非空——没有材料或没有目标时不点亮按钮、不创建空窗口。

## 4. 【阮弦】（ruanxian.gd）

### 4.1 玩家可见正文（逐字）

```
结束阶段，你可以重铸一张锦囊牌（每种花色限一次），然后令所有拥有技能“梅绽”的其他角色各摸一张牌。
```

### 4.2 常量

```gdscript
const RUANXIAN_SKILL_ID: String = "ruanxian"
const MEIZHAN_SKILL_ID: String = "meizhan"
const CHOICE_KIND: String = "ruanxian_recast_trick"
const SETTLEMENT_KIND: String = "ruanxian_after_recast"
const REBUILD_KIND: String = "ruanxian_rebuild_entry"
const USED_SUITS_KEY: String = "ruanxian_used_suits"
## 四种花色；与 CardInstance.is_valid_suit 的取值一一对应。
const CARD_SUITS: Array[String] = ["spade", "heart", "club", "diamond"]
## 每名其他梅绽持有者获得的摸牌数。
const DRAW_COUNT: int = 1
```

### 4.3 结算时序

```
subscribe_timing("phaseEnd", _on_owner_phase_end, "player")
      ↓
_on_owner_phase_end()     ① 复核：持有者存活在场 + 有可用锦囊候选 + 至少1名“其他”梅绽持有者
                          ② host.has_nested_settlement_barrier() 为真
                             → defer_settlement({kind: REBUILD_KIND}) 并返回（重建入口）
                          ③ 否则 request_card_selection("阮弦", ..., candidates, 1, 1, true, {kind: CHOICE_KIND})
      ↓
continue_selection()      ④ 复核材料仍是手牌且花色仍有全局额度
                          ⑤ host.recast_hand_card(...)   ← 先重铸
                          ⑥ 失败 → 直接结束
                          ⑦ 记账：全局花色 + announce_activation
                          ⑧ defer_settlement({kind: SETTLEMENT_KIND})
      ↓
continue_settlement()     ⑨ REBUILD_KIND → 重跑 ①③；SETTLEMENT_KIND → 兑现摸牌
```

**为什么 ② 需要屏障判断**：`phaseEnd` 可能在外层技能效果内部被同步派发（`内容制作指南.md:2315-2321`）。此时 `request_card_selection()` 会被控制器**静默丢弃**（`request_card_choice()` 在已有待响应选择时直接返回空值）。因此必须按规范两段式：先复核条件，再判屏障，屏障为真时登记重建步骤。

**为什么结束阶段的询问不会吞掉回合推进**：`内容制作指南.md:2323` 明确——结束阶段触发技能若创建选择，控制器会暂停回合尾部，待该技能产生的全部连续选择完成后再派发 `phaseAfter` 并推进回合。因此本技能不需要自行处理回合推进。

### 4.4 摸牌范围

`_get_other_meizhan_holder_ids()` = `host.state.players` 中满足全部条件的角色：

- `player.player_id != owner_player_id`（原文“其他角色”固定表示排除技能持有者，见 `内容制作指南.md:2331`）
- `alive and not out_of_game`
- `host.call("has_skill", player.player_id, "meizhan")`

因此阮梅自己**不会**因【阮弦】摸牌，即使她固有拥有“梅绽”。这与【梅绽】明确包含自己形成对照，两者都必须有用例锁定。

### 4.5 材料候选

`_get_recast_candidates()`：

1. `get_hand_candidates(owner, owner)`
2. 只保留 `GameDatabase.get_card(card_data.definition_id).type == "trick"`
3. 只保留 `str(card_data.get("suit", ""))` 尚未写入全局已用花色的候选

本人手牌对本人可见，按花色过滤不违反隐藏信息规则（与【天坠】按 `type == "trick"` 过滤同类）。

## 5. 全局限次的读写

两个技能共用同一套读写模式（键名与字段见父任务 `design.md` 第 2 节）：

```gdscript
## 返回本技能在 character_form_state 中记录的已用集合；类型异常时按空集合处理。
func _get_used_values(key: String) -> Array[String]
## 把一个取值追加进已用集合并写回 character_form_state；已存在时不重复写入。
func _mark_used(key: String, value: String) -> void
```

- 读取入口：`get_owner_skill_player().get_state().character_form_state`
- 写入时机：**只在 `recast_hand_card()` 返回 `true` 之后**
- 类型收敛：字段不是 `Array` 时按空集合处理，不因旧存档崩溃

## 6. AI 设计

### 6.1 通用约束（三个技能共同遵守）

- AI 钩子（`score_ai_action` / `score_ai_choice`）**没有 `host`**，只能读 `authoritative_snapshot` 与 `evaluator` 的公开只读接口。
- 技能拥有判定一律用 `SkillDefinition.snapshot_has_skill()`（父任务交付的统一入口）。
- 数值尺度统一用 `NonameAIEvaluator.CARD_RESOURCE_VALUE`；禁止字面量、禁止技能 ID 白名单。
- **动作层与选择层必须同源**：`score_ai_action()` 用来判断“值不值得发动”的费用估算，必须与 `score_ai_choice()` 里实际扣的费用来自同一个函数，否则会出现“提议发动 → 立刻取消”的死循环（【天坠】的既有教训）。

### 6.2 【灵赋】AI

**用户给定的三级优先（必须实现）**

| 优先级 | 条件 | 目标 |
|---|---|---|
| 1 | 存在**没有“梅绽”的队友** | 从中选择收益最高者（分支一：授予技能） |
| 2 | 队友都已拥有“梅绽” | 优先**有卖血技能的队友**（分支二） |
| 3 | 没有卖血技能队友，**或有多个**卖血技能队友 | 对**体力值最低的**使用 |

“队友”判定：`evaluator.get_attitude(snapshot, owner_player_id, target_id) > 0`（不用 `get_real_attitude`，避免未卜先知）。
“有卖血技能”判定：`evaluator.get_snapshot_sell_blood_value(target_snapshot) > 0.0`（复用既有权威元数据，自动覆盖【百折】与本次新增的【梅绽】）。

**必须补全的通用逻辑（提示未覆盖）**

1. **敌方 / 中立目标的负收益惩罚**：对态度 `<= 0` 的目标发动分支一等于白送技能、发动分支二等于资敌（+1 体力上限 +1 体力），必须给严格负分；只有“队友全部已拥有且自身处于必输局面”这类极端情形才可能被其它正收益盖过，本技能不做特例。
2. **费用估算**：重铸一张牌的机会成本 = 该牌保留价值 − 未知补牌的期望价值。复用 `NonameAIEvaluator.CARD_RESOURCE_VALUE` 与既有牌保留价值口径（参考 `lianxi.gd` 的 `AI_RECAST_QUALITY_COST` 写法：`CARD_RESOURCE_VALUE * 0.35`）。**动作层与选择层使用同一个 `_get_recast_cost_value()`**。
3. **材料选取**：`score_ai_choice()` 中按保留价值**从低到高**评估候选，优先重铸价值最低的牌；类别额度已用的候选根本不会出现在候选数组里，AI 无需再判。
4. **取消基线**：取消恒为 `0.0` 分，且必须始终可选（`allow_cancel = true`）。
5. **自己作为目标**：分支二对自己是“+1 体力上限 +1 体力 但失去【灵赋】”。自身失去【灵赋】的代价用 `SKILL_LOSS_COST`（复用 `liubai.gd` 的口径 `1.0`）扣减，使 AI 不会为了一点体力上限无脑自弃技能。

**评分骨架**

```
score_ai_action(...) =
      最佳目标毛收益（按 6.2 三级优先选出）
    − _get_recast_cost_value(...)        # 与选择层同源
```

### 6.3 【阮弦】AI

```
score_ai_action(...) = 受益队友数 × 未知牌质价值 − _get_recast_cost_value(...)
```

- 受益者 = `alive and not out_of_game`、非自己、`snapshot_has_skill(P, "meizhan")`、且态度 `> 0` 的队友；敌方持有者摸牌是**负**收益，必须减去。
- 只有 `> 0.0` 才确认发动；`<= 0.0` 一律取消。
- 结束阶段是“免费时机”，但仍需评估材料机会成本，不能无脑发动。

### 6.4 【梅绽】AI

见 2.3。此外 `sell_blood_value = 1.0` 会让既有的“对友方【杀】是否放弃【闪】”分支自动把梅绽持有者视为卖血角色，无需改动该分支。

## 7. 测试计划

| 用例 | 断言 |
|---|---|
| `skill_ownership` | `has_skill` 与 `snapshot_has_skill` 在固有 / 模式 / 临时 / 局内获得四类来源上一致；`installed_skill_ids` 裁剪生效；`yaoli` 旧缺陷已修 |
| `meizhan_multi_holder_draw` | 授予第二人“梅绽”后，任一持有者受伤 → 两名持有者各摸1张；护盾全额吸收（`hp_lost == 0`）不触发 |
| `meizhan_dynamic_sell_blood` | 目标为敌 / 为友两个分支的修正分符号都正确；只对 `ai_profile.damage == true` 生效；【百折】估值仍为 `1.0` |
| `lingfu_recast_before_effect` | 确定后**先**完成重铸补摸、**后**才授予技能（顺序断言） |
| `lingfu_grant_branch` | 目标无“梅绽” → 获得技能；随后其受伤能触发【梅绽】 |
| `lingfu_upgrade_branch` | 目标已有“梅绽” → 体力上限 +1、体力 +1，且阮梅失去【灵赋】（`has_skill(阮梅,"lingfu") == false`） |
| `lingfu_global_quota` | 同类别第二次发动被拒；失去【灵赋】后重新授予，已用类别仍不复活；存档往返后同样不复活 |
| `lingfu_self_target` | 阮梅可选择自己，且必定进入分支二 |
| `lingfu_phase_limit` | 同一出牌阶段第二次发动被拒；额外出牌阶段恢复一次额度 |
| `ruanxian_other_holders_only` | 只有**其他**梅绽持有者摸牌，阮梅自己不摸 |
| `ruanxian_suit_quota` | 同一花色第二次被拒；四种花色各自独立计数；跨失去技能不复活 |
| `ruanxian_no_holder_no_request` | 场上没有其他梅绽持有者时不创建任何选择请求 |
| `ruanxian_nested_barrier` | 结束阶段存在嵌套屏障时，通过 `defer_settlement` 重建入口而不是静默丢弃 |
| `ruanmei_metadata` | 武将 `faction == "yinhexvezhe"`、`max_hp == 3`、`gender == "female"`、技能顺序为 梅绽→灵赋→阮弦 |
| `ruanmei_description_verbatim` | 三个 `description` 与原文主句逐字相等（含【梅绽】的两个右引号） |

测试文件放在 `tests/`，沿用既有 `tests/*_mechanics_test.gd` 的写法（直接实例化控制器、构造快照、断言数值）。
