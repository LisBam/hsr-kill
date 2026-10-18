# 执行计划 · 阮梅武将与技能拥有查询机制（父任务）

> 父任务是**集成与验收**容器：自身不产出独立代码，只负责编排两个子任务的顺序、锁定跨子任务的共享契约、并在两者都完成后执行整体验收。
> 逐项技术细节见 `design.md`；单技能结算细节见 `10-18-ruanmei-character-skills/design.md`。

---

## 1. 实施顺序（严格串行）

| 阶段 | 任务 | 产出 | 完成判据 |
|---|---|---|---|
| P1 | `10-18-skill-ownership-query-port` | 层 A 端口 `has_skill` + 层 B 静态入口 + 6 处收敛 + 既有缺陷修复 | 该子任务自身验收全绿 |
| P2 | `10-18-ruanmei-character-skills` | 阮梅武将 + 【梅绽】【灵赋】【阮弦】+ 配套 AI | 该子任务自身验收全绿 |
| P3 | 本父任务 | 跨子任务集成验收 + 全量文档一致性核对 + 学习反馈与提交描述 | 本文第 3 节全部勾选 |

**P1 必须先于 P2**：P2 的三个技能文件在规则段与 AI 段都要调用 P1 交付的入口；若先写 P2 会临时产生第二套技能枚举实现，违背本次交付的核心目标。

**为什么不是父子依赖系统**：本项目的任务树不表达依赖，顺序只写在这里与两个子任务的 `prd.md` 中，由执行者遵守。

## 2. 每个阶段内的固定动作

1. **动手前**：加载 `trellis-before-dev`，读取 `game_data` 层与 `scripts/core` / `scripts/ai` 层的 spec 与检查清单。
2. **改动中**：所有魔法数字提取为带注释的常量；每个变量独占一行注释；Tab 缩进。
3. **改完代码后立刻**：同步 `docs/` 对应文档（清单见 `design.md` 第 4 节），不允许“先写代码后补文档”跨阶段遗留。
4. **阶段收尾**：加载 `trellis-check` 执行质量门禁，再写学习反馈摘要与编号 Git 提交描述，追加到根目录 `临时反馈文档.md`（带 `YYYY-MM-DD HH:MM` 时间戳）。

## 3. 父任务验收清单

### 3.1 技能拥有查询（R1）

- [x] 全项目「某角色是否拥有技能 X」的判定只有**一处**实现。
- [x] `installed_skill_ids` 裁剪规则只有**一处**实现。
- [x] 层 A 与层 B 在四类来源（固有 / 模式 / 临时 / 局内获得）上返回一致结果，有用例覆盖。
- [x] 两个既有缺陷已修并有回归用例锁定：
  - [x] AI 侧技能枚举不再把「已失去的固有技能」算作拥有。
  - [x] 只读武将固有技能列表的入口不再漏判模式 / 临时 / 局内获得技能。
- [x] 查询为纯只读：不创建技能实例、不安装时机、不写日志、不改写状态。
- [x] `scripts/ui/` 中语义等价的枚举已收敛；确属展示专属的保留项已在注释中注明「拥有口径来自统一入口」。

### 3.2 阮梅与三技能（R2–R6）

- [x] 阮梅可在开局选将中正常出现并选中；`GameDatabase.validation_errors` 为空。
- [x] 三个技能 `description` 与用户原文主句**逐字一致**（含【梅绽】原文两个右引号 `”`）。
- [x] 【梅绽】锁定技，任意持有者受伤 → 全部持有者各摸1张（含受伤者本人与阮梅）。
- [x] 【灵赋】每出牌阶段1次；全局每种牌类别1次；确定后**先重铸、后结算**。
- [x] 【灵赋】分支一：目标无“梅绽” → 目标获得“梅绽”。
- [x] 【灵赋】分支二：目标已有“梅绽” → 目标 +1 体力上限、回复1点体力，然后阮梅失去【灵赋】。
- [x] 【灵赋】全局限次在「失去【灵赋】→ 重新获得」与「存档往返」后不复活。
- [x] 【灵赋】目标范围含阮梅自己（项目「一名角色」既有口径）。
- [x] 【阮弦】结束阶段1次；全局每种花色1次；只令**其他**梅绽持有者各摸1张（不含阮梅）。
- [x] 【阮弦】全局限次同样跨技能实例重建存活。
- [x] 两个技能在无可用材料 / 无合法目标 / 非对应阶段时**不创建**任何选择请求。

### 3.3 AI（R6）

- [x] 【灵赋】三级优先完整实现：无梅绽队友 → 有卖血技能队友 → 体力最低者。
- [x] 【灵赋】提示未覆盖的通用逻辑已补全：发动时机与收益门槛、材料按保留价值从低到高选取、取消动作零分基线、敌方目标负收益惩罚。
- [x] 【阮弦】发动判定评估材料保留价值与受益队友数量，严格正分才发动。
- [x] 【梅绽】动态卖血估值以出手方为参照系，两个分支（目标为敌 / 为友）符号都正确，且只对伤害类来牌生效。
- [x] 未新增任何技能 ID 白名单；「卖血技能」判定复用 `sell_blood_value` 既有元数据。
- [x] 其他武将 / 卡牌的 AI 决策未受影响（`ai_policy_test` 全绿）。

### 3.4 文档（R7）

- [x] `docs/内容制作指南.md`：端口表、技能拥有查询双层入口小节、全局限次存储约定、动态卖血钩子用法、重铸先于后续效果的 `defer_settlement` 用法。
- [x] `docs/游戏机制与玩法内容.md`：阮梅与三技能的机制说明 + **全部具体数值**。
- [x] `docs/AI模块.md`：技能拥有查询入口 + 梅绽动态卖血口径。
- [x] `docs/卡牌系统.md` / `README.md`：按需核对后同步或明确记录“无需改动”的理由。

### 3.5 质量门禁

- [x] 相关测试场景串行跑通，无 `SCRIPT ERROR` / `FAIL`：
  - `tests/gameplay_regression_test.tscn`
  - `tests/ai_policy_test.gd` 所在场景
  - `tests/new_character_mechanics_test.gd` 所在场景
  - `tests/skill_settlement_runtime_test.tscn`
  - `tests/event_runtime_test.tscn`
  - `tests/rule_timing_test.tscn`
  - `tests/health_mechanics_test.tscn`
  - `tests/phase_progression_test.tscn`
- [x] 新增回归用例覆盖：技能拥有查询四来源、`installed_skill_ids` 裁剪、灵赋先重铸后结算、全局限次跨失去技能存活、阮弦“其他角色”排除自己、梅绽多持有者摸牌、梅绽动态卖血两分支符号。
- [x] 学习反馈摘要 + 编号 Git 提交描述已追加到 `临时反馈文档.md`。

## 4. 回滚点

| 阶段 | 回滚点 |
|---|---|
| P1 | 逐文件回滚：`scripts/core/match_controller.gd`、`game_data/skill_definition.gd`、`scripts/ai/*`、`game_data/skills/shengbian.gd`、`game_data/skills/yaoli.gd`、`game_data/cards/huogong.gd` |
| P2 | 删除 `game_data/characters/ruanmei.gd` 与 `game_data/skills/{meizhan,lingfu,ruanxian}.gd` 即完全退出，无残留注册点（内容目录自动扫描） |
| P3 | 文档回滚不影响运行；代码回滚以 P1/P2 为单位 |

---

## 5. P3 集成验收记录（执行结果）

### 5.1 收敛完备性复核

全项目扫描「枚举技能来源」的代码点，逐个确认其**问的是不是同一个问题**：

| 位置 | 问的问题 | 处置 |
|---|---|---|
| `match_controller.gd:10595`（`has_skill` 内） | 「此刻是否拥有技能 X」 | **权威实现，唯一一处** |
| `skill_definition.gd:299 / 343` | 同上（快照侧） | **快照实现，唯一一处** |
| `match_controller.gd:4797 / 10391` | 「除被移除的来源之外，还有没有别的来源提供这个技能」 | 来源归属判定，**不是拥有查询**：必须在卸载实例**之前**读取来源清单，此时 `has_skill()` 恒为真，因此不得改写 |
| `skill_definition.gd:655` | 「这个实例是不是来自『局内获得』这一来源」 | 来源归属判定，用于跳过固有技能的额度检查 |
| `match_controller.gd:10336 / 10359 / 10385 / 10432` | 「这个来源的记录还在不在」 | 来源专属端口（`can_use_acquired_skill` / `remove_acquired_skill` / `remove_temporary_skill`） |
| `match_controller.gd:11051 / 11052` | 「移除前该来源的记录是否存在」 | `remove_skill()` 的清理决策 |
| `match_controller.gd:9841 / 11085 / 11089 / 11271 / 16170 / 16172`、`10454` | 逐项遍历以执行移除、归零额度或恢复 | 遍历而非查询 |
| `match_table.gd:2320-2340`、`player_target_view.gd:679-691` | 展示排序 + 缺失定义占位 + 领袖技可见性 | **展示专属，保留**；已在注释中写明「拥有口径来自统一入口」 |
| `information_box_layer.gd:965`、`all_cards_panel.gd:585 / 639 / 761` | 渲染**武将牌本身**的内容 | 与拥有权无关，不需要收敛 |
| `character_selection_panel.gd` / `online_settings_panel.gd` / `developer_console_panel.gd` | 选将候选与头像列表 | 与技能拥有权无关 |

结论：`installed_skill_ids` 裁剪规则在**规则侧只有一处**（`collect_snapshot_skill_ids`），`snapshot_has_skill` 与之共用同一套来源清单与裁剪判定；UI 侧两条保留管线各自带免责注释。

### 5.2 两处既有缺陷的回归锁

| 缺陷 | 回归用例 | 断言 |
|---|---|---|
| AI 侧技能枚举不按 `installed_skill_ids` 裁剪，把已失去的固有技能继续算成拥有 | `skill_ownership_test` → `_test_ai_sell_blood_respects_installed` | 旧快照（无裁剪字段）卖血价值 `1.0`；权威快照明确未安装【百折】时归零；运行时获得的卖血技能照常计入 |
| 【药理】联动只读武将固有技能列表，漏判模式 / 临时 / 局内获得技能 | `skill_ownership_test` → `_test_yaoli_linkage_uses_unified_entry`（P3 新增） | 局内获得技能返回真、临时技能返回真、固有技能仍返回真、权威快照明确未安装时返回假 |

### 5.3 阮梅开局选将可用性

`ruanmei_mechanics_test` → `_test_ruanmei_metadata` 新增两条断言：`GameDatabase.get_selectable_character_ids()` 必须包含 `ruanmei`（武将未标 `special`，因此进入普通可选池），且 `resolve_character_name("ruanmei")` 必须等于 `阮梅`。

### 5.4 质量门禁结果

以下 16 个场景**串行**运行，全部 `EXIT=0`，无 `SCRIPT ERROR` / `ERROR:` / `FAIL`：

`smoke_test`、`skill_ownership_test`、`multi_recast_test`、`ruanmei_mechanics_test`、`gameplay_regression_test`、`ai_policy_test`、`new_character_mechanics_test`、`skill_settlement_runtime_test`、`event_runtime_test`、`rule_timing_test`、`health_mechanics_test`、`phase_progression_test`、`ui_layout_test`、`yinzhi_xunli_lijie_test`、`main_menu_test`、`skill_target_ui_test`。

其中 `smoke_test` 额外锁定 `GameDatabase.validation_errors` 为空、技能定义数 `115`、武将定义数 `53`，并跑完一整局 AI 对局（`SMOKE_PASS game_over winner=rebels actions=221 frames=795`）。

### 5.5 文档同步结果

| 文档 | 结果 |
|---|---|
| `docs/游戏机制与玩法内容.md` | 阮梅条目 + 三技能机制 + 全部数值（含 AI 权重） |
| `docs/AI模块.md` | 技能拥有判定统一入口 + 【梅绽】动态卖血 + 【灵赋】三级优先与费用同源 + 【阮弦】净受益者符号 |
| `docs/内容制作指南.md` | 双层入口 + 快照来源前提 + 全局归属效果写法 + 全局限次存放位置 + 重铸两段式 + 重铸口径 |
| `docs/架构说明.md` | 技能拥有查询统一入口说明（P1） |
| `.trellis/spec/core/layering-and-state.md` | 拥有查询约束（P1） |
| `.trellis/spec/content/skill-authoring.md` | 先重铸后效果、触发时机两段式、全局归属与全局限次、重铸口径（P2） |
| `README.md` | 新增 `skill_ownership_test` 与 `ruanmei_mechanics_test` 两条说明 |
| `docs/卡牌系统.md` | **核对后确认无需改动**：第 260 行已写明「重铸仍严格为弃置1张、随后摸1张；最后手牌触发插入事件时只延后摸牌，不改变数量」，与本次实现完全一致 |
