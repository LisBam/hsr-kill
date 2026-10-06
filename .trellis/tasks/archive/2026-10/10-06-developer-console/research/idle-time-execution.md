# 调研：「当前结算完毕后的空闲时间」如何在架构内表达

> 来源：只读代码/文档检索，未修改任何文件。关键行号均由 read 工具直接核对，非推测。
> 结论用途：为开发者菜单确定「效果延后到结算空闲边界执行」的唯一正确机制。

---

## 1. 结论先行

**唯一正确机制 = 在 `MatchController` 新增一条纯数据待办队列，由统一结算管线在既有优先级链的末端消费，并用既有的唯一延后唤醒（`_schedule_settlement_pipeline_resume()`）驱动。**

这与项目已有的三条队列结构完全同构：

| 既有队列 | 语义 | 消费位置 |
|---|---|---|
| `_deferred_skill_settlements` | 技能自行声明的「然后」步骤 | 优先级链倒数第二位 |
| `_rule_continuations` | 通用规则后半段（父流程恢复） | 优先级链中段 |
| `_queued_equipment_triggers` | 装备排队触发 | 优先级链前段 |
| **`_developer_effects`（新增）** | **外部注入的调试效果** | **优先级链最末端** |

不新增第二条推进路径、不新增计时器、不新增轮询。

---

## 2. 既有的唯一延后唤醒机制（逐字核对）

`scripts/core/match_controller.gd:2737–2747`
```gdscript
## 登记唯一的延后结算唤醒；多个技能、时机或停滞修复同帧请求时只保留一个call_deferred。
## 唤醒实际通过process_frame跨帧执行；直接接管和离树时释放连接，代次校验作为额外的过期回调保护。
func _schedule_settlement_pipeline_resume() -> void:
	if _settlement_resume_scheduled or state == null or state.game_over or not is_inside_tree():
		return
	_settlement_resume_scheduled = true
	_settlement_resume_generation += 1
	# 本次延后唤醒捕获的对局代次；重开或拆除后与当前值不等时直接失效。
	var resume_generation: int = _settlement_resume_generation
	_settlement_resume_callback = _run_scheduled_settlement_pipeline_resume.bind(resume_generation)
	get_tree().process_frame.connect(_settlement_resume_callback, CONNECT_ONE_SHOT)
```

`scripts/core/match_controller.gd:2750–2755`
```gdscript
## 执行已登记的延后结算唤醒；只有代次一致的唯一任务能重新进入管线。
func _run_scheduled_settlement_pipeline_resume(resume_generation: int) -> void:
	if resume_generation != _settlement_resume_generation:
		return
	_invalidate_scheduled_settlement_resume()
	_resume_settlement_pipeline()
```

要点：
- 去重标志 `_settlement_resume_scheduled`，同帧多次请求只保留一个。
- 跨帧手段是 `get_tree().process_frame` + `CONNECT_ONE_SHOT`（**不是** `call_deferred`）。
- 代次 `_settlement_resume_generation` 让重开 / 拆除 / 显式恢复后的旧回调自动失效。
- `_invalidate_scheduled_settlement_resume()`（`:2768`）显式断开信号，不只清布尔值。
- `_exit_tree()`（`:2777`）释放唤醒连接。

**复用本机制 = 免费获得跨帧语义 + 去重 + 重开失效 + 离树清理。** 任何自建方案都要重新实现这四件事。

---

## 3. 为什么其它候选机制都不成立

### 3.1 `Callable.call_deferred` —— 被文档明确否定

`docs/战斗结算框架.md:63`：
> `call_deferred` 可能在同一空闲轮继续排空，**不能作为跨帧证据**。

### 3.2 `RuleContinuationQueue` —— 语义与白名单都不允许

`match_controller.gd:150–167`：
```gdscript
## 统一结算管线允许的通用规则续接类型；字符串不在此表时于登记阶段局部拒绝，避免无处理分支的记录静默丢失。
const RULE_CONTINUATION_TYPES: Array[String] = [
	"rule_sequence",
	"skill_response",
	"card_response",
	"equipment_response",
	"trick_negation_response",
	"simultaneous_negation_response",
	"slash_flow",
	"recast_draw",
	"current_player_death",
	"round_end_restore",
	"round_end_after_restore",
	"conquest_enemy_defeat",
	"conquest_enemy_replacement",
	"opportunity_resolution",
	"ahha_moment_resolution",
]
```
白名单在登记阶段**局部拒绝**未知类型；`_run_settlement_pipeline_pass()` 内对续接有专门的 `continuation_type` 分支（含 `conquest_*` 的角色生命周期边界处理）。该队列的语义是**「父流程恢复」**，不是「外部效果注入」。塞新类型需要同时改常量表与 `match` 分支，且会与既有的最内层优先（LIFO）语义冲突。

### 3.3 `defer_skill_settlement()` —— 需要真实技能对象

`match_controller.gd:12626–12644` 的登记内容包含 `skill_owner_id` / `skill_id` / `skill_character_generation` / `settlement_key` / `settlement_visits` / `chain_step_count`，恢复时（`_resume_deferred_skill_settlements`，`:12650`）要求能解析出真实 `SkillDefinition` 并校验 `matches_character_generation` 与 `can_use_effect`。开发者菜单没有技能实例，**不可用**。

### 3.4 `GameFlowPacer` —— 计时器，完全不感知事件树

`scripts/core/game_flow_pacer.gd`（71 行）：
```
schedule(task_key, delay_seconds, callback, process_always = false) -> int   # :14
cancel() -> void                                                             # :28
cancel_all() -> void                                                         # :33
has_pending() -> bool                                                        # :38
has_any_pending() -> bool                                                    # :43
has_pending_skill_interval() -> bool                                         # :49
```
它只管理「计时到期后调用回调」。计时到期时事件可能仍在结算中；要在回调里补一道闸就必须手写 idle 轮询——而项目**刻意避免**这种模式（`docs/战斗框架回归说明.md` 记录的「零进展活锁」：登记了待办却没有任何路径消费它，界面表现为永久卡住）。

### 3.5 `EventScheduler.scheduler_idle` —— 零订阅者的既有钩子，但不等价

`scripts/core/event_scheduler.gd`：
```gdscript
signal scheduler_idle()      # :31
```
在 `drain()` 内于 `_event_stack.is_empty() and not _stop_requested` 时发出（`:244–245`）。

全项目检索确认：**该信号目前零订阅者**，是一个未被使用的既有钩子。

**为什么仍然不用它**：
1. 「事件栈为空」≠「控制器没有待办」。`_has_unresolved_settlement_work()` 还要看技能「然后」、规则续接、装备触发、触发管理器的延后派发四类队列。
2. 控制器还有独立子阶段门控（`_rule_sequence_execution_depth > 0`、`_conquest_replacement_transition_active`、`game_flow_pacer.has_pending_skill_interval()`）。
3. 用它仍要叠加上述判据，等于在管线之外重建一套「是否空闲」的近似判断，与统一管线的唯一权威地位冲突。
4. 即便采用，也无法复用「唯一唤醒 + 代次失效」的去重与清理保障。

**唯一有价值的用法**：作为**测试断言**的观测点（等待事件栈排空），不用于生产推进。

### 3.6 `resume_settlement_pipeline()` —— 公开但为同步排空

`match_controller.gd:2730–2734`
```gdscript
## 供技能流程间隔到期后重新进入统一结算管线；已有选择、判定或终局时内部入口会安全忽略。
func resume_settlement_pipeline() -> void:
	_resume_settlement_pipeline()
	if event_scheduler != null:
		event_scheduler.drain()
```
它在**当前调用栈内**同步排空，因此不适合作为「登记后延后执行」的驱动——会越过调用方尚未完成的收尾逻辑。既有的三条队列全部采用「登记 + 唯一延后唤醒」而非同步排空。

---

## 4. 管线的固定优先级链与插入点（逐字核对）

`scripts/core/match_controller.gd:13000–13017`
```gdscript
## 按触发、装备、规则后半段、技能后续的固定优先级排空当前结算，最后才恢复阶段或父牌游标。
func _resume_settlement_pipeline() -> void:
	# 技能回调内重新请求结算时不得递归进入同一管线；唯一延后唤醒会在当前调用栈退出后重试。
	if _settlement_pipeline_running:
		_schedule_settlement_pipeline_resume()
		return
	# 直接安全出口比已登记的空闲帧任务更早进入时，立即使旧任务代次失效，避免它在测试重置或下一业务状态中空跑。
	if _settlement_resume_scheduled:
		_invalidate_scheduled_settlement_resume()
	_settlement_pipeline_running = true
	_run_settlement_pipeline_pass()
	_settlement_pipeline_running = false
	# 活跃性保证：本轮入口已经作废旧的唯一延后唤醒，而本次同步排空可能因为独立子阶段、待选请求或待判定
	# 门控提前返回且一项都没有消费。此时若队列仍有明确待办，就必须立刻重新登记唤醒；
	# 否则“管线内登记延后结算不自行登记唤醒”与“本轮入口作废旧唤醒”会叠加成永久滞留，
	# 表现为额外出牌阶段内技能“然后”步骤不结算、后续阶段无法推进。
	if _has_unresolved_settlement_work():
		_schedule_settlement_pipeline_resume()
```

`scripts/core/match_controller.gd:13027–13039`
```gdscript
## 判断统一结算管线是否仍有必须由延后唤醒补齐的待办；供活跃性保证决定是否重新登记唤醒。
##
## 待选请求与待判定各自拥有明确的“收到响应后重驱管线”入口，等待它们期间由响应路径负责恢复，
## 因此这两种阻塞存在时返回false，避免人类思考期间出现每帧空跑的唤醒。
## 其余队列（技能“然后”步骤、规则续接、装备排队触发、触发管理器的延后派发）都只能靠唤醒推进。
func _has_unresolved_settlement_work() -> bool:
	if state == null or state.game_over:
		return false
	if has_pending_card_choice() or has_pending_judgment_request():
		return false
	if not _deferred_skill_settlements.is_empty() or _rule_continuations.has_pending() or not _queued_equipment_triggers.is_empty():
		return true
	return trigger_manager != null and trigger_manager.has_deferred_dispatches()
```

`scripts/core/match_controller.gd:13042–13062`（入口门控）
```gdscript
func _run_settlement_pipeline_pass() -> void:
	if state == null or state.game_over or _rule_sequence_execution_depth > 0:
		return
	if _conquest_replacement_transition_active:
		...
		return
	if has_pending_card_choice():
		return
	# 技能安排的可见结果停留仍是当前结算的一部分；回调完成后会重新调用本入口。
	if game_flow_pacer != null and game_flow_pacer.has_pending_skill_interval():
		return
	var settlement_step_count: int = 0
	while state != null and not state.game_over and not has_pending_card_choice() and not _conquest_replacement_transition_active and (game_flow_pacer == null or not game_flow_pacer.has_pending_skill_interval()) and settlement_step_count < max_settlement_steps_per_pass:
```

`scripts/core/match_controller.gd:13139–13143`（**优先级链末端 —— 插入点**）
```gdscript
		# 技能自行声明的“然后”步骤保持登记顺序，每项之后重新检查触发、装备与通用规则续接。
		if not _deferred_skill_settlements.is_empty():
			_resume_deferred_skill_settlements()
			continue
		break
```

`scripts/core/match_controller.gd:13144–13154`（单帧预算复查与阶段恢复后复查）
```gdscript
	# 达到单帧保护上限时仍有明确队列，下一帧只继续同一管线；未完成后续绝不交给阶段游标或父牌兼容入口。
	if settlement_step_count >= max_settlement_steps_per_pass and (not _queued_equipment_triggers.is_empty() or _rule_continuations.has_pending() or not _deferred_skill_settlements.is_empty() or (trigger_manager != null and trigger_manager.has_deferred_dispatches())):
		_schedule_settlement_pipeline_resume()
		return
	if state != null and not state.game_over and not has_pending_card_choice() and not has_pending_judgment_request() and not _conquest_replacement_transition_active and (game_flow_pacer == null or not game_flow_pacer.has_pending_skill_interval()):
		if state == null or state.game_over or has_pending_card_choice() or has_pending_judgment_request():
			return
		_resume_interrupted_turn_flow()
		# 阶段恢复可能刚刚完成额外弃牌阶段并暴露新的技能“然后”步骤；延后一帧再次排空，避免后续额外出牌阶段被嵌套询问吞掉。
		if not has_pending_card_choice() and (not _queued_equipment_triggers.is_empty() or _rule_continuations.has_pending() or not _deferred_skill_settlements.is_empty() or (trigger_manager != null and trigger_manager.has_deferred_dispatches())):
			_schedule_settlement_pipeline_resume()
```

### 插入点判定

| 位置 | 是否合适 | 原因 |
|---|---|---|
| 优先级链最前端（触发之前） | ✗ | 会越过未完成的触发续列，破坏既有结算顺序 |
| 装备触发与规则续接之间 | ✗ | 同上；且规则续接是「父流程恢复」，必须优先 |
| `_deferred_skill_settlements` 之前 | ✗ | 技能「然后」是当前结算的组成部分，不是外部效果 |
| **`_deferred_skill_settlements` 之后、`break` 之前** | **✓** | 此刻触发续列、装备触发、规则续接、技能「然后」均已排空 —— 正是需求要求的「当前结算完毕后的空闲时间」 |
| `break` 之后（阶段恢复之前） | ✗ | 不在 `while` 内，无法 `continue` 重跑优先级链；且会与阶段恢复交错 |

---

## 5. 必须一并处理的四类门控（否则永久滞留）

### 5.1 `_has_unresolved_settlement_work()` —— **必需，不是优化**

`_resume_settlement_pipeline()` 入口会**作废**已登记的唤醒（`:13007–13008`）。若本次同步排空因为待选 / 子阶段门控**一项都没消费**提前返回，而开发者队列又没被算进「仍有待办」，则：
- 唤醒已被作废；
- 没有新的唤醒被登记；
- 队列永远不被消费 → **永久滞留**。

这正是 `:13012–13015` 注释记录的陷阱。因此挂钩 4（把 `_developer_effects.has_pending()` 加入 `:13037`）是**强制项**。

### 5.2 单帧预算复查（`:13145`）

达到 `max_settlement_steps_per_pass` 时，若队列非空必须重新登记唤醒，否则要等下一次无关唤醒才会继续。

### 5.3 阶段恢复后复查（`:13153`）

`_resume_interrupted_turn_flow()` 可能暴露新待办；此处同样要复查开发者队列。

### 5.4 待选 / 待判定期间不消费（语义正确，无需改）

- `_run_settlement_pipeline_pass()` 在 `has_pending_card_choice()` 时提前返回（`:13055`）。
- `_has_unresolved_settlement_work()` 在待选 / 待判定时返回 `false`（`:13035–13036`），**刻意**避免人类思考期间每帧空跑。

因此「有待办选择时提交开发者效果」的自然行为就是**排队**：不消费、不登记唤醒，等响应路径恢复管线时才轮到它。这正好满足需求，且界面必须显示排队数，否则看起来像没反应。

---

## 6. 清理点（与 `_rule_continuations` 同批）

`_rule_continuations.reset()` 出现的全部 5 处（grep 确认）：
| 行 | 所在函数 |
|---|---|
| `:1694` | `_teardown_previous_match_runtime()`（`:1664`） |
| `:1767` | `_reset_per_match_progress_state()`（`:1755`） |
| `:1854` | 放弃对局 / 半成品回滚路径 |
| `:16131` | 换将 / 生命周期重置路径 |
| `:16160` | 同上 |

新队列在每一处之后追加 `_developer_effects.reset()`，即可覆盖重新开局、放弃对局、节点离场与换将重置。

另有 `_reset_settlement_runtime_guard()`（`:2781–2787`）统一「使全部旧延后唤醒失效」，新队列无需在此单独处理（唤醒失效由代次机制自动覆盖），但若队列持有跨对局载荷则应一并清理——本设计采用「5 处 reset」已足够，且 `match_id` 复核作为额外防线。

---

## 7. 未决 / 需实现期实测的假设

1. `_resume_settlement_pipeline()` 确实在**每一次**选择提交后被调用（grep 到 14 处调用点，含 `:3508` 一带的响应路径），从而保证待办选择完成后开发者队列会被继续消费。
2. 开发者效果若自身创建了待办选择（弃牌走 `adjust_hand_size`），`while` 条件立即为假并退出，剩余条目留待响应后消费 —— 与既有 `_resume_deferred_skill_settlements()` 的行为一致（`docs/内容制作指南.md:2311` 一带记录了 `request_*_selection()` 在已有待办选择时**静默返回空**、不排队、不报错）。
3. `_run_settlement_pipeline_pass()` 在 `_rule_sequence_execution_depth > 0` 时提前返回，意味着开发者效果在规则序列执行期间不会插入 —— 语义正确（那本身也是结算进行中）。
