# 多张重铸机制 — 技术设计

> 需求与验收见同目录 `prd.md`；公共架构决策见父任务 `09-30-huanyu-ahha-system/design.md`。

---

## 一、现状锚点

`match_controller.gd:12714`-`12739` 的单张重铸：

```gdscript
func recast_hand_card(player_id: int, card_uid: int) -> bool:
	# 校验角色：存在、存活、未离场
	# 校验牌：player.find_hand_card(card_uid)（仅普通手牌区）
	player.take_hand_card(card.uid)
	_move_to_discard(card, -2, false)          # 关键：false = 不构成“弃置”动作
	add_log("%s重铸了%s。" % [...])
	if _has_nested_settlement_barrier():
		_defer_rule_continuation("recast_draw", {"player_id":player_id})
		return true
	draw(player_id, 1)
	return true
```

`_move_to_discard(card, source_player_id, is_discard_action)` 的第三个参数决定是否派发弃置批次与写「弃置了」日志（见 `:14333` 附近注释）。重铸必须传 `false`。

---

## 二、改动清单

| # | 文件 | 改动 |
|---|---|---|
| 1 | `scripts/core/match_controller.gd` | 提炼私有辅助 + 新增 `recast_hand_cards(player_id, card_uids) -> int`）
| 2 | `tests/multi_recast_test.tscn` + `.gd` | **新建**：专项测试 |
| 3 | `README.md` | 「自动校验」章节补一行 |

**不新增**：不改 `card_movement_service.gd`（移牌唯一边界已由 `_move_to_discard` 承担）、不改 `PlayerAction` 协议（本端口只被技能调用，不新增玩家动作类型）。

---

## 三、接口设计

### 公开端口

```gdscript
## 令指定角色一次重铸多张普通手牌：先把它们全部置入弃牌堆，再摸等量的牌。
## 返回值 = 实际重铸张数；返回 0 表示一张都没有被重铸，调用方不得据此产生任何后续效果。
## 语义与 recast_hand_card 完全一致：不构成“使用”“打出”，也不构成“弃置”。
func recast_hand_cards(player_id: int, card_uids: Array[int]) -> int
```

### 私有辅助（消除重复）

```gdscript
## 重铸流程的共享实现：逐张移入弃牌堆、写日志、按屏障决定立即补摸或延后补摸。
## single_card_log=true 时使用单张日志文本（保持既有行为），否则使用带张数的日志文本。
## 返回实际重铸张数。
func _recast_cards_common(player_id: int, card_uids: Array[int], single_card_log: bool) -> int
```

`recast_hand_card(player_id, card_uid)` 改为：

```gdscript
return _recast_cards_common(player_id, [card_uid] as Array[int], true) > 0
```

**行为守恒要点**：单张路径的日志文本、`draw(player_id, 1)`、`_defer_rule_continuation("recast_draw", {...})` 的参数形状必须与改动前逐字一致——既有测试 `card_action_semantics_test.gd:319` 与 `gameplay_regression_test.gd:827` 直接依赖它们。

### 实现细节

```text
_recast_cards_common(player_id, card_uids, single_card_log):
  if state == null or state.game_over: return 0
  player = state.get_player(player_id)
  if player == null or not player.alive or player.out_of_game: return 0

  moved_uids = []           # 实际被重铸的实体 UID（去重 + 区域复核）
  moved_names = []          # 对应的显示名（用于单张日志）
  for uid in card_uids:
      if moved_uids.has(uid): continue              # 重复 UID 只重铸一次
      card = player.find_hand_card(uid)
      if card == null: continue                     # 非普通手牌区 / 已离手
      definition = GameDatabase.get_card(card.definition_id)
      player.take_hand_card(card.uid)
      _move_to_discard(card, -2, false)             # 不构成弃置
      moved_uids.append(card.uid)
      moved_names.append(GameSettings.resolve_card_name(definition))

  if moved_uids.is_empty(): return 0                # 不写日志、不摸牌

  if single_card_log:
      add_log("%s重铸了%s。" % [format_player_state_log_name(player), moved_names[0]])
  else:
      add_log("%s重铸了%d张牌。" % [format_player_state_log_name(player), moved_uids.size()])

  count = moved_uids.size()
  if _has_nested_settlement_barrier():
      _defer_rule_continuation("recast_draw", {"player_id":player_id, "count":count})
      return count
  draw(player_id, count)
  return count
```

### 续接路径兼容

`_defer_rule_continuation("recast_draw", ...)` 的消费端按 `context["count"]` 取张数；单张路径必须继续携带 `count=1`（等价于原先的隐式 1 张）。实现时需核对续接消费点，确认新增 `count` 键不会与既有键冲突。

> 若消费端当前写死 `draw(player_id, 1)`，则改为读取 `int(context.get("count", 1))`——默认值 `1` 保证任何历史续接上下文仍然按单张补摸。

---

## 四、测试设计（`tests/multi_recast_test.tscn`）

| 用例 | 断言 |
|---|---|
| 3 张一次重铸 | 返回 `3`；弃牌堆 +3；摸牌堆 -3；手牌净变化 0 |
| 不构成弃置 | 未派发 `cardsDiscardedBatchAfter`；日志不含「弃置了」；日志含「重铸了3张牌」 |
| 重复 UID | `[A, A, B]` 返回 `2`，A 只进弃牌堆一次 |
| 非手牌 UID | 装备牌 UID / 木牛「粮」UID / 判定牌 UID 均被忽略，返回值不计入 |
| 死亡/离场角色 | 返回 `0`，两堆牌数量不变 |
| 空数组 | 返回 `0`，不写日志 |
| 单张回归 | `recast_hand_card` 仍返回 `bool`，日志仍为「重铸了<牌名>。」 |
| 嵌套屏障 | 构造末张手牌触发技能屏障的场景，补摸在屏障清空后发生且张数正确 |

---

## 五、风险

| 风险 | 说明 | 对策 |
|---|---|---|
| 单张日志文本被改动 | `card_action_semantics_test` 会失败 | `single_card_log` 分支保留原文；测试直接断言 |
| 续接上下文键冲突 | `recast_draw` 消费端若已有 `count` 语义 | 实现前先读消费端；默认值取 1 |
| `_move_to_discard` 第三参数误传 `true` | 会派发弃置批次、触发弃置类技能 | 复用同一条私有路径，只有一处调用点 |

---

## 六、回滚

删除 `recast_hand_cards` 与私有辅助、把 `recast_hand_card` 还原为原实现即可；无状态与存档变化。
