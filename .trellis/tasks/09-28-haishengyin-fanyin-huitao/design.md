# 技术设计：海瑟音（泛音 · 回涛）

> 承接父任务 `.trellis/tasks/09-28-three-new-characters/design.md`。本文件只写本批特有设计。
> 需求与验收见同目录 `prd.md`。

---

## 一、技能形态判定

### 【泛音】= 4 节轮回技 + 半锁定技（双段单技能）

原文：`轮回技，出牌阶段，你可弃置一张①黑桃②红桃③梅花④方块牌。锁定技，当你弃置牌时，若这些牌中有黑色牌，你令一名角色弃置一张手牌；若这些牌中有红色牌，你摸一张牌。`

**关键理解**：主动段（轮回技部分）**本身只做一件事——弃置一张指定花色的牌**，没有任何附加效果。真正的收益来自后半段的锁定技：弃置动作触发黑/红效果。因此「轮回节推进」与「锁定技收益」是**同一动作的两面**：

| 轮回节 | 费用（弃置） | 触发色 | 锁定技效果 |
|---|---|---|---|
| ① | 黑桃 | 黑 | 令一名角色弃置一张手牌 |
| ② | 红桃 | 红 | 自己摸一张牌 |
| ③ | 梅花 | 黑 | 令一名角色弃置一张手牌 |
| ④ | 方块 | 红 | 自己摸一张牌 |

黑红天然交替，四节走完恰好形成两轮「削对手 / 补自己」的节奏。

**元数据**（依据 `game_data/skill_definition.gd:66-94` 的推导规则）：

```gdscript
super({
    "id":"fanyin",
    "name":"泛音",
    "trigger":"active/cardsDiscardedBatchAfter",
    "enable":"phaseUse",
    "ui_enabled":true,
    # 描述中“锁定技”位于中段，显式标注前后段规则边界；
    # 核心层据此在“非锁定技失效”时只保留后段（skill_definition.gd:298）。
    "half_locked":true,
    "reincarnation":true,
    "reincarnation_section_count":4,
    "reincarnation_has_explicit_sections":true,
    "reincarnation_each_section_once_per_play_phase":true,
    "description":"<R0 原文逐字>",
})
```

**为什么 `half_locked` 而非 `lock`**：`lock` 为真会让整个技能（含主动轮回段）变成不创建发动询问的强制效果，与「你可弃置」矛盾。`half_locked` 正是为「非锁定前段 + 锁定后段」设计的，先例 `baizhe.gd:47`、`zhidong.gd:50`，且 `can_use_effect(locked_segment)`（`SD:293-298`）保证「非锁定技失效」时后段仍生效。

**节序号与花色映射**：`①..④` 对应黑桃/红桃/梅花/方块，实现为顶部常量数组：

```gdscript
## 四个轮回节依次要求弃置的花色；索引即 section_index（0 基），与描述中的①②③④一一对应。
const SECTION_SUITS: Array[String] = ["spade", "heart", "club", "diamond"]
```

### 【回涛】= 非锁定观察型触发技

原文：`当一名角色的轮回技进入下一个轮回时，若该轮回技的轮回节数不小于3，你可令其摸一张牌。`

- 观察**任意角色**的轮回技推进 → `role="global"`。
- 门槛 `section_count >= 3` 提取常量，**读 `section_count` 而非 `has_explicit_sections`**。
- 效果对象 = 该轮回技的持有者（`event.player_id`），而非海瑟音自己。

---

## 二、泛音的执行流程

### 主动段（轮回节推进）

沿用 `kansha.gd` 的四节模板：

1. `can_activate()` 判定：`can_activate_reincarnation()` 为真 + 当前是本技能持有者的出牌阶段 + 手牌或装备区存在**本节对应花色**的牌。
2. `activate()`：
   - 直接动作（AI/网络）携带 `card_uids` → 校验花色后 `_execute_section()`。
   - 否则 `request_card_selection("【泛音】请弃置一张%s牌" % 花色名, 候选, 1, 1, true, {"kind":"fanyin_discard_suit", "section_index":当前节})`。
3. `continue_selection()`：`kind == "fanyin_discard_suit"` 时校验 `response.confirmed` 与张数，通过后 `_execute_section()`；取消即返回（`begin_reincarnation_activation()` 尚未调用，无需回滚）。
4. `_execute_section(card_uids)`：
   - `begin_reincarnation_activation()` → `host.call("discard_selected_hand_equipment", owner_player_id, card_uids)` → `complete_reincarnation_activation()` → `announce_activation({...})`。
   - **顺序要点**：弃置触发本技能的锁定后段（走批次事件），因此必须在 `complete_reincarnation_activation()` **之前**完成弃置，否则批次事件里的节状态与轮次状态不一致。

### 锁定后段（弃置批次判定）

```gdscript
func install() -> void:
    # locked_segment=true：半锁定技后段在“非锁定技失效”时仍然生效。
    subscribe_timing("cardsDiscardedBatchAfter", _on_cards_discarded_batch, "player", 0, false, false, Callable(), true)
```

`_on_cards_discarded_batch(event)`：

1. `event.player_id != owner_player_id` → 返回（只关心「当你弃置牌时」）。
2. 从 `event.data["card_uids"]` 取整批牌，回查花色（牌可能已在弃牌堆，按 `uid` 在 `state.discard_pile` 中查找，参照 `dieying.gd:40-51`、`anke.gd:69-76`）。
3. 判色：`spade`/`club` 为黑，`heart`/`diamond` 为红。
4. **先黑后红**（R0 的代码参考明确要求）：
   - 有黑 → 令一名角色弃置一张手牌：候选为「有手牌的其他角色（含自己？）」→ **需要按原文「一名角色」取全场有手牌角色（含自己）**，走 `request_target_selection`，`kind="fanyin_black_target"`；选定后由**目标本人**随机弃一张？不——原文是「令一名角色弃置一张手牌」，无名杀惯例为**由目标自己选择弃置**，故走 `request_card_selection_for_player(target_id, ...)`，`kind="fanyin_black_discard"`。
   - 有红 → 自己摸一张牌（`host.call("draw_cards", owner_player_id, 1)` 或既有摸牌端口，实现时以 `GameDatabase`/MC 现有公开端口为准）。
5. 两个效果都需异步选择 → 黑色效果完成后才能执行红色效果，因此用**两段 `continue_selection` 串行推进**，跨段只传稳定字段（`batch_card_uids`）。

### 空节与费用

- 若某一节对应花色的牌在手牌与装备区都不存在，`can_activate()` 返回 false —— **这与指南 `:3881-3896` 的「空节必须推进」不冲突**：该条针对「客观上无合法目标/已耗尽」的情形，而「费用牌不足」不在其列举范围内，`kansha.gd` 已确立同款先例（无红/黑牌时返回 false）。

---

## 三、回涛的执行流程

```gdscript
func install() -> void:
    # role=global：需要观察任意角色的轮回技推进，而非只观察自己。
    subscribe_timing("reincarnationStart", _on_reincarnation_start, "global")
```

`_on_reincarnation_start(event)`：

1. `event.data["section_count"] < MIN_SECTION_COUNT_FOR_HUITAO` → 返回。
2. `int(event.data["round_count"]) < 2` → 返回（`reincarnationStart` 在 `round_count += 1` **之后**派发，因此首轮进入不会走到这里；该判定用于排除 `reset_skill` 等重新派发的情形）。
3. 轮回技持有者 = `event.player_id`；海瑟音若死亡/离场则不发（由基类 `_can_receive_timing_event` 自动拦截）。
4. 询问是否发动（非锁定技，「你可」）：确认后 `host.call("draw_cards", holder_id, 1)` 并 `announce_activation({...})`。

---

## 四、AI 设计

| 技能 | 钩子 | 策略 |
|---|---|---|
| 泛音 | `append_play_phase_actions` | 枚举四种花色的可弃置牌，为该花色生成动作（`payload.card_uids` 取该花色中 AI 估值最低的一张） |
| 泛音 | `score_ai_action` | 基础分 + 黑色效果收益（令敌弃牌）/ 红色效果收益（摸牌）；弃牌机会成本扣减（参照 `kansha.gd` 的 `get_owned_card_value_by_uid(...) * 0.45` 范式） |
| 泛音 | `score_ai_choice` | 黑色目标：敌方优先、无手牌者排除；**黑色弃牌选择时，若“场上其他角色都没手牌”被迫使自己弃牌，优先弃置红色牌**（R0 的 AI 参考原文） |
| 回涛 | `append_play_phase_actions` | 不使用（非主动技） |
| 回涛 | `score_ai_choice` | 对己方（自己或队友）无脑发动，对敌方不发（R0 的 AI 参考原文） |

**硬约束**：所有 AI 钩子内 `host == null`，只能读 `authoritative_snapshot` 与 `evaluator`（`docs/内容制作指南.md:1873-1877`）。

---

## 五、权威层依赖

仅依赖 `design.md` 的 **U1 弃置批次聚合**。回涛零权威层改动。

---

## 六、测试设计

`tests/haishengyin_mechanics_test.gd`（新建，仿 `tests/reincarnation_mechanics_test.gd`）：

1. 元数据：`half_locked`、`reincarnation`、`section_count == 4`、描述四节高亮可用。
2. 节推进：依次发动四节，断言 `section_index` 0→1→2→3、`round_count` 在第四节后 +1。
3. 费用校验：手牌无对应花色时 `can_activate()` 为 false。
4. 锁定后段：构造一次「黑桃+红桃」批量弃置，断言**先黑后红**（黑色询问先出现），且恰好一次批次事件。
5. 单独黑 / 单独红 / 无黑无红三种批次的行为。
6. 回涛：`section_count == 3` 时被询问、`section_count == 2` 时不询问、`round_count == 1` 时不询问。
7. 描述文本与 R0 逐字比对（含 `①..④` 与全角引号）。
