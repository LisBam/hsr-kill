# 技术设计 · 武将砂金与技能【筹码】【盲注】【风口】

> 需求与验收标准见 `prd.md`。核心层端口与时机语义以父任务 `prd.md` 的 F1–F28 表为准。
> **前置**：【风口】第一段要求 `10-04-batch-gain-timing-mechanism` 已落地（提供 `cardsGainedBatchAfter`）。

## 0. 文件清单

| 文件 | 类型 | 说明 |
|---|---|---|
| `game_data/characters/shajin.gd` | 新增 | 武将静态资料 |
| `game_data/skills/chouma.gd` | 新增 | 锁定技【筹码】 |
| `game_data/skills/mangzhu.gd` | 新增 | 【盲注】（含两个选择步骤 + 阶段比对） |
| `game_data/skills/fengkou.gd` | 新增 | 【风口】（含两段） |
| `tests/shajin_mechanics_test.gd` / `.tscn` | 新增 | 专项测试 |

**无核心层改动**。武将元数据同丹恒·饮月：`id=shajin`、`display_name=砂金`、`gender=male`、`faction=xingjihepinggongsi`、`max_hp=3`、技能顺序 `[chouma, mangzhu, fengkou]`。

## 1. 【筹码】

```gdscript
func _init() -> void:
    super({"id":"chouma","name":"筹码","trigger":"gameStart","ui_enabled":false,
           "lock":true,"description":"锁定技，游戏开始时，你摸X张牌，你的手牌上限+X。（X为你的体力上限）"})

func install() -> void:
    subscribe_timing("gameStart", _on_game_start, "global")
```

- `role` 必须是 `"global"`：`gameStart` 的三项 ID 全为 `-1`（F26）。
- 幂等位 `var _applied: bool = false`；回调开头 `if _applied: return`。
- 效果顺序：先 `announce_activation({"draw_count":x, "hand_limit_bonus":x})`（参照 `yanling.gd` 的「先宣告再效果」），再
  1. `host.call("draw", owner_player_id, x)`
  2. `host.call("add_hand_limit_bonus", owner_player_id, x, get_id())`
- `x` 读取：`get_owner_skill_player().get_state().max_hp`；取不到时回退到本文件的 `DEFAULT_MAX_HP = 3` 常量并仍执行摸牌（不得静默跳过整条效果）。
- 常量集中在文件顶部：`DEFAULT_MAX_HP`、`HAND_LIMIT_BONUS_PER_HP`（=1，使「X」既能表示摸牌张数也能表示上限加成，便于以后按需求调整）。
- **AI**：无任何 AI 决策点（无选择、无主动入口），实现文件内**不写** AI 钩子，并在类注释显式说明理由。

## 2. 【盲注】

### 2.1 元数据与状态

- `trigger` = `"phaseDrawBegin"`（被动触发，无主动入口），`ui_enabled` = `false`。
- 实例状态（每次 `phaseDrawBegin` 全部重置）：

| 字段 | 含义 |
|---|---|
| `_turn_number: int` | 绑定的回合号；拒绝迟到事件 |
| `_active: bool` | 本次摸牌阶段是否已真实弃置至少 1 张 |
| `_discarded_colours: Array[String]` | 以此法弃置的牌的颜色（去重后最多 2 项） |
| `_gained_colours: Array[String]` | 本阶段中砂金获得的、落入手牌的牌的颜色 |

### 2.2 时机订阅

```gdscript
subscribe_timing("phaseDrawBegin", _on_phase_draw_begin, "player")
subscribe_timing("gainAfter", _on_gain_after, "player")
subscribe_timing("phaseDrawEnd", _on_phase_draw_end, "player")
subscribe_timing("phaseDrawSkipped", _on_phase_draw_aborted, "player")
subscribe_timing("phaseDrawCancelled", _on_phase_draw_aborted, "player")
```

`gainAfter` 的 `role="player"` 只在本角色是**获得方**时命中（获得类时机的 `player_id` 就是获得方），因此无需再按 `player_id` 过滤；但**仍要**过滤 `to_zone == "hand"`（排除进入装备区/判定区的移动），并过滤阶段与回合（见 2.4）。

### 2.3 阶段开始：两步单选（构造上保证颜色不同）

```
phaseDrawBegin（砂金自己的摸牌阶段才继续）
  ├─ _reset_phase_state()
  ├─ 候选 = get_skill_material_candidates(owner) 过滤 zone ∈ {hand, equipment}
  ├─ 候选为空 → 直接结束（本阶段无记录）
  └─ has_nested_settlement_barrier() ?
        ├─ 是 → defer_settlement({"kind":DEFERRED_START})   # 见 2.6
        └─ 否 → 立即建 CHOICE_PICK_FIRST
CHOICE_PICK_FIRST（request_card_selection，1..1，可取消）
  ├─ 取消 → 结束（零效果、零记录）
  └─ 确认 → 复核牌仍在候选内 → discard_selected_hand_equipment(owner, [uid])
            → _active = true；记录第 1 张颜色
            → 第 2 步候选 = 剩余 hand+equipment 中「颜色 != 第 1 张颜色」的牌
                 ├─ 为空 → 直接结束（本次只弃 1 张）
                 └─ 非空 → 建 CHOICE_PICK_SECOND
CHOICE_PICK_SECOND（request_card_selection，1..1，可取消）
  ├─ 取消 → 结束（只弃 1 张）
  └─ 确认 → 复核 → discard_selected_hand_equipment(owner, [uid]) → 记录第 2 张颜色
```

**为什么用两次单选而不是一次多选 + 校验**：多选需要提交后校验，非法组合必须重问，而 AI 在「重问」场景下容易反复提交同一非法组合；两次单选把「颜色不同」变成候选集合的构造性质，AI 与玩家都不可能选出非法组合。

### 2.4 阶段中：累计获得的颜色

`_on_gain_after(event)` 的处理顺序（任一不满足即 `return`）：

1. `_active` 为真（没有真实弃置就没有记录，无需累计）。
2. `int(event.data.get("to_zone","")) == "hand"`。
3. `host.state.current_player_id == owner_player_id` 且 `host.state.current_phase == "draw"`。
4. `host.state.turn_number == _turn_number`（拒绝迟到的旧回合事件）。
5. 遍历 `event.data["card_uids"]`，对每个 uid 调 `get_owned_conversion_material_card(uid)`；取到时把 `get_color()` 追加进 `_gained_colours`（**在获得时解析颜色**，避免牌在阶段结束前离手导致解析失败）。

> `get_owned_conversion_material_card` 会搜索持有者的手牌、木牛「粮」与装备区，正好覆盖「刚落入手牌的牌」这一场景，且是现成的只读端口，无需新增核心 API。

### 2.5 阶段结束：颜色比对与结算

`_on_phase_draw_end(event)`：

1. `_active` 且回合号匹配才继续；否则仅 `_reset_phase_state()` 后返回。
2. `common = 交集(_discarded_colours, _gained_colours)`。
3. `common.size() >= 1` → `host.call("shield", owner_player_id, 1, owner_player_id, get_id())`。
4. `common.size() >= 2` → `host.call("draw", owner_player_id, 2)`。
5. `announce_activation({"common_colours":common})`（只有确实产生过效果才宣告）。
6. `_reset_phase_state()`。

两种效果**并用**（不是 else 分支）：原文用分号并列两个条件，且「至少两种」必然同时满足「至少一种」。

`_on_phase_draw_aborted(...)`：仅 `_reset_phase_state()`。

### 2.6 嵌套屏障与空转

- `phaseDrawBegin` / `phaseDrawEnd` / `gainAfter` 都是**时机回调**，在其内部直接建选择请求会踩 F22 的「已有未决选择时静默返回空数组」陷阱。因此**建请求前统一检查 `bool(host.call("has_nested_settlement_barrier"))`**：为真时用 `defer_settlement(ctx)` 登记，并在 `continue_settlement(context)` 中再建请求。
- `continue_settlement` 只处理本技能的 `kind`，未命中返回 `false`。
- **空转防护**：本技能的两步都是「取消即终结」，不存在「取消后必须重问」的循环，因此**不给保底确认分**；是否弃牌完全由真实收益决定（见 2.7）。

### 2.7 AI

| 分支 | 口径 |
|---|---|
| `CHOICE_PICK_FIRST` 确认 | 估算「弃掉这张牌」的代价 + 「凑成同色的期望收益」。本阶段的获得牌数未知，用「预计摸牌数 × 已记录颜色命中率」的粗略期望（常量 `AI_EXPECTED_DRAW_COUNT`），减去被弃牌的价值。净收益 `<= 0` 时返回负分（让通用策略取消）。**不得无条件给正分**，否则 AI 会为了凑色弃掉好牌 |
| `CHOICE_PICK_SECOND` 确认 | 只在这张牌便宜、且第 1 张的颜色与「已获得的颜色」已经命中时给正分；否则负分（只弃 1 张） |
| `append_play_phase_actions` | **不实现**：本技能没有出牌阶段主动入口（`enable` 为空） |

牌面价值统一取 `evaluator` 的公开接口或卡牌定义 `ai.value`（数组型取首项，判型后转换 — 见 `linggan.gd:672-688` 的踩坑注释）。

## 3. 【风口】

### 3.1 展示文案

`description` 使用 `prd.md` R4.1 裁定的**用户优化描述**（逐字）。元数据：

```gdscript
{"id":"fengkou","name":"风口","trigger":"active/phaseUse","enable":"phaseUse","ui_enabled":true,
 "description":"当你一次性获得至少两张牌时，你可以弃置这些牌。出牌阶段，你可以获得一名其他角色的随机一张手牌，你此前每发动一次该技能便重复一次该流程，然后你失去该技能。"}
```

### 3.2 第一段：批量获得时的可选弃置

订阅：

```gdscript
subscribe_timing("cardsGainedBatchAfter", _on_cards_gained_batch, "player")
```

`role="player"` 命中「砂金自己是获得方」的批次（批次载荷的 `receiver_player_id` 同时写入 `player_id`/`source_id`）。

回调处理顺序：

1. `int(event.data.get("batch_size", 0)) >= 2`，否则 `return`。
2. `int(event.data.get("receiver_player_id", -1)) == owner_player_id`（防御性复核）。
3. 取 `card_uids`，与「当前仍在砂金手牌中的 uid」求交集；交集为空则 `return`。
4. **重入与排队**：若 `_pending_batch_uids` 非空（已有未决询问），把本批 uid 追加进 `_batch_queue` 并 `return`；否则设 `_pending_batch_uids` 并建请求。
5. **嵌套屏障**：建请求前检查 `has_nested_settlement_barrier()`，为真则 `defer_settlement({"kind":DEFERRED_BATCH, "card_uids":uids})`；`continue_settlement` 中再建请求。
6. 请求：`request_card_selection("风口", "是否弃置这些牌？", 这批牌的候选, n, n, true, {"kind":CHOICE_CLAUSE1, "card_uids":uids, "ai_allow_confirm":true})`，其中 `n = uids.size()`——「弃置这些牌」= **全弃**，因此最小=最大=张数。
7. `CHOICE_CLAUSE1` 恢复：
   - 取消 → 清 `_pending_batch_uids`，转入队列中的下一批。
   - 确认 → `discard_selected_hand_equipment(owner, uids)`；返回弃置数 `> 0` 时把第一段计数 +1 并 `announce_activation({"count":n})`；然后清 `_pending_batch_uids` 并转入队列下一批。

**计数持久化**：写 `PlayerState.character_form_state`，键 `fengkou_clause1_count`（F21）。读取封装为 `_get_clause1_count()` / `_add_clause1_count(n)` 两个私有函数，任何地方都不得直接拼字符串键。

> **为什么不用实例字段**：换将、复原武将牌、读档都会重建技能实例；计数必须跨这三种场景保留（用户口径 U2 明确它是「历史发动次数」）。

### 3.3 第二段：出牌阶段主动获得随机手牌

```
activate()
  ├─ can_activate() 校验
  └─ request_target_selection("风口：选择一名其他角色", 合法目标, 1, 1, true, {"kind":CHOICE_PICK_TARGET})
CHOICE_PICK_TARGET（continue_selection）
  ├─ 取消 → 结束（不获得牌、不失去技能）
  └─ 确认 → _execute_active(target_id)
```

`can_activate()`：

- 持有者存活、未离场。
- `host.state.current_player_id == owner_player_id` 且 `host.state.current_phase == "play"`。
- `not host.has_pending_card_choice()`。
- 技能实例仍存在（已被移除时自然不会走到这里）。
- 存在至少一名「存活、未离场、非自己、当前手牌非空」的合法目标。
- **没有**「出牌阶段限一次」：不设阶段额度计数器（原文无此限制）。

`_execute_active(target_id)`：

```gdscript
var total: int = 1 + _get_clause1_count()      # 基础 1 张 + 每发动过一次第一段重复 1 次
var gained: int = 0
for index: int in range(total):
    # 每次重新取候选：目标手牌在每次取牌后都会变化
    var candidates: Array[Dictionary] = host.call("get_hand_candidates", owner_player_id, target_id)
    # 只取手牌区；get_hand_candidates 已经只含手牌
    if candidates.is_empty():
        break
    var picked: int = int(host.call("pick_random_candidate_index", candidates.size(), RANDOM_HISTORY_KIND,
        {"target_id":target_id, "index":index, "turn_number":int(host.state.turn_number)}))
    if picked < 0 or picked >= candidates.size():
        break
    var uid: int = int((candidates[picked] as Dictionary).get("uid", -1))
    if uid < 0 or not bool(host.call("take_selected_player_card", owner_player_id, target_id, uid)):
        break
    gained += 1
# 失去技能：无论是否取到牌，只要第二段真实发动就失去
host.call("remove_skill", owner_player_id, get_id(), "fengkou_active")
announce_activation({"target_id":target_id, "gained_count":gained, "repeat_count":total - 1})
```

约束与边界：

1. **随机可复现**：`history_kind` 用固定常量 `RANDOM_HISTORY_KIND = "fengkou_random_hand"`，`history_data` 至少含 `target_id` 与 `index`，使回放/联机两端产生同一序列（F18）。
2. **提前停止**：目标手牌耗尽、随机端口返回 `-1`、或取牌被权威拒绝，都立刻 `break`；剩余次数**不补**到别的目标。
3. **失去技能**：走 `remove_skill`（F19），它同时清 `acquired_skills`/`temporary_skills` 记录并卸载订阅，读档不会把 `fengkou` 装回来。
4. **是否失去的判定**：只要 `CHOICE_PICK_TARGET` 确认就失去（原文「然后你失去该技能」在发动之后），即使因为目标恰好无手牌而一张都没取到。取消目标选择则完全不失去。
5. **禁止入队**：第二段不能再被第一段触发（第二段每次只取 1 张，批次大小为 1，第一段条件天然不成立）。

### 3.4 AI

| 钩子 | 口径 |
|---|---|
| `append_play_phase_actions(result)` | `can_activate()` 为真时追加 `use_skill` 动作 |
| `score_ai_action(...)` | 存在有手牌的敌方可选目标时给严格正分，并按 `1 + 第一段计数` 估算可获得牌数；技能即将失去，因此只要收益为正就发动 |
| `score_ai_choice` · `CHOICE_PICK_TARGET` | 确认分 = `n × 每张牌的基础价值 × 权重 + Σ(目标态度 × 权重)`；取消给 `0.0`。合法目标已保证有手牌，因此确认必然产生真实收益 |
| `score_ai_choice` · `CHOICE_CLAUSE1` | 确认分 = `AI_CLAUSE1_SETUP_VALUE × 第二段剩余期望收益 − 这批牌的总价值`。默认在牌便宜时为正；同时受「技能尚未使用」约束（技能已失去时本分支不会再出现） |
| `continue_settlement` 分支 | 不参与评分（不是玩家选择） |

`AI_CLAUSE1_SETUP_VALUE` 与权重常量一律前置在文件顶部并写注释说明量级与调整影响。

## 4. 兼容与风险

| 风险 | 处理 |
|---|---|
| 【盲注】的 `gainAfter` 也会在**非摸牌阶段**触发 | 用 `current_phase == "draw"` + `turn_number` 双条件过滤 |
| 【盲注】与【风口】同为砂金技能，摸牌会同时触发两者 | 这是正确行为：`draw(2)` 既累计【盲注】的获得颜色，也派发一次 `batch_size == 2` 的批次事件给【风口】。专项测试必须包含该组合场景 |
| 【风口】第一段的询问可能打断摸牌阶段 | 批次事件在 `DrawResolutionService._finish_batch` 派发，此时摸牌主体已完成；询问结束后阶段照常推进 |
| 【风口】第一段在同一结算内连续触发多个批次 | 用 `_batch_queue` 顺序处理，绝不叠加第二个未决请求（F22） |
| 计数被 AI 快照读到 | `character_form_state` 对所有 AI 快照可见（F21）。本计数由公开的弃置行为决定，不构成泄漏；在文档中记录该事实 |
| 读档后【风口】被重新装回 | `remove_skill` 同步更新保存的已安装技能集合；专项测试必须覆盖「失去后存档→读档仍不存在」 |
| `pick_random_candidate_index` 在联机两端的确定性 | 与既有随机取牌共用同一条随机流；`history_data` 必须完整描述本次取牌，不得含非确定性字段（如帧号、时间） |
