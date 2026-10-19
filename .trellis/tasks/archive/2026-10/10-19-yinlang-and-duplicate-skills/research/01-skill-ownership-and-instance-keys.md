# 调研 01 · 技能归属模型与「同名技能多实例」阻塞点

调研范围：技能实例的存放位置、键结构、全部读写点、时机派发是否按实例区分、额度记账、UI/AI/存档受影响面。
结论：**派发层无需改动**；**全部归属容器都是「技能 ID 键字典」是唯一阻塞点**。

---

## 1. 实例存放与键结构

| 容器 | 位置 | 结构 | 键 |
|---|---|---|---|
| `skill_instances_by_player` | `scripts/core/match_controller.gd:496` | `{player_id -> {skill_id -> SkillDefinition}}` | **纯技能 ID** |
| `PlayerState.acquired_skills` | `scripts/data/player_state.gd:146` | `{skill_id -> {source, per_turn_limit, per_round_limit, total_limit, tracked_turn_number, tracked_round_number, uses_this_turn, uses_this_round, total_uses}}` | **纯技能 ID** |
| `PlayerState.temporary_skills` | `player_state.gd:143` | `{skill_id -> ...}` | **纯技能 ID** |
| `PlayerState.reincarnation_skills` | `player_state.gd:149` | `{skill_id -> metadata}` | **纯技能 ID** |
| `PlayerState.dynamic_skill_descriptions` | `player_state.gd:78` | `{skill_id -> description}` | **纯技能 ID** |

`skill_instances_by_player` 的全部写入点（`match_controller.gd`）：`:1742`、`:1838`、`:4829`、`:4863`、`:10311`、`:10401`、`:10422`、`:10445`、`:10984`、`:11013`、`:11030`、`:16187`（另有整表清空 `:1742`、`:1838`、`:11000`）。
全部读取点 39 处；`.values()` 遍历：`:2527`、`:4822`、`:5821`、`:5838`、`:8041`、`:10232`、`:10244`、`:10267`、`:10282`、`:10547`、`:10992`、`:10995`、`:11009`、`:15348`。

## 2. 为什么派发层无需改动

`TriggerManager.subscribe(event_name, owner, callback, priority, owner_player_id, role, first_do, last_do, condition)`（`scripts/core/trigger_manager.gd:45-65`）与 `RuleModifierPipeline.register(modifier_name, owner, callback, priority)`（`scripts/core/rule_modifier_pipeline.gd:14`）**都以 `owner` 对象（即 `self`，技能实例）为键**，不以技能 ID 为键。

`unsubscribe_owner(owner)`（`trigger_manager.gd:69-81`）、`unregister_owner(owner)`（`rule_modifier_pipeline.gd:31`）同样按对象移除。

→ **两个同 ID 的不同实例各自订阅、各自触发、各自注销，互不干扰。派发层零改动。**

## 3. 唯一阻塞点：全部归属查询按纯 ID

| 位置 | 表达式 | 问题 |
|---|---|---|
| `match_controller.gd:10302-10304` | `if player_skills.has(skill_id): return false` | ★**拒绝重复安装**（日志「已经拥有【%s】，本次获得未重复安装」） |
| `:9888-9891` | `get_skill_instance(player_id, skill_id)` | 只能取到一个 |
| `:10582-10595` | `has_skill(player_id, skill_id)` | 口径 = 实例 ∪ acquired ∪ temporary，无存活过滤 |
| `:10563-10570` | `get_installed_skill_ids()` | 返回 ID 列表 |
| `:10536-10559` | `get_active_skill_ids()` | 同上 |
| `:10475-10532` | `can_activate_skill()` | 按 ID 查额度 |
| `:11041-11070` | `remove_skill(player_id, skill_id, reason)` | 按 ID 移除 |
| `:11078+` | `remove_all_skills(player_id, reason)` | 先快照 ID 再逐个移除 |
| `game_data/skill_definition.gd:665` | `owner.acquired_skills.has(get_id())` | ★**额度门禁用 `get_id()`** → 多实例下会互相顶替额度（quota-bypass bug） |
| `skill_definition.gd:164` | `bind()` 内轮回技注册 | 用 `get_id()` |
| `skill_definition.gd:208` | `announce_activation()` → `record_skill_activation` | 用 `get_id()` |
| `skill_definition.gd:216-217` | `consume_acquired_skill_use` | 用 `get_id()` |
| `character_skill_display.gd:30-58` | `collect_visible_skill_ids()` | 返回 ID 列表 |
| `match_table.gd:2312-2331` | `_get_visible_skill_ids()` | 同上 |

## 4. 既有可复用能力（无需新建）

| 能力 | 位置 |
|---|---|
| 运行时授予技能 | `match_controller.gd:10295-10327 grant_acquired_skill(player_id, skill_id, per_turn_limit, total_limit, source, allow_out_of_game, per_round_limit) -> bool` |
| 额度门禁 | `:10331-10350 can_use_acquired_skill()` |
| 额度消耗 | `:10354-10378 consume_acquired_skill_use()` |
| 仅移除局内获得 | `:10382-10404 remove_acquired_skill()` |
| 临时技能 | `:10408-10425 grant_temporary_skill()` / `:10429-10446 remove_temporary_skill()` |
| 限定技 | `skill_definition.gd:104`（`limited` 由正文「限定技」自动置位）+ `:267-286`（`has_available_intrinsic_use` / `consume_intrinsic_use` / `restore_limited_use`） |
| 描述覆盖 | `player_state.gd:78 dynamic_skill_descriptions` + `match_controller.gd:17768-17778 set_skill_display_description()`；用例 `duanjie.gd:280-286` |
| 纯查询聚合范式 | `match_controller.gd:9996-10113`（`skill_play_count_limit_bonus`、`modify_skill_distance_to_target` 等 7 个） |
| 技能重置 | `:11250-11280 _rebuild_character_skills_and_zero_usage()` |
| 复活/还原 | `:4787-4831 _replace_native_character_skills()`、`:4835-4867 restore_character_card_skills()`、`:4871-4884 get_used_limited_skill_ids()`、`:4888-4904 restore_limited_skill_use()` |
| 批量安装/卸载 | `:10952-10987 _install_all_character_skills()`、`:10991-11000 _uninstall_all_character_skills()`、`:11004-11033 _reinstall_character_skills_for_player()` |

## 5. 受影响面

- **测试**：35 个测试文件直接以纯 ID 键写 `skill_instances_by_player`，标准写法：
  ```gdscript
  var player_skills: Dictionary = _controller.skill_instances_by_player.get(player_id, {}) as Dictionary
  player_skills[skill_id] = skill
  _controller.skill_instances_by_player[player_id] = player_skills
  skill.install()
  ```
  含 `smoke_test.gd:1324-1330`（断言 `size() == 4`）、`new_character_mechanics_test.gd`（12 处）、`requested_changes_test.gd`（12 处）、`doudizhu_mode_test.gd:270,973-976`、`leader_skill_test.gd:79,93-94,304`。
- **UI**：`character_skill_display.gd` + `match_table.gd:2173-2251 _render_local_skills()` + `skill_button_view.gd:83-96 configure()`（名称读静态库、短名取前 2 字）。
- **AI**：`noname_ai_evaluator.gd:473,775`、`basic_ai_policy.gd:397,423,441`、`identity_strategy_evaluator.gd:269` 经 `GameDatabase.create_skill(current_skill_id)` 构造实例 → 未登记 ID 解析为 `null` 被跳过。
- **存档**：`_reinstall_saved_runtime_skills`（`:16163-16189`）按 ID 经 `create_skill` 还原，未知 ID 静默 `continue`（`:16181-16183`）。
- **快照**：`skill_definition.gd:305-342 collect_snapshot_skill_ids()`、`:351-368 snapshot_has_skill()`；`PlayerState` 字段 `installed_skill_ids`。

## 6. 结论：改造方向

**复合实例键**（见 `../10-19-skill-instance-multiplicity/design.md` D1）：

- 第 1 个实例的键 == 纯技能 ID；第 2 个起为 `"<skill_id>#<N>"`（N ≥ 2，取最小空闲值）。
- 技能 ID 的字符集是 `[a-z0-9_]+`（`game_database.gd:489-492` 强制文件名规则），因此 `#` 无歧义；用 `rfind("#")` 实现 `SkillDefinition.base_skill_id_of(instance_key)`。
- **向后兼容红利**：第 1 个实例键等于纯 ID → 既有单实例路径、旧存档、旧回放、35 个测试文件全部**逐字节不变**；无需提升 `SAVE_FORMAT_VERSION`。

**被否决的方案**：

| 方案 | 否决理由 |
|---|---|
| `{skill_id -> Array[SkillDefinition]}` | 破坏约 20 个核心读取点 + 35 个测试文件 |
| 运行时合成技能 ID | `GameDatabase.get_skill()` 查不到 → UI 名称退化为 ID、AI 直接跳过该技能 |

**端口约定（D1.1）**：所有技能参数端口同时接受实例键与纯技能 ID —— 先精确匹配实例键，否则取该基础 ID 的第一个实例。例外：`remove_skill(pid, base_id)` 移除该技能的全部实例；`remove_skill(pid, instance_key)` 只移除一个。
