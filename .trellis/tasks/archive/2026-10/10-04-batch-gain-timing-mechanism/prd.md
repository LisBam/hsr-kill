# 批量获得时机机制（cardsGainedBatchAfter）

> 前置说明：本子任务是父任务 `10-04-danheng-yinyue-and-shajin-characters` 的**前置机制**，必须先于 `10-04-shajin-character-and-skills` 的【风口】实现完成并归档。

## Goal

在核心层新增一个与既有 `cardsDiscardedBatchAfter` **完全对称**的批量获得时机 `cardsGainedBatchAfter`：一次面向规则、语义上原子的「获得牌」动作全部结算完成后派发一次，载荷携带该次动作整批获得的实体牌 UID 与张数。

用户价值：让「当你一次性获得至少两张牌时」这类内容首次可以被精确表达；后续任何「一次性获得多张」类技能都可直接订阅该时机，而无需在内容层猜测批次边界。

## 背景与动机

- 既有获得类时机只有 `gainBefore` / `gainBegin` / `gainEnd` / `gainAfter`，**恒为一张一次**，`card_uids` 恒为单元素数组，载荷**不含张数**（`scripts/core/match_controller.gd:15910-15911`）。逐张事件无法表达「这些牌」。
- 项目对「一次性多张」的唯一既有先例是**弃置**：`cardsDiscardedBatchAfter`（`scripts/core/rule_timing_catalog.gd:57-60`），由显式作用域端口 `_begin_discard_batch()` / `_end_discard_batch()` 配合「栈空则自成隐式批次」实现（`scripts/core/match_controller.gd:15795-15829,15837-15877`），已被【泛音】用于整批黑红判定（`game_data/skills/fanyin.gd:62-64,137-166`）。
- 内容层**无法**自行合成获得批次：`request_card_choice` 等选择协议只携带牌集合，不携带「是否来自同一次动作」。因此必须由核心层提供原子语义（符合 `.trellis/spec/content/index.md:28`「若涉及未收录的新机制，先完成机制开发与文档更新，再实现内容」）。

## Requirements

1. **时机名称**：新增标准时机 `cardsGainedBatchAfter`，登记进 `RuleTimingCatalog.CARD_MOVE_TIMINGS`，紧随 `cardsDiscardedBatchAfter` 之后。
2. **派发次数**：一次「获得牌」动作派发且仅派发一次；单张获得同样派发一次（与弃置批次的既有口径保持一致），张数由载荷的 `batch_size` 表达。
3. **载荷**：必须为纯可序列化数据，键固定为
   - `gain_batch_id: int`（稳定批次号，嵌套批次不与外层重号）
   - `card_uids: Array[int]`（本批实际进入手牌的实体牌 UID，按移动成功顺序）
   - `receiver_player_id: int`（获得牌的角色）
   - `reason: String`（本次动作原因）
   - `batch_size: int`（等于 `card_uids.size()`）
4. **角色参数**：`player_id == source_id == receiver_player_id`，`target_id == -1`，使 `role="player"` / `"source"` 都能收到；监听其他角色需 `role="global"`（与弃置批次、`gainAfter` 的既有约定一致）。
5. **空批次不派发**：本批没有实际牌进入手牌时不得派发事件（避免「发动了却没有牌可判定」的空事件）。
6. **覆盖面**：以下路径的获得都必须被正确归批
   - 摸牌（`MatchController.draw()` 经 `DrawResolutionService`）：**同一 `draw()` 调用内摸到的全部牌属于同一批**
   - 统一移牌管线中所有「进入手牌」的移动（`_move_card_with_timings(..., "hand", target_player_id, ...)`）：**单次调用自成一批**
   - 多张获得端口 `gain_all_hand_cards()`：**同一次调用内的全部牌属于同一批**
   - 逐张获得端口 `gain_card_to_hand_by_uid()`、`transfer_hand_card_as()`：各自单张成批
7. **批次边界正确性**：一次批次事件在其回调中连锁产生的新获得必须自成新批次，不得被并入外层批次。
8. **资源安全**：任何提前返回/取消路径都必须收敛批次作用域，不得把批次永久留在栈上吞掉后续获得。
9. **零回归**：既有 `cardsDiscardedBatchAfter` 语义、`gain*` 逐张时机、存档格式、回放协议均不得改变；新增时机只增加事件。`_gain_batch_stack` 为纯瞬态字段，**不进入存档**。
10. **时机计数同步**：`tests/rule_timing_test.gd:133-136` 的分类计数断言与注释必须同步（`CARD_MOVE_TIMINGS` 37 → 38，合计 236 → 237）。
11. **文档同步**：`docs/内容制作指南.md`（时机分类表、批次时机语义）、`docs/游戏机制与玩法内容.md`（机制口径与全部数值）、`docs/架构说明.md`（职责归属）必须同步；新增专项测试。

## 非目标（本子任务不做）

- 不重构、不改名、不改变既有 `cardsDiscardedBatchAfter` 的任何语义与载荷。
- 不新增公共内容端口（内容侧只订阅新时机，不需要 `begin/end` 端口）。
- 不新增 `gainBatchBefore` 等前置窗口。
- 不为获得批次引入网络专用协议（沿用既有 RuleEvent 广播链路）。
- 不改动 `PlayerState` 的任何字段或序列化。

## Acceptance Criteria

- [ ] `RuleTimingCatalog.has_timing("cardsGainedBatchAfter")` 为 `true`，且该名紧随 `cardsDiscardedBatchAfter`。
- [ ] `tests/rule_timing_test.gd` 的分类计数为 `[58,48,16,35,38,10,14,8,4,6]`（合计 237）且通过。
- [ ] 一次 `draw(player_id, 2)` 只派发 1 次 `cardsGainedBatchAfter`，`batch_size == 2`、`card_uids` 为那两张实体牌、`receiver_player_id` 为该角色。
- [ ] 一次 `draw(player_id, 1)` 派发 1 次，`batch_size == 1`。
- [ ] `gain_all_hand_cards()` 获得 N 张时只派发 1 次，`batch_size == N`。
- [ ] 连续两次独立获得（例如两次单张 `gain_card_to_hand_by_uid`）派发 2 次，各自 `batch_size == 1`，`gain_batch_id` 不同。
- [ ] 在被取消/无效目标/牌堆为空的路径上不产生空批次事件，且批次栈回到空。
- [ ] 在 `cardsGainedBatchAfter` 回调内再造成一次获得，新获得自成新批次，外层 `batch_size` 不被污染。
- [ ] 既有获得类时机（`gainAfter` 等）的事件数量、载荷与顺序**逐字不变**。
- [ ] `tests/rule_timing_test`、既有战斗/卡牌/技能测试全绿；`GameDatabase.validation_errors` 为空。
- [ ] 上述三份文档已同步，且新时机的语义、载荷与数值在文档中可追溯。

## 备注

- 阶段划分与验证命令见 `implement.md`；技术设计（数据结构、插入点、边界处理）见 `design.md`。
