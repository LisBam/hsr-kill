# 技能制作规范

> 权威来源：`docs/内容制作指南.md`「技能制作」全书（运行方式、静态参数总表、生命周期函数、规则修正与虚拟牌、主动/被动示例）。
> 铁律：玩家可见的技能描述文本必须与需求原文**逐字一致**（见 [`../project/collaboration-rules.md`](../project/collaboration-rules.md)）。

---

## 一、技能的运行方式

武将文件直接引用技能脚本。选将完成后，系统为每名持有者创建**独立** `SkillDefinition` 实例并自动调用：

```text
_init()
  ↓
bind(match_host, owner_player_id)
  ↓
install()
  ↓
对局运行：事件触发或玩家提交 use_skill
  ↓
uninstall()
```

- 不同玩家即使拥有同一个技能，也**不会共享**次数、标记或临时状态。
- 同一稳定 `player_id` 在车轮战、过关斩将或武将交换后仍代表同一座次，但新武将属于新的 `PlayerState.character_generation`。
- **内容不得把稳定玩家 ID 误认为永远是同一武将实例。**

---

## 二、静态参数总表

| 参数 | 必填 | 类型 | 说明 |
|---|---|---|---|
| `id` | 是 | `String` | 永久逻辑 ID，也是主动技能动作与回放记录使用的 ID |
| `name` | 是 | `String` | 技能按钮与提示的显示名称 |
| `trigger` | 是 | `String` | `sample_only` 是保留值（只有元数据、规则未接入）；其他值表示正式技能，推荐填 `active`/`passive`/主要事件名。**该字段本身不会自动订阅事件** |
| `lock` | 是 | `bool` | 是否锁定技。`true` 表示满足条件强制执行且**不得创建发动选择**；缺省被规范为 `false`，现有锁定技必须显式填 `true` |
| `half_locked` | 半锁定技显式填 | `bool` | 是否同时具有非锁定前段与锁定后段。正文中「锁定技」标签位于非开头位置时基类也会自动识别；对应时机订阅必须显式传 `locked_segment=true` |
| `leader_skill` | 是 | `bool` | 领袖技。`true` 时只有身份为 `leader` 的角色安装实例并在技能栏显示；其他身份即使选同一武将也不拥有、不显示，AI 也不应用其钩子 |
| `out_of_game_skill` | 是 | `bool` | 离场技。缺省 `false`；`true` 时持有者存活但离场仍可接收时机、完成自身选择并参与纯查询效果，**死亡后仍失效** |
| `ui_enabled` | 是 | `bool` | `true` 表示生成可主动发动入口，并**要求实现** `can_activate()` 与 `activate()` |
| `enable` | 主动技能建议填 | `String` 或 `Array[String]` | 声明主动入口：`phaseUse`、`chooseToUse`、`chooseToRespond`、`chooseCard`。旧 `ui_enabled=true` 且未填时默认仅 `phaseUse`；无效名称会被过滤 |
| `description` | 是 | `String` | 必须完整写明发动时机、条件、次数、目标、费用和效果数值 |

技能可增加自定义静态字段（如 `max_uses`、`cost_count`、`damage_amount`），类型与范围由技能文件负责，但**所有魔法数字都应提取为带注释的常量或变量**。

---

## 三、关键生命周期函数

| 函数 | 何时覆盖 | 作用 |
|---|---|---|
| `_init()` | 必填 | 调用 `super({...})` 写入技能元数据 |
| `bind(match_host, player_id)` | 通常**不得**覆盖 | 系统自动绑定 `host` 与 `owner_player_id` |
| `subscribe_timing(event_name, callback, role="player", priority=0, first_do=false, last_do=false, condition=Callable(), locked_segment=false, maintenance=false)` | 被动技能 | 以持有者身份订阅 236 个标准时机，自动绑定 `self` 与 `owner_player_id`，并把内容条件与持有者有效性条件组合；失败返回 `-1` |
| `install()` | 被动技能需要 | 订阅事件、触发器或查询修正 |
| `uninstall()` | 有自定义注册时需要 | 先清理修正管线，再 `super.uninstall()` 清理事件订阅 |
| `can_activate(context)` | 主动技能需要 | **无副作用**检查当前是否可发动，返回 `bool` |
| `activate(context)` | 主动技能需要 | 执行效果；成功返回**空字符串**，失败返回玩家可见错误文本 |
| `can_use_effect(locked_segment=false)` | 主动入口/查询/钩子统一使用 | 返回当前效果片段能否在「非锁定技失效」期间生效。完整锁定技恒 `true`；半锁定技仅当参数为 `true` 时保留锁定后段；其他非锁定效果返回 `false` |
| `can_trigger_while_owner_inactive(event)` | 仅死亡/离场后仍需触发的特殊技能 | 默认 `false`；不得为普通全局技关闭统一生存校验。两种合法用途：**持续效果的到期清理**（例：【补缀】）与**仅由持有者本人承担、必须在失效后补做的清理**（例：【凶星】阵亡后清掉自己的上限保护额度）。放行范围必须收敛到真正需要的时机，禁止 `return true`。**已经挂在目标身上的持续效果不要用它实现**：技能实例还会被换将整体卸载，放行覆盖救不了换将场景，应改用 `PlayerEffect` |
| `announce_activation(context={})` | 效果**实际成立**时调用 | 写入 `skill_history`、对局日志并触发牌面提示；指定角色时 `context` 必须写 `target_id` 或按序列写 `target_ids`。**不得在取消、未支付费用或执行失败时调用** |
| `announce_activation_for_player(activator_player_id, context={})` | 跨角色发动时 | 同上传记归属到实际支付费用/执行效果的角色 |
| `observe_identity_behavior(target_ids, ai_profile)` | 有公开可选目标效果时 | 上报身份观察；只更新 AI 观察，不执行效果 |

`subscribe_timing` 补充：

- 普通技能持有者**死亡、离场或状态缺失后不再接收新时机**。
- 只负责移除旧持续效果的到期或死亡清理可传 `maintenance=true`，但**不得借此在失效期间产生新收益**。
- “本局一次”或跨回合的私有记忆必须写入持有者的 `PlayerState.character_form_state`（随权威存档往返、不进入公开快照），不能只放在技能实例字段里：技能实例会在复原武将牌、技能重装与读档后被重建，实例字段会静默丢失。
- 持有者有效性检查的**固定顺序**是：武将代次匹配 → （持有者存活且在场，或 `can_trigger_while_owner_inactive(event)` 返回 `true`，或 `out_of_game_skill` 覆盖）→ `can_use_effect()`（`maintenance=true` 时跳过）→ **仅当技能位于 `player.acquired_skills` 时才检查局内获得技能额度** → 内容自定义条件。因此固有技能的死亡后清理不会被“获得技能额度”挡住；反之，**局内获得的技能**（额度来自 `acquired_skills`）即使覆盖了死亡放行也会被额度检查拒绝。

---

## 三之二、按“真实轮末”到期的持续效果

“本轮结束时……”类效果（例：【补缀】发放的护盾在轮末失去）必须订阅真实轮末时机 `roundEnd`，不要挂在下一轮 `roundStart`：

```gdscript
func install() -> void:
	super.install()
	# 轮末到期：只做清理，不产生新收益，因此 maintenance=true 并放行持有者死亡后的这一条清理。
	subscribe_timing("roundEnd", _on_round_end, "global", 0, false, false, Callable(), false, true)

func can_trigger_while_owner_inactive(_event: RuleEvent) -> bool:
	return true

func _on_round_end(event: RuleEvent) -> void:
	# 事件数据里的 round_number 是刚结束的那一轮；本端只消费“小于等于结束轮数”的记录，
	# 后续轮次的记录保留到对应轮末再结算，因此同一轮多次发放会逐条叠加。
	var ending_round_number: int = int(event.data.get("round_number", host.state.round_number))
	...
```

约定：

- 发放时按 `{round_number, target_ids}` 逐条登记**自己实例内**的记录；`round_number` 取当时的 `host.state.round_number`。
- 清理统一走权威端口（`who.loseShield(count, source)` 等），由端口负责拒绝已死亡、已离场或没有对应资源的角色；“目标已失效”不需要技能自己判断。
- 到期只做**移除**：不接受目标、不读取玩家选择、不写新的收益，这样才符合 `maintenance=true` 的约束。
- 换将（技能实例被卸载）会丢失实例内尚未消费的记录；这是既有边界。需要跨换将（以及跨施放者阵亡、跨“非锁定技失效”）保留时，状态写进目标的 `character_form_state`，并把**结算者**改写成 `PlayerEffect`（见下一节）。

---

## 三之三、手牌视为：换名与换牌面

| 端口 | 语义 | 表现 |
|---|---|---|
| `MatchController.set_hand_cards_view_as(...)` / `set_hand_card_view_as_until_next_turn_end(...)` | 只把牌名视为另一张牌，**花色点数保持实体原值** | 牌名与说明改成视为牌名，角标仍是实体花色点数 |
| `MatchController.set_hand_card_view_as_with_face(player_id, card_uid, view_as_definition_id, suit, rank, source_id="runtime") -> bool` | 牌名 + **花色 + 点数**一起视为（例：【鉴映】） | 横幅显示“花色符号 + 点数 + 视为牌名”，牌角与插画保留实体原样 |
| `MatchController.reveal_hand_card(player_id, card_uid, reason)` | 只把这张牌标记为对全体公开，用于“展示”类技能 | — |

契约与边界：

- `set_hand_card_view_as_with_face` 只在牌**位于该角色普通手牌区**（`CardInstance.zone == "hand"`）时生效；牌名必须能在 `GameDatabase.get_card()` 中解析，花色必须是 `is_valid_suit()` 的四种之一，点数必须是 `is_valid_rank()` 的 `1..13`；任一不满足都**零副作用返回 `false`**。
- 端口只负责写入视为、写日志与 `_emit_state()`；**发动次数、时机、目标与“B 是否为装备牌”等全部规则属于调用方技能**，不要在控制器里判断。
- 复制牌面意味着**颜色判定、材料花色聚合、点数比较**都会读到视为后的值（例如黑桃2 → 红桃12 后，它是一张红色、点数为12 的牌）；这是有意为之，不要为“原牌面”再补一套并行字段。
- 表现层从快照读取：`presentation_original_suit/rank` 是实体牌角（离手后为空，表现层回退到实体 `suit/rank`），`view_as_suit/rank/definition_id` 是视为牌面，离手后仍保留以解释“曾视为”。
- 需要“先展示 A、再选择并展示 B、最后才视为”的技能，必须把三段拆成 `run_steps([...])`/多个 `continue_selection` 轮次：展示动作不能与选择动作在同一轮里合并，否则会出现“两张牌同时公开”。

### 规则结果改写钩子

- `modify_death_reward(victim_snapshot, base_reward)`：改写**击杀奖惩**。返回空字符串表示不改写；返回非空稳定类型字符串即**整体替换**身份规则结论，由 `MatchController.resolve_death_reward()` 统一结算，基础奖惩与改写结果**不叠加**。被击杀者快照固定含 `player_id`、`character_id`、`identity`、`alive`；技能不得自行摸牌、弃牌或直接修改 `PlayerState`。
- 新增奖惩类型时把稳定字符串与固定数值集中声明在 `DeathResolutionService`（当前 `KILL_REWARD_DRAW_FOUR_TYPE` / `KILL_REWARD_DRAW_FOUR_COUNT`），技能只引用常量，**不得在技能内重复写数值**。
- 规则改写与 AI 预估必须共用同一份判定条件：规则侧用 `modify_death_reward()`，AI 侧用 `modify_ai_lethal_damage_consequence(snapshot, actor_id, target_id, current_score, evaluator)`，后者只读快照、只返回修正分，不得执行规则效果。

---

## 三之四、跨换将的持续效果：`PlayerEffect`

判断标准只有一句：**这个效果在施放它的技能实例消失之后，是否还必须继续生效？**

技能实例会在三种情况下停止工作，这正是效果必须独立存在的三种理由：施放者阵亡（统一生存校验不再放行）、施放者换将（`_reinstall_character_skills_for_player()` 整体卸载旧实例）、施放者被“非锁定技失效”压制（该检查对技能订阅生效）。

是 → 写成 `game_data/effects/<拼音>.gd` 的 `PlayerEffect` 子类：

- `get_id()` 与文件名一致；`install_effect()` 订阅时机（基类已登记承载者死亡回收，**不要覆盖 `install()`**）。
- `has_persisted_state(player)` 必须实现为纯只读查询，对局开始与存档恢复按它重建实例；重建只看角色自己的 `character_form_state`，**不要求施放者仍在场**。
- 持久状态写在**承载角色**的 `character_form_state`；实例由 `PlayerEffectService` 持有强引用，内容侧**不得**只把实例放在局部变量里（会被回收，订阅随之失效）。
- 技能侧用 `host.call("install_player_effect", target_id, EFFECT_ID)` 取得（已存在则复用）实例，再把数值交给它累加。

否 → 留在技能里即可（例：【凶星】自己那一次“防止体力上限减少”随爻光消失而失去意义）。

完整接口、状态与角标规范见 `docs/内容制作指南.md`「角色持续效果制作」。

---

## 四、主动技能

- `enable` 声明入口；`phaseUse` 是出牌阶段主动发动入口。
- 必须实现 `can_activate(context)`（无副作用）与 `activate(context)`（成功返回空字符串）。
- 需要基础 AI 主动发动时覆盖 `append_play_phase_actions(result)`，追加 `action_type=use_skill` 的合法动作字典。
- 需要目标、费用或确认预览时覆盖 `get_activation_preview(context)`，返回**只读** `Dictionary`，**不得产生副作用**。
- 当前桌面技能按钮只提交 `action_type=use_skill` 与 `payload.skill_id`，**不会主动消费** `get_activation_preview()` 的字段。

> 可取消的内联选择：若技能在 `activate()` 中创建了允许取消的选择，原技能按钮保持选中可点击；玩家再次点击会通过原请求入口提交 `confirmed=false`，**内容脚本必须把它当作「未支付费用、未选定目标、未消耗次数」的取消结果**。

---

## 五、暂停与续接（选择、响应、判定、额外阶段）

技能创建的一切交互都经统一选择协议；创建后必须实现对应恢复函数，且**上下文必须只含可序列化数据**。

| 恢复函数 | 何时覆盖 |
|---|---|
| `continue_choice(context, selected_uids)` | 技能创建普通选牌；识别后返回 `true` |
| `continue_selection(context, response)` | 需要读取牌、目标或文字选项；`response.card_ids`/`response.target_ids` 保留提交顺序，互斥文字选项读 `response.control_id` |
| `continue_response(context, response_card)` | 技能创建响应请求；`null` 表示放弃 |
| `continue_judgment(context, judgment_card)` | 技能发起可暂停判定；`null` 表示取消或无法完成。必须按业务 `kind` 复核原父牌、目标、回合等稳定上下文 |
| `continue_extra_phase(context)` | 技能创建额外阶段；`End/After` 均完成后恢复来源技能，适合结算「然后」后的护盾、摸牌等 |
| `continue_settlement(context)` | 技能顺序效果被嵌套选择暂停；**不得保存运行时对象** |

### 请求包装函数（自动写入上下文）

优先使用基类包装函数，它们会自动写入：

```gdscript
context["skill_id"] = get_id()
context["skill_owner_id"] = owner_player_id
```

| 函数 | 用途 |
|---|---|
| `request_card_selection(...)` | 技能持有者选牌 |
| `request_card_selection_for_player(chooser_id, ...)` | **令其他角色**选牌（如「其弃置一张手牌」），不得把选择错误交给技能持有者 |
| `request_control_selection(...)` | 持有者选择互斥文字选项，结果读 `ChoiceResponse.control_id` |
| `request_control_selection_for_player(chooser_id, ...)` | 令其他角色选择互斥选项 |
| `request_target_selection(...)` | 选目标（`choice_type=target`） |
| `request_card_target_selection(...)` | 同时选牌与目标（`choice_type=card_target`） |

创建响应牌请求时还要写入 `responder_id`；`request_response_card()` 会自动补充 `response_patterns`。

### 顺序效果的登记

技能顺序效果若被嵌套选择暂停，用 `defer_settlement()` 登记**纯数据步骤**；控制器在选择、同一时机续列和装备触发均无等待后调用原实例的 `continue_settlement()`。**避免业务函数在选择存在时继续同步结算。**

---

## 六、响应转化（把实体材料当响应牌打出）

采用**显式发动协议**，内容作者**不得**依赖「材料颜色满足条件就自动当响应牌」的隐式行为：

- 覆盖 `can_convert_response_card(card, response_patterns)`：无副作用判断能否满足任一响应模式——**只决定候选，不提前移动材料**。
- 覆盖 `get_converted_response_definition_id(card, response_patterns)`：返回转化后的实体定义 ID；提交时控制器再次复核、移动材料，并生成继承单张材料花色与点数的虚拟响应牌。
- 候选快照为可转换材料写入 `required_response_skill_id`；桌面先保持材料暗置，仅当玩家点击匹配的 `chooseToRespond` 技能按钮后才开放选择；提交动作必须携带同一个 `response_skill_id`。
- 控制器消费材料前会再次复核技能实例、主动入口、材料区域与转换条件；**ID 为空或不匹配时拒绝转换**。

---

## 七、轮回技与连续虚拟牌

- 需要连续使用多张**无材料虚拟牌**的技能，继承 `SequentialVirtualSkillDefinition`（`game_data/sequential_virtual_skill_definition.gd`），它只保存可序列化队列与活动项，在 `useCardAfter`/`useCardCancelled` 后逐张继续。
- 轮回技状态由 `ReincarnationSkillService` 统一维护（轮回数、轮回节、永劫、每回合次数、每节出牌阶段次数），技能文件**不自行维护第二份进度**。
- 需要推进**其他角色**的轮回技时，先调用 `MatchController.list_reincarnation_skill_ids(player_id)` 取得稳定 ID 数组，再逐个调用 `enter_next_reincarnation()`（下一个**轮回**，轮回数 `+1` 并回到①）或 `enter_next_reincarnation_section()`（下一个**轮回节**，末节完成后自动进入下一轮回）；**不得遍历 `PlayerState.reincarnation_skills`**，也不得混用两种语义。

---

## Quality Check

- [ ] 玩家可见 `name` 与 `description` 与需求原文逐字一致。
- [ ] 静态参数齐全；锁定技显式 `lock=true`；半锁定技后段订阅显式 `locked_segment=true`。
- [ ] `ui_enabled=true` 的技能已实现 `can_activate()` 与 `activate()`；`activate()` 成功返回空字符串。
- [ ] 所有主动入口/查询/钩子都经 `can_use_effect()` 复核失效状态。
- [ ] 每个创建交互的函数都有对应 `continue_*` 恢复实现。
- [ ] `context` 中**没有**节点、`PlayerState`、`CardInstance`、`Callable`。
- [ ] 令他人选择的场景使用 `*_for_player()` 包装，未把选择错误交给持有者。
- [ ] 效果实际成立时才调用 `announce_activation()`；带目标时写入了 `target_id`/`target_ids`。
- [ ] 正式技能已补配套 AI（见 [content-ai.md](./content-ai.md)）；`sample_only` 未伪造 AI。
- [ ] 「本轮结束」类到期效果订阅的是 `roundEnd`，且只做移除（`maintenance=true` + `can_trigger_while_owner_inactive`）。
- [ ] 跨施放者阵亡/换将/非锁定技失效仍需结算的效果已写成 `PlayerEffect`（并实现 `has_persisted_state()`），而不是靠技能订阅或放行覆盖硬撑。
- [ ] 复制牌面的视为使用 `set_hand_card_view_as_with_face()`；「先展示、再选择、最后生效」已拆成独立轮次（不会同时公开两张牌）。
- [ ] `docs/内容制作指南.md` 与《游戏机制与玩法内容》已同步新接口、规则与全部数值。
