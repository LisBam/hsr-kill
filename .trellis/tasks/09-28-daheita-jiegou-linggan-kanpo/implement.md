# 实施计划：大黑塔（解构 / 灵感 / 看破）

实施依据：`prd.md`（需求）+ `design.md`（设计）。执行顺序自上而下，每一步都可独立验证。

---

## 前置约定

- **无头测试命令**（场景路径是位置参数，不能写 `--scene`）：

```powershell
& 'E:\Godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe' `
  --headless --path . res://tests/<name>.tscn --quit-after 6000
```

- **`--quit-after` 会让被中断的测试也返回 0**，因此判定必须 `grep` 到 `_PASS` 行，不能只看退出码。
- 缩进一律 **Tab**。
- 技能描述文本**一字不可改**（项目铁律），包含原文中的「解读」字样。

---

## 单元划分

### U1 — M5 记录容器字段

**文件**：`scripts/data/player_state.gd`

1. 在 `reincarnation_skills` / `skills_permanently_removed` 附近新增字段：

```gdscript
## 角色通过【解构】记录的牌名稳定ID列表；按记录先后排列、自动去重、跨回合保留。
## 属于公开信息（对手 AI 与界面都要读），因此写入 to_dict 的公开部分而非 character_form_state。
var recorded_card_names: Array[String] = []
```

2. `from_authoritative_dict`（`:284` 附近的静态构造）读取：

```gdscript
player.recorded_card_names.assign(data.get("recorded_card_names", []) as Array)
```

3. `to_dict`（`:462`）公开部分写回：

```gdscript
"recorded_card_names": recorded_card_names.duplicate(),
```

**验证**：字段存在、读档往返一致、公开快照含该键。

---

### U2 — M5 读写端口

**文件**：`scripts/core/match_controller.gd`（放在 `get_used_limited_skill_ids` / `remove_all_skills_permanently` 同一区域）

```gdscript
## 记录一个牌名；已存在时不重复记录并返回 false，供技能区分“新记录”与“重复记录”。
func record_card_name(player_id: int, definition_id: String) -> bool

## 移除一个牌名；不存在时返回 false。供【灵感】结算完毕与【看破】发动时调用。
func remove_recorded_card_name(player_id: int, definition_id: String) -> bool
```

两者共同要求：
- `state == null` 或 `definition_id.is_empty()` → `false`
- 玩家不存在 → `false`
- 变更后 `add_log(...)` + `_emit_state()`
- 日志使用 `GameSettings.resolve_card_name(GameDatabase.get_card(definition_id))` 解析显示名

**验证**：重复记录返回 false 且不产生重复项；移除不存在项返回 false。

---

### U3 — M6 定义补丁

**文件**：`scripts/core/card_rule_service.gd`

1. 新增私有解析函数：

```gdscript
## 解析虚拟牌定义；rule_overrides 可携带 definition_patch 按键覆写定义字段，
## 用于“效果取甲牌、目标规则取乙牌”的通用重定向。补丁按键合并，不含任何牌名特例。
func _resolve_definition(definition_id: String, rule_overrides: Dictionary) -> Dictionary:
	var definition: Dictionary = GameDatabase.get_card(definition_id)
	var definition_patch: Dictionary = rule_overrides.get("definition_patch", {}) as Dictionary
	if definition.is_empty() or definition_patch.is_empty():
		return definition
	var merged: Dictionary = definition.duplicate(true)
	merged.merge(definition_patch, true)
	return merged
```

2. `validate_virtual_use`（`:149`）改为：

```gdscript
var definition: Dictionary = _resolve_definition(definition_id, rule_overrides)
```

3. `list_legal_virtual_targets`（`:190`）同样改为 `_resolve_definition(definition_id, rule_overrides)`。

**注意**：只改这两个函数。实体牌路径的 `_get_entity_card_rule_overrides` 不读补丁，行为完全不变。

**验证**：不传 `definition_patch` 时两个函数行为与改动前逐字一致（由 `gameplay_regression_test`、`smoke_test`、`skill_choice_test` 等既有用例背书）。

---

### U4 — 武将定义

**文件**：`game_data/characters/daheita.gd`（+ `.uid` 由引擎生成）

```gdscript
extends CharacterDefinition
```

`_init()` 参数：`id: "daheita"`、`display_name: "大黑塔"`、`gender: "female"`、`faction: "yinhexvezhe"`、`max_hp: 3`、`skills: ["jiegou", "linggan", "kanpo"]`。

**验证**：`GameDatabase` 扫到该武将，`validation_errors` 为空。

---

### U5 — 【解构】jiegou

**文件**：`game_data/skills/jiegou.gd`

- 元数据：`trigger: "active/phaseUse"`、`enable: "phaseUse"`、`ui_enabled: true`。无次数上限。
- 常量置于文件顶部：`RECORDABLE_TYPE = "trick"`、`RECORDABLE_SUBTYPE = "normal"`、`CONTEXT_CARD_DEFINITION_ID`、`CHOICE_KIND = "jiegou_recast"`。
- `can_activate()`：出牌阶段 + 存活 + 手牌中存在至少一张可记录锦囊。
- 候选：`type == "trick" and subtype == "normal"` 且 `not delayed` 的手牌。
- `activate()`：
  1. **先把每张候选的 `definition_id` 存进请求上下文**（重铸后牌会离手，取不到牌名）；
  2. 请求选牌 `min=1, max=1, allow_cancel=true`；
  3. `continue_selection` 中：读上下文里的 `definition_id` → `recast_hand_card(owner_id, uid)` → 成功则 `record_card_name(owner_id, definition_id)`。
- AI：`score_ai_action` 复用评估器重铸尺度；牌名未被记录时额外加成。

**验证**：只有非延时普通锦囊可被记录；延时锦囊被拒；重复牌名不重复记录。

---

### U6 — 【灵感】linggan

**文件**：`game_data/skills/linggan.gd`

- 元数据：`trigger: "active/phaseUse"`、`enable: "phaseUse"`、`ui_enabled: true`。
- 私有计数器 `_used_this_play_phase`，在 `subscribe_timing("phaseUseBegin", ..., "player")` 中重置，实现「出牌阶段限一次」。
- 三段选择（kind 常量）：`linggan_pick_effect` → `linggan_confirm_retarget` → `linggan_pick_target_mode`。
- 段 1/3 的候选来自 `owner.recorded_card_names`，**并显式排除 `wuxie`**；段 3 额外排除段 1 已选。
- **取消契约**：任何一段取消 → 直接 `return`，不消费次数、不移除记录、不留残留状态。
- 段 3 结束后：消费次数 → 拼装 `rule_overrides`（含 `definition_patch`，见 `design.md` 3.4）→ 用同一份 overrides 依次调用 `list_legal_virtual_targets`、`validate_virtual_use`、`execute_cardless_virtual_card_use`。
- **移除记录**：仅在 `execute_cardless_virtual_card_use` 返回 `true` 之后，移除效果牌名与目标牌名（未选目标牌时只移除效果牌名）。
- 未选段 3 时：不传 `definition_patch`。
- AI：枚举全部 (效果牌, 目标牌/无) 组合评分，优先「单目标当群体用」与「群体当单体用避免误伤」，返回 `> 0` 的最优组合。

**验证**：AC4/AC5/AC6/AC7 全部有断言。

---

### U7 — 【看破】kanpo

**文件**：`game_data/skills/kanpo.gd`

- 元数据：`trigger: "passive/useCardToTargeted"`、`ui_enabled: false`。
- 私有 `_used_round_number: int = -1` 实现「每轮限一次」。
- `install()`：`subscribe_timing("useCardToTargeted", _on_card_targeted, "target")`。
- `_on_card_targeted(event)` 取 `card_uid` / `target_id`，经 `_get_card_use_context(card_uid)` 读 `actor_id` / `card_definition_id`，按 `design.md` 5.3 的六条前提判定。
- 全部满足 → 请求确认（`request_card_selection`，空候选，`allow_cancel=true`）。
- 确认后：`remove_recorded_card_name(owner_id, trick_id)` → `exclude_card_target(card_uid, owner_id, "kanpo")` → `_used_round_number = state.round_number`。
- AI：负面锦囊为正、正向锦囊（`wugu` / `taoyuan`）为负。

**验证**：AC8 及前提判定。

---

### U8 — 回归测试

**文件**：`tests/daheita_mechanics_test.gd` + `tests/daheita_mechanics_test.tscn`

沿用 `tests/nakexia_mechanics_test.gd` 的夹具模式：`_ready()` → `call_deferred("_run")`；`_create_controller()` 建 `MatchController` + `RuleEventBus` + `AICoordinator` + `NetworkGateway`；`_reset_state(n)` 手工构造 `GameState` 并调用 `_controller._rebuild_match_rule_services_and_root_event()`；`_install_skill` 用 `GameDatabase.create_skill` → `bind` → 注册 → `install`。

`.tscn` 六行模板，根节点名 `DaheitaMechanicsTest`。

十个子测试见 `design.md` 第七节。成功打印：

```
DAHEITA_MECHANICS_PASS records=1 redirect=1 negate_self=1 wuxie_excluded=1 round_limit=1
```

**验证**：`grep` 到 `_PASS`。

---

### U9 — 计数断言同步

**文件**：`tests/smoke_test.gd`

批 2 后为 **技能 77 / 武将 36**。本批次 +3 技能、+1 武将 → **技能 80 / 武将 37**。

**验证**：`SMOKE_PASS`。

---

### U10 — U12 文档同步

| 单元 | 文件 |
|---|---|
| U10 | `docs/游戏机制与玩法内容.md`（武将技能表、数值快照） |
| U11 | `docs/AI模块.md`、`docs/内容制作指南.md` |
| U12 | `docs/界面与交互.md`、`docs/架构说明.md`、`README.md` |

---

### U13 — 全量回归

依次运行 `tests/` 下全部 `.tscn`，逐个 `grep` `_PASS`。已知基线：`android_adaptation_test` 无 `_PASS` 标记（历史遗留）。

若新增武将再次引起固定种子位移导致既有测试失败，按批 1/批 2 的既有手法修复：优先让测试对「出场武将是谁」免疫（结算待处理请求、显式指定武将），而不是调整随机种子。

---

## 验收对照

| AC | 对应单元 | 断言位置 |
|---|---|---|
| AC1 文件落地、无校验错误 | U4–U7 | 测试子项 1 |
| AC2 描述逐字一致（含「解读」） | U5–U7 | 测试子项 1 |
| AC3 仅非延时锦囊、跨回合、去重 | U5 | 子项 2、3 |
| AC4 灵感候选来自记录且排除无懈 | U6 | 子项 4 |
| AC5 三段取消无副作用 | U6 | 子项 5 |
| AC6 目标重定向生效 | U3 + U6 | 子项 6 |
| AC7 结算后移除记录 | U6 | 子项 7 |
| AC8 看破仅对本人无效 | U7 | 子项 8、9 |
| AC9 三技能 AI 评分 > 0 | U5–U7 | 子项 10 |
| AC10 新测试通过、无回归 | U8、U9、U13 | `_PASS` 全绿 |
| AC11 无牌名/技能白名单 | U3 | 代码评审：`_resolve_definition` 只做键合并 |

---

## 提交拆分

单个提交，Git 描述按下列条目分行（先代码、后文档）：

1. 新增大黑塔武将定义
2. 新增玩家状态记录牌名容器并写入存档与公开快照
3. 新增控制器记录与移除牌名端口
4. 新增卡牌规则服务的虚拟牌定义补丁入口
5. 新增【解构】重铸非延时锦囊并记录牌名
6. 新增【灵感】视为使用记录牌名并按另一记录牌名结算目标
7. 新增【看破】移除记录并令锦囊对自身无效
8. 新增大黑塔机制回归用例
9. 调整烟雾测试的武将与技能定义数量断言
10. 补充玩法内容文档中大黑塔的技能与数值快照
11. 补充AI模块文档中三技能的评分规则
12. 补充内容制作指南中记录容器与目标重定向写法
13. 补充界面与交互文档中灵感三段选择流程
14. 补充架构说明中记录容器与定义补丁机制
15. 更新README中大黑塔回归用例的覆盖范围

> 若 U13 发现既有测试因种子位移失败，追加「修复 XX 测试被 XX 阻塞」条目。
