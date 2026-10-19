# 技能多实例底座（同名技能可重复获得、分别计数）

## Goal

把「一个角色拥有哪些技能」从「技能 ID 集合」升级为「技能**实例**集合」：同一技能 ID 可在一个角色身上同时存在多个实例，每个实例在技能栏/武将详情中各占一项，各自的每回合、每轮、总额度与限定技固有额度**分别计算**，各自独立触发、独立移除；单实例场景的快照、存档、界面与行为与改动前完全一致。

## Requirements

### R1 实例键（唯一身份）

- **R1.1 编码**：每个已安装技能实例拥有一个稳定「实例键」。同一技能 ID 的**第一个**实例的实例键等于技能 ID 本身；第 N（N ≥ 2）个实例的实例键为 `<技能ID>#<N>`，N 取该角色容器内当前未被占用的最小整数（从 2 起）。
- **R1.2 解析**：提供纯静态入口 `SkillDefinition.base_skill_id_of(instance_key) -> String`，把实例键还原为技能 ID（无 `#` 后缀时原样返回）。
- **R1.3 单一来源**：`skill_instances_by_player`、`acquired_skills`、`temporary_skills`、`reincarnation_skills`、`dynamic_skill_descriptions`、`skill_used_card_names`、快照 `installed_skill_ids` / `used_limited_skill_ids` / `used_intrinsic_use_skill_ids` 一律以**实例键**为键。
- **R1.4 端口兼容约定**：所有以技能为参数的公开端口（`get_skill_instance`、`has_skill`、`can_activate_skill`、`can_use_acquired_skill`、`consume_acquired_skill_use`、`remove_skill`、`remove_acquired_skill`、`remove_temporary_skill`、`set_dynamic_skill_description` 等）同时接受**实例键**与**技能 ID**：先按实例键精确匹配，未命中时按技能 ID 匹配该技能的第一个实例。唯一例外是 `remove_skill`（见 R4.3）。

### R2 重复获得

- **R2.1 授予端口**：`grant_acquired_skill()` 与 `grant_temporary_skill()` 末尾新增可选参数 `allow_duplicate: bool = false`。为 `false` 时行为与改动前逐字节一致（已拥有则拒绝并写日志）；为 `true` 时若已有同技能实例，则分配新实例键并安装**第二个独立实例**，返回 `true`。
- **R2.2 独立记录**：重复实例拥有独立的 `acquired_skills[实例键]` / `temporary_skills[实例键]` 记录，记录内新增 `"skill_id"` 字段保存技能 ID。
- **R2.3 首次实例不变**：单实例时实例键即技能 ID，因此既有调用方、既有存档、既有回放与既有测试全部保持原语义。

### R3 分别计算

- **R3.1 额度独立**：每回合限一次、每轮限一次、总次数、限定技固有额度、技能脚本自有的阶段额度（`_used_this_play_phase` 等）全部按实例隔离。
- **R3.2 额度检查不得被绕过**：`SkillDefinition._can_receive_timing_event()` 与 `announce_activation()` 必须使用**实例键**查询与消耗额度；不得出现「实例键查不到记录 → 跳过额度检查」的静默放开。
- **R3.3 触发独立**：同一时机下 N 个实例各自收到事件并各自结算；非锁定技失效、代次校验、死亡/离场校验对每个实例分别成立。
- **R3.4 额度耗尽即失去**：`total_limit` 耗尽时只移除**该实例**。

### R4 独立移除

- **R4.1** `remove_acquired_skill(player_id, 实例键)` / `remove_temporary_skill(player_id, 实例键)` 只移除被寻址的那一个实例，并释放其时机订阅。
- **R4.2** 移除后不得残留任何订阅（`trigger_manager` / `event_bus` / `modifier_pipeline` 均已按对象身份解绑）。
- **R4.3** `remove_skill(player_id, 技能ID)` 传技能 ID 时移除该技能的**全部**实例（角色整体失去该技能）；传实例键时只移除该实例。

### R5 快照与存档

- **R5.1** 观察者快照 `installed_skill_ids` 改为实例键列表（首实例等于技能 ID）；`used_limited_skill_ids` / `used_intrinsic_use_skill_ids` 同为实例键列表。
- **R5.2** 技能拥有权查询保持技能 ID 语义：`SkillDefinition.collect_snapshot_skill_ids()` 返回**去重后的技能 ID**（由实例键还原）；`snapshot_has_skill()` 保持「是否拥有该技能」语义。新增 `SkillDefinition.collect_snapshot_skill_keys()` 返回实例键列表，供界面逐项展示。
- **R5.3** 新增 `PlayerState.runtime_skill_data: Dictionary`（实例键 → 该实例的运行时配置字典），进入公开快照与权威存档，并提供 `MatchController.get/set_runtime_skill_data()` 端口；未写入任何实例时不影响既有快照。
- **R5.4** 读档：`_install_all_character_skills` 按实例键还原技能 ID 并重新分配同一实例键；纯技能 ID 的旧存档按「首实例」处理，行为不变。
- **R5.5** 征服模式存档 `skill_runtime_states` 与 `installed_skill_ids` 同步改为实例键。

### R6 界面

- **R6.1** 技能查看的唯一实现仍是 `CharacterSkillDisplay`：新增按实例键输出的入口，悬停资料、右键详情、技能栏三处共用。
- **R6.2** 同名技能在技能栏与详情中各占一项；标题相同但各自独立可点击、可查看、可发动。
- **R6.3** 技能按钮的列表签名必须按实例键区分，同名技能不得因签名相同而被判为「无变化」。
- **R6.4** 限定技/觉醒技的变淡表现、轮回技徽记、动态描述、剩余次数提示全部按实例键读取。

### R7 AI

- **R7.1** AI 决策上下文与动作负载按实例键寻址，能够发动第 2 个实例。
- **R7.2** AI 读取技能元数据（`GameDatabase.get_skill`）时一律先还原技能 ID。
- **R7.3** 「对手是否拥有技能 X」类判定保持技能 ID 语义。

### R8 边界与文档

- **R8.1** 轮回技：`register_reincarnation_skill` 按实例键登记，同一轮回技的多个实例各自持有轮回进度；技能被移除时清理该实例的轮回记录。
- **R8.2** 欢愉技：阿哈时刻参演队列按实例键登记与完成匹配。
- **R8.3** 过关斩将模式「敌方技能机缘不重复」是**模式规则**，保持不变，并在文档中说明它不受本次改动影响。
- **R8.4** `docs/架构说明.md` 增补「技能实例键」章节（键格式、端口兼容约定、快照/存档/网络口径）；`docs/内容制作指南.md` 增补「让技能可获得多份」的制作规范；`docs/游戏机制与玩法内容.md` 记录该机制规则。

## Acceptance Criteria

- [ ] `SkillDefinition.base_skill_id_of("zhuru") == "zhuru"`、`base_skill_id_of("zhuru#2") == "zhuru"`。
- [ ] 同一角色连续两次 `grant_acquired_skill(pid, "zhuijian", 1, 0, "test", false, 0, true)` 后，该角色容器内存在 `"zhuijian"` 与 `"zhuijian#2"` 两个实例。
- [ ] `has_skill(pid, "zhuijian") == true`；`get_skill_instances(pid, "zhuijian").size() == 2`；`get_installed_skill_ids(pid)` 中 `"zhuijian"` 只出现一次；`get_installed_skill_keys(pid)` 含两个键。
- [ ] 实例 A 在同一回合发动一次后，实例 B 仍可发动；同一回合内实例 A 第二次发动被拒绝。
- [ ] `total_limit = 1` 的两个实例各自可发动一次，耗尽后只移除自身。
- [ ] 两个实例订阅同一时机时，一次事件产生两次独立结算。
- [ ] `remove_skill(pid, "zhuijian#2")` 后 `"zhuijian"` 仍可发动；`remove_skill(pid, "zhuijian")` 后两个实例都消失，且 `trigger_manager` 中不再有这两个 owner 的订阅。
- [ ] 快照 `installed_skill_ids` 含 `["zhuijian", "zhuijian#2"]`，`SkillDefinition.collect_snapshot_skill_ids(snapshot)` 中 `"zhuijian"` 只出现一次，`snapshot_has_skill(snapshot, "zhuijian")` 为真。
- [ ] `CharacterSkillDisplay` 对上述快照产出 2 条技能条目，标题相同、实例键不同。
- [ ] 存档 → 读档后两个实例的键、额度、动态描述与轮回状态完全还原。
- [ ] 旧存档（`installed_skill_ids` 只含技能 ID）读档后技能数量与行为不变。
- [ ] 既有测试场景全绿（`skill_ownership_test`、`smoke_test`、`new_character_mechanics_test`、`gameplay_regression_test`、`skill_settlement_runtime_test`、`phase_progression_test`、`reincarnation_mechanics_test`、`opportunity_system_test`、`ahha_moment_test`、`doudizhu_mode_test`、`ui_layout_test`、`font_color_audit_test`）。
- [ ] 新增 `tests/skill_instance_multiplicity_test.tscn` 覆盖上述多实例断言。
- [ ] `docs/架构说明.md`、`docs/内容制作指南.md`、`docs/游戏机制与玩法内容.md` 已同步。

## Notes

- 本次改动**不得**改变任何既有技能的玩家可见描述原文。
- 本次改动**不得**改变单实例场景下的快照字段名与取值，避免破坏旧存档与旧回放。
- 设计决策与备选方案对比见 `design.md` 的 D1。
