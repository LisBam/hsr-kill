# 执行计划：优化卡牌交互动画连续性

## 0. 前置

- 权威设计见 `design.md`；需求与验收见 `prd.md`。
- Godot 可执行文件（本机）：`E:\Godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64.exe`
- 测试即场景，逐个进程顺序执行，不要并发（会争用 `.godot` 缓存与本机用户设置）。
- 基线先跑一次，确认改动前就是 PASS，避免把既有失败算到本次头上。

## 1. 基线验证

```powershell
$godot = "E:\Godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64.exe"
& $godot --headless --path . res://tests/ui_layout_test.tscn
& $godot --headless --path . res://tests/virtual_hand_choice_test.tscn
& $godot --headless --path . res://tests/match_replay_test.tscn
```

- [ ] 1.1 记录基线输出（PASS 标记、退出码）。若基线已失败，先向用户报告并暂停。

## 2. 实现顺序（自底向上，每步可独立验证）

### 步骤 2.1 — `CardView.hand_layout_offset`（无依赖）

- [ ] 在 `hand_selection_offset` 之后新增 `hand_layout_offset`，注释写明用途、取值含义、默认值理由、由谁写入。
- [ ] 保持 `hand_entry_offset` / `hand_selection_offset` 的代码与注释**完全不动**。

验证：`ui_layout_test.tscn` 仍 PASS（此时新属性无人使用）。

### 步骤 2.2 — `DecadeHandContainer` 槽位过渡

- [ ] 新增 `relayout_animation_seconds` 导出参数（带完整注释）。
- [ ] 新增 `_slot_positions` / `_relayout_tweens` 两个私有状态（带注释）。
- [ ] `_layout_cards()` 按 `design.md §3.8` 改造写入段：槽位不含悬停补偿、新牌与拖动牌跳过、槽位变化时累加残留并重建补间。
- [ ] 空手牌早退分支与布局结束处清理已离场实例的槽位记录与补间。
- [ ] `_exit_tree()` 终止全部残留补间。
- [ ] 保持结构签名命中时的零开销 `return`。

验证：`ui_layout_test.tscn` PASS；手牌相关既有断言（落点、顺序）不变。

### 步骤 2.3 — `EquipmentStackView.find_card_global_rect()`

- [ ] 新增只读查询，复用 `EQUIPMENT_SLOT_ORDER` / `_equipment` / `_rows_by_slot`，返回 `{"valid":bool, "rect":Rect2}`。
- [ ] 不修改 `configure()`、`_layout_rows()` 或任何既有行为。

验证：`ui_layout_test.tscn` PASS（装备槽位断言不变）。

### 步骤 2.4 — `CardUseAnimationLayer` 落地回调

- [ ] `play_transfer()` 新增可选 `on_flight_finished: Callable = Callable()`；把单条补间拆成飞行 + 停留/淡出两条，落地处（代次校验后）调用回调一次。
- [ ] `play_draw_transfer_batch()` 新增同名可选参数并透传给 `_play_draw_transfer_batch()`；在飞行补间结束、代次校验之后调用一次。
- [ ] 不传回调时两条补间的顺序、总时长、视觉与改造前完全一致；`_transfer_tweens` / `_draw_transfer_batch_tweens` 的登记方式保持可被 `clear_presentations()` 整体终止。

验证：`ui_layout_test.tscn`（含既有同批弃牌顺序与转移断言）PASS；`smoke_test.tscn` PASS。

### 步骤 2.5 — `MatchTable` 唯一来源解析与牌背判定

- [ ] 新增 `_try_take_card_origin(card_uid, source_player_id, source_zone) -> Dictionary`，实现 `design.md §3.4` 的四级解析与接管前收尾。
- [ ] 新增 `_should_show_card_back(source_player_id, source_zone, target_player_id, target_zone) -> bool`，把 `:4751` 的内联表达式整体搬入。
- [ ] `_on_card_transfer_requested()` 的弃牌分支与转移分支改用这两个入口；命中活跃手牌节点时直接把该节点交给 `play_card()` / `play_transfer()`。
- [ ] `_on_card_presentation_requested()` 的新建副本按更精确的来源矩形摆放；**目标指示线锚点保持原样**。
- [ ] 不改动去重/认领、处理区早退、目标区域边界的任何顺序。

验证：新增断言（步骤 2.8 的第 4/5/6 项）通过。

### 步骤 2.6 — `MatchTable` 本机手牌入场门闸

- [ ] 新增 `_local_hand_gain_flight_gates` 状态与 `_play_local_hand_gain_flight()` / `_finish_local_hand_gain_flight()` / `_hold_gated_local_hand_entries()` 三个函数（合计不超过三个新私有函数）。
- [ ] `_start_pending_local_hand_gain_animations()` 增加「门闸存在则保留 UID 并跳过」的早退。
- [ ] `_render_local_hand()` 在 `layout_cards_now()` 之后插入 `_hold_gated_local_hand_entries()`；快照中不再出现的 UID 同时清除门闸。
- [ ] `_clear_local_hand_gain_animations()` 清空门闸。
- [ ] `is_local_gain` 分支改为：登记待入场 → `_play_local_hand_gain_flight()` → 启动一次入场。

验证：新增断言（步骤 2.8 的第 1/3 项）通过。

### 步骤 2.7 — `MatchTable` 真实摸牌批次登记

- [ ] `_on_draw_presentation_batch_finished()`：目标为本机时，为每个摸到的 UID 登记待入场并加门闸，再调用批次播放并传入落地回调统一解除门闸。
- [ ] 其他玩家分支与空批次早退保持原样。

验证：新增断言（步骤 2.8 第 3 项）通过；`draw_sequence_test.tscn` PASS。

### 步骤 2.8 — 回归测试扩展（`tests/ui_layout_test.gd`）

- [ ] 第 1 项：改造既有 `local_gain_entity` 断言（`ui_layout_test.gd:1172-1205`）——转移后动画层持有 1 张飞行牌；手牌节点被门闸固定在右侧入场点且无入场补间；等待后飞行牌释放、偏移归零。
- [ ] 第 2 项：既有 `local_draw_entity` 断言（非批次摸牌）保持语义：无前置飞行、立即滑入。
- [ ] 第 3 项：新增批次摸牌断言——本机 UID 登记待入场并处于门闸，落地回调后滑入。
- [ ] 第 4 项：新增弃置本机手牌断言——节点父节点变为动画层、属于 `_active_cards`、全局位置等于记录的原始槽位位置。
- [ ] 第 5 项：新增弃置本机装备断言——飞行牌起点等于该装备槽矩形中心。
- [ ] 第 6 项：新增展示本机手牌断言——展示牌面起点等于该手牌原位置矩形中心。
- [ ] 第 7 项：新增手牌整理过渡断言——离场后存活手牌 `hand_layout_offset` 非零，过渡后归零且位置与纯布局结果一致。
- [ ] 第 8 项：新增悬停不触发整理断言。
- [ ] 全部异步断言使用条件等待 + 兜底超时；失败信息带上实际观测值。

### 步骤 2.9 — 文档同步

- [ ] `docs/游戏机制与玩法内容.md`：改写第 983 条；补充离场原位起飞与手牌整理过渡（含 `0.18` 秒数值与「悬停不触发过渡」口径）。
- [ ] `docs/界面与交互.md`：同步手牌区/动画表现描述。
- [ ] `docs/内容制作指南.md`：新增可复用接口条目（来源解析、牌背判定、落地回调参数、`hand_layout_offset`、`find_card_global_rect`）。
- [ ] `README.md`：更新 `ui_layout_test.tscn` 覆盖说明。
- [ ] `.trellis/spec/ui/component-patterns.md`：视觉规格表新增「手牌整理过渡 0.18 秒」；常见错误表新增两条反模式。
- [ ] `临时反馈文档.md`：追加学习反馈摘要与 Git 提交描述（带时间戳）。

## 3. 评审门（每个门都必须真实跑出结果，不接受"应该能过"）

| 门 | 命令 | 通过标准 |
|---|---|---|
| G1 界面布局与动画 | `res://tests/ui_layout_test.tscn` | 退出码 0 + 自身 PASS + 日志无 `ERROR`/`SCRIPT ERROR`/`FAIL` |
| G2 虚拟手牌 | `res://tests/virtual_hand_choice_test.tscn` | 同上（该用例依赖 `hand_entry_offset`） |
| G3 回放重演 | `res://tests/match_replay_test.tscn` | 同上（转移与批次表现被重演） |
| G4 摸牌批次 | `res://tests/draw_sequence_test.tscn` | 同上 |
| G5 规则回归 | `res://tests/gameplay_regression_test.tscn` | 同上（确认纯表现改动未动规则时序） |
| G6 整体烟雾 | `res://tests/smoke_test.tscn` | 同上 |
| G7 字体色审计 | `res://tests/font_color_audit_test.tscn` | 仅当新增了文本控件时必跑；本次预期无新增文本，仍跑一次兜底 |

## 4. 自检清单

- [ ] 全项目搜索确认「来源位置解析」只有一个入口；`_get_player_indicator_position()` 语义未被改动。
- [ ] 全项目搜索确认「牌背判定」只有一个入口。
- [ ] `CardUseAnimationLayer` 没有新增播放函数，只给既有三个播放接口中的两个加了同一个可选回调参数。
- [ ] `hand_entry_offset` / `hand_selection_offset` 的既有代码与注释未被改名或删除，只新增 `hand_layout_offset`。
- [ ] 规则层（`scripts/core/`）、内容层（`game_data/`）、网络层（`scripts/network/`）、AI 层无任何改动。
- [ ] 所有新增变量都有独占一行注释，说明作用、取值、默认值理由。
- [ ] 新增可调参数只有 `relayout_animation_seconds` 一个，且为 `@export`。

## 5. 回滚点

| 回滚点 | 范围 | 方式 |
|---|---|---|
| R1（步骤 2.1–2.3） | 手牌偏移 + 容器过渡 + 装备槽查询 | 单独提交，可独立回退；回退后手牌恢复瞬间跳位 |
| R2（步骤 2.4–2.6） | 落地回调 + 来源解析 + 入场门闸 | 单独提交；回退后恢复「牌消失再从锚点冒出」的旧表现 |
| R3（步骤 2.7） | 真实摸牌批次登记 | 单独提交；回退后真实对局摸牌恢复直接进入手牌区 |
| R4（步骤 2.8–2.9） | 测试与文档 | 必须与对应实现同批提交，不允许只回退实现留下过期断言 |

## 6. 完成标准

- 第 3 节 G1–G6 全部真实 PASS 并附实际输出。
- 第 4 节自检清单全部勾选。
- `prd.md` 的 AC1–AC11 全部可追溯地满足或明确记录偏差原因。
- 文档同步清单（`design.md §8`）全部完成。
