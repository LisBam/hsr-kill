# 技术设计：优化获得牌飞行落点与拖拽落位过渡

## 1. 现状与问题定位

| 现象 | 现状代码 | 根因 |
| --- | --- | --- |
| 拖拽松手后瞬间归位 | `_on_hand_drag_finished()` → `_render_local_hand()` → `hand_container.layout_cards_now()` | 布局第 180 行**绝对写入** `card.position`，拖动期间鼠标独占的位置没有任何过渡量承接；`_start_relayout_transition()` 只按「上一次记录槽位 → 新槽位」的差值补偿，而拖动中的牌被 `_slot_positions` 有意排除（第 166 行），松手帧没有可用的起始偏移 |
| 获得牌「从右侧加入手牌再归位」 | `_play_local_hand_gain_flight()` 终点 = `_get_local_hand_gain_start_global_position()`；落地后 `_start_local_hand_gain_animation()` 补间 `hand_entry_offset` 0.24 秒 | 两段表现的第一段终点被写成「手牌区右侧入场点」，而不是最终槽位；第二段再把节点从右侧滑到槽位 |
| 摸牌同样是「先到锚点再滑入」 | `_on_draw_presentation_batch_finished()` 把整批目标写成玩家锚点，并给本机牌登记 `_pending_local_hand_gain_uids` | 批次落点是**一个**锚点（整组居中），不表达每张牌各自的最终槽位 |
| 获得正在展示的牌像「复制一张」 | `_on_card_transfer_requested()` 的 `is_local_gain` 分支无条件新建 `flight_card` | 中央展示队列（`_active_cards`）里那张同 UID 的牌面没有被接管，仍在原处淡出 |

## 2. 设计原则

1. **只有一条飞行路径**：所有飞行都走 `CardUseAnimationLayer.play_transfer()` / `play_draw_transfer_batch()`；本轮只增加「逐张落点」这一个可选入参与「取走中央展示牌」这一个查询接口，不另建飞行动画函数。
2. **槽位真值只有一个**：飞行终点必须等于容器布局算出的槽位中心（`card.position - card.hand_entry_offset - card.hand_selection_offset - card.hand_layout_offset` 的等价量），不允许各调用方自己估算坐标。
3. **不新增偏移字段**：门闸保持继续复用 `CardView.hand_entry_offset`，落位过渡复用 `CardView.hand_layout_offset`，两者都只驱动「偏移归零」，槽位仍由每次布局绝对写入。
4. **正式手牌节点只能用「位置」隐藏，不能用 `visible=false`**：容器布局只收集 `visible` 的子节点，隐藏会改变其他手牌的槽位；把手牌按在来源处（手牌滚动区之外）即可自然被裁剪。

## 3. 数据与接口变更

### 3.1 `DecadeHandContainer`：拖拽落位过渡（R1）

新增配置与状态：

```gdscript
## 拖拽排序松手后从释放点滑回稳定槽位的过渡时长；默认0.18秒与整理过渡一致，运行时可由主题调整。
@export_range(0.05, 0.8, 0.01) var drag_settle_seconds: float = 0.18

## 卡牌实例 ID 到拖拽释放点左上角（容器坐标）的映射；松手后由下一次布局消费，转换成 hand_layout_offset 并补间归零。
var _settle_start_positions: Dictionary = {}
```

新增接口：

```gdscript
## 登记一次拖拽落位过渡的起点；必须在释放点仍有效、且发生任何重新布局之前调用（手牌被动画层接管、离场则记录随槽位记录一并清理）。
func begin_card_settle(card: CardView, release_position: Vector2) -> void
```

实现要点：

- `_layout_cards()` 的位置写入点改为先算 `base_position`（等于原第 180 行的 `Vector2(x - hover_comp, max(y,0)) + hand_entry_offset + hand_selection_offset`），再消费一次 `_settle_start_positions`：命中则 `_start_settle_transition(card, release_position, base_position)`，最后 `card.position = base_position + card.hand_layout_offset`。
- 新增 `_start_settle_transition()` 写**绝对**偏移 `release_position - base_position`；`_start_relayout_transition()` 仍写**差值**累加。两者共用新抽出的 `_start_layout_offset_tween(card, duration)` 创建/索引补间，避免出现第二套补间创建代码。
- 拖拽落位过渡必须**覆盖**同帧的槽位整理过渡（释放点才是真值）：`_start_settle_transition()` 内部先 `_kill_relayout_tween()`。
- `_clear_departed_card_layout_records()` 同时清理 `_settle_start_positions`，防止实例 ID 被复用后继承到别人的释放点。
- 松手帧的布局一定不会因签名早退而跳过：签名包含 `card.is_hand_dragging()`（第 109 行），松手时它由 true 变 false。

### 3.2 `CardView`：无新增接口

复用上一轮的 `hand_layout_offset`（整理/落位过渡）与既有的 `hand_entry_offset`（入场/门闸保持）。拖拽相关接口 `begin_hand_drag()` / `move_hand_drag()` / `end_hand_drag()` / `is_hand_dragging()` 保持不变。

### 3.3 `CardUseAnimationLayer`：逐张落点 + 取走中央展示牌（R3/R4）

**3.3.1 批次逐张落点**

```gdscript
func play_draw_transfer_batch(card_views: Array[CardView], start_position: Vector2, target_position: Vector2, on_flight_finished: Callable = Callable(), card_targets: Array[Vector2] = []) -> void
```

- `card_targets` 为空或长度与有效牌面数不一致时，保持原行为：整组以 `target_position` 为中心按 `draw_batch_card_spacing` 铺开（其他观察者的摸牌、任何单锚点调用方、既有 `smoke_test` 的直连调用都走这一条）。
- `card_targets` 长度匹配时，第 i 张牌的终点取 `card_targets[i]`，逐张落到自己的槽位；起点仍是同一个 `batch_start_position`（牌堆只有一个物理起点），批次补间、停留与淡出节奏完全不变（同批同帧起飞、多批并行）。

**3.3.2 取走中央展示牌**

把 `_remove_presented_card()` 中的索引清理抽成 `_detach_presented_card(card_view)`，并新增：

```gdscript
## 从中央展示队列取走指定实体的正式牌面并交给调用方；返回非空表示调用方已接管该节点（队列成员随即补位），返回 null 表示该牌当前没有中央牌面。
func take_over_active_card(card_uid: int) -> CardView
```

- `_detach_presented_card()` 清 `_active_cards` / `_motion_tweens` / `_card_lifecycle_tweens` / `_card_presentation_started_msec` / `_discard_claim_card_instance_ids` / `_card_sequences`，并新增 `_fade_queue.erase(card_view)`（已进入淡出等待队列的牌同样不能再被释放）。
- `_remove_presented_card()` = `_detach_presented_card()` + `queue_free()`，行为不变。
- `take_over_active_card()` = 按 UID 在 `_active_cards` 中查找 → `_detach_presented_card()` → `_reflow_active_cards(queue_reflow_duration)` → 返回节点（**不**释放、**不**改父级，它本来就是动画层的子节点）。

### 3.4 `MatchTable`：门闸升级为「起点保持」+ 飞行延后到快照（R2/R3/R4）

**3.4.1 门闸记录升级**

`_local_hand_gain_flight_gates[uid]` 的值由 `CardView` 升级为字典：

```gdscript
## 一次本机获得牌飞行的门闸记录：
## card    本次飞行使用的牌面（自愈判定：牌面已释放说明落地回调不会再来）
## origin  本次飞行起点（动画层局部坐标）；正式手牌节点在飞行期间被按在该点，因位于手牌滚动区之外而被裁剪
## started 飞行是否已经起飞；未起飞时快照先到也不能提前把节点放进槽位
## batch   所属摸牌批次 ID；-1 表示单张获得飞行
```

**3.4.2 飞行延后到快照之后**

- 单张获得：`is_local_gain` 分支不再调用 `_play_local_hand_gain_flight()` 立即起飞，改为：
  1. `_try_take_card_origin()` 解析来源；若来源是**正在中央展示**的同 UID 牌面，则用 `take_over_active_card()` 取走那张牌面作为飞行牌面、起点取其当前 `position`；
  2. 否则按现有规则（牌背判定 + 缓存牌面定义）新建飞行牌面，放在来源处；
  3. 登记门闸（`started=false`）后调用 `_start_pending_local_hand_gain_flights()`——此时快照还没到、正式节点还不存在，因此本帧不会起飞。
- 本机摸牌批次：`_on_draw_presentation_batch_finished()` 在 `player_id == local` 时不再立即 `play_draw_transfer_batch()`，而是把「牌面数组 + 起点 + UID 数组 + 批次 ID」登记为待起飞批次，并为每张牌登记门闸（`batch=该批次ID`）。其他玩家的批次行为完全不变（立即起飞、整组居中到其武将牌锚点）。
- `_render_local_hand()` 在 `layout_cards_now()` 之后调用新增的 `_start_pending_local_hand_gain_flights()`：对每个 `started=false` 的门闸，找到正式手牌节点、取出它的槽位中心作为终点后**才**起飞：
  - 单张 → `play_transfer(flight_card, origin, slot_center, "", _release_local_hand_gain_flight_gates.bind([uid]))`
  - 批次 → 逐张收集「可解析槽位」的牌面与终点，一次性 `play_draw_transfer_batch(views, origin, origin, _release_...bind(uids), targets)`
  - 无法解析节点（该牌已经不在手牌区）→ 丢弃该门闸与该飞行牌面，不留下停在屏幕上的孤立牌面。

**3.4.3 门闸保持改为「按在飞行起点」**

```gdscript
## 把仍被门闸挡住的本机获得牌固定在本次飞行的起点；在每次快照手牌布局之后调用。
func _hold_gated_local_hand_entries() -> void
```

- 保持偏移 `hand_entry_offset = 起点(动画层坐标) → 容器局部坐标 − 槽位`；起点转全局用 `card_use_animation_layer.get_global_transform() * origin`，再复用 `hand_container.get_global_transform().affine_inverse()`。
- 只处理 `started=true` 且已经有正式节点的门闸；自愈逻辑（牌面已释放 → 立即解闸）保留。
- 原本的 `_get_local_hand_gain_entry_offset()` / `_get_local_hand_gain_start_global_position()` 仍然保留并被**虚拟手牌**路径使用（候选从右侧进入），不删除。

**3.4.4 解闸即落位（取消第二段滑动）**

`_release_local_hand_gain_flight_gates()` 解闸后改为调用新增的 `_finish_local_hand_gain_holds(uids)`：把这些节点残留的 `hand_entry_offset` 归零并重新布局一次——节点在落地那一帧直接出现在槽位，不再有 0.24 秒滑入。

**3.4.5 真实获得牌不再走右侧入场**

- `is_local_gain` 分支不再写 `_pending_local_hand_gain_uids`；该集合与 `_start_local_hand_gain_animation()` 之后只服务虚拟手牌候选与虚拟牌回归（右侧进入的语义在那一处是刻意保留的）。
- 本机区域间移动（木牛 ↔ 手牌）没有飞行，也不再从右侧进入，改由容器既有的槽位整理过渡表达。

## 4. 关键时序

### 4.1 单张获得（含正在中央展示的牌）

```
controller.card_transfer_requested(target=本机 hand)
  └─ _on_card_transfer_requested → is_local_gain
       ├─ take_over_active_card(uid)：正在中央展示 → 取走该节点（队列补位）
       ├─ _try_take_card_origin(uid, 来源)：解析起点（本机装备槽 / 其他角色武将牌 / 公共锚点）
       ├─ 登记门闸 {card, origin, started:false}
       └─ _start_pending_local_hand_gain_flights()  ← 正式节点还不存在，本帧不起飞
state_changed → _on_state_changed → _render_local_hand
  ├─ layout_cards_now()：正式手牌节点加入容器并算出槽位
  ├─ _hold_gated_local_hand_entries()：把该节点按在来源处（滚动区外→被裁剪）
  └─ _start_pending_local_hand_gain_flights()
       └─ play_transfer(飞行牌面, 来源, 槽位中心, "", 落地回调)
飞行落地 → _release_local_hand_gain_flight_gates([uid])
  └─ _finish_local_hand_gain_holds([uid])：偏移归零 → 正式节点就出现在槽位
```

### 4.2 本机摸牌批次

```
batch_started / 逐张 transfer（带批次 ID）/ batch_finished
  └─ 本机：建牌背牌面 + 逐张登记门闸 {origin: 牌堆锚点, batch: id, started:false}，登记待起飞批次
state_changed → _render_local_hand
  └─ _start_pending_local_hand_gain_flights()
       └─ play_draw_transfer_batch(views, 牌堆锚点, 牌堆锚点, 落地回调, [各槽位中心...])
落地 → 解闸 → 各正式手牌节点直接出现在各自槽位
```

### 4.3 拖拽排序松手

```
CardInputArea.hand_drag_finished
  └─ _on_hand_drag_finished
       ├─ release_position = source_view.position   ← 必须在退出跟随/重排之前取
       ├─ end_hand_drag()
       ├─ hand_container.begin_card_settle(source_view, release_position)
       ├─ 命中目标 → _on_hand_card_reorder_requested → _render_local_hand → layout_cards_now()
       └─ 未命中 → layout_cards_now()
            └─ _layout_cards 消费释放点 → hand_layout_offset = 释放点 − 基准位置 → 补间归零(drag_settle_seconds)
```

## 5. 边界与自愈

| 场景 | 处理 |
| --- | --- |
| 门闸登记后该牌离开手牌（被使用/弃置/重铸） | `_cancel_local_hand_gain_animation()` 解闸并丢弃待起飞记录（既有路径，新增批次登记也要一并清理） |
| 快照迟迟不到、正式节点始终不出现 | 门闸保留 → 保持函数不写位置；下一次对账继续尝试；清场时统一清空 |
| 飞行牌面意外被释放 | `_hold_gated_local_hand_entries()` 的 `is_instance_valid(gate["card"])` 自愈 → 立即解闸落位 |
| 同一 UID 连续获得两次 | 门闸字典按键覆盖，`started` 随新记录重置；旧飞行牌面仍走自己的落地回调（回调按 UID 解闸，解的是最新记录，语义一致） |
| 重新开局 / LAN 重连 | `_clear_local_hand_gain_animations()`（+: 清空待起飞批次与释放未起飞的飞行牌面）；`clear_presentations()` 递增代次使旧协程退出 |
| 摸牌批次的牌没有正式手牌节点（同时被弃置等） | 该牌从批次中剔除；若整批都无节点则丢弃批次并释放牌面，不留孤立牌 |
| 取走的中央展示牌正好在淡出等待队列中 | `take_over_active_card()` 会先 `_fade_queue.erase()`，避免接管后又被淡出流程 `queue_free()` |

## 6. 测试设计（`tests/ui_layout_test.gd`）

- R1：模拟拖动一张牌到另一张牌左侧 → 断言松手帧 `position` 等于释放点、`hand_layout_offset` 等于释放点 − 槽位；等待 `drag_settle_seconds` 后偏移归零且 `position` 等于最终槽位；未命中目标时同样走过渡回原位。
- R2：既有 `local_gain_entity` 用例改写为：断言门闸 `started=false` → 快照后飞行终点等于正式节点槽位中心、正式节点被按在来源处且无入场补间 → 落地后正式节点位于槽位。
- R3：既有批次用例改写为：断言本机批次的 `card_targets` 分别等于各自槽位中心、批次补间只有一组、落地后节点直接到位；其他玩家批次仍整组居中。
- R4：在中央展示队列里放一张同 UID 牌面 → 触发本机获得 → 断言返回节点实例 ID 与队列中一致、接管后不在 `_active_cards`、队列其余成员位置重新铺开、节点未被释放、`_transfer_cards`/新建牌面数为 0。
- 必须保持的既有断言：牌背判定口径、缺失锚点不伪造落点、`local_hand_exit`/弃牌队列顺序、悬停不触发整理、虚拟手牌候选仍从右侧进入。

## 7. 风险与取舍

- **风险：飞行终点取自「落地前最后一次布局」。** 若落地前又有其他牌入场使槽位变化，飞行终点会是旧槽位，出现一次小跳。取舍：门闸保持阶段会按最新槽位重新按住（按住位置不变），且飞行时长 0.42 秒内极少发生第二次手牌结构变化；相比「先飞到右侧再滑入」的固定偏差，这是明显更小的误差。
- **风险：本机摸牌不再整组居中。** 这是用户明确要求的方向（各自直飞最终槽位）；`draw_batch_card_spacing` 仍被其他观察者路径与既有直连接口使用，因此不移除。
- **取舍：不删除右侧入场能力。** 虚拟手牌候选/回归继续使用它，避免把「候选牌像摸牌一样进入」这条刻意语义一并改掉。
