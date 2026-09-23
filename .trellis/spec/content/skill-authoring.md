# 技能制作规范

> 权威来源：`docs/内容制作指南.md`「技能制作」全书（运行方式、静态参数总表、生命周期函数、规则修正与虚拟牌、主动/被动示例）。
> 铁律：玩家可见的技能描述文本必须与主公原文**逐字一致**（见 [`../project/collaboration-rules.md`](../project/collaboration-rules.md)）。

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
| `subscribe_timing(event_name, callback, role="player", priority=0, first_do=false, last_do=false, condition=Callable(), locked_segment=false, maintenance=false)` | 被动技能 | 以持有者身份订阅 228 个标准时机，自动绑定 `self` 与 `owner_player_id`，并把内容条件与持有者有效性条件组合；失败返回 `-1` |
| `install()` | 被动技能需要 | 订阅事件、触发器或查询修正 |
| `uninstall()` | 有自定义注册时需要 | 先清理修正管线，再 `super.uninstall()` 清理事件订阅 |
| `can_activate(context)` | 主动技能需要 | **无副作用**检查当前是否可发动，返回 `bool` |
| `activate(context)` | 主动技能需要 | 执行效果；成功返回**空字符串**，失败返回玩家可见错误文本 |
| `can_use_effect(locked_segment=false)` | 主动入口/查询/钩子统一使用 | 返回当前效果片段能否在「非锁定技失效」期间生效。完整锁定技恒 `true`；半锁定技仅当参数为 `true` 时保留锁定后段；其他非锁定效果返回 `false` |
| `can_trigger_while_owner_inactive(event)` | 仅死亡/离场后仍需触发的特殊技能 | 默认 `false`；不得为普通全局技关闭统一生存校验 |
| `announce_activation(context={})` | 效果**实际成立**时调用 | 写入 `skill_history`、对局日志并触发牌面提示；指定角色时 `context` 必须写 `target_id` 或按序列写 `target_ids`。**不得在取消、未支付费用或执行失败时调用** |
| `announce_activation_for_player(activator_player_id, context={})` | 跨角色发动时 | 同上传记归属到实际支付费用/执行效果的角色 |
| `observe_identity_behavior(target_ids, ai_profile)` | 有公开可选目标效果时 | 上报身份观察；只更新 AI 观察，不执行效果 |

`subscribe_timing` 补充：

- 普通技能持有者**死亡、离场或状态缺失后不再接收新时机**。
- 只负责移除旧持续效果的到期或死亡清理可传 `maintenance=true`，但**不得借此在失效期间产生新收益**。

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

---

## Quality Check

- [ ] 玩家可见 `name` 与 `description` 与主公原文逐字一致。
- [ ] 静态参数齐全；锁定技显式 `lock=true`；半锁定技后段订阅显式 `locked_segment=true`。
- [ ] `ui_enabled=true` 的技能已实现 `can_activate()` 与 `activate()`；`activate()` 成功返回空字符串。
- [ ] 所有主动入口/查询/钩子都经 `can_use_effect()` 复核失效状态。
- [ ] 每个创建交互的函数都有对应 `continue_*` 恢复实现。
- [ ] `context` 中**没有**节点、`PlayerState`、`CardInstance`、`Callable`。
- [ ] 令他人选择的场景使用 `*_for_player()` 包装，未把选择错误交给持有者。
- [ ] 效果实际成立时才调用 `announce_activation()`；带目标时写入了 `target_id`/`target_ids`。
- [ ] 正式技能已补配套 AI（见 [content-ai.md](./content-ai.md)）；`sample_only` 未伪造 AI。
- [ ] `docs/内容制作指南.md` 与《游戏机制与玩法内容》已同步新接口、规则与全部数值。
