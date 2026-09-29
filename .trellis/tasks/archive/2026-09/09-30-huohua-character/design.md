# 武将火花与技能好戏连戏 — 技术设计

> 需求与验收见同目录 `prd.md`；欢愉技机制见子任务 `09-30-ahha-joy-mechanic/design.md`；多张重铸端口见子任务 `09-30-multi-recast-mechanic/design.md`。

---

## 一、文件清单

| # | 文件 | 类型 |
|---|---|---|
| 1 | `game_data/factions.json` | 修改（追加一条势力） |
| 2 | `game_data/characters/huohua.gd` | **新建** |
| 3 | `game_data/skills/haoxi.gd` | **新建** |
| 4 | `game_data/skills/lianxi.gd` | **新建** |
| 5 | `tests/huohua_joy_test.tscn` + `.gd` | **新建**（专项测试） |
| 6 | `README.md` | 修改（自动校验章节补一行） |

---

## 二、欢愉势力（改动 1）

在 `game_data/factions.json` 的 `factions` 数组末尾追加（保持既有条目顺序与格式，不插入中间）：

```json
{"id":"huanyu","display_name":"欢愉","short_name":"欢","color":"e0673c"}
```

- `color` 必须为六位十六进制 RGB（`game_database.gd:508` 强校验）。
- `id` 为完整小写拼音；与既有 `xingjianhuanyv`（星间寰宇）不构成重复。
- 追加到数组末尾使既有势力的相对顺序不变，选将界面与全武将入口的既有排序不受影响。

---

## 三、武将火花（改动 2）

`game_data/characters/huohua.gd`，结构照 `xiluwa.gd`：

```gdscript
extends CharacterDefinition

## 【火花】武将源码。武将通过独立技能组件配置欢愉技【好戏】与主动技【连戏】。

## 【好戏】技能脚本；由阿哈时刻按参演编号驱动的欢愉技。
const HAOXI_SKILL: Script = preload("res://game_data/skills/haoxi.gd")

## 【连戏】技能脚本；出牌阶段限一次的多次重铸与伤害技能。
const LIANXI_SKILL: Script = preload("res://game_data/skills/lianxi.gd")


func _init() -> void:
	super({
		"id":"huohua",
		"display_name":"火花",
		"gender":"female",
		"faction":"huanyu",
		"max_hp":3,
		"description":"以阿哈时刻登台演出，弃敌手牌换取基本牌，并可反复重铸手牌换取伤害。",
	}, [HAOXI_SKILL, LIANXI_SKILL])
```

---

## 四、【好戏】`haoxi`（改动 3）

### 静态参数

| 键 | 值 |
|---|---|
| `id` | `"haoxi"` |
| `name` | `"好戏"` |
| `trigger` | `"passive"`（不订阅任何标准时机，由阿哈时刻系统调用） |
| `joy_skill` | `true` |
| `performance_number` | `144` |
| `lock` | 不设（保持 `false`） |
| `ui_enabled` | 不设（保持 `false`，不生成主动按钮） |
| `description` | `欢愉技，参演编号144，你可弃置0-2名其他角色各一张随机手牌，然后从牌堆中获得X张基本牌。（X为2-本次选择的目标数）` |

### 常量（魔法数字前置）

```gdscript
## 可选择的其他角色数上限；原文“0-2名”。
const MAX_TARGETS: int = 2
## 基础获得牌数；原文“X为2-本次选择的目标数”。
const BASE_GAIN_COUNT: int = 2
## 所获得牌的类型；原文“基本牌”。
const GAIN_CARD_TYPE: String = "basic"
## 目标选择步骤的稳定 kind。
const CHOICE_KIND_TARGETS: String = "haoxi_targets"
## 随机弃置所用的随机历史稳定标识。
const HISTORY_DISCARD_CARD: String = "haoxi_random_discard"
## 从牌堆取得基本牌的移动原因标识。
const GAIN_REASON: String = "haoxi_gain_basic"
```

### 执行入口

```gdscript
func perform_joy_skill(context: Dictionary) -> void
```

```text
targets = _get_available_target_ids()          # 其他存活未离场且手牌非空的角色
if targets.is_empty():
    _resolve_effect([])                        # 无可选目标：直接按选择 0 名结算
    return
request_target_selection("【好戏】请选择0至2名其他角色", targets, 0, mini(MAX_TARGETS, targets.size()), false,
        {"kind":CHOICE_KIND_TARGETS})
```

> `allow_cancel=false`：需求写明「可以不选择角色直接点确定」，即「不选」本身就是合法结果（0 名），不应走取消路径。

### 恢复

```gdscript
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool
```

```text
if response == null: return false
if str(context.get("kind","")) != CHOICE_KIND_TARGETS: return false
if not response.confirmed: return true          # 防御：正常路径已禁用取消
_resolve_effect(response.target_ids)
return true
```

### 效果结算

```text
_resolve_effect(target_ids):
    valid_targets = 仍在场且仍有手牌的目标（逐项复核）
    announce_activation({"target_ids":valid_targets})
    # ① 逐个目标随机弃置一张手牌
    for target_id in valid_targets:
        player = host.state.get_player(target_id)
        if player == null or player.hand.is_empty(): continue
        index = host.pick_random_candidate_index(player.hand.size(), HISTORY_DISCARD_CARD,
                                                 {"skill_id":get_id(), "target_id":target_id})
        if index < 0: continue
        host.discard_selected_player_cards(target_id, [player.hand[index].uid], owner_player_id)
    # ② 从牌堆随机获得 X 张基本牌
    gain_count = maxi(BASE_GAIN_COUNT - target_ids.size(), 0)
    _gain_random_basic_cards(gain_count)
    # ③ 嵌套结算屏障处理后才回报阿哈时刻
    _finish_performance_with_barrier_check()
```

`_gain_random_basic_cards(count)`：

```text
pool = [card for card in host.state.draw_pile if GameDatabase.get_card(card.definition_id).get("type") == GAIN_CARD_TYPE]
if pool.is_empty() or count <= 0: return
for i in range(mini(count, pool.size())):
    index = host.pick_random_candidate_index(pool.size(), HISTORY_DISCARD_CARD + "_gain", {...})
    if index < 0: break
    card = pool[index]
    pool.remove_at(index)                       # 同一张牌不会被重复抽到
    host.gain_draw_pile_card_by_uid(owner_player_id, card.uid, GAIN_REASON)   # 见 :8186
```

> 复用现有原子端口，不新增移牌逻辑：`pick_random_candidate_index`（权威随机流）+ `gain_draw_pile_card_by_uid`（牌堆→手牌的唯一入口）。

`_finish_performance_with_barrier_check()`：

```text
if host.has_nested_settlement_barrier():
    defer_settlement({"kind":"haoxi_finish"})       # 基类 :557
    return
finish_joy_skill_performance()
```

```gdscript
func continue_settlement(context: Dictionary) -> bool
    if str(context.get("kind","")) == "haoxi_finish":
        finish_joy_skill_performance(); return true
    return false
```

> **为什么必须检查屏障**：弃牌与获得牌都可能触发其他角色的技能（如「当你失去最后手牌时」），这些嵌套结算必须先完成，阿哈时刻才能推进下一项欢愉技；否则会出现两个并列流程同时推进。

### 配套 AI

覆盖 `score_ai_choice(snapshot, choice_request, action, evaluator)`，只处理 `kind == "haoxi_targets"`：

- 逐目标评分：`弃置目标一张手牌的收益 − 为它放弃的 1 张基本牌收益`。
  - 目标手牌数越少（尤其 =1 时），弃置造成的破坏越大（命中其最后防御牌的概率越高）→ 正分越高。
  - 目标手牌数越多，弃置一张的相对影响越小 → 评分下降，直到低于「保留 1 张基本牌」的机会成本。
- 自身手牌中基本牌为 0 时，额外提高「放弃目标换取基本牌」的权重（对应需求参考的第一条）。
- 目标态度（`evaluator` 的敌对/友方判定）参与修正：对敌方为正、对友方为负。
- 返回值必须与「实际选中的目标集合」一致：多目标提交时按集合总分给出，保证 AI 不会提交一个集合总分低于其子集的动作。

`append_play_phase_actions` **不覆盖**（欢愉技没有出牌阶段入口）。

---

## 五、【连戏】`lianxi`（改动 4）

### 静态参数

| 键 | 值 |
|---|---|
| `id` | `"lianxi"` |
| `name` | `"连戏"` |
| `trigger` | `"active"` |
| `ui_enabled` | `true` |
| `enable` | `["phaseUse"]` |
| `description` | `出牌阶段限一次，你可以重铸你手牌中的所有基本牌，你可以重复此流程（至多重铸七次），最后对一名其他角色造成Y点伤害。（Y为你本次重铸的次数/2，向下取整）` |

### 常量

```gdscript
## 重铸次数上限；原文“至多重铸七次”。
const MAX_RECAST_ROUNDS: int = 7
## 伤害除数；原文“Y为你本次重铸的次数/2，向下取整”。
const DAMAGE_DIVISOR: int = 2
## 可重铸的牌类型；原文“基本牌”。
const RECAST_CARD_TYPE: String = "basic"
## 继续重铸询问的稳定 kind 与选项 ID。
const CHOICE_KIND_CONTINUE: String = "lianxi_continue"
const OPTION_CONTINUE: String = "continue"
const OPTION_STOP: String = "stop"
## 目标选择的稳定 kind。
const CHOICE_KIND_TARGET: String = "lianxi_target"
## 本阶段的发动额度字段；与项目既有“出牌阶段限一次”命名约定一致。
var _used_this_play_phase: bool = false
```

### 入口

```gdscript
func can_activate(_context: Dictionary = {}) -> bool
    # 无副作用：出牌阶段、未发动、手牌中至少有一张基本牌、至少有一名其他存活角色
func activate(context: Dictionary = {}) -> String
```

`can_activate` 的三条前置（配套补全，见 `prd.md` Key Decisions）：出牌阶段 + 本阶段未发动 + 手牌存在基本牌 + 存在合法伤害目标。

`activate` 流程：

```text
if not can_activate(context): return "【连戏】当前不能发动。"
_used_this_play_phase = true
announce_activation({})
_start_recast_round({"kind":"lianxi", "recast_count":0})
return ""
```

### 重铸循环（自管理状态机，仿 `xingluo.gd`）

```text
_start_recast_round(context):
    uids = _collect_basic_card_uids()           # 当前手牌中的基本牌 UID
    if uids.is_empty(): _go_to_target_selection(context); return
    count = host.recast_hand_cards(owner_player_id, uids)     # 子任务②端口；一次性重铸
    if count <= 0: _go_to_target_selection(context); return
    context["recast_count"] = int(context.get("recast_count", 0)) + 1
    if host.has_nested_settlement_barrier():
        defer_settlement(context.merged({"kind":"lianxi_resume"}))   # 屏障清空后继续
        return
    _after_recast(context)

continue_settlement(context) -> bool
    if str(context.get("kind","")) != "lianxi_resume": return false
    _after_recast(context); return true

_after_recast(context):
    rounds = int(context["recast_count"])
    if rounds >= MAX_RECAST_ROUNDS or _collect_basic_card_uids().is_empty():
        _go_to_target_selection(context); return
    request_control_selection("【连戏】当前已重铸%d次，是否继续重铸？" % rounds,
        "", [{"id":OPTION_CONTINUE, "text":"是"}, {"id":OPTION_STOP, "text":"否"}], false,
        context.merged({"kind":CHOICE_KIND_CONTINUE}))

continue_selection(context, response) -> bool
    kind = str(context.get("kind",""))
    if kind == CHOICE_KIND_CONTINUE:
        if response != null and response.control_id == OPTION_CONTINUE:
            _start_recast_round(context)        # 继续：再重铸一轮
        else:
            _go_to_target_selection(context)    # 停止：进入目标选择
        return true
    if kind == CHOICE_KIND_TARGET:
        if response != null and response.confirmed and response.target_ids.size() == 1:
            _deal_damage(int(context.get("recast_count", 0)), response.target_ids[0], context)
        return true
    return false

_go_to_target_selection(context):
    targets = 其他存活未离场角色
    if targets.is_empty(): return                 # 无合法目标：技能结束，不产生伤害
    request_target_selection("【连戏】请选择一名其他角色", targets, 1, 1, true,
        context.merged({"kind":CHOICE_KIND_TARGET}))

_deal_damage(rounds, target_id, context):
    amount = rounds / DAMAGE_DIVISOR               # 整数除法即向下取整
    if amount <= 0: return                         # 0 点伤害不产生事件
    announce_activation({"target_id":target_id, "amount":amount, "recast_count":rounds})
    host.damage(owner_player_id, target_id, amount)
```

**关键口径**：

- `Y = rounds / 2` 用整数除法天然向下取整（GDScript `/` 对 `int` 即整除）。
- `rounds == 1` 时 `amount == 0`：不造成伤害、不派发伤害事件（0 点伤害没有规则意义），但流程正常结束。
- 提示文本必须与需求原文一致：`当前已重铸%d次，是否继续重铸？`（原文中的 `y` 即次数占位）。
- 询问只在「本轮重铸后有基本牌」且「未满 7 次」时出现，与需求「直到选择否或者手牌中没有基本牌」一致。
- 目标选择允许取消：取消则不造成伤害，技能已消耗的本阶段额度不返还（与项目「取消不回退已支付费用」口径一致）。

### 配套 AI

1. `append_play_phase_actions(result)`：仅当 `can_activate()` 为真时追加一个 `action_type=use_skill`、`payload.skill_id="lianxi"` 的合法动作。
2. `score_ai_action(snapshot, action, evaluator)`：按 `⌊预期重铸次数/2⌋` 的伤害收益减去重铸消耗的手牌质量损失给出正分；手牌中基本牌越多、目标越敌对，分越高。
3. `score_ai_choice`：
   - `lianxi_continue`：比较「再重铸一轮后预期伤害增量」与「再消耗一批基本牌的损失」。基本牌可用量充足且目标为敌方时倾向继续；否则停止。**必须避免 0 分**（否则 AI 会进入「发动→取消」空转，参照 `jiegou.gd` 的既有教训）。
   - `lianxi_target`：优先敌方、优先生存威胁最大的目标。
4. 需求未提供【连戏】的 AI 参考，以上为按项目规范补全的通用逻辑（见 `项目专属AGENTS.md` 2.3）。

---

## 六、测试设计（`tests/huohua_joy_test.tscn`）

| 用例 | 断言 |
|---|---|
| 势力与武将 | 火花 `faction == "huanyu"`、`max_hp == 3`、`gender == "female"`；势力表含「欢愉」且颜色为 `e0673c` |
| 文本逐字一致 | 两技能的 `name` 与 `description` 与 `prd.md` 原文逐字相同（含全角括号、半角连字符、`X`/`Y` 占位符） |
| 好戏·0 目标 | 选 0 名 → 获得 2 张基本牌，无目标被弃牌 |
| 好戏·1 目标 | 选 1 名 → 该目标被随机弃置 1 张手牌、获得 1 张基本牌 |
| 好戏·2 目标 | 选 2 名 → 两名目标各被弃 1 张、获得 0 张基本牌 |
| 好戏·牌堆不足 | 牌堆基本牌不足 X 张时按实际数量获得且不报错 |
| 好戏·无候选 | 其他角色均无手牌时直接获得 2 张基本牌 |
| 连戏·单轮 | 手牌 2 张基本牌，选择「否」→ 重铸 2 张、摸 2 张、`rounds=1`、伤害 0（不派发伤害事件） |
| 连戏·多轮 | 持续选择「是」直到 7 次上限 → 不再询问，直接进入目标选择，伤害 3 |
| 连戏·自然终止 | 重铸后手牌已无基本牌 → 不再询问，直接进入目标选择 |
| 连戏·限一次 | 发动一次后 `can_activate` 在本出牌阶段返回 `false` |
| 连戏·伤害公式 | `rounds` = 2/3/4/5/6/7 时伤害分别为 1/1/2/2/3/3 |
| AI·好戏 | 自身基本牌为 0 时，AI 选择的目标数少于基本牌充足时 |
| AI·连戏 | `score_ai_choice` 对「继续」与「停止」给出非零且可比较的分数（不空转） |

---

## 七、风险与回滚

| 风险 | 说明 | 对策 |
|---|---|---|
| 【好戏】随机弃置未走权威随机流 | 固定种子下不可复现 | 统一走 `pick_random_candidate_index`，禁止用 `randi()` |
| 【好戏】直接改动手牌/牌堆 | 违反「移牌唯一边界」 | 只经 `discard_selected_player_cards` 与 `gain_draw_pile_card_by_uid` |
| 【连戏】重铸逐张调用 | 违反需求「而不是一张一张重铸」 | 必须调用 `recast_hand_cards` 一次性传全部 UID |
| 嵌套结算与阿哈时刻队列并发推进 | 队列停在当前项或两项流程同时推进 | 落点统一走 `has_nested_settlement_barrier()` + `defer_settlement` |
| 文案与原文不一致 | 违反项目第一铁律 | 测试逐字断言 |

**回滚**：删除三个新文件、还原 `factions.json` 即可（无状态、无存档影响）。
