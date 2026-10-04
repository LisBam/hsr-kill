# 执行计划：优化获得牌飞行落点与拖拽落位过渡

## 0. 前置

- 依赖上一轮成果（已归档 `10-04-card-interaction-animation-continuity`）：`_try_take_card_origin()`、`_should_show_card_back()`、`_local_hand_gain_flight_gates`、`play_transfer(..., on_flight_finished)`、`hand_layout_offset`、`relayout_animation_seconds`。
- 先读 `.trellis/spec/ui/component-patterns.md` 与 `.trellis/spec/ui/index.md`，确认界面层规范后再动代码。
- Godot 可执行文件：`E:\Godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64.exe`。
- 测试跑法（**必须用管道，不要用变量捕获原生输出**）：
  ```powershell
  & $godot --headless --path . res://tests/<name>_test.tscn 2>&1 | Select-String -Pattern "_PASS|_FAIL|SCRIPT ERROR"; $LASTEXITCODE
  ```

## 1. 基线验证（改动前）

1. `ui_layout_test.tscn` → `UI_LAYOUT_PASS`
2. `smoke_test.tscn` → `SMOKE_PASS`
3. `virtual_hand_choice_test.tscn` → `VIRTUAL_HAND_CHOICE_PASS`
4. `draw_sequence_test.tscn` → `DRAW_SEQUENCE_PASS`
5. `match_replay_test.tscn` → `MATCH_REPLAY_PASS`
6. `gameplay_regression_test.tscn` → `GAMEPLAY_REGRESSION_PASS`

任一不为绿先修基线，不得带着红基线开工。

## 2. 实现顺序（自底向上，每步可独立验证）

### 步骤 2.1 — `DecadeHandContainer` 拖拽落位过渡（R1，无依赖）

- 新增 `@export_range(0.05, 0.8, 0.01) var drag_settle_seconds: float = 0.18`（放在 `relayout_animation_seconds` 之后，逐行注释说明用途与运行时可否调整）。
- 新增 `var _settle_start_positions: Dictionary = {}`（实例 ID → 释放点左上角容器坐标）。
- 新增 `begin_card_settle(card, release_position)`；`_layout_cards()` 的位置写入点改为先算 `base_position` 再消费释放点；新增 `_start_settle_transition()` 与共用补间创建 `_start_layout_offset_tween()`；`_start_relayout_transition()` 改为调用共用补间创建（行为不变）。
- `_clear_departed_card_layout_records()` 一并清理 `_settle_start_positions`。
- 验证：`ui_layout_test` 仍 PASS（此时还没有用例覆盖新接口，先保证不回归）。

### 步骤 2.2 — `MatchTable` 松手接入落位过渡（R1）

- `_on_hand_drag_finished()`：在 `end_hand_drag()` 之前取 `release_position = source_view.position`，随后调用 `hand_container.begin_card_settle(source_view, release_position)`；未命中目标的早退分支保留。
- 验证：`ui_layout_test` PASS。

### 步骤 2.3 — `CardUseAnimationLayer` 批次逐张落点（R3）

- `play_draw_transfer_batch(...)` 新增可选 `card_targets: Array[Vector2] = []`，长度匹配时逐张使用自己的终点，否则保持整组居中；`_play_draw_transfer_batch(...)` 同步接收。
- 验证：`smoke_test` 的直连批次断言（整组居中 + 42 像素间距）必须仍然 PASS——证明默认路径未被改动。

### 步骤 2.4 — `CardUseAnimationLayer` 取走中央展示牌（R4）

- 抽出 `_detach_presented_card(card_view)`（含 `_fade_queue.erase`），`_remove_presented_card()` 复用它 + `queue_free()`。
- 新增 `take_over_active_card(card_uid) -> CardView`：查找 → 摘除索引 → 队列补位 → 返回节点。
- 验证：`ui_layout_test` + `match_replay_test` PASS（中央展示队列与回放不受影响）。

### 步骤 2.5 — `MatchTable` 门闸升级与飞行延后（R2/R3/R4）

按依赖顺序改：

1. 门闸记录结构升级为 `{card, origin, started, batch}`；`_hold_gated_local_hand_entries()` 改为按 `started` 过滤并按起点保持；自愈判定读 `gate["card"]`。
2. 新增 `_start_pending_local_hand_gain_flights()`（单张 + 批次统一入口）与 `_finish_local_hand_gain_holds(uids)`；`_release_local_hand_gain_flight_gates()` 解闸后调用落位收尾而不是右侧滑入。
3. `is_local_gain` 分支：先查 `take_over_active_card()`，未命中才新建飞行牌面；不再写 `_pending_local_hand_gain_uids`；不再立即起飞。
4. `_on_draw_presentation_batch_finished()`：本机批次登记待起飞而不立即播放；其他玩家分支不变。
5. `_render_local_hand()`：在 `layout_cards_now()` 之后调用 `_start_pending_local_hand_gain_flights()`（替代原来对真实获得牌的 `_start_pending_local_hand_gain_animations()` 依赖）。
6. 清理路径：`_cancel_local_hand_gain_animation()` / `_clear_local_hand_gain_animations()` 一并清空待起飞批次并释放未起飞的飞行牌面。
- 验证：`ui_layout_test`、`draw_sequence_test`、`virtual_hand_choice_test`、`gameplay_regression_test` 全绿。

### 步骤 2.6 — 虚拟手牌路径回归确认（R5/AC5）

- 确认 `_pending_local_hand_gain_uids` + `_start_local_hand_gain_animation()` 只被虚拟候选/回归使用，右侧入场行为不变。
- 验证：`virtual_hand_choice_test` PASS 且断言未改动语义。

### 步骤 2.7 — 回归测试扩展（R1/R2/R3/R4）

- `tests/ui_layout_test.gd` 新增/改写用例（见 design.md 第 6 节），覆盖：落位过渡、直飞最终槽位、批次逐张落点、取走中央展示牌。
- 验证：`ui_layout_test` PASS，输出包含新用例名。

### 步骤 2.8 — 文档与规范同步（R6）

- 改写（不是追加）已失效结论：`docs/界面与交互.md`、`docs/卡牌系统.md`、`docs/游戏机制与玩法内容.md`。
- 补充新接口与视觉规格：`docs/内容制作指南.md`（按《项目专属AGENTS.md》要求）、`.trellis/spec/ui/component-patterns.md`、`README.md`（回归测试说明）。
- 追加 `临时反馈文档.md`：时间戳 + 学习反馈摘要 + 分点 Git 提交描述。

## 3. 评审门（每个门都必须真实跑出结果，不接受“应该能过”）

| 门 | 命令 | 期望 |
| --- | --- | --- |
| G1 | `ui_layout_test` | `UI_LAYOUT_PASS` |
| G2 | `virtual_hand_choice_test` | `VIRTUAL_HAND_CHOICE_PASS` |
| G3 | `draw_sequence_test` | `DRAW_SEQUENCE_PASS` |
| G4 | `match_replay_test` | `MATCH_REPLAY_PASS` |
| G5 | `gameplay_regression_test` | `GAMEPLAY_REGRESSION_PASS` |
| G6 | `smoke_test` | `SMOKE_PASS` |
| G7 | 专项（`card_back_overlay`、`multi_recast`、`batch_gain_timing`、`skill_target_ui`、`font_color_audit`、`virtual_card_color`、`card_action_semantics`、`exclusive_card_and_private_placement`、`auto_management`、`android_adaptation`、`overlay_blank_close`、`pre_game_deal_gain`、`opportunity_system`、`main_menu`、`performance_and_pacing`） | 退出码 0，无 `SCRIPT ERROR` |

每个门的判定必须包含：PASS 标记 + 退出码 0 + 无 `SCRIPT ERROR`。

## 4. 自检清单

- [ ] 没有新增第二套飞行/入场接口；`play_transfer` / `play_draw_transfer_batch` / `_try_take_card_origin` / `_should_show_card_back` 仍是唯一入口。
- [ ] 每个新增变量都有独占一行的注释；没有删除/改写既有变量名与注释。
- [ ] 新增可调参数都是脚本顶部的 `@export`。
- [ ] 没有用 `visible=false` 隐藏待入场的正式手牌节点。
- [ ] 门闸的三条清理路径（离场、清场、重开）都能清掉待起飞批次与飞行牌面。
- [ ] 文档中不再残留“从右侧入场点滑入最终手牌位置”的失效结论。

## 5. 回滚点

- 步骤 2.1+2.2 完成后是一个可独立成立的提交（仅拖拽落位过渡）。
- 步骤 2.3+2.4 完成后是一个可独立成立的提交（动画层两个新能力）。
- 步骤 2.5+2.6 是主体改动；若回归失败，先回退到 2.4 的状态再定位。
- 步骤 2.7/2.8 只涉及测试与文档。

## 6. 完成标准

- 6 套基线 + 15 项专项全绿；`ui_layout_test` 新增断言覆盖 R1/R2/R3/R4。
- 文档与规范同步完成，`临时反馈文档.md` 已追加。
- 提交描述按功能点分点，每个功能点单独一行。

## 7. 执行结果（本次实现记录）

- 步骤 2.1–2.8 全部完成；21 套测试全绿（6 套基线 + 15 项专项，均含 PASS 标记、退出码 0、无 `SCRIPT ERROR`）。
- 与计划的两处偏差（均为写测试时发现，已同步回写文档与规范）：
  1. `DecadeHandContainer._layout_cards()` 的布局签名新增“待消费的拖拽释放点数量”。否则松手帧签名与拖动前完全一致，布局会被提前返回跳过，被拖牌停在鼠标位置不再回落。
  2. `_play_local_hand_gain_flight()` 的“缺少来源玩家的私有区域”守卫去掉了 `processing`：中央处理区对获得牌是公共可见来源，保留它会导致获得正在展示的【杀】时完全没有飞行，即用户报告的“原牌留在中央、手里凭空多一张”现象。
- 步骤 2.6 结论：`_pending_local_hand_gain_uids` 与 `_start_local_hand_gain_animation()` 现在只服务虚拟手牌候选与虚拟牌回归；右侧入场表现（`local_hand_gain_entry_margin`、`local_hand_gain_duration`）按原样保留，`virtual_hand_choice_test` 全绿。
- `ui_layout_test` 新增/改写断言：R1 松手落位过渡（有目标互换槽位、无目标回归原槽位）、R2 单张获得直飞最终槽位并用容器左边距与内容高度独立校验槽位、R3 两张同批牌背分别命中两个不同槽位、R4 接管中央展示牌（同一实例、队列补位、落地即落位）；并保留牌背谓词、缺失锚点不创建、弃牌队列顺序、悬停不整理、虚拟候选右侧入场等原有断言。
