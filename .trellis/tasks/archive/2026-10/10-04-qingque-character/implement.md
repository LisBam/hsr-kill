# 青雀武将与三技能 · 实施计划

> PRD：[`prd.md`](./prd.md) ｜ 技术设计：[`design.md`](./design.md)
> 权威需求原文不可变；本文件的「验证」表在执行过程中逐行回填实测结果。

---

## 0. 阶段与回滚点

| 阶段 | 内容 | 回滚点 |
|---|---|---|
| P1 | 核心机制（伤害牌字段、用牌禁令钩子、时机花色、已用牌名容器） | `git stash` / 单文件 `git checkout` 即可回到改动前；核心改动全部是**新增**，无行为替换 |
| P2 | 三个技能 + 武将内容 | 删除 4 个新增文件即完全回滚，核心新增端口成为无消费者的死代码（不影响任何既有行为） |
| P3 | 专项测试 + 既有计数同步 | 删除测试文件、还原 `tests/smoke_test.gd` 两行 |
| P4 | 全量回归 + 文档同步 + 反馈文档 | 文档单独一处提交，代码回滚不影响文档可用性 |

**核心改动全部为附加式（新增键/新增函数/新增字段），唯一修改既有判断的地方是 `validate_use` 与 `_build_response_choice_candidates` 的插入点，且钩子默认放行 ⇒ 未安装【独弈】的对局行为不变。**

---

## 1. P1 · 核心机制

### 1.1 卡牌「是否为伤害牌」

- [ ] `game_data/card_definition.gd`：新增只读入口 `is_damage_card() -> bool`（读 `_metadata.get("is_damage", false)`，缺省 `false`）+ 面向长期维护的注释。
- [ ] 给 9 张牌加顶层 `"is_damage":true`：`sha.gd`、`huosha.gd`、`leisha.gd`、`juedou.gd`、`nanmanruqin.gd`、`wanjianqifa.gd`、`huogong.gd`、`shuiyanqijun.gd`、`shandian.gd`。
- [ ] 不动任何 `ai` 子字典（`ai.damage` 语义与读取点保持原样）。

### 1.2 【独弈】用牌禁令钩子

- [ ] `game_data/skill_definition.gd`：新增 `validate_card_action_permission(_card, _card_definition, _card_action) -> String`，默认返回 `""`。
- [ ] `scripts/core/match_controller.gd`：新增聚合入口 `validate_skill_card_action_permission(player_id, card, card_action) -> String`（与 `validate_skill_card_target_selection` 同构，遍历 `skill_instances_by_player`，`can_use_effect()` 过滤）。`can_use_effect()`（`skill_definition.gd:436`）对完整锁定技恒为真，因此【独弈】不会因自身是锁定技而被聚合跳过。
- [ ] `scripts/core/match_controller.gd`：新增稳定动作常量 `CARD_ACTION_USE = "use"` / `CARD_ACTION_RESPOND = "respond"`。
- [ ] `scripts/core/card_rule_service.gd` `validate_use`：在 `response_only` 判定（`:103-104`）之后、阶段使用次数计算（`:106`）之前插入禁令查询（动作 `"use"`）。
- [ ] `scripts/core/match_controller.gd` `_build_response_choice_candidates`：跳过被禁止打出的**手牌**（`card.zone == "hand"` + `CARD_ACTION_RESPOND`）。
- [ ] 确认不咨询 `validate_virtual_use` / 装备主动动作 / 重铸路径（见 design 2.5）。

### 1.3 为牌时机的使用牌花色/颜色

- [ ] `scripts/core/match_controller.gd` `_execute_card_use`：`_card_use_contexts[card.uid]` 新增 `"card_suit"` / `"card_color"`。
- [ ] `scripts/core/match_controller.gd` `_build_card_use_timing_data`：导出同名两键。
- [ ] `scripts/core/match_controller.gd` `_execute_card_use_timing_event`：`timing_data` 导出同名两键。

### 1.4 技能「已以此法使用过的牌名」容器

- [ ] `scripts/data/player_state.gd`：新增公开字段 `skill_used_card_names: Dictionary`（技能 ID → `Array[String]`）。
- [ ] `scripts/data/player_state.gd` `to_dict()`：与 `recorded_card_names` 并列公开输出。
- [ ] `scripts/data/player_state.gd` 存档恢复：缺键按空字典容错。
- [ ] `scripts/core/match_controller.gd`：新增 `add_skill_used_card_name(player_id, skill_id, definition_id) -> bool` 与 `get_skill_used_card_names(player_id, skill_id) -> Array[String]`（与 `record_card_name` / `get_recorded_card_names` 同构，写入后广播快照）。

**P1 自检**：`& $godot --headless --path . --quit` 退出码 0 且无 `SCRIPT ERROR`。

---

## 2. P2 · 内容

### 2.1 `game_data/skills/duyi.gd`（【独弈】）

- [ ] 静态元数据：`id/name/description`（逐字原文）/`lock:true`/`ui_enabled:false`/`trigger:["phaseDiscardBegin"]`。
- [ ] 常量：`CARD_SUITS`、`BLOCKED_TYPES`、`BLOCKED_ZONE`、`HISTORY_KIND_KEEP_SUIT`。
- [ ] `validate_card_action_permission`：手牌 + 基本牌/锦囊牌 → 返回拒绝文案；其余返回 `""`。
- [ ] `install()`：订阅 `phaseDiscardBegin`（role `player`）。
- [ ] `_on_phase_discard_begin`：按花色归组 → 逐花色 `pick_random_candidate_index` 保留 1 张 → 批次弃置其余 → `announce_activation` → 跳过弃牌阶段（嵌套时 `defer_settlement`）。
- [ ] `continue_settlement`：承接 `duyi_skip_discard`。
- [ ] AI：`modify_ai_incoming_card_effect`（无法打出手牌【闪】⇒ 针对她的需要【闪】的来牌收益提高）。

### 2.2 `game_data/skills/qihe.gd`（【弃和】）

- [ ] 静态元数据：`lock:true`/`ui_enabled:false`/`trigger:["useCardToTargeted"]`。
- [ ] `install()`：订阅 `useCardToTargeted`（role `target`）。
- [ ] 回调：目标是我 → 使用者是其他角色 → `is_damage` 为真 → `card_suit` 合法 → 手牌有同花色 → 随机弃 1 张 → `exclude_card_target` → `announce_activation`。
- [ ] `continue_settlement`：承接 `qihe_exclude`。
- [ ] AI：`modify_ai_incoming_card_effect`（可能被抵消 ⇒ 针对她的伤害牌收益降低）。

### 2.3 `game_data/skills/zimo.gd`（【自摸】）

- [ ] 静态元数据：普通主动技，`enable:"phaseUse"`、`ui_enabled:true`。
- [ ] 额度状态：`_used_this_play_phase`、`_extended_limit_turn_number`、`_get_play_phase_limit()`。
- [ ] `install()`：订阅 `phaseUseBegin` → 归零已发动次数。
- [ ] `can_activate()` / `activate()`：分支一（摸 1 → 不可取消选牌 → 不可取消选目标 → 视为使用）；分支二（内联花色选项 → 弃该花色全部手牌 → 上限改 2）。
- [ ] `continue_selection()`：三个 kind 的完整续接（含 `defer_settlement` 承接嵌套弃置）。
- [ ] `_get_feasible_effect_ids()`：`sha` + 未被本技能用过、且当前存在合法目标的普通锦囊（排除【无懈可击】与延时锦囊）。
- [ ] 展示文本刷新（`set_skill_display_description`）。
- [ ] AI：`append_play_phase_actions` / `score_ai_action` / `score_ai_choice`（三 kind，确认分高于取消分）。

### 2.4 `game_data/characters/qingque.gd`

- [ ] `id:"qingque"`、`display_name:"青雀"`、`gender:"female"`、`faction:"xianzhou"`、`max_hp:3`、技能顺序 `[duyi, qihe, zimo]`、不填 `art_path`。

---

## 3. P3 · 测试与既有常量

- [ ] 新增 `tests/qingque_mechanics_test.gd` + `tests/qingque_mechanics_test.tscn`（Tab 缩进；`QINGQUE_MECHANICS_PASS` / `QINGQUE_MECHANICS_FAIL`）。
- [ ] 覆盖 design 第 10 节的全部场景（元数据逐字、伤害牌清单一致、用牌封锁、弃牌阶段、弃和、自摸两分支、整局累计、AI 方向断言、存档往返）。
- [ ] `tests/smoke_test.gd:200`：技能数 102 → 105（补历史口径注释）。
- [ ] `tests/smoke_test.gd:307`：武将数 48 → 49（补历史口径注释）。

---

## 4. P4 · 验证与文档

### 4.1 验证命令（PowerShell，逐进程顺序执行）

```powershell
$godot = 'E:\Godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe'
# 无头解析校验
& $godot --headless --path . --quit
# 逐项回归（不要并发跑多个 Godot 进程）
& $godot --headless --path . res://tests/qingque_mechanics_test.tscn
& $godot --headless --path . res://tests/smoke_test.tscn
& $godot --headless --path . res://tests/requested_changes_test.tscn
& $godot --headless --path . res://tests/ai_policy_test.tscn
& $godot --headless --path . res://tests/new_character_mechanics_test.tscn
& $godot --headless --path . res://tests/card_action_semantics_test.tscn
& $godot --headless --path . res://tests/event_runtime_test.tscn
& $godot --headless --path . res://tests/phase_progression_test.tscn
& $godot --headless --path . res://tests/card_timing_sequence_test.tscn
& $godot --headless --path . res://tests/conquest_save_test.tscn
& $godot --headless --path . res://tests/conquest_coop_test.tscn
git diff --check
```

判定标准：**退出码 0 + 输出自身 PASS 标记 + 日志无 `ERROR`/`SCRIPT ERROR`/`FAIL`**。

- [ ] `GameDatabase.validation_errors` 为空（由 `smoke_test` 首段断言）。
- [ ] 新专项测试与上表全部用例通过。

### 4.2 验证回填表

| 用例 | 期望标记 | 实测 |
|---|---|---|
| `res://tests/qingque_mechanics_test.tscn` | `QINGQUE_MECHANICS_PASS` | 待填 |
| `res://tests/smoke_test.tscn` | `SMOKE_PASS …` | 待填 |
| `res://tests/requested_changes_test.tscn` | `REQUESTED_CHANGES_…` | 待填 |
| `res://tests/ai_policy_test.tscn` | `AI_POLICY_PASS cards=…` | 待填 |
| `res://tests/new_character_mechanics_test.tscn` | `NEW_CHARACTER_MECHANICS_PASS` | 待填 |
| `res://tests/card_action_semantics_test.tscn` | `CARD_ACTION_SEMANTICS_PASS …` | 待填 |
| `res://tests/event_runtime_test.tscn` | `EVENT_RUNTIME_PASS …` | 待填 |
| `res://tests/phase_progression_test.tscn` | `PHASE_PROGRESSION_PASS` | 待填 |
| `res://tests/card_timing_sequence_test.tscn` | `CARD_TIMING_SEQUENCE_PASS …` | 待填 |
| `res://tests/conquest_save_test.tscn` | `CONQUEST_SAVE_PASS …` | 待填 |
| `res://tests/conquest_coop_test.tscn` | `CONQUEST_COOP_PASS …` | 待填 |
| `& $godot --headless --path . --quit` | 退出码 0、无 `SCRIPT ERROR` | 待填 |
| `git diff --check` | 无输出 | 待填 |

### 4.3 文档同步（逐项勾选）

- [ ] `docs/内容制作指南.md`：`is_damage` 字段；`validate_card_action_permission` 钩子与两个动作取值；「新增机制制作接口」补两条；模板/检查清单补「锁定技不创建询问」「动态阶段额度写法」。
- [ ] `docs/游戏机制与玩法内容.md`：追加青雀小节（含全部具体数值与 AI 数值）。
- [ ] `docs/卡牌系统.md`：「是否为伤害牌」字段语义 + 9 张清单。
- [ ] `docs/界面与交互.md`：两种技能交互复用既有协议、分支一不可取消的界面表现。
- [ ] `docs/AI模块.md`：三技能的 AI 钩子口径。
- [ ] `README.md`：「## 自动校验」追加新测试段落。
- [ ] `临时反馈文档.md`：时间戳 + 学习反馈摘要 + 编号 Git 提交描述。

---

## 5. 完成定义（DoD）

1. `tests/qingque_mechanics_test.tscn` 通过，且覆盖 design 第 10 节全部场景。
2. 上表全部回归用例通过，`GameDatabase.validation_errors` 为空。
3. 三个技能的 `description` 与 `prd.md` 原文**逐字一致**。
4. 三技能的 AI 钩子齐备（主动技含 `score_ai_action` + `score_ai_choice`；锁定技含来牌估值修正），且方向断言可测。
5. 文档清单全部勾选，`git diff --check` 干净。
6. `临时反馈文档.md` 已追加本次反馈与提交描述。
