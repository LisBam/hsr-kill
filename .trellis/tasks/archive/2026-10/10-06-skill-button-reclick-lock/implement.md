# 执行计划：技能按钮在发动流程中失效

## 一、执行顺序清单

- [ ] **1. 删除临时探针**：删除 `tests/zz_probe_skill_reclick_test.gd` 与 `tests/zz_probe_skill_reclick_test.tscn`（调查用，结论已写入 `prd.md`）。
- [ ] **2. 新增判定入口**：在 `scripts/ui/match_table.gd` 中用 `_get_in_flight_skill_release_id()` 取代 `_get_selected_skill_release_id()`，判定不看 `allow_cancel`，仍要求 `context.skill_id` 对应技能 `ui_enabled=true`。
- [ ] **3. 改造刷新分支**：`scripts/ui/match_table.gd` 约 `:2192-2203` 的三个局部量（`skill_release_in_progress` / `skill_response_mode_active` / `skill_selected` / `skill_available`）按 `design.md` 第三节改写。
- [ ] **4. 改造重建分支**：`scripts/ui/match_table.gd` 约 `:2222-2233` 同改，保证首次渲染与后续刷新一致。
- [ ] **5. 改造点击入口**：`scripts/ui/match_table.gd:2425 _on_skill_requested()` 在响应转化分支之后加入"发动中直接 return"守卫。
- [ ] **6. 删除死代码**：移除 `_is_originating_inline_skill_release()` 与 `_cancel_originating_inline_skill_release()`（确认全仓库无其他调用点后再删）。
- [ ] **7. 改写回归用例**：`tests/skill_target_ui_test.gd` 的 `_test_active_skill_second_click_cancels()` 改名为 `_test_active_skill_reclick_is_ignored()`，断言：
  - 发动后该按钮 `disabled=true` 且 `is_skill_selected=true`；
  - 强制 `_on_skill_requested("yaoli")` 后请求仍在、材料仍在手牌、`action_sequence` 不变；
  - 点击"取消"按钮后请求清空、材料仍在手牌、出牌请求重新开放。
- [ ] **8. 新增多段技能用例**：在 `tests/skill_target_ui_test.gd` 增加【濯世】用例，走到第②段费用询问 `zhuoshi_second_cost`，强制点击技能按钮，断言 `context.kind` 仍是 `zhuoshi_second_cost`（未跳到 `zhuoshi_third_cost`）且目标手牌数不变。
- [ ] **9. 同步文档**：改写 `docs/卡牌系统.md`、`docs/界面与交互.md`、`docs/架构说明.md`、`docs/内容制作指南.md`、`docs/游戏机制与玩法内容.md`、`.trellis/spec/content/skill-authoring.md` 中"二次点击取消"的段落，统一为"发动中按钮失效、取消由取消按钮/ Esc / 右键表达"，并写明数值与交互结论（无新增数值）。
- [ ] **10. 追加反馈文档**：按项目规范向根目录 `临时反馈文档.md` 追加带时间戳的「学习反馈摘要」与「Git 提交描述」。
- [ ] **11. 提交**：单一提交，逐行列出改动点。

## 二、验证命令

Godot 可执行文件（本机 4.7.1 控制台版）：

```
GODOT="E:\Godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe"
```

| 目的 | 命令 |
|---|---|
| 技能按钮交互主回归 | `& $GODOT --path "E:\Godot\MyGame\hsr-kill" --headless res://tests/skill_target_ui_test.tscn` |
| 丹恒·饮月双技能规则回归 | `& $GODOT --path "E:\Godot\MyGame\hsr-kill" --headless res://tests/danheng_yinyue_mechanics_test.tscn` |
| 内联选择与取消按钮回归 | `& $GODOT --path "E:\Godot\MyGame\hsr-kill" --headless res://tests/inline_hand_choice_test.tscn` |
| 技能按钮布局与禁用视觉 | `& $GODOT --path "E:\Godot\MyGame\hsr-kill" --headless res://tests/ui_layout_test.tscn` |
| 青雀/【自摸】隐藏取消按钮场景 | `& $GODOT --path "E:\Godot\MyGame\hsr-kill" --headless res://tests/qingque_mechanics_test.tscn` |

判定标准：测试脚本输出 `*_PASS` 且退出码为 `0`；出现 `*_FAIL` 或非 0 退出码即失败。注意场景测试可能打印 `1 resources still in use at exit` 之类退出期告警，只要退出码与 PASS 行正确即视为通过。

## 三、风险文件与回滚点

| 文件 | 风险 | 回滚点 |
|---|---|---|
| `scripts/ui/match_table.gd` | 高：两处 `_render_local_skills` 分支必须同改；点击入口守卫位置必须早于 `can_activate_skill` 判定 | 改动前后各跑一次 `skill_target_ui_test.tscn`；必要时 `git checkout -- scripts/ui/match_table.gd` |
| `tests/skill_target_ui_test.gd` | 中：新用例依赖真实技能实例（药理 / 濯世）与手牌构造，构造失败会表现为误判 | 用例内每一步都给出明确 `_fail_bool` 原因字符串 |
| 五份 `docs/` + 一份 spec | 低：纯文本同步，但必须逐处替换，不能只改一处 | `git diff --stat` 核对改动文件数 |

## 四、`task.py start` 前的自检

- [ ] `prd.md` / `design.md` / `implement.md` 三份产物齐备且互相一致。
- [ ] 阻塞性开放问题为空（失效范围与取消出口已由用户确认）。
- [ ] 探针文件删除计划已列入清单第 1 项。
- [ ] 验证命令可直接执行（已在本机确认 Godot 4.7.1 控制台版路径）。
- [ ] 本次为 inline（DeepSeek Harness）工作流，`implement.jsonl` / `check.jsonl` 由 `trellis-before-dev` 取代，无需填充。
