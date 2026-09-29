# 内容文件的配套 AI 规范

> 权威来源：`docs/内容制作指南.md`「基础 AI 对内容字段的真实解释」、`docs/AI模块.md`、`AI相关内容.md`。
> 核心原则：**AI 只评分并返回动作，最终统一进入权威校验。AI 不直接造成伤害、回复体力、移动牌、修改身份或推进阶段。**

---

## 一、铁律：AI 与规则同文件维护

- 卡牌的通用 AI 数据写在卡牌自身 `game_data/cards/<拼音>.gd` 的 `super({...})` 元数据的 `ai` 字典中。
- 正式技能的规则代码与配套 AI **必须共同保存在该技能自己的** `game_data/skills/<拼音>.gd` 文件。
- **新增卡牌不得要求 `BasicAIPolicy` 增加卡牌 ID 白名单。**
- `trigger="sample_only"` 的占位技能**不得伪造可执行 AI**；技能完成规则接入后必须同时补齐 AI。

这条沿用无名杀的组织方式：技能规则与 `ai.check/order/result/effect/threaten` 同文件维护。

---

## 二、四层 AI 分工（内容文件只碰第一层）

| 层 | 文件 | 职责 |
|---|---|---|
| 身份观察 | `scripts/ai/identity_ai_model.gd` | 局势、态度、暴露度、忠反标记 |
| 身份战略 | `scripts/ai/identity_strategy_evaluator.gd` | 领袖危险、威胁、阵营集火、内奸控场、救援 |
| 牌效评估 | `scripts/ai/noname_ai_evaluator.gd` | 卡牌、响应、选牌与目标效用 |
| 动作选择 | `scripts/ai/basic_ai_policy.gd` | 组合内容钩子并选择最终合法动作 |

内容文件**只写静态 AI 数据与专属评分钩子**，不得直接修改身份模型或对局状态。

`BasicAIPolicy` 只在核心**已经生成的合法动作集合**中评分：

- 最高主动动作分必须**严格大于 `0`**，否则返回 `end_play`。
- 可取消选择的最高确认分也必须严格大于 `0`，否则返回 `confirmed=false`。
- **不可取消请求**无论分数正负，都必须提交当前合法动作中收益最高或代价最低的一项。

---

## 三、卡牌 `ai` 字典字段

| 字段 | 类型 | 用途 |
|---|---|---|
| `order` | `float` | 出牌顺序。总评分只按 `0.12` 权重使用，**不能代替真实牌效** |
| `value` | `float` 或 `Array[float]` | 手牌保留价值；数组表示同名牌越多后续副本价值可递减 |
| `equip_value` | `float` | 装备场面价值；换装时扣除同槽旧装备价值 |
| `player_result` | `float` | 使用者自身直接收益（摸牌、增益、装备） |
| `target_result` | `float` | 目标基础结果；正数表示帮助，负数表示伤害/弃牌/控制 |
| `damage` | `bool` | 启用低体力、少手牌、已知响应牌与救命牌修正 |
| `nature_damage` | `bool` | 启用横置角色的属性伤害传播估值 |
| `respond_sha` / `respond_shan` | `bool` | 目标是否需要响应【杀】/【闪】，用于命中率估算 |
| `recover` / `save` | `bool` | 回复或救援语义标签 |
| `draw` | `int` | 令目标**实际摸牌的张数**；无懈会把至少 `2` 张的敌方摸牌视为关键牌差 |
| `lose_card` / `discard` / `gain` | `bool` | 失去牌、弃牌或获得牌语义标签 |
| `skip_play` / `skip_draw` | `bool` | 跳过阶段的控制语义 |
| `multitarget` | `bool` | 多目标牌效标签 |
| `beneficial` | `bool` | 无懈可击中该锦囊通常是否有利 |
| `expose` | `float` | 使用该牌额外增加的身份暴露度 |

另有一组旧的扁平字段（`ai_use_value`、`ai_target_attitude`、`ai_beneficial`），缺省值分别为 `3.0`、`neutral`、`false`。

---

## 四、卡牌专属评分钩子

通用字段无法表达的动作，在**同一卡牌文件**覆盖：

```gdscript
func modify_ai_action_score(authoritative_snapshot: Dictionary, action: Dictionary, current_score: float, evaluator: Object) -> float
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float
func score_ai_play_phase_action(authoritative_snapshot: Dictionary, action: Dictionary, evaluator: Object) -> float
func build_ai_virtual_card_action(authoritative_snapshot: Dictionary, action: Dictionary, evaluator: Object) -> Dictionary
func get_identity_observation_target_result(authoritative_snapshot: Dictionary, actor_id: int, target_id: int, current_result: float) -> float
```

| 钩子 | 用途 |
|---|---|
| `modify_ai_action_score()` | 修正普通 `use_card` 动作（如【铁索连环】按横置状态反转目标意义） |
| `score_ai_choice()` | 修正本卡牌创建的确认、选牌、选目标或组合选择 |
| `score_ai_play_phase_action()` | 评估装备追加的自定义动作（木牛存粮、丈八两牌当【杀】） |
| `build_ai_virtual_card_action()` | 仅为**实际生成虚拟牌**的自定义动作返回只读 `use_card` 代理；非转化动作返回空字典 |
| `get_identity_observation_target_result()` | 只修正公开行为的身份暴露方向；**不得修改目标状态** |

技能侧对应入口：`append_play_phase_actions(result)` 追加 `action_type=use_skill` 的合法动作。

---

## 五、统一资源换算（禁止重复声明比例）

直接改变牌数或体力的技能必须调用 `NonameAIEvaluator.score_resource_change()`，或复用其公开资源常量：

| 常量 | 值 | 含义 |
|---|---|---|
| `CARD_RESOURCE_VALUE` | `1.0` | 1 张牌的统一资源价值 |
| `HP_RESOURCE_VALUE` | `2.0` | 1 点体力 = 2 张牌 |
| `RECAST_DRAW_VALUE` | `4.5` | 未知牌的原始牌质与保留价值；**只用于重铸、换牌和费用质量比较**，不表示直接摸 1 张的净资源收益 |

函数会再乘观察者对目标的态度比例。技能自身的 `sell_blood_value` 等专属权重按同一体系折算。

**不得在技能文件重复声明换算比例。**

---

## 六、通用评分中的既有数值（改动需谨慎）

以下数值已固化在 `BasicAIPolicy` / `NonameAIEvaluator` 中，**修改会影响全局 AI 行为**，必须同步 `docs/AI模块.md` 与《游戏机制与玩法内容》：

- 伤害目标：1 点体力乘 `2.5`，2 点体力乘 `1.8`。
- 手牌数修正：0/1/2/3 张以上手牌分别乘 `1.5 或 1.7` / `1.3` / `1.1` / `0.5`。
- 目标已知拥有所需响应牌：乘 `0.35`；无已知【闪】但有【八卦阵】：乘 `0.65`；1 点体力且有【桃】或自救【酒】：乘 `0.7`。
- 未被无视的【藤甲】令普通【杀】与两种伤害群体锦囊的确定无效目标收益为 `0`，火焰伤害 AI 收益乘 `2.0`。
- 每多 1 点预期伤害，目标效果乘 `2.0`；响应【闪】时每多 1 点真实 `damage_amount` 加 `4.0` 分，伤害不小于响应者当前体力+护盾时再加 `8.0` 分。
- 【无懈可击】储备：最后 1 张时普通非关键锦囊收益乘 `0.45` 并额外扣 `1.5` 分；【闪电】无懈收益乘 `0.10`；目标为 AI 本人且已有足量直接响应资源时收益乘 `0.20`。

技能侧的身份死亡后果由 `modify_ai_lethal_damage_consequence(snapshot, actor_id, target_id, current_score, evaluator)` 在基础结论之后修正。身份局基础分值为「击杀反贼 `+3.0`、击杀已确认同阵营 `-8.0`、主公误杀忠臣 `-(12.0 + 2.0×(手牌数+装备数))`」；改写击杀奖惩的技能必须先撤销通用层已计入的对应项，再加入改写后的真实收益，**只改评分，不改规则侧实际奖惩**。该钩子按行动者固有、模式、临时与局内技能依次执行，同一技能 ID 只执行 1 次，领袖技只在行动者身份确为领袖时参与。

> 具体战略数值（领袖危险、阵营集火、濒死救援等）见 `docs/AI模块.md` 与 `AI相关内容.md`。

---

## 七、AI 缓存边界（性能红线）

`IdentityAIModel` 在单次同步决策边界内：先完成固定身份观察同步，再最多遍历 10 名玩家 1 次建立索引，返回动作前**连同技能实例一起清空**。

**绝不跨决策缓存权威快照或决策结果。**

`NonameAIEvaluator` 与两个战略评估器分别缓存数据库返回的**静态元数据独立副本**，同一合法动作集合内按技能 ID 复用纯 AI 技能实例。

---

## Quality Check

- [ ] 新卡牌已在自身文件声明 `ai` 字典；未新增 `BasicAIPolicy` 白名单。
- [ ] 正式技能的规则与 AI 都在同一 `game_data/skills/*.gd` 文件。
- [ ] `sample_only` 占位技能未编写可执行 AI。
- [ ] 改变牌数/体力的评分复用了 `score_resource_change()` 与公开资源常量。
- [ ] 专属钩子只做**纯查询**修正，未修改对局状态或其他角色的隐藏手牌。
- [ ] AI 改动未影响其他武将/卡牌的既有决策。
- [ ] 已补全通用决策逻辑（不止实现需求中明示的分支），并说明补全内容及其作用域。
- [ ] 已跑 `tests/ai_policy_test.tscn`。
- [ ] `docs/AI模块.md` 与《游戏机制与玩法内容》已同步数值。
