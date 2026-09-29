# 多张重铸机制 — 执行计划

> 设计见同目录 `design.md`；需求与验收见 `prd.md`。

---

## 一、实施顺序

### 步骤 1：读消费端，确认续接契约
1. 定位 `_defer_rule_continuation("recast_draw", ...)` 的消费点，确认补摸张数是写死 `1` 还是读 `context["count"]`。
2. 若写死 `1`，改为 `int(context.get("count", 1))`——默认值 `1` 保证历史上下文与单张路径行为不变。

### 步骤 2：提炼共享路径并新增端口
3. 新增私有 `_recast_cards_common(player_id, card_uids, single_card_log) -> int`。
4. `recast_hand_card(player_id, card_uid) -> bool` 改为委托（保持签名与返回值）。
5. 新增公开 `recast_hand_cards(player_id, card_uids) -> int`。

**验证点**：单张路径的日志文本、返回值、补摸行为逐字不变。

### 步骤 3：专项测试
6. 新建 `tests/multi_recast_test.gd` + `.tscn`。
7. `README.md`「自动校验」章节补一行。

---

## 二、验证命令

```powershell
$GODOT = 'E:\Godot\Godot_v4.6.1-stable_mono_win64\Godot_v4.6.1-stable_mono_win64_console.exe'

# 本子任务专项
& $GODOT --headless --path . res://tests/multi_recast_test.tscn
# 单张重铸的语义守门测试（必须 PASS，证明零回归）
& $GODOT --headless --path . res://tests/card_action_semantics_test.tscn
& $GODOT --headless --path . res://tests/gameplay_regression_test.tscn
# 既有技能重铸路径（【星落】【解构】【弦奏】【领航】）
& $GODOT --headless --path . res://tests/daheita_mechanics_test.tscn
& $GODOT --headless --path . res://tests/leader_skill_test.tscn
& $GODOT --headless --path . res://tests/new_character_mechanics_test.tscn
& $GODOT --headless --path . res://tests/phase_progression_test.tscn
```

---

## 三、风险文件与回滚点

| 文件 | 风险等级 | 回滚方式 |
|---|---|---|
| `scripts/core/match_controller.gd`（重铸段） | **高**（4 个既有技能与 3 个测试依赖单张路径） | 还原 `recast_hand_card` 原实现，删除新端口与私有辅助 |

**回滚触发条件**：`card_action_semantics_test` 或 `gameplay_regression_test` 失败（说明单张语义被改动）。

---

## 四、`task.py start` 前复查

- [ ] 已读 `recast_draw` 续接消费端，`count` 键契约确认无冲突
- [ ] `prd.md` / `design.md` / `implement.md` 无 TBD
- [ ] 与子任务③的接口约定已对齐（`recast_hand_cards(player_id, card_uids) -> int` 签名不再变动）
