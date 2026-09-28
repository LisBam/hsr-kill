# 设计文档：大黑塔（解构 / 灵感 / 看破）

本文档给出 `prd.md` 中 M5–M8 四项机制的落地设计。所有结论均基于对现有实现的实地核对，核对到的关键接口在文中标出行号。

---

## 一、总体策略：能不新增端口就不新增

调研结论是本批次**只需新增一个核心层能力（M6 的定义补丁），其余三项都复用现有权威端口**：

| 机制 | 落地方式 | 依据 |
|---|---|---|
| M5 记录容器 | 新增 `PlayerState.recorded_card_names` 公开字段 | `character_form_state` 是私有容器，不满足「公开可读」 |
| M6 目标重定向 | `card_rule_service` 新增通用「定义补丁」 | 现有 `rule_overrides` 只能调数量上限，改不了 `target_mode` |
| M7 排除无懈可击 | **纯内容层过滤** | 解构不记录、灵感不列出，双保险 |
| M8 令此牌对你无效 | **完全复用 `exclude_card_target`** | 语义已完全吻合，无需新端口 |

这条策略直接满足 AC11：核心层没有出现任何牌名或技能 ID 白名单。M6 的定义补丁是**按键合并的通用字典机制**，它不知道谁是「南蛮入侵」、谁是「铁索连环」。

---

## 二、M5：记录牌名容器

### 2.1 存储位置与类型

在 `PlayerState` 新增：

```gdscript
## 角色通过【解构】记录的牌名稳定ID列表；按记录先后排列、自动去重、跨回合保留，
## 属于公开信息，因此写入 to_dict 的公开部分，供界面展示、对手 AI 读取与局域网同步。
var recorded_card_names: Array[String] = []
```

**为什么不用 `character_form_state`**：该容器只在 `to_dict(..., reveal_private=true)` 时出现（`player_state.gd:498`），即「仅本人可见」。但记录必须公开——看破的对手要读、灵感的 AI 要读、界面要展示给所有人。放在公开字段是唯一正确选择。

**为什么存稳定 id 而不是显示名**：项目存在名称模式切换（`original_name` / `custom_name`，如南蛮入侵↔寰宇蝗灾）。存 id、展示时经 `GameSettings.resolve_card_name` 解析，才能跟随名称模式变化。

### 2.2 读写端口

在 `MatchController` 新增两个薄端口，避免技能直接改 `PlayerState` 数组：

```gdscript
## 记录一个牌名；已存在时不重复记录并返回 false，供技能区分“新记录”与“重复记录”。
func record_card_name(player_id: int, definition_id: String) -> bool

## 移除一个牌名；不存在时返回 false。供【灵感】结算完毕与【看破】发动时调用。
func remove_recorded_card_name(player_id: int, definition_id: String) -> bool
```

两者都：校验玩家存在、去重/存在性判断、`add_log` + `_emit_state()`。

### 2.3 存档与联机的自然覆盖

`PlayerState.to_dict` 是唯一序列化出口，因此只要字段进了 `to_dict`（公开部分）与 `from_authoritative_dict`（读档），存档、局域网快照、界面三条链路自动一致，无需逐处补丁。这与批 2 `skills_permanently_removed` 的处理方式一致。

---

## 三、M6：视为使用任意牌名 + 目标模式重定向

### 3.1 复用已有的无材料虚拟牌路径

现有入口（`MC:11600`）：

```gdscript
func execute_cardless_virtual_card_use(actor_id, virtual_card_definition_id, target_ids,
                                       log_message := "", rule_overrides := {}, virtual_storage := {}) -> bool
```

它内部会：构造虚拟 `CardInstance` → `card_rules.validate_virtual_use(...)` 复核 → 走标准 `CardUseEvent` 结算。**效果由 `virtual_card_definition_id` 决定**，所以「效果取第一张牌名」天然成立。

### 3.2 需要解决的问题

`validate_virtual_use` / `list_legal_virtual_targets` 都从 `GameDatabase.get_card(definition_id)` 取定义（`card_rule_service.gd:149`、`:190`），而目标规则（`target_mode` / `min_targets` / `max_targets` / `distance_limit`）全部来自这份定义。现有 `rule_overrides` 只能做 `maximum_target_count_bonus` 这种**增量**调整（`:167`），改不了 `target_mode` 这类**枚举**字段，更无法把 `all_others` 变成自选。

### 3.3 方案：通用的「定义补丁」

在 `card_rule_service.gd` 新增私有解析函数：

```gdscript
## 解析虚拟牌定义；rule_overrides 可携带 definition_patch 按键覆写定义字段，
## 用于「效果取甲牌、目标规则取乙牌」的通用重定向。补丁按键合并，不含任何牌名特例。
func _resolve_definition(definition_id: String, rule_overrides: Dictionary) -> Dictionary
```

实现：取 `GameDatabase.get_card(definition_id)`，若有 `rule_overrides["definition_patch"]` 则 `duplicate(true)` 后 `merge(patch, true)`。

`validate_virtual_use`（`:149`）与 `list_legal_virtual_targets`（`:190`）改为调用它。**其余逻辑一行不改**——数量校验、`_validate_target`、距离限制会自动读取补丁后的字段。

### 3.4 灵感如何拼装补丁

灵感选定「效果牌名 A」与「目标牌名 B」后：

```gdscript
var definition_b: Dictionary = GameDatabase.get_card(definition_b_id)
var rule_overrides: Dictionary = {
    "definition_patch": {
        "target_mode": str(definition_b.get("target_mode", "")),
        "min_targets": int(definition_b.get("min_targets", 0)),
        "max_targets": int(definition_b.get("max_targets", 0)),
        "distance_limit": str(definition_b.get("distance_limit", "none")),
    },
    "ignore_play_count_limit": true,   # 灵感是技能视为使用，不受 A 牌自身次数限制
}
```

然后：
- 目标枚举：`card_rules.list_legal_virtual_targets(owner_id, a_id, rule_overrides)`
- 提交校验：`card_rules.validate_virtual_use(owner_id, a_id, target_ids, rule_overrides)`
- 实际结算：`execute_cardless_virtual_card_use(owner_id, a_id, target_ids, "", rule_overrides, {"source_skill_id": get_id()})`

三处传**同一份** `rule_overrides`，这是 prd「Notes」里强调的一致性要求：三处只要有一处漏传补丁，就会出现「能选中但提交被拒」或「提交通过但结算按原目标模式执行」。

### 3.5 未选第二张牌名时

不传 `definition_patch`，目标规则取 A 自身，即普通「视为使用 A」。

### 3.6 效果与结算模式

- **效果**：由 `execute_cardless_virtual_card_use` 的第一参数决定，A 牌的 `resolve()` 被调用。
- **`resolution_mode`**：属于「效果如何结算」，因此**不补丁**，保持 A 的取值。
- 目标数量上限被补丁改写后，`resolve()` 收到的 `target_ids` 自然受限，群体牌（如南蛮）会按 A 的逐目标逻辑处理 B 允许的目标。

---

## 四、M7：排除无懈可击

**双重保证，全在内容层**：

1. **解构侧**：记录条件要求「非延时锦囊」。无懈可击的 `type == "trick"`、`subtype == "counter"`、`delayed == false`，若只判 `type`/`delayed` 会被误记录。因此记录条件必须显式要求 `subtype == "normal"`，从源头排除。
2. **灵感侧**：两次牌名选择的候选列表都再过一遍排除（`id != "wuxie"`）。这是防御性的——即使将来有别的途径污染了记录，选择列表也不会出现无懈。

**不新增核心层开关**。prd 的 M7 原文允许「必要时加防御性开关」，但既然记录源头已经堵死（`subtype == "normal"` 是通用规则，不是牌名特例），再加开关只会制造第二个真相来源。

---

## 五、M8：令此牌对你无效

### 5.1 完全复用现有端口

`MC:7755`：

```gdscript
## 将一张仍处于使用生命周期的牌对指定目标标记为无效；只跳过该目标内容，不取消其他合法目标。
func exclude_card_target(card_uid: int, target_id: int, _reason: String = "") -> bool
```

语义与看破的「令此牌对你无效」**完全一致**，且它已经保证了 prd R2.3 要求的「仅对持有者本人无效，不影响其他目标」。

它写入的是 `_card_use_contexts[card_uid]["excluded_target_ids"]`，而 `MC:12147` 在**牌效执行前**会重新检查该数组：

```gdscript
if target_id >= 0 and (card_use_context.get("excluded_target_ids", []) as Array).has(target_id):
    _complete_active_card_target(card_uid)
    event.cancel("target_lifecycle_cancelled")
    return
```

这条「前置生命周期可能异步取消，牌效执行前必须重新检查」的注释正是为异步技能准备的——看破的确认窗口发生在 `useCardToTargeted` 时机，只要能在此之前写入排除标记，结算阶段就会跳过该目标。

### 5.2 挂载时机

看破订阅 `useCardToTargeted`（时机目录 `rule_timing_catalog.gd:24`），这是「成为目标时」的标准时机，早于牌效 content 事件。

事件数据提供 `card_uid` 与 `target_id`；配合 `_card_use_contexts[card_uid]` 可读出 `actor_id`、`card_definition_id`。

### 5.3 发动前提（全部满足才开放入口）

1. `target_id == owner_player_id`（自己是目标）；
2. `actor_id != owner_player_id`（**其他角色**使用）；
3. `exclude_card_target` 要求的目标仍在 `target_ids` 内（保证不是已被排除的目标）；
4. 该牌的 `type == "trick"`（锦囊）；
5. `owner.recorded_card_names` 含该牌的稳定 id；
6. 本轮未发动过（`_used_round_number != state.round_number`）。

### 5.4 结算顺序

确认发动后**先移除记录，再写排除标记**，与原文「你可移除……然后令此牌对你无效」的先后一致；两者都在同一同步块内完成，中途无询问，不存在半完成状态。

---

## 六、三个技能组件设计

### 6.1 解构（jiegou）

- 元数据：`trigger: "active/phaseUse"`、`enable: "phaseUse"`、`ui_enabled: true`、无次数上限。
- `can_activate()`：出牌阶段 + 持有者存活 + 手牌中存在至少一张「非延时普通锦囊」。
- 候选：所有满足 `type == "trick" and subtype == "normal" and delayed == false` 的手牌。
- `activate()`：请求选牌（`min=1, max=1, allow_cancel=true`）→ 确认后 `recast_hand_card(owner_id, uid)` → 若 `record_card_name` 返回 true 则写日志。
  - **重铸与记录的先后**：先重铸（弃置+摸牌），再记录。原文是「重铸一张……然后若该牌牌名未被记录，你记录」。
  - 重铸后牌已进弃牌堆，因此**必须在重铸前**把 `definition_id` 存进请求上下文，否则牌对象离手后取不到牌名。
- AI：重铸收益按评估器的通用重铸尺度；若新牌名未被记录，额外加成（因为解锁灵感可选牌）。按 prd 补充「几乎可以无脑重铸」。

### 6.2 灵感（linggan）

- 元数据：`trigger: "active/phaseUse"`、`enable: "phaseUse"`、`ui_enabled: true`、私有计数器实现「出牌阶段限一次」（在 `phaseUseBegin` 重置）。
- **三段式流程**（严格按 prd R2.2 顺序，每段都可取消）：

| 段 | kind | 候选 | 可否取消 |
|---|---|---|---|
| 1 | `linggan_pick_effect` | 记录中的牌名（排除 wuxie） | 可 |
| 2 | `linggan_confirm_retarget` | 空候选确认 | 可 |
| 3 | `linggan_pick_target_mode` | 记录中的牌名（排除 wuxie、排除第一段已选） | 可 |

- 取消语义分两类：**第一段取消＝整体放弃**（不消耗次数、不移除记录、不产生残留窗口，满足 AC5）；**第二、三段取消＝不使用目标重定向**，继续按效果牌名自身的目标规则进入目标选择。这样既保留了原文「然后**可**令该牌的目标按另一张……结算」的可选性，也保留了「随时可以放弃发动」的出口。
- 全部完成后：请求目标选择（`list_legal_virtual_targets` + 补丁）→ 提交 `validate_virtual_use` → `execute_cardless_virtual_card_use`。
- **移除时机**：在虚拟牌**开始结算时**移除（AC7「该牌结算完毕后」）。实现上在 `execute_cardless_virtual_card_use` **返回 true 之后**移除两张牌名——因为该入口同步启动结算流程，返回后牌已进入处理区、记录可以安全摘除。若返回 false（校验失败）则不移除、不消耗次数。
- 计数消费：在**第三段结束、目标选择建立之前**消费，避免玩家在目标选择阶段取消后仍保留次数。这与【领航】「一旦确认发动便立即记录次数」的既有做法一致。
- AI：枚举记录中所有 (效果牌, 目标牌) 组合（含「只用效果牌」），按「效果收益 + 目标模式带来的目标数变化」评分；优先把单目标锦囊当群体用、把群体锦囊当单体用以避免误伤队友。返回最高分组合，且确保 > 0。

### 6.3 看破（kanpo）

- 元数据：`trigger: "passive/useCardToTargeted"`、`ui_enabled: false`、每轮限一次（`_used_round_number`）。
- `install()` 订阅 `useCardToTargeted`，角色 `"target"`（事件的 `target_id` 即看破持有者）。
- `can_activate()`：见 5.3 六条前提。
- 确认后：`remove_recorded_card_name` + `exclude_card_target(card_uid, owner_id, "kanpo")`，并记录 `_used_round_number`。
- AI：按 prd「几乎可以无脑使用，除非是五谷丰登、桃园结义这类正向锦囊」——对负面锦囊（伤害/弃牌/失去）评分为正、对正向锦囊为负。

---

## 七、测试设计

新增 `tests/daheita_mechanics_test.gd` + `.tscn`，覆盖 AC1–AC11：

1. `_test_metadata_and_descriptions`：三技能原文逐字比对（含「解读」字样）+ 武将属性 + `GameDatabase.validation_errors` 为空。
2. `_test_jiegou_records_normal_trick_only`：重铸普通锦囊后记录成功；延时锦囊（乐不思蜀/闪电）不被接受；重复牌名不重复记录。
3. `_test_jiegou_record_persists_across_turns`：跨回合记录仍在（AC3）。
4. `_test_linggan_candidates_exclude_wuxie`：即使人为把 `wuxie` 塞进记录，两段候选列表都不含它（AC4）。
5. `_test_linggan_cancel_paths`：三段各自取消 → 次数未消耗、记录未移除、无残留请求（AC5）。
6. `_test_linggan_target_redirect`：记录南蛮 + 铁索 → 合法目标枚举为「自选至多两名」而非「全体其他角色」；提交两名目标成功（AC6）。
7. `_test_linggan_removes_used_names`：结算后两张牌名均从记录移除；只用一张时只移除一张（AC7）。
8. `_test_kanpo_negates_self_only`：A 对 B 与持有者 C 使用群体锦囊 → C 看破 → C 不受影响、B 照常结算（AC8）。
9. `_test_kanpo_preconditions`：记录无该牌名 / 自己使用 / 本轮已用 → 均不开放入口。
10. `_test_ai_hooks_positive`：三技能 AI 均产出 > 0 分数（AC9）。

测试夹具沿用批 2 `nakexia_mechanics_test.gd` 的成熟模式：`_reset_state` 手工构造 `GameState`、`_install_skill` 直接装配、`_submit_choice` / `_submit_confirm` 提交选择、成功后打印 `DAHEITA_MECHANICS_PASS` 标记。

**AC10 的回归重点**：`smoke_test`（技能/武将计数）、`gameplay_regression_test`（逐目标无懈时序）、`rule_timing_test`（时机目录数量）。由于 M6 改了 `card_rule_service` 两个函数的定义读取方式，必须确认无补丁时行为完全不变。

---

## 八、文档同步清单

| 文档 | 内容 |
|---|---|
| `docs/内容制作指南.md` | M5 记录容器读写规范、M6 定义补丁与三处一致传参契约、M7 排除规则、M8 `exclude_card_target` 用法 |
| `docs/游戏机制与玩法内容.md` | 大黑塔技能表与全部数值（3 体力、每轮限一次、出牌阶段限一次、记录去重、移除时机、无懈排除） |
| `docs/界面与交互.md` | 灵感三段选择流程与取消行为、记录牌名的展示方式 |
| `docs/AI模块.md` | 三技能 AI 规则，含目标模式重定向的收益估算 |
| `docs/架构说明.md` | 定义补丁机制、记录容器字段与序列化位置 |
| `README.md` | 新增回归测试覆盖面 |

---

## 九、风险与对策

| 风险 | 对策 |
|---|---|
| 目标重定向三处传参不一致 | 三处复用同一份 `rule_overrides` 变量，并在测试中同时断言「枚举含 2 人」与「提交 2 人成功」 |
| `exclude_card_target` 因牌已离开使用生命周期而返回 false | 看破必须挂在 `useCardToTargeted`（早于 content），并在测试中断言返回值 |
| 记录字段公开导致联机泄露 | 记录本身按设计就是公开信息，无需裁剪；但需确认 `from_authoritative_dict` 读档路径同步 |
| 定义补丁污染实体牌路径 | 只有 `validate_virtual_use` / `list_legal_virtual_targets` 读补丁；实体牌走 `_get_entity_card_rule_overrides`，不含 `definition_patch` |
| 灵感移除记录时机过早，结算中断后记录已丢 | 在 `execute_cardless_virtual_card_use` 返回 true 之后才移除 |


## 10. 实现后修正（联调反馈）

首版实现完成后，根据实际试玩反馈修正了四处语义偏差。以下记录最终口径，与代码一致。

### 10.1 【解构】的可重铸范围不等于可记录范围
首版把“可重铸”与“可记录”合并成同一个判定（`type == "trick"` 且 `subtype == "normal"` 且非延时），
导致【无懈可击】连重铸都被禁止。按原文“重铸一张**非延时锦囊牌**”，响应类锦囊同样是非延时锦囊，
因此必须允许重铸；而“不能用于使用或转换”只约束**记录**（记录后才能被【灵感】视为使用）。
最终拆成两个判定：`_is_recastable_trick()`（`type == "trick"` 且非延时，含【无懈可击】）用于候选枚举与
`can_activate()`；`_is_recordable_definition()`（在前者基础上要求 `subtype == "normal"`）用于写记录。
AI 的“首次记录”加成同样只对可记录牌名生效。

### 10.2 【灵感】的全体目标模式必须交给整牌逻辑展开
首版对所有模式一律请求玩家选择目标，产生两个错误：
①【南蛮入侵】【万箭齐发】这类 `all_others` 牌可以只指定部分目标；
②可以把自己选为【南蛮入侵】的目标，而 `all_others` 本应排除使用者。
根因是技能自行枚举目标并当成最终目标提交。修正方式是把“目标展开”还给执行入口：
`execute_cardless_virtual_card_use()` 内部先调用 `card_rules.normalize_targets()`，
它已经正确实现 `all_others` 排除使用者、`all_players` 包含全场。
因此当最终定义的 `target_mode` 属于 `["all_others", "all_players"]` 时，技能**传空目标数组直接执行**，
完全不建立目标选择请求；只有非全体模式才用 `list_legal_virtual_targets()` 枚举并询问玩家。

### 10.3 次数消费时机推迟到“视为使用真正成立之后”
首版在“权威目标枚举非空、准备建立目标选择请求”时就消费 `_used_this_play_phase`，
导致玩家在目标选择阶段取消后次数已被扣掉，技能显示为“本阶段已发动过”而无法再次发动——
这与“每步都可取消且取消无代价”的设计冲突。修正为在 `execute_cardless_virtual_card_use()` 返回 `true`
之后才消费；任一步取消（含目标选择取消）都不消耗次数、不移除记录。
同时 `can_activate()` 增加“当前存在待处理选择则不开放入口”，避免选择进行中重复点击产生空请求。

### 10.4 永久失去技能必须实时反映到界面
`remove_all_skills_permanently()` 早已正确卸载实例并把 `skills_permanently_removed` 写入公开快照，
但界面两处仍直接读武将静态定义，导致技能按钮与悬停/详情中的技能条目继续存在：
`MatchTable._get_visible_skill_ids()` 与 `PlayerTargetView._request_character_information()`。
修正在两处都前置判断该标记并返回空技能列表（模式技能一并隐藏，因为它们同样不再被装配），
表现上等同于“该技能已从武将身上移除”，而不是灰显或保留占位。

### 10.5 对应新增回归
`tests/daheita_mechanics_test.gd` 新增 `_test_jiegou_recast_wuxie_without_recording()` 与
`_test_linggan_self_expanding_target_mode()`，并在 `_test_linggan_cancel_paths()` 末尾补上
“目标选择取消后仍能重新发动”的断言；通过行扩展为
`DAHEITA_MECHANICS_PASS records=1 recast_wuxie=1 redirect=1 expanding=1 cancel_safe=1 negate_self=1 wuxie_excluded=1`。


## 11. 第二次联调修正（目标模式一致性）

### 11.1 根因：目标展开与目标校验读取了不同的定义
首版只让 `CardRuleService.validate_virtual_use()` 读取 `rule_overrides["definition_patch"]`，
而 `normalize_targets()` 仍从 `GameDatabase.get_card(card.definition_id)` 取原始定义。
于是重定向后的虚拟牌出现两套目标模式：**展开**阶段用效果牌自身的模式，**校验**阶段用补丁后的模式，
两者互相否决，表现为“视为使用后无法触发”。

具体症状：
- 效果取【无中生有】（`self`）、目标模式取【南蛮入侵】（`all_others`）：展开得到「使用者自己」，
  校验按 `all_others` 判定该目标非法 → 整张牌被拒绝，所有其他角色都没有成为目标。
- 效果取【万箭齐发】（`all_others`）、目标模式取【无中生有】（`self`）：展开得到「所有其他角色」，
  校验按 `self` 要求目标必须是使用者 → 同样被拒绝。

### 11.2 修正
1. `normalize_targets()` 增加 `rule_overrides` 参数，内部改用 `_resolve_definition()` 取得合并后的定义；
   默认空字典时行为与改动前完全一致，既有调用点零影响。
2. `execute_cardless_virtual_card_use()` 把 `rule_overrides` 一并传入 `normalize_targets()`，
   使同一次执行中的展开与校验必然读取同一个 `target_mode`。
3. `normalize_targets()` 新增自指分支：`target_mode` 为 `self` 或 `self_wounded` 时直接返回 `[actor_id]`。
   此前这两种模式在传空目标时会走 `requested_targets.size() <= 1` 的早退并返回**空数组**，
   导致“把牌当【无中生有】使用”没有目标、效果不生效。
4. 【灵感】的自动目标模式常量由 `SELF_EXPANDING_TARGET_MODES`（仅全体两种）扩展为
   `AUTO_TARGET_MODES`（`all_others`、`all_players`、`self`、`self_wounded`），
   自指牌因此不再请求玩家点击自己。

### 11.3 单牌名时跳过目标重定向询问
记录容器中若不存在第二张可用牌名，原文的“另一张『解构』记录牌名”无从选择。
修正为在第一步选定效果牌名后先检查 `_get_effect_name_options(owner, [effect_id])`，
为空则**跳过第二步确认**，直接进入目标选择或结算，避免出现无意义的询问。

### 11.4 对应回归
新增 `_test_linggan_all_others_target_mode_on_self_effect()`（【无中生有】效果 + 全体目标模式，
断言两名其他角色各摸 2 张而使用者不摸）、`_test_linggan_self_target_mode()`（【万箭齐发】效果 +
自指目标模式，断言只有使用者自己需要作出【闪】响应）与
`_test_linggan_single_name_skips_retarget_prompt()`（单牌名直接进入目标选择）。
既有的取消语义用例与无懈可击排除用例因“单牌名跳过询问”改为使用两张或三张记录。
通过行扩展为
`DAHEITA_MECHANICS_PASS records=1 recast_wuxie=1 redirect=1 expanding=1 self_target=1 single_name=1 cancel_safe=1 negate_self=1 wuxie_excluded=1`。
