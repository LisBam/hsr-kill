# 技术设计 · 阮梅武将与技能拥有查询机制

> 本文只写**跨子任务共享**的技术契约：技能拥有查询双层入口、全局限次存储、梅绽动态卖血估值、文档同步清单。
> 单技能的逐条结算设计见子任务 `10-18-ruanmei-character-skills/design.md`。

---

## 1. 技能拥有查询：双层契约

### 1.1 为什么是两层

技能代码同时包含两种运行环境：

| 段 | 运行环境 | 能拿到什么 | 适用入口 |
|---|---|---|---|
| 规则段（`can_activate` / `activate` / `continue_*` / 时机回调） | 真实对局，`host` 已绑定 | `MatchController` 权威状态 | **层 A · 权威端口** |
| AI 段（`score_ai_choice` / `score_ai_action` / `modify_ai_incoming_card_effect`） | `skill.bind(null, target_id)` 的无宿主评分实例 | 只有 `authoritative_snapshot: Dictionary` | **层 B · 快照纯函数** |

两层的**判定口径必须完全一致**（固有 + 模式 + 临时 + 局内获得，去重），否则同一条「是否拥有技能」的规则在规则段与 AI 段会得出不同答案。因此层 B 的实现写成静态纯函数，层 A 与层 B 共享同一份「来源清单」定义。

### 1.2 层 A · 权威端口（`scripts/core/match_controller.gd`）

```gdscript
## 判断指定角色此刻是否拥有指定技能。
## 口径：固有技能、模式技能、临时技能与局内获得技能统一按“已安装实例 ∪ 获得记录 ∪ 临时记录”判定，
## 因此【升变】军功授予的【奇袭】这类“视为拥有”的技能同样返回 true。
## 纯只读：不创建技能实例、不安装时机、不广播状态、不写日志。
## 不做存活过滤：死亡/离场角色的技能归属仍如实返回，调用方按自己的语义决定是否过滤。
func has_skill(player_id: int, skill_id: String) -> bool
```

- 实现位置紧邻既有 `get_installed_skill_ids(player_id)`（`match_controller.gd:10563`），复用同一容器语义。
- 判定集合 = `skill_instances_by_player[player_id]` 的键 ∪ `PlayerState.acquired_skills` 的键 ∪ `PlayerState.temporary_skills` 的键。
  - 之所以要并上两个记录字典：`remove_skill()` 的既有注释明确指出「实例为空但记录仍在时同样算‘拥有’」，只读实例容器会漏判这一状态。
- 空 `skill_id`、无效玩家、无对局状态一律返回 `false`，不写日志（查询不应产生副作用）。
- 技能侧调用：`host.call("has_skill", player_id, skill_id) as bool`。

### 1.3 层 B · 快照纯函数（`game_data/skill_definition.gd`，静态）

放在 `SkillDefinition` 而非新文件的理由：① 项目已有同类静态纯函数先例（`description_declares_tag`，且注释明确“技能源码、AI评分实例与内容测试可以共用同一套识别规则”）；② 技能文件 `extends SkillDefinition`，可以**裸调用**，无需 import；③ 避免为一个纯查询新增文件与新的加载顺序依赖。`skill_definition.gd` 已在同文件内引用 `GameDatabase`，不引入新的层间依赖。

```gdscript
## 收集玩家权威快照声明的全部技能ID并去重；技能拥有口径的唯一来源。
## 枚举顺序固定为 固有 → 模式 → 临时 → 局内获得，保证同一技能不会因来源顺序产生不同结果。
## 快照带 installed_skill_ids 字段时按其裁剪固有与模式技能：该字段是“此刻真实安装”的权威列表，
## 失去技能（如【留白】）后必须被裁掉，否则会把已经失去的技能算成仍然拥有。
static func collect_snapshot_skill_ids(player_snapshot: Dictionary) -> Array[String]

## 判断玩家权威快照是否拥有指定技能；等价于 collect_snapshot_skill_ids(...).has(skill_id)，
## 但直接做成员判定、不构造中间数组，供高频查询使用。
static func snapshot_has_skill(player_snapshot: Dictionary, skill_id: String) -> bool
```

判定细节（与层 A 对齐）：

| 来源 | 快照字段 | 是否受 `installed_skill_ids` 裁剪 |
|---|---|---|
| 固有 | `GameDatabase.get_character(snapshot.character_id).skills` | **是**（该字段存在时） |
| 模式 | `snapshot.mode_skill_ids` | **是**（该字段存在时） |
| 临时 | `snapshot.temporary_skills` 的键 | 否（键存在即代表此刻拥有） |
| 局内获得 | `snapshot.acquired_skills` 的键 | 否（同上） |

- `installed_skill_ids` 字段**不存在**时不裁剪（兼容旧快照与手工构造的测试快照），与既有 `shengbian.gd` / UI 的 `filter_by_installed` 写法一致。
- 空快照 / 空 `skill_id` → `false`；不读取任何隐藏信息（只读公开稳定 ID）。

### 1.4 既有重复实现的收敛清单

**本项是本次交付的核心价值：把 6 处各自实现收敛为 1 处，并修掉其中的既有缺陷。**

| # | 位置 | 现状 | 处置 |
|---|---|---|---|
| 1 | `scripts/ai/noname_ai_evaluator.gd:796` `_collect_snapshot_skill_ids` | 私有实现，注释自称“唯一来源”但**未按 `installed_skill_ids` 裁剪**（漏判：已失去的固有技能仍被计入） | 改为委托 `SkillDefinition.collect_snapshot_skill_ids`，缺陷随之修复 |
| 2 | `scripts/ai/noname_ai_evaluator.gd:787` `_snapshot_player_has_skill` | 私有布尔查询 | 改为委托 `SkillDefinition.snapshot_has_skill` |
| 3 | `scripts/ai/noname_ai_evaluator.gd:463` `_modify_incoming_card_effect_by_target_skills` 内联枚举 | 内联重复第三份 | 改用静态入口 |
| 4 | `scripts/ai/basic_ai_policy.gd:~398` 内联枚举 | 内联重复 | 改用静态入口 |
| 5 | `scripts/ai/identity_strategy_evaluator.gd:~263` 内联枚举 | 内联重复 | 改用静态入口 |
| 6 | `game_data/skills/shengbian.gd:~199` `_score_snapshot_merit_trigger_skills` 内联枚举 | 已按 `installed_skill_ids` 裁剪，是正确口径的来源 | 改用静态入口（保留其“只统计两类标签技能”的业务过滤） |
| 7 | `game_data/skills/yaoli.gd:191` `_owner_has_skill` | **只读武将固有技能列表**，漏判模式/临时/局内获得技能（缺陷） | 改用静态入口，缺陷随之修复 |
| 8 | `game_data/cards/huogong.gd:263` `_snapshot_has_skill` | 卡片侧私有重复 | 改用静态入口 |
| 9 | `scripts/ui/`（`information_box_layer.gd` / `player_target_view.gd` / `match_table.gd`） | 展示侧枚举，带**展示专属**的额外语义（技能栏顺序、`filter_by_installed` 开关、临时/获得技能单独收集） | **逐个核对**：语义等价者改用统一入口；确属展示专属（顺序、可见性开关）者保留，并在注释中写明「拥有口径来自统一入口，此处只做展示排序」 |

**收敛判据**：收敛后全项目「某角色是否拥有技能 X」的判断只有一处实现；`installed_skill_ids` 裁剪规则只有一处实现；任何新增技能都自动获得正确判定，不需要改动调用方。

**风险与对策**：收敛会改变 #1 与 #7 的行为（都是**修正**）。为避免误伤，先补回归用例锁定修复后的期望值，再替换实现；替换后跑 `ai_policy_test` / `gameplay_regression_test` / `new_character_mechanics_test` 全量确认无副作用。

---

## 2. 「全局每种类别 / 每种花色限一次」的存储与生命周期

### 2.1 存储位置

写入 `PlayerState.character_form_state`（角色私有形态状态），键为稳定字符串常量：

| 技能 | 键 | 值类型 | 值语义 |
|---|---|---|---|
| 【灵赋】 | `lingfu_used_card_categories` | `Array[String]` | 本局已被【灵赋】重铸过的牌类别集合，取值 `basic` / `trick` / `equipment` |
| 【阮弦】 | `ruanxian_used_suits` | `Array[String]` | 本局已被【阮弦】重铸过的花色集合，取值 `spade` / `heart` / `club` / `diamond` |

选它的理由：

- **原文写的是“全局”**：整局游戏一次性额度，不是每回合刷新。放在技能实例字段里会在「失去技能 → 重新获得」时静默复活，直接违反原文（【灵赋】分支二会令阮梅失去【灵赋】自身，这条路径**必然**被走到）。
- `character_form_state` 随权威存档往返（`player_state.gd:319/542`），读档不丢。
- 它不进公开快照（只有 `reveal_private` 才下发），但**全部 AI 快照都是 `to_dict(该AI的player_id, true)`**，因此 AI 能读到同一事实，与“重铸是公开动作”相符。
- 项目既有同类先例：`fengkou` / `shengxi` / `xiongxing` / `xinxing` 等都用该容器保存本局私有计数。
- 经核对，`character_form_state` 在全项目**没有任何清空点**（只出现在 `player_state.gd` 的序列化与 `player_effect_service.gd` 的重建读取），因此「复原武将牌 / 机缘卡 / 换将后重新获得技能」都不会复活额度，符合“全局”。

### 2.2 写入时机与幂等

- **只在重铸真实发生后写入**：以 `host.call("recast_hand_card", ...)` 的布尔返回值为准；返回 `false`（牌已不在手牌、不是普通手牌等）时不写额度、不进入后续效果。
- 写入即去重追加，重复调用不产生第二条记录。
- 读取时对字段做类型收敛（非 `Array` 一律按空集合处理），避免旧存档或异常写入导致崩溃。

### 2.3 候选枚举与额度判定的单一入口

每个技能内部提供一对私有函数，规则段与 AI 段共用同一份“可用材料”定义：

```gdscript
## 返回本技能当前仍可重铸的候选牌（已按全局额度过滤）。
func _get_recast_candidates() -> Array[Dictionary]
## 返回该类别/花色是否仍有全局额度。
func _has_global_quota(key: String) -> bool
```

AI 段（`score_ai_choice`）**不得另建一套额度判断**，必须复用同一常量与同一字段名。

---

## 3. 【梅绽】动态卖血估值

### 3.1 语义

原文：`当你受到伤害后，所有拥有技能”梅绽”的角色各摸一张牌。`
即：**任意一名梅绽持有者受伤，场上每名梅绽持有者各摸1张**（按伤害事件结算一次，不随伤害点数翻倍）。

以**出手方（AI 自己）**为参照系（用户决策）：

> 修正分 =（对出手方态度为正的梅绽持有者数 − 态度为负的梅绽持有者数）× 1张牌

- 自己永远计入“我方”。
- 只统计**存活且未离场**的角色（死亡/离场者不会摸牌）。
- 态度为 `0`（中立 / 身份未暴露）的持有者不参与计数，与项目既有“中立关系不修正”口径一致。

### 3.2 为什么用 `sell_blood_value = 1.0` + 动态钩子，而不是纯静态或纯动态

| 方案 | 问题 |
|---|---|
| 纯静态 `sell_blood_value = 1.0` | 只表达“受伤者自己摸1张”，无法表达其余持有者的跨阵营收益 |
| 纯动态（`sell_blood_value = 0.0` + 钩子） | `_should_decline_dodge_against_ally_sell_blood_slash()` 读的是 `get_snapshot_sell_blood_value(responder) > 0`，静态值为 0 会让梅绽持有者**完全不**被视为卖血角色，与“梅绽算卖血技能”的要求冲突 |
| **静态 1.0 + 动态钩子追加其余持有者** | 既有静态消费者照常生效；总修正分在两个分支上都精确等于正确值（见 3.3 推导） |

### 3.3 正确性推导（锁定两个分支都不反号）

记出手方为 `A`，目标为 `T`（`T` 拥有【梅绽】），其余梅绽持有者集合为 `O`。

- 通用静态路径（`noname_ai_evaluator.gd:497-500`）贡献：`attitude(A→T) > 0` 时 `+1`，`< 0` 时 `−1`，`= 0` 时 `0`。这正好等价于“把 `T` 自己算进净计数”。
- 钩子追加：`Σ_{P ∈ O} sign(attitude(A→P))`（正 `+1`、负 `−1`、零 `0`）。
- 合计 = `Σ_{P ∈ 全体存活梅绽持有者} sign(attitude(A→P))` = 3.1 的公式。∎

两个分支都无需翻转符号，因此**不改动** `_modify_incoming_card_effect_by_target_skills` 的通用符号逻辑。

### 3.4 实现落点

在 `game_data/skills/meizhan.gd` 覆盖既有钩子（`skill_definition.gd:770` 的基类默认实现），无需任何基础设施改动：

```gdscript
func modify_ai_incoming_card_effect(authoritative_snapshot, actor_id, target_id, definition,
        ai_profile, target_result, expected_damage_amount, current_score, evaluator) -> float
```

- 仅当 `ai_profile.damage == true`（伤害类来牌）时生效——非伤害牌不会触发“受到伤害后”。
- 遍历 `authoritative_snapshot.players`，用层 B 的 `SkillDefinition.snapshot_has_skill(P, "meizhan")` 判定持有者，`P.player_id == target_id` 者跳过（已由静态路径计入）。
- 态度经 `evaluator.get_attitude(snapshot, actor_id, P.player_id)` 读取，**不使用** `get_real_attitude`（会泄露隐藏身份）。
- 数值尺度统一用 `NonameAIEvaluator.CARD_RESOURCE_VALUE`（项目内技能读取该常量的既有写法，如 `bingfeng.gd:15`），不写字面量 `1.0`。
- 纯只读：不修改伤害量、不修改摸牌数、不修改任何技能状态。

---

## 4. 文档同步清单（跨子任务）

| 文档 | 必须写入的内容 |
|---|---|
| `docs/内容制作指南.md` | ① 「常用规则操作端口」表补 `has_skill(player_id, skill_id)` 行；② 「技能制作」章补「技能拥有查询双层入口」小节（层 A 端口 + 层 B 静态函数 + 使用示例 + `installed_skill_ids` 裁剪规则）；③ 补「全局限次记录存入 `character_form_state`」的约定与稳定键命名规范；④ 补 `modify_ai_incoming_card_effect` 作为“需要按场面定价的卖血价值”落点的说明；⑤ 补「重铸先于后续效果」的 `defer_settlement` 用法 |
| `docs/游戏机制与玩法内容.md` | 阮梅武将条目 + 【梅绽】【灵赋】【阮弦】的机制与**全部具体数值**：摸牌数 `1`、体力上限增量 `+1`、回复量 `1`、出牌阶段次数 `1`、全局类别数 `3`、全局花色数 `4`、AI 评分数值 |
| `docs/AI模块.md` | ① 技能拥有查询入口（AI 侧用静态纯函数）；② 梅绽动态卖血估值口径与参照系；③ 说明“新增卖血技能只需声明元数据或覆盖钩子，禁止技能 ID 白名单” |
| `docs/卡牌系统.md` | 仅在需要澄清「重铸不算使用/打出/弃置、且不派发 `cardsDiscardedBatchAfter`」时补充；本次预计**无需改动**，实施时核对 |
| `README.md` | 若含武将 / 技能计数则同步更新 |

---

## 5. 风险与回滚

| 风险 | 影响 | 对策 / 回滚点 |
|---|---|---|
| 收敛 AI 技能枚举改变既有 AI 决策 | 可能引起 `ai_policy_test` 等回归 | 先补期望值用例 → 再替换 → 全量跑；单点 `git checkout` 对应文件即可回滚 |
| `installed_skill_ids` 裁剪规则引入到 AI 侧 | 失去技能的目标不再被高估（修正），但可能改变既有对局结果 | 该裁剪本就是 UI/`shengbian` 的既有正确口径；回归用例锁定 |
| `defer_settlement` 顺序处理不当导致“先结算后重铸” | 【灵赋】核心操作顺序错误 | 专用回归用例断言「重铸完成后目标才获得技能」；回滚点是 `lingfu.gd` 的 `activate`/`continue_settlement` 两个函数 |
| 全局限次写入时机过早（重铸失败也记账） | 额度被白白消耗 | 只以 `recast_hand_card` 返回值记账；用例覆盖“牌已离手”场景 |
| 梅绽动态钩子遍历全体玩家造成性能问题 | 每次来牌估值多一次 O(玩家数) 扫描 | 玩家上限 10，且钩子只在目标确实拥有【梅绽】时被调用；可接受 |
