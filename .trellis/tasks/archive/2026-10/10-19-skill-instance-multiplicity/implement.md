# 技能多实例底座 · 实施计划

阶段顺序遵循「先数据契约、再端口、后消费者」：A1-A2 建立身份与存储，A3-A5 打通权威端口与持久化，A6 堵住额度漏检，A7-A8 修消费者，A9 补测试与文档。

---

## A1 `SkillDefinition`：实例键与拥有权契约

- [x] A1.1 新增 `_instance_key: String = ""`（独占一行 `##` 注释说明默认值语义）、`get_instance_key()`、`set_instance_key()`、静态 `base_skill_id_of(instance_key)`。
- [x] A1.2 新增静态 `collect_snapshot_skill_keys(player_snapshot, character_definition) -> Array[String]`：并集 native + `mode_skill_ids` + `temporary_skills` 键 + `acquired_skills` 键，按键去重、保持原顺序。
- [x] A1.3 改写 `collect_snapshot_skill_ids()` 为「`collect_snapshot_skill_keys()` → `base_skill_id_of()` → 去重」，返回值语义与改动前一致（单实例时逐元素相同）。
- [x] A1.4 `snapshot_has_skill()` 改为按技能 ID 语义判断：实例键还原后与目标 ID 比较；`installed_skill_ids` 过滤同样先还原再比较。
- [x] A1.5 `declares_description_tag` / 元数据相关静态方法不受影响（不涉及键）。

**验证**：`tests/skill_ownership_test.gd` 全绿；新增断言 `base_skill_id_of("zhuru#2") == "zhuru"`、`base_skill_id_of("zhuru") == "zhuru"`。
**回滚点**：本阶段只新增与等价改写，回滚即还原 `skill_definition.gd`。

---

## A2 `PlayerState`：实例级存储与序列化

- [x] A2.1 新增 `runtime_skill_data: Dictionary = {}`（独占 `##` 注释：键为实例键，值为该实例的运行时配置；进入公开快照与权威存档）。
- [x] A2.2 `acquired_skills` / `temporary_skills` 记录内新增 `"skill_id"` 字段（写入方在 A3）。
- [x] A2.3 `from_authoritative_dict` 读取 `runtime_skill_data`；`to_dict` 写出。其余技能相关字段序列化代码保持原样（键本身是字符串，天然兼容）。
- [x] A2.4 注释明确：`reincarnation_skills` / `dynamic_skill_descriptions` / `skill_used_card_names` 的键自此为实例键。

**验证**：`tests/phase_progression_test.gd`、`tests/skill_settlement_runtime_test.gd` 全绿；新增断言「`runtime_skill_data` 往返一致」。
**回滚点**：字段新增为纯增量，回滚即删除字段与两处读写。

---

## A3 `MatchController`：容器与端口

- [x] A3.1 新增私有工具 `_resolve_skill_instance_key(player_id, key_or_id) -> String`：先按实例键精确匹配，未命中时取 `base_skill_id_of` 匹配的第一个实例键；空字符串表示未命中。
- [x] A3.2 新增私有工具 `_allocate_skill_instance_key(player_skills, skill_id) -> String`：返回 `skill_id`（若空闲）或 `"<skill_id>#<最小可用 N≥2>"`。
- [x] A3.3 `get_skill_instance` 走 A3.1（保持「键或 ID」语义）。
- [x] A3.4 新增 `get_skill_instances(player_id, skill_id) -> Array[SkillDefinition]`、`get_installed_skill_keys(player_id) -> Array[String]`、`get_active_skill_keys(player_id) -> Array[String]`。
- [x] A3.5 `get_installed_skill_ids` 改为返回去重技能 ID（由键还原）。
- [x] A3.6 `has_skill` 保持技能 ID 语义（实例键还原后比较；`acquired_skills` / `temporary_skills` 任一含该技能的实例即真）。
- [x] A3.7 `grant_acquired_skill(..., allow_duplicate := false)`：`allow_duplicate` 为假时保留原去重分支与日志文案；为真时分配新实例键、`set_instance_key`、写入 `acquired_skills[键]`（含 `"skill_id"`）、`install()`。返回 `true`。
- [x] A3.8 `grant_temporary_skill(..., allow_duplicate := false)` 同上。
- [x] A3.9 `can_use_acquired_skill` / `consume_acquired_skill_use` 接受键或 ID（经 A3.1 解析）；额度耗尽时只移除该实例。
- [x] A3.10 `remove_acquired_skill` / `remove_temporary_skill` 只移除被寻址实例；`remove_skill` 按 design D「传 ID 移除全部实例、传键移除单个」实现，并逐个 `uninstall()`。
- [x] A3.11 `can_activate_skill` / `get_active_skill_keys` 返回实例键；`get_active_skill_ids` 保留并返回技能 ID（去重）。
- [x] A3.12 `set_skill_display_description` / `get_skill_used_card_names` / `record_skill_activation` / `repeat_skill_activation` 走 A3.1。
- [x] A3.13 新增 `get_runtime_skill_data(player_id, instance_key)` / `set_runtime_skill_data(player_id, instance_key, data)`；写入后 `_emit_state()`。
- [x] A3.14 `get_used_limited_skill_ids` 返回实例键；`restore_limited_skill_use` 接受键或 ID。

**验证**：`tests/skill_ownership_test.gd`、`tests/skill_settlement_runtime_test.gd`、`tests/skill_choice_test.gd`、`tests/opportunity_system_test.gd` 全绿。
**回滚点**：本阶段改动集中在 `match_controller.gd` 的端口层，未触碰快照与安装路径，可单独回滚。

---

## A4 安装 / 卸载路径

- [x] A4.1 `_install_all_character_skills(saved_keys_by_player := {})`：
  1. native + mode 技能 ID 逐项安装为首实例；
  2. 存档实例键列表中非首实例键 → 还原技能 ID → `create_skill` → `set_instance_key` → `bind` → `install`；
  3. `create_skill` 返回 null 时 `push_error` 并 `add_log` 明确提示「技能定义缺失」，不再静默。
- [x] A4.2 `_reinstall_character_skills_for_player` 与 `_replace_native_character_skills`：换将时按技能 ID 清理**全部**实例（含 `#N`），安装新武将技能时先查实例键是否已占用。
- [x] A4.3 `restore_character_card_skills` / `_rebuild_character_skills_and_zero_usage` 同步按前缀清理与重建。
- [x] A4.4 `_reinstall_saved_runtime_skills` 按实例键还原。
- [x] A4.5 每个 `player_skills[键] = skill` 写入点都先 `skill.set_instance_key(键)`（避免默认回落导致额度记录错位）。

**验证**：`tests/new_character_mechanics_test.gd`、`tests/omphalos_transform_test.gd`、`tests/doudizhu_mode_test.gd` 全绿；新增「换将后同名技能多实例全部清理」断言。
**回滚点**：与 A3 分离，可单独回滚安装路径。

---

## A5 快照与存档

- [x] A5.1 `_append_limited_skill_usage_to_snapshot`：`installed_skill_ids` / `used_limited_skill_ids` / `used_intrinsic_use_skill_ids` 输出实例键；新增 `runtime_skill_data` 与 `acquired_skill_remaining_uses`（实例键）。
- [x] A5.2 `_capture_skill_runtime_states` / `_apply_skill_runtime_states` 按实例键存取。
- [x] A5.3 征服模式 `_build_conquest_save_data` 与恢复路径按实例键；`installed_skill_ids` 保存实例键。
- [x] A5.4 旧存档兼容：纯技能 ID → 首实例；在恢复代码处补注释说明。

**验证**：`tests/requested_changes_test.gd`、`tests/pre_game_deal_gain_test.gd` 全绿；新增「存档 → 读档 → 两实例键与额度一致」断言。
**回滚点**：快照字段名未变，回滚即还原写入内容。

---

## A6 堵住 `SkillDefinition` 的 ID 泄漏

- [x] A6.1 `bind()` 轮回技登记改用 `get_instance_key()`。
- [x] A6.2 `announce_activation()` 的 `record_skill_activation` 与 `consume_acquired_skill_use` 改用 `get_instance_key()`；语音仍用 `get_id()`。
- [x] A6.3 `_can_receive_timing_event()` 的额度门禁改用 `get_instance_key()`，并补注释说明「用技能 ID 会导致重复实例绕过额度」。
- [x] A6.4 `get_skill_player()` 的记录键改用 `get_instance_key()`；`skill_used_card_names` 按实例键。
- [x] A6.5 `ReincarnationSkillService.register_skill` 接受实例键，内部用 `base_skill_id_of` 取元数据；清理按实例键。
- [x] A6.6 `AhhaMomentSystem` 参演队列按实例键登记与完成匹配。
- [x] A6.7 日志显示（`format_skill_log_name` 等）先还原技能 ID，保证玩家看到的技能名不带 `#N`。

**验证**：`tests/reincarnation_mechanics_test.gd`、`tests/ahha_moment_test.gd`、`tests/huohua_joy_test.gd` 全绿；新增「两实例分别计数」与「总额度耗尽只移除自身」断言。
**回滚点**：逐条独立，可按 A6.x 单独回滚。

---

## A7 界面

- [x] A7.1 `CharacterSkillDisplay.collect_visible_skill_keys()` + `build_skill_entries()` 按实例键迭代，条目新增 `"instance_key"`；名称/描述先还原技能 ID，`dynamic_skill_descriptions[实例键]` 优先。
- [x] A7.2 `build_skill_title()` 先还原技能 ID。
- [x] A7.3 `match_table`：`_skill_views` 按实例键、`skill_list_signature` 用实例键、`_get_visible_skill_keys()`、`_get_acquired_skill_remaining_uses()` 按实例键、按钮 payload `skill_id` 传实例键、`_active_response_skill_id` 语义改实例键。
- [x] A7.4 `player_target_view` 的视觉签名与悬停条目改用实例键。
- [x] A7.5 领袖技过滤按技能 ID 判定（同一技能的所有实例同进同出）。
- [x] A7.6 所有颜色仍经 `BattleUIStyle` / `UIStyleRegistry`；无新增硬编码颜色。

**验证**：`tests/ui_layout_test.gd`、`tests/font_color_audit_test.gd`、`tests/skill_target_ui_test.gd` 全绿；新增「同名两实例产出 2 条条目」断言；`editor_screenshot` 目视确认技能栏出现两个同名技能。
**回滚点**：UI 改动独立，可按文件回滚。

---

## A8 AI

- [x] A8.1 `basic_ai_policy._decision_skill_instances` 改按实例键；构造评分实例时 `create_skill(base_skill_id_of(key))` + `set_instance_key(key)`。
- [x] A8.2 `noname_ai_evaluator` / `identity_strategy_evaluator`：迭代实例键，元数据查询先还原技能 ID；「是否拥有技能 X」保持技能 ID 语义。
- [x] A8.3 确认 AI 决策列表中同名实例各自成为候选，不再按 ID 去重。

**验证**：`tests/doudizhu_mode_test.gd`、`tests/ai_*`（若存在）、`tests/smoke_test.gd` 全绿。
**回滚点**：AI 改动独立。

---

## A9 测试与文档

- [x] A9.1 新增 `tests/skill_instance_multiplicity_test.gd` + `.tscn`，覆盖 PRD 验收清单的多实例断言（重复授予、分别计数、分别触发、独立移除、快照键/ID 语义、UI 条目数、存档往返、旧存档兼容）。
- [x] A9.2 扩展 `tests/skill_ownership_test.gd` 的双实例用例。
- [x] A9.3 运行并确认全绿：`skill_ownership_test`、`smoke_test`、`new_character_mechanics_test`、`gameplay_regression_test`、`skill_settlement_runtime_test`、`phase_progression_test`、`reincarnation_mechanics_test`、`opportunity_system_test`、`ahha_moment_test`、`doudizhu_mode_test`、`ui_layout_test`、`font_color_audit_test`、`skill_instance_multiplicity_test`。
- [x] A9.4 `docs/架构说明.md`：新增「技能实例键」章节（键格式、端口兼容约定、快照/存档/网络/AI 口径、边界表）。
- [x] A9.5 `docs/内容制作指南.md`：新增「让技能可获得多份」小节（`allow_duplicate` 用法、实例键读取方式、内容层注意事项、`runtime_skill_data` 用法）。
- [x] A9.6 `docs/游戏机制与玩法内容.md`：新增「同名技能多实例（技能实例键）」机制条目，记录键格式与计数口径。
- [x] A9.7 `README.md`：测试场景清单补充 `skill_instance_multiplicity_test`。
- [x] A9.8 `临时反馈文档.md`：追加学习反馈摘要 + Git 提交描述（带时间戳）。

**验证**：全部测试场景 PASS 标记 + 退出码 0。
**回滚点**：文档与测试为纯增量。

---

## 依赖与顺序

```
A1 → A2 → A3 → A4 → A5
              ↘ A6
A5 → A7 → A8 → A9
```

A6 只依赖 A1（`get_instance_key`），可与 A4/A5 并行。A7/A8 依赖 A3/A5 的端口与快照就绪。
