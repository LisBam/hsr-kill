# 技术设计：中央区展示牌被获得时先入弃牌堆再飞向获得者

## 1. 现状与问题定位

| 现象 | 现状代码 | 根因 |
|---|---|---|
| 本机获得中央展示牌时，牌**永远到不了中央弃牌区**，而是从出牌者武将牌直接拐进手牌 | `match_table.gd` `_play_local_hand_gain_flight()` L5014-L5048 在收到获得信号的当帧调用 `card_use_animation_layer.take_over_active_card()` | 展示牌面刚由 `play_card()` 加入队列、仍在飞向中央的途中就被摘走；`take_over_active_card()` 用「它当前所在位置」当起点，于是起点是出牌者武将牌 |
| 其他角色获得中央展示牌时，画面里同时出现两张同 UID 牌面 | `match_table.gd` `_on_card_transfer_requested()` L4873-L4905 无条件新建一张牌面放在中央弃牌锚点 | 该分支从不查询中央队列里是否已有同 UID 牌面；原牌面继续飞向中央并留在队列里，新建牌面则从中央飞向获得者 |
| 规则上「牌已经进入弃牌堆」这件事在画面上没有任何落点 | 中央展示队列 `_active_cards` | 本机路径当帧摘牌、旁观路径另造牌面，两者都没有让这张牌在队列里落位 |

时序事实（决定实现方式）：`MatchController._move_played_card_to_discard()` 先请求中央展示（`owns_discard_transfer=true`），再把实体移入弃牌堆；随后才派发 `respond` 时机，【伏辰】在该回调里立刻 `gain_card_to_hand_by_uid()`。因此**获得信号与展示信号几乎同帧**，展示牌面此时通常仍在飞往中央的途中。

## 2. 设计原则

1. **只改「什么时候取走」，不改「取走什么」**：`take_over_active_card()` 保留为唯一取走接口；本轮只把它的调用时机从「收到获得信号的当帧」推迟到「该牌在中央队列落位之后」。
2. **落位判定只有一个来源**：`CardUseAnimationLayer` 自己知道每张展示牌的位置补间何时结束，因此由它提供唯一的「落位通知」入口；桌面不得轮询计时、不得自行推算队列坐标。
3. **不新增第二套飞行动画**：第二段仍然走 `play_transfer()`，终点仍由既有入口给出（本机 `_get_local_hand_card_slot_center()`、他人 `_try_get_player_indicator_position()`）。
4. **等待期间正式手牌节点不得提前可见**：继续复用 `_local_hand_gain_flight_gates` 门闸与 `hand_entry_offset` 起点保持，只给门闸增加一个「等待中央落位」状态，不引入第二套偏移字段。
5. **取消必须彻底**：等待登记、门闸、未播放牌面三者必须能被同一条取消路径一起回收（`_cancel_pending_local_hand_gain_flight()` 已存在，本轮让它同时撤销落位通知）。

## 3. 接口与数据变更

### 3.1 `CardUseAnimationLayer`：唯一的中央牌面落位通知

新增状态：

```gdscript
## 等待「中央牌面飞抵队列落位」通知的实体 UID 到回调的映射。
## 键用稳定 UID 而不是实例 ID：同一实体在同一时刻最多只有一张中央牌面，
## 且调用方（桌面）本身就是按 UID 管理门闸的。
var _pending_active_card_landings: Dictionary = {}
```

新增接口（唯一入口，桌面只调用它）：

```gdscript
## 申请在该实体当前中央牌面「飞抵弃牌队列落位」时收到一次通知。
## 返回 {"accepted":bool, "position":Vector2}：
##   accepted=false —— 该 UID 当前没有中央牌面，调用方必须走原有的立即解析来源路径；
##   accepted=true  —— 已登记通知；position 是该牌此刻的牌面中心（动画层局部坐标），
##                     调用方用它作为等待期间的起点保持位置，使正式手牌节点停在手牌滚动区之外被裁剪。
func request_active_card_landing(card_uid: int, on_landed: Callable) -> Dictionary

## 撤销一次尚未触发的落位通知；返回 true 表示确实撤销了一条等待登记。
## 调用方在取消本次获得表现、或该牌已经离开手牌区时调用，避免回调迟到后取走一张已经无主的牌面。
func cancel_active_card_landing(card_uid: int) -> bool
```

内部实现要点：

- `request_active_card_landing()` 命中队列后写入 `_pending_active_card_landings[card_uid]`，随后调用 `_bind_active_card_landing(card_view)`：
  - 若该牌当前仍有**正在运行**的位置补间（`_motion_tweens` 中有效且 `is_running()`），把 `finished` 连到 `_on_active_card_motion_finished(instance_id)`（一次性连接）；
  - 否则说明它已经落位（例如补间已结束或队列已静止），当帧直接走 `_complete_active_card_landing(instance_id)`，保证调用方不会永远等不到回调。
- `_start_card_motion()` 末尾补一次 `_bind_active_card_landing()`：队列补位会替换同一张牌的位置补间，落位必须跟随**最新**那条补间结束，而不是旧补间。
- `_complete_active_card_landing(instance_id)`：节点仍属于 `_active_cards` 时取出并删除该 UID 的等待登记，然后调用回调。**不在动画层内部摘牌**——是否取走由调用方决定，这样「等待已被取消」时牌面自然留在队列里按原节奏淡出。
- `_detach_presented_card()` 与 `clear_presentations()` 同时清掉该 UID 的等待登记，避免节点已消失后回调仍然触发。
- 取消语义：`cancel_active_card_landing()` 只删除登记，不释放节点（节点仍归中央队列）。

### 3.2 `match_table.gd`：本机获得路径（R1/R2/R3/R5）

`_play_local_hand_gain_flight()` 的流程改为：

1. 来源守卫（不变）。
2. **先申请落位通知**：`request_active_card_landing(card_uid, _on_central_display_card_landed.bind(card_uid))`。
3. `accepted=true`：登记**等待落位**门闸，然后直接返回（当帧不取牌、不建牌面）：
   ```gdscript
   {"card":null, "origin":<该牌此刻中心>, "started":false, "batch":-1,
    "snapshot_generation":_local_hand_snapshot_generation, "awaiting_landing":true}
   ```
4. `accepted=false`：保持原有行为（立即 `take_over_active_card()`；取不到再走 `_try_take_card_origin()` 并新建牌面），门闸带 `"awaiting_landing":false`。

新增回调：

```gdscript
## 中央展示牌面落位后的接管入口；由动画层落位通知触发，是「先进入弃牌堆、再飞向获得者」的分界点。
func _on_central_display_card_landed(card_uid: int) -> void
```

- 门闸缺失或已不处于等待状态（本次获得表现已被取消）→ 直接返回，牌留在中央队列按原节奏淡出。
- 否则 `take_over_active_card(card_uid)`：
  - 返回 null（通知与取走之间牌面消失）→ 走 `_release_local_hand_gain_flight_gates([card_uid])`，让正式手牌节点直接落位，绝不留下永远等不到回调的门闸；
  - 返回牌面 → 把 `card` / `origin`（= 落位后的牌面中心）写回门闸、清掉等待标记，然后调用 `_start_pending_local_hand_gain_flights()`；若权威快照已到达（正式节点已在容器中），第二段飞行当帧起飞，否则等下一次快照对账。

配套修改（都是「让等待状态可被现有机制理解」的最小改动）：

| 函数 | 改动 |
|---|---|
| `_hold_gated_local_hand_entries()` | 起点保持条件从「已起飞」放宽为「已起飞**或**正在等待中央落位」：等待期间正式节点同样必须被按在起点，否则它会先出现在最终槽位、与中央区那张牌同时可见 |
| `_start_pending_local_hand_gain_flights()` | 在「已起飞 / 摸牌批次」早退之后增加等待落位早退：此时既没有可飞的牌面，**也不能**把它当成「飞行牌面已失效」而释放门闸 |
| `_cancel_pending_local_hand_gain_flight()` | 等待落位时先 `cancel_active_card_landing(card_uid)`；未起飞的牌面释放逻辑不变（等待期间 `card` 为 null，自然跳过） |
| `_render_local_hand()` 的门闸对账 | 撤销过期门闸时改为调用 `_cancel_pending_local_hand_gain_flight()` 再删除门闸，保证落位通知与门闸一起回收 |
| `_clear_local_hand_gain_animations()` | 逐个撤销仍在等待的落位通知（遍历键而不是值），与门闸清空同批完成 |

### 3.3 `match_table.gd`：其他角色获得路径（R2/R3）

`_on_card_transfer_requested()` 的非本机分支在解析完 `start_position` / `target_position` / `show_card_back` 之后、新建牌面之前插入：

```gdscript
# 中央区展示牌被其他角色获得：先等它飞入中央弃牌队列落位，再由同一牌面继续飞向获得者。
# 只在本次转移应当显示正面时申请：牌背转移与「公开展示中的正面牌面」不可能同时成立，
# 若强行接管会改变已公开牌面的可见性语义。
if not show_card_back:
    var landing_result: Dictionary = card_use_animation_layer.request_active_card_landing(
        card_uid, _on_central_display_card_transfer_landed.bind(card_uid, target_position))
    if bool(landing_result.get("accepted", false)):
        return
```

新增回调：

```gdscript
## 其他角色获得中央展示牌时的第二段飞行入口；与「立即新建牌面」路径互斥。
func _on_central_display_card_transfer_landed(card_uid: int, target_position: Vector2) -> void
```

- `take_over_active_card(card_uid)` 为 null → 本次表现放弃（与既有「锚点缺失宁可跳过动画」的口径一致）。
- 否则 `play_transfer(animated_card, <落位后中心>, target_position, draw_stack_key)`，其中 `draw_stack_key` 沿用原分支公式（只有牌堆来源且目标是手牌时才非空，中央展示来源恒为空串）。

**取舍**：`target_position` 在申请时解析并捕获，而不是落位后再解析。理由是保持既有「目标锚点缺失时整段表现放弃、不伪造落点」的早退语义；座位锚点在一局内稳定，0.42 秒的捕获窗口不构成可见误差。

### 3.4 不新增的参数

本轮不引入新的可调时长/距离：第一段时长沿用既有 `card_flight_duration`（0.42 秒），队列补位沿用 `queue_reflow_duration`（0.18 秒），第二段沿用 `card_flight_duration` 与既有停留/淡出节奏。等待落位的等待时长完全由第一段飞行时长决定，不需要新的 `@export`。

## 4. 数据流（【伏辰】获得其他角色打出的【杀】）

```
核心：_move_played_card_to_discard()
  ├─ 请求中央展示（owns_discard_transfer=true）→ play_card()：牌面入队、开始飞向中央区
  └─ 实体进入弃牌堆 → card_transfer_requested(processing → discard_pile)
                         └─ register_discard_transfer() 命中认领 → 不新建牌面，牌面继续飞
核心：派发 respond 时机 → 【伏辰】gain_card_to_hand_by_uid()
  └─ card_transfer_requested(discard_pile → hand, 目标=获得者)
       ├─ 本机获得：申请落位通知 → 登记「等待落位」门闸（正式手牌节点被按在起点、裁剪不可见）
       └─ 他人获得：解析目标武将牌锚点 → 申请落位通知
牌面飞抵中央弃牌队列（位置补间结束）
  └─ 动画层落位通知
       ├─ 本机获得：take_over_active_card() → 门闸记录牌面与落位起点 → 快照就绪则起飞 → 飞向最终槽位
       └─ 他人获得：take_over_active_card() → play_transfer() → 飞向获得者武将牌
落地帧：本机正式手牌节点出现在同一槽位、飞行牌面同帧隐藏；队列其余成员按 0.18 秒补位
```

## 5. 边界与取消路径

| 场景 | 期望行为 |
|---|---|
| 该牌当前没有中央牌面（展示已淡出、来源本来就不是中央展示） | 落位申请返回 `accepted=false`，走原有立即路径（AC7） |
| 等待落位期间该牌离开本机手牌区（例如再次被移走） | 门闸对账调用取消路径 → 撤销落位通知 → 牌留在中央队列按原节奏淡出（AC6） |
| 等待落位期间重新开局 / 清场 | `clear_presentations()` 清空动画层等待登记，`_clear_local_hand_gain_animations()` 清空门闸并撤销剩余通知（AC6） |
| 落位通知触发但牌面已消失 | 本机路径解闸让正式节点落位；他人路径放弃本次表现（不留孤立牌面） |
| 等待落位期间权威快照先到 | 门闸把正式节点按在起点（手牌滚动区之外、被裁剪），不出现「手牌区先有一张、中央区还有一张」（AC5） |
| 队列中该牌被其他路径提前取走 | `_detach_presented_card()` 清掉等待登记，回调不再触发，调用方靠门闸兜底落位 |

## 6. 测试设计（`tests/ui_layout_test.gd`）

改写「获得正在中央展示中的牌」用例（现有 `continuity_takeover_*` 段落）为两段断言：

1. **申请阶段**：把两张展示牌放进队列并**放慢飞行**（`card_flight_duration` 调大），在本机获得信号到达的那一帧断言：该 UID 仍在 `_active_cards` 中、`_transfer_cards` 为空、门闸带 `awaiting_landing=true` 且 `card` 为空、`origin` 等于该牌此刻的中心。
2. **等待期间快照**：先推入包含该牌的权威快照，断言正式手牌节点已在容器中、`hand_entry_offset` 非零（被按在起点）、位置在手牌滚动区之外，且**没有**出现在最终槽位。
3. **落位阶段**：等待 `card_flight_duration` 之后断言：`_active_cards` 中不再有该 UID、接管牌面的实例 ID 与队列中那张完全一致、门闸 `card` 非空且 `origin` 等于落位后的中心、`awaiting_landing=false`、`_transfer_cards` 恰为 1。
4. **落地阶段**：等待第二段飞行结束后断言正式节点位于最终槽位、`hand_entry_offset` 归零、飞行牌面不可见（沿用既有断言口径）。
5. **其他角色路径**：对同一个 UID 走「获得者是其他角色」的转移，断言第二段飞行的 `start_position` 等于落位中心（而不是中央弃牌锚点）、`target_position` 等于获得者武将牌锚点，且全程 `_transfer_cards` 只有 1 张该 UID 牌面。
6. **取消路径**：在等待落位期间调用取消/清场入口，断言动画层的等待登记被清空、门闸被清空、该牌仍留在 `_active_cards` 中（未被摘走、未被释放）。

必须保持的既有断言：牌背判定口径、缺失锚点不伪造落点、`local_hand_exit`/弃牌队列顺序、悬停不触发整理、虚拟手牌候选仍从右侧进入、本机摸牌逐张落点、拖拽落位过渡、表现牌三档层级。

## 7. 风险与取舍

- **风险：落位通知依赖位置补间结束。** 若队列补位在该牌落位前又替换了它的位置补间，通知会推迟到最新那条补间结束——此时牌确实停在队列槽位上，语义仍然成立，只是第二段飞行稍晚。
- **风险：等待期间牌在队列里的停留时长可能很短。** 落位当帧即起飞，玩家看到的是「牌落进弃牌区后立刻被拿走」，这正是需求要表达的规则顺序；不额外增加停留时长以免拖慢结算节奏。
- **取舍：不删除 `take_over_active_card()`。** 它是「取走队列中同 UID 牌面本身」的唯一能力，新方案仍在使用，只是调用时机后移。
- **取舍：等待登记按 UID 而不是实例 ID 索引。** 桌面按 UID 管理门闸，按 UID 索引让「取消」可以直接用门闸里的 UID 完成，不需要额外维护实例映射。
