# 执行计划：参考无名杀优化铁索连环与重铸的AI决策

调研证据见同目录 `research.md`；实现时逐条对照，不依赖记忆。

## 步骤

1. **基线**：跑 `tests/gameplay_regression_test.tscn`、`tests/ai_policy_test.tscn`、`tests/multi_recast_test.tscn`，确认当前全部通过；记录铁索相关断言位置。
2. **补全通用查询能力**（`scripts/ai/noname_ai_evaluator.gd`，只在确有需要时）：
   - “场上能承受火/雷属性伤害的存活角色数”这一类查询应作为通用评估器能力实现，并按牌效语义可复用，避免卡牌文件自行遍历玩家；
   - 若护甲已有 `get_ai_incoming_damage_multiplier` 等接口，横置收益倍率/免疫横置也应走同一护甲与技能标签查询口径，不新增硬编码牌名。
3. **卡牌侧（`game_data/cards/tiesuolianhuan.gd`）** 按 `research.md` 第5节逐条落地：
   - 新增硬门槛：可受属性伤害角色 < 2 → 返回重铸分；
   - 新增全局否决：≥2名敌人且已有敌人横置 → 不再横置敌人（压到重铸分之下）；
   - 目标收益按 `research.md` 第1节修正（免疫横置 / 免火免雷 → 0；只免一种 → 收益减半；【藤甲】且不免火 → 翻倍）；
   - 保留 1v1 强制重铸与“整组合总分”口径，并在注释中标明与无名杀原版的差异；
   - 所有新数值提取为 `const`，带用途/取值范围/修改影响注释。
4. **重铸时机**：确认修复后仍是“只有没有任何正收益目标时才重铸”，不得出现“有正收益目标仍重铸”的新回归（由断言保证）。
5. **AI 补全说明**：在代码注释与 `docs/AI模块.md` 中写清新增判定覆盖的局面与未覆盖的局面（无随机化的无懈保留策略不移植）。
6. **测试**：在 `tests/gameplay_regression_test.gd`（或 `tests/ai_policy_test.gd`）新增门槛断言，覆盖 PRD 的 7 条验收标准。
7. **文档同步**：`docs/AI模块.md`、`docs/卡牌系统.md`（第39行整段）、`docs/游戏机制与玩法内容.md`（横置与重铸）、`docs/内容制作指南.md`（卡牌 AI 钩子与重铸端口）、`README.md`。

## 验证命令

```powershell
& 'E:\Godot\Godot_v4.5.1-stable_mono_win64\Godot_v4.5.1-stable_mono_win64_console.exe' --headless --path . --scene res://tests/gameplay_regression_test.tscn
& 'E:\Godot\Godot_v4.5.1-stable_mono_win64\Godot_v4.5.1-stable_mono_win64_console.exe' --headless --path . --scene res://tests/ai_policy_test.tscn
& 'E:\Godot\Godot_v4.5.1-stable_mono_win64\Godot_v4.5.1-stable_mono_win64_console.exe' --headless --path . --scene res://tests/multi_recast_test.tscn
& 'E:\Godot\Godot_v4.5.1-stable_mono_win64\Godot_v4.5.1-stable_mono_win64_console.exe' --headless --path . --scene res://tests/control_all_characters_test.tscn
```

## 完成条件

- PRD 中 7 条验收标准全部满足；
- 上述四个场景通过；
- 文档同步完成，`临时反馈文档.md` 追加本次学习反馈与分点提交描述。
