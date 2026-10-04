# 事件运行时与阶段流程

> 权威来源：`docs/架构说明.md`「事件运行时边界」「停滞自修复边界」，`docs/内容制作指南.md`「事件步骤与阶段转换安全规范」「MatchController 私有技能、回合与判定调度」。

---

## 一、EventScheduler 步骤契约

`scripts/core/event_scheduler.gd` 维护：根事件、事件栈、`next`/`after` 队列、步骤游标、`goto`/`redo`、多通道暂停 token、选择请求与终局中断。

**每个 `GameEvent` 内容步骤执行后必须至少满足一项：**

1. 推进到下一步骤
2. 调用 `finish` / `cancel` / `neutralize` / `abort` 进入终态
3. 通过 `create_child()` 插入真实子事件
4. 通过 `request_choice()` 等入口取得暂停 token
5. 在明确修改有限游标后调用 `redo()` / `goto()`

**禁止**在没有上下文变化、子事件或暂停点时永久 `redo()`。

### 运行时硬上限

| 限制 | 值 | 超限行为 |
|---|---|---|
| 单次 `drain()` 操作数 | **256** | 延后一帧继续 |
| 同一事件同一步无等待连续重跑 | **2048** | 以 `runaway_step` 中断当前事件并继续父流程 |
| 新事件嵌套深度 | **32** | 熔断最内层事件并发出可序列化故障 |
| 同一 `RuleEvent` 对象重入 | 立即取消 | — |
| 触发器排序分片检查 | **64** 项/分片 | 分片让出 |

> **内容作者不得依赖「一个超大事件树必须在同一帧全部结束」。** 需要读取结果的逻辑应放在父事件后续步骤或 `after` 事件中。

### 终态与释放

- 事件状态区分 `finished`、`cancelled`、`neutralized`、`aborted`。
- 长期根事件通过 `held_open` 等待后续子树，**不占用暂停 token**，也不阻塞新阶段或卡牌事件。
- **无法构造任何合法提交**的单个选择可调用 `abort_choice()` 只中断所属事件并释放自己的暂停 token，**不扩大为整局中断**。
- 事件完成后立即释放含 `Callable`、可变上下文和步骤队列的完整 `GameEvent`；按 ID 快速查询只索引最多 **4096** 份最终摘要，旧事件从完整历史逆序恢复并提升回热索引。
- 同步 `record_event()` **只记录父 ID 关系**，不进入长期根事件的待执行队列。

### 诊断接口（只读）

| 接口 | 约束 |
|---|---|
| `EventScheduler.has_pending_drain_continuation()` | 只读诊断；**不得据此跳过规则步骤** |
| `EventScheduler.get_last_fault()` | 最近一次熔断的深拷贝摘要；空字典表示未发生，**不得用于修改事件状态** |

---

## 二、阶段推进（禁止直写状态）

- **禁止**内容脚本直接写 `GameState.current_phase` / `phase_index` / `current_player_id`。
- **禁止**直接调用 `GameFlowPacer.schedule("phase_transition", ...)`。
- 只能调用 `MatchController` 的**标准阶段 / 额外阶段端口**。

控制器 `_schedule_phase_transition()` 把「对局 ID + 回合 + 角色 + 当前阶段 + 目标方法」组成**稳定语义键**，交由 `GameFlowTransitionCoordinator` 管理唯一有效转换：

| 接口 | 约束 |
|---|---|
| `schedule_transition(key, delay, guard, callback)` | 登记唯一阶段转换；`guard` 在登记和到期各执行一次且**必须是纯查询**，`callback` 才能执行规则推进 |
| `cancel_pending(reason)` | 重开、失败开局或废弃阶段树时取消并释放运行时 `Callable` |
| `get_pending_snapshot()` | 只返回 `transition_id`/`transition_key` 的可序列化诊断摘要 |

行为保证：完全重复恢复**不重置等待时间**；同一阶段的冲突出口**不能覆盖先登记出口**；已经过期的角色或阶段恢复**在登记前直接拒绝**。

若 `GameFlowPacer` 已存在 `phase_transition`，恢复入口必须**幂等**并等待既定切换，**禁止以同一业务键覆盖已经排队的额外阶段**。

---

## 三、暂停机制

- `GameplayPauseService` 是对局级令牌暂停：首个调用方申请时保存原场景树暂停状态并暂停对局，最后一个调用方释放后恢复。
- `MatchController` 同步持有 `EventScheduler` 全局 token；所有 AI 调度与动作入口都查询同一状态。
- `GameFlowPacer` 只按业务键管理可取消计时器与回调令牌；**重新开局会取消全部旧任务**，场景暂停期间计时不推进。

> 新增任何等待型界面（详情面板、弹窗）都必须走令牌，不得自行 `get_tree().paused = true`。

---

## 四、时机派发与触发排序

- `RuleTimingCatalog` 是**无状态时机目录**：集中保存 **236** 个不重复监听事件、**4** 个主动技能入口，以及 `judgment/draw/play/discard` → `phaseJudge/phaseUse/...` 的唯一主要阶段时机前缀映射。它不做派发，只提供名称校验与稳定分类顺序。`GAME_PHASE_TIMINGS` 的数组顺序即规则流程顺序，`roundEnd` 固定紧邻 `roundStart` 之前。
  - **`gameStart` 的位置是「正式开局时刻」**：`enterGame → gameDrawBefore → gameDrawBegin → gameDrawAfter → gameStart → roundEnd → roundStart`，其中 `gameStart` 由 `MatchController._complete_pre_game_start()` 在**起始手牌与手气卡全部结束之后、第一轮之前**唯一派发（普通开局与手气卡结束共用这一出口）。因此要区分「开局配置阶段」与「正式开局」：希望可能被手气卡刷到的效果、或任何依赖起始手牌的配置，都必须发生在 `gameStart` **之前**；在 `gameStart` 里加入牌堆的牌**不可能进入任何一次手气卡重发**。
  - `gameStart` 同样是一次**正式技能发动**：内容应走 `announce_activation()`（写入 `skill_history`、公开日志与 `skillAfter` 时机），不得静默改写状态；并且 `context` 会成为公开快照字段，**不得放入牌面、位次等隐藏信息**。
- `RuleTimingService` 是标准时机派发组件：先调用兼容 `RuleEventBus`，再依据当前状态的存活座次把事件交给独立 `TriggerManager`，最后完成事件；**不执行任何具体牌效、伤害、移动或阶段逻辑**。
- `TriggerManager` 排序规则：先按 `player/source/target/global` 过滤技能持有者与 `RuleEvent` 角色关系，再按 `firstDo`/`lastDo` → 技能优先级 → 起始座次 → 注册顺序排列，并在执行前**重新检查所有者生命周期与动态条件**。
- **同一时机内部始终沿用初次排列**；回调内又创建暂停时机时，续列按**最内层优先**恢复。
- 权威流程边界（如阶段跳过）令旧时机失效时，`cancel_matching_dispatches()` 以稳定原因终止所有匹配事件；恢复器只清理终态续列，**不再执行剩余技能**。
- 同一规则时机出现多个可选技能时，`TriggerManager` 保存已排序续列，当前选择及其后续选择**完全恢复后**再从当前回合角色起按座次继续询问——**不能覆盖后续技能请求**。

---

## 五、续接队列（RuleContinuationQueue）

只保存稳定续接类型、可序列化上下文与统一结算因果链元数据的**后进先出**规则栈。

**核心边界：事实已经成立、结果尚未读取。**

- 同步规则在响应牌、费用牌、区域移动或回合开始时机已经成立后若插入新选择，**只登记尚未执行的后半段**。
- 恢复时**不重复消费实体牌、不重复发布已完成时机**。
- **不得保存** `Callable`、节点、`PlayerState` 或 `CardInstance` 引用。
- 控制器在入栈时校验**稳定类型白名单**；子续接继承当前因果链的语义键访问次数与总步数。
- 同一语义步骤默认最多 **16** 次；单条变化上下文因果链默认最多 **512** 步；异常自我入栈只**局部熔断**。
- **内容文件不得自行访问 `_rule_continuations`**；技能自己的「然后」步骤使用 `defer_settlement()`。

---

## 六、统一结算管线的固定恢复顺序

`_resume_settlement_pipeline()` 固定按以下顺序恢复，**每一步后重新检查新选择**：

```text
最内层同一时机续列
  → 当前判定子流程
  → 其余同一时机续列
  → 装备延后触发
  → 通用规则后半段
  → 技能登记后续（按原登记顺序）
  → 阶段 / 父牌游标
```

要点：

- 判定在创建它的**父时机剩余处理器之前**完成，避免异步判定被外层伤害流程越过。
- 通用规则后半段按**嵌套层级后进先出**；技能同层后续仍保持**原登记顺序**。
- 关卡换将（`conquest_enemy_replacement`）是角色生命周期边界：先排空已登记的技能「然后」步骤，再补齐活动目标 `End`/`After`，最后才冻结事件树换将。
- 阶段恢复若刚暴露新的技能后续，用**单调代次**只登记 1 条空闲帧唤醒，**不递归重入管线**，也不让重复 `call_deferred` 多次消费同一队列。
- 单帧默认最多处理 **256** 步（检查器可设 16~4096，步长 16），达到上限延后一帧。
- **屏障早退必须回答「被它挡住的条目由谁消费」。** 当栈顶父序列等待独立子阶段时，管线会早退以免越过外层时机；此时**由该子阶段技能登记的延后结算条目全部排在屏障之后**，永远不会被消费，形成「待办 > 0 而消费恒为 0」的**零进展活锁**——外部表现是「什么都没发生」（资源已扣、后续步骤不结算、`chooseToUse` 永不重建），**不是**转不停的死循环，因此不能靠「跑不动了」来发现。约定：延后条目入队时记录**登记时刻的活动独立阶段实例号**（不在任何独立阶段内为 `-1`），管线在屏障早退**之前**只排空「归属等于当前阶段实例号」的条目（`-1` 的父序列遗留一律不动，因此不改变外层时机顺序），排空后按与正常出牌阶段完全相同的方式重建出牌窗口。**不得**通过放宽屏障来修——那会以外层时机错序为代价。
- 上述排空必须**单帧封顶**（默认 **8** 次，检查器可设 1~64），达到上限且仍有同阶段残留时记录一次局部熔断。但熔断**不得**记在被轮询的诊断路径 `get_stall_diagnostics()` 上：故障计数参与停滞指纹（`_compose_stall_fingerprint()`），每次轮询都记会让指纹不断变化、不断刷新看门狗的停滞计时器，反而使强制修复**永不触发**并刷屏。诊断端口只做纯读取，熔断只记在真正异常的那条分支上。

---

## 七、回合开始游标

`_continue_turn_start()` 按**稳定回合开始游标**逐段发布：

```text
roundStart → phaseBefore → 翻面检查 → phaseBeforeStart → phaseBeforeEnd → phaseBeginStart → phaseBegin → phaseZhunbei
```

- 任一步创建选择时压入下一步，完成当前时机及其剩余处理器后才恢复。
- 因此【振旗】等回合前选择必须**完整结束后**才会进入【加护】等准备阶段选择，两者**不能共享或覆盖同一选择窗口**。
- `phaseBefore` 完成后若角色背面向上：翻回正面并**直接跳过整个回合**，不发布 `phaseBegin`、不运行六阶段主体。
- 只有依赖**实际回合开始**的效果才能在下一次真正进入 `phaseBegin` 时到期。

---

## 八、轮末边界游标（roundEnd）

普通回合结束、且行动顺序轮转**回到本轮轮锚点**时进入真实轮末边界；额外回合不进入。控制器用一个可暂停的 `run_rule_sequence` 依次执行：

```text
roundEnd（派发时机）
  → _restore_round_limited_out_of_game_players(round_number + 1)（恢复“直到本轮结束”的离场角色）
  → _continue_round_end_after_restore()（轮末机缘与下一回合安排）
```

**契约**：

| 项目 | 约定 |
|---|---|
| 派发入口 | `emit_sequence_timing(sequence, "roundEnd", finished_player_id, finished_player_id, finished_player_id, {...})`，因此处理者创建选择时整条轮末序列会等待其结算 |
| 事件数据 | `{round_number, finished_player_id, turn_number}`；`round_number` 是**刚结束**的那一轮（递增发生在下一次 `_start_turn`） |
| 每轮次数 | 每个真实轮末**恰好一次**；额外回合与“同轮内的额外出牌阶段”都不派发 |
| 顺序 | `roundEnd` **严格早于**下一轮的 `roundStart`；轮末机缘（机会/机缘结算）在恢复离场角色之后 |
| 续接类型 | 屏障出现在派发 `roundEnd` 之前 → `round_end_restore`（恢复后从 `_begin_round_end_boundary` 重新进入，**不得跳过** `roundEnd`）；屏障出现在恢复之后 → `round_end_after_restore`（直接进入 `_continue_round_end_after_restore`，**不得重复派发**） |
| 过期保护 | 两步都先校验 `state.current_player_id == finished_player_id`；等待期间换人结束回合时旧序列直接 `finish()` 且不改座次 |

> **内容作者要点**：需要“本轮结束才到期”的持续效果（如【补缀】发放的护盾），在 `install()` 中订阅 `roundEnd` 并用 `role="global"`；**不要把到期挂在下一轮 `roundStart`**（那会把“本轮”悄悄变成“下一轮”，并让额外回合语义出错）。同时注册 `maintenance=true` 并覆盖 `can_trigger_while_owner_inactive(event) -> true`，才能让持有者阵亡后仍完成一次清理。

> **Warning**：`roundEnd` 里创建的选择会真正暂停轮末流程；恢复后**不要**重新发一遍时机（见「常见错误」表）。

---

## 常见错误

| 错误 | 后果 |
|---|---|
| 写裸 `redo()` 等状态变化 | `runaway_step` 熔断，事件被打断 |
| 假设事件树单帧跑完 | 超过 256 步预算后被延后，后续代码看到未完成状态 |
| 直接写 `current_phase` | 绕过 `GameFlowTransitionCoordinator`，阶段转换冲突、重复推进 |
| 在 `context` 里存 `Callable`/节点/`PlayerState` | 存档、回放、网络序列化全部失效 |
| 技能自建续接队列 | 绕过白名单与熔断保护，可能无限递归 |
| 把异步选择后的恢复写成"重新发一遍时机" | 已完成时机被重复派发，技能多次结算 |
| 用「跳过三阶段 + 补三个额外出牌阶段」实现四阶段转出牌 | 派发了不该有的跳过时机；应调用 `convert_current_turn_main_phases_to_play()` |
| 把「本轮结束」的到期效果挂到下一轮 `roundStart` | 语义从“本轮”漂移到“下一轮”，额外回合与读档恢复都会算错；应订阅 `roundEnd` |
| `round_end_restore` 与 `round_end_after_restore` 混用 | 前者跳过 `roundEnd` 会让轮末时机整轮丢失，后者重复派发会让到期效果结算两次 |
| 在 `roundEnd` 处理者里假设“轮数已经递增” | `round_number` 此时仍是刚结束的那一轮，判定下一轮请用 `round_number + 1` |
| 从既有调用点反推 `_emit_rule_timing(...)` 的参数顺序 | 签名是 `(event_name, player_id, source_id, target_id, event_data, parent_id)`；参考调用点若参数取值相同（如 `1, 0, 1`）会掩盖顺序错误，技能按 `role = "target"` 订阅时表现为**回调静默不执行**，看起来像技能逻辑没生效 |
| 屏障早退前不排空「子阶段自己登记的延后条目」，只依赖末尾的「有待办就重新唤醒」兜底 | 唤醒每次都会再次撞上同一屏障，条目永远排在屏障之后：**零进展活锁**，表现为「什么都没发生」，且看门狗反复进入同一屏障无法自愈 |
| 延后条目不带「登记时所归属的阶段实例号」，改用一个布尔「是否在额外阶段内」 | 无法区分「本子阶段的条目」与「父序列遗留的条目」，排空时会越过外层时机、打乱触发顺序 |
| 把排空熔断记在 `get_stall_diagnostics()` 这类被轮询的诊断路径上 | 故障计数参与停滞指纹，指纹每轮都变 → 看门狗停滞计时器被不断刷新 → 强制修复永不触发，并产生日志刷屏 |
| 为独立额外出牌阶段另开一条专用推进/专用结算队列 | 与统一结算管线形成两套顺序，屏障语义被绕过，时机错序且无法被熔断保护 |
