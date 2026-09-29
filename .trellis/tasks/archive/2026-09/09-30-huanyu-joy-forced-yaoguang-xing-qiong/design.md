# 技术设计：欢愉技强制发动机制与爻光/星/穹三名武将

> 依据 `prd.md`（含 D1–D8 已裁决项）。分层遵循 `.trellis/spec/` 的单向依赖铁律：内容层只声明，权威只在 `MatchController` + `GameState`，UI/AI/网络只读快照。

---

## 一、总体分层落点

| 变更 | 层 | 落点 |
|---|---|---|
| 欢愉技强制发动口径（不询问、不取消、`lock=false`） | core + content + docs | 文档口径为主；代码侧只需好戏窗口 `allow_cancel=false`（见 §四.1） |
| 独立欢愉技演出（咬它驱动他人欢愉技） | core | `AhhaMomentSystem` 新增 standalone 演出通道 |
| 额外阿哈时刻（鸿运） | core | 同上通道 + `AhhaMomentSystem` 新增绕额度入口 |
| 技能效果层数（凶星叠层） | content | 技能侧写入目标/自己的 `PlayerState.character_form_state`（零核心字段改动，D7 修正） |
| 场上牌候选（好活） | core | `MatchController` 新增公开候选聚合端口 |
| 按花色额度（咬它，整局各一次） | content | 技能实例私有字段（照【弦奏】范式，不重置） |
| 视角/时机接线（咬它、鸿运） | content | 订阅既有 `phaseBefore` 时机（D8） |
| 角标与层数文本（凶星） | content | `set_character_corner_text_entry`，照【逐风】`"逐风 %d"` 范式 |
| 好戏正文与窗口 | content + ui | `haoxi.gd` 正文改写 + 取消按钮可见性收敛 |

---

## 二、内容层新增文件

```text
game_data/characters/yaoguang.gd      # 爻光：仙舟联盟 xianzhou / female / 3 / [xiongxing, hongyun]
game_data/characters/xing_huanyv.gd   # 星  ：欢愉派系 huanyu   / female / 4 / [yaota, haohuo]
game_data/characters/qiong_huanyv.gd  # 穹  ：欢愉派系 huanyu   / male   / 4 / [yaota, dangshang]
game_data/skills/xiongxing.gd         # 凶星：欢愉技，参演编号 116
game_data/skills/hongyun.gd           # 鸿运：普通技能（非欢愉技），phaseBefore
game_data/skills/yaota.gd             # 咬它：普通技能（非欢愉技），phaseBefore；星/穹共用（D5）
game_data/skills/haohuo.gd            # 好活：欢愉技，参演编号 120
game_data/skills/dangshang.gd         # 当赏：欢愉技，参演编号 120
```

命名：文件名与稳定 `id` 均为小写拼音，全项目唯一。五名技能的 `description` **逐字**采用 `prd.md` R3–R5 的原文，一字不改（含标点与括号）。

---

## 三、核心层新增与改动

### 3.1 凶星层数落点：既有 `PlayerState.character_form_state`（D7 修正）

**零核心字段改动。** 依据 `skill-authoring.md:70` 的强制规范——「本局一次」或跨回合的私有记忆必须写入持有者的 `PlayerState.character_form_state`（随权威存档往返、`to_dict` 仅在 `reveal_private` 时输出，即**不进公开快照**），项目已有【轮回】`lunhui.gd:51`、【薪继】`xinji.gd:95`、【劫制】`jiezhi.gd:144`、【咒叙】`zhuxv.gd:162`、【永劫】`yongjie.gd:271` 五个技能沿用该范式。

技能侧直接读写（先例同前），键名集中声明为文件顶部常量：

```gdscript
## 目标身上「下次受伤 +N」的累计层数键；写入目标角色的 character_form_state，多来源共享同一键以聚合层数。
const DAMAGE_STACK_STATE_KEY: String = "xiongxing_damage_stacks"

## 自选凶星时提供的「下次体力上限减少防止」剩余次数键；只写入持有者自己的 character_form_state。
const MAX_HP_GUARD_STATE_KEY: String = "xiongxing_max_hp_guard"
```

- **权威端读写**：技能运行在权威侧，直接经 `host.state.get_player(target_id).character_form_state` 读写；观察者快照的私有裁剪不影响它，也不新增裁剪规则。
- **多来源聚合**：多名爻光打同一目标时共享同一键，值即目标身上的**总层数**；角标按该值重写。
- **读档一致性**：`character_form_state` 与 `character_corner_text_entries` **都**随存档往返，因此读档后无需迁移；`install()` 里做一次自愈校验（层数为 0 时移除残留角标、层数 > 0 时按层数重写文本）。
- **死亡清理**：订阅 `dieAfter` 清理自己的键与角标（照【追歼】`_on_player_died`）。

### 3.2 `AhhaMomentSystem`：独立演出与额外阿哈时刻

新增一个**共用**的 standalone 通道，供两种新需求复用：

```gdscript
## 独立演出完成上下文；非空表示当前队列由技能请求，结束后回调该技能而非恢复回合开始。
## 只保存可序列化基础值：completion_kind / skill_owner_id / skill_id / skill_character_generation / 业务字段。
var _standalone_context: Dictionary = {}
```

- `try_perform_single_joy_skill(player_id, skill_id, completion_context) -> bool`
  只把**指定的一项**放入 `_performance_queue`，走既有 `_advance_to_next_valid_entry()` / `finish_joy_skill_performance()` 回报链（技能侧无需改动，仍调用 `finish_joy_skill_performance()`）。
  技能必须 `can_perform_joy_skill()` 为真，否则返回 false 且不建立队列。
- `try_trigger_extra_moment(trigger_player_id, completion_context) -> bool`
  **绕过**概率判定与 `_triggered_this_round` 轮次额度（D1）；复用 `build_performance_order(trigger_player_id)`；参演序列为空时返回 false，**不消耗随机数、不写随机历史、不占额度**（保持既有口径）。
- `_complete_all_performances()` 分流：`_standalone_context` 非空 → `_host.continue_after_standalone_joy_performance(context)`；否则维持既有 `continue_after_ahha_moment(...)`。
- `shutdown()` / `configure()` 一并清空 `_standalone_context`。
- 日志：standalone 演出写自己的公开日志（不复用「阿哈时刻：%d项欢愉技依次演出。」的语义，避免与正常阿哈时刻混淆）。

`SkillDefinition` 新增基类钩子（默认空实现，与 `continue_extra_phase` 同构）：

```gdscript
## 独立欢愉技演出结束后的恢复入口；由控制器在 standalone 队列排空后回调。
## 默认空实现；只有以"令他人发动欢愉技"方式驱动演出的技能需要覆盖。
func continue_joy_performance(_context: Dictionary) -> void:
	pass
```

`MatchController.continue_after_standalone_joy_performance(context) -> void`：按 `skill_owner_id` + `skill_character_generation` 复核实例有效性后回调，范式照 `_complete_active_independent_play_phase`（`match_controller.gd:7676-7681`）。

### 3.3 「场上」候选聚合端口（好活）

新增公开端口（复用既有私有积木 `_build_player_zone_candidates` / `_serialize_choice_candidate` / `can_discard_player_card`）：

```gdscript
## 返回全部存活在场角色装备区与判定区的可弃置候选；不含手牌区，即"场上"。
## include_self 由调用方决定是否包含来源角色自己的区域性牌（好活包含自己，D3）。
func get_field_card_candidates(viewer_id: int, include_self: bool = true) -> Array[Dictionary]
```

- 遍历 `state.players`（跳过死亡/离场），对每名角色取装备 5 槽（跳过已废除槽位）与 `judgment_area`（跳过 `judgment_area_abolished`）。
- 每张牌过 `can_discard_player_card(viewer_id, owner_id, card, zone, slot)` 保护校验。
- 候选结构沿用 `{"uid","owner_id","zone","slot","visible","card_data"}`，界面与 AI 复用同一份数据。

### 3.4 好戏窗口：`allow_cancel = false`（R2.2）

- `haoxi.gd`：`_init()` 的 `description` 改为 R2.1 原文（去「可」字）；`perform_joy_skill()` 的目标选择请求 `allow_cancel` 由 `true` 改 `false`，`MIN_TARGET_COUNT` 保持 `0`（0 名合法）。
- `continue_selection()` 的语义相应简化：请求不再允许取消，但**仍保留** `not response.confirmed` 的防御分支（网络/回放异常输入），按 0 名目标结算，保持 X 口径不变。
- **UI 必须同步**：`scripts/ui/card_selection_panel.gd:312` 与 `:464` 当前是
  `_cancel_button.visible = allow_cancel or min_select == 0`，
  即 `min_select == 0` 会**无条件**显示取消按钮。需把取消按钮可见性**收敛为只由 `allow_cancel` 决定**（`card_selection_panel.gd:287`、`:959` 已是该口径，与内联选择 `match_table.gd:4810` 一致），否则改 `allow_cancel` 无效。
  影响面：仅 `min_select == 0 且 allow_cancel == false` 的既有请求会从「有取消」变为「无取消」——这本就是 `allow_cancel=false`（不可取消）的正确语义；实现时需逐个核对生产调用点并在测试中回归。

### 3.5 好戏的「强制发动、不属于锁定技」（R1）

- 现状已满足「无是否发动询问」（欢愉技 `trigger:"passive"`、`ui_enabled` 默认 false、`lock` 默认 false）。
- 本次补齐的是**口径文档化**（`docs/游戏机制与玩法内容.md`、`docs/内容制作指南.md`）：欢愉技一律强制发动、不可取消、不询问是否发动；强制发动**不来自**锁定技语义，`lock` 保持 `false`，仍可被「非锁定技失效」压制。
- 咬它驱动他人欢愉技、鸿运驱动额外阿哈时刻，同样**不创建**「是否发动该欢愉技」的询问。

---

## 四、五个新技能的实现设计

### 4.1 【凶星】`xiongxing.gd`（欢愉技 / 116）

- `joy_skill = true`、`performance_number = 116`、`trigger = "passive"`。
- **`perform_joy_skill()`**：选 `1` 名角色（**含自己**，存活且未离场），`allow_cancel = false`（欢愉技强制发动，无取消）。确认后把目标 `character_form_state[DAMAGE_STACK_STATE_KEY]` 层数 +1（自选时同时给 `MAX_HP_GUARD_STATE_KEY` +1），刷新角标并 `finish_joy_skill_performance()`。
- **加伤**：订阅 `damageBegin3`（`"global"`），照【追歼】范式在 `event.data["amount"] += stacks`；用预留事件 ID 防止同一次外层伤害的嵌套伤害重复加成。
- **消费**：订阅 `damage`，实际伤害成立时把该目标层数减 1 并刷新角标（层数归零即移除角标）。`damageCancelled` / `damageZero` 只释放事件占用，不消费层数（与追歼一致）。
- **自选附加效果**：目标为持有者自己时，该层额外提供一次「下次体力上限减少时防止之」。订阅 `loseMaxHpBefore`（`"target"`，窗口在 `change_max_hp` 中**同步派发且可取消**，`match_controller.gd:4064-4066`），若 `event.target_id` 是持有者且持有者身上有可用的「凶星自选防止额度」，则 `event.cancel()` 并消耗一层防止额度。
- **角标**：单一条目 ID `"xiongxing"`（**不带来源玩家后缀**——层数已按目标聚合在目标自己的 `character_form_state` 里，一条即够，与【酩酊】的「每来源一条」不同）；文本 `凶星`（1 层）或 `凶星xN`（N ≥ 2，R3.3）；`order = 50`（与【酩酊】【追歼】同档）。层数归零调用 `remove_character_corner_text_entry`。
- **AI**（R3.2）：目标分 = `get_threat()` 正向权重 + 敌方态度权重；自己为候选时，仅在「自身体力上限 == 1 且我方欢愉技数 − 敌方欢愉技数 ≥ 2」时把自己的分抬到最高。欢愉技数量由 **AI 层**的 `get_side_joy_skill_count()` 从静态元数据统计（见 §五的修正说明），核心层不新增该端口。

### 4.2 【鸿运】`hongyun.gd`（普通技能 / phaseBefore）

- `joy_skill = false`（无标签、无参演编号）。
- 订阅 `phaseBefore`（`"player"`，D8）。
- 触发窗口的**配套判据**（需求未明确，按通用设计补全，见末尾「自行补全」）：持有者存活在场、体力上限 > 1、本技能本轮未发动、`AhhaMomentSystem` 当前不在演出中、场上存在可执行欢愉技（参演序列非空）。任一不满足则不创建窗口（不询问、不消耗额度）。
- 玩家确认 → `try_trigger_extra_moment(owner_player_id, {...})`；演出结束后经 `continue_joy_performance()` 回调 → `change_max_hp(owner_player_id, -1, ...)` → 本轮额度置位。
- 「每轮限一次」：私有 `_used_this_round: bool` + 订阅 `roundStart` 重置（照【焕发】`huanfa.gd:6/43/49`）。
- **AI**（R3.5）：比较双方欢愉技数量差 `d = 我方 − 敌方`；`d ≤ -1` 不发动；`d ∈ {0,1}` 且 `hp < max_hp` 时发动；`d ≥ 2` 且 `max_hp > 1` 时发动。

### 4.3 【咬它】`yaota.gd`（普通技能 / phaseBefore；星与穹共用）

- `joy_skill = false`。订阅 `phaseBefore`（`"player"`）。
- **额度**：私有 `_used_suits: Dictionary`（键为 `spade/heart/club/diamond`），**整局不重置**（D4）。花色是裸 `String`，技能顶部自建 `const CARD_SUITS`（项目无 `Suit` 枚举）。
- **候选**：`get_hand_candidates(owner_player_id, owner_player_id)` 中筛出「花色属于四花色 且 该花色额度未用」的普通手牌；为空则不创建窗口。
- **询问**：`request_card_target_selection(...)`：1 张手牌（费用）+ 1 名角色（目标，**含自己**，存活在场），`allow_cancel = true`（这是可选的普通技能）。
- **结算**：先按弃置的实体牌花色锁定额度（失败回滚，照【弦奏】`xianzou.gd:60-65`），弃置走 `discard_selected_hand_equipment`；再取目标身上**参演编号最小**的可执行欢愉技：
  - 有 → `try_perform_single_joy_skill(target_id, skill_id, {...})`（强制发动，不询问），演出结束后 `continue_joy_performance()` 收尾。
  - 无 → `request_extra_play_phase(target_id, owner_player_id, get_id(), completion_context)`，阶段结束后 `continue_extra_phase()` 收尾。
  - 完成上下文固定带 `skill_owner_id` / `skill_id` / `skill_character_generation`（照 `mice.gd:128-136`）。
- **AI**（R4.2）：目标优先级 ①有欢愉技的队友 ②手牌 ≥ 8 的队友 ③有欢愉技的任意角色 ④手牌 ≥ 5 的队友 ⑤自己 —— 按 `prd.md` R4.2 的**字面顺序**实现为加权评分（手牌数 ≥ 8 的队友 > 有欢愉技的队友 > 手牌数 ≥ 5 的队友 > 自己）；最高优先级不是自己时，只要存在可弃置花色就发动；最高优先级是自己时，仅当可弃置花色的牌价值低于阈值才发动。

### 4.4 【好活】`haohuo.gd`（欢愉技 / 120）

- `perform_joy_skill()`：用 `get_field_card_candidates(owner_player_id, true)`（含自己，D3）取「场上」候选；为空则直接 `finish_joy_skill_performance()`（无牌可弃，演出空过但必须回报结束）。
- 目标选择 `1` 张、`allow_cancel = false`；按候选的 `owner_id` 调 `discard_selected_player_card(owner_player_id, owner_id, uid)`（**支持判定区且过保护校验**；不使用绕过保护的 `discard_selected_judgment_card`）。
- **AI**（R4.4）：优先我方判定区的延时锦囊（`type == "trick" and delayed == true`，不硬编码牌名，权威写法见 `match_controller.gd:6732`），其中【乐不思蜀】`lebu` / 【兵粮寸断】`bingliang` 最高；其次敌方装备区牌；再其次其他。

### 4.5 【当赏】`dangshang.gd`（欢愉技 / 120）

- `perform_joy_skill()`：选 `1` 名角色（含自己），`allow_cancel = false`；调用统一摸牌端口令其摸 1 张，然后 `finish_joy_skill_performance()`。
- AI：按目标态度与手牌价值选最优（队友或自己优先，敌方为负收益）。

---

## 五、需要新增的通用只读查询

```gdscript
## 返回指定角色当前可执行的欢愉技 ID 列表；按参演编号升序、技能 ID 字典序稳定排列。
func get_joy_skill_ids(player_id: int) -> Array[String]
```

落点：`MatchController`（读 `skill_instances_by_player`，与 `ahha_moment_system.gd:167-172` 同一口径），避免内容层自行遍历私表。

**修正（实现期）**：「我方/敌方欢愉技数量」不属于核心只读查询，而是 **AI 层**的判断口径——AI 不得读取权威 `skill_instances_by_player`（`content-ai.md` §七）。因此改为在 `NonameAIEvaluator` 内新增：

```gdscript
## 返回某一阵营的欢愉技数量；按静态武将元数据统计（武将 → skills → joy_skill），结果按角色ID缓存。
func get_side_joy_skill_count(authoritative_snapshot: Dictionary, viewer_id: int, allied: bool) -> int

## 判断一名角色是否持有欢愉技；同样只读静态元数据。
func character_has_joy_skill(character_id: String) -> bool
```

态度为正或 0 的角色计入我方、为负的计入敌方，中立角色不计入任何一方。核心层因此**不再新增** `get_joy_skill_count`。

---

## 六、兼容性与迁移

| 关注点 | 结论 |
|---|---|
| 存档 | **不新增字段**。凶星层数走既有 `character_form_state`（`player_state.gd:295` 回填 / `:511` 输出），角标走既有 `character_corner_text_entries`，两者都随存档往返 → 读档后层数与角标同时恢复，无需迁移 |
| 联机快照 | 快照结构**不变**；角标文本本来就是公开字段，层数本身留在 `reveal_private` 之外，不新增裁剪规则、不增加快照体积 |
| 回放 | 新增随机/演出均不引入新随机源：`try_trigger_extra_moment` 与 standalone 演出**不掷骰**；好活/当赏无随机；凶星无随机 → 回放确定性不受影响 |
| 既有技能 | 既有技能不读新增键；好戏仅改文本与窗口；取消按钮收敛只影响 `min_select=0 且 allow_cancel=false` 的请求 |
| 时机目录 | **不新增时机**（D8 复用 `phaseBefore`）；`loseMaxHpBefore` 已在 `RuleTimingCatalog.HEALTH_STATE_TIMINGS` |
| 文档漂移 | `docs/内容制作指南.md:1028` 的 `change_max_hp` 签名缺 `allow_out_of_game`/`resolve_dying`，本次一并修正 |

---

## 七、重要取舍与风险

1. **`phaseBefore` 而非回合事实之前（D8）**：需求原文写「你的回合开始前」，项目内该语义的既有落点是 `phaseBefore`（回合事实已建立、准备阶段之前）。取此方案可完全避免改动 `_continue_turn_start_prelude` 硬编码链，风险最低；代价是鸿运的额外演出必然排在正常阿哈时刻之后（与 D1 一致）。
2. **`request_extra_play_phase` 在 `phaseBefore` 的恢复语义（高风险）**：该端口会把 `original_phase`/`original_phase_index` 快照为 `start`/`0` 并在阶段结束后回写。既有先例 `mice.gd` 是在 `phaseEnd` 调用（`original_phase == "finish"`），`phaseBefore` 场景**无先例**。实现时必须先跑最小验证；若不兼容，回退方案是：咬它在 `continue_selection` 里先 `defer_settlement(...)`，把启动独立阶段推迟到通用结算屏障清空之后，再启动。
3. **凶星层数走 `character_form_state` 而非公开标记或新字段**：`public_marks` 的 `globally_unique` 是「清除其他角色的同 ID 标记」，**不是**多来源合并计数，且会渲染圆形徽标（与「和酩酊一样的角标」冲突）；新增公开字段则会让快照结构变化。`character_form_state` 既有、私有、随存档往返，且项目规范强制要求跨回合私有记忆写在这里，故采用。代价：层数不进公开快照，AI 若要读数值需经权威侧查询而非快照。
4. **「下次体力上限减少」的防止必须同步完成**：`change_max_hp` 用同步派发的 `_emit_rule_timing`（不可跨帧等待），因此**不能**做成「弹窗询问是否防止」。凶星是纯被动防止，直接 `event.cancel()` 即正确；若将来需要「先询问再防」，须为 `change_max_hp` 新增 `RuleStepSequence` 端口（本次不做）。
5. **咬它「整局每种花色各一次」不进存档**：与【弦奏】【逐风】的既有取舍一致（技能实例私有字段不入存档）。本次**不**扩大改动面去修这处既有技术债，仅在文档中记录该限制。
6. **取消按钮可见性收敛的回归风险**：见 §3.4，属 UI 行为变化，需逐个核对生产调用点并跑 UI 测试。

---

## 八、自行补全的配套逻辑（需求未明确，按通用设计补全，交付时单独告知）

1. 【鸿运】的发动前置判据：体力上限 ≤ 1 时不开放窗口；场上无可执行欢愉技时不开放窗口（避免白扣上限）。
2. 【鸿运】减少上限调用 `change_max_hp` 时，该端口不写日志也不 `_emit_state()`，因此技能自行 `add_log` 并确认界面刷新路径。
3. 【凶星】选自己时，「防止上限减少」按层各提供一次（层数即次数），与「下次受伤 +N」的层数语义对齐。
4. 【咬它】目标拥有欢愉技但该技能当前不可执行（如被「非锁定技失效」压制）时，按字面走「无欢愉技」分支给予额外出牌阶段 —— 待实现时以「是否 `can_perform_joy_skill()`」为准，并在文档中写明。
5. 【咬它】目标拥有多个欢愉技时，取参演编号最小者（编号相同退化为技能 ID 字典序），与阿哈时刻的排序口径一致。
6. 【好活】无任何场上牌可弃时，技能空过但正常回报演出结束，不卡队列。
7. 【当赏】与【好活】参演编号同为 120，同编号时的先后由阿哈时刻既有座次排序决定，不做特殊处理。

---

## 九、回滚

- 本次改动集中在新增文件 + `AhhaMomentSystem` 的 standalone 通道 + `MatchController` 三个新端口 + `card_selection_panel.gd` 两行可见性收敛；**不动 `PlayerState` 结构、不动快照与存档格式**。
- 回滚顺序：先回滚好戏与 UI（互不依赖），再回滚 `AhhaMomentSystem` 通道（`_standalone_context` 默认空即等价旧行为，属**可安全共存**的新增分支），最后移除五份新增内容文件。
