# 青雀武将与三技能 · 技术设计

> 权威需求见 `prd.md`。本文件只描述**怎么做**：新增/复用的机制端口、数据与状态、时序、AI、测试与文档同步。

---

## 0. 结论速览

| 编号 | 交付物 | 类型 | 是否新增核心端口 |
|---|---|---|---|
| A | 卡牌「是否为伤害牌」字段 + 9 张牌标注 | 静态数据 + 基类只读入口 | 否 |
| B | 「禁止使用/打出手牌」通用纯查询钩子（【独弈】用） | 新机制 | **是**（技能钩子 + 控制器聚合 + 2 处消费点） |
| C | 为牌时机暴露「使用牌的花色/颜色」（【弃和】用） | 新机制 | **是**（3 行核心写入/导出） |
| D | 技能公开「以此法使用过的牌名」容器（【自摸】用） | 新机制 | **是**（状态字段 + 2 个端口） |
| E | 技能自身「出牌阶段额度」动态 1→2（【自摸】用） | 技能内部实现 | 否 |
| F | 阶段跳过 + 随机保留花色（【独弈】用） | 复用现有端口 | 否 |
| G | 随机弃牌 + 令牌对自身无效（【弃和】用） | 复用现有端口 | 否 |
| H | 虚拟手牌选择请求（【自摸】“视为使用”用） | 新机制 | **是**（技能基类 1 个端口 + `match_table.gd` 一层虚拟手牌模式） |

**核心改动面**：`game_data/skill_definition.gd`（+1 钩子、+1 虚拟手牌请求端口）、`game_data/card_definition.gd`（+1 只读入口）、`scripts/core/match_controller.gd`（+1 聚合 + 1 处候选过滤 + 3 行时机数据 + 2 个端口）、`scripts/core/card_rule_service.gd`（+1 禁令咨询 + 2 个虚拟牌公开查询）、`scripts/data/player_state.gd`（+1 公开字段）、`scripts/ui/match_table.gd`（虚拟手牌渲染模式）。**无任何技能 ID / 牌名白名单进入核心层。**

---

## 1. 数据与静态内容

### 1.1 卡牌「是否为伤害牌」

**定义口径**：使用此牌时，其**自身效果**会对目标造成伤害 → `is_damage = true`。

- 基类 `game_data/card_definition.gd` 新增只读入口：

```gdscript
## 当前卡牌是否为伤害牌；true表示使用此牌时其自身效果会对目标造成伤害。
## 该字段是【弃和】等“成为伤害牌目标”类内容的唯一判定依据，内容层禁止另建牌名白名单。
## 元数据缺失时按 false 处理，因此新增卡牌默认不是伤害牌。
func is_damage_card() -> bool:
	return bool(_metadata.get("is_damage", false))
```

- 9 张牌在 `_init()` 的 `super({...})` 字典中新增**顶层**键 `"is_damage":true`（与 `type`/`effect_id` 同级，不放进 `ai` 子字典）：

| 文件 | `id` | 伤害来源 |
|---|---|---|
| `game_data/cards/sha.gd` | `sha` | 【杀】 |
| `game_data/cards/huosha.gd` | `sha_fire` | 火【杀】 |
| `game_data/cards/leisha.gd` | `sha_thunder` | 雷【杀】 |
| `game_data/cards/juedou.gd` | `juedou` | 【决斗】 |
| `game_data/cards/nanmanruqin.gd` | `nanman` | 【南蛮入侵】 |
| `game_data/cards/wanjianqifa.gd` | `wanjian` | 【万箭齐发】 |
| `game_data/cards/huogong.gd` | `huogong` | 【火攻】 |
| `game_data/cards/shuiyanqijun.gd` | `shuiyanqijun` | 【水淹七军】 |
| `game_data/cards/shandian.gd` | `shandian` | 【闪电】（延时，判定结算时造成 3 点雷电伤害） |

- **保留 `ai.damage` 原样不动**：`ai.damage` 是「AI 估值口径」，`is_damage` 是「规则事实口径」。两者当前对这 9 张牌完全一致，但语义独立；`yongjie.gd` 等既有读取点继续读 `ai.damage`，本次不改既有行为。
- 不新增 `GameDatabase` 校验（避免对既有 44 张牌引入新的失败面）；一致性由 `tests/qingque_mechanics_test.gd` 断言「9 张 `is_damage` 牌与 `ai.damage` 集合完全相等」。

### 1.2 武将 `game_data/characters/qingque.gd`

```gdscript
extends CharacterDefinition

## 【青雀】武将源码。武将通过三个独立技能组件组合“锁手牌的自闭过牌”与“无实体牌的视为使用”：
## 【独弈】与【弃和】是锁定技，分别限制自身用牌方式与抵消来袭伤害牌；
## 【自摸】是主动技，用手牌花色数决定“摸牌视为使用”或“弃一色换两次发动”两条分支。

## 【独弈】技能脚本；负责手牌基本牌与锦囊牌的使用/打出限制、弃牌阶段的随机保留与阶段跳过。
const DUYI_SKILL: Script = preload("res://game_data/skills/duyi.gd")

## 【弃和】技能脚本；负责成为伤害牌目标时的同花色随机弃牌与令牌无效。
const QIHE_SKILL: Script = preload("res://game_data/skills/qihe.gd")

## 【自摸】技能脚本；负责出牌阶段的虚拟手牌选牌、视为使用与出牌阶段限次改写。
const ZIMO_SKILL: Script = preload("res://game_data/skills/zimo.gd")

func _init() -> void:
	super({
		"id":"qingque",
		"display_name":"青雀",
		"gender":"female",
		"faction":"xianzhou",
		"max_hp":3,
		"description":"仙舟联盟的摸鱼棋手，只与自己对弈：既不碰手牌中的基本牌与锦囊牌，也总能从对手的杀招里舍掉一张以自保。",
	}, [DUYI_SKILL, QIHE_SKILL, ZIMO_SKILL])
```

- 势力 `xianzhou` 已在 `game_data/factions.json` 登记，**无需改动**。
- 不填 `art_path`；插画与阵亡语音缺失不报错（占位图 / 静默）。
- 技能数组顺序 = 技能栏顺序 = 安装顺序：`duyi → qihe → zimo`。

### 1.3 三个技能文件的静态元数据

| 技能 | `id` | `lock` | `ui_enabled` | `enable` | `trigger` |
|---|---|---|---|---|---|
| 独弈 | `duyi` | `true` | `false` | — | `"passive/phaseDiscardBegin"` |
| 弃和 | `qihe` | `true` | `false` | — | `"passive/useCardToTargeted"` |
| 自摸 | `zimo` | `false`（默认） | `true` | `"phaseUse"` | `"active/phaseUse"` |

`trigger` 只作静态元数据（与【看破】`passive/useCardToTargeted`、【灵感】`active/phaseUse` 同口径），真正的时机注册在各自的 `install()` 中完成。

【独弈】【弃和】的 `description` 以「锁定技」开头 ⇒ 全目录回归 `tests/requested_changes_test.gd:159-170` 会强制校验 `lock == true`，**必须显式写 `"lock":true`**。

---

## 2. 新机制 B：禁止角色使用/打出实体牌（【独弈】核心）

### 2.1 问题

现网 9 个技能纯查询修正器全部只能**放宽**规则（忽略次数、加距离、允许自己为目标…），没有任何端口能**收紧**「能否使用/打出这张牌」。因此必须新增一个**通用纯查询钩子**。

### 2.2 技能基类钩子（`game_data/skill_definition.gd`）

```gdscript
## 判断技能持有者当前是否被禁止使用或打出某张实体牌；返回空字符串表示允许，否则返回玩家可见的拒绝原因。
## 纯查询：不得消费次数、移动牌、创建选择或写入任何状态；同一张牌可能被多个技能依次否决。
## 只对所有已安装技能聚合，且与“牌目标筛选”分开：本钩子回答“能不能用这张牌”，不回答“能打给谁”。
func validate_card_action_permission(_card: CardInstance, _card_definition: Dictionary, _card_action: String) -> String:
	return ""
```

- `_card_action` 取稳定字符串 **`"use"`（使用）** 与 **`"respond"`（打出/响应）**；常量由调用方（核心层）定义，技能只比较字面量。

### 2.3 控制器聚合（`scripts/core/match_controller.gd`）

在 `validate_skill_card_target_selection`（`:9786`）旁新增同构聚合入口：

```gdscript
## 汇总指定角色全部已安装技能对“能否使用/打出这张实体牌”的限制；空字符串表示允许。
## 与 validate_skill_card_target_selection 并列但语义不同：本入口在目标筛选之前生效，
## 因此被禁止的牌不会进入任何目标枚举、界面候选或AI合法动作。
func validate_skill_card_action_permission(player_id: int, card: CardInstance, card_action: String) -> String:
	# 当前玩家技能实例表；遍历顺序与技能栏、安装顺序一致，拒绝原因因此稳定可复现。
	var player_skills: Dictionary = skill_instances_by_player.get(player_id, {}) as Dictionary
	for skill_variant: Variant in player_skills.values():
		# 当前技能实例；纯查询，不在此消费任何额度或牌。
		var skill: SkillDefinition = skill_variant as SkillDefinition
		if skill == null or not skill.can_use_effect():
			continue
		# 当前牌面定义；实体牌缺失时使用空定义，由技能按自身口径处理。
		var definition: Dictionary = GameDatabase.get_card(card.definition_id) if card != null else {}
		var validation_error: String = skill.validate_card_action_permission(card, definition, card_action)
		if not validation_error.is_empty():
			return validation_error
	return ""
```

### 2.4 两个消费点

1. **`scripts/core/card_rule_service.gd` `validate_use`（`:90`）**：**插在 `target_mode == "response_only"` 判定（`:103-104`）之后、阶段使用次数计算（`:106`）之前**——「这张牌本身不能用」优先于「次数用尽」，拒绝文案因此稳定：

```gdscript
# 手牌用牌禁令（技能纯查询）；返回非空表示整张牌不可使用，与目标无关，因此必须早于目标校验。
var action_permission_error: String = str(skill_rule_provider.call("validate_skill_card_action_permission", actor.player_id, card, "use"))
if not action_permission_error.is_empty():
	return action_permission_error
```

  这一处即覆盖：`get_legal_actions`（AI 与界面合法动作枚举，内部经 `_append_if_legal`）、`get_card_use_preview`（界面预览）、`_prevalidate_play_action`（AI 预校验）、`submit_action`（真人 / AI / 联机房主的唯一权威提交入口）。

2. **`scripts/core/match_controller.gd` `_build_response_choice_candidates`（`:5201`）**：在遍历 `player.get_playable_cards()` 时，跳过被禁止打出的手牌：

```gdscript
# 打出禁令（技能纯查询）；被否决的手牌不进入任何响应窗口，
# 因此真人界面、AI 响应与联机验证读取同一份候选。
if card.zone == "hand" and not validate_skill_card_action_permission(player.player_id, card, CARD_ACTION_RESPOND).is_empty():
	continue
```

  装备区的响应候选（`:5222`）不受影响：禁令只针对实体手牌，且【独弈】只封锁基本牌与锦囊牌。

### 2.5 刻意不咨询的地方

| 位置 | 为何不咨询 |
|---|---|
| `validate_virtual_use` | 无实体虚拟牌不来自手牌；技能制造的虚拟牌不属于「手牌中的牌」，原文明确不受限 |
| `validate_play_phase_action`（装备主动动作） | 装备牌与装备主动动作均不在【独弈】封锁范围 |
| `recast_hand_card` / `_prevalidate_play_action` 的 `recast_card` 分支 | **重铸不是「使用」也不是「打出」**，因此青雀仍可重铸手牌锦囊 |
| 木牛流马「粮」（`zone == "wooden_ox"`） | 「粮」不是手牌；按原文严格口径不受限。**区域判定写在内容层（`duyi.gd`）**，核心层不含任何区域白名单 |

### 2.6 【独弈】钩子实现（`game_data/skills/duyi.gd`）

```gdscript
## 被封锁的牌类别；原文只封锁基本牌与锦囊牌，装备牌仍可正常使用。
const BLOCKED_TYPES: Array[String] = ["basic", "trick"]

## 封锁生效的区域；原文限定为“手牌中的”，木牛流马“粮”与装备区因此不受影响。
const BLOCKED_ZONE: String = "hand"
```

`validate_card_action_permission` 返回示例：`"【独弈】：你不能使用或打出手牌中的基本牌和锦囊牌。"`（按动作区分「使用」/「打出」前缀，便于信息框展示）。

---

## 3. 新机制 C：为牌时机暴露使用牌的花色/颜色（【弃和】核心）

### 3.1 问题

`useCardToTargeted` 时机数据由 `_build_card_use_timing_data`（`:12900`）与 `_execute_card_use_timing_event`（`:13506`）构造，**只有 `card_uid` 与 `card_id`，没有花色**，而【弃和】必须比较「此牌花色」与「手牌花色」。运行时也没有「查询处理区某张牌花色」的公开端口（`get_processing_candidates` 依赖处理区时序，不做为首选依据）。

### 3.2 改动（3 处，纯附加）

1. `_execute_card_use`（`:13238`）写入共享上下文：

```gdscript
"card_suit":virtual_card.suit,
"card_color":virtual_card.get_color(),
```

2. `_build_card_use_timing_data`（`:12903`）导出：

```gdscript
"card_suit":str(card_use_context.get("card_suit", "none")),
"card_color":str(card_use_context.get("card_color", "none")),
```

3. `_execute_card_use_timing_event`（`:13506`）的 `timing_data` 同步导出同名两键。

**语义**：`card_suit` / `card_color` 是**逻辑牌**的花色与颜色（实体牌取实体花色；多材料转化取聚合花色；无材料虚拟牌为 `none`）。附加只读键不影响既有技能（它们只读自己认识的键），也不参与 `_apply_card_rule_timing` 的回写（该方法只回写 `target_ids` / `excluded_target_ids` / `direct_hit_target_ids` / `custom_args`）。

---

## 4. 新机制 D：技能公开「以此法使用过的牌名」（【自摸】核心）

### 4.1 存储（`scripts/data/player_state.gd`）

```gdscript
## 各技能按自身语义记录的“已以此法使用过的牌名”公开容器；键为稳定技能ID，值为牌名ID数组。
## 与 recorded_card_names 分开保存：【解构】【灵感】【看破】共用后者，语义不可混用。
## 公开可见、随存档往返、可被AI钩子通过权威快照读取，因此不使用私有的 character_form_state。
var skill_used_card_names: Dictionary = {}
```

- `to_dict()` 中与 `recorded_card_names` 并列输出 `"skill_used_card_names": skill_used_card_names.duplicate(true)`（公开，不随 `reveal_private` 裁剪）。
- 静态存档恢复函数中新增 `player.skill_used_card_names = (data.get("skill_used_card_names", {}) as Dictionary).duplicate(true)`（旧存档缺键 → 空字典，语义安全）。

### 4.2 端口（`scripts/core/match_controller.gd`，与 `record_card_name` / `get_recorded_card_names`（`:10607`/`:10638`）同构）

```gdscript
## 为一个技能登记一条“已以此法使用过”的牌名；重复登记幂等，成功写入后广播公开快照。
func add_skill_used_card_name(player_id: int, skill_id: String, definition_id: String) -> bool

## 读取指定技能已经以此法使用过的牌名副本；未登记或角色无效时返回空数组。
func get_skill_used_card_names(player_id: int, skill_id: String) -> Array[String]
```

- 内部保存在 `player.skill_used_card_names[skill_id]`（`Array[String]`）。
- 【自摸】的读取集合 = 该数组 ∪ 该数组以外无内容；牌名去重由端口保证幂等。

### 4.3 公开可查

- 每次登记后调用 `host.call("set_skill_display_description", owner_player_id, get_id(), 展示文本)`：展示文本 = 原文 + 换行 + `（已以此法使用：A、B）`；集合为空时传空串清除（恢复静态正文）。
- 静态 `description` 元数据**永不改写**，`smoke_test` / `requested_changes_test` 的逐字断言因此不受影响。

---

## 5. 新机制 E：【自摸】的出牌阶段额度 1 → 2

### 5.1 为什么不需要核心端口

现网唯一的技能阶段额度端口 `reset_skill_play_phase_usage`（`:4732`）**只能归零**；「限两次」在核心层没有任何表达（`zhuxv.gd` 的 `PLAY_PHASE_LIMIT = 2` 只是它自己的常量）。而【自摸】的额度是**本技能自己的私有事实**，因此**在技能内部实现**，不新增核心表：

```gdscript
## 基础阶段额度；数值1来自原文“出牌阶段”（限一次）语义。
const BASE_PLAY_PHASE_LIMIT: int = 1

## 分支二提升后的阶段额度；数值2来自原文“出牌阶段限两次”。
const EXTENDED_PLAY_PHASE_LIMIT: int = 2

## 当前出牌阶段已发动次数；沿用基类 PLAY_PHASE_USAGE_FIELDS 约定命名，可被 reset_play_phase_usage 归零。
var _used_this_play_phase: int = 0

## 额度提升生效的回合序号；-1表示未提升。按回合号比较而不是布尔标记，
## 使“直到回合结束”自然到期：回合号一旦前进，提升自动失效，不需要额外的到期清理时机。
var _extended_limit_turn_number: int = -1
```

- `_get_play_phase_limit()` → `EXTENDED if _extended_limit_turn_number == host.state.turn_number else BASE`。
- `install()` 订阅 `phaseUseBegin` → `_used_this_play_phase = 0`（**不清除**提升回合号：提升跨出牌阶段持续到回合结束）。
- `can_activate()` 末尾要求 `_used_this_play_phase < _get_play_phase_limit()`。
- 「此前发动过也计入限两次」天然成立：提升上限时**不重置** `_used_this_play_phase`。

### 5.2 时序对照

| 玩家操作序列 | `_used_this_play_phase` | 上限 | 结果 |
|---|---|---|---|
| 分支二（弃一种花色） | 0 → 1 | 1 → 2 | 额度 1/2，还可再发动一次 |
| 再分支一（摸牌+视为使用） | 1 → 2 | 2 | 额度 2/2，本阶段结束 |
| 反之：先分支一（1/1）再分支二 | 1 → 2 | 1 → 2 | 额度 2/2，分支二只提升了上限，本阶段无剩余 |

---

## 6. 【独弈】弃牌阶段实现

```
install(): subscribe_timing("phaseDiscardBegin", _on_phase_discard_begin, "player")
```

**锁定技 ⇒ 不创建任何可取消询问**，直接执行：

1. 按花色归组手牌：`_get_hand_suit_groups(owner) -> Dictionary`，键为 `CARD_SUITS` 中的稳定花色，值为该花色的手牌 UID 数组；**花色不在 `CARD_SUITS` 内的手牌（`none`）不与任何花色成组**。
2. 每种**存在**的花色各随机保留 1 张：逐花色调用
   `host.call("pick_random_candidate_index", uids.size(), HISTORY_KIND_KEEP_SUIT, {"player_id":owner_player_id, "suit":suit, "candidate_count":uids.size()})`
   取到的索引对应 UID 进入 `kept_uids`。
3. `discard_uids` = 手牌全部 UID − `kept_uids`（含 `none` 花色手牌）。
4. `discard_uids` 非空时调用 `host.call("discard_selected_hand_cards", owner_player_id, discard_uids)`（**批次弃置**，`counts_as_discard_action = true`，会产生 `cardsDiscardedBatchAfter`，供【泛音】等既有技能读取）。
5. `announce_activation({"kept_uids":…, "discard_uids":…, "suits":…})`。
6. 跳过弃牌阶段：
   - 若 `host.has_pending_card_choice()`（弃置触发了嵌套选择）→ `defer_settlement({"kind":"duyi_skip_discard"})`；
   - 否则直接 `host.call("skip_current_main_phase", owner_player_id, "discard", get_id())`。
   - `continue_settlement(context)` 命中 `duyi_skip_discard` → 调用同一跳过端口。
   - **调用后不得再自行推进阶段**：`skip_current_main_phase` 的 `discard` 分支已把 `current_phase` 置为 `discard_skipped` 并排好到 `_enter_finish_phase` 的转场。

**边界**：手牌为空 / 只有 1 种花色 / `discard_uids` 为空 ⇒ 不调用弃置端口，仍然跳过阶段。牌堆与手牌实体守恒由测试断言。

---

## 7. 【弃和】实现

```
install(): subscribe_timing("useCardToTargeted", _on_card_targeted, "target")
```

回调中依次判定（任一不满足即静默返回，锁定技不询问）：

1. `int(event.data.get("target_id", event.target_id)) == owner_player_id`（`role = "target"` 已保证，仍做防御性复核）。
2. `actor_id = int(event.source_id)`；要求 `actor_id >= 0 and actor_id != owner_player_id`（**其他角色**）。
3. `card_id = str(event.data.get("card_id", ""))`；`GameDatabase.get_card(card_id)` 非空，且 `bool(definition.get("is_damage", false))` 为真。
4. `suit = str(event.data.get("card_suit", "none"))`；要求 `CARD_SUITS.has(suit)`（无花色虚拟牌不可能满足）。
5. 收集 `owner.hand` 中 `card.suit == suit` 的 UID，为空则返回（**不触发**）。
6. `index = host.call("pick_random_candidate_index", uids.size(), HISTORY_KIND, {"player_id":owner_player_id, "card_uid":card_uid, "card_id":card_id, "suit":suit})`。
7. `host.call("discard_card_from_hand", owner_player_id, uids[index])` → 单张弃置（计入弃置动作）。
8. 令此牌对自身无效：`host.call("exclude_card_target", card_uid, owner_player_id, get_id())`。
   - 若第 7 步引发了嵌套选择（`host.has_pending_card_choice()`）→ 先 `defer_settlement({"kind":"qihe_exclude", "card_uid":card_uid})`，在 `continue_settlement` 中调用 `exclude_card_target`；
   - 否则立即调用。
9. `announce_activation({"card_id":card_id, "card_uid":card_uid, "suit":suit, "discarded_uid":…})`。

**重复进入**：`useCardToTargeted` 对同一（牌, 目标）只派发一次，单张弃置不产生弃置批次，因此不需要计数器守卫；`exclude_card_target` 自带幂等（重复调用返回 `true`，不重复写入）。**只有使用者禁止改为「每回合每名角色一次」时才需要新增守卫**（本次原文无此限制）。

---

## 8. 【自摸】实现

### 8.1 常量与状态

| 名称 | 值 | 含义 |
|---|---|---|
| `CHOICE_PICK_EFFECT` | `"zimo_pick_effect"` | 分支一“选牌 + 选目标”的虚拟手牌请求类别 |
| `CHOICE_PICK_SUIT` | `"zimo_pick_suit"` | 分支二选花色（内联互斥选项） |
| `SLASH_DEFINITION_ID` | `"sha"` | 固定候选【杀】；可重复使用，不计入“已以此法使用过” |
| `TRICK_TYPE` / `NORMAL_TRICK_SUBTYPE` | `"trick"` / `"normal"` | 普通锦囊筛选口径（延时锦囊与响应类锦囊【无懈可击】都被排除） |
| `delayed` 字段需为 `false` | — | **排除延时锦囊**；`subtype == "normal"` 已覆盖普通锦囊，延时锦囊另有 `delayed` 兜底 |
| `AUTO_TARGET_MODES` | `["all_others","all_players","self","self_wounded"]` | 目标由规则唯一确定的模式（与【灵感】同口径） |
| `CARD_SUITS` | `["spade","heart","club","diamond"]` | 实体花色稳定集合；`none` 不计入花色数 |
| `SUIT_SYMBOLS` / `SUIT_NAMES` | ♠/♥/♣/♦ + 黑桃/红桃/梅花/方块 | 分支二选项标签素材（沿用 `anke.gd` 口径） |
| `DRAW_COUNT` | `1` | 分支一摸牌数（原文“摸一张牌”） |
| `SUIT_COUNT_THRESHOLD` | `4` | 分支分界（原文“少于4”/“不少于4”） |
| `BASE_PLAY_PHASE_LIMIT` / `EXTENDED_PLAY_PHASE_LIMIT` | `1` / `2` | 基础额度与分支二改写后的额度 |
| `AI_ACTION_BASE` | `20.0` | 【自摸】主动动作的保底正分（落实“满足条件无脑发动”） |
| `AI_COMMIT_REWARD` | `100.0` | 选牌 / 选花色的保底确认分，杜绝「发动→取消」空转 |
| `AI_SUIT_DISCARD_PENALTY` | `0.6` | 分支二每张被弃手牌的偏好惩罚；张数越少越优先 |
| `AI_SLASH_BONUS` | `0.5` | 分支一里【杀】的额外偏好 |

状态：`_used_this_play_phase`（本次出牌阶段已发动次数，`phaseUseBegin` 归零）、`_extended_limit_turn_number`（额度提升生效的回合号，`-1` 表示未提升）。

### 8.2 `can_activate()`

1. 持有者存活、未离场；`host.state.current_player_id == owner_player_id` 且 `host.state.current_phase == "play"`。
2. `_used_this_play_phase < _get_play_phase_limit()`。
3. 分支判定：
   - 花色数 `< 4` → `_build_effect_selection_data()` 必须非空（至少一个“存在合法目标”的完整效果）；
   - 花色数 `>= 4` → `_collect_suit_groups(owner)` 非空（至少要有一张实体花色手牌可弃）。

不额外要求 `not host.has_pending_card_choice()`：进入选择请求后按钮本来就被请求占用，额度的唯一权威就是 `_used_this_play_phase`。

### 8.3 `activate()`

```
suits = get_hand_suit_count(owner)
if suits < 4:
    _used_this_play_phase += 1          # 次数在摸牌时消费；摸牌不可撤销
    host.call("draw", owner_player_id, 1)
    _reopen_effect_selection()          # 建立虚拟手牌“选牌 + 选目标”请求
else:
    options = 每种现存花色的 {"id": suit, "label": "♠ 黑桃（3张）"}
    request_control_selection("自摸", SUIT_PROMPT, options, true, {"kind":CHOICE_PICK_SUIT, "suit_card_counts": {...}})
```

- 分支二的计次与额度改写**不在 `activate()` 内**，而在选择确认且弃置真正落地之后（见 8.6），避免弃置被中断时白吃一次额度。
- `_build_effect_selection_data()` 返回 `{"entries": [...], "min_targets": int, "max_targets": int}`；`entries` 逐项为
  `{"definition_id", "label", "target_combinations": Array[Array[int]], "auto_target_ids"?: Array[int]}`，
  技能侧**从不计算占位 UID**，UID 翻译全部由 `request_virtual_hand_card_target_selection` 完成。
- 候选过滤：`_get_effect_definition_ids()` 给出 `sha` + 全部未以此法使用过的普通锦囊；随后逐张用
  `host.card_rules.list_legal_virtual_targets(...)` + `validate_virtual_use(...)` 枚举“当前确实存在”的合法目标组合，
  组合为空者直接不进入候选（**因此不可能选出无法结算的牌名**；这也是“先过滤是否存在合法目标，再跳过视为使用规则”的落地点）。
- `min_targets` 取所有候选声明下限的最小值、`max_targets` 取最大值，请求级范围只用于协议承载，**精确约束由每张牌的目标组合映射收紧**。
- 顺序：`sha` 固定第一，其余按 `GameDatabase.cards.keys()` 排序后遍历（本地 / AI / 联机三端稳定）。

### 8.4 摸牌端口选择

`host.call("draw", owner_player_id, 1)`（与【飞焰】【宴请】等既有技能同一端口）。摸牌必须走权威端口，禁止直接操作 `state.draw_pile`。

### 8.5 交互流程与 `continue_selection()`

```
发动 ──► 摸 1 张（次数已消费）
        └─► 虚拟手牌请求（request_virtual_hand_card_target_selection，allow_cancel = true）
              ├─ 取消 ──► _reopen_effect_selection()（重新枚举候选，不重复摸牌、不重复消费次数）
              └─ 确认 ──► 复核 validate_virtual_use
                            ├─ 失败（含“当前已无合法目标”）──► 回到重新枚举
                            └─ 成功 ──► execute_cardless_virtual_card_use → 登记锦囊牌名（【杀】除外）→ 刷新展示文本
```

| `context.kind` | 行为 |
|---|---|
| `CHOICE_PICK_EFFECT` | 取消 / 候选数不为 1 / 占位 UID 不是本技能候选 / `validate_virtual_use` 失败 / `execute_cardless_virtual_card_use` 失败 → **一律回到 `_reopen_effect_selection()`**（不退回摸牌、不返还次数）；成功则登记牌名 + `announce_activation` + 刷新展示文本 |
| `CHOICE_PICK_SUIT` | 取消 → 直接返回（不消耗额度、不移牌）；确认 → 再枚举一次该花色 UID → `discard_selected_hand_cards` 成功且弃置数 > 0 → `_used_this_play_phase += 1` + `_extended_limit_turn_number = host.state.turn_number` + `announce_activation` |

- 登记牌名的范围：**只登记普通锦囊牌名**；`sha` 不写入集合（因此每个出牌阶段都能把【杀】作为候选）。
- 名额消费只在 `activate()`（分支一）与分支二弃置成功时各发生一次，反复取消 / 换牌不产生额外消耗。
- `_get_play_phase_limit()` 按**回合号**判定：`_extended_limit_turn_number == host.state.turn_number` 时返回 2，否则返回 1，因此“直到回合结束”自然到期，不需要额外的到期清理时机。
- 取消语义按用户最终口径：**选牌阶段不可取消的旧方案已废弃**，现在“取消 = 重新选牌”，选目标与选牌在同一次请求内同时完成。

### 8.6 分支二的展示与额度刷新

- 每次额度变化（分支二确认、`phaseUseBegin` 归零）后刷新 `set_skill_display_description`：正文 + `（已以此法使用：A、B）`；集合为空则还原为基础正文。
- 不新增角标按钮（复用统一信息框即可）。

### 8.7 界面表现：手牌区虚拟替换（用户最终指定）

- 协议层：`request_virtual_hand_card_target_selection` 构造的候选 `zone` 为 `"virtual_hand"`、带 `virtual_hand:true`，
  `card_data` 的 `suit` 固定 `"none"`、`rank` 固定 `0`（视为使用的牌没有花色与点数，因此界面也不显示）。
- 这些候选**只是视觉替身**：请求端口使用 `VIRTUAL_HAND_CANDIDATE_UID_BASE = 1000000000 + index` 的占位 UID，
  协议只校验 `selected_uids ⊆ candidates[*].uid`，因此占位 UID 能通过校验，且不会与任何真实 UID 冲突（真实 UID 远小于基数）。
- 界面：`scripts/ui/match_table.gd` 检测到虚拟手牌请求后进入“虚拟手牌模式”——
  真实手牌向左平移动画离场 → 虚拟候选以摸牌动画（复用 `hand_entry_offset` 与既有摸牌动画时序）从手牌入口进入 → 玩家像操作真实手牌一样同时选牌与选目标 → 确定后虚拟牌向右动画离场 → 真实手牌以摸牌动画回到手牌区。
- 动画参数：`local_hand_exit_duration`（默认 `0.24` 秒）、`local_hand_exit_margin`（默认 `24.0` 像素），与既有 `local_hand_gain_duration` 同组导出。
- 渲染层面这一模式**早退**在 `_render_local_hand()` 之前，因此真实手牌状态不会被虚拟替身污染；请求结束后一次性对真实手牌（含木牛流马“粮”）重放摸牌动画。

---

## 9. AI 配套（项目专属 AGENTS 2.3：不得只做提示分支）

### 9.1 【自摸】（主动技，四类钩子）

| 钩子 | 实现 |
|---|---|
| `append_play_phase_actions` | `can_activate()` 为真时追加 `{"action_type":"use_skill","actor_id":owner_player_id,"skill_id":"zimo","payload":{"skill_id":"zimo"}}` |
| `score_ai_action` | 只读快照；持有者存活且手牌非空即返回 `AI_ACTION_BASE`（保证「无脑发动」）。**不读取任何运行时字段**（AI 评分使用数据库新建的静态实例） |
| `score_ai_choice` | `CHOICE_PICK_EFFECT`：确认 → `AI_COMMIT_REWARD + 该牌面价值`；`CHOICE_PICK_SUIT`：确认 → `AI_COMMIT_REWARD − 该花色手牌数 × 单张弃置成本`（**优先弃置张数最少的花色**，代价最小）；`CHOICE_SELECT_TARGETS`：确认 → `AI_COMMIT_REWARD + 逐目标敌我收益`，取消 → `0` |
| `build_ai_virtual_card_action` | 不覆盖：虚拟牌由技能自身的选牌名步骤产生，与【灵感】同构 |

### 9.2 【独弈】（被动锁定技，来牌估值）

| 钩子 | 实现 |
|---|---|
| `modify_ai_incoming_card_effect` | 目标为本技能持有者且来牌需要【闪】响应（`bool(ai_profile.get("respond_shan", false))`）→ 提高该次来牌收益：持有者无法打出手牌【闪】，攻击必定命中。具体形式在实现阶段定稿为**对 `current_score` 的正向叠加**，并以「AI 对青雀使用【杀】的评分严格高于对无技能角色使用【杀】的评分」作为测试断言 |

### 9.3 【弃和】（被动锁定技，来牌估值）

| 钩子 | 实现 |
|---|---|
| `modify_ai_incoming_card_effect` | 目标为本技能持有者、来牌 `is_damage` 为真、且持有者手牌非空 → 按「手牌中至少有一张与来牌同花色」的估计概率降低该次来牌收益，使 AI 不再把青雀当作可以随意打伤害的软目标。断言：**AI 对青雀使用伤害牌的评分严格低于对无技能角色使用同一张牌的评分** |

### 9.4 不得干扰既有 AI

- 两个锁定技只改**自己的**来牌估值；【独弈】的用牌禁令经 `validate_use` 生效，AI 的合法动作列表自动不含被禁手牌，不需要额外策略分支。
- 所有 AI 钩子只读 `authoritative_snapshot` / 动作字典 / 选择请求 / `evaluator`；禁止 `host`、场景节点、运行时成员变量。

---

## 10. 测试设计（新增 `tests/qingque_mechanics_test.gd` + `.tscn`）

结构照抄 `tests/new_character_mechanics_test.gd`：`extends Node`、`_ready()` → `call_deferred("_run")`、手工 `MatchController` + 手装 `RuleEventBus`/`AICoordinator`/`NetworkGateway`、`_reset_state(player_count)`、`_add_hand_card()`、`_install_single_skill()`、`_submit_pending_choice()`、失败 `printerr("QINGQUE_MECHANICS_FAIL %s")` + `quit(1)`，成功 `print("QINGQUE_MECHANICS_PASS")` + `quit(0)`。**Tab 缩进**。

| 场景 | 关键断言 |
|---|---|
| 元数据与原文 | 武将 `id/display_name/gender/faction/max_hp/skills` 顺序；三个技能 `description` **逐字**等于 `prd.md` 原文；`lock`/`ui_enabled` 取值；【自摸】`enable == "phaseUse"` |
| 伤害牌清单一致性 | `is_damage` 为真的定义集合 == `ai.damage` 为真的定义集合，且恰为 9 个；`sha` 为真、【桃】/【八卦阵】为假 |
| 【独弈】用牌封锁 | 青雀手牌【杀】：`validate_use` 非空且原因含“独弈”；`validate_card_action_permission(..., CARD_ACTION_PLAY)` 同样被拒；手牌锦囊被拒；手牌装备与木牛流马“粮”不受限 |
| 【独弈】弃牌阶段 | 走真实 `_enter_discard_phase(0, true)`：6 张手牌覆盖 4 花色、体力 3 → 结束后恰好 4 张（每花色 1 张），证明既做了随机保留又跳过了“弃到体力值”的普通主体；`random_history` 恰好多出 4 条 `duyi_keep_suit`；阶段已离开本人弃牌阶段 |
| 【弃和】触发 | 手牌含红桃（另有黑桃）→ 敌方红桃【杀】指定青雀：**只**弃掉红桃那一张、`_card_use_contexts[uid]["excluded_target_ids"] == [0]`；同一张牌重复派发同一时机不再次弃牌 |
| 【弃和】边界 | 无同花色手牌 → 不弃牌不排除；非伤害牌（【过河拆桥】）→ 不触发；自己使用的伤害牌指定自己 → 不触发；无花色（`none`）虚拟伤害牌 → 不触发 |
| 【自摸】分支一 | 2 花色手牌：发动 → 手牌 +1 → `_pending_card_choice` 为 `card_target`、`context.virtual_hand == true`、全部候选 `zone == "virtual_hand"` 且 `suit == "none" / rank == 0`、占位 UID ≥ `VIRTUAL_HAND_CANDIDATE_UID_BASE` → 取消 → **手牌数量不变**且重新出现同一请求 → 提交【无中生有】→ 手牌再 +2、`get_skill_used_card_names(0,"zimo") == ["wuzhong"]`、`can_activate() == false`、重新枚举的候选不含【无中生有】但仍含【杀】 |
| 【自摸】分支二 | 4 花色手牌：`_get_play_phase_limit() == 1` → 发动 → `choice_type == "control"` 且选项数 == 4 → 提交红桃 → 红桃全部被弃、其余花色不动、`_get_play_phase_limit() == 2` → 同回合再发动分支一（花色数降到 3）成功 → 第三次 `can_activate() == false` → `turn_number` 前进后 `_get_play_phase_limit() == 1`（“直到回合结束”） |
| AI 完整性 | `append_play_phase_actions` 恰 1 条且 `score_ai_action > 0`；`score_ai_choice` 确认分严格大于取消分；分支二张数少的花色得分更高；【弃和】`modify_ai_incoming_card_effect` 在持有者手牌 2 张时小于基线、手牌 0 张时等于基线、非伤害牌等于基线；【独弈】对带 `respond_shan` 的【杀】大于基线、对无 `respond_shan` 的牌与其他目标等于基线 |
| 存档往返 | `skill_used_card_names` 经 `to_dict` → 恢复后保持一致（由 `auto_management_test` / `conquest_save_test` 覆盖） |

必跑回归：`res://tests/qingque_mechanics_test.tscn`、`res://tests/smoke_test.tscn`、`res://tests/requested_changes_test.tscn`、`res://tests/card_action_semantics_test.tscn`、`res://tests/event_runtime_test.tscn`、`res://tests/phase_progression_test.tscn`、`res://tests/card_timing_sequence_test.tscn`、`res://tests/ai_policy_test.tscn`、`res://tests/new_character_mechanics_test.tscn`、`res://tests/inline_hand_choice_test.tscn`、`res://tests/skill_target_ui_test.tscn`（后两个覆盖被改动的界面选择链路）。

运行方式（本机 Godot 4.7.1）：

```powershell
$godot = 'E:\Godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe'
& $godot --headless --path . res://tests/smoke_test.tscn
& $godot --headless --path . --quit          # 无头解析校验（不要用 --check-only --script）
```

---

## 11. 必须同步的既有测试常量

| 文件 | 位置 | 现值 → 新值 |
|---|---|---|
| `tests/smoke_test.gd` | `:200` | 技能数 `102` → `105`（并补一行历史口径注释） |
| `tests/smoke_test.gd` | `:307` | 武将数 `48` → `49`（并补一行历史口径注释） |

其余计数（`installed_skills`、图鉴、头像列表）均为动态计算，不受影响；未新增卡牌、牌堆、势力，因此 `:117`/`:109`/`:313` 与 `opportunity_system_test` 的计数均不变。

---

## 12. 文档同步清单

| 文档 | 同步内容 |
|---|---|
| `docs/内容制作指南.md` | ①「卡牌静态参数总表」新增 `is_damage` 字段说明；②「技能静态参数总表 / 技能生命周期函数」新增 `validate_card_action_permission` 钩子与两个 `card_action` 取值；③「新增机制制作接口」新增「使用牌花色/颜色时机数据」「技能公开已用牌名容器」两条；④技能模板与检查清单补充「锁定技不创建询问」「动态阶段额度的写法」 |
| `docs/游戏机制与玩法内容.md` | 追加 `## 青雀与【独弈】【弃和】【自摸】（YYYY-MM-DD）` 小节：武将数值（仙舟联盟 · 女 · 3 体力）、三个技能数值表（保留花色数/随机源、伤害牌判定字段、花色数阈值 4、摸牌 1、额度 1→2、弃置张数）、AI 数值 |
| `docs/卡牌系统.md` | 新增「是否为伤害牌」字段的语义与 9 张标注清单 |
| `docs/界面与交互.md` | 说明【自摸】的“手牌区虚拟替换”表现：真实手牌左移离场 → 无花色无点数的虚拟候选以摸牌动画进入 → 选牌与选目标同时完成 → 确定后虚拟牌右移离场、真实手牌以摸牌动画回归；导出参数 `local_hand_exit_duration` / `local_hand_exit_margin`；分支二仍复用内联互斥文字选项 |
| `docs/AI模块.md` | 新增两个锁定技的来牌估值钩子与【自摸】三处选择评分口径 |
| `README.md` | 「## 自动校验」追加一段：运行 `res://tests/qingque_mechanics_test.tscn` 可验证…… |
| `临时反馈文档.md` | 追加时间戳 + 学习反馈摘要 + 编号 Git 提交描述 |

---

## 13. 风险与对策

| 风险 | 对策 |
|---|---|
| 新增 `validate_use` 禁令误伤其他武将 | 钩子默认返回空串；只有安装【独弈】的角色受影响；回归 `card_action_semantics_test` / `ai_policy_test` / `smoke_test` |
| `CardRuleService` 脱离对局构造时没有技能提供者 | 咨询前同时判 `skill_rule_provider != null` 与 `has_method(...)`，与既有 `modify_skill_distance_to_target` 等咨询点同构；`smoke_test` 内的纯规则调用因此不受影响 |
| 时机数据新增键影响既有技能或测试 | 只做**附加**；不回写、不删除既有键；跑 `event_runtime_test` / `card_timing_sequence_test` / `card_action_semantics_test` |
| 【自摸】选出无法结算的牌名 | 候选**每次呈现都重新枚举**并按 `list_legal_virtual_targets` + `validate_virtual_use` 过滤为“当前确实存在合法目标”；提交后仍二次复核，失败只回到重新选牌 |
| 【自摸】取消造成重复摸牌或重复抢次数 | 摸牌与次数消费只发生在 `activate()` 内一次；取消只回到重新选牌，不回到摸牌；分支二的次数在弃置落地后才消费 |
| 占位 UID 与真实 UID 冲突 / 被协议拒绝 | 占位 UID 取 `1000000000 + index` 且只出现在 `candidates[*].uid` 中，协议只校验“提交集合 ⊆ 候选集合”，因此天然通过；基数远大于任何真实 UID |
| 虚拟手牌模式污染真实手牌渲染 | `_render_local_hand()` 在虚拟模式下早退，虚拟视图独立成组；请求结束后按真实 UID 重放摸牌动画并清理所有退出补间 |
| 弃置触发嵌套选择时漏掉「对自身无效」 | 统一用 `defer_settlement` + `continue_settlement` 承接，与【弦奏】同构 |
| 新增公开字段破坏旧存档 | 恢复时对缺失键按空字典容错；跑 `conquest_save_test` / `auto_management_test` |
| 固定种子选将阵容变化导致既有测试偶发失败 | 改完先跑 `smoke_test`，再抽查 `conquest_coop_test` / `pre_game_customization_test` |
| 锁定技正文以「锁定技」开头但忘记 `lock=true` | 显式写 `"lock":true`，并由 `requested_changes_test` 全目录校验兜底 |
