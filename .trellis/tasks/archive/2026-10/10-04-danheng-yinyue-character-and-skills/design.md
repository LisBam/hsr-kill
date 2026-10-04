# 技术设计 · 武将丹恒·饮月与技能【伏辰】【濯世】

> 需求与验收标准见 `prd.md`。核心层端口、时机语义与仓库事实以父任务 `prd.md` 的 F1–F28 表为准，本文件不重复。

## 0. 文件清单

| 文件 | 类型 | 说明 |
|---|---|---|
| `game_data/characters/danheng_yinyue.gd` | 新增 | 武将静态资料（21 行模板） |
| `game_data/skills/fuchen.gd` | 新增 | 锁定技【伏辰】规则 + AI |
| `game_data/skills/zhuoshi.gd` | 新增 | 主动技【濯世】规则 + AI |
| `tests/danheng_yinyue_mechanics_test.gd` / `.tscn` | 新增 | 专项测试 |

无核心层改动。

## 1. 武将文件

严格沿用 `game_data/characters/danheng.gd` 的模板形状：顶部 `const FUCHEN_SKILL: Script = preload("res://game_data/skills/fuchen.gd")`（每个技能一个常量，顺序即技能栏顺序），`_init()` 调 `super(...)` 传元数据与技能数组。

```
id           = "danheng_yinyue"
display_name = "丹恒·饮月"
gender       = "male"
faction      = "xianzhou"
max_hp       = 4
```

`description` 写武将简介（一段中文），**不得**把技能正文写进去；技能正文由技能文件自己的 `description` 提供。

## 2. 【伏辰】设计

### 2.1 元数据

- `id` = `fuchen`，`name` = `伏辰`
- `trigger` = `respond`（锁定技没有主动入口，因此无 `enable`、`ui_enabled` = `false`）
- `lock` = 锁定技标记（与项目既有锁定技一致），保证**不产生任何选择请求**
- `description` = `锁定技，当其他角色打出一张【杀】后，你获得之。`

### 2.2 订阅与过滤

```gdscript
func install() -> void:
    subscribe_timing("respond", _on_other_player_played_sha, "global")
```

`role` 必须是 `"global"`：`respond` 的 `target_id` 恒为 `-1`（F4/`match_controller.gd:5538`），`"target"` 永远不会命中，无法监听其他角色。

回调内的过滤链条（任一不满足即 `return`）：

| 顺序 | 条件 | 理由 |
|---|---|---|
| 1 | 持有者存在且 `alive` | 死亡角色不再获得牌 |
| 2 | `int(event.player_id) != owner_player_id` | 排除自己（U5） |
| 3 | `str(event.data.get("response_action", "")) == "play"` | **语义自证**：核心在 `:5560` 已保证 `respond` 只对应「打出」；此判断只表达需求「注意，是打出」，不改行为 |
| 4 | `str(event.data.get("response_pattern", "")) == "sha"` | 只响应【杀】 |
| 5 | `int(event.data.get("card_uid", -1)) >= 0` | 必须有实体牌 |

### 2.3 效果

```gdscript
host.call("gain_card_to_hand_by_uid", owner_player_id, card_uid, get_id())
```

- 时机由核心保证可执行：`_move_played_card_to_discard()` 在派发 `respond` **之前**执行（F6），因此回调执行时该实体已在 `discard_pile`，而 `gain_card_to_hand_by_uid` 接受 `discard_pile` 来源（F7）。
- 返回值为 `false` 时（牌已被其他效果移走等）静默跳过，**不写日志、不产生选择**。
- 不调用 `announce_activation()`：锁定技无发动确认，且日志由移牌链路自身的「获得牌」日志承担。

### 2.4 AI

【伏辰】是**无选择的锁定技**，AI 不需要任何钩子：触发时自动获得牌是纯收益，没有可拒绝的分支。因此**不实现** `score_ai_action` / `score_ai_choice` / `append_play_phase_actions`。

> 这与 `content-ai.md`「正式技能必须补齐 AI」不冲突：该规范针对**存在 AI 决策点**的技能；【伏辰】没有任何 AI 可选项，伪造钩子反而会引入无意义分支。实现时在该文件的类注释中显式说明这一点。

## 3. 【濯世】设计

### 3.1 元数据与常量

```gdscript
"trigger":"active/phaseUse", "enable":"phaseUse", "ui_enabled":true,
"description":"出牌阶段限一次，你可以弃置一张基本牌并选择一名其他角色，你弃置其一张手牌，然后你可再次弃置一张基本牌并弃置其一张牌，最后你可再次弃置一张基本牌并对其造成1点雷电伤害。"
```

常量（全部前置到文件顶部，含 `@export`/`const` 风格的集中配置）：

| 常量 | 值 | 用途 |
|---|---|---|
| `PLAY_PHASE_LIMIT` | `1` | 「出牌阶段限一次」 |
| `MAX_COST_CARDS` | `3` | 三段各 1 张基本牌 |
| `THUNDER_DAMAGE` | `1` | 第三段雷电伤害点数 |
| `CARD_TYPE_BASIC` | `"basic"` | 费用牌类型 |
| `DAMAGE_NATURE_THUNDER` | `"thunder"` | 雷电属性字面量（F10） |
| `CHOICE_STEP1` / `CHOICE_STEP1_DISCARD` / `CHOICE_STEP2` / `CHOICE_STEP2_DISCARD` / `CHOICE_STEP3` | 各自稳定字符串 | `context.kind` 分派 |
| `AI_STEP_COMMIT_REWARD` | 大正数 | 步骤 1/2/3 的保底确认分（F25） |
| `AI_TARGET_WEIGHT` | 正数 | 目标态度权重 |

实例状态：`var _used_this_play_phase: int = 0`，在 `install()` 订阅的 `phaseUseBegin`（role `"player"`）中复位（F23）。

### 3.2 状态机

```
activate()
  └─ CHOICE_STEP1: request_card_target_selection(基本牌候选, 合法目标候选, 1,1,1,1, true)
        ├─ 取消 → 结束（不消费次数、零效果）
        └─ 确认 →
             discard_selected_hand_cards(owner, [card_uid])
             _used_this_play_phase += 1          # 额度只在真实弃置后消费
             announce_activation({...})
             → 建 CHOICE_STEP1_DISCARD
  └─ CHOICE_STEP1_DISCARD: request_card_selection(get_hand_candidates(owner, target), 1,1, false)
        └─ 确认 → discard_selected_player_cards(target, [uid], owner)
                  → 建 CHOICE_STEP2
  └─ CHOICE_STEP2: request_card_selection(基本牌候选, 1,1, true)
        ├─ 取消 → 建 CHOICE_STEP3
        └─ 确认 → discard_selected_hand_cards(owner, [uid]) → 建 CHOICE_STEP2_DISCARD
  └─ CHOICE_STEP2_DISCARD: request_card_selection(get_hand_equipment_candidates(owner, target), 1,1, false)
        └─ 确认 → discard_selected_player_cards(target, [uid], owner) → 建 CHOICE_STEP3
  └─ CHOICE_STEP3: request_card_selection(基本牌候选, 1,1, true)
        ├─ 取消 → 结束
        └─ 确认 → discard_selected_hand_candidates(owner, [uid])
                  damage(owner, target, 1, "thunder", "", false, false, {"source_skill_id":get_id()})
                  → 结束
```

### 3.3 关键契约与边界

1. **候选构建（每次现算，不复用旧快照）**
   - 基本牌费用候选：`host.call("get_skill_material_candidates", owner_player_id)`，过滤 `zone == "hand"` 且 `card_data.type == "basic"`。
     **口径说明**：木牛「粮」中的基本牌不作为费用候选（技能原文的「弃置一张基本牌」在本项目按手牌处理；木牛粮需专用端口）。该口径必须写进注释与文档。
   - 步骤 1 合法目标候选：存活、未离场、`player_id != owner_player_id`、且**当前至少有一张手牌**。
   - 步骤 1a 候选：`get_hand_candidates(owner_player_id, target_id)` —— 他人手牌只发**牌背**（F17），满足 U4「由你暗选」。
   - 步骤 2a 候选：`get_hand_equipment_candidates(owner_player_id, target_id)` —— 手牌 + 装备区，按 U4 口径**不含**判定区。
2. **必做步骤的退化处理**：`CHOICE_STEP1_DISCARD` / `CHOICE_STEP2_DISCARD` 是 `allow_cancel = false` 的必做步骤，异步窗口内目标可能失去全部候选。因此建请求**之前**必须先取候选；候选为空时**跳过该步骤**直接进入下一步（绝不发一个 `min_select = 1` 且候选为空的不可取消请求——那会造成永久停摆）。
3. **费用不足的退化**：步骤 2 / 3 建请求前若基本牌候选为空，直接跳过该段（等价于玩家无法支付）。取消与无候选都不得消费次数。
4. **额度消费点**：只在步骤 1 的两张牌都真实弃置成功后 `+= 1`。若 `discard_selected_hand_cards` 返回 0（权威复核拒绝）则不消费、不发 `announce_activation`、不建后续请求。
5. **每一步都要复核权威状态**：`continue_selection` 的每个分支开头重新取 `get_owner_skill_player().get_state()`，并复核目标仍存活、`host.state.current_player_id == owner_player_id`、`host.state.current_phase == "play"`；不满足则终止整条链（不产生后续效果）。
6. **目标固定**：`target_id` 只在 `CHOICE_STEP1` 确定后写入 `context`，后续步骤一律从 `context` 读取，**不重新请求目标**。
7. **`continue_selection` 返回值**：命中本技能的任何 `kind` 都返回 `true`；未命中的 `kind` 返回 `false`（避免吞掉其他技能的选择）。
8. **不建跨技能请求**：全部请求都由 `activate()` / `continue_selection()` 发起；**不在** `phaseUseBegin` 之类的时机回调里建请求，因此不需要 `has_nested_settlement_barrier()`（F22）。若实现时改变了这一点，必须补屏障检查。
9. **日志与表现**：`announce_activation()` 只在步骤 1 真实成功后调用一次，携带 `{"target_id": target_id, "cost_card_uid": uid}`。

### 3.4 AI 设计

| 钩子 | 口径 |
|---|---|
| `append_play_phase_actions(result)` | `can_activate()` 为真时追加 `{"action_type":"use_skill","actor_id":owner_player_id,"skill_id":get_id(),"payload":{"skill_id":get_id()}}` |
| `score_ai_action(...)` | 从快照读自己手牌、基本牌数、其他角色手牌数；存在「≥1 张基本牌 + ≥1 名有手牌的敌方可选目标 + 未用尽阶段额度」时给严格正分，否则 `0.0` |
| `score_ai_choice` · `CHOICE_STEP1` | 确认 → `AI_STEP_COMMIT_REWARD + 最优目标收益`；取消 → `0.0`。目标收益 = `∑(目标态度 × AI_TARGET_WEIGHT) − 费用`，费用用 `evaluator.score_resource_change()`（F24） |
| `score_ai_choice` · `CHOICE_STEP1_DISCARD` | 选牌分 = `-态度(target) × AI_TARGET_WEIGHT`（对敌方为正）；无候选时不会建请求 |
| `score_ai_choice` · `CHOICE_STEP2` | 确认 = 再付 1 张基本牌换对方 1 张牌；净收益为正才给 `> 0`，否则给负分让通用策略取消。**避免 0 分**（0 分 + 通用 +0.1 兜底会导致无条件确认，见 F25 与 `linggan.gd:76-80` 的同类注释） |
| `score_ai_choice` · `CHOICE_STEP2_DISCARD` | 同 `CHOICE_STEP1_DISCARD`，但目标为「手牌 + 装备区」中价值最高者；优先拆敌方装备 |
| `score_ai_choice` · `CHOICE_STEP3` | 1 点雷电伤害对敌方为纯收益 → 确认给 `AI_STEP_COMMIT_REWARD + 伤害收益`；对友方给负分拒绝 |

**空转防护**：`CHOICE_STEP1` / `2` / `3` 的「确认」分必须**严格大于 0**（F25），且 `AI_STEP_COMMIT_REWARD` 必须显著高于任何单张牌面收益，使「是否继续」只由真实收益的小数部分决定，不被通用手牌费用评分翻转。

## 4. 兼容与风险

| 风险 | 处理 |
|---|---|
| `respond` 派发时牌已在弃牌堆 | 这是**设计依赖**（F6），不是缺陷；实现后必须以「弃牌堆不再有该实体、手牌多一张」双向断言锁定 |
| `respond` 也可能由装备响应提供（如【八卦阵】判定为红色） | 装备响应没有实体牌消耗，`card_uid` 指向装备本身（`consume_equipment_response` 路径），此时 `response_pattern` 可能为 `"shan"`；本技能只接 `"sha"`，且应额外拒绝 `card.uid` 指向装备区的实体（实现时以「移动前实体是否在 `discard_pile`」做最终复核，取不到就跳过） |
| `hand_view_as`（手牌视为）打出的【杀】 | 消耗的是真实实体牌，`consumed.uid` 稳定，照常获得 |
| 步骤 2a 与「弃置其一张牌」的区域口径 | 按 U4 固定为手牌 + 装备区；判定区牌不在范围内，必须在测试中断言 |
| 连续发动导致链过长 | 每段都复核状态与候选，任何一步不满足即终止；链长上限恒为 3 段 |
