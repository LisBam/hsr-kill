# 技术设计 · 批量获得时机机制（cardsGainedBatchAfter）

> 本文件只描述**技术设计**：边界、契约、数据结构、插入点、边界处理与兼容性。需求与验收标准见 `prd.md`。

## 1. 设计与既有机制的关系

本机制**逐条镜像**既有弃置批次，减少认知负担并让两者可被同一套心智模型理解：

| 维度 | 既有弃置批次 | 新增获得批次 |
|---|---|---|
| 时机名 | `cardsDiscardedBatchAfter` | `cardsGainedBatchAfter` |
| 作用域栈 | `_discard_batch_stack` | `_gain_batch_stack` |
| 批次号源 | `_next_discard_batch_id` | `_next_gain_batch_id` |
| 开栈 | `_begin_discard_batch(player_id, reason) -> int` | `_begin_gain_batch(player_id, reason) -> int` |
| 收栈并派发 | `_end_discard_batch()` | `_end_gain_batch()` |
| 逐张登记 | `_move_to_discard()` 内联 `batch_card_uids.append(card.uid)` | `_register_gain_into_batch(card_uid)` |
| 隐式单张批次 | 栈空时 `owns_batch = true` | 栈空时 `owns_gain_batch = true` |
| 主体角色 | `source_player_id`（弃牌方） | `receiver_player_id`（获得方） |
| 空批次 | 不派发 | 不派发 |

**刻意的不对称**：弃置的登记点在 `_move_to_discard()` 内联完成，因为所有弃置都汇聚到该函数；而获得的登记点有**两条**通道（统一移牌管线 + 摸牌服务），因此抽出 `_register_gain_into_batch()` 作为唯一登记入口，避免两处重复实现。

## 2. 数据结构

新增两个控制器瞬态字段，紧邻既有弃置批次字段（`scripts/core/match_controller.gd:571-576`）：

```gdscript
## 当前批量获得作用域栈；栈顶为本批已成功进入手牌的实体牌UID。
## 与 _discard_batch_stack 对称：栈空表示当前没有批量入口，此时单张获得自成隐式批次。
var _gain_batch_stack: Array[Dictionary] = []

## 下一个批量获得批次号；自增保证嵌套批次不与外层重号。
var _next_gain_batch_id: int = 1
```

栈元素结构与弃置完全一致：

```gdscript
{
    "batch_id": int,     # 稳定批次号
    "player_id": int,    # 获得牌的角色
    "reason": String,    # 本次动作原因
    "card_uids": Array,  # 本批实际进入手牌的实体牌UID，按成功顺序
}
```

**不进入存档**：与 `_discard_batch_stack` 一样是纯瞬态字段，`GameState.to_dict()` 不含它，因此存档格式**零变化**。

## 3. 契约

### 3.1 时机目录

`scripts/core/rule_timing_catalog.gd:57-60` 的 `CARD_MOVE_TIMINGS` 中，在 `"cardsDiscardedBatchAfter"` 之后插入 `"cardsGainedBatchAfter"`，并补一条与弃置同风格的中文说明注释：载荷 `card_uids` 为整批牌，供「当你一次性获得多张牌时」类技能按一次动作整批判定。

顺序要求：必须紧随 `cardsDiscardedBatchAfter`，让两个批次时机在目录中相邻，便于阅读与检索。

### 3.2 三个新增控制器函数

```gdscript
## 开启一次获得批次；批量获得入口在循环外层调用，使整批牌共享同一个 cardsGainedBatchAfter 事件。
## 批量入口必须无条件调用本函数（即使外层已有批次），嵌套获得才能各自成批而不把内层牌计入外层。
## 返回稳定批次号；调用方必须保证随后调用 _end_gain_batch() 收尾，包括提前跳出循环的路径。
func _begin_gain_batch(player_id: int, reason: String) -> int


## 把一张已成功进入手牌的实体登记到栈顶获得批次；当前不在任何批次内时不做任何事。
func _register_gain_into_batch(card_uid: int) -> void


## 结束栈顶获得批次；先弹出再派发，使批次事件内由技能连锁产生的新获得动作自成新批次。
func _end_gain_batch() -> void
```

`_end_gain_batch()` 的派发（先 `pop_back()` 再 `_emit_rule_timing`，与弃置同构）：

```gdscript
	var finished_batch: Dictionary = _gain_batch_stack.pop_back()
	var batch_card_uids: Array = finished_batch.get("card_uids", []) as Array
	if batch_card_uids.is_empty():
		return
	var batch_player_id: int = int(finished_batch.get("player_id", -1))
	_emit_rule_timing("cardsGainedBatchAfter", batch_player_id, batch_player_id, -1, {
		"gain_batch_id": int(finished_batch.get("batch_id", -1)),
		"card_uids": batch_card_uids.duplicate(),
		"receiver_player_id": batch_player_id,
		"reason": str(finished_batch.get("reason", "")),
		"batch_size": batch_card_uids.size(),
	}, state.current_event_id)
```

要点：
- `player_id == source_id == receiver_player_id`，`target_id == -1`。因此 `role="player"` / `"source"` 都能收到，`role="global"` 用于监听他人（与 `gainAfter`、`cardsDiscardedBatchAfter` 的既有约定一致）。
- 先弹栈再派发，使批次事件回调内连锁产生的新获得自成新批次（与 `_end_discard_batch()` 的既有注释一致）。
- 空批次直接 `return`（不派发）。**注意**：`_end_gain_batch()` 在栈空时必须直接 `return`（与弃置同构的防御）。

### 3.3 插入点（逐点）

#### A. 统一移牌管线 —— `MatchController._move_card_with_timings()`（`match_controller.gd:15881-15975`）

这是所有**非摸牌**获得进手牌的汇聚点（`to_zone == "hand"`）。

1. 在既有持久区域校验的**三处提前 `return null`（`:15893`、`:15896`、`:15898`）之后**、`lifecycle_names` 计算之前，插入：

```gdscript
	# 本次移动是否构成一次“获得牌”动作；只有进入玩家手牌区才参与获得批次。
	var counts_as_gain_action: bool = to_zone == "hand" and target_player_id >= 0
	# 本次获得是否自成一个批次；栈非空表示外层批量入口已经建立了更大的批次，此时只把本张计入该批次。
	var owns_gain_batch: bool = counts_as_gain_action and _gain_batch_stack.is_empty()
	if owns_gain_batch:
		_begin_gain_batch(target_player_id, reason)
```

2. 既有 `before` 窗口取消分支（`:15938-15939`）与 `begin` 窗口取消分支（`:15946-15947`）必须在 `return null` 之前收敛隐式批次，否则空批次会永久留在栈上吞掉后续获得：

```gdscript
			if before_event != null and (before_event.cancelled or before_event.neutralized):
				if owns_gain_batch:
					_end_gain_batch()
				return null
```

（`begin` 分支同样处理。`_end_gain_batch()` 在批内无牌时不派发，因此取消路径不会产生空事件。）

3. 在全部生命周期后置时机派发完成后、`return move` 之前，插入登记与隐式收尾：

```gdscript
	# 获得批次登记；本次移动成功进入手牌后按顺序登记，隐式批次同样登记，使单张获得也产生一次批次事件。
	if counts_as_gain_action:
		_register_gain_into_batch(card.uid)
		if owns_gain_batch:
			_end_gain_batch()
```

事件顺序因此固定为 `… → gainAfter → cardsGainedBatchAfter`，与弃置的 `cardsDiscardAfter → cardsDiscardedBatchAfter` 完全平行。

#### B. 摸牌通道 —— `DrawResolutionService`

摸牌**不经过** `_move_card_with_timings`（`draw_resolution_service.gd:161` 直接调 `card_movement.move_card`），因此必须显式开关批次。**同一次 `draw()` 调用摸到的全部牌属于同一批**。

1. `_prepare_batch()`（`draw_resolution_service.gd:78-95`）：在全部有效性校验通过、表现批次建立之后追加：

```gdscript
	# 获得批次作用域；同一次摸牌的全部牌共享一个 cardsGainedBatchAfter 事件。
	_host._begin_gain_batch(int(sequence.context.player_id), "draw")
	sequence.context["gain_batch_started"] = true
```

放在 `_prepare_batch` 内（而不是 `draw()` 入口）是因为：`_prepare_batch` 之前的所有取消/无效路径都不应开启批次。

2. `_draw_card_commit()`（`draw_resolution_service.gd:143-166`）：在 `move` 成功、`sequence.context.drawn_uids.append(card.uid)`（`:165`）之后追加一行 `_host._register_gain_into_batch(card.uid)`。

3. `_finish_batch()`（`draw_resolution_service.gd:199-209`）：在函数开头（表现批次恢复之前）插入带幂等标志的收尾：

```gdscript
	# 获得批次收尾；幂等标志保证牌堆耗尽路径与正常收尾路径都只关闭一次。
	if bool(sequence.context.get("gain_batch_started", false)):
		sequence.context["gain_batch_started"] = false
		_host._end_gain_batch()
```

幂等标志是必需的：`_draw_next_card()` 的牌堆耗尽分支（`:104-108`）会**先调用 `_finish_batch()` 再 `sequence.finish()`**，而正常路径的 `_finish_batch` 步骤不会执行——两条路径必须都关闭批次且只关闭一次。

事件顺序：`… → drawEnd → drawAfter → cardsGainedBatchAfter`。

#### C. 多张获得入口（同一次调用 = 同一批）

以下端口内部以循环逐张调用统一移牌管线，必须在循环外层无条件开启批次，使整批归为一次：

| 端口 | 位置 | 收尾要求 |
|---|---|---|
| `gain_all_hand_cards(receiver_id, target_id, reason)` | `match_controller.gd:6863-6881` | 循环前 `_begin_gain_batch(receiver_id, reason)`；循环后 `_end_gain_batch()` |
| `gain_group_cards_from_draw_or_discard(...)` | `match_controller.gd:7410-7433` | 同上（`reason` 用入参） |
| `gain_same_name_length_cards_from_draw_or_discard(...)` | `match_controller.gd:7455+` | 同上（`reason` 用入参） |

**注意**：这三个端口在**无牌可动**时必须提前返回，不得开启空批次（既避免无意义事件，也避免 `_end_gain_batch` 的栈配对被破坏）。若循环内已有 `break`/提前 `return` 路径，必须保证 `_end_gain_batch()` 仍被调用（推荐「先判空再开栈 + 单一收尾点」的写法）。

#### D. 明确**不**归批的路径（审计结论，需在 `implement.md` 中逐条复核）

| 路径 | 位置 | 不归批的理由 |
|---|---|---|
| 起始手牌 / 手气卡重发 `mulligan_deal` | `match_controller.gd:11389` | 直接调用 `card_movement.move_card`，**既有的 `gain*` 时机也不派发**；起始手牌不是「获得牌」动作。若归批会让【风口】在开局就获得一次「获得≥2张」的选项，属明显错误 |
| 牌堆置入 `secret_pile_placement` / `mulligan_return` | `match_controller.gd:8994,11370` | 目标区域是 `draw_pile`，不是获得 |
| 死亡弃牌 `death_equipment` 等 | `death_resolution_service.gd:202-209` | 目标区域是 `discard_pile`，不是获得 |
| 用牌材料移入处理区 | `match_controller.gd:13533,13583+` | 目标区域是 `processing`，不是获得 |

> 该表是**审计基线**：实现时必须重新 grep 一次全部 `to_zone`/区域参数为 `"hand"` 的移牌点，若发现新路径必须补进本表并给出归批结论。

## 4. 边界与失败处理

| 场景 | 期望行为 |
|---|---|
| 移动被 `gainBefore`/`gainBegin` 取消 | 关闭隐式批次；不派发（空批次）；栈回到空 |
| 持久区域校验失败（早期 `return null`） | 尚未开栈，无副作用 |
| 摸牌目标在等待期间死亡/换将 | `_valid_target` 返回 false，后续步骤跳过；`_finish_batch` 仍执行并关闭批次；空批不派发 |
| 摸牌中途牌堆耗尽 | `_finish_batch` 提前调用并关闭批次；`gain_batch_started` 置 false，后续不再重复关闭 |
| 批次事件回调内再次获得 | 外层已 `pop`，新获得自成新批次，外层 `batch_size` 不被污染 |
| 嵌套批量入口（批量内再批量） | 内层 `_begin_gain_batch` 无条件开新栈帧；内层先收尾，外层不受影响 |
| 终局中断（`state.game_over`） | 既有代码在多处直接 `return`；批次栈可能残留，但终局后不再有任何获得派发，且下一局 `MatchController` 会重建。**必须在 `implement.md` 中确认控制器重建路径不会复用带残留栈的实例**；若复用则需在开局重置处补 `_gain_batch_stack.clear()` |

## 5. 兼容性与回滚

- **存档**：无变化（瞬态字段不入档）。
- **回放**：新时机只增加事件记录；旧回放不含该事件，播放逻辑不依赖它，因此向后兼容。回放录制按事件名白名单/黑名单的情况需在实现时确认（若存在白名单需同步加入，与 `cardsDiscardedBatchAfter` 同档）。
- **网络**：与 `cardsDiscardedBatchAfter` 走同一条 RuleEvent 广播链路；两端执行同一确定性代码，批次号由自增计数器产生，需确认计数器不在两端产生分叉（与既有 `_next_discard_batch_id` 同风险等级，沿用同一模式即可）。
- **性能**：每张获得手牌多派发 0～1 个 RuleEvent（批次内为 0，单张为 1）。与既有弃置批次同阶，可接受。
- **回滚**：本机制是纯增量（新增时机名 + 新增瞬态字段 + 新增函数 + 三处接入），回滚 = 撤销这些改动；无数据迁移。

## 6. 验证策略

新增专项测试 `tests/batch_gain_timing_test.gd`（沿用 `tests/` 既有测试宿主风格），至少覆盖 `prd.md` 验收标准中的 9 条行为断言：

1. `RuleTimingCatalog.has_timing("cardsGainedBatchAfter")` 为真，且紧邻 `cardsDiscardedBatchAfter`。
2. `draw(p, 2)` → 恰好 1 次批次事件、`batch_size == 2`、`card_uids` 与实际入手的实体一致。
3. `draw(p, 1)` → 恰好 1 次、`batch_size == 1`。
4. `gain_all_hand_cards()` 得 N 张 → 1 次、`batch_size == N`。
5. 两次独立单张获得 → 2 次、各自 `batch_size == 1`、`gain_batch_id` 不同。
6. `gainBefore` 取消 → 0 次批次事件，且栈为空。
7. 批次事件回调内再触发一次获得 → 新批次独立，外层 `batch_size` 不变。
8. 既有 `gainAfter` 事件数量与顺序不因本机制改变（回归断言）。
9. 分类计数断言更新为 `[58,48,16,35,38,10,14,8,4,6]`。

运行方式见 `implement.md`。
