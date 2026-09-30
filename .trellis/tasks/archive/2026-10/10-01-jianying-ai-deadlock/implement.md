# 执行计划：修复鉴映AI在自身回合的发动-取消死循环

## 步骤

1. **保留复现证据**：先跑一次 `tests/_repro_jianying_ai.tscn`，确认仍能复现“`use_skill jianying` → `jianying_material confirmed=false` 循环”。
2. **通用层改动**（`scripts/ai/noname_ai_evaluator.gd`）：在 `score_choice_action()` 中、通用“支付牌值”扣分分支**之前**新增一个上下文转义位（语义：`ai_choice_skill_scored`，即“本条选择请求的收益已由技能自己的 `score_ai_choice` 全权表达，通用层不得再叠加牌值成本”）；命中且已确认时 `return 0.0`。
   - 与既有 `ai_choice_card_semantics` 转义位并列，命名与注释风格保持一致；
   - 只在该标志为真时生效，不改动任何默认路径。
3. **技能层改动**（`game_data/skills/jianying.gd`）：
   - 在材料步与 B 步（reveal）创建的请求上下文里写入该转义位；
   - 材料步估值改为读取**技能持有者手牌快照**（与 `_get_cheapest_hand_value` 同一来源，例如 `evaluator.get_owned_card_value_by_uid`），使“主动动作被选中 ⇒ 最便宜材料的确认评分 > 0”成为结构性结论；
   - 复核 `AI_SELF_CARD_PENALTY` / `AI_MATERIAL_COST_MULTIPLIER` 等常量在转义位生效后是否仍被重复计入；若重复则按注释说明调整。
4. **回归测试**：在 `tests/zhenzhu_mechanics_test.gd` 增加一个走真实控制器决策链的用例（注册基础 AI → `_begin_play_choice` → 提交动作 → 断言材料步确认为真 → 走完三段 → `_used_this_play_phase` 为真，且外层动作次数为 1）。
5. **删除临时脚本** `tests/_repro_jianying_ai.gd` / `.tscn`（或将其内容并入正式用例后删除）。
6. **文档同步**：`docs/AI模块.md`（鉴映评分口径与新的通用转义位）、`docs/游戏机制与玩法内容.md`（真珠 AI 条目）、`docs/内容制作指南.md`（选择语义转义位说明）、`README.md`（测试清单）。

## 验证命令

```powershell
& 'E:\Godot\Godot_v4.5.1-stable_mono_win64\Godot_v4.5.1-stable_mono_win64_console.exe' --headless --path . --scene res://tests/zhenzhu_mechanics_test.tscn
& 'E:\Godot\Godot_v4.5.1-stable_mono_win64\Godot_v4.5.1-stable_mono_win64_console.exe' --headless --path . --scene res://tests/ai_policy_test.tscn
& 'E:\Godot\Godot_v4.5.1-stable_mono_win64\Godot_v4.5.1-stable_mono_win64_console.exe' --headless --path . --scene res://tests/skill_choice_test.tscn
```

通过标准：退出码 0 且打印对应 `*_PASS` 行；日志落在 `.godot_test_logs/`。

## 完成条件

- PRD 中 4 条验收标准全部满足；
- 上述三个既有场景不回归；
- 文档同步完成，`临时反馈文档.md` 追加本次学习反馈与分点提交描述。
