# 卡牌制作规范

> 权威来源：`docs/内容制作指南.md`「卡牌制作」全书，以及「通用制作规范」中的事件与阶段安全条款。

---

## 一、工作流程

1. 在 `docs/内容制作指南.md` 中检索是否已有可复用机制与函数。
2. 在 `game_data/cards/<拼音>.gd` 新建文件，`extends CardDefinition`。
3. 在 `_init()` 中通过 `super({...})` 写入**完整静态信息**与 `ai` 字典。
4. 在本文件实现效果入口（`resolve()` / `resolve_target()` / 各类钩子）。
5. 把卡牌登记进 `data/decks.json`。
6. 同步 `docs/卡牌系统.md`、`docs/游戏机制与玩法内容.md`（含全部具体数值）。

---

## 二、完整模板（可直接照抄结构）

下面的示例牌只能对自己使用，效果为摸 1 张牌：

```gdscript
extends CardDefinition

## 【示例牌】卡牌源码。静态信息、目标规则与效果入口均在本文件维护。


## 写入卡牌完整静态信息；所有字段会由 GameDatabase 自动建立只读索引。
func _init() -> void:
	super({
		"id": "shilipa",
		"original_name": "示例牌",
		"custom_name": "示例牌",
		"type": "trick",
		"subtype": "normal",
		"effect_id": "example_draw_one",
		"nature": "normal",
		"target_mode": "self",
		"min_targets": 1,
		"max_targets": 1,
		"distance_limit": "none",
		"play_limit": 0,
		"response_pattern": "wuxie",
		"recast": false,
		"delayed": false,
		"description": "出牌阶段对自己使用，摸1张牌。",
		"resolution_mode": "per_target",
		"final_zone": "discard",
		"provided_response_pattern": "",
	})


## 目标未被【无懈可击】抵消时摸1张牌；选择等待期间返回 pending 保持当前内容事件暂停。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	for target_id: int in target_ids:
		if resolver.should_skip_trick_target(card, actor_id, target_id):
			continue
		resolver.host.draw(target_id, 1)
	return resolver.default_destination()
```

---

## 三、必填字段

### 数据库真正强制的 7 项

`original_name`、`custom_name`、`type`、`subtype`、`effect_id`、`target_mode`、`description`。

> 参数表中标记为必填的其他字段属于**规则完整性制作规范**。遗漏时部分核心会使用默认值，但**不应依赖这种容错创建正式内容**。

### 关键字段语义

| 字段 | 取值 | 说明 |
|---|---|---|
| `type` | `basic`、`trick`、`equipment` | 主类别，影响牌面类别文本与颜色；其他字符串无完整 UI 与规则保证 |
| `subtype` | 见指南「卡牌子类型」表 | 装备的 `weapon`/`armor`/`offensive_mount`/`defensive_mount`/`treasure` 决定牌面底部文本 |
| `effect_id` | 任意非空稳定字符串 | **只用于规则语义、事件与扩展查询，不会按值自动执行牌效**；自定义效果必须在本文件实现 |
| `nature` | `normal`、`fire`、`thunder` | 伤害属性；非伤害牌通常填 `normal` |
| `target_mode` | 见指南「目标模式」表 | 决定哪些玩家可成为候选目标 |
| `min_targets` / `max_targets` | ≥0，且 min ≤ max | 全体牌当前用 `max_targets=99`；实际受存活人数与规则修正限制 |
| `distance_limit` | `none`、`one`、`attack_range`、`special` | `special` 表示由专用逻辑处理，通用规则不自动校验 |
| `play_limit` | ≥0，`0` 为无限 | 由通用历史统计执行，**不按具体牌名判断** |
| `play_limit_group` | 稳定 `[a-z0-9_]+` | 共享次数的多张牌填同一值，例如三种【杀】都填 `slash` |
| `play_limit_scope` | `turn`（缺省）、`phase` | 【杀】牌族用 `phase`；【酒】继续用 `turn` |
| `response_pattern` | `""`、`sha`、`shan`、`tao`、`jiu`、`wuxie` | 牌效关联的响应语义；普通可被无懈的锦囊填 `wuxie` |
| `provided_response_pattern` | 同上 | 该**实体牌自身**能作为哪种响应打出 |
| `recast` | `true`/`false` | 是否允许从普通手牌重铸；木牛「粮」不能重铸 |
| `delayed` | `true`/`false` | 延时锦囊；`true` 会启用同名判定区限制，并要求实现判定阶段效果 |
| `resolution_mode` | `per_target`、`whole` | `per_target` 为每名目标创建独立内容事件；`whole` 一次取得完整目标数组 |
| `final_zone` | `discard`、`equipment`、`judgment` | 正常使用后的目标区域语义，也用于中央牌面判断是否接管弃牌动画 |
| `rule_name` | 任意非空 | 只供规则文本与牌族查询统一称呼；火【杀】、雷【杀】都填「杀」，而 `original_name`/`custom_name` 仍填「火杀」「雷杀」 |

### 装备专有字段

| 字段 | 说明 |
|---|---|
| `slot` | 装备进入的唯一槽位（五选一） |
| `attack_range` | 武器攻击范围，`1` 以上；小于 1 会被规则层修正为 1 |
| `distance_modifier` | 进攻坐骑填 `-1`，防御坐骑填 `1`；必须与槽位规则一致 |
| `response_material_count` | 作为响应入口时还需选择的普通手牌材料数 |
| `play_phase_interaction` | 出牌阶段主动交互类别；空字符串表示没有主动入口 |
| `play_phase_action_type` | `PlayerAction.action_type`，必须同时由装备文件的动作钩子声明和处理 |
| `play_phase_material_count` | 主动效果需要选择的普通手牌材料数 |
| `play_phase_action_card_source` | `equipment` 或 `material`，决定动作 `card_uid` 来源 |
| `shows_attachment_count` | 是否在装备区显示附属牌数量 |

> UI 字段**不能代替**权威校验：核心仍会调用装备源码的 `validate_play_phase_action()` 或响应材料校验。

---

## 四、效果实现的硬约束

### 1. 效果写在本文件

`CardEffectResolver` 只是**纯调度器**：按卡牌 ID 调用 `resolve`/`resolve_target`，并按父牌 UID 把选择、响应和专用无懈结果交回原卡牌文件。它**不包含任何具体牌效函数**。

### 2. 事件步骤必须有终态或推进

每个 `GameEvent` 内容步骤执行后必须至少满足一项：

- 推进到下一步骤
- 调用 `finish`/`cancel`/`neutralize`/`abort` 进入终态
- 通过 `create_child()` 插入真实子事件
- 通过 `request_choice()` 等入口取得暂停 token
- 在明确修改有限游标后调用 `redo()`/`goto()`

**禁止**在没有上下文变化、子事件或暂停点时永久 `redo()`。

调度器每次 `drain()` 默认最多执行 **256** 个操作，达到预算后延后一帧继续；同一事件同一步无等待连续重跑超过 **2048** 次会以 `runaway_step` 中断当前事件并继续父流程。

> 内容作者不得依赖「一个超大事件树必须在同一帧全部结束」；需要读取结果的逻辑应放在父事件后续步骤或 after 事件中。

### 3. 阶段推进只能走控制器端口

- **禁止**内容脚本直接写 `GameState.current_phase` / `phase_index` / `current_player_id`。
- **禁止**直接调用 `GameFlowPacer.schedule("phase_transition", ...)`。
- 需要改变阶段后继的技能必须使用现有**额外阶段队列、阶段转换或跳过端口**，并在原阶段登记转换之前完成规则选择。

### 4. 伤害与回复的时机选择

- 需要在目标**濒死、救援与死亡判定都完成后**处理效果 → 订阅 `damageSource` 并使用 `role="source"`，校验 `event.source_id`、正数 `amount` 与目标存活状态。
- 只需在伤害后半段、**不依赖濒死结论** → 订阅 `damageAfter`。
- 固定目标的可选回复可创建**零材料确认请求**；恢复时重新读取目标状态再调用 `recover(...)`；**异步等待期间不得保留旧 `PlayerState` 引用**。

### 5. 高频错误：`Object.call` 与强类型数组参数

通过 `Object.call()`、`Callable.call()` 或动态端口调用参数类型为 `Array[int]`、`Array[String]`、`Array[Dictionary]` 的函数时，**禁止**直接传 `[value]`、`[]`、`some_array.duplicate()` 等可能被推断为普通 `Array` 的表达式。

GDScript 的动态调用不会自动把普通 `Array` 转换为强类型数组，运行时会报：
`The array of argument ... does not have the same element type as the expected typed array argument`

```gdscript
# 错误：字面量通常是普通 Array，静态解析可能不会在 Object.call 处提前报错。
host.call("execute_cardless_virtual_card_use", owner_player_id, "huogong", [target_id])

# 正确：先构造与端口签名 Array[int] 完全一致的参数。
var target_ids: Array[int] = [target_id]
host.call("execute_cardless_virtual_card_use", owner_player_id, "huogong", target_ids)
```

从普通快照数组、字典值或 `duplicate()` 结果恢复强类型数组时：

- 新建强类型结果并逐项 `append()`，或在类型确定且版本支持时使用 `assign()`。
- **不得**只写 `as Array[int]` 就假定运行时会转换元素类型。

> 新增动态端口调用的测试**必须实际执行该调用**，不能只测试前置合法性查询——这类错误不会被「只加载脚本」或「只检查目标列表」的测试发现。

---

### 6. 执行牌效的路径必须经过权威目标校验

「使用牌不可被指定为目标」只有**一条**权威链路：`SkillDefinition.validate_incoming_card_target_selection(actor_id, card_definition, card_color)` → `MatchController.validate_incoming_skill_card_target_selection()` → `CardRuleService._validate_target()`。`validate_use()`、`validate_virtual_use()`、`list_legal_targets()`、`list_legal_virtual_targets()` 四条正常用牌链路全部走它，**核心层不维护任何牌名或技能白名单**。

因此新增任何「会实际执行某张牌牌效」的路径时（强制用牌、代理用牌、二次结算等），必须先回答：**这条路径经过权威目标校验了吗？** 只靠「存活 + 非自身 + 距离」自行拼装目标判据，会静默绕过全部卡牌目标模式、使用者技能目标限制与目标持有技能的来牌限制（【琥珀】等），且这类漏洞**只在特定内容组合下才暴露**。

强制用牌（发起者与执行者不是同一角色，执行者往往也不是当前行动者，例如【借刀杀人】要求持刀者使用的【杀】）必须使用专用的阶段无关端口，**不得**改用 `validate_use()`（阶段、持牌区域与次数三道闸门会全部误报）：

- 声明期枚举：`card_rules.list_legal_targets_for_definition(执行者, "sha", {"ignore_phase_limit":true, "ignore_play_count_limit":true})`。
- 单目标资格：`card_rules.validate_target_only(actor_id, definition_id, target_id, rule_overrides)`。
- 真实牌到手后复核：`card_rules.validate_entity_card_target(执行者, 实体牌, 目标)`，颜色强制取实体牌自身颜色，调用方**不能覆盖颜色**。

**两个必须记住的边界**：

1. **任何目标复核都必须传单元素目标数组**。`_validate_target()` 在牌源码 `preserves_requested_target_order()` 返回 `true`（【借刀杀人】等）且目标数组长度大于 1 时**直接判定通过**；带整组目标复核等于让被指定的角色绕过全部来牌限制。
2. **限制要按「判定所需信息何时可得」分层**：颜色无关的限制在声明期即可排除该角色；颜色相关的限制（【琥珀】只拒绝黑色【杀】）在声明期只有无色的抽象牌，必然通过，必须在执行者交出真实牌之后复跑一次。无名杀的 `filterAddedTarget` + `game.Check.target` 正是这个分层。

---

## Quality Check

- [ ] `_init()` 中的静态字段齐全，且已写 `ai` 字典（见 [content-ai.md](./content-ai.md)）。
- [ ] 效果写在卡牌文件内，未在核心新增牌名分支。
- [ ] 所有事件步骤都有推进/终态/子事件/暂停点，没有裸 `redo()` 死循环。
- [ ] 未直接改写阶段字段；阶段变更走控制器端口。
- [ ] 所有动态端口调用已按签名构造**强类型数组**。
- [ ] `context` 只含可序列化数据（数字/字符串/布尔/数组/字典）。
- [ ] 卡牌已加入 `data/decks.json`；`validation_errors` 为空。
- [ ] `docs/卡牌系统.md` 与《游戏机制与玩法内容》已同步全部数值。
