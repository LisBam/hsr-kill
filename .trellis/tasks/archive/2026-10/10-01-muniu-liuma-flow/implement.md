# 执行计划：木牛流马两段式流程与5张容量上限

## 步骤

1. **基线**：跑 `tests/gameplay_regression_test.tscn`、`tests/inline_hand_choice_test.tscn`、`tests/ui_layout_test.tscn`、`tests/requested_changes_test.tscn`，记录与木牛相关的既有断言位置。
2. **接口扩展**（`game_data/card_definition.gd` + `scripts/core/match_controller.gd`）：
   - 新增 `continue_equipment_selection(match_host, context, response: ChoiceResponse) -> bool` 基类钩子（默认 `return false`），注释说明“不依附处理区父牌、且需要读取目标与确认状态的装备选择恢复入口”；
   - 在控制器装备恢复分支（约第3835-3856行）接入该钩子，保持既有调用顺序不变。
3. **第一段改造**（`game_data/cards/muniuliuma.gd`）：
   - 顶部分别新增 `TRANSFER_PROMPT` 与 `WOODEN_OX_STORAGE_CAPACITY = 5` 常量（各带用途/取值范围/修改影响注释）；
   - `validate_play_phase_action()` 拒绝第一段携带目标，并在容量已满时返回明确拒绝原因；
   - `execute_play_phase_action()` 只完成存牌，然后创建第二段目标选择请求（提示文本取自常量，`allow_cancel = true`）；
   - `is_play_phase_action_available()` 与 `append_play_phase_actions()` 落实容量上限；
   - 实现 `continue_equipment_selection()`：取消分支与确认分支；
   - `get_play_phase_action_preview()` 去掉 `optional_single_other` 目标语义。
4. **控制器预览改造**：移除/改写 `_build_play_phase_action_preview` 中 `store_wooden_ox` 的可选目标分支（约第15799-15815行），改为“第一段不需要目标”，并更新该处注释。
5. **AI 补全**：`score_ai_choice()` 实现第二段的“取消 / 转移给最优队友”判断；`score_ai_play_phase_action()` 复核容量上限；说明补全范围与未覆盖情形。
6. **测试**：按 `design.md` 第5节新增/改写用例（两步顺序、取消、确认、容量 4→5 与 5→拒绝、AI 不越界）；同步 `tests/gameplay_regression_test.gd` 中依赖“一步完成转移”的断言。
7. **文档同步**：`docs/游戏机制与玩法内容.md`（木牛条目与数值：容量5）、`docs/内容制作指南.md`（装备主动动作与两段式恢复钩子、容量端口）、`docs/界面与交互.md`（新交互与提示文本）、`docs/AI模块.md`（木牛 AI）、`docs/卡牌系统.md`（第106/108行附近装备结算描述）、`README.md`。

## 验证命令

```powershell
& 'E:\Godot\Godot_v4.5.1-stable_mono_win64\Godot_v4.5.1-stable_mono_win64_console.exe' --headless --path . --scene res://tests/gameplay_regression_test.tscn
& 'E:\Godot\Godot_v4.5.1-stable_mono_win64\Godot_v4.5.1-stable_mono_win64_console.exe' --headless --path . --scene res://tests/inline_hand_choice_test.tscn
& 'E:\Godot\Godot_v4.5.1-stable_mono_win64\Godot_v4.5.1-stable_mono_win64_console.exe' --headless --path . --scene res://tests/ui_layout_test.tscn
& 'E:\Godot\Godot_v4.5.1-stable_mono_win64\Godot_v4.5.1-stable_mono_win64_console.exe' --headless --path . --scene res://tests/requested_changes_test.tscn
& 'E:\Godot\Godot_v4.5.1-stable_mono_win64\Godot_v4.5.1-stable_mono_win64_console.exe' --headless --path . --scene res://tests/ai_policy_test.tscn
```

## 完成条件

- PRD 中 7 条验收标准全部满足；
- 上述五个场景通过；
- 文档同步完成，`临时反馈文档.md` 追加本次学习反馈与分点提交描述。
