# 封装技能拥有查询端口

> 子任务，父任务 `10-18-ruanmei-and-skill-ownership-query`。
> **必须在本任务的兄弟任务 `10-18-ruanmei-character-skills` 之前完成**：后者在规则段与 AI 段都要调用本任务交付的入口。
> 技术设计（双层契约、收敛清单、风险对策）写在父任务 `../10-18-ruanmei-and-skill-ownership-query/design.md` 第 1 节，本文件只列需求与验收。

## Goal

把「检查某角色是否拥有指定技能」封装为**唯一**的两个入口（规则侧权威端口 + 快照侧共享纯函数），并把项目内 6 处各自实现收敛到该入口，顺带修掉其中的既有判定缺陷。

## 背景（现状证据）

- 项目目前**没有**布尔形式的技能拥有查询，只有返回数组的 `MatchController.get_installed_skill_ids(player_id)`（`scripts/core/match_controller.gd:10563`）。
- 「是否拥有技能 X」在以下位置各自重复实现，口径互不一致：
  1. `scripts/ai/noname_ai_evaluator.gd:796` `_collect_snapshot_skill_ids`（私有，注释自称“唯一来源”，但**未按 `installed_skill_ids` 裁剪**）
  2. `scripts/ai/noname_ai_evaluator.gd:787` `_snapshot_player_has_skill`
  3. `scripts/ai/noname_ai_evaluator.gd:463` `_modify_incoming_card_effect_by_target_skills` 内联枚举
  4. `scripts/ai/basic_ai_policy.gd:~398` 内联枚举
  5. `scripts/ai/identity_strategy_evaluator.gd:~263` 内联枚举
  6. `game_data/skills/shengbian.gd:~199` 内联枚举（**已按 `installed_skill_ids` 裁剪**，是正确口径）
  7. `game_data/skills/yaoli.gd:191` `_owner_has_skill`（**只读武将固有技能列表**）
  8. `game_data/cards/huogong.gd:263` `_snapshot_has_skill`
  9. `scripts/ui/` 三处展示侧枚举
- 因此同一条规则在规则段与 AI 段可能得到不同答案；且 #1 与 #7 是**已存在的缺陷**。

## Requirements

### R1 规则侧权威端口

- R1.1 在 `scripts/core/match_controller.gd` 新增 `has_skill(player_id: int, skill_id: String) -> bool`，位置紧邻既有 `get_installed_skill_ids`。
- R1.2 判定口径 = 已安装技能实例 ∪ `acquired_skills` 记录 ∪ `temporary_skills` 记录。并上两个记录字典是必须的：`remove_skill()` 的既有注释明确「实例为空但记录仍在时同样算拥有」。
- R1.3 必须覆盖「视为拥有技能」类效果：`grant_acquired_skill()` 授予的技能返回 `true`。
- R1.4 纯只读：不创建技能实例、不安装时机、不广播状态、不写日志。
- R1.5 不做存活过滤（死亡/离场角色的技能归属如实返回），由调用方按自身语义决定是否过滤。

### R2 快照侧共享纯函数

- R2.1 在 `game_data/skill_definition.gd` 新增两个静态函数：`collect_snapshot_skill_ids(player_snapshot) -> Array[String]` 与 `snapshot_has_skill(player_snapshot, skill_id) -> bool`。
- R2.2 枚举顺序固定为 固有 → 模式 → 临时 → 局内获得，并去重，与 R1.2 口径一致。
- R2.3 快照带 `installed_skill_ids` 字段时，按它裁剪**固有**与**模式**技能（该字段是“此刻真实安装”的权威列表；失去技能后必须被裁掉）。字段不存在时不裁剪，兼容旧快照与手工构造的测试快照。
- R2.4 `snapshot_has_skill` 直接做成员判定、不构造中间数组，供高频查询使用。
- R2.5 只读公开稳定 ID，不读取隐藏信息，不创建技能实例。

### R3 收敛既有重复实现

- R3.1 按父任务 `design.md` 第 1.4 节的清单逐项替换；语义等价者一律改用统一入口。
- R3.2 `scripts/ui/` 的展示侧枚举**逐个核对**：语义等价者改用统一入口；确属展示专属（技能栏顺序、可见性开关）者保留，并在注释中写明「拥有口径来自统一入口，此处只做展示排序」。
- R3.3 收敛过程中不得改变任何技能的既有业务过滤（例如 `shengbian.gd` 只统计带特定标签的技能，这层过滤必须保留）。

### R4 修复既有缺陷

- R4.1 修复 #1：AI 侧技能枚举按 `installed_skill_ids` 裁剪，不再把「已失去的固有技能」算作拥有。
- R4.2 修复 #7：`yaoli.gd` 的拥有判定不再漏判模式 / 临时 / 局内获得技能。

### R5 文档

- R5.1 `docs/内容制作指南.md`：常用规则操作端口表补 `has_skill` 行；技能制作章补「技能拥有查询双层入口」小节（两个入口的签名、使用示例、`installed_skill_ids` 裁剪规则、纯只读约束）。
- R5.2 `docs/AI模块.md`：说明 AI 侧统一使用快照静态入口，禁止再写私有枚举。

## Acceptance Criteria

- [ ] AC1 `MatchController.has_skill()` 存在且为纯只读；四类来源（固有 / 模式 / 临时 / 局内获得）均返回正确结果。
- [ ] AC2 `SkillDefinition.collect_snapshot_skill_ids()` 与 `SkillDefinition.snapshot_has_skill()` 存在，结果与 `has_skill()` 在四类来源上一致。
- [ ] AC3 `installed_skill_ids` 裁剪规则只有一处实现，且有回归用例覆盖「固有技能被移除后不再被判为拥有」。
- [ ] AC4 全项目不再存在第二处「枚举某角色全部技能 ID」的实现（`scripts/ui/` 保留项必须有注释说明其展示专属语义）。
- [ ] AC5 `yaoli.gd` 的拥有判定能识别局内获得的技能，有回归用例锁定。
- [ ] AC6 `scripts/ai/noname_ai_evaluator.gd` 的 `get_snapshot_sell_blood_value()` 行为对既有技能（【百折】=1.0，其余=0.0）保持不变。
- [ ] AC7 `ai_policy_test` / `gameplay_regression_test` / `new_character_mechanics_test` 串行跑通，无 `SCRIPT ERROR` / `FAIL`。
- [ ] AC8 文档同步完成（R5）。
- [ ] AC9 学习反馈摘要 + 编号 Git 提交描述已追加到根目录 `临时反馈文档.md`。

## Out of Scope

- 不新增任何武将或技能内容（那是兄弟任务 `10-18-ruanmei-character-skills` 的范围）。
- 不修改 `sell_blood_value` 的既有静态语义与既有消费者行为。
- 不重构 `scripts/ui/` 的展示逻辑，只做口径收敛。

## Notes

- 本任务改动集中在 `scripts/core`、`scripts/ai`、`game_data` 三层，动手前必须加载 `trellis-before-dev` 读取对应层 spec。
- 收敛会改变 #1 与 #7 的行为（都是修正）。执行顺序：**先补期望值回归用例 → 再替换实现 → 再跑全量**，避免误伤被当成回归。
