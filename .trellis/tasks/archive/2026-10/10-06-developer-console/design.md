# 技术设计：开发者设置与开发者菜单（单机局内调试控制台）

> 对应需求：`prd.md`（R1–R7 / AC1–AC18 / D1–D11）
> 目标读者：实现者与评审者。本文只描述**边界、契约、数据流、权衡**，执行顺序见 `implement.md`。

---

## 1. 设计目标

| 目标 | 含义 |
|---|---|
| 零新增数值结算 | 9 项效果全部调用既有控制器端口，开发者菜单内**不出现任何** `hp -= n` / `max_hp += n` / `shield = ...` 之类的直接状态写入 |
| 零第二套推进路径 | 空闲时间执行复用统一结算管线的既有优先级链与唯一帧唤醒，不新增计时器、不新增 `call_deferred`、不新增 `process` 轮询 |
| 零新增快照字段 | 目标列表取自既有 `players` 快照；摸牌堆牌面与武将目录走既有只读端口 / 静态数据库 |
| 单向依赖不破 | `MatchController` 不知道 UI；`DeveloperConsolePanel` 不知道规则状态；`MatchTable` 是唯一中介 |
| 离线特权硬门控 | 入口在 `NetworkGateway.Mode.OFFLINE` 之外不可达（`docs/内容制作指南.md:12`） |
| 可数据化扩展 | 新增一项效果 = 追加一条效果声明，不改窗口构建代码 |

---

## 2. 分层与职责边界

```text
┌─ ui 层 ─────────────────────────────────────────────────────────────┐
│ MatchMenu（既有）                                                    │
│   · 新增「开发者设置」按钮 + signal developer_settings_requested      │
│   · 仅按 _offline_controls_visible 显隐；不持有窗口、不读控制器        │
│                                                                     │
│ DeveloperConsolePanel（新增，无状态表现组件）                          │
│   · 渲染目标列表 / 效果行 / 第二层窗口 / 状态反馈                       │
│   · 只发意图信号；只读 GameDatabase 静态定义（既有惯例）                 │
│   · 不读 GameState / MatchController                                  │
│                                                                     │
│ MatchTable（既有，桌面协调器）                                         │
│   · 装配窗口、注入快照派生的活数据、转发意图到控制器                      │
│   · 主题刷新、焦点、关闭清理                                            │
└─────────────────────────────────────────────────────────────────────┘
                              ↕ 只读查询 / 只提交请求
┌─ core 层 ───────────────────────────────────────────────────────────┐
│ MatchController（既有，只做薄端口与管线挂钩）                            │
│   · request_developer_effect(kind, player_id, amount) -> bool         │
│   · get_developer_effect_pending_count() -> int                       │
│   · _run_settlement_pipeline_pass() 末端消费队列                       │
│                                                                     │
│ DeveloperEffectService（新增，单一职责服务组件）                        │
│   · 纯数据待办队列 + 按 kind 分派到既有规则端口                          │
└─────────────────────────────────────────────────────────────────────┘
```

### 关键边界决策

- **为什么队列放在 core 层而不是 UI 层**：需求要求「当前结算完毕后的空闲时间执行」。UI 层无法观测结算边界，也无法参与管线推进。把队列放进结算管线是项目唯一被验证过的做法（`_deferred_skill_settlements` / `_rule_continuations` / `_queued_equipment_triggers` 三条先例）。
- **为什么拆出 `DeveloperEffectService`**：`.trellis/spec/core/index.md` 要求「新增逻辑优先落在单一职责服务组件中，而非继续膨胀 `MatchController`」（该文件已 18564 行）。服务类形态与既有 `DrawResolutionService.new(self)` / `RecoveryResolutionService.new(self)` 一致，`MatchController` 只保留 3 处薄挂钩。
- **为什么静态武将目录由面板自己读 `GameDatabase`**：这是既有惯例。`CardSelectionPanel` 收到规则层下发的 `card_data` 后自行调用 `GameDatabase.get_card(definition_id)`；`AllCardsPanel` 也直接读 `GameDatabase.characters`。因此「活数据注入、静态定义自取」是本项目已确立的 UI 数据边界，不构成对 UI 层禁令的破坏。
- **为什么不复用 `CardSelectionPanel` 承载「获得牌堆指定牌」**：`CardSelectionPanel` 是 `main.tscn` 中的常驻单例节点，绑定规则层的 `show_request(choice_request)` / `choice_submitted(request_id, selected_card_uids)` 协议。若把开发者选择塞进同一节点，会与真实待办选择互相覆盖。**只复用其交互形态**（牌面网格 + 选中态 + `min_select`/`max_select` 判定 + 确定/取消），在开发者菜单内部实现为子视图。

---

## 3. 新增与修改文件清单

### 新增

| 文件 | 类型 | 职责 |
|---|---|---|
| `scripts/core/developer_effect_service.gd` | `class_name DeveloperEffectService extends RefCounted` | 开发者效果待办队列；纯数据登记、代次校验、按 kind 分派到既有规则端口 |
| `scripts/ui/developer_console_panel.gd` | `class_name DeveloperConsolePanel extends Control` | 开发者菜单窗口：遮罩、目标选择、9 项效果行、两个第二层窗口、状态反馈、主题刷新 |
| `scenes/components/developer_console_panel.tscn` | 极简场景（照 `card_selection_panel.tscn`，约 15 行） | 只声明根 `Control`（全屏锚点）+ 挂脚本 + `@export` 默认值 |

> 第二层窗口（牌堆选牌 / 换将选将）**不单独建场景**，作为 `DeveloperConsolePanel` 的内部子视图由代码构建，避免为纯表现分片引入额外装配点。

### 修改

| 文件 | 改动 |
|---|---|
| `scenes/main.tscn` | `MatchMenu/MenuPanel/MenuVBox` 内、`MenuReturnToMainButton` 之前插入 `MenuDeveloperSettingsButton`（`visible = false`、`custom_minimum_size = Vector2(0, 32)`、`text = "开发者设置"`、`unique_name_in_owner = true`、**新的未占用 `unique_id`**） |
| `scripts/ui/match_menu.gd` | 新增 signal、`@onready` 引用、`_ready()` 连接、`refresh_ui_style()` 上色、离线显隐（含 `release_focus()`）、`_request_developer_settings()` |
| `scripts/ui/match_table.gd` | 新增 `preload` 常量、`_create_developer_console_panel()`、菜单信号连接、`_on_developer_settings_requested()`、`_on_developer_console_effect_requested()` 等转发、快照→目标列表投影、主题刷新调用、返回主菜单时关闭窗口 |
| `scripts/core/match_controller.gd` | 新增 `_developer_effects` 成员、`request_developer_effect()`、`get_developer_effect_pending_count()`、管线末端消费分支、`_has_unresolved_settlement_work()` 判据、5 处 `reset()` 清理点 |
| `docs/界面与交互.md` | 入口、显隐条件、窗口结构、`z_index` 表新增 `520`、第二层窗口规格 |
| `docs/游戏机制与玩法内容.md` | 新增「开发者菜单」章节，记录全部数值与执行时序规则 |
| `docs/架构说明.md` | 开发者请求队列与空闲边界端口、离线特权表面边界 |

---

## 4. 契约定义

### 4.1 开发者效果键（`effect_kind`）

集中在一处常量表中，作为 `core` 与 `ui` 之间的**唯一稳定协议**（字符串常量，不依赖枚举跨层序列化）：

| kind | 语义 | 目标端口调用 |
|---|---|---|
| `draw` | 摸牌 | `draw(target, amount)` |
| `discard` | 自选弃置 | `adjust_hand_size(target, hand.size() - amount)` |
| `recover` | 回复体力 | `recover(-1, target, amount)` |
| `lose_hp` | 失去体力 | `lose_hp(-1, target, amount)` |
| `damage` | 无来源普通伤害 | `damage(-1, target, amount)` |
| `gain_max_hp` | 增加体力上限 | `change_max_hp(target, amount)` |
| `lose_max_hp` | 减少体力上限 | `change_max_hp(target, -amount)` |
| `gain_shield` | 获得护盾 | `shield(target, amount)` |
| `lose_shield` | 失去护盾 | `change_hujia(target, -amount)` |
| `gain_draw_pile_card` | 获得摸牌堆指定牌（`amount` 不使用，牌 UID 列表另传） | 逐张 `gain_draw_pile_card_by_uid(target, uid)` |
| `replace_character` | 更换武将（`amount` 不使用，武将 ID 另传） | `replace_player_character_card(target, character_id)` |

> 「获得牌堆指定牌」与「更换武将」的载荷是**列表 / 字符串**而非数值，因此队列条目使用通用字典载荷（`amount` 与 `payload` 二选一），而不是给它们硬凑一个 `amount`。

### 4.2 `DeveloperEffectService`

```gdscript
class_name DeveloperEffectService
extends RefCounted

## 开发者效果待办上限；超过时拒绝新请求，避免误操作或脚本循环把队列撑成无界内存。
const MAX_PENDING_EFFECTS: int = 64

## 绑定宿主控制器；服务不持有规则状态，一切读写都经宿主公开端口。
func _init(host_controller: Node = null) -> void

## 登记一条开发者效果；只接受纯数据载荷，登记时校验对局有效性与目标存在性。
## 返回 false 表示未受理（无对局 / 已终局 / 队列已满 / 目标不存在）。
func enqueue(effect_kind: String, target_player_id: int, amount: int, match_id: String, payload: Dictionary = {}) -> bool

## 是否有待执行的开发者效果；供控制器管线活跃性判据与界面计数使用。
func has_pending() -> bool

## 待执行数量；供界面显示「已排队 N 项」，不暴露队列本体。
func pending_count() -> int

## 消费一条待办效果；返回 true 表示本轮消费了一条（调用方应 continue 重跑管线）。
## 代次不符或目标已失效的条目在此静默丢弃并写一条开发者日志。
func resume_next() -> bool

## 丢弃全部待办；重新开局、放弃对局、节点离场共用。
func reset() -> void

## 清空队列并返回被丢弃的条数；用于界面在重开局后提示，不参与规则。
func drain_discarded() -> int
```

**契约要点**

1. **只接受纯数据**：队列条目为 `{kind, target_player_id, amount, match_id, payload}`，全部是 `String`/`int`/`Dictionary`。禁止存入 `PlayerState`、`CardInstance`、节点或 `Callable`（`.trellis/spec/core/index.md` 质量检查项）。
2. **登记时校验、执行时复校**：`enqueue()` 校验「对局存在 + 未终局 + 目标玩家存在」；`resume_next()` 再校验 `match_id` 与目标玩家仍然存在（R7.7）。
3. **一次只消费一条**：`resume_next()` 每次最多消费一条并返回 `true`，由管线的 `continue` 重新回到优先级链顶端。这样「弃牌」产生的待办选择能让管线在正确位置退出，且下一条效果必然等到该选择完成后才执行（R7.8）。
4. **返回值语义**：`resume_next()` 内部按端口返回值区分「已生效 / 未生效」，并通过宿主的开发者日志端口记录，供界面状态行读取。

### 4.3 `MatchController` 新增端口

```gdscript
## 开发者效果待办服务；与规则续接队列同生命周期，重开与拆除时统一重置。
var _developer_effects: DeveloperEffectService = DeveloperEffectService.new()

## 提交一条开发者效果请求；离线特权表面，联机模式下由调用方保证不可达。
## 返回 true 表示已受理（可能仍在排队），false 表示未受理。
func request_developer_effect(effect_kind: String, target_player_id: int, amount: int, payload: Dictionary = {}) -> bool

## 返回当前待执行的开发者效果数量；只读诊断，供界面显示排队状态。
func get_developer_effect_pending_count() -> int
```

> **实现期修订（阶段 1）**：上面成员声明处的 `DeveloperEffectService.new()` **改为惰性创建**。
>
> ```gdscript
> ## 开发者效果待办服务；构造时需要宿主控制器，因此惰性创建并缓存。
> var _developer_effects: DeveloperEffectService = null
>
> ## 取得开发者效果待办服务；首次访问时以 self 为宿主创建。
> func _get_developer_effects() -> DeveloperEffectService:
> 	if _developer_effects == null:
> 		_developer_effects = DeveloperEffectService.new(self)
> 	return _developer_effects
> ```
>
> 原因：`DeveloperEffectService` 需要在构造时接收宿主控制器（`_init(host_controller)`，与 `recovery_resolution_service.gd` 等服务同构），而**成员初始化阶段拿不到可用的 `self`**——在 `var` 声明处调用 `DeveloperEffectService.new(self)` 会拿到尚未完成初始化的对象。`RuleContinuationQueue` 之所以能直接在声明处 `new()`，正是因为它的构造不需要宿主。所有挂钩点与端口一律经 `_get_developer_effects()` 访问，不再直接读成员。

`request_developer_effect()` 的实现骨架 —— **登记尾部必须逐字对齐 `defer_skill_settlement()` 的既有形态**（`match_controller.gd:12640–12645`），不自创第二套唤醒策略：

```gdscript
func request_developer_effect(effect_kind: String, target_player_id: int, amount: int, payload: Dictionary = {}) -> bool:
	if state == null or state.game_over:
		return false
	# 开发者菜单是离线特权表面；联机（含房主）一律拒绝，与 docs/内容制作指南.md:12 一致。
	if network_gateway != null and network_gateway.mode != NetworkGateway.Mode.OFFLINE:
		return false
	if not _developer_effects.enqueue(effect_kind, target_player_id, amount, state.match_id, payload):
		return false
	# 与 defer_skill_settlement() 同构：已在管线内时当前 while 会自然取下一项；否则登记唯一延后唤醒。
	# 注意“已在管线内”并不保证当次循环一定能消费到本项——排空可能因为待选请求或子阶段提前返回，
	# 且管线入口会作废旧唤醒，因此活跃性由 _resume_settlement_pipeline() 末尾的待办复查统一兜底
	# （前提是挂钩 4 已把开发者队列纳入 _has_unresolved_settlement_work()）。
	if not _settlement_pipeline_running and not has_pending_card_choice():
		_schedule_settlement_pipeline_resume()
	return true
```

> **为什么用 `_schedule_settlement_pipeline_resume()` 而不是 `_resume_settlement_pipeline()`**：后者是同步排空入口，在 `submit_action()` / 技能回调等深调用栈中被调用会把整条结算链推进到当前栈内，可能越过调用方尚未完成的收尾逻辑。项目既有的三条队列（技能「然后」、规则续接、装备触发）**全部**采用「登记 + 唯一延后唤醒」而非同步排空，本设计沿用该约定。
> **为什么不在登记后无条件登记唤醒**：`_schedule_settlement_pipeline_resume()` 自带 `_settlement_resume_scheduled` 去重（`:2740`），无条件调用本身无害，但会掩盖「已在管线内时无需唤醒」的语义，并让 `_resume_settlement_pipeline()` 末尾的活跃性兜底失去意义。保持与既有形态一致便于日后对照维护。

> **实现期修订（阶段 1 收尾）**：上面骨架里的 **`network_gateway.mode != OFFLINE` 拒绝**与**尾部唤醒登记**都是**必需项**，二者在首轮实现中一度被漏掉，均由回归用例抓回：
>
> - 漏掉唤醒登记 → 新增用例 `_test_idle_submission_wakes_pipeline()` 失败（`idle_wakeup_missing`）。原用例 `_test_effect_deferred_to_idle_boundary()` 之所以没抓到，是因为它在入队后**手工调用了 `resume_settlement_pipeline()`**，替被测代码完成了「驱动管线」这一步，从而掩盖了缺陷。新用例改为只提交请求并 `await get_tree().process_frame`。
> - 漏掉联机拒绝 → `_test_queue_validation_guards()` 新增断言：切到 `NetworkGateway.Mode.LAN` 后端口必须返回 `false` 且队列不增长，切回 `OFFLINE` 后必须恢复受理（后半句用于证明拒绝来自联机判定，而不是端口整体失效）。
>
> 结论：**「首次唤醒」与「重新唤醒」是两个不同职责**——尾部这一句负责「管线根本没在跑」，挂钩 4 负责「管线在跑但本轮零消费提前返回」。只实现其中一个，都会得到「只在特定初始状态下偶然可用」的功能。

### 4.4 管线挂钩（3 处，缺一不可）

**挂钩 1 — 消费点**：`_run_settlement_pipeline_pass()` 的 `while` 内，位于 `_deferred_skill_settlements` 分支之后、`break` 之前（当前 `match_controller.gd:13139–13143`）：

```gdscript
		# 技能自行声明的“然后”步骤保持登记顺序，每项之后重新检查触发、装备与通用规则续接。
		if not _deferred_skill_settlements.is_empty():
			_resume_deferred_skill_settlements()
			continue
		# 开发者效果排在全部规则待办之后：此刻触发续列、装备触发、规则续接、技能“然后”均已排空，
		# 正是需求要求的“当前结算完毕后的空闲时间”。
		if _developer_effects.has_pending():
			_developer_effects.resume_next()
			continue
		break
```

**挂钩 2 — 单帧预算复查**（当前 `:13145`）：把 `_developer_effects.has_pending()` 加入该 `if` 的判据，否则达到 `max_settlement_steps_per_pass` 时队列会被搁置到下一次无关唤醒。

**挂钩 3 — 阶段恢复后复查**（当前 `:13153`）：同上，把 `_developer_effects.has_pending()` 加入判据。

**挂钩 4 — 活跃性判据**：`_has_unresolved_settlement_work()`（当前 `:13032–13039`）加入 `_developer_effects.has_pending()`：

```gdscript
	if not _deferred_skill_settlements.is_empty() or _rule_continuations.has_pending() or not _queued_equipment_triggers.is_empty() or _developer_effects.has_pending():
		return true
```

> 这一条是**必需**的，不是优化：`_resume_settlement_pipeline()` 入口会作废已登记的帧唤醒，若同步排空因待选/子阶段门控提前返回而一条都没消费，而没有把开发者队列算进「仍有待办」，就会形成永久滞留（既有注释 `:13012–13015` 记录了这个陷阱）。

**挂钩 5 — 清理点**：在 `_rule_continuations.reset()` 出现的全部 5 处（当前 `:1694`、`:1767`、`:1854`、`:16131`、`:16160`）之后追加 `_developer_effects.reset()`。复用同一批既有清理入口，保证重新开局 / 放弃对局 / 换将重置 / 节点离场都覆盖。

### 4.5 各 kind 的执行映射（服务内分派）

**关键前提：规则端口分「同步返回值」与「异步无返回值」两类**，二者反馈方式必须不同。

| kind | 执行 | 生效判定 |
|---|---|---|
| `draw` | `host.draw(target, amount)` | **异步**：`draw()` 内部 `preload(draw_resolution_service).new(self).draw(...)` 只登记规则序列，实体在后续时机窗口才移动。→ 报「已提交」，结果由权威日志与刷新后的快照体现 |
| `discard` | `host.adjust_hand_size(target, hand.size() - amount)` | 返回 `bool`；`true` 表示已受理（可能创建待办选择），实际弃置数由后续快照反映 |
| `recover` | `host.recover(-1, target, amount)` | **异步**：`recover()` 内部 `recovery_resolution_service` 同样只登记序列，`hp` 不会同步变化。→ 报「已提交」；仅用公开字段 `hp >= max_hp` 做**提交前提示**「体力已满，预计未生效」 |
| `lose_hp` | `host.lose_hp(-1, target, amount)` | 直接使用返回的 `int` 实际失去值（0 → 未生效） |
| `damage` | `host.damage(-1, target, amount)` | **异步**：`damage()` 依次派发多级时机窗口，扣血发生在窗口之后。→ 报「已提交」，结果由日志体现 |
| `gain_max_hp` | `host.change_max_hp(target, amount)` | 直接使用返回的 `int` |
| `lose_max_hp` | `host.change_max_hp(target, -amount)` | 直接使用返回的 `int`；注意权威端把减少量钳制为「至少保留 1 点上限」（`:4509`），返回的 `int` 已反映钳制结果 |
| `gain_shield` | `host.shield(target, amount)` | 直接使用返回的 `int` |
| `lose_shield` | `host.change_hujia(target, -amount)` | 直接使用返回的 `int`（返回负数，取绝对值显示） |
| `gain_draw_pile_card` | 逐张 `host.gain_draw_pile_card_by_uid(target, uid)` | 统计非 `null` 返回值的张数 |
| `replace_character` | `host.replace_player_character_card(target, character_id)` | 返回 `bool` |

> **必须区分同步 / 异步的原因**：所有规则端口在死亡 / 离场 / 非正数 / 满体力等条件下**静默早退**（无错误、无日志、无信号）。若界面只按「点击成功」反馈，开发者无法区分「排队中」「已生效但数值为 0」「规则拒绝」，会误判为功能损坏（AC7 明确要求满体力时报告「未生效」）。
> 但 `draw` / `recover` / `damage` 是 **`-> void` 且异步登记规则序列**的端口，执行后**同步读到的 `hand.size()` / `hp` 必然与执行前相同**，用「前后对比」判定会把成功误报成失败。因此：
> 1. 有返回值的端口一律用返回值判定，**不在服务内复制任何规则公式**（例如伤害的护盾优先扣减不在此处重算）。
> 2. 无返回值的端口只报「已提交」，真实结果由控制器既有的 `add_log`（`recover` / `lose_hp` / `shield` / `damage` 都会写权威日志）与下一次 `state_changed` 快照体现。
> 3. 可选的**提交前提示**只读公开字段（`hp >= max_hp`、`shield <= 0`、`hand.is_empty()`），属于「表现判断」，不参与规则决策，权威端仍会独立复核（符合 `cross-layer-thinking-guide.md`「校验一次，在权威入口；UI 只做候选可点击性的表现判断」）。
> 4. 提交后**不做** `refresh_state_snapshot()` 的同步强制刷新期待；异步端口的状态变化会经既有 `_emit_state()` 自然到达界面。

### 4.6 UI ↔ 协调器契约

`DeveloperConsolePanel` 对外只暴露意图信号与注入方法：

```gdscript
## 请求关闭开发者菜单；桌面负责隐藏、归还焦点并清理第二层窗口。
signal close_requested

## 请求执行一条数值效果；协调器转交控制器。
## effect_kind 为稳定字符串，amount 为当前输入值，target_player_id 为当前选中目标。
signal effect_requested(effect_kind: String, target_player_id: int, amount: int)

## 请求从摸牌堆获得指定牌；uids 为所选实体 UID 列表。
signal draw_pile_gain_requested(target_player_id: int, uids: Array[int])

## 请求更换指定目标的武将。
signal character_replace_requested(target_player_id: int, character_id: String)

## 请求协调器注入摸牌堆牌面候选；窗口不自行读取牌堆。
signal draw_pile_candidates_requested

## 注入由快照派生的目标候选；每项含 player_id / display_text / is_local。
func set_target_candidates(candidates: Array[Dictionary], preferred_player_id: int) -> void

## 注入摸牌堆全量牌面候选（由协调器经控制器只读端口取得）。
func set_draw_pile_candidates(candidates: Array[Dictionary]) -> void

## 注入待执行效果数量与最近一次执行结果，供状态行显示。
func set_pending_count(pending_count: int) -> void
func set_status_text(status_text: String) -> void

## 打开窗口并进入指定视图（主视图 / 牌堆选牌 / 换将选将）。
func open_console() -> void
func close_console() -> void

## 按当前 UI 风格重绘全部样式；主题切换时由协调器调用。
func refresh_ui_style() -> void
```

**数据流（数值效果）**

```text
MatchTable._snapshot.players ──投影──> set_target_candidates() ──> 目标 OptionButton
用户点「摸牌」按钮
  └─ effect_requested("draw", target_id, value)
       └─ MatchTable._on_developer_console_effect_requested()
            └─ match_controller.request_developer_effect("draw", target_id, value)
                 └─ DeveloperEffectService.enqueue(...) → 队列
                      └─ 管线空闲边界：resume_next() → host.draw(target, value)
                           └─ refresh_state_snapshot()
                                └─ MatchTable 收到 state_changed → set_pending_count()/set_status_text()
```

**数据流（获得摸牌堆指定牌）**

```text
用户点「获得牌堆中的指定牌」
  └─ 面板发出内部视图切换请求（面板自身不读规则状态）
       └─ MatchTable 调 match_controller.get_top_draw_card_candidates(local_human_player_id, draw_pile_count)
            └─ set_draw_pile_candidates() 注入
                 └─ 用户多选 → draw_pile_gain_requested(target_id, uids)
                      └─ request_developer_effect("gain_draw_pile_card", target_id, 0, {"uids": uids})
```

> **`get_top_draw_card_candidates(viewer_id, count)` 可原样复用**（`match_controller.gd:9034`）：它按「数组末尾为牌堆顶」的顺序返回 `count` 张，内部 `mini(count, draw_pile.size())` 钳制；当 `count == draw_pile.size()` 时**不会触发重洗**（重洗条件是 `size() < count`）。因此传入快照中的 `draw_pile_count` 即可获得全量牌面且**不改动牌堆**（满足 R5.6）。
> 返回的每项形如 `{"uid", "owner_id", "zone", "slot", "visible", "card_data"}`，`card_data` 含 `definition_id` / `suit` / `rank`（`_serialize_choice_candidate`，`:6810`），面板据此自取 `GameDatabase.get_card()` 渲染牌面。

**数据流（更换武将）**

```text
用户点「更换武将」
  └─ 面板自 GameDatabase.characters 构建列表（静态定义，既有惯例）
       └─ 用户单选 → character_replace_requested(target_id, character_id)
            └─ request_developer_effect("replace_character", target_id, 0, {"character_id": id})
```

---

## 5. 关键时序设计

### 5.1 什么算「当前结算完毕后的空闲时间」

**定义**：统一结算管线到达优先级链末端（`_deferred_skill_settlements` 也排空）且 `while` 循环没有因门控提前返回的那一刻。

**不是**：`event_scheduler` 事件栈为空、`_process` 空闲帧、`GameFlowPacer` 计时到期。项目不存在统一 `is_idle()` 谓词，轮询式判定会与管线脱节。

**为什么不用 `GameFlowPacer` 计时器**：pacer 完全不感知事件树，计时到期时事件可能仍在结算中。要在回调里补一道闸就得手写 idle 轮询——正是项目刻意避免的模式（`docs/战斗框架回归说明.md` 记录的「零进展活锁」）。且 `Callable.call_deferred` 被 `docs/战斗结算框架.md:63` 明文否定为跨帧证据。

### 5.2 排队与抢占的边界（D6）

- 存在待办选择（`has_pending_card_choice()`）或待判定时，`_run_settlement_pipeline_pass()` 在 `:13055` 提前返回，开发者效果**不会被消费**，只留在队列里。
- 玩家/响应路径提交后调用 `_resume_settlement_pipeline()`（既有 14 处调用点之一，如 `:3508`），管线重新进入，此时才轮到开发者效果。
- 因此「待办选择期间点击效果」的自然行为是**排队**，符合 D6，且无需额外代码——但**界面必须显示排队数**（R7.5 / AC14），否则看起来像没反应。

### 5.3 多效果连续提交

- 每次 `resume_next()` 只消费一条，随后 `continue` 回到优先级链顶端。
- 若某条效果（弃牌）创建了待办选择，`while` 条件立即为假并退出；剩余条目留在队列，由响应路径恢复管线时继续消费。
- 因此「按点击顺序逐个在结算边界生效」由结构保证，不需要额外的顺序号。

### 5.4 重开 / 终局安全

- 队列在 5 处既有清理点被 `reset()`，与 `_rule_continuations` 同批。
- 帧唤醒由既有 `_settlement_resume_generation` 代次机制自动失效，无需额外代码（这正是选择复用 `_schedule_settlement_pipeline_resume()` 的收益）。
- `resume_next()` 仍以 `match_id` 复核作为额外防线（R7.7）。

---

## 6. 界面设计要点

### 6.1 入口（`MatchMenu`）

- 按钮为 `MenuVBox` 直接子节点，插在 `MenuReturnToMainButton` 之前。
- 显隐遵循「控制所有角色」的既有范式：由 `set_offline_controls_visible()` 与 `set_authority_controls_visible()` **两边都重算**（后者被调用时若不重算，按钮会在 LAN 客户端残留可见），实现上抽一个私有 `_refresh_developer_entry_visibility()` 由两个 setter 调用。
- 隐藏时 `release_focus()`。
- 点击后先关闭菜单面板再 `emit`，与 `_request_chat_toggle()` 一致。

#### ⚠️ 竖向空间已接近饱和 —— 必须先实测

`MenuPanel` 是**固定锚定高度**的 `PanelContainer`（`main.tscn:266–280`，`anchors_preset = 11`、`offset_top = 65.0`、`offset_bottom = -27.0`），其内部 `MenuVBox` 是**普通 `VBoxContainer`，没有 `ScrollContainer`**，且 `clip_contents` 未开启。

静态核算（按 `main.tscn` 中已声明的 `custom_minimum_size` / `font_size` 累加，取整数近似）：

| 项 | 值 |
|---|---|
| `MenuVBox` 全部子节点最小高度合计 | ≈ **669 px** |
| 身份模式下被隐藏的行（座次补偿 26 + 过关斩将 30+30 + 车轮战 34+34） | −154 px |
| 身份模式可见内容合计（含 `separation = 1` × 20） | ≈ **515 px** |
| 设计分辨率 1152×648 下 `MenuPanel` 可用高度（648 − 65 − 27） | **556 px** |
| 当前余量 | ≈ **41 px** |
| 新增一个 32px 按钮 + 1px 间距 | **−33 px** → 余量 ≈ **8 px** |

**结论：理论可行但余量极小，且 Label 实际行高依赖字体度量，8px 的估算误差足以导致溢出。** 一旦溢出，`MenuPanel` 作为 `PanelContainer` 会按最小尺寸向下撑出锚定矩形，最后一个子节点 `MenuReturnToMainButton` 会落到屏幕底边之外，玩家无法点击「返回主菜单」。

**因此阶段 2 必须把「实测」作为硬门（见 `implement.md` 2.2b）**，用一次性 headless 检查打印 1152×648 下的
`MenuPanel.size`、`MenuVBox.get_combined_minimum_size()`、各可见子节点的 `get_rect()`，确认插入后最后一个子节点的 `rect.end.y ≤ 视口高度`。

**若余量不足，按以下优先级回退：**

1. **首选回退**：新增 `MenuBottomButtonRow`（`HBoxContainer`）承载 `MenuReturnToMainButton` 与 `MenuDeveloperSettingsButton` 并排，**额外高度为 0**。因为 `match_menu.gd` 与测试都通过 `%` 唯一名引用这两个按钮，改父节点不影响 `%` 解析；但需复核是否有按绝对路径 `MenuVBox/MenuReturnToMainButton` 取值的地方（grep 确认无）。
2. **次选回退**：把新按钮高度降到 24px 并核对是否足够。
3. **不采用**：给 `MenuVBox` 外套 `ScrollContainer` —— 会破坏 `match_menu.gd:416–445` 中大量 `_menu_panel.get_node("MenuVBox/...")` 绝对路径，改动面远大于收益。

注意：该按钮**仅在纯离线模式可见**，局域网下布局与改动前完全一致，因此回退影响面只限单机。

#### ✅ 实现期结论（阶段 2.2b 实测）：**采用了首选回退 1**

实测数据（权威 1280×720 逻辑画布，未叠加 `canvas_items` 拉伸的敌对用例为 1152×648）：

| 项 | 实测值 |
|---|---|
| 竖排方案（新按钮堆在 `MenuReturnToMainButton` 之上） | `MenuVBox` 最小高度 570 → **606**，`MenuPanel` 高 620 且 `position.y = 33` → 底边 **653 > 648**，`pre_game_customization_test` 的 `encloses()` 断言失败（`settings_content_overflow`） |
| 并排方案（`MenuBottomButtonRow`） | `MenuVBox` 最小高度回到 **570**，`MenuPanel` 为 `(994, 65) 268×628`，行位于 `y = 535` 高 35，最后一个可见子节点底边 **642**，余量 **58 px** |
| 两个按钮各自宽度 | 122 px（最小 106 px），无截断 |

因此**竖排方案的静态估算（余量 8 px）过于乐观**：Label 实际行高依赖字体度量，估算误差直接导致溢出。最终实现采用首选回退 1，`MenuReturnToMainButton` 与 `MenuDeveloperSettingsButton` 并排于 `MenuBottomButtonRow`，额外高度为 0，几何与改动前逐像素一致。`%` 唯一名解析不受改父节点影响（已 grep 确认无 `MenuVBox/MenuReturnToMainButton` 绝对路径取值）。

### 6.2 开发者菜单窗口（`DeveloperConsolePanel`）

- 根 `Control` 全屏锚点；内部：全屏 `ColorRect` 遮罩（`MOUSE_FILTER_STOP`，色取 `BattleUIStyle.get_color("shade")`）+ 居中 `PanelContainer`（`BattleUIStyle.make_inset_panel()`）。
- `z_index = CONSOLE_Z_INDEX = 520`；`process_mode` 与 `MatchMenu` 一致（继承），因为局内菜单在 `GameplayPauseService` 暂停期间本就不可达，窗口无需更宽的可操作性。
- 内容区用 `ScrollContainer` + `VBoxContainer`：标题行 → 目标选择行 → 分隔 → 9 个效果行 → 分隔 → 2 个纯按钮行 → 状态行。
- 效果行结构：`Button`（固定宽度，文本为效果名）+ `HSlider`（`min 1` / `max 10` / `step 1`）+ 数值输入框（无上限，最小 1）。三者在同一 `HBoxContainer` 内。
- 数值输入框采用项目既有「文本优先」取值惯例（`lan_lobby_panel.gd:157` / `match_menu.gd:290`）：以 `LineEdit` 承载，读取时 `text.to_int()` 优先、非法或空则回退拖条值、只对下限 `1` 做钳制、**不设上限**。使用 `SpinBox` 也可行，但需把 `max_value` 设为哨兵并处理「静默写入不刷新内部 LineEdit 文本」的既有陷阱，`LineEdit` 更直接。
- 同步用 `set_value_no_signal()` 切断回环（项目全局惯例）。
- 第二层窗口在窗口内部以子视图形式切换（同一个遮罩内替换内容），而不是再叠一层全屏遮罩，避免层级与 Esc 优先级复杂化。
- Esc 处理：`_unhandled_input` 中先判断第二层子视图是否打开 → 先关子视图；否则发 `close_requested`；两种情况都 `set_input_as_handled()`。安卓返回键同理。
- 样式：按钮一律 `BattleUIStyle.apply_interaction_button()`；滑条照 `main_menu.gd:1824 _apply_slider_style()`；文本输入照 `all_cards_panel.gd:920 _apply_line_edit_style()`；新增 `Label` 必须纳入统一字体色覆盖，否则 `font_color_audit_test` 失败。
- 实现 `refresh_ui_style()`（`if not is_node_ready(): return` 开头），订阅 `GameSettings.ui_style_changed`。

> **实现期修订（阶段 3 / 5）**，共四处：
>
> 1. **`process_mode` 改为 `PROCESS_MODE_ALWAYS`**（原文为「与 `MatchMenu` 一致，继承」）。原判断「局内菜单在暂停期间本就不可达」只覆盖了**打开**窗口的路径，没有覆盖**打开之后**才发生暂停的情况：一旦对局在窗口打开期间被暂停，继承模式会让 `_unhandled_input` 停止工作，玩家既关不掉窗口也点不动「返回」，被困在模态遮罩后面。改为 `ALWAYS` 后唯一的差别是「暂停期间仍可关闭窗口」，严格更安全。
> 2. **不自行订阅 `GameSettings.ui_style_changed`**，改由 `MatchTable._apply_ui_style()` 统一调用 `developer_console_panel.refresh_ui_style()`。牌桌已经是全部组件的样式扇出点（`match_menu.refresh_ui_style()`、`main_menu.refresh_ui_style()` 同处一行），组件各自订阅会让同一份样式被重绘两次。
> 3. **数值回环用「单向同步」切断，而不是 `set_value_no_signal()`**：滑条 `value_changed` → 写入输入框 `text`（程序化写 `LineEdit.text` **不会**触发 `text_changed`），输入框不回写滑条。因此不存在回环，也不需要抑制信号；输入框始终是真实数值的唯一持有者。
> 4. **`draw_pile_candidates_requested` 信号**为契约必需项（见 §4.6）：窗口不读牌堆，必须在进入第二层视图时向协调器索取牌面，否则摸牌堆选牌视图永远拿不到候选。该信号在 `_open_view(View.DRAW_PILE)` 中先 `emit`，协调器在本次信号内同步回填 `set_draw_pile_candidates()`，随后视图才切到前台。
>
> 另外补充两条实现约定：换将候选网格**只在进入该视图时才构建**（武将池接近两百项，窗口创建时预建会拖慢每次进局的界面初始化）；`CheckBox` 换成 `toggle_mode = true` 的 `Button`，避开 `docs/界面与交互.md:114` 要求的自定义指示器约束。

### 6.3 效果行数据化（D10 / AC18）

效果声明集中在脚本顶部常量数组，每项 `{kind, label, uses_amount}`；窗口构建与信号分发都遍历该数组，`uses_amount = false` 的两项（获得牌堆指定牌、更换武将）渲染为纯按钮行。新增效果只需追加一项声明 + 在服务内补一个 `match` 分支。

### 6.4 目标列表

- 由 `MatchTable` 从 `_snapshot.players` 投影：`player_id`、`display_text`（`武将名（玩家名）`，武将未公开时只显示玩家名，复用 `GameDatabase.resolve_character_name()`）、`is_local`。
- 刷新时保留当前选择；仅当该 `player_id` 不在新列表中时回退到 `match_controller.local_human_player_id`。

---

## 7. 权衡与备选方案

| 决策 | 选择 | 被否方案与原因 |
|---|---|---|
| 延后执行机制 | 统一结算管线末端新队列（D8） | `GameFlowPacer` 计时器 + 手动 idle 闸：pacer 不感知事件树，需手写轮询，项目明令避免；`RuleContinuationQueue`：白名单严格且语义是「父流程恢复」，塞新类型要同时改常量与 `match` 分支，语义不符；`defer_skill_settlement`：要求真实 `SkillDefinition` 实例，控制台没有；`EventScheduler.scheduler_idle`：零订阅者的既有钩子，但事件栈空 ≠ 控制器队列空，仍需叠加判据，收益不明显 |
| 跨帧唤醒 | 复用 `_schedule_settlement_pipeline_resume()` | 自建 `call_deferred` / `create_timer`：前者被文档否定为跨帧证据，后者需要自己接 3 套清理机制 |
| 弃牌实现 | `adjust_hand_size()`（D3） | 自建 `request_card_choice` + 新 `context.kind`：恢复分派器不认识新 kind，请求**永久挂起**；`discard_n_from_player()`：不让玩家选择，不满足需求 |
| 面板数据 | 活数据注入 + 静态定义自取 | 全注入：`MatchTable` 继续膨胀；全自取：面板会读 `GameState`，违反 UI 层禁令 |
| 牌堆选牌窗口 | 面板内部子视图，复用 `CardSelectionPanel` 的交互形态（D9） | 直接实例化 `CardSelectionPanel`：与规则层选择协议冲突 |
| 窗口暂停 | **暂停**（D5 已反转，2026-10-06 修订）：打开即申请对局暂停令牌，绑定窗口 `visibility_changed` 释放 | 最初的「不暂停」判断基于「暂停会让空闲时间永不到来」；实测该担心不成立——结算管线入口 `_run_settlement_pipeline_pass()` 不检查对局暂停，唤醒走 `SceneTree.process_frame`（该信号在暂停期间照常发出），因此同步端口与异步端口在暂停期间都照常生效 |

---

## 8. 兼容性与回归风险

| 风险 | 说明 | 缓解 |
|---|---|---|
| 破坏结算管线优先级 | 新增消费点插错位置会越过未完成的结算去推进阶段 | 消费点固定插在 `_deferred_skill_settlements` 之后、`break` 之前；跑 `event_runtime_test` / `phase_progression_test` |
| 队列滞留 | 未加入 `_has_unresolved_settlement_work()` 会导致登记后永不执行 | 挂钩 4 为必需项；用「待办选择期间提交效果」场景验证（AC14） |
| 单帧预算搁置 | 未加入 `:13145` / `:13153` 判据时，达到预算上限会搁置队列 | 挂钩 2、3 |
| 重开后旧效果生效 | 队列未清理 | 5 处 `reset()`；用「有待办时重开」场景验证（AC15） |
| LAN 泄漏 | 入口在房主可见 → 联机中操控他人角色，违反 `内容制作指南.md:12` | 入口由 `_offline_controls_visible` 门控；`request_developer_effect()` 自身也以 `NetworkGateway.Mode.OFFLINE` 复核（纵深防御） |
| UI 层越界 | 面板读 `GameState` / `MatchController` | AC16 检查；面板只发信号 + 读 `GameDatabase` 静态定义 |
| 字体色审计失败 | 新增 `Label` / `Button` 未纳入主题 | 一律经 `BattleUIStyle` 上色；跑 `font_color_audit_test` |
| 布局回归 | `MenuPanel` 是固定锚定高度且 `MenuVBox` 无滚动容器，竖向余量仅约 41px（详见 §6.1）；插入 33px 可能把 `MenuReturnToMainButton` 撑出屏幕。开发者窗口在 1152×648 下也可能溢出 | 阶段 2 硬门：先实测余量再决定是否走 §6.1 的回退方案；窗口内容全部放入 `ScrollContainer`；跑 `ui_layout_test` |
| 既有测试的节点路径 | `tests/main_menu_test.gd:194/340` 等按绝对路径取 `MenuVBox` 子节点；`match_menu.gd:416–445` 也用 `MenuVBox/...` 绝对路径 | 新按钮插在按钮区（绝对路径按名字取，不受索引影响）；§6.1 回退方案 1 只改父节点，已 grep 确认 `MenuReturnToMainButton` / `MenuConquestExitButton` 仅经 `%` 引用 |
| 快照刷新 | 效果生效后界面未更新 | 每次 `resume_next()` 后调 `refresh_state_snapshot()`（R7.9） |

---

## 9. 回滚形态

- 改动是**纯增量**：新增 2 个文件 + 1 个极简场景；`MatchController` 只新增成员/端口/一个 `if` 分支与 5 行 `reset()`；`MatchMenu` / `MatchTable` 只新增条目。
- 回滚 = 删除新增文件 + 撤销 `main.tscn` 的按钮节点 + 移除 `match_menu.gd` / `match_table.gd` / `match_controller.gd` 的增量块。无数据迁移、无存档格式变化、无网络协议变化。
- 队列为空时 `has_pending()` 恒为 `false`，管线行为与改动前逐位一致——这保证了「功能不用时零影响」。

---

## 10. 待实现期验证的假设

以下在设计中成立、但实现时需实测确认：

1. `_resume_settlement_pipeline()` 确实在**每一次**选择提交后被调用（`:3508` 等 14 处调用点覆盖 `_continue_card_choice` 路径），从而保证待办选择完成后开发者队列会被继续消费。
2. `_run_settlement_pipeline_pass()` 的 `while` 条件在开发者效果创建待办选择后立即为假（`not has_pending_card_choice()`），使队列自然暂停而非越界执行。
3. `get_top_draw_card_candidates(viewer_id, draw_pile_count)` 在 `draw_pile_count == 0` 时返回空数组且不触发重洗。
4. `ui_layout_test` 的几何断言不依赖 `MenuVBox` 的子节点数量或 `MenuPanel` 的最终高度。
5. `main.tscn` 手工插入节点后 Godot 能正常打开并保留 `unique_id`（若 `unique_id` 由编辑器生成而非必需，则省略该字段亦应可加载——实现时以编辑器实际行为为准）。
