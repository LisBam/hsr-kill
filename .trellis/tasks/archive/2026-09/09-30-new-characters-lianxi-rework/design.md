# 技术设计：三名新武将与【连戏】改写

> 需求与验收标准见 [`prd.md`](./prd.md)；执行顺序与验证命令见 [`implement.md`](./implement.md)。
> 铁律：五个技能的玩家可见 `description` 与需求原文**逐字一致**，任何设计取舍都不得改动原文。

---

## 1. 改动分布（分层）

| 层 | 文件 | 改动性质 |
|---|---|---|
| 核心层 | `scripts/core/match_controller.gd`、`scripts/core/card_rule_service.gd`、`game_data/skill_definition.gd` | **新增 3 处能力**（§3）。除此之外不改核心结算流程 |
| 内容层 | `game_data/skills/lianxi.gd` | 重构为「出牌阶段开始时」询问式技能；两个常量改值 |
| 内容层 | `game_data/skills/tongpao.gd`、`yuezhi.gd`、`duanjie.gd`、`yaoji.gd`、`lingshuang.gd` | 新增 |
| 内容层 | `game_data/characters/danheng_tenhuang.gd`、`waerte.gd`、`yanqing.gd` | 新增 |
| 测试 | `tests/huohua_joy_test.gd`、新增专项测试 | 更新 / 新增 |
| 文档 | `docs/内容制作指南.md`、`docs/游戏机制与玩法内容.md`、`docs/AI模块.md`、`README.md` | 同步 |

**不新增**任何牌名/技能 ID 白名单，不改 `BasicAIPolicy`、不改 `CardEffectResolver`、不改阶段编排。

---

## 2. 设计总原则

- 五个技能全部走**既有端口**；只有三处是既有能力不足的缺口，因此新增 §3 的三处最小扩展（2 个控制器端口 + 1 条带目标上下文的距离钩子链）。
- 技能私有跨回合状态一律写入 `PlayerState.character_form_state`（随权威存档往返、不进公开快照），**不**依赖技能实例字段保存持久进度。
- 「客观上无可执行内容」的轮回节按既有铁律走**空节推进**（`docs/内容制作指南.md:4061-4076`），不得让 `can_activate()` 返回 `false` 而卡死轮回。
- 每个可能产生子交互的效果独占一步；创建交互的函数必须有对应 `continue_*` 恢复实现。

---

## 3. 核心层三处新增

三处都是**纯新增**：新增函数、或在一个既有布尔表达式上 OR 一个默认返回 `false` 的新钩子。既有技能的返回值不会改变，既有分支语义不变。

### 3.1 `replace_card_use_targets()` —— 异步改写用牌目标

**为什么必须新增**：`_apply_card_rule_timing()`（`match_controller.gd:12558`）在**规则事件完成后**以 `rule_event.data["target_ids"]` 整体覆盖 `card_use_context["target_ids"]`。同步技能可直接写 `event.data`；但【岳峙】需要一次「你可以」询问，是**异步**的：询问恢复时原回调栈已返回，此时只写 `card_use_context` 会被随后的结果提交用派发前快照覆盖（该陷阱在 `:8140-8142` 已用 `_publish_pending_custom_args` 解决过一次）。

```gdscript
## 把仍处于使用生命周期的牌的目标数组整体替换为给定数组；同时写入共享上下文与
## 正在等待应答的用牌修改窗口，保证异步技能（选择恢复后）的目标改写不会被结果提交
## 用派发前快照覆盖。目标数组保留重复项，使同一角色按出现次数分别结算。
func replace_card_use_targets(card_uid: int, target_ids: Array[int], reason: String = "") -> bool
```

实现要点：
- 复用既有定位机制 `_find_pending_card_timing_event(card_uid)`（`:8160`）取得等待窗口，写 `pending_event.data["target_ids"]`；无等待窗口时退化为纯写共享上下文（与 `_publish_pending_custom_args` 同口径）。
- 同步写 `_card_use_contexts[card_uid]["target_ids"]`。
- 不改 `_apply_card_rule_timing` 的既有语义（`target_ids` 以 RuleEvent 为准、排除/直击仍为可叠加集合）。
- 只接受整数玩家 ID，保留重复项；与 `docs/内容制作指南.md:2512` 的数据契约一致。

**回归面**：纯新增函数，无既有调用者；不改变任何现有路径的行为。

### 3.2 `mark_card_use_limit_exempt()` —— 事后补记次数豁免

**为什么必须新增**：`does_not_count_toward_play_limit()` 钩子只在 `declare` 步骤被读取一次（`match_controller.gd:12320`）并把结果写进两个豁免历史（`:12325-12327`）；而【凌霜】的触发时机（"当你使用【杀】指定目标时"）**必然晚于** `declare`，钩子在本次用牌上早已返回过。项目内该钩子目前**零使用示例**。

```gdscript
## 为一名角色的一次用牌补记“不计入使用次数限制”的豁免历史；供技能在使用牌声明之后追加豁免。
## 与声明步骤（_card_use_step_declare）的写入口径完全一致：整局与出牌阶段两份豁免历史同时递增，
## 因此次数查询的净计数“使用 - 豁免”会减少，已经达到上限的牌族重新变为可用，无需改动任何校验分支。
## 幂等性由调用方技能负责：同一次用牌重复调用会重复豁免，使该牌族的可使用次数被额外放宽。
func mark_card_use_limit_exempt(player_id: int, card_definition_id: String) -> bool
```

实现要点：
- 写入 `play_phase_card_use_limit_exempt_history` 与 `card_use_limit_exempt_history`，与 `:12325-12327` 完全同一条链（因此 `card_rule_service._get_grouped_play_count :397` 的 `use - exempt` 自动生效）。
- 幂等保护由调用方（技能）持有的「本张牌是否已豁免」标记负责；端口自身只做一次累加。
- **不得**由内容层直接改写 `PlayerState`；本端口是唯一合法入口。

**回归面**：纯新增函数 + 一个写入端口，不改变 `validate_use` 的既有判定分支。

### 3.3 `ignores_card_distance_limit_to_target()` —— 带目标上下文的距离豁免钩子

**为什么必须新增**：项目既有的两个距离钩子都缺一半上下文，**二者都无法表达"只对【杀】、只对距离最远的角色解除距离限制"**：

| 既有钩子 | 知道什么 | 缺什么 | 若强行使用 |
|---|---|---|---|
| `ignores_card_distance_limit(card_definition)`（`skill_definition.gd:734`） | 牌 | **目标** | 让【杀】**对所有角色**解限，违背原文"对距离与你最远的角色"限定 |
| `modify_distance_to_target(target_id, current_distance)`（`:739`） | 目标 | **牌** | 把「最远角色」的距离视为 1，**同时放宽所有距离敏感牌**（【顺手牵羊】【借刀杀人】等），且改写了距离数值本身 |

而用牌目标的距离判定处（`card_rule_service.gd:368-373`）**恰好同时持有牌定义与目标 ID**：

```gdscript
# 既有代码（_validate_target 内，:368-373）
var distance_limit: String = str(definition.get("distance_limit", "none"))
var ignore_distance_limit: bool = bool(rule_overrides.get("ignore_distance_limit", false)) or _skill_ignores_card_distance_limit(actor.player_id, definition)
if not ignore_distance_limit and distance_limit == "attack_range" and calculate_distance(actor.player_id, target_id) > get_attack_range(actor.player_id):
	return ...
if not ignore_distance_limit and distance_limit == "one" and calculate_distance(actor.player_id, target_id) > 1:
	return ...
```

因此新增一条**贯穿三层**的钩子（3 个文件，每层各一个方法）：

| 层 | 新增内容 |
|---|---|
| `game_data/skill_definition.gd` | `func ignores_card_distance_limit_to_target(_card_definition: Dictionary, _target_id: int) -> bool: return false`（默认不修改任何距离，与 `:734` 同文档风格） |
| `scripts/core/match_controller.gd` | `func skill_ignores_card_distance_limit_to_target(player_id, card_definition, target_id) -> bool`，聚合所有技能实例（镜像既有 `:8864 skill_ignores_card_distance_limit` 的遍历写法） |
| `scripts/core/card_rule_service.gd` | `_validate_target` 的 `ignore_distance_limit` 表达式上追加 `or _skill_ignores_card_distance_limit_to_target(actor.player_id, definition, target_id)`；并新增该私有聚合函数（镜像 `:498` 的写法） |

**该设计同时满足三个硬要求**：
1. **只对【杀】**：技能自己判断 `effect_id == "slash"`（与 `match_controller.gd:11958` 判定杀族时机的口径一致，覆盖普通/火/雷【杀】及视为【杀】的虚拟牌）。
2. **只对距离最远的角色**：技能自己判断 `_is_farthest_opponent(target_id)`。
3. **不影响其他任何距离牌**：钩子只在"用牌目标距离校验"这一条链上被询问，且默认返回 `false`；`calculate_distance()` 完全不动，因此距离**数值**本身不变，其他技能与界面的距离读取零影响。

**三处调用方同源，无需分别适配**：AI 动作枚举走 `_append_if_legal → validate_use()`（`docs/内容制作指南.md:291`）、UI 预览走 `rule_query.gd:57 card_usable → validate_use()`、最终提交走 `match_controller.gd:2224/2660`——全部经过 `_validate_target`，因此 AI 与界面会自动认可"对最远角色使用【杀】"合法。

> 三者都是新增函数或新增默认 `false` 的钩子，**不改既有签名、不改既有分支取值**，因此可以独立回滚（§13）。

---

## 4. 【连戏】改写（`game_data/skills/lianxi.gd`）

### 4.1 元数据与入口

| 项 | 旧 | 新 |
|---|---|---|
| `trigger` | `"active"` | `"phaseUseBegin"` |
| `ui_enabled` | `true` | `false` |
| `enable` | `["phaseUse"]` | `"phaseUse"` |
| `description` | 旧原文 | 新原文（R1.1 逐字） |
| `MAX_RECAST_TIMES` | `7` | `9` |
| `DAMAGE_DIVISOR` | `2` | `3` |

**常量与变量名一律保留**（协作规范「严禁擅自修改变量名」），只改值与注释中过期的数值描述。

### 4.2 生命周期（照抄【行军】的成熟形态）

- `install()` 订阅 `phaseUseBegin`（`role="player"`）。
- `can_activate()` 恒返回 `false`；`activate()` 返回提示文本；`append_play_phase_actions()` 不追加动作。三者与 `game_data/skills/xingjun.gd:36-48` 同形态。
- `phaseUseBegin` 回调：
  - 若手牌中**没有基本牌** → 不创建询问（与旧语义一致：重铸无事发生，不展示入口）。
  - 否则 `request_card_selection("连戏", "是否发动【连戏】？", [], 0, 0, true, {"kind":"lianxi_phase_use_begin", "ai_allow_confirm":true})`。
- `continue_selection` 新增 `lianxi_phase_use_begin` 分支：
  - 取消 → 本阶段结束，不移动任何牌、不消耗任何额度。
  - 确认 → 立刻创建**不可取消**的第一轮重铸窗口（`_request_recast_choice(0, false)`）。

### 4.3 链式重铸窗口

旧实现的重铸窗口由 `activate()` 创建，新实现由阶段 Begin 询问创建，因此必须补上**嵌套恢复**：

- `_execute_recast_round()` 执行完一次真实重铸后，若 `host.has_pending_card_choice()`（重铸触发了别的技能的嵌套选择，例如弃置类时机）→ `defer_settlement({"kind":"lianxi_recast_continue","recast_count":n})`；否则直接 `_request_recast_choice(n, false)`。
- 新增 `continue_settlement()` 处理 `lianxi_recast_continue` 并恢复重铸窗口。该模式与 `game_data/skills/xianzou.gd:46-80` 完全一致。

### 4.4 数值语义（保持不变的部分）

- 每轮把**当前全部基本牌一次性**置入弃牌堆并等量补摸（手牌张数不变）。
- 至少完成 1 次真实重铸后才出现「结束」选项；到上限后只剩结束选项。
- 结束时 `Y = ⌊重铸次数 ÷ 3⌋`；`Y = 0` 不创建目标选择、不产生伤害事件。
- 新数值对照：1~2 次 = 0、3~5 次 = 1、6~8 次 = 2、9 次 = 3。

### 4.5 AI

- `append_play_phase_actions()` 置空（阶段开始技能不追加主动动作）。
- 新增 `score_ai_choice()` 的 `lianxi_phase_use_begin` 分支：复用现有 `_score_lianxi_activation()`，把预期重铸轮数上限由 `7` 改为读取 `MAX_RECAST_TIMES`（消除硬编码字面量），确认必须**严格正收益**才发动。
- 重铸窗口与伤害目标选择的既有评分逻辑保留。

---

## 5. 【同袍】（`tongpao`，丹恒·腾荒）

### 5.1 静态定义

```gdscript
"reincarnation":true,
"reincarnation_section_count":4,
"reincarnation_has_explicit_sections":true,
"reincarnation_each_section_once_per_play_phase":true,
"trigger":"active", "enable":"phaseUse", "ui_enabled":true,
```

结构完全对标 `game_data/skills/kansha.gd`（4 节有序推进、每节每出牌阶段限一次）。

节索引常量：`DAMAGE_SELF_SECTION_INDEX=0`、`SHIELD_SECTION_INDEX=1`、`DISCARD_HAND_SECTION_INDEX=2`、`DISCARD_ZONE_SECTION_INDEX=3`。
数值常量：`SELF_DAMAGE_AMOUNT=1`、`SHIELD_AMOUNT=1`、`DISCARD_HAND_COUNT=1`、`DISCARD_ZONE_COUNT=1`。

### 5.2 四节效果与端口

| 节 | 效果 | 端口 |
|---|---|---|
| ① | 对自己造成 1 点**普通伤害**（护盾可吸收，不是「失去体力」） | `get_owner_skill_player().damage(SELF_DAMAGE_AMOUNT, get_owner_skill_player())` |
| ② | 令一名其他角色获得 1 点护盾 | `get_skill_player(target_id).shield(SHIELD_AMOUNT, get_owner_skill_player())` |
| ③ | 弃置自己一张**手牌**（装备牌不可作费用） | 候选 `get_hand_candidates(owner, owner)` → `discard_selected_hand_cards(owner, uids)` |
| ④ | 弃置一名其他角色**区域内**一张牌（手牌/装备/判定三区） | 两步：先选角色（区域内至少一张牌的其他存活角色），再 `get_player_zone_candidates(viewer=owner, target)` → `discard_selected_player_card(owner, target, uid)`（**带保护**，不使用绕过保护的 `discard_selected_judgment_card`） |

### 5.3 空节推进（强制）

②③④ 在「客观上没有可执行内容」（无其他存活角色 / 自己无手牌 / 目标区域全空）时：
- `can_activate()` **仍返回 `true`**（否则轮回永久卡死）；
- `activate()` 识别该情形并按选中 0 个目标直接完成本节：`begin_reincarnation_activation()` → `announce_activation({"empty_section":true,...})` → `complete_reincarnation_activation()`，不产生任何牌效、不改 `X`。

① 恒可执行（自伤总能成立）。

### 5.4 AI（按 R2.4 补全 + 通用分支）

- 节 ①：自身体力 ≥ 2 且存在**需要护盾的残血队友**（体力 ≤ 2 且态度为正）时才发动；否则**返回负分不发动**（有序推进下不发动①就永不到②，这是原文的固有代价，AI 不得为了推进而自伤）。
- 节 ②：目标取「态度为正、体力 ≤ 2、当前护盾最少」的角色；无合法队友时返回负分。
- 节 ③：费用取自己**最低价值**的手牌；若该手牌是全场最低价值且弃置有正收益（为④开路）时发动。
- 节 ④：按「判定区延时锦囊（【乐不思蜀】【兵粮寸断】等）优先 → 敌方装备 → 敌方手牌」分级评分；对队友判定区的负面延时锦囊返回**正分**（协助解围），对敌方返回正分，对队友的非负面牌返回负分。
- 所有评分复用 `NonameAIEvaluator.score_resource_change()` 与公开资源常量，不重复声明换算比例。

---

## 6. 【岳峙】（`yuezhi`，丹恒·腾荒，限定技）

### 6.1 静态定义

`"limited":true`（正文含「限定技」，基类亦会自动识别）、`trigger:"useCard"`、`ui_enabled:false`。

### 6.2 触发与改写

订阅**整牌时机 `useCard`**（属于 `CardUseEventService.USE_TIMING_NAMES`，**会**走 `_apply_card_rule_timing` 写回；不得使用 `useCardBefore/useCardBegin` 等不走写回的路径）。

回调逻辑：
1. 条件：`host` 有效、持有者存活在场、限定技额度可用（`has_available_intrinsic_use()`）、`event.data["target_ids"].size() >= 2`、该牌不是持有者正在进行的同一张牌（防重入）、且目标数组尚未被本技能改写。
2. 创建**可取消**布尔询问 `{"kind":"yuezhi_become_sole_target","card_uid":<uid>,"original_target_count":<X>,"card_definition_id":<id>}`。
3. `continue_selection` 确认后：
   - 调用 `host.call("replace_card_use_targets", card_uid, [owner_player_id] × X, get_id())`；
   - `announce_activation({"target_id":owner_player_id,"resolve_times":X,"card_uid":card_uid})`；
   - 把「结算期守卫」写入技能私有状态：`_guard_card_uid`、`_guard_active=true`、`_damage_resolved=false`、`_recover_resolved=false`。

> 持有者**不必是**该牌原本的目标之一（原文"你可成为该牌的唯一目标"是主动成为）。

### 6.3 结算期守卫（防止伤害 / 防止回复）

- 订阅 `damageBegin4`（`role="target"`，该窗口位于最终伤害数值确定后、护盾与体力扣减前）：若 `_guard_active` 且 `event.target_id == owner_player_id` 且伤害 > 0：
  - `_damage_resolved == true` → `event.cancel("yuezhi_guard")` 防止本次伤害；
  - 否则置 `_damage_resolved = true`，放行首次伤害。
- 订阅 `recoverBegin`（`role="target"`）同理：`_recover_resolved` 为真时取消本次回复，否则放行首次并置位。
- **「该牌结算完毕」的判定**：订阅该牌整牌尾时机 `useCardAfter`，当 `card_uid` 与 `_guard_card_uid` 一致时清除 `_guard_active` 与两个已发生标记。
  - 兜底：`uninstall()` 与持有者死亡/离场时一并清除，避免守卫泄漏到后续牌。

### 6.4 幂等与边界

- 同一张牌只允许改写一次（`_guard_card_uid` 比对 + `card_use_context` 已含重复目标时直接跳过）。
- 目标数 X 取**改写前**的原目标数（含持有者自己若原本在列）。
- 空目标数（X ≤ 1）不触发（原文"指定多名角色"）。
- 被改写掉的目标不会收到该牌的效果（因为目标数组被整体替换）。

### 6.5 AI（按 R2.7 补全 + 通用分支）

- 敌方**伤害类**多目标牌（`ai.damage == true` 或 `nature_damage`）：若我方（态度为正的角色）中存在体力 ≤ 2 者，且原目标数 X ≥ 2 → 返回正分发动（净收益 ≈ 替队友挡下的伤害 − 自己承受的 1 点）。
- **正收益**多目标牌（`ai.beneficial == true`，如【五谷丰登】【桃园结义】）：当原目标中敌方数量多于我方时 → 返回正分（剥夺敌方收益 + 自己获得 X 次收益）；我方居多时返回负分。
- 其他情况返回 ≤ 0，不发动。
- 补全的通用部分：限定技额度耗尽后不产生任何动作；己方 1 血时不发动（避免自救失败）。

---

## 7. 【断界】（`duanjie`，瓦尔特）

### 7.1 静态定义

`trigger:"active"`、`enable:"phaseUse"`、`ui_enabled:true`。

常量：`OPTION_LINK_TARGET=1`、`OPTION_UNLINK_TARGET=2`、`OPTION_TURN_FACE_UP=3`、`OPTION_TURN_FACE_DOWN=4`、`INITIAL_OPTION_COUNT=4`。

### 7.2 状态与消耗语义

**存储位置的选择依据**（两个约束必须同时满足：可存档 + 可被复原）：

| 候选位置 | 随存档往返 | 随「复原武将牌上的技能」清零 |
|---|---|---|
| 技能实例字段 | ✗ 读档后实例重建，进度丢失（可被存档-读档刷回） | ✓ 重建实例天然归零 |
| `PlayerState.character_form_state` | ✓ 进权威存档、不进公开快照 | ✗ 项目刻意不清（【薪继】依赖该特性） |

因此采用**组合方案**：存 `character_form_state`，并由技能自己订阅 `changeSkillsAfter` 在复原时清除。

- **键**：`character_form_state["duanjie_remaining_options"]`，形如 `[1,2,3,4]`。
- **惰性初始化**：键**缺失**即代表完整初始列表（返回 `[1,2,3,4]` 的副本），"键存在"等价于"已经删除过选项"。因此 `install()` **不需要**写初始值，复原只需 `erase` 该键。
- **复原订阅**：`install()` 中 `subscribe_timing("changeSkillsAfter", _on_change_skills_after, "player")`；回调内只在 `change_type` 为 `restore_character_card_skills` / `replace_character_card` 且 `skill_ids` 含 `"duanjie"` 时 `erase` 该键。
  - **必须过滤 `change_type`**：`restore_limited_skill_use`（单项复原限定额度，`:4408`）派发同一时机，但它不应重置选项列表。
  - 该时机在本项目**没有任何既有订阅者**（与 §3.2 的次数钩子同类情况），因此其"新实例能收到自己在 `install()` 中订阅的这次派发"这一时序必须在 M0 验证：派发点 `:4372` 位于 `install()` 之后，故新实例应当能收到。
- **每次发动流程**：任选当前列表中**有合法目标**的一项执行 → 执行完毕后 `pop_back()` 删除**列表最后一项**。
- **可用范围**：`{1,2,3,4}` → `{1,2,3}` → `{1,2}` → `{1}`；第四次发动后列表为空，技能不可再发动。
- 「出牌阶段限一次」用技能实例字段 + `phaseUseBegin` 重置（与既有主动技能同口径；该额度本就应随复原清零，与实例字段语义一致）。

### 7.3 选项效果

| 选项 | 合法目标 | 执行 |
|---|---|---|
| 1 横置 | 当前**未横置**的存活在场角色（含自己） | `set_player_linked(target, true, owner, get_id())` |
| 2 竖置 | 当前**已横置**的存活在场角色 | `set_player_linked(target, false, owner, get_id())` |
| 3 翻至正面 | 当前**背面向上**的存活在场角色 | 先判 `face_down == true` 再 `turn_over_player(target, owner, get_id())` |
| 4 翻至背面 | 当前**正面向上**的存活在场角色 | 先判 `face_down == false` 再 `turn_over_player(target, owner, get_id())` |

> 翻面**没有绝对设置端口**，只有 `turn_over_player()` 切换；因此必须前置状态判断后才能调用（`docs/内容制作指南.md:554` 禁止直接写字段）。

### 7.4 交互

- 用 `request_control_selection` 提供当前可用选项（选项 ID 用稳定字符串，标签显示 1/2/3/4 的原文描述）。
- 选定后再 `request_target_selection` 选择该选项的目标；取消任一步都不删除列表项、不消耗本阶段额度。
- 若无任何选项存在合法目标 → `can_activate()` 返回 `false`（技能熄灭，符合"没有能做的事"直觉，且不涉及轮回推进，不存在卡死风险）。

### 7.5 AI

- 首次发动（列表含 4）→ 优先选项 4（选项 4 之后永久消失，是唯一使用窗口），目标取「正面向上、态度最负、行动顺序最靠前」的敌人。
- 后续发动：对队友使用选项 2（若已横置）或 3（若背面）；对敌人使用选项 1（若未横置）。
- 所有候选为负收益时（例如只剩选项 1 且无未横置敌人）→ 返回 ≤ 0，不发动。

---

## 8. 【遥击】（`yaoji`，彦卿）

### 8.1 静态定义

`"lock":true`（锁定技）、`trigger:"passive"`、`ui_enabled:false`。

### 8.2 实现路径

覆盖 §3.3 新增的带目标距离钩子：

```gdscript
func ignores_card_distance_limit_to_target(card_definition: Dictionary, target_id: int) -> bool:
	# 只对【杀】生效；【顺手牵羊】等任何其他距离敏感牌完全不受影响。
	if not _is_slash_definition(card_definition):
		return false
	# 只对距离与持有者最远的角色生效；距离不足时不得放宽。
	return _is_farthest_opponent(target_id)
```

- `_is_slash_definition()` 读 `effect_id == "slash"`（与 `match_controller.gd:11958` 判杀族时机的口径一致），覆盖普通/火/雷【杀】，也覆盖技能视为的【杀】（虚拟牌同样经 `_validate_target`）。
- 该钩子只在**用牌目标的距离校验**处被询问，且**完全不改** `calculate_distance()`，因此距离数值本身不变，其他技能与界面对距离的读取零影响。
- **不需要**提取"距离视为 1"之类的覆写常量——本方案不动距离数值。

**明确不采用的两个方案**（记录理由，防止后续误改）：

| 方案 | 为什么不用 |
|---|---|
| `ignores_card_distance_limit(card_definition)` | 无目标参数 → 会让【杀】对**所有**角色解限，违背"对距离与你最远的角色"这一限定 |
| `modify_distance_to_target(target_id, current_distance)` | 无牌参数 → 会同时放宽【顺手牵羊】【借刀杀人】等**所有**距离敏感牌，且污染距离数值本身 |

### 8.3 最远判定

```gdscript
func _is_farthest_opponent(target_id: int) -> bool
```
- 遍历 `host.state` 的存活且在场的**其他**角色，逐个 `host.card_rules.calculate_distance(owner_player_id, p)`。
- **必须先过滤死亡与离场**：`calculate_distance` 对无效目标返回 `999`，不过滤会污染最大距离。
- 与最大值相等的**并列角色全部**满足条件（原文未要求唯一）。
- 无人可比（1v1）时按"并列最远"处理（对唯一对手生效）。

### 8.4 AI

- 【遥击】是锁定技，无主动入口，不需 `append_play_phase_actions`。
- **AI 合法动作枚举无需额外适配**：AI 的标准动作走 `_append_if_legal → validate_use()`（`docs/内容制作指南.md:291`），与 UI 预览、最终提交共用 `_validate_target`，因此"对最远角色使用【杀】"会自动成为合法动作。
- 补全通用决策：覆盖 `modify_ai_card_action_score()`，对"态度为负且距离最远"的目标补充可达性收益，使 AI 在多个可打目标中优先选择原本打不到的最远敌方角色。

---

## 9. 【凌霜】（`lingshuang`，彦卿）

### 9.1 静态定义

`trigger:"useCardToTargeted"`（使用者视角的逐目标时机）、`ui_enabled:false`、非锁定技。

> 时机选择说明：原文「当你使用【杀】指定目标时」是**使用者**语义，因此以 `role="source"` 订阅逐目标时机；必须确认订阅的是会走 `_apply_card_rule_timing` 的四组 `useCardTo*` 之一（不使用 `useCardToBefore/Begin/End/After`）。

### 9.2 效果

1. 条件：`event` 的牌 `effect_id == "slash"`、来源是持有者、目标存活在场、持有者本张牌尚未发动过本技能。
2. 创建**可取消**布尔询问 `{"kind":"lingshuang_turn_over","card_uid":<uid>,"target_id":<目标>}`。
3. `continue_selection` 确认后：
   - 记录翻转前状态 `was_face_down = owner.face_down`；
   - `turn_over_player(owner_player_id, owner_player_id, get_id())`；
   - 若 `was_face_down == false`（本次由**正面翻至背面**）：
     - 弃置目标角色两张手牌：候选 `get_hand_candidates(viewer=owner, target=目标)`（他人手牌候选 `visible=false`，即**盲选**，与 `game_data/skills/jianying.gd` 的既有口径一致），`discard_selected_hand_cards(目标, uids)`（不足两张时弃置其全部手牌）；
     - 令此【杀】不计入次数：`host.call("mark_card_use_limit_exempt", owner_player_id, card_definition_id)`（§3.2）；
   - 若 `was_face_down == true`（背面翻回正面）：只有翻面本身，无附加效果。
4. `announce_activation({"target_id":目标, "face_down":<翻转后>, "discarded_count":n, "limit_exempted":bool})`。

### 9.3 幂等

- 同一张【杀】的多个目标：每个目标各自触发一次，但只有**第一次**（正面→背面）带附加效果；后续触发时 `was_face_down == true`，自然退化为纯翻面。这与原文"若你因此翻至背面向上"的条件完全吻合。
- `mark_card_use_limit_exempt` 对同一张牌由技能侧的 `_exempted_card_uids` 标记保证只调用一次。

### 9.4 AI（按 R4.5 补全 + 通用分支）

- 目标手牌数 ≥ 2 且态度为负（敌人）→ **无条件**返回正分发动（原文提示）。
- 其他情形按通用翻面成本估值：翻面会跳过持有者下个完整回合（`turn_start_service.gd:90-125`），成本按「下一次出牌阶段机会成本 + 回合内资源损失」折算；只有收益（弃牌 + 次数豁免 + 对敌压制）严格大于成本才发动。
- 补全的通用部分：持有者已是背面时发动只翻回正面（净收益为正的"解除翻面"），此时按 `+1.0` 级别的解除惩罚评分；持有者 1 血且被翻面会跳过回合导致无法自救时返回强负分。

---

## 10. 三个武将定义

| 文件 | `id` | 显示名 | 性别 | 势力 | 体力 | 技能顺序 |
|---|---|---|---|---|---|---|
| `game_data/characters/danheng_tenhuang.gd` | `danheng_tenhuang` | 丹恒·腾荒 | male | `wengfaluosi` | 4 | 【同袍】→【岳峙】 |
| `game_data/characters/waerte.gd` | `waerte` | 瓦尔特 | male | `xingqionglieche` | 4 | 【断界】 |
| `game_data/characters/yanqing.gd` | `yanqing` | 彦卿 | male | `xianzhou` | 3 | 【遥击】→【凌霜】 |

技能以 `preload` 常量注入 `super({...}, [SKILL_A, SKILL_B])`，与 `game_data/characters/huohua.gd`、`danheng.gd` 同形态。三个势力 ID 已存在于 `game_data/factions.json`，**无需新增势力**；插画缺失按占位图处理，不产生校验错误。

---

## 11. 数据、存档、回放与网络

| 状态 | 存放位置 | 理由 |
|---|---|---|
| 【断界】剩余选项列表 | `PlayerState.character_form_state["duanjie_remaining_options"]` | 必须**同时**满足"随权威存档往返"与"可被复原武将牌清零"；技能自己订阅 `changeSkillsAfter` 清除该键（§7.2） |
| 【岳峙】结算期守卫 | 技能实例字段 | 生命周期严格限定在**一张牌的一次结算**内，跨帧但不出对局边界；并在 `uninstall()` / `useCardAfter` 双重清理 |
| 【同袍】轮回进度 | `PlayerState.reincarnation_skills`（由 `ReincarnationSkillService` 托管） | 复用既有权威服务，不自行存进度 |
| 【凌霜】本张牌已豁免标记 | 技能实例字段（按 `card_uid` 记录） | 单张牌生命周期，随 `useCardAfter` 清理 |
| 各技能「本阶段已发动」 | 技能实例字段 + `phaseUseBegin` 重置 | 与既有主动技能同口径 |

`context` 中只允许出现**可序列化**数据（整数 ID、字符串、数组、字典）；**禁止**节点、`PlayerState`、`CardInstance`、`Callable`。

---

## 12. 兼容性与影响面

- **不影响其他武将/卡牌**：五个技能都是新增内容；【连戏】的非数值改动只影响火花自身，其数值改动不改变任何其他技能的算式。
- **不改** `BasicAIPolicy` 白名单、不改通用 AI 常量（§6 中 `docs/AI模块.md` 的全局数值一律不动）。
- `docs/内容制作指南.md` 需新增三处核心扩展的说明章节（含新距离钩子的签名与"为什么必须带目标参数"的理由），并更新「两种用牌次数语义」（§3.2 补上"事后豁免"入口）与「当前正式武将技能」列表。
- `docs/游戏机制与玩法内容.md` 需记录全部新增数值（9 次上限、除数 3、护盾 1、自伤 1、弃置 2 张、X = 原目标数、选项消耗序列等），并更新【连戏】条目。
- `README.md` 需更新 `huohua_joy_test` 的描述与新增专项测试的运行说明。

---

## 13. 风险、降级与回滚

| 风险 | 等级 | 缓解 |
|---|---|---|
| 重复目标结算在某类牌上不幂等（例如群体锦囊的响应流程被触发 X 次） | 中 | **implement 第 1 步先做最小运行时验证**（见 `implement.md` M0），确认后再写技能；若某牌族异常，收敛到"保证原文语义"的最小范围并在 `docs/` 记录，**原文不改** |
| `useCard` 时机创建异步询问后，改写未落到等待窗口 | 中 | 直接用 M0 验证脚本覆盖"询问→改写→重复结算"全链路；端口复用既有 `_find_pending_card_timing_event` 定位逻辑 |
| 【凌霜】次数豁免被 declare 快照覆盖 | 中 | M0 验证「使用【杀】→ 发动【凌霜】→ 本阶段可再使用一张【杀】」 |
| `<【杀】不计入>` 与 `ignores_play_count_limit` 两类语义混用 | 低 | 严格按 `docs/内容制作指南.md:4084-4085` 的两条链分别实现，不交叉 |
| 【断界】`changeSkillsAfter` 是零订阅者时机，新实例可能收不到自己刚订阅的那次派发 | 中 | M0 验证项 G：复原后断言选项列表确实回到 4 项、且单项复原限定额度不会误触发；若时序不成立，退化为技能实例字段并在 `docs/` 记录"读档会丢失进度"的已知边界，**回报用户后再定** |
| 【遥击】新增钩子改动了 `_validate_target` 的既有布尔表达式 | 低 | 新钩子默认返回 `false` 且无既有技能覆盖它，既有技能的返回集合不变；配 M0 的距离回归用例（对最远角色合法、对非最远角色仍非法、【顺手牵羊】等不受影响） |
| 【同袍】有序轮回在某节长期无内容导致轮回停滞 | 低 | 强制空节推进（§5.3），`can_activate()` 不因无候选返回 `false` |

**回滚粒度**：
1. 五个技能各自独立成文件 → 删除新增文件即回滚该武将（需同步回滚武将定义与测试）。
2. 【连戏】的改动集中在单文件，`git checkout` 单文件即回滚。
3. 三处核心扩展都是**纯新增函数**，或**默认返回 `false` 的新钩子** → 删除即回滚，不影响任何既有路径；唯一需要额外还原的是 `_validate_target` 中追加的那个 `or` 分支。

---

## 14. 验证策略

- **数据关**：`GameDatabase.validation_errors` 为空且可正常开局（内容新增的第一道关）。
- **专项测试**：更新 `tests/huohua_joy_test.gd`（连戏新时机/新算式/无基本牌不询问），新增新武将专项测试（三个武将定义、五个技能正文与参数、五条完整结算链路）。
- **AI 回归**：`tests/ai_policy_test.tscn`（新技能不得产生非法动作、不得影响既有卡牌 AI）。
- **核心回归**（因新增三处核心扩展）：`tests/gameplay_regression_test.tscn`、`tests/event_runtime_test.tscn`、`tests/skill_settlement_runtime_test.tscn`、`tests/phase_progression_test.tscn`（阶段 Begin 询问 + 翻面 + 次数语义）。
- **距离回归**（因新增距离钩子链）：断言"持【遥击】者对距离最远的角色使用【杀】合法、对非最远角色仍非法"，且【顺手牵羊】等其他距离敏感牌的可选目标集合与改动前**完全一致**。
- **内容增长稳定性**：复核依赖固定种子的既有测试是否因新增武将被抽到而失效（不要假设候选首项可用）。
- 判定标准：退出码 0 + 自身 `*_PASS` 标记 + 日志无 `ERROR`/`SCRIPT ERROR`/`FAIL`。

---

## 15. M0 实测结论（已回填）

`tests/tmp_m0_probe_test.gd` 的真实输出（末行 `M0_PROBE_PASS`）：

```
M0_OBS B fire_count=1 hp=7 (7=重复结算生效, 5=仅一次, 4=改写未生效)
M0_OBS E fire_count=1 target_id=1 card_uid=2 target_ids=[1]
M0_OBS G fire_count=1 change_type=restore_character_card_skills skill_ids=["haoxi", "lianxi"]
M0_OBS D before="本阶段使用【杀】的基础次数已用尽。" after="" grouped_count=0
M0_OBS C rewrite_attempted=true hp=5 (5=改写被结果提交覆盖, 7=只写共享上下文也生效)
```

### 15.1 结论与对设计的确认

| 假设 | 结论 | 对设计的影响 |
|---|---|---|
| A/B 重复目标多次结算 | **成立**（【桃园结义】重复 3 次回复：4→7） | §6【岳峙】的"唯一目标 × 结算 X 次"可实现，**无需为此新增核心能力** |
| C 只写共享上下文被覆盖 | **成立且确实被覆盖**（`hp=5`，改写无效） | §3.1 `replace_card_use_targets` **必要**；这是【岳峙】能生效的前提 |
| D 事后次数豁免 | **成立**（拒绝信息消失，净计数 1→0） | §3.2 `mark_card_use_limit_exempt` 的设计前提成立，**无需改校验分支** |
| E `useCardToTargeted` role=source | **成立**（拿到 `card_uid` 与 `target_ids`） | §9【凌霜】可在此时机驱动 |
| G `changeSkillsAfter` 可订阅 | **成立**（`change_type` 与 `skill_ids` 均可读） | §7.2【断界】的"可存档 + 可复原"组合方案成立 |
| F 距离钩子三层贯通 | 待 M1 验证门补测 | §3.3 |

### 15.2 与规划不同的两处实测修正

1. **观测用牌改用【桃园结义】**：原计划用【五谷丰登】，实测发现它会**为每个目标创建选牌请求**（`wugufengdeng.gd:101` 的 `request_card_choice`），带交互，无法干净观测"到底结算了几次"。改用【桃园结义】（`taoyuanjieyi.gd:42` 只有一行 `resolver.host.recover`，无任何交互）。
2. **A 与 B 合并验证**：二者共用同一 content 结算机制，一次观测即可互相推及，不必拆成两项。

### 15.3 一个额外发现（对【岳峙】AI 有价值）

【桃园结义】的卡牌元数据带 `"multitarget":true, "beneficial":true`（`taoyuanjieyi.gd:31`）。这正是 §6.5【岳峙】AI 分支所依赖的"正收益多目标牌"判据，**可直接读牌定义而无需硬编码牌名**，与项目"不硬编码"的约束一致。
