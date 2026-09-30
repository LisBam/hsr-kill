# 技术设计：主演机制、座次相邻、目标改写与两名武将

> 配套 `prd.md`。本文件只讲**怎么做**：边界、契约、数据流、取舍、兼容与回滚形态。

## 1. 改动地图

| 层 | 文件 | 改动性质 |
|---|---|---|
| 内容数据 | `game_data/factions.json` | 改 `xinghelieshou.color` |
| 内容数据 | `game_data/characters/bailu.gd`、`ren.gd` | 新增 |
| 内容数据 | `game_data/skills/xuanhu.gd`、`shengxi.gd`、`wansi.gd`、`zhili.gd` | 新增 |
| 核心服务 | `scripts/core/starring_role_service.gd` | 新增（主演唯一性不变量 + 角标维护） |
| 核心查询 | `scripts/data/game_state.gd` | 新增座次相邻查询（纯查询，无状态） |
| 核心规则 | `scripts/core/card_rule_service.gd` | 接入「允许自己成为目标」技能钩子（2 处：目标校验 + 全体展开） |
| 核心规则 | `scripts/core/match_controller.gd` | 挂载主演服务；弃牌上限接入技能钩子 |
| 技能基类 | `game_data/skill_definition.gd` | 新增 2 个默认钩子（手牌上限豁免、允许自己成为目标） |
| 测试 | `tests/zhuyan_zhili_test.gd/.tscn` | 新增 |
| 文档 | `docs/内容制作指南.md`、`docs/游戏机制与玩法内容.md` | 同步 |

**不新增序列化字段**：主演状态复用既有 `PlayerState.character_corner_text_entries`，因此公开快照、权威存档、AI 私有快照、网络与回放全部自动覆盖，无需改动任何序列化协议。

---

## 2. 主演机制

### 2.1 权威表示（关键技术决策）

主演状态的**唯一权威表示** = 「某角色的 `character_corner_text_entries` 中存在条目 ID `zhuyan`」。

理由：

1. `character_corner_text_entries` 已经是「角色级公开持续状态」的既有通道，「酩酊」「追歼」「永劫」「凶星」全部走这条通道；主演要求「与酩酊一样的角标显示」，复用同一通道天然等价。
2. 该字段已在 `PlayerState.to_dict()` 中输出（`player_state.gd:527`），因此主演状态**零成本**进入全部观察者快照；`noname_ai_evaluator.gd:391` 已经读取该字段，AI 天然可读。
3. 该字段随权威存档往返（`player_state.gd:311`），读档后主演状态自动恢复，不需要新增迁移代码。
4. 主演角色死亡时既有死亡清理已清空该字段（`match_controller.gd:13897-13898`），本条需求自动满足。
5. 「至多一名主演」这一不变量由**服务是唯一写入口**保证，而不是靠存储结构表达——结构上不可能出现「两个主演」这种非法状态，因为每次设置都先移除旧主演的条目。

### 2.2 `StarringRoleService`

`extends RefCounted`，与 `ReincarnationSkillService` 同构（`configure(match_host)` + 只调用宿主稳定端口）。

```
const CORNER_ENTRY_ID   = "zhuyan"   # 稳定条目 ID；与技能 ID 解耦，避免与技能条目冲突
const CORNER_TEXT       = "主演"      # 固定显示文本
const CORNER_TEXT_ORDER = 50          # 与【酩酊】【追歼】【永劫】【凶星】同档

func configure(match_host) -> void            # 绑定宿主；重开局时重建
func get_starring_player_id() -> int          # 返回当前主演 player_id；无主演返回 -1
func is_starring(player_id) -> bool           # 纯查询
func set_starring(player_id) -> bool          # 成为主演（原子：先移除旧主演角标，再写新角标）
func clear_starring(player_id = -1) -> bool   # 显式清除；player_id<0 表示清除任意当前主演
```

契约：

- `set_starring` 必须**原子**完成「旧主演摘除 + 新主演标注」，中间不得留下「两名主演」的可观察时刻（两步写完后由控制器统一 `_emit_state()`，见 2.3）。
- `set_starring` 对无效/死亡/离场角色返回 `false` 且零副作用。
- `get_starring_player_id()` 以**权威状态扫描**为准（遍历 `state.players` 找持有条目者），实例内 `_cached_player_id` 只作为快速路径；`configure()` 时缓存置为 `-1` 强制一次重扫。这样即使读档恢复出了主演条目，服务也能立即正确回答。
- 服务**不负责**死亡清理：死亡清理属于既有控制器职责（`character_corner_text_entries.clear()`）。服务只在被查询与主动设置时动作。

### 2.3 控制器接入

在 `match_controller.gd` 中与 `reincarnation_skill_service` 完全同构地挂载：

- 声明字段 `var starring_role_service: StarringRoleService`
- 初始化处（`reincarnation_skill_service` 的既有初始化点，`match_controller.gd:1460-1462` 附近）创建并 `configure(self)`
- 暴露给技能的公开端口（技能通过 `host.call(...)` 使用）：

| 端口 | 返回值 | 语义 |
|---|---|---|
| `set_starring_role(player_id)` | `bool` | 令该角色成为主演；成功写入角标并 `_emit_state()` |
| `get_starring_role_player_id()` | `int` | 当前主演 ID；无主演为 `-1` |
| `is_starring_role(player_id)` | `bool` | 纯查询 |

- 端口只在状态**真实变化**时 `_emit_state()`，避免高频空刷新。

---

## 3. 座次相邻查询

放在 `GameState`（纯数据查询，不依赖任何内容层），与既有 `get_next_alive_player()` 并列：

```gdscript
## 返回指定角色在「存活且未离场角色环形座次」上的左右相邻角色。
## 跳过死亡/离场角色；结果去重且按座次顺序返回，最多 2 名。
func get_seat_neighbor_player_ids(player_id: int) -> Array[int]
```

语义与边界：

- 底层就是既有的「存活环」构造方式（`CardRuleService.calculate_distance()` 用的同一套 `state.get_alive_players()` 口径），因此**「相邻」与「距离为 1」在该实现下等价**，符合用户确认的口径。
- 2 人局：左右邻是同一个人，**去重后只返回 1 个 ID**（【杀】对同一角色结算两次没有规则意义，且会让 AI 与界面产生误导性预览）。
- 存活角色 ≤ 1 名：返回空数组。
- 目标本身死亡/离场：返回空数组。
- 结果顺序固定为「按座次顺时针方向」：先右邻（下家方向）后左邻（上家方向），保证网络、回放与 AI 的确定性。

---

## 4. 【支离】目标改写管线

### 4.1 效果一：自己是自己使用【杀】的合法目标

现状（`card_rule_service.gd`）：

- `line 354`：`target_mode` 为 `single_other*` / `weapon_holder` 时拒绝自己；【杀】的 `target_mode` 是 `all_others`，**不在这条分支里**。
- `line 286`：`all_others` 自动展开时**显式跳过使用者自己**。
- `line 375`：距离限制 `attack_range` 判定——自己到自己的距离是 `0`（`calculate_distance` 对同 ID 返回 `0`），`0 <= 攻击范围` 成立，**不会**因此被拒。

因此拦截点有两处：**自动展开跳过自己**（line 286）与**自动展开前的枚举**（`list_legal_targets` 的循环，line 247-251 会自然包含自己，但交给 `_validate_target` 后被 `normalize_targets` 跳过）。

新增技能钩子（`skill_definition.gd`，默认 `false` 保持既有行为）：

```gdscript
## 判断本技能是否令持有者成为其自身使用指定卡牌的合法目标；默认 false 保持既有规则。
func allows_self_as_card_target(_card_definition: Dictionary) -> bool:
	return false
```

接线（`card_rule_service.gd`）：

- 新增私有查询 `_skill_allows_self_as_card_target(actor_id, definition) -> bool`，通过 `skill_rule_provider` 汇总全部已安装技能（与 `_skill_ignores_card_distance_limit` 完全同一模式）。
- `_validate_target`：在距离限制判定**之前**，若 `target_id == actor.player_id` 且该查询返回 `true`，则把距离限制视为已满足（不进入 `attack_range` / `one` 分支）。
- `normalize_targets`：`all_others` 分支的 `player.player_id == actor_id` 跳过条件改为「除非 `_skill_allows_self_as_card_target` 成立」。

副作用面：只影响**拥有该钩子**的角色，其他武将零变化。

### 4.2 效果三/四：指定唯一目标时改写 + 结算完毕后失去体力

**时机选型（关键）**：必须使用**会写回用牌上下文的整牌时机 `useCard`**。

- `useCardBefore` / `useCardBegin` 不写回上下文，改写会被静默丢弃（`docs/内容制作指南.md:4103` 明文警告）。
- `useCard` 位于 `useCard2` 之后、四组逐目标时机 `useCardToPlayer → useCardToTarget → useCardToPlayered → useCardToTargeted` **之前**（`docs/内容制作指南.md:2422`）。因此在本时机改写可保证：被替换掉的原目标**从未进入逐目标时机**，即不再响应【闪】——正是用户确认的「指定目标时即时改写」语义。

**改写端口**：`host.call("replace_card_use_targets", card_uid, new_target_ids, get_id())`（`match_controller.gd:8144`）。它同时写共享上下文与等待窗口，是唯一能真正生效的路径。

**流程**（`zhili.gd`）：

```
install():
  subscribe_timing("useCard",      _on_slash_used,  "source")   # 只关心自己用的牌
  subscribe_timing("useCardAfter", _on_slash_after, "source")   # 结算完毕后付出代价
  subscribe_timing("damageSource", _on_starring_damage, "source") # 主演造成伤害时回复（效果二）
  subscribe_timing("dieAfter",     _on_player_died, "global")   # 清理待结算标记

_on_slash_used(event):
  1. 牌必须是【杀】牌族（definition.effect_id == "slash"），否则返回
  2. 目标数组长度必须恰好为 1，否则返回（「指定唯一目标」）
  3. 该 card_uid 已在本次用牌中改写过的（查 _rewritten_card_uids）→ 返回，保证幂等
  4. neighbors = state.get_seat_neighbor_player_ids(唯一目标)
     - 为空 → 不改写（保留原目标），但仍然登记代价标记（用户确认：代价无条件支付）
     - 非空 → host.replace_card_use_targets(card_uid, neighbors, "zhili")
  5. _rewritten_card_uids.append(card_uid)；_pending_hp_cost_by_card[card_uid] = true
  6. announce_activation({...})  # 效果实际成立才昭示

_on_slash_after(event):
  1. card_uid 必须在 _pending_hp_cost_by_card 中，否则返回
  2. 清除标记
  3. who.loseHp(1, source)   # 失去体力，不是伤害
```

**幂等来源说明**：`useCard` 是**整牌**时机，每次用牌只派发一次，因此正常路径不会重复改写。用 `_rewritten_card_uids` 集合做二次防御，覆盖「同一张牌被重复派发」的异常路径（与【凌霜】【岳峙】的既有做法一致：幂等必须由技能侧保证）。

**跨换将边界**：`_pending_hp_cost_by_card` 是实例字段。若在 `useCard` 与 `useCardAfter` 之间发**换将/重装技能**，代价会丢失。这是项目既有边界（技能实例被卸载即丢实例状态）；本项目现有同类技能（【岳峙】守卫、【凌霜】豁免集合）采用同样处理，不额外引入 `character_form_state` 存储。

### 4.3 效果二：主演使用【杀】造成伤害时回复 1 点体力

订阅**全局** `damageSource`（触发角色 `source`）：

```
_on_starring_damage(event):
  1. 伤害来源 = event.source_id；必须 is_starring_role(source_id)
  2. 本次牌必须是【杀】牌族（读 event.data 的 card_id / virtual_storage，按项目既有【杀】判定口径）
  3. 伤害必须为正数（damage > 0）
  4. host.recover(source_id, source_id, 1, get_id())   # 主演自己回复 1 点
```

要点：

- 该效果属于**任何**主演（含非刃的主演），因此不能用 `role="source"` 绑定持有者自己，必须用 `role="global"` 并在回调里按「当前主演」判定。
- 「造成伤害时」按项目既有口径取伤害**成立**的时机（`damageSource`），与【山倾】红桃效果同款。
- 回复主体是**主演本人**，不是技能持有者。

---

## 5. 【万死】额外回合时序

**时机选型**：`phaseAfter`（`match_controller.gd:13280-13281`，在 `_complete_finish_turn` 内派发）。

该时机的性质正合需求：

- 它在**弃牌阶段完整结束之后**才派发（`_complete_finish_turn` 负责回合尾部），因此「于本回合结束后」得到精确表达。
- 派发时 `state.current_player_id` 仍是该角色，额外回合通过既有 `who.addPhase()` 入队后，会在本回合收尾完成后按队列执行，结束后自动恢复正常下家（`match_controller.gd:13382-13398`）。
- `phaseAfter` 是**可暂停时机**（`_run_phase_notification` 带 `_continue_after_phase_after` 续接），因此技能在该时机产生异步结果也是安全的。

**流程**（`wansi.gd`）：

```gdscript
install():
  subscribe_timing("damageAfter", _on_damage_after, "target")  # 自己受到伤害后
  subscribe_timing("phaseAfter",  _on_phase_after,  "player")  # 自己的回合结束之后

_on_damage_after(event):
  1. host.state.turn_number 为本回合键；若已发动过 → 返回
  2. owner.hp 必须恰为 1 → 否则返回
  3. 请求确认（choice_type=control，可取消，allow_cancel=true）
     - 取消 → 不设待执行标记、不消耗额度
     - 确认 → _pending_turn_number = 当前回合号；_used_turn_number = 当前回合号；announce_activation()

_on_phase_after(event):
  1. event.player_id 必须等于 owner_player_id（是自己的回合结束）
  2. _pending_turn_number 必须等于当前回合号 → 否则返回
  3. 清除 _pending_turn_number
  4. host.call("set_starring_role", owner_player_id)   # 先成为主演
  5. who.addPhase()                                     # 再执行额外回合
```

**「每回合限一次」的额度语义**：按**全局回合号**（`state.turn_number`）记账，与项目既有的「每回合限一次」实现口径一致（如【山倾】的 `_sync_turn_state`）。注意：额外回合拥有自己的 `turn_number`，因此额外回合内再次受伤到 1 点可以再次发动——这符合「每回合限一次」的字面语义。

**AI**：需求提示为「无脑发动」，即条件满足即确认。仍需实现完整的 `score_ai_choice`（返回正分即确认），并保证取消分支为 0 分（不会主动取消）。

---

## 6. 【悬壶】

### 6.1 效果一：【桃】不计入手牌上限

现状：手牌上限 = `PlayerState.get_hand_limit()`，只在**两个弃牌阶段**被调用（`match_controller.gd:7890`、`line 13146`），计算式 `手牌数 - 手牌上限`。

新增技能钩子（`skill_definition.gd`，默认 `false`）：

```gdscript
## 判断持有者的这张手牌是否不计入其手牌上限；默认全部计入。
func does_not_count_toward_hand_limit(_card: CardInstance, _card_definition: Dictionary) -> bool:
	return false
```

接线（`match_controller.gd`，两处弃牌计算统一走一个新的私有聚合入口，避免两处各写一套）：

```gdscript
## 返回指定角色不计入手牌上限的手牌数量；汇总其全部已安装技能的纯查询结论。
func _count_hand_limit_exempt_cards(player_id: int) -> int
```

`discard_count` 改为 `maxi(player.hand.size() - exempt_count - player.get_hand_limit(), 0)`。

- 只改**弃牌阶段**的溢出计算；`get_hand_limit()` 本身不变，因此 UI 上的「手牌上限」显示与其他任何读该值的地方保持既有语义。
- 纯查询、无副作用；不移动牌、不产生日志。

### 6.2 效果二：角色死亡后从牌堆获得一张【桃】

订阅 `dieAfter`（`role="global"`，因为**任意角色**死亡都触发）。锁定技 → 无选择窗口。

```
_on_player_died(event):
  1. 持有者存活且未离场（死亡者是自己时不发牌：自己已死亡，端口会拒绝）
  2. 遍历 host.state.draw_pile（从顶到底，数组顺序即牌堆顺序）
     找第一张 definition_id == "tao" 的实体
  3. 找到 → host.call("gain_draw_pile_card_by_uid", owner_player_id, card.uid, get_id())
     没找到 → 直接返回（不报错、不改动牌堆、不做洗牌）
```

- 使用 `gain_draw_pile_card_by_uid`（`match_controller.gd:8350`）：它正是为「观看/搜索牌堆后的精确获得」提供的端口，支持取得**不是牌堆顶**的牌，且内部处理日志与移动记录。
- **不**使用 `draw()`：`draw()` 固定从牌堆顶摸牌，与「从句牌堆中获得一张【桃】」不符（用户明确选择「只从牌堆中的【桃】里取一张」）。
- 【桃】的判定口径：`GameDatabase.get_card(card.definition_id).get("type") == "basic"` **且** `definition_id == "tao"`。直接比 `definition_id` 最精确，避免把【酒】等基本牌误判为桃。

### 6.3 锁定技与「无脑发动」

`lock=true`、无 `ui_enabled`、无 `can_activate`/`activate`。AI 提示「无脑发动」在本技能上体现为「不需要 AI 决策」：两个效果都在事件回调里无条件执行，不创建任何选择请求，因此不需要 `score_ai_choice`。

---

## 7. 【生息】

### 7.1 状态存储

必须跨技能实例存活（换将、重装、读档），因此写入 `PlayerState.character_form_state`：

| 键 | 类型 | 语义 |
|---|---|---|
| `shengxi_accumulated_x` | `int` | 当前永久 X；缺省按初始值 1 处理 |
| `shengxi_turn_number` | `int` | 记账所属的全局回合号；`-1` 表示尚未同步 |
| `shengxi_uses_this_turn` | `int` | 本回合已发动次数 |

- X **只增不减**，无上限。
- 额度刷新：`_sync_turn_state()` 发现 `turn_number` 变化时把 `uses_this_turn` 归零并更新记账回合号（与【山倾】`_sync_turn_state` 同款惰性同步，避免依赖回合开始订阅的时序）。

### 7.2 触发与选择

订阅 `useCard`（`role="source"`，整牌时机恰好每次用牌一次，天然幂等）：

```
_on_basic_card_used(event):
  1. 牌必须是基本牌（definition.type == "basic"）
  2. _sync_turn_state()；当前已发动次数 < 当前 X 才能询问
  3. 创建二选一控制选择（可取消）：
     - 选项 A：摸一张牌          control_id = "draw"
     - 选项 B：令本回合结束后X+1  control_id = "increase"
     - 取消：不消耗额度、不产生任何效果
  4. 确认后消耗 1 次额度
```

- 「使用基本牌时」包括视为使用的基本牌：`useCard` 读取的是**逻辑牌定义**（`virtual_card`），因此【杀】的转化牌同样触发，符合项目统一用牌事件口径。
- 【桃】自己使用也属于基本牌，同样触发。

### 7.3 「令本回合结束后X+1」的生效点

用户确认与原文均表述为「本回合**结束后**」。因此：

- 选择 B 时**不立即**修改 X，只登记一条「待递增」（实例内数组 `_pending_increase_count`，或直接累加计数）。
- 订阅 `phaseAfter`（`role="player"`）：当该时机属于持有者自己的回合结束时，把 `_pending_increase_count` 一次性加到 `shengxi_accumulated_x` 上并清零。
- 该动作**只写数值**：不创建选择、不摸牌、不移动牌、不发布新的用牌事件，因此不会在回合尾部引发新的触发链。
- 额外出牌阶段/额外回合分别有自己的 `turn_number` 与 `phaseAfter`，因此「本回合结束后」与既有【万死】保持同一套回合边界语义，两个技能不会互相干扰。

### 7.4 AI

需求提示：`X > 手牌数` → 选摸牌；否则选 `X+1`。

- 实现于 `score_ai_choice()`：读 `context` 中的当前 X 与持有者 `hand_count`（AI 只能读**自己**的手牌数，快照合法），决定两个选项的分数。
- 通用补全（`项目专属AGENTS.md` 2.3 要求）：
  - 额度耗尽时不得生成动作（由是否创建请求决定，不靠评分）。
  - 濒死/体力极低等通用局势修正：选「摸一张牌」的收益复用 `evaluator.score_resource_change()`，不重复声明资源换算比例（`content-ai.md` 第五节）。
  - X 已经很大（相对手牌数）时，`X+1` 的边际价值下降，但按用户明确口径仍以「X > 手牌数」为唯一判定条件，不额外引入阈值。

---

## 8. 【支离】AI：按改写后实际目标评分

### 8.1 问题

`BasicAIPolicy._score_action()` 对 `use_card` 动作的评分链是：

1. `evaluator.score_action()` —— 通用牌效（按**动作里的原目标**算）
2. `card_definition.modify_ai_action_score()` —— 卡牌专属
3. **`skill.modify_ai_card_action_score()`——持有者每一个技能**（`basic_ai_policy.gd:219-220`）

第 3 步正是技能侧介入【杀】评分的地方（现有范例：`game_data/skills/jiyu.gd:140`、`bingfeng.gd:170`、`yaoji.gd:62`）。

### 8.2 方案

在 `zhili.gd` 覆盖 `modify_ai_card_action_score()`：

```
1. 动作必须是【杀】牌族、且目标恰好 1 名 → 否则原样返回 current_score
2. 计算改写后目标集合 neighbors（与规则侧**共用同一个查询函数**，保证规则与 AI 同源）
3. 撤销通用层对原目标计入的收益，再加入改写后目标集合的收益：
   new_score = current_score
             - evaluator.score_action(对原目标的杀)      # 通用层已计入
             + evaluator.score_action(对 neighbors 的杀)  # 实际会发生
             - 自身失去 1 点体力的代价
4. 代价 = evaluator.score_resource_change(snapshot, owner, owner, 0, -1)   # 1 点体力
5. neighbors 为空 → 保留原目标，只扣体力代价
```

要点：

- **规则与 AI 共用同一份相邻查询**（`state.get_seat_neighbor_player_ids` / 快照等价实现），满足 `content-ai.md` 第 124 行「规则改写与 AI 预估必须共用同一份判定条件」。
- 「按改写后实际目标评分」直接落实用户 AI 提示：AI 不再按「想杀谁就指定谁」评分，而会主动挑选「相邻者是敌人」的目标位，并回避「相邻者是队友或自己」的目标位。
- **不得**生成「改写后反而打到自己/队友」的正分动作：由于改写后收益就是通用层对 neighbors 的真实牌效（含态度修正），队友/自己会自然得到负分。
- 扣代价使用的是既有资源换算端口 `score_resource_change()`，不重复声明比例。

### 8.3 通用估值体系的同步（`项目专属AGENTS.md` 2.3 要求）

- 「主演」引入了一个新的全局博弈维度：**谁当主演，谁的【杀】就附带 1 点自我回复**。
- 本任务在 AI 侧的实现范围：
  - 主演信息通过既有 `character_corner_text_entries` 进入快照（`noname_ai_evaluator.gd:391` 已在读取该字段），因此**不需要新增快照字段**。
  - 【支离】的 `modify_ai_card_action_score` 负责持有者自身的用牌决策修正。
  - 其他角色对「主演」的评估：现有 AI 已能读到角标条目，但本任务**不新增**对其他武将的针对性策略（避免影响既有决策），仅在 `docs/AI模块.md` 与《游戏机制与玩法内容》中登记该维度与本次补全范围。

---

## 9. 兼容性与回归风险

| 风险点 | 缓解 |
|---|---|
| 改 `card_rule_service` 的 `all_others` 展开 | 新钩子默认 `false`；只有显式覆盖的武将受影响；既有 `all_others` 行为逐字不变 |
| 改弃牌阶段溢出计算 | 把「豁免张数」聚合成独立函数；无技能豁免时结果为 0，计算式与原式等价 |
| `useCard` 时机改写目标 | 只改**唯一目标**的【杀】；多目标【杀】、其他牌、其他角色完全不受影响 |
| 主演服务与既有角标条目冲突 | 使用独立条目 ID `zhuyan`；`_refresh_character_corner_text` 已支持多条目按 `order` 合并（`match_controller.gd:15710-15749`），与「酩酊」等共存 |
| 【万死】额外回合打断既有回合链 | 复用既有 `add_phase()` 队列与 `_start_queued_or_normal_turn()`，不新造第二套回合调度 |
| 【生息】在 `useCard` 创建选择 | `useCard` 是**可暂停时机**（`_dispatch_card_rule_timing` 用 `run_rule_sequence` + `wait_for_timing` 等待应答），技能在其中创建可取消选择是既有支持的模式（与【岳峙】在同一时机 `request_card_selection` 相同） |
| 回合尾部 `phaseAfter` 新增结算 | 该时机可暂停且带 `_continue_after_phase_after` 续接；【万死】只做「写角标 + 入队额外回合」两件幂等事 |
| 新技能的 AI 钩子干扰基础 AI | 钩子只在动作是「自己使用【杀】且唯一目标」时生效；跑 `ai_policy_test` |

**回滚形态**：全部改动按文件独立可分。若需回滚，删除 4 个新技能文件与 2 个武将文件、`starring_role_service.gd`，并还原 `factions.json` 颜色与 4 个核心文件的接线点即可；核心侧新增的全部是**增量钩子/增量函数**，没有就地改写既有规则分支的语义。

---

## 10. 验证设计

新增 `tests/zhuyan_zhili_test.gd` + `.tscn`，在 `game_flow_interval_seconds = 0` 下同步运行，覆盖：

**主演**
1. 首次 `set_starring_role(A)` → A 的 `character_corner_text == "主演"`、`character_corner_text_entries` 含 `zhuyan`（`order == 50`）。
2. 再 `set_starring_role(B)` → B 有角标、**A 的角标条目被移除**、全场含 `zhuyan` 条目的角色数恰为 1。
3. `get_starring_role_player_id()` 与权威条目一致。
4. 主演死亡 → 角标消失、`get_starring_role_player_id() == -1`。

**座次相邻**

5. 8 人局：一号位的相邻 = {八号位, 二号位}（环形）。
6. 中间座位死亡后，其左右两侧在存活环上互成相邻。
7. 2 人局：相邻数组长度为 1（去重）。

**白露**

8. 白露 3 体力、手牌 3 张非桃 + 2 张【桃】→ 弃牌阶段弃 0 张；把 2 张桃换成非桃 → 按原规则弃 2 张。
9. 其他角色死亡 → 白露手牌 +1 且该牌是【桃】；牌堆中【桃】全部移除后死亡 → 手牌数不变、无错误。
10. 使用基本牌 → 出现二选一；选「摸一张牌」→ 手牌 +1、X 不变。
11. 选「X+1」→ 本回合内 X 不变（额度仍为 1）；回合结束后 X 变为 2。
12. 连续两个回合各选一次「X+1」→ X 累计为 3；跨回合不重置。
13. 一个回合内发动次数达到 X 后不再创建请求。

**刃**

14. 刃 4 体力、势力 `xinghelieshou`、技能顺序【万死】【支离】。
15. 刃受伤后体力为 1 → 出现【万死】确认；体力为 2 → 不出现；同回合第二次受伤到 1 → 不再出现。
16. 确认后：**伤害当刻不获得额外回合**；本回合 `phaseAfter` 后成为主演且进入额外回合（额外回合期间 `current_player_id == 刃`）。
17. 刃的【杀】目标候选包含自己；指定自己可通过 `card_rules.validate...` 与最终提交。
18. 刃用【杀】唯一指定 T → 实际目标集合 == T 的相邻角色集合；T 不在目标集合中；T 未进入【闪】响应窗口。
19. 改写后目标包含刃自己（T 的相邻者是自己时）。
20. 改写后的【杀】结算完毕 → 刃体力 -1；被【闪】抵消时同样 -1；【杀】被取消时同样 -1。
21. 非刃的主演使用【杀】造成伤害 → 该主演回复 1 点体力。

**回归**

22. `GameDatabase.validation_errors` 为空。
23. 新增技能的 AI 动作不产生「发动→取消」空转。

既有测试命令（`docs/战斗框架回归说明.md` 的口径）：

```
res://tests/smoke_test.tscn
res://tests/ai_policy_test.tscn
res://tests/new_character_mechanics_test.tscn
res://tests/zhuyan_zhili_test.tscn   # 新增
```
