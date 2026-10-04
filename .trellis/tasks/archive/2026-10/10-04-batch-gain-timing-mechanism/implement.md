# 执行计划 · 批量获得时机机制（cardsGainedBatchAfter）

> 需求见 `prd.md`，技术设计见 `design.md`。本文件只描述**执行顺序、验证方式与门禁**。

## 执行前置

- 必须已读：`.trellis/spec/core/index.md`（核心层规范）、`.trellis/spec/core/rule-timing.md`（若存在）、`.trellis/spec/content/rule-timing-usage.md`（若存在）。
- 先跑一次基线，确认**改动前**即为绿色，否则无法区分回归与新引入问题：
  - `tests/rule_timing_test.tscn`
  - `tests/draw_sequence_test.tscn`
  - `tests/card_timing_sequence_test.tscn`
  - `tests/event_runtime_test.tscn`
  - `tests/haiseyin_mechanics_test.tscn`（既有弃置批次的唯一使用者，是「批次机制没被弄坏」的关键回归）

  执行方式：优先用 godot-ai MCP 的 `test_run`（可用 `suite`/`test_name` 过滤）；或直接运行对应 `res://tests/*.tscn` 场景。

---

## 阶段 1 · 登记时机与字段（最小可编译增量）

1. `scripts/core/rule_timing_catalog.gd`
   - 在 `CARD_MOVE_TIMINGS` 中 `"cardsDiscardedBatchAfter"` 之后插入 `"cardsGainedBatchAfter"`。
   - 补一条与弃置同风格的中文注释，说明载荷 `card_uids` 为整批牌、供「一次性获得多张」类技能整批判定。
2. `scripts/core/match_controller.gd`
   - 在 `_discard_batch_stack` / `_next_discard_batch_id`（`:573`、`:576`）旁新增 `_gain_batch_stack` 与 `_next_gain_batch_id`，按项目规范为**每个变量**写独占一行注释。
3. `tests/rule_timing_test.gd:133-134`
   - 期望值改为 `[58,48,16,35,38,10,14,8,4,6]`，并更新注释中的合计（236 → 237）与新增说明。

**验证**：`tests/rule_timing_test.tscn` 通过。
**门禁**：时机名拼写、插入位置、注释风格。

## 阶段 2 · 三个批次函数

在 `_end_discard_batch()` 之后（`match_controller.gd:15830` 附近）新增 `_begin_gain_batch()` / `_register_gain_into_batch()` / `_end_gain_batch()`，签名与行为严格按 `design.md` §3.2，且注释需说明「为什么批量入口要无条件开栈」「为什么先弹栈再派发」「为什么空批次不派发」。

**验证**：`tests/rule_timing_test.tscn` + 编辑器无脚本错误（检查 `editor_manage(op="logs_read", source="editor")`）。
**门禁**：三个函数只做批次作用域与事件派发，不得改动牌区、不得写日志。

## 阶段 3 · 接入统一移牌管线

按 `design.md` §3.3 A 修改 `_move_card_with_timings()`：

1. 三处早期 `return null` **之后**计算 `counts_as_gain_action` / `owns_gain_batch` 并开隐式批次。
2. `before` 与 `begin` 两个取消分支在 `return null` 前先 `_end_gain_batch()`。
3. 全部后置时机派发完成后登记 `card.uid`，并在 `owns_gain_batch` 时收尾。

**验证**：
- `tests/draw_sequence_test.tscn`
- `tests/card_timing_sequence_test.tscn`
- `tests/gameplay_regression_test.tscn`
- 手工冒烟：单张 `gain_card_to_hand_by_uid` → 1 次批次事件；`before` 取消 → 0 次且栈空。

**门禁**：`gainBefore/gainBegin/gainEnd/gainAfter` 的事件顺序与载荷**逐字未变**（用现有测试的事件断言核对）。

## 阶段 4 · 接入摸牌通道

按 `design.md` §3.3 B 修改 `scripts/core/draw_resolution_service.gd`：`_prepare_batch` 开批次并置 `gain_batch_started`；`_draw_card_commit` 登记；`_finish_batch` 幂等收尾。

**验证**：
- `tests/draw_sequence_test.tscn`（重点：牌堆耗尽路径只关闭一次、取消路径不产生空批次）
- 手工冒烟：`draw(p,2)` → 1 次 `batch_size==2`；`draw(p,1)` → 1 次 `batch_size==1`。

**门禁**：`drawEnd` / `drawAfter` 载荷不变；`cardsGainedBatchAfter` 出现在 `drawAfter` **之后**。

## 阶段 5 · 接入多张获得入口

按 `design.md` §3.3 C 修改 `gain_all_hand_cards()`、`gain_group_cards_from_draw_or_discard()`、`gain_same_name_length_cards_from_draw_or_discard()`：判空后无条件开栈、单一收尾点、`break`/提前 `return` 路径也要收尾。

**验证**：手工冒烟 `gain_all_hand_cards` → 1 次 `batch_size == 实际张数`；无牌可动时 → 0 次事件且栈空。
**门禁**：这三个端口的返回值与日志文案不变。

## 阶段 6 · 执行 §3.3 D 的路径审计

重新 grep 一遍全部移入手牌的移牌点（`move_card(` 的 `to_zone`、`_move_card_with_timings(` 的第二参数为 `"hand"`），逐条与 `design.md` §3.3 D 的表对照：**新增路径必须补进表并给出归批结论**；结论为「归批」的必须补实现。

**门禁**：审计表与代码一致；无遗漏路径。

## 阶段 7 · 专项测试

新增 `tests/batch_gain_timing_test.gd` + `tests/batch_gain_timing_test.tscn`（沿用 `tests/` 既有测试宿主与 `support/` 辅助风格），覆盖 `design.md` §6 的 9 条断言。

**验证**：`tests/batch_gain_timing_test.tscn` 全绿。
**门禁**：测试不得依赖图形界面；随机相关逻辑走权威端口。

## 阶段 8 · 文档同步

| 文档 | 同步内容 |
|---|---|
| `docs/内容制作指南.md` | 时机分类表中的「牌移动与区域变化」条目数与名称（37 → 38，新增 `cardsGainedBatchAfter`）；批次时机语义小节（与 `cardsDiscardedBatchAfter` 并列，含载荷字段表与「单张也派发一次」的口径）；总时机数 236 → 237 |
| `docs/游戏机制与玩法内容.md` | 新机制口径：什么是「一次性获得多张」、批次边界规则、载荷数值（`batch_size`、`card_uids`、`gain_batch_id`、`receiver_player_id`、`reason`）、哪些路径归批/不归批 |
| `docs/架构说明.md` | 批量获得与批量弃置同属核心层批次语义，派发归属 `MatchController`；摸牌通道由 `DrawResolutionService` 登记 |

**注意**：`docs/内容制作指南.md:2526` 附近的「牌移动与区域变化（36个）」与 `:2323` 关于【无懈可击】的表述已是**既有文档缺陷**（实际为 37 个；【无懈可击】走 `useCard` 而非 `respond`）。本次只需保证新增项正确；若顺手修正既有偏差，必须在提交描述中单列一条。

## 阶段 9 · 全量回归与收尾

1. 跑一遍与本次改动相关的全部测试场景：`rule_timing`、`draw_sequence`、`card_timing_sequence`、`event_runtime`、`gameplay_regression`、`haiseyin_mechanics`、`batch_gain_timing`、`ai_policy`。
2. 在编辑器内开局冒烟：确认无脚本错误、`GameDatabase.validation_errors` 为空。
3. 按项目规范输出「学习反馈摘要」+ 编号 Git 提交描述，并追加到 `临时反馈文档.md`（带时间戳）。

---

## 回滚点

| 回滚点 | 方式 |
|---|---|
| 阶段 1 之后 | 撤销时机名与两个字段、恢复测试期望值（本次改动尚不可见） |
| 阶段 3–5 之后 | 保留时机名与函数，撤销三处接入 → 时机永不派发，对既有内容零影响 |
| 全部完成后 | 需整体回滚时按 `design.md` §5：无数据迁移，撤销代码即可 |

## 完成定义（DoD）

- `prd.md` 的全部验收标准勾选完成。
- 阶段 6 的审计表已复核，无未分类的移牌入手指路径。
- 文档三处已同步，且 `docs/游戏机制与玩法内容.md` 记录了本机制的全部数值。
- 学习反馈与 Git 提交描述已追加到 `临时反馈文档.md`。
