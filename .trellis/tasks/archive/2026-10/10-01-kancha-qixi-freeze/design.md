# 技术设计：额外出牌节点下堪杀触发奇袭的结算丢失

## 1. 复现与实测结论

复现脚本按真实入口驱动：`mice.call("_on_phase_end", ...)` → 提交 `mice_target_option`（选“play_phase”）→ `_active_independent_play_phase.player_id == 1` → `_begin_play_choice(1)` → `get_legal_actions(1)` 提交 `kansha` 动作 → 提交后续 `kansha_discard` / `kansha_damage` → `end_current_play_phase(1)`。

实测（三种轮回节 × {直接动作, AI 正式驱动} 六组场景，`wooden_ox`/状态均为最小构造）：

| 观察点 | 结果 |
| --- | --- |
| 堪杀①/②/③后 `_deferred_skill_settlements.size()` | 恒为 1（技能持有者1、技能 `qixi`） |
| 让出 12 帧后 | **仍为 1**；`_settlement_resume_scheduled == false`、`_settlement_pipeline_running == false`、`_rule_sequence_execution_depth == 0`、`_rule_continuations` 为空、无待选请求、`game_flow_pacer.has_pending_skill_interval() == false` |
| 手工调用一次 `_resume_settlement_pipeline()` | 立刻排空（1 → 0），`qixi` 的“进入下一个轮回节”真实生效（轮回节 1→2、2→0） |
| 堪杀③（伤害节） | `deferred` 自然变 0（伤害创建了规则序列，管线在当次调用内被重新驱动） |

结论：**奇袭的“然后”步骤被登记后，唯一唤醒者在“入口作废旧唤醒 + 当次同步排空因门控提前返回”的组合中丢失，队列永久滞留。** 这不是评分问题，也不是奇袭/堪杀自身的问题，而是统一结算管线的活跃性缺陷。

## 2. 根因

`scripts/core/match_controller.gd`：

- `defer_skill_settlement()`（第11520-11574行）在末尾按条件登记延后唤醒：`if not _settlement_pipeline_running and not has_pending_card_choice(): _schedule_settlement_pipeline_resume()`。
  → **当登记发生在一次正在执行的管线内部时，它明确不登记唤醒**，把唤醒责任交给“当前这一轮 while 循环自然会取到新增项”。
- `_resume_settlement_pipeline()`（第11930行起）在进入同步排空前先调用 `_invalidate_scheduled_settlement_resume()`，即**先取消已有唤醒，再尝试排空**，并假设这次同步排空一定能把队列走完。
- 实际存在多条“当次排空不能走完且不重登记唤醒”的路径：
  - `_run_settlement_pipeline_pass()` 的 `_top_sequence_waits_for_child_phase()` 门控直接 `return`（第11974行）——独立额外出牌阶段/额外弃牌阶段正在作为子阶段运行，父序列必须等待；
  - 待选请求 `has_pending_card_choice()`、待判定 `has_pending_judgment_request()`、流程节奏器的技能间隔门控同样直接返回。

组合结果：奇袭在堪杀激活过程中登记延后结算（此时管线在跑，不登记唤醒）→ 某处调用 `_resume_settlement_pipeline()` 先作废旧唤醒 → 这次排空命中子阶段门控直接返回 → 没有任何人再登记唤醒 → 队列滞留。

## 3. 修复方案（通用层，不针对具体技能）

在统一结算管线上补一条**活跃性保证**，语义为：“只要队列中仍有明确待办，且阻塞原因不是‘等待外部输入’，就一定有唤醒者。”

1. 新增私有判定 `_has_unresolved_settlement_work() -> bool`：
   - `state == null or state.game_over` → false；
   - `has_pending_card_choice() or has_pending_judgment_request()` → false（这两类各自拥有明确的响应恢复入口，会重新驱动管线，不需要轮询唤醒）；
   - 否则返回 `not _deferred_skill_settlements.is_empty() or _rule_continuations.has_pending() or not _queued_equipment_triggers.is_empty() or (trigger_manager != null and trigger_manager.has_deferred_dispatches())`。
2. 在 `_resume_settlement_pipeline()` 的同步排空结束处（`_settlement_pipeline_running = false` 之后）追加：
   ```gdscript
   if _has_unresolved_settlement_work():
       _schedule_settlement_pipeline_resume()
   ```
3. 顺带修正 `defer_skill_settlement()` 的注释，说明“管线内登记不等于必然被当次循环消费”，把活跃性责任明确交给上面的补齐逻辑；不改动其原有调度条件以外的最小行为（保留 `not _settlement_pipeline_running` 判断以减少同帧重复唤醒）。

### 为什么这样能解决问题

- 旧唤醒被作废后，若本次排空没有真正清空队列，第2步立即重新登记一个跨帧唤醒；下一帧它再跑一次，直到门控真正解除（子阶段结束、选择被回答）后自然排空。
- 门控期间每帧只多一次“判定 + 立即返回”的空跑，代价可忽略；而“永远不再被唤醒”的永久滞留被结构性消除。
- 不动子阶段门控语义，结算顺序不变。

### 风险与对策

- 风险：正常等待人类输入时也可能每帧空跑。对策：`has_pending_card_choice()` / `has_pending_judgment_request()` 显式排除，等待输入期间不登记唤醒。
- 风险：与 `_run_scheduled_settlement_pipeline_resume()` 的 `_pending_conquest_boundary_player_id` 逻辑互相触发。对策：该入口在排空后按原有分支处理边界，新增的重新登记沿用同一唯一性守卫（`_settlement_resume_scheduled`），不会产生多条连接。

## 4. 验证设计

把临时复现脚本转成正式回归（放进既有 `tests/new_character_mechanics_test.gd` 或新建专项测试场景），断言：

1. 六组场景中 `_deferred_skill_settlements` 在让出若干帧后为空；
2. 奇袭的“进入下一个轮回节”真实生效（轮回节索引按规则变化）；
3. 额外出牌阶段结束后 `_active_independent_play_phase` 为空、控制权回到秘策持有者的结束阶段、`_rule_sequences` 收敛；
4. 既有秘策两种阶段顺序与堪杀/奇袭断言不回归。

临时脚本 `tests/_repro_kancha_qixi.gd` / `.tscn` 在测试落地后删除。
