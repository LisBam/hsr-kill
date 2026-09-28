# 技术设计：那刻夏（逐虚 · 揭质 · 留白）

> 承接父任务 `.trellis/tasks/09-28-three-new-characters/design.md`。本文件只写本批特有设计。
> 需求与验收见同目录 `prd.md`；本批独占父任务缺口表中的 **M2 / M3 / M4** 三项。
> 实施顺序固定为 **M2 → M3 → M4 → 内容层**：M2 只增不改、风险最低；M3 引入持久化字段；M4 复用 M3 的卸载路径。

---

## 一、技能形态判定

### 【逐虚】= 2 节轮回技 + 主动技（出牌阶段限两次）

原文：`轮回技，出牌阶段限两次，你可①弃置随机一名有牌的角色随机一张牌；②对随机一名角色造成1点伤害。`

**关键理解**：两节**共用**同一个「出牌阶段限两次」额度，而一个完整轮回恰好是 2 步。「整个技能限两次」与「轮回服务自带的每轮回节限次」是**两套独立额度**，必须并存复核，不能只留一套：

| 轮回节 | 效果 | 目标范围 | 随机层数 |
|---|---|---|---|
| ① | 弃置该角色区域内随机一张牌 | 当前**有牌**的角色（含自己） | 两层：角色等概率 → 该角色区域内牌等概率 |
| ② | 造成 1 点伤害 | **全部存活**角色（含自己，无「有牌」限制） | 一层：角色等概率 |

「出牌阶段限两次」不写成 `reincarnation_each_section_once_per_play_phase`：后者语义是**每个轮回节各限一次**（走完一轮 = 4 次发动），与本技能的「整个技能限两次」不同。因此额度由技能私有计数器承担，并在 `phaseUseBegin` 复原（沿用 `kance.gd` 的既有范式）。

**元数据**：

```gdscript
super({
    "id":"zhuxv",
    "name":"逐虚",
    "trigger":"active/phaseUse",
    "enable":"phaseUse",
    "ui_enabled":true,
    "reincarnation":true,
    "reincarnation_section_count":2,
    "reincarnation_has_explicit_sections":true,
    "description":"<原文逐字>",
})
```

### 【揭质】= 被动技（每局限两次）

原文：`每局游戏限两次，当你发动“逐虚”后，你可对相同目标执行一次相同的效果。`

- **不是限定技**：`limited` 会让 UI 与 AI 按「每局一次」呈现，且 `get_used_limited_skill_ids` 会把它算进限定技集合。本技能用私有 `_used_count` + `PER_GAME_LIMIT = 2` 承载，与 `limited` 解耦。
- **触发点**：逐虚的**每一节**实际结算完成后（① 与 ② 均可）。由逐虚在效果收尾处显式通知，而不是让揭质自己猜时机——逐虚知道「本次是哪一节、目标是谁」，这是权威信息。
- **重复语义**：对**同一名目标**再执行一次**同一节效果**，即重新走一次该节的随机层（① 再随机弃其一张，② 再造成 1 点）。
- **非法目标**：目标在重复执行时已死亡、离场或（① 情形）已无牌可弃，则**不开放发动入口**（`can_use_effect` 返回 false），既不消耗次数也不产生空动作。

### 【留白】= 限定技 + 延迟清算（双段）

原文：`限定技，出牌阶段，你可重置所有其他技能。本回合结束时，你失去所有技能。`

- 第一段（立即，出牌阶段主动发动）：**重置所有其他技能**——不含留白自身。
- 第二段（延迟，本回合结束时机）：**永久失去全部技能**——含留白自身。
- 顺序固定：先重置、后失去，不得调换或合并。延迟段用 `turnEnd` 订阅实现，并**在该回合内保持订阅存活**（留白尚未被移除）。
- `limited` 为真（真正的限定技）；`limit_scope` 按项目既有推导，第一段失败时**不消耗**限定技额度（沿用 `activate` 返回 false 即不记账的既有约定）。

---

## 二、权威层改造落点（M2 / M3 / M4）

### M2 技能可用的随机端口

**问题**：技能若自建 `RandomNumberGenerator` 或调用裸 `randi()`，会脱离权威随机流，导致存档 `rng_state` 复现与联机确定性失效。

**落点**：`scripts/core/match_controller.gd` 新增一个通用端口，与既有「随机取牌」范例（`get_random_zone_card_uids_for_each_player`，`MC:6509`）保持同一套 `_rng` + `state.random_history` 契约：

```gdscript
## 从候选集合中等概率取一项并写入随机历史；技能随机效果必须经此入口以保证存档与联机确定性。
func pick_random_candidate_index(candidate_count: int, history_kind: String = "", history_data: Dictionary = {}) -> int
```

- 返回**索引**而非元素：调用方保留对自己的候选数组的类型控制（GDScript 的 `Array[int]` / `Array[Dictionary]` 异构候选不适合统一返回值类型）。
- `candidate_count <= 0` 返回 `-1`，由调用方按「无效果」处理，端口本身不抛错。
- 每次调用都写入 `state.random_history`（`kind` 缺省为 `skill_random_pick`），使固定种子下的随机结果可复盘——这也是 AC4 的断言依据。

### M3 固有技能永久移除端口

**问题**：现有 `_uninstall_all_character_skills` / `_reinstall_character_skills_for_player` 只卸载**实例**；任何后续的换将、觉醒、存档恢复、局内获得都会把技能装回来，无法表达「本局永久失去」。

**落点**：

1. `scripts/data/player_state.gd` 新增持久化布尔字段 `skills_permanently_removed`（默认 false）。
   - 该字段必须进入存档序列化，否则读档后技能会复活。
   - LAN 公开快照需暴露该字段：其他客户端据此把该角色的技能栏画成空，而不是继续显示对手已经失去的技能。
2. `scripts/core/match_controller.gd` 新增端口：

```gdscript
## 本局永久移除指定角色的全部技能；写入不可逆标记，使后续所有安装路径均不再为其装配技能。
func remove_all_skills_permanently(player_id: int, reason: String = "") -> bool
```

   端口职责：卸载全部实例（事件总线订阅随之释放）→ 清空 `player.acquired_skills` → 清空轮回进度 → 置 `skills_permanently_removed = true` → `_emit_state()`。
3. **所有安装/授予路径都必须复核该标记**（这是 M3 的完整性要求，缺一处即「技能复活」bug）：

| 路径 | 位置 | 处理 |
|---|---|---|
| 开局全量安装 | `_install_all_character_skills`（`MC:9224`） | 跳过该玩家 |
| 换将重装 | `_reinstall_character_skills_for_player`（`MC:9267`） | 卸载旧实例后不再装配 |
| 局内获得技能 | `grant_acquired_skill`（`MC:8650`） | 直接返回 false |
| 读档恢复运行时技能 | `_reinstall_saved_runtime_skills`（`MC:13623`） | 跳过 |

### M4 强化「重置技能」端口

**问题**：留白要复原的五类额度**全部散落在技能实例的私有字段里**——限定技已发动标记、`kance.gd: _used_this_play_phase` 这类阶段额度、每回合额度、觉醒技已发动标记、轮回技的 `_reincarnation_*` 进度。核心层没有任何通用接口能逐个访问它们。

**方案：重建实例**。卸载并按定义重新装配，让所有私有运行时状态自然归零，不需要为每个技能新增「重置自己的额度」方法（那会引入「新技能忘记实现」的长期漏点，与 AC7「逐项断言」的完备性要求冲突）：

```gdscript
## 重置指定角色除排除项以外的全部技能；以重建实例一次性归零限定技、阶段额度、回合额度、
## 觉醒技与轮回进度等散落在技能私有字段中的运行时状态。
func reset_all_other_skills(player_id: int, exclude_skill_id: String = "") -> int
```

**必须处理的三个细节**：

1. **排除项保留原实例**。若把留白自身也重建，「限定技已发动」标记会一起归零，留白即可无限发动——这是本设计最危险的退化点。实现上先把排除项实例取出，重建完成后回填。
2. **局内获得技能要一并重建**。`_reinstall_character_skills_for_player` 只装配「武将固有技能 + 模式技能」，会丢掉 `grant_acquired_skill` 获得的技能。因此需要读取 `player.acquired_skills` 的**限额定义**（`source` / `per_turn_limit` / `per_round_limit` / `total_limit`）重新授予，并把 `uses_*` 归零；总次数已用尽而被移除的技能（已不在 `skill_instances_by_player` 中）**不重建**，因为那是「永久失去」而不是「额度耗尽」。
3. **不动停云的复原限定技**。`restore_limited_skill_use`（`MC:4343`）的既有语义与调用点保持不变；M4 是**新增端口**，不是替换。

**幂等与日志**：端口返回被重建的技能数量，便于测试断言与 AI 估值复用。

---

## 三、数据流与序列化

```
留白.activate
   └─ MC.reset_all_other_skills(owner, "liubai")        ← M4
        └─ 卸载(除 liubai) → 重装固有/模式 → 重授予局内获得技能(uses 归零)
             └─ _emit_state()                            ← UI 技能栏刷新为“全部未发动”
   └─ subscribe turnEnd → 本回合结束时
        └─ MC.remove_all_skills_permanently(owner)       ← M3
             └─ 卸载全部(含 liubai/留白自身) + 清空 acquired_skills + 清空轮回进度
                  └─ skills_permanently_removed = true   ← 存档 / LAN 快照同字段
                       └─ _emit_state()                  ← 技能栏清空且不再恢复
```

`state.random_history` 由 M2 写入（`kind` 形如 `zhuxv_random_target` / `zhuxv_random_card`），与 `state.rng_state` 一起构成随机可复现证据。

---

## 四、风险与回归面

| 风险 | 说明 | 缓解 |
|---|---|---|
| M4 重建导致限定技无限发动 | 排除项被重建 | 保留原实例并在测试中断言「留白仍为已发动」 |
| M4 丢失局内获得技能 | 重建路径不覆盖 `acquired_skills` | 从 `acquired_skills` 回读限额重建（见上） |
| M3 遗漏装配路径 | 四入口任一未复核标记 | 四条路径逐一断言（AC8） |
| 新增武将改变固定种子选将结果 | 与批 1 同因：选将/机缘/洗牌共用 `_rng` | 复用批 1 已建立的「结算开局技能选择」夹具范式 |
| 轮回额度与阶段额度互相遮蔽 | 两套额度并存 | 阶段额度用私有计数器，轮回进度由服务托管，测试逐项断言 |
| 订阅泄漏 | 留白第二段必须在本回合内保持订阅 | 失能后 `uninstall()` 释放；测试断言移除后不再有时机回调 |

回归重点（必须无回归）：`reincarnation_mechanics_test`、`new_character_mechanics_test`、`tingyun_mechanics_test`（复原限定技）、`conquest_*`、`control_all_characters_test`、`smoke_test`。

---

## 五、测试策略

新增 `tests/nakexia_mechanics_test.gd`（+ `.tscn`），覆盖：

1. 元数据与三条描述逐字一致；`GameDatabase.validation_errors` 为空。
2. 逐虚额度：同一出牌阶段第 3 次不开放入口；进入新出牌阶段后复原。
3. 逐虚随机范围：① 只落在「有牌的角色」且含自己；② 落在「全部存活角色」且含自己、不要求有牌；同种子下 `random_history` 可复现。
4. 逐虚轮回推进：① 完成后停在①；② 完成后轮回数 +1 并回到 ①。
5. 揭质：仅逐虚实际发动后出现入口；重复作用于同一目标；2 次用尽后不再出现；目标非法时不开放入口。
6. 留白重置：预先耗尽另一技能的限定技/阶段/回合/觉醒/轮回额度，发动留白后逐项复原；留白自身仍保持「已发动」。
7. 留白清算：回合结束后该角色技能表为空、`acquired_skills` 为空、轮回状态清空、`skills_permanently_removed` 为真；再次尝试换将/授予技能均不复活。
8. 三技能 AI 动作评分严格 > 0；留白 AI 在「重置收益」为 0 时给负分或不发动。
