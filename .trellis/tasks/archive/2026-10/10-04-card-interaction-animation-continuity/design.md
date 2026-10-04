# 技术设计：优化卡牌交互动画连续性

## 1. 问题定位（代码级根因）

### 根因 A：弃置/重铸新建了第二张牌，原节点先被释放

`MatchTable._on_card_transfer_requested()` 在 `target_zone == "discard_pile"` 时：

1. 用 `start_position = _try_get_player_indicator_position(source_player_id)` 取起点；本机玩家的锚点是**手牌区顶边中心**（`match_table.gd:4792`），不是被弃置那张牌的位置。
2. `CARD_VIEW_SCENE.instantiate()` **新建**一张牌放到该锚点（`match_table.gd:4753-4760`），再交给 `play_card()`。
3. 随后的 `_on_state_changed` → `_render_local_hand()` 发现原 UID 不在快照里，于是把原正式手牌节点 **`queue_free()`**（`match_table.gd:2394-2396`）。

净效果：原位置的牌瞬间消失 → 手牌区中心冒出一张新牌 → 飞到弃牌堆。装备区同理，但连槽位坐标都没有取，直接用武将牌/手牌区锚点。

关键机会：`card_transfer_requested` 在 `state_changed` **之前**发出（已被现有 `is_local_gain` 分支「登记待入场 UID、等下一次快照再播放」的实现反向证明），所以信号到达时原节点仍活在原位置。而 `CardUseAnimationLayer.play_card()` 已经具备接管活跃节点的能力：

```gdscript
# card_use_animation_layer.gd:284-291
var original_global_transform: Transform2D = presented_card.global_transform
if presented_card.get_parent() != self:
    presented_card.reparent(self)
presented_card.global_transform = original_global_transform
```

**结论：不需要新的动画函数，只需要把「已有节点」交给已有接口，并把起点换成真实位置。**

### 根因 B：本机获得牌缺少前置飞行段

`is_local_gain` 分支只登记 `_pending_local_hand_gain_uids` 后 `return`（`match_table.gd:4730-4733`），因此本机从弃牌堆/其他角色区域获得牌时**没有任何飞行牌**，只有正式手牌节点从右侧滑入。表现为「牌从弃牌堆消失 → 手牌区右侧冒出来」。

### 根因 C：真实摸牌走批次分支，绕过了手牌入场登记

`_on_draw_presentation_batch_started/_finished` 会在 `draw()` 期间给牌堆→手牌的移动打上 `DRAW_PRESENTATION_BATCH_ID_KEY`。`_on_card_transfer_requested()` 遇到批次标记就 `return`（`match_table.gd:4700-4707`），**不会**登记 `_pending_local_hand_gain_uids`。

而 `_pending_local_hand_gain_uids` 只在三处登记：局内虚拟手牌回归（2592）、虚拟候选（2639）、`is_local_gain`（4731）。批次路径不在其中。

**因此真实对局中本机摸牌／获得的牌是直接出现在手牌槽位的**，`_start_local_hand_gain_animation()` 从未被调用。这正是用户描述的「而不是直接进入手牌区」。现有测试只覆盖了非批次路径（`ui_layout_test.gd:1229-1235`），所以这个缺口一直没有被拦住。

### 根因 D：手牌容器没有槽位过渡

`DecadeHandContainer._layout_cards()` 每次结构变化都用 `card.position = ...` 直接写入最终槽位（`decade_hand_container.gd:126`）。既没有上一帧槽位记录，也没有补间，因此数量变化时其余手牌瞬间跳位。

### 根因 E：展示本机手牌从手牌区中心锚点起飞

`_on_card_presentation_requested()` 中 `presentation_only == true`（`showCards`）时新建牌面副本，起点是 `start_position`＝本机手牌区顶边中心。而火攻等展示的牌其实就明明白白躺在手牌区里。

---

## 2. 分层与边界

| 层 | 文件 | 本次职责 |
|---|---|---|
| 表现层（动画播放器） | `scripts/ui/card_use_animation_layer.gd` | 只增加「飞行落地」这一可观察时刻的通知；不新增播放语义 |
| 表现层（牌桌协调器） | `scripts/ui/match_table.gd` | 唯一的「卡牌来源位置解析」入口、牌背判定入口、手牌入场门闸 |
| 表现层（无状态布局组件） | `scripts/ui/decade_hand_container.gd` | 槽位过渡补间；仍然不认识身份、阶段或规则 |
| 表现层（卡牌组件） | `scripts/ui/card_view.gd` | 新增第三个可叠加偏移属性 `hand_layout_offset` |
| 表现层（装备栏组件） | `scripts/ui/equipment_stack_view.gd` | 新增一个只读的「实体 UID → 槽位屏幕矩形」查询 |
| 规则层 / 网络层 / 内容层 | — | **零改动** |

`MatchController`、`CardMovementService`、快照结构、`PlayerAction`、AI、网络协议一律不动。这是纯表现改动。

---

## 3. 接口设计

### 3.1 `CardUseAnimationLayer.play_transfer()` 增加可选落地回调

```gdscript
func play_transfer(card_view: CardView, start_position: Vector2, target_position: Vector2,
                   draw_stack_key: String = "", on_flight_finished: Callable = Callable()) -> void
```

把原来「飞行 + 停留 + 淡出」的单条补间拆成两条：

- 飞行补间：`position` + `scale`，时长不变；写入 `_transfer_tweens` 以便 `clear_presentations()` 仍能整体终止。
- 飞行结束 → 代次校验 → `on_flight_finished.call()` → 停留补间（`tween_interval` + `modulate:a`），同样写入 `_transfer_tweens`。

**为什么必须拆**：原来只有一个 `await transfer_tween.finished`，调用方无法知道「牌什么时候落到手牌区右侧」。拆开后落地时刻成为明确事件，调用方据此启动正式手牌节点的滑入，两段首尾严格衔接，且不引入任何计时猜测（检查器里改 `card_flight_duration` 时衔接自动跟随）。

**行为兼容**：不传回调时两条补间顺序播放，总时长与视觉与原来完全一致。

### 3.2 `CardUseAnimationLayer.play_draw_transfer_batch()` 增加可选落地回调

```gdscript
func play_draw_transfer_batch(card_views: Array[CardView], start_position: Vector2,
                              target_position: Vector2, on_flight_finished: Callable = Callable()) -> void
```

`_play_draw_transfer_batch()` 在 `await flight_tween.finished` 与代次校验之后、建立 `hold_tween` 之前调用一次回调。理由同上：真实摸牌走批次路径，本机手牌入场必须等这批牌背落地。

### 3.3 `EquipmentStackView.find_card_global_rect()`：装备槽位唯一查询

```gdscript
## 返回指定实体 UID 当前所在装备槽的屏幕矩形；未装备或行节点缺失时返回 valid=false。
func find_card_global_rect(card_uid: int) -> Dictionary
```

实现直接复用 `EQUIPMENT_SLOT_ORDER`（唯一顺序来源）、`_equipment`、`_rows_by_slot`，与既有 `get_row()` / `is_slot_equipped()` 同一风格，不新增第二份槽位表。

### 3.4 `MatchTable._try_take_card_origin()`：全项目唯一的来源解析入口

```gdscript
## 统一解析并接管一张牌的离场起点。所有「离场、被取走、被展示」的表现都必须经此入口取起点，
## 不得在别处重写来源判断，否则同一种语义会出现第二套位置规则。
##
## 返回字段：
## - valid：是否解析到可用来源；false 时调用方必须放弃本次表现，不得伪造中央落点。
## - position：动画层局部坐标下的牌面中心。
## - global_rect：来源的屏幕矩形，供热区与落点换算。
## - card_view：仍位于手牌容器内、可被动画层直接接管的正式手牌节点；null 表示调用方需新建表现牌。
func _try_take_card_origin(card_uid: int, source_player_id: int, source_zone: String) -> Dictionary
```

解析顺序（顺序即优先级，注释里写明理由）：

1. **本机手牌区 / 木牛“粮”的正式节点**（`source_zone in ["hand", "wooden_ox"]`）：返回该节点自身矩形。
   - 副作用：先收尾该 UID 未完成的入场补间并把 `hand_entry_offset` / `hand_selection_offset` 归零，使接管从**真实槽位**开始；同时把该 UID 从待入场表与门闸表移除。这些收尾都发生在同一帧内、下一次绘制之前，因此不产生可见跳变。
2. **本机装备槽**（`source_zone == "equipment"` 且来源是本机）：经 `equipment_label.find_card_global_rect()` 取槽位矩形；装备行不是 `CardView`，所以只给位置，`card_view` 为 null。
3. **其他角色**：沿用 `_try_get_player_indicator_position()` 的武将牌中心；座位缺失时 `valid=false`。
4. **公共区域**（`draw_pile` / `processing` / `discard_pile`）：中央弃牌锚点。

**明确不改**：`_get_player_indicator_position()` 的语义保持原样。它是**目标指示线**的唯一本机锚点，被 `ui_layout_test` 断言；本入口只服务飞牌起点。

### 3.5 `MatchTable._should_show_card_back()`：唯一的牌背判定入口

把现在内联在 `_on_card_transfer_requested():4751` 的表达式提取为函数：

```gdscript
## 判断一次区域转移是否只能显示牌背。牌堆方向对所有人隐藏；
## 手牌／木牛方向只对「既非来源本人、也非目标本人」的观察者隐藏，公开弃牌始终显示正面。
func _should_show_card_back(source_player_id: int, source_zone: String,
                            target_player_id: int, target_zone: String) -> bool
```

本机获得、他人获得、展示三条路径共用它，避免「改了一处忘了另一处」导致的私有牌面泄露。

### 3.6 `MatchTable` 本机手牌入场门闸

新增唯一一份门闸状态：

```gdscript
## 本机获得牌的前置飞行门闸；键为实体 UID，值固定为 true。
## 门闸存在期间，对应正式手牌节点必须停留在手牌区右侧入场点，不得提前滑入或出现在最终槽位。
## 门闸只由飞行落地回调解除，因此检查器里调整飞行时长不会破坏两段衔接。
var _local_hand_gain_flight_gates: Dictionary = {}
```

配套三个私有函数（不再增加第四个）：

| 函数 | 作用 |
|---|---|
| `_play_local_hand_gain_flight(card_uid, card_data, source_player_id, source_zone) -> bool` | 判断该次获得是否需要前置飞行；需要时登记门闸并调用既有 `play_transfer()`（落地回调解除门闸），返回是否创建了飞行段 |
| `_finish_local_hand_gain_flight(card_uid)` | 解除门闸并再次尝试启动手牌入场 |
| `_hold_gated_local_hand_entries()` | 把仍被门闸挡住的手牌节点固定在右侧入场点（复用 `_get_local_hand_gain_start_global_position()`），使其既不在槽位、也不在屏幕内 |

`_start_pending_local_hand_gain_animations()` 增加一条早退：**门闸存在则保留 UID 并跳过**，不消耗待入场登记。

`_start_local_hand_gain_animation()` **不需要改**：它已经用 `target_position = card_view.position - card_view.hand_entry_offset` 扣除已有偏移（`match_table.gd:4829`），因此「门闸期间预先写入的偏移」会被正确识别为本次补间起点。

门闸的判定矩阵：

| 场景 | 前置飞行段 | 门闸 | 落地回调 |
|---|---|---|---|
| 本机从弃牌堆/其他角色区域获得（含【浮辰】类效果、【顺手牵羊】、五谷取得） | 有，来源锚点 → 手牌区右侧入场点 | 有 | 解除门闸 |
| 本机 `draw()` 批次摸牌（真实对局主路径） | 有（既有牌背批次），落点为手牌区顶边中心 | 有 | 解除门闸 |
| 本机非批次摸牌（兼容路径 / 测试） | 无 | 无 | — |
| 其他角色获得 | 有（既有逻辑，来源 → 其武将牌） | 不适用 | — |

### 3.7 `CardView.hand_layout_offset`：第三个可叠加偏移

```gdscript
## 手牌整理过渡偏移；容器在槽位变化时把该牌视觉上留在原槽位所需的补偿量，由容器补间回零。
## 与 hand_entry_offset、hand_selection_offset 同构：写入差量而不是绝对值，任意时刻三者可叠加。
var hand_layout_offset: Vector2 = Vector2.ZERO:
	set(value):
		position += value - hand_layout_offset
		hand_layout_offset = value
```

用「偏移属性 + 补间归零」而不是「直接补间 position」，原因是容器每次布局都会绝对写入 `position`；只有偏移量才能在布局重算之间保持视觉连续性，并与既有入场/选中动画正交叠加。

### 3.8 `DecadeHandContainer` 槽位过渡

新增状态与配置：

```gdscript
## 手牌槽位变化后的过渡时长；默认0.18秒与弃牌队列补位时长一致，运行时可由主题调整。
@export_range(0.05, 0.8, 0.01) var relayout_animation_seconds: float = 0.18

## 卡牌实例 ID 到上一次写入的“槽位左上角”的映射；槽位不含悬停放大补偿，
## 因此悬停不会产生任何过渡动画。
var _slot_positions: Dictionary = {}

## 卡牌实例 ID 到整理过渡补间的映射；同一张牌同时只保留一条补间。
var _relayout_tweens: Dictionary = {}
```

`_layout_cards()` 的写入段改为：

```
slot_position = Vector2(current_card_x, maxf(base_y, 0.0))          # 不含悬停补偿
previous_slot  = _slot_positions.get(card.get_instance_id())

若 previous_slot 不存在（新牌）或该牌正在被拖动：
    归零 hand_layout_offset 并终止残留补间      # 新牌由入场动画负责，拖动牌由鼠标负责
否则若 previous_slot 与 slot_position 不同：
    hand_layout_offset += previous_slot - slot_position   # 先留在原处
    重建整理补间，把 hand_layout_offset 补间回零

写入 card.position = slot_position + 悬停补偿 + hand_entry_offset + hand_selection_offset + hand_layout_offset
_slot_positions[id] = slot_position
```

要点：

- **悬停补偿排除在槽位之外**，所以悬停一张牌不会让其余牌产生过渡，也不会让被悬停牌自己产生过渡（沿用「悬停不改变其他手牌位置」的既有约定）。
- **偏移是累加的**：整理补间未播完又来一次布局时，`previous_slot + 当前残量 - 新槽位` 正好等于「从当前位置过渡到新槽位」所需补偿，不会跳变。
- **清理**：每轮布局结束时移除已不在容器中的实例 ID 的槽位记录与补间；`_exit_tree()` 终止全部残留补间。`cards.is_empty()` 的早退分支同样执行清理。
- 结构签名命中时仍然直接 `return`，零开销。

---

## 4. 调用点改造

| 调用点 | 改造 |
|---|---|
| `_on_card_transfer_requested` → `target_zone == "discard_pile"` | 经 `_try_take_card_origin()` 取来源；命中活跃手牌节点则直接交给 `play_card()` 接管（起点＝该牌原位置）；否则按来源矩形新建表现牌。既有去重、认领、处理区早退顺序全部保持不变 |
| `_on_card_transfer_requested` → `is_local_gain` | 先登记待入场 UID；再用 `_play_local_hand_gain_flight()` 决定是否加门闸；随后调用一次 `_start_pending_local_hand_gain_animations()` |
| `_on_card_transfer_requested` → 其他转移 | 用 `_try_take_card_origin()` 替换手写的来源锚点判断；命中活跃节点则直接交给 `play_transfer()`；牌背用 `_should_show_card_back()` |
| `_on_card_presentation_requested` | `presentation_only` 新建副本时，若有更精确的来源矩形则用它摆放节点；**目标指示线锚点仍用原 `start_position`**，`_get_player_indicator_position()` 语义不变 |
| `_on_draw_presentation_batch_finished` | 目标为本机时，先为每个摸到的 UID 登记待入场并加门闸；批次飞行传入落地回调统一解除 |
| `_render_local_hand` | `layout_cards_now()` → `_hold_gated_local_hand_entries()` → `_start_pending_local_hand_gain_animations()`；不在快照中的 UID 同时清掉门闸 |
| `_clear_local_hand_gain_animations` | 一并清空门闸 |

**顺序不变式（必须保持）**：去重/认领判定 → 处理区早退 → 目标区域边界 → 表现创建。本次改造只替换「起点从哪里来」，不调整任何分支顺序，因此表现 ID 幂等、UID 所有权消费、回放重演的行为一致性都不受影响。

---

## 5. 兼容性、回滚与风险

| 风险 | 处置 |
|---|---|
| 接管活跃手牌节点后 `_render_local_hand()` 误释放它 | 释放条件已要求 `get_parent() == hand_container`；接管后父节点是动画层，条件不成立。同时 `_card_views` 在下一次对账整体替换，映射自然失效 |
| 接管节点后残留的 `hand_entry_offset` / `hand_selection_offset` 让起飞点偏移 | 在入口解析函数内归零两个偏移（属性写入会同步移动 `position`），归零后再读取矩形 |
| 门闸残留导致手牌永远不滑入 | 三处兜底：快照中不再出现该 UID 时清除、重新开局统一清除、门闸只由落地回调解除且回调带代次校验；`_start_pending_local_hand_gain_animations()` 对无门闸的 UID 行为完全不变 |
| 真实摸牌同时出现「牌背飞向手牌区」与「手牌滑入」两段重叠 | 批次门闸让手牌滑入在牌背落地后才开始，两段串行 |
| 整理补间与入场/选中补间争用 `position` | 三者都通过各自的偏移属性增量写入，容器每次布局都把它们一起求和写入，互不覆盖 |
| 拖动中的牌被整理动画改写位置 | 拖动牌跳过过渡并归零该偏移 |
| 回放重演表现与录制端不一致 | 回放复用同一批处理函数（`match_table.gd:1506-1510`），门闸与门闸解除都在同一入口内，无需新增回放步骤 |
| 需要回滚 | 改动集中在 5 个 UI 脚本 + 1 个测试文件；`git revert` 单个提交即可，规则层与内容层无关联改动 |

---

## 6. 参数一览（全部前置暴露）

| 参数 | 位置 | 默认值 | 说明 |
|---|---|---|---|
| `relayout_animation_seconds` | `DecadeHandContainer` | `0.18` | 手牌槽位过渡时长，与弃牌队列补位时长一致 |
| `hand_layout_offset` | `CardView` | `Vector2.ZERO` | 第三个可叠加偏移，由容器唯一维护 |
| `local_hand_gain_duration` | `MatchTable`（既有） | `0.24` | 手牌右侧滑入时长，不变 |
| `local_hand_gain_entry_margin` | `MatchTable`（既有） | `24.0` | 右侧入场外扩距离，不变 |
| `card_flight_duration` | `CardUseAnimationLayer`（既有） | `0.42` | 非摸牌转移飞行时长，新的获得飞行段复用 |
| `draw_flight_duration` | `CardUseAnimationLayer`（既有） | `0.24` | 摸牌批次飞行时长，不变 |

不引入任何新的魔法数字；新增量只有 `relayout_animation_seconds` 一个可调项。

---

## 7. 测试设计

在既有 `tests/ui_layout_test.gd` 内扩展（不新建测试场景，避免 README 与测试矩阵膨胀）：

1. **本机获得牌（来源＝他人手牌）**：改造既有 `local_gain_entity` 断言——转移信号后动画层持有 1 张飞行牌、手牌节点被门闸固定在右侧入场点且尚无入场补间；等待落地与滑入后飞行牌释放、`hand_entry_offset` 归零。
2. **本机非批次摸牌**：既有 `local_draw_entity` 断言保持（无前置飞行、立即滑入）。
3. **本机批次摸牌**：新增——`_on_draw_presentation_batch_finished` 后本机 UID 登记待入场并处于门闸状态，批次落地回调解除后滑入。
4. **弃置本机手牌**：新增——记录原手牌节点全局矩形 → 触发 `hand → discard_pile` 转移 → 断言该节点父节点变为动画层、属于 `_active_cards`、且其全局位置仍等于记录的矩形位置（即从原位起飞）。
5. **弃置本机装备**：新增——在装备栏装入一张牌 → 触发 `equipment → discard_pile` 转移 → 断言飞行牌起点等于该槽位矩形中心。
6. **展示本机手牌**：新增——触发 `showCards` → 断言新建展示牌面起点等于该手牌在原位置的矩形中心。
7. **手牌整理过渡**：新增——手牌两张时移除第一张并刷新快照 → 断言存活手牌 `hand_layout_offset` 非零；等待 `relayout_animation_seconds` 后归零，且最终位置与纯布局结果一致。
8. **悬停不触发整理**：新增——悬停一张手牌后断言其余手牌 `hand_layout_offset` 仍为零。

异步断言统一用条件等待 + 兜底超时，不用固定墙钟等待（遵循 `.trellis/spec/project/verification.md`）。

---

## 8. 文档同步清单

| 文档 | 变更 |
|---|---|
| `docs/游戏机制与玩法内容.md` | 改写第 983 条「本机进入手牌区的牌都不创建临时转移牌」为新的三段式口径；在表现段落补充离场原位起飞、手牌整理过渡时长与悬停不触发过渡 |
| `docs/界面与交互.md` | 同步手牌区与动画表现描述 |
| `docs/内容制作指南.md` | 新增可复用接口条目：`_try_take_card_origin()`、`_should_show_card_back()`、`play_transfer()`/`play_draw_transfer_batch()` 的落地回调参数、`CardView.hand_layout_offset`、`EquipmentStackView.find_card_global_rect()` |
| `README.md` | 更新 `ui_layout_test.tscn` 的覆盖说明 |
| `.trellis/spec/ui/component-patterns.md` | 视觉规格表新增「手牌整理过渡 0.18 秒」；常见错误表新增「在别处重写来源位置解析」「本机获得只登记待入场不加门闸」两条 |
| `临时反馈文档.md` | 追加学习反馈摘要与 Git 提交描述 |
