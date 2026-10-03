# 技术设计：十项缺陷修复

> 本文只记录**技术方案**：根因、落点、替代方案与否决理由、回归面。
> 需求原文与验收标准见 [`prd.md`](./prd.md)；执行顺序见 [`implement.md`](./implement.md)。

## 1. 总体思路

十个问题分三类，处置原则各不相同：

| 类别 | 问题 | 处置原则 |
|---|---|---|
| **量纲／口径错误** | ① 泛音、⑨ 支离 | 修正与文档已声明口径不一致的那一处数值来源，不改通用评分常量 |
| **声明缺失／字段写错** | ② 借刀杀人、⑦ 自摸、⑩ 取消按钮 | 补齐或纠正内容层声明，让既有通用机制重新生效 |
| **机制性缺陷** | ④ 判定顺序、⑤ 自摸目标枚举、⑥ 用牌禁令漏检、⑧ 界面状态被覆盖 | 在唯一权威点修正，不新增特例分支、不引入牌名白名单 |

贯穿约束（来自 [`.trellis/spec/`](../.trellis/spec/) 与 `项目专属AGENTS.md`）：

- **单向依赖**：`game_data/`（内容）→ `scripts/core/`（规则）→ `scripts/ui` / `scripts/ai`（适配）。内容不得反向依赖核心，核心不得出现牌名或技能名特例。
- **单一权威**：规则事实只在 `MatchController` + `GameState`；AI 与界面只读快照、只提交动作。
- **内容自洽**：技能的规则与 AI 钩子写在该技能自己的 GD 文件里。
- **原文不可变**：技能／卡牌正文一字不改。

---

## 2. 分层落点总表

| # | 文件 | 层 | 改动性质 |
|---|---|---|---|
| ① | `game_data/skills/fanyin.gd` | content | 补 `ai_choice_skill_scored` 声明 |
| ② | `game_data/cards/jiedaosharen.gd` | content | 响应动作类别 `PLAY` → `USE` |
| ③ | `scripts/core/match_controller.gd` | core | 补一次 `ahha_moment_system.configure` |
| ④ | `scripts/core/match_controller.gd`、`game_data/skills/xingqi.gd`、`game_data/skills/yousi.gd` | core + content | 判定取牌端从数组首改为数组尾 |
| ⑤ | `game_data/skills/zimo.gd`、`scripts/core/card_rule_service.gd` | content + core | 枚举改为全体角色双循环；候选错误文本收窄 |
| ⑥ | `scripts/core/card_rule_service.gd` | core | 目标枚举咨询用牌禁令 |
| ⑦ | `game_data/skills/zimo.gd` | content | 选择评分改为代理用牌评分 + 关闭通用层叠加 |
| ⑧ | `scripts/ui/match_table.gd` | ui | 手牌重渲染不回写询问期间的按钮态 |
| ⑨ | `game_data/skills/zhili.gd` | content | 自身体力代价按统一资源值计价 |
| ⑩ | `game_data/skills/zimo.gd`、`scripts/ui/match_table.gd` | content + ui | 请求声明不可取消；取消按钮按声明暗置 |

---

## 3. 逐项技术方案

### ①【泛音】黑色分支 AI 选队友

**现象**：弃置黑色牌后的「对一名角色造成效果」被 AI 稳定指向队友。

**根因**：同一次弃牌被**两层以相反符号重复计价**，恰好相消。

- 通用层（`scripts/ai/noname_ai_evaluator.gd:709-713`）：普通选目标默认返回 `态度 / ATTITUDE_SCALE`，即**偏好友方**。
- 技能层（`game_data/skills/fanyin.gd:273-277`）：`score_resource_change(..., -1, 0) + 2.0`，其中 `score_resource_change` 又乘一次同一态度（`noname_ai_evaluator.gd:218-225`）。
- 两层相加（`scripts/ai/basic_ai_policy.gd:369,378`）后，`ATTITUDE_SCALE = 5.0`、`CARD_RESOURCE_VALUE = 1.0` 使友方、敌方、自己的总分**恒等于 `2.0`**；`basic_ai_policy.gd:131-134` 用严格 `>` 比较，并列时保留枚举顺序第一项，而单目标动作按候选数组顺序生成（`scripts/core/match_controller.gd:3505-3510`）→ 命中座次最前者（通常正是队友）。

**方案**：给黑色分支的目标请求补 `"ai_choice_skill_scored": true`（`fanyin.gd:154` 的上下文）。

**为什么可行**：该标志是项目已文档化的转义入口（`scripts/ai/noname_ai_evaluator.gd:610-618`，[`docs/内容制作指南.md:2278`](../../../docs/内容制作指南.md)），语义正是「本请求收益已由技能自己的 `score_ai_choice` 完整表达，通用层不得再叠加」。声明后通用层只剩「未确认 = 0」基准，技能层成为唯一计价方：队友 `-1.0 + 2.0 = +1.0`，敌人 `+1.0 + 2.0 = +3.0`，净差 `2.0` 且方向正确；同时 `+2.0` 的固定偏置使「确认」严格大于「取消」的 `0.0`，锁定效果不会被 AI 取消。

**替代方案与否决理由**：
- *把技能系数放大到 `2×`*：能打破并列，但两层仍在重复计价，数值随 `ATTITUDE_SCALE` 漂移，属于治标。
- *改通用层不再按态度给普通选目标计分*：会改变全部技能的选目标行为，回归面过大。
- *给 `BLACK_DISCARD_KIND` 也加该标志*：否决。该步骤依赖通用层的「选中牌按牌面价值计费」来体现「弃置低价值牌」的偏好，关闭后会退化为随机弃牌。

### ②【借刀杀人】所用【杀】未触发「使用」时机

**现象**：持刀者被要求使用的【杀】不触发【生息】等订阅「使用」时机的技能。

**根因**：响应端口按内容层声明分派主体时机（`scripts/core/match_controller.gd:5476,5526,5579-5581`）：

```gdscript
func _get_card_action_main_timing(action: String) -> String:
	return "useCard" if action == CARD_ACTION_USE else "respond"
```

而 `game_data/cards/jiedaosharen.gd:155` 把该次响应声明为 `"response_action": CARD_ACTION_PLAY`（打出），于是只派发 `respond`／`respondEnd`／`respondAfter`，`useCard` 系列永远不会触发。

**方案**：只把这一处声明改为 `CardDefinition.CARD_ACTION_USE`。

**为什么可行**：同一端口的副产物全部一致或改善——
- 实体回收走 `_move_played_card_to_discard`（`:5605-5619`），该函数对两种动作**完全同构**，只把动作名写进移牌原因；
- 公开日志动词由 `_get_card_action_verb`（`:5595`）给出，改为「使用了」，与卡牌正文「令一名装备武器的角色对合法目标**使用**」一致；
- 语音模式、表现认领、弃置批次隔离（不误触发【泛音】）均不受影响。

**替代方案与否决理由**：*改走 `execute_virtual_card_use` 完整用牌链路*：否决。`jiedaosharen.gd:164-189` 已经手工调用 `resolve_external_target` 完成这段【杀】的结算，再走完整链路会重复结算并与其手工上下文互相覆盖。

**已知边界（需在文档中写明）**：本路径只派发整牌时机 `useCard` 与 `useCardAfter`，不派发 `useCardBefore`／`useCard0..2`／`useCardTo*` 等逐目标子时机——因为持刀者的响应是单段入口，逐目标效果由这段【杀】自身的伤害流程承担。

### ③ 过关斩将不触发阿哈时刻

**现象**：过关斩将中场上明明有欢愉技，整轮都不出现阿哈时刻。

**根因**：**读档恢复路径漏配组件**。`resume_conquest_match` 先调用 `_teardown_previous_match_runtime()`（`match_controller.gd:15450`），而该函数会 `ahha_moment_system.shutdown()`（`:1583-1584`），`shutdown()` 把 `_enabled = false`（`scripts/core/ahha_moment_system.gd:128`）。恢复流程随后只重配了机缘组件（`:15481-15482`），**从未重配阿哈时刻组件**——全项目 `ahha_moment_system.configure` 只有普通开局的 `:1505-1507` 一处。于是该局剩余全程在门禁 `_can_trigger_now()`（`:397-399`，含 `_enabled`）第一行返回 `false`；同时 `_state` 还残留指向被丢弃的旧 `GameState`。

**排除的假设**：用户猜测的「敌方切换武将导致参演名单失效」不成立——`build_performance_order`（`:333-362`）每次实时读 `_host.skill_instances_by_player`，`_advance_to_next_valid_entry`（`:438-455`）每步重取技能实例，换将后的新欢愉技会自动纳入；本轮额度标记 `_triggered_this_round` 也已在 `shutdown()` 中归位。缺陷完全在门禁，不在名单。

**方案**：在 `match_controller.gd:15482` 之后补 `ahha_moment_system.configure(self, state, _rng, true)`。

**为什么可行**：位置满足全部前置条件——`state` 已在 `:15459` 重建、`_rng` 的种子与内部状态已在 `:15452-15453` 恢复、后续 `_rebuild_match_rule_services_and_root_event()` 与 `_start_turn()` 都在其后；写法与普通开局 `:1505-1507` 完全同构（含 `enabled = true` 的「对所有模式生效」口径）。

### ④ 判定区判牌顺序应为「后来居上」

**现象**：先进入判定区的延时锦囊先判定。

**规则依据**（官方规则集，逐字）：`三国杀规则集/游戏的流程 _ 三国杀官方规则集 3.0.html:808`
「角色须检测其判定区里是否有延时类锦囊牌：若有，进行其中**最后置入**其判定区里的那张延时类锦囊牌的使用结算，然后重复此流程」。

**根因**：`PlayerState.judgment_area` 是**置入顺序**数组（`card_movement_service.gd:226-227` 用 `append`，与 `player_state.gd:116` 注释一致），但判定流程固定取数组首：

```gdscript
# scripts/core/match_controller.gd:12770
var delayed_card: CardInstance = player.judgment_area.front()
```

即「先进先判」，与规则完全相反。

**方案（在两种可行方案中选择）**：

| 方案 | 内容 | 决策 |
|---|---|---|
| (a) | `card_movement_service.gd:227` 改 `append` → `push_front`，判定循环继续取 `front()` | ✗ 否决：会把「最后置入的在最左」变成界面显示顺序，看起来像把判定区整列翻了一次；且现有存档与测试里手工 `append` 构造的状态会与新语义不一致 |
| **(b) 采用** | 保持数组与界面显示为**置入顺序**，把判定取牌端从数组首改为**数组尾**（`front()` → `back()`） | ✓ 采用：改动面最小、界面显示不变，与规则原文「最后置入的那张」逐字对应 |

**必须一并修正的依赖方**（只有两处把「数组首位」当作「下一张被判定」）：

- `game_data/skills/xingqi.gd:126`：`owner.judgment_area.front()` → `.back()`，否则 AI 会为**错误的那张**延时锦囊找安全判定牌。
- `game_data/skills/yousi.gd:311-334`：只识别**最先被判定**的那张延时锦囊的花色，因此改为读数组最后一项（原注释「只有第一张延时锦囊能被牌堆顶第一张改写」同步改写为「最后置入的那张」）。

其余读取方（`guohechaiqiao.gd:63`、`shunshouqianyang.gd:63`、`feiyang.gd:28,44`、`haohuo.gd:176-177`、`huanfa.gd:248`、`linggan.gd:595`、`shanqing.gd:350`、`tongpao.gd:254,460,470`、`xianzou.gd:128`、`zhuxv.gd:205`、`slash_effect.gd:313`、`opportunity_system.gd:1038`）只计数或全量遍历，**顺序无关，不改**。

**顺带说明（不改）**：`match_controller.gd:6878` 的 `discard_n_from_player` 用 `pop_front()` 自动弃置判定区牌。该效果是「弃置区域内至多 N 张」的自动结算，原文未规定顺序，改动它对玩家无可感知收益，因此保留。

### ⑤【自摸】视为使用【借刀杀人】的目标枚举错误

**现象**：某些装备了武器的角色不能成为借刀目标；未装备武器的角色不能成为被杀者。

**根因**：`game_data/skills/zimo.gd:264-295` 先用 `list_legal_virtual_targets()` 取「单目标候选池」，再用**同一个池子**充当第 1、第 2 个位置：

```gdscript
for first in pool:
	for second in pool:
		if first == second: continue
		... validate_virtual_use(owner, definition_id, [first, second])
```

而 `list_legal_virtual_targets`（`scripts/core/card_rule_service.gd:212-239`）对每个候选都用**单元素数组**调 `_validate_target`（`:237`），【借刀杀人】的 `validate_target_selection`（`jiedaosharen.gd:100-115`）要求 `all_target_ids[0]` 必须是「另一名装备武器的角色」，于是池子被过滤成「①自己以外的持武器者」，连带产生两个后果：

1. 第 2 个位置也必须持武器 ⇒ **无武器者永远不能成为被杀者**；
2. 某持刀者若没有合法第二目标，它自己也不在池中 ⇒ **有武器者可能不能成为借刀目标**。

**方案**：把枚举改为**全体存活角色双循环 + 逐条完整组合校验**，直接照抄项目已有的正确先例 `game_data/skills/chuanchong.gd:155-174`。

**为什么可行**：权威端口本身接受这种有序双目标组合——`card_rule_service.gd:165 validate_virtual_use` → `:364` 对「声明保留顺序且目标数 > 1」的牌提前返回，逐位置校验由各牌自己的 `validate_target_selection` 完成，因此 `[持刀者, 无武器者]` 是合法的。候选池因此恢复成「真实可能」，而「能否结算」仍由同一个权威端口回答。

**附带加固**：`card_rule_service.gd:379` 的逐候选错误文本（「首个目标没有装备武器。」）只在 `all_target_ids[0] == target_id` 时才成立，否则会给出与实际位置不符的原因；把它收窄为「仅当该候选确实位于首位」时报告。这只影响**诊断文本**，不改变任何通过／拒绝结论。

### ⑥ 不可使用的【铁索连环】仍可指定目标

**现象**：被【独弈】禁止使用的【铁索连环】，手牌可点开并高亮目标，只是最后不能确认。

**根因**：用牌禁令（`SkillDefinition.validate_card_action_permission`，架构见 [`docs/架构说明.md:357-371`](../../../docs/架构说明.md)）只在 `validate_use`（`scripts/core/card_rule_service.gd:112-115`）里被咨询，而**目标枚举端口 `list_legal_targets`（`:243`）没有咨询**。于是对带 `recast: true` 的【铁索连环】：

- `match_controller.gd:2400-2401` 为它生成 `recast_card` 动作 → 牌进入 `chooseToUse` 的 `card_ids`（手牌可点，**这是正确的**：重铸是合法动作）；
- 目标候选来自 `list_legal_targets`（`:2488`）→ 禁令不生效 → 仍然返回候选；
- 只有 `can_submit` 为 `false`（`:2491`），于是「能选目标但不能确认」。

**对照**：距离不足的【杀】是正确的——核心不为它生成 `use_card` 动作（`:15982`），牌不入 `card_ids`，界面据 `is_interactable=false` 直接禁止点击。

**方案**：在 `list_legal_targets` 的入口（`card == null` 判断之后）咨询同一个聚合端口，被否决时返回空数组：

```gdscript
if skill_rule_provider != null and skill_rule_provider.has_method("validate_skill_card_action_permission"):
	if not str(skill_rule_provider.call("validate_skill_card_action_permission", actor_id, card, CARD_ACTION_USE)).is_empty():
		return result
```

**为什么可行**：`get_legal_actions`（`match_controller.gd:2410`）与界面预览（`match_table.gd:3169`）都从这一处取候选，改一处即同时收敛 AI 与界面。且不触碰「牌本身可点」这条链路，符合 [`docs/架构说明.md:108`](../../../docs/架构说明.md) 的「禁用状态只阻止规则动作，仍允许查看信息」。

**不改的地方（并需在文档说明理由）**：`list_legal_virtual_targets` 与 `validate_virtual_use` **不**咨询该禁令。禁令的语义是「手牌中的牌不能使用」，而虚拟牌（【自摸】的候选、丈八蛇矛的【杀】）不在手牌区；【独弈】自己的钩子也以 `card.zone != "hand"` 提前放行（`duyi.gd:53-54`），因此虚拟路径既不会漏用也不会误用禁令。核心层不得按牌名或牌类写白名单。

### ⑦【自摸】的 AI 不按牌面收益与目标评估虚拟牌

**现象**：青雀的 AI 几乎只会「自摸 → 对最友好的角色使用【杀】」，从不比较各候选虚拟牌的收益，也从不挑目标。

**根因（两层叠加）**：

1. **通用层把虚拟牌当成要支付的费用**。请求由 `request_virtual_hand_card_target_selection` → `request_card_target_selection(..., min_cards = 1, ...)` 创建，因此请求的 `min_card_select == 1`（`match_controller.gd:2958,3015`）。`scripts/ai/noname_ai_evaluator.gd:674` 的条件正是 `min_card_select > 0`：

```gdscript
elif choice_kind == "discard_phase" or ... or int(choice_request.get("min_card_select", ...)) > 0:
	return -selected_value
```

​	于是通用层在**到达目标态度评分分支（`:710-713`）之前就 return**，返回「候选牌保留价值的负值」。结果是：所有同一张牌的目标**组合同分**（AI 取枚举顺序第一项）；不同牌之间**越便宜越受偏爱**（【杀】价值最低）。
2. **技能层给的是常量**。`game_data/skills/zimo.gd:437-445` 只读 `selected_card_uids` 得到牌名，然后返回 `AI_COMMIT_REWARD + (0.5 if 杀)`，`_evaluator` 与 `selected_target_ids` **完全不参与**。

**方案**：把这一分支改成「构造代理用牌动作 + 交权威端口评分」，并关闭通用层叠加：

1. `zimo.gd:202` 的请求上下文补 `"ai_choice_skill_scored": true`。
2. `CHOICE_PICK_EFFECT` 分支改为：

```gdscript
var definition_id := ...  # 由 virtual_hand_definition_ids_by_uid 反查
var target_ids := payload.get("selected_target_ids", []) as Array
var proxy_action := {"action_type":"use_card", "actor_id":owner_player_id,
	"card_definition_id":definition_id, "card_color":"none", "target_ids":target_ids.duplicate()}
var score := evaluator.score_action(authoritative_snapshot, proxy_action, owner_player_id)
# 虚拟牌不消耗手牌：把通用层按「牌的保留价值」计入的幻影费用加回。
score += evaluator.get_card_value_by_id(definition_id, authoritative_snapshot, owner_player_id) * NonameAIEvaluator.CARD_COST_WEIGHT
return AI_COMMIT_REWARD + score
```

**为什么可行**：
- `evaluator.score_action` 是对外权威端口（`noname_ai_evaluator.gd:260`），完整覆盖卡牌 `ai` 配置（`order`／`player_result`／`target_result`）、目标的身份态度与状态倍率、防具拦截、连环传播、距离与响应资源——即「像手牌一样」判断收益与目标；`score_target_effect`（`:305`）已把友方目标计为负值，因此不会再打队友。
- 唯一需要补正的是 `:282` 的 `- card_value * CARD_COST_WEIGHT`：函数用 `get_card_value_by_id` 计的是「消耗这张牌的保留价值」，而【自摸】的候选只是选择介质、并不会真的失去那张牌，所以必须把该幻影费用加回。
- 保留 `AI_COMMIT_REWARD` 作为确认基线：`_continue_effect_selection`（`zimo.gd:328-336`）把「未确认」解释为**重开同一询问**，AI 一旦取消就会在同一处反复进入，表现为回合停滞；因此确认分必须恒大于取消的 `0.0`，逐候选的差异只用于在确认之间排序（差异量级为个位数，远小于 `AI_COMMIT_REWARD`）。

**替代方案与否决理由**：*在通用层为 `virtual_hand` 请求特判*：会让 AI 适配层认识一种协议形态并影响全部 `card_target` 请求，回归面大于收益；且项目原则是「同类内容的 AI 口径写在内容文件里」。故改在 `zimo.gd`，并留下 `ai_choice_skill_scored` 声明供后续同类技能复用。

**已知边界（需写入文档）**：本方案复用 `score_action`，因此不包含「卡牌自身 `modify_ai_action_score`」与「持有者技能 `modify_ai_card_action_score`」两级修正（它们由 `BasicAIPolicy` 的 `use_skill` 虚拟牌差分链路补入，选择链路没有对应端口）。对【自摸】的候选集合而言影响可忽略，且方向正确。

### ⑧【朱雀羽扇】询问按钮态被虚拟手牌退场动画覆盖

**现象**：自摸视为使用普通【杀】后，朱雀羽扇已在装备区高亮选中，但「确定」点不动；必须点击该装备**两次**（先取消选中、再重新选中）才能确认或取消。

**根因**：**延迟的手牌重渲染回写了询问期间的按钮态**。

- 虚拟手牌离场动画结束时调用 `_on_virtual_hand_exit_animation_finished`（`scripts/ui/match_table.gd:2529-2532`），末尾调用 `_render_local_hand()`；
- `_render_local_hand()` 的收尾（`:2391-2395`）**无条件**写 `use_button.disabled = true` 与 `%CancelButton.visible = false`；
- 此刻朱雀羽扇的询问已经建立（`request_equipment_trigger`，`match_controller.gd:7710-7727`），其按钮态是 `_refresh_inline_choice_text`（`:5156-5159`）刚设好的；
- 正常时序下 `_render_local_hand()` 总会被随后的 `_refresh_selection_text()`（`:3871`）修回，但**动画结束回调晚于该修复**，于是只剩破坏、没有修复。
- 自动选中本身仍在 `_inline_selected_card_uids` 里（`:3861-3863`），所以第一次点装备走的是「已选中 → 取消选中」分支（`:4287-4288`），第二下重新选中并顺带 `_refresh_selection_text()` 修复按钮——正是玩家描述的两次点击。

**方案**：让 `_render_local_hand()` 的收尾按钮写在「存在内联询问」时让位：

```gdscript
	# 内联询问期间按钮态由询问刷新函数唯一维护；本函数不得回写普通出牌态，
	# 否则延迟执行的手牌重渲染会覆盖刚建立的询问按钮（例如虚拟手牌退场动画晚于【朱雀羽扇】询问建立）。
	if _inline_card_choice.is_empty():
		use_button.disabled = true
		%CancelButton.visible = false
		%CancelButton.disabled = false
```

**为什么可行**：`_inline_card_choice` 正是内联询问的唯一真相（`:3856` 写入、`:5119` 起被各刷新函数读取）。让位后，正常时序与延迟时序的结果一致——都由询问刷新函数决定按钮态；无询问时行为与改动前完全相同。

### ⑨【刃】在斗地主不会用【杀】指定自己

**技能原文**（`game_data/skills/zhili.gd:41`，不可改）：
「锁定技，你是你自己使用【杀】的合法目标。……当你使用【杀】指定唯一目标时，你令此【杀】的目标改为与目标角色相邻的角色，此【杀】结算完毕后，你失去1点体力。」

**机制要点**：斗地主三人局中，刃指定**自己**时相邻集合就是另外两名角色（都是敌人），因此「指定自己」是最优打法。

**根因**：**代价项量纲错误，把 1 点体力算成了 4 分**。

- `game_data/skills/zhili.gd:188-189`：`evaluator.score_resource_change(snapshot, owner, owner, 0, -HP_COST)`
- `scripts/ai/noname_ai_evaluator.gd:220-225`：`resource_value * attitude / ATTITUDE_SCALE`，而自己对自己的态度恒为 `10`、`ATTITUDE_SCALE = 5.0` ⇒ 再乘 `2.0`
- 于是 `-1 × HP_RESOURCE_VALUE(2.0) × 10/5 = -4.0`，即文档口径的两倍。

斗地主中每次命中敌人的收益约 `+1.2`（态度 `8/5` 乘「手牌 ≥ 3」的 `status_multiplier = 0.5`），自指动作净分约 `-1.5 < 0`，低于 `basic_ai_policy.gd` 的 `ACTION_ACCEPTANCE_THRESHOLD`，AI 干脆不出牌。

**排除的假设**：不是候选生成问题——「自己」确实在合法目标里（`card_rule_service.gd:243-263` 遍历全体、`:366-370` 走技能豁免，由 `match_controller.gd:9640-9648` ← `zhili.gd:63-64 allows_self_as_card_target` 放行），合法动作枚举（`match_controller.gd:2410-2412`）也不过滤自己；也不是「目标是自已就判负」的通用逻辑（不存在）。

**方案**：`_score_self_hp_cost` 改用统一资源值直接计价：

```gdscript
func _score_self_hp_cost(_authoritative_snapshot: Dictionary, _evaluator: Object) -> float:
	# 统一资源口径：1 点体力按 HP_RESOURCE_VALUE 计价；持有者就是资源变化的目标，
	# 不能再乘一次自身态度（10/5）把代价放大一倍。
	return -float(HP_COST) * NonameAIEvaluator.HP_RESOURCE_VALUE
```

**为什么可行**：这正是 [`docs/AI模块.md:410`](../../../docs/AI模块.md) 已经写明的口径（「叠加持有者失去 `1` 点体力的统一资源代价 `HP_RESOURCE_VALUE`」），即**文档已声明、代码未落实**的偏差；`NonameAIEvaluator.HP_RESOURCE_VALUE` 也是内容层已成惯例的引用方式（`tongpao.gd:369`、`zhenqi.gd:33`、`zhuxv.gd` 等同构）。改后地主刃的自指动作约 `+0.5`，成为该局唯一正分的【杀】动作；二人局仍为负值，保留「不无故自伤」的原设计。

**不改的地方**：`NonameAIEvaluator` 的常量与 `score_resource_change` 本身不动——`tests/new_character_mechanics_test.gd:2072-2075` 断言「自身体力 = 牌值 2 倍」，那是通用换算口径的契约，本次偏差只在调用方多乘了一次态度。

**次生缺陷（本次一并记录、不在本任务修复）**：`basic_ai_policy.gd:331` 的「防具完全拦截」判定读的是**改写前**的 `action.target_ids`，因此刃自己装备藤甲／仁王盾时自指动作会被判成 `-INF`。它与本项症状无关，且修正它需要让通用层先咨询技能的 `preview_card_use_targets`，属于另一次设计变更。

### ⑩【自摸】选牌窗口的「取消」应暗置

**现象**：取消按钮亮着、可点，但点了没有任何效果。

**根因（两层）**：

1. **语义**：`zimo.gd:202` 以 `allow_cancel = true` 发出请求；而 `_continue_effect_selection`（`:328-336`）把「未确认」解释为**重开同一询问**——这个技能一旦发动就没有可放弃的出口，因此「取消」在语义上不存在。
2. **表现**：`scripts/ui/match_table.gd:5158` 无条件 `%CancelButton.visible = true`，`:5159` 只用 `disabled` 表达 `allow_cancel`。于是出现「可见但点击无效」——正是玩家指出的反模式。项目既有先例（`:2394`、`:4902`、`:4920`、`:4967`）都是直接 `visible = false`，没有统一的 `set_cancel_visible()` 入口。

**方案**：

1. `zimo.gd:202` 的 `allow_cancel` 传 `false`（选牌步骤不可取消；花色选择步骤保持可取消，因为它真的可以放弃且不会重开）。
2. `match_table.gd:5158` 改为按声明决定可见性：

```gdscript
	# 取消按钮按请求声明显示：不可取消的请求直接暗置，避免「可见但点击无效」的反模式。
	%CancelButton.visible = bool(_inline_card_choice.get("allow_cancel", false))
```

**为什么可行**：可见性与 `disabled` 从此同源（都读 `allow_cancel`），不再出现「看得见、点不动、点了也没用」；同时 `allow_cancel = false` 会让权威层不再枚举取消动作（`match_controller.gd:3427-3430`），AI 侧也不会产出空响应。第 2 点是**通用修正**，对所有声明为不可取消的内联询问一致生效，与既有 `visible = false` 先例方向相同。

**影响面核对**：`_refresh_inline_choice_text` 中依赖 `allow_cancel` 的两处下限抬高（`:5146`、`:5150`）对 `choice_type == "card_target"` 本就不生效（条件限定了 `card`／`respond`／`discard`／`target`），因此本改动不改变确认按钮的可用性判定。

---

## 4. 风险与回归面

| 风险 | 说明 | 缓解 |
|---|---|---|
| ② 改变动作类别会扩大「使用时机」的触发面 | 【生息】【山倾】【行峻】【月织】【织识】【复活】等 `useCard` 订阅者此后都会对这段【杀】触发 | 这是需求明确要求的行为；回归靠 `gameplay_regression_test`、`new_character_mechanics_test` 与借刀专项用例 |
| ④ 反转结算顺序 | 只有一处断言依赖 FIFO 的具体顺序（`tests/gameplay_regression_test.gd:1336,1351`），需按「后来居上」重写期望 | 同步修正该断言，并保留「判定区数组顺序 = 置入顺序」的界面契约 |
| ⑤ 扩大【自摸】候选组合 | 组合数由「持刀者²」变为「角色²」，仅在小规模（≤10 人）下枚举，无性能问题 | 逐条仍走 `validate_virtual_use` 权威校验；`tests/qingque_mechanics_test.gd` 覆盖 |
| ⑦ 替换 AI 评分 | 会改变青雀 AI 的实际出牌与目标选择 | 新评分方向与「像手牌一样」一致；用 `ai_policy_test` + 新增断言复核「不取消、选敌不选友」 |
| ⑨ 数值口径修正 | 只影响【支离】的自身体力代价 | `tests/zhuyan_zhili_test.gd` 的规则与原文断言不受影响（评分钩子未被现有用例覆盖） |
| ③ 恢复路径补配置 | 只影响读档恢复后的过关斩将 | `tests/conquest_save_test.gd` 覆盖恢复流程 |
| ⑩ 取消按钮可见性通用化 | 影响所有声明 `allow_cancel = false` 的内联询问 | 与既有 `visible = false` 先例一致；`ui_layout_test` 覆盖 |

---

## 5. 不做的事

- 不重构【借刀杀人】为完整用牌链路（与其手工 `resolve_external_target` 冲突）。
- 不改变判定区的置入顺序数组语义与界面从左到右的显示顺序。
- 不改 `NonameAIEvaluator` 的常量、`score_resource_change`、`ATTITUDE_SCALE` 与 `CARD_COST_WEIGHT`。
- 不修 `basic_ai_policy.gd:331` 的防具拦截前置目标问题（⑨ 的次生缺陷，仅记录）。
- 不在核心层新增任何牌名／技能名／区域白名单。
- 不新增武将、卡牌、技能、机缘或势力。
